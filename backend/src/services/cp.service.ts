import crypto from 'crypto';
import { isValidGiftQuantity } from '../gifts/giftLimits';
import { runGiftOperation, giftOperationId, type GiftTransactionContext } from '../gifts/giftOperation';
import prisma from '../utils/prisma';
import { createNotification } from './notification.service';
import { sendGiftAtomic } from '../gifts/giftService';
import { flushGiftDeliveries, emitGiftAnnouncement } from '../gifts/controller';
import { CpError, assertCpUnlocked, computeCpLevel, readCpSettings } from './cpUnlock.service';
import {
  cpPointsFor,
  isCpGift,
  pinFeaturedIfUnset,
  reassignFeaturedAfterRemoval,
  recordCpGiftValue,
  releaseCpGiftEvent,
  reserveCpGiftEvent, canActivateCp } from './cpGift.service';

// CpError moved to cpUnlock.service so the unlock layer can raise the same
// shape; re-exported so every existing import of it keeps working.
export { CpError };

/**
 * A15 / #44 — نظام الـ CP.
 *
 * The client's spec, verbatim in outline:
 *   "الشخص ده بيبعت هديه CP لشخص تاني، الشخص التاني بيجيله اشعار إن فلان
 *    بعتلك هدية CP: قبول / رفض. لو رفض الهديه متتمش ويتخصم منه 30% من قيمة
 *    الهديه. لو قبل يتخصم منه سعر الهديه كامل وتتحول قيمتها لتارجت عنده."
 *
 * Two deliberate design points:
 *
 *  1. NOTHING is charged when the request is created. The 30%/100% split only
 *     exists if the money moves at resolution time, so the sender's balance is
 *     merely *verified* up front and charged when the recipient answers.
 *
 *  2. Acceptance runs the ordinary `sendGiftAtomic`, it does not reimplement
 *     crediting. That is what makes "قيمتها تتحول لتارجت عنده" true without a
 *     second set of rules: a hosting/charging-agency member already receives
 *     0 wallet coins and the full value as target on every normal gift.
 */

/** Rejection fee, as a fraction of the gift's full price. Client-specified. */
export const CP_REJECT_FEE_RATE = Number(process.env.CP_REJECT_FEE_RATE ?? 0.3);

/** A pair is stored once, with the lower id first, so (a,b) == (b,a). */
const orderPair = (x: number, y: number): [number, number] => (x < y ? [x, y] : [y, x]);

export interface CreateCpRequestInput {
  senderId: number;
  recipientId: number;
  giftId: string;
  quantity?: number;
  roomId?: number | null;
  /** One per tap in the app; a resend with the same key is not charged again. */
  requestKey?: string | null;
}

/**
 * Sends the CP invitation. Charges nothing yet — see the note above.
 *
 * هدايا CP (2026-09-24): if the two are ALREADY partners there is nothing to
 * accept — the CP gift is sent right away and raises their CP level by the
 * gift's configured amount ([sendCpGiftToPartner]). The response says which
 * of the two happened (`kind`).
 */
export async function createCpRequest(input: CreateCpRequestInput) {
  const quantity = input.quantity ?? 1;
  if (!isValidGiftQuantity(quantity)) {
    throw new CpError('INVALID_QUANTITY', 'الكمية غير صالحة');
  }
  if (input.senderId === input.recipientId) {
    throw new CpError('SELF_CP', 'لا يمكنك إرسال هدية CP لنفسك');
  }

  // صلاحيات فتح CP — the server-side gate. A locked account gets 403
  // CP_LOCKED with the quoted fee, whatever the app claims.
  await assertCpUnlocked(input.senderId);

  const [gift, recipient] = await Promise.all([
    prisma.gift.findUnique({ where: { id: input.giftId } }),
    prisma.user.findUnique({ where: { id: input.recipientId }, select: { id: true, name: true } }),
  ]);
  if (!gift || !gift.isActive) throw new CpError('INVALID_GIFT', 'الهدية غير متاحة', 404);
  // Only the gifts enabled in the dashboard's CP list make or raise a CP.
  if (!isCpGift(gift)) throw new CpError('NOT_CP_GIFT', 'هذه الهدية ليست من هدايا CP');
  if (!recipient) throw new CpError('INVALID_RECIPIENT', 'المستخدم غير موجود', 404);

  const totalCoins = gift.coinCost * quantity;
  if (totalCoins <= 0 || !Number.isSafeInteger(totalCoins)) {
    throw new CpError('INVALID_AMOUNT', 'قيمة الهدية غير صالحة');
  }

  const sender = await prisma.user.findUnique({
    where: { id: input.senderId },
    select: { id: true, name: true, coinsBalance: true },
  });
  if (!sender) throw new CpError('UNAUTHORIZED', 'غير مصرح', 401);
  // Verified now so a request can never be created that the sender could not
  // pay for; the actual debit happens on accept/reject.
  if (sender.coinsBalance < totalCoins) {
    throw new CpError('INSUFFICIENT_COINS', 'رصيدك لا يكفي لهذه الهدية', 402);
  }

  const [aId, bId] = orderPair(input.senderId, input.recipientId);
  const already = await prisma.cpPair.findUnique({
    where: { userAId_userBId: { userAId: aId, userBId: bId } },
  });
  if (already) {
    return sendCpGiftToPartner(input, already.id, gift, quantity);
  }

  // SPEC52 #34 — only a gift marked "تفعيل CP" may create a relationship.
  // Refused before anything is reserved or charged.
  if (!canActivateCp(gift as any)) {
    throw new CpError('CP_LEVEL_ONLY', 'هذه الهدية ترفع مستوى CP فقط ولا تُنشئ علاقة — اختر هدية تفعيل مثل الخاتم');
  }

  // One live invitation per direction; re-sending just returns the open one so
  // a double-tap cannot queue two charges against the same person.
  const open = await prisma.cpRequest.findFirst({
    where: { senderId: input.senderId, recipientId: input.recipientId, status: 'pending' },
  });
  if (open) return { ...open, kind: 'invitation' as const };

  const request = await prisma.cpRequest.create({
    data: {
      senderId: input.senderId,
      recipientId: input.recipientId,
      giftId: gift.id,
      quantity,
      totalCoins,
      roomId: input.roomId ?? null,
    },
  });

  await createNotification({
    userId: input.recipientId,
    actorId: input.senderId,
    type: 'cp_request',
    title: 'هدية CP 💞',
    body: `${sender.name} أرسل لك هدية ${gift.nameAr ?? gift.name} — قبول أم رفض؟`,
    data: {
      cpRequestId: request.id,
      giftId: gift.id,
      giftName: gift.nameAr ?? gift.name,
      giftIconUrl: gift.iconUrl,
      quantity,
      totalCoins,
      senderId: input.senderId,
      senderName: sender.name,
    },
  }).catch((e) => console.warn('[cp] request notification failed:', e));

  return { ...request, kind: 'invitation' as const };
}

/** The level a pair shows for a given value, under the current settings. */
async function levelOf(pairId: number, db: any = prisma) {
  const [pair, settings] = await Promise.all([db.cpPair.findUnique({ where: { id: pairId } }), readCpSettings(db)]);
  if (!pair) return null;
  return computeCpLevel({ cpValue: pair.cpValue, createdAt: pair.createdAt, levelOverride: pair.levelOverride }, settings);
}

/**
 * هدايا CP — a CP gift from one partner to the other. Charged in full right
 * away (same crediting as any gift), then the pair's CP value rises by the
 * gift's "مقدار رفع مستوى CP" × quantity, logged in cp_value_events. A resend
 * with the same `requestKey` returns the first result and charges nothing.
 */
async function sendCpGiftToPartner(
  input: CreateCpRequestInput,
  pairId: number,
  gift: { id: string; coinCost: number; cpLevelPoints?: number | null; name: string; nameAr: string | null },
  quantity: number,
  context?: GiftTransactionContext,
): Promise<any> {
  if (!context) {
    const operation = { senderId: input.senderId, id: giftOperationId(input.senderId, `cp:${input.requestKey ?? crypto.randomUUID()}`), requestHash: JSON.stringify({ ...input, quantity }) };
    return (await runGiftOperation(operation, ctx => sendCpGiftToPartner(input, pairId, gift, quantity, ctx))).body;
  }
  const db = context.tx;
  const currentGift = await db.gift.findUnique({ where: { id: gift.id } });
  if (!isCpGift(currentGift)) throw new CpError('INVALID_GIFT', 'الهدية غير مناسبة لـ CP');
  gift = currentGift;
  const eventInput = {
    pairId,
    senderId: input.senderId,
    recipientId: input.recipientId,
    giftId: gift.id,
    quantity,
    source: 'partner_gift' as const,
    requestKey: input.requestKey ?? null,
  };
  const before = await levelOf(pairId, db);
  if (!before) throw new CpError('NOT_FOUND', 'ارتباط CP غير موجود', 404);
  const points = cpPointsFor(gift, quantity);
  const giftResult = await sendGiftAtomic({
    senderId: input.senderId, recipientId: input.recipientId, roomId: input.roomId ?? null,
    giftId: gift.id, quantity, cpXp: points,
    clientRequestId: input.requestKey ? giftOperationId(input.senderId, `cp:${input.requestKey}`) : null,
  }, context);
  const recorded = await recordCpGiftValue({ ...eventInput, points, giftTransactionId: giftResult.transactionId }, db);
  const after = await levelOf(pairId, db);

  const [sender, recipient] = await Promise.all([
    db.user.findUnique({ where: { id: input.senderId }, select: { id: true, name: true, avatarUrl: true } }),
    db.user.findUnique({ where: { id: input.recipientId }, select: { id: true, name: true, avatarUrl: true } }),
  ]);
  const leveledUp = !!before && !!after && after.level > before.level;
  context.afterCommit.push(async () => {
  emitCpGift(
    { senderId: input.senderId, recipientId: input.recipientId, roomId: input.roomId ?? null, quantity },
    giftResult,
    sender,
    recipient,
  );
  await createNotification({
    userId: input.recipientId,
    actorId: input.senderId,
    type: 'cp_gift',
    title: leveledUp ? `ارتفع مستوى الـ CP إلى LV.${after!.level} 💞` : 'هدية CP 💞',
    body: `${sender?.name ?? 'شريكك'} أرسل لك ${gift.nameAr ?? gift.name} — +${points} CP`,
    data: { pairId, giftId: gift.id, points, cpValue: recorded.cpValue, level: after?.level ?? null },
  }).catch((e) => console.warn('[cp] partner gift notification failed:', e));

  });
  return {
    kind: 'partner_gift' as const,
    duplicate: false,
    pairId,
    pointsAdded: recorded.counted ? points : 0,
    cpValue: recorded.cpValue,
    level: after?.level ?? null,
    levelName: after?.levelName ?? null,
    previousLevel: before?.level ?? null,
    leveledUp,
    balance: giftResult.senderBalance,
    transactionId: giftResult.transactionId,
  };
}

/**
 * The gift animation / announcement for a CP gift. `sendGiftAtomic` records
 * the transaction but emits nothing — the socket events live in the HTTP send
 * controller, which the CP flows never go through. Same payload shape as an
 * ordinary send so the overlay, activity feed and announcement bar need no
 * special case.
 */
function emitCpGift(
  req: { senderId: number; recipientId: number; roomId: number | null; quantity: number },
  giftResult: Awaited<ReturnType<typeof sendGiftAtomic>>,
  sender: { id: number; name: string | null; avatarUrl: string | null } | null,
  recipient: { id: number; name: string | null; avatarUrl: string | null } | null,
) {
  void flushGiftDeliveries();
  emitGiftAnnouncement({
    senderId: req.senderId,
    senderName: sender?.name ?? null,
    senderAvatarUrl: sender?.avatarUrl ?? null,
    gift: {
      id: giftResult.gift.id,
      name: giftResult.gift.name,
      nameAr: giftResult.gift.nameAr,
      iconUrl: giftResult.gift.iconUrl,
    },
    quantity: req.quantity,
    recipientCount: 1,
    recipientName: recipient?.name ?? null,
    roomId: req.roomId,
    totalCoins: giftResult.totalCoins,
    ts: Date.now(),
  });
}

/** Loads a pending request and asserts `userId` is the one being asked. */
async function loadPending(requestId: number, recipientId: number) {
  const request = await prisma.cpRequest.findUnique({ where: { id: requestId } });
  if (!request) throw new CpError('NOT_FOUND', 'الطلب غير موجود', 404);
  if (request.recipientId !== recipientId) throw new CpError('FORBIDDEN', 'غير مصرح', 403);
  if (request.status !== 'pending') throw new CpError('ALREADY_RESOLVED', 'تم الرد على هذا الطلب بالفعل');
  return request;
}

/**
 * Accept: the gift is sent for real (full price off the sender, value into the
 * recipient's target through the normal crediting rules) and the pair is made.
 */
export async function acceptCpRequest(requestId: number, recipientId: number, context?: GiftTransactionContext): Promise<any> {
  if (!context) {
    return (await runGiftOperation({ senderId: recipientId, id: giftOperationId(recipientId, `cp-accept:${requestId}`), requestHash: `cp-accept:${requestId}:${recipientId}` },
      ctx => acceptCpRequest(requestId, recipientId, ctx))).body;
  }
  const db = context.tx;
  const request = await db.cpRequest.findUnique({ where: { id: requestId } });
  if (!request || request.recipientId !== recipientId) throw new CpError('FORBIDDEN', 'غير مصرح', 403);
  if (request.status !== 'pending') throw new CpError('ALREADY_RESOLVED', 'تم الرد على هذا الطلب بالفعل');
  const gift = await db.gift.findUnique({ where: { id: request.giftId } });
  if (!isCpGift(gift) || !canActivateCp(gift)) throw new CpError('INVALID_GIFT', 'هدية التفعيل غير صالحة');

  // Claim the invitation BEFORE any coins move: of two taps (or an accept
  // racing a reject/cancel) exactly one gets here, so the gift can never be
  // charged or counted twice.
  const claimed = await db.cpRequest.updateMany({
    where: { id: request.id, status: 'pending' },
    data: { status: 'accepting' },
  });
  if (claimed.count === 0) throw new CpError('ALREADY_RESOLVED', 'تم الرد على هذا الطلب بالفعل');

  // One transaction with the claim above: if the gift fails (e.g. the sender
  // can no longer afford it) the whole accept rolls back and the invitation is
  // still pending — nothing to undo by hand.
  const giftResult = await sendGiftAtomic({
    senderId: request.senderId,
    recipientId: request.recipientId,
    roomId: request.roomId,
    giftId: request.giftId,
    quantity: request.quantity,
    clientRequestId: giftOperationId(request.senderId, `cp-accept-gift:${request.id}`),
    cpActivate: true, cpXp: cpPointsFor(gift, request.quantity),
  }, context);

  const [aId, bId] = orderPair(request.senderId, request.recipientId);
  // A re-pair between the same two people keeps what they already built up.
  const pair = await db.cpPair.upsert({
    where: { userAId_userBId: { userAId: aId, userBId: bId } },
    update: { giftId: request.giftId },
    create: { userAId: aId, userBId: bId, giftId: request.giftId, cpValue: 0 },
  });

  // The accepting gift is the pair's first CP value — by the gift's configured
  // "مقدار رفع مستوى CP", logged once per gift transaction.
  await recordCpGiftValue({
    pairId: pair.id,
    senderId: request.senderId,
    recipientId: request.recipientId,
    giftId: request.giftId,
    quantity: request.quantity,
    source: 'accept',
    points: gift ? cpPointsFor(gift, request.quantity) : giftResult.totalCoins,
    giftTransactionId: giftResult.transactionId,
  }, db);

  // "مستخدم CP الظاهر": only someone with no choice yet gets this partner.
  await pinFeaturedIfUnset(request.senderId, request.recipientId, db);

  await db.cpRequest.update({
    where: { id: request.id },
    data: { status: 'accepted', resolvedAt: new Date() },
  });

  const [sender, recipient] = await Promise.all([
    db.user.findUnique({
      where: { id: request.senderId },
      select: { id: true, name: true, avatarUrl: true },
    }),
    db.user.findUnique({
      where: { id: request.recipientId },
      select: { id: true, name: true, avatarUrl: true },
    }),
  ]);

  context.afterCommit.push(async () => {
  // The gift only actually moves NOW, so this is where the animation belongs.
  emitCpGift(
    { senderId: request.senderId, recipientId: request.recipientId, roomId: request.roomId, quantity: request.quantity },
    giftResult,
    sender,
    recipient,
  );

  // SPEC52 #10 — the minimal activation display in the room: the two
  // pictures, a handshake and the CP level. Nothing else.
  try {
    const { readCpSettings, computeCpLevel } = await import('./cpUnlock.service');
    const fresh = await prisma.cpPair.findUnique({ where: { id: pair.id } });
    const lv = fresh ? computeCpLevel(fresh as any, await readCpSettings()) : null;
    const { emitToRoomAndUsers } = await import('./socket.service');
    emitToRoomAndUsers(request.roomId ?? null, [request.senderId, request.recipientId], 'cp_activated', {
      pairId: pair.id,
      roomId: request.roomId ?? null,
      userA: { id: sender?.id ?? request.senderId, name: sender?.name ?? null, avatarUrl: sender?.avatarUrl ?? null },
      userB: { id: recipient?.id ?? request.recipientId, name: recipient?.name ?? null, avatarUrl: recipient?.avatarUrl ?? null },
      level: lv?.level ?? 1,
      levelName: lv?.levelName ?? null,
      ts: Date.now(),
    });
  } catch (e) {
    console.warn('[cp] cp_activated emit failed:', (e as Error).message);
  }

  await createNotification({
    userId: request.senderId,
    actorId: request.recipientId,
    type: 'cp_accepted',
    title: 'تم قبول الـ CP 💞',
    body: `${recipient?.name ?? 'المستخدم'} قبل هدية الـ CP — أصبحتما مرتبطين`,
    data: { cpRequestId: request.id, pairId: pair.id, partnerId: request.recipientId },
  }).catch((e) => console.warn('[cp] accept notification failed:', e));

  });
  return { request, pair, gift: giftResult };
}

/**
 * Reject: the gift does not complete, but 30% of its price is still taken off
 * the sender — the client's explicit rule. Recorded as a Transaction so the
 * charge is explainable when someone asks where the coins went.
 */
export async function rejectCpRequest(requestId: number, recipientId: number) {
  const request = await loadPending(requestId, recipientId);
  const fee = Math.floor(request.totalCoins * CP_REJECT_FEE_RATE);

  const charged = await prisma.$transaction(async (tx) => {
    // Resolve it first, conditionally: a second tap (or a racing accept /
    // cancel) finds it no longer pending and the fee is never taken twice.
    const resolved = await tx.cpRequest.updateMany({
      where: { id: request.id, status: 'pending' },
      data: { status: 'rejected', resolvedAt: new Date() },
    });
    if (resolved.count === 0) throw new CpError('ALREADY_RESOLVED', 'تم الرد على هذا الطلب بالفعل');
    let taken = 0;
    if (fee > 0) {
      // Guarded decrement: if the sender has since spent the coins we take what
      // the rule allows and no more — never push a balance negative.
      const dec = await tx.user.updateMany({
        where: { id: request.senderId, coinsBalance: { gte: fee } },
        data: { coinsBalance: { decrement: fee } },
      });
      if (dec.count > 0) {
        taken = fee;
        await tx.transaction.create({
          data: {
            userId: request.senderId,
            type: 'CP_REJECT_FEE',
            amountCoins: -fee,
            status: 'completed',
          },
        });
      }
    }
    return taken;
  });

  const recipient = await prisma.user.findUnique({
    where: { id: request.recipientId },
    select: { name: true },
  });
  await createNotification({
    userId: request.senderId,
    actorId: request.recipientId,
    type: 'cp_rejected',
    title: 'تم رفض الـ CP',
    body: `${recipient?.name ?? 'المستخدم'} رفض هدية الـ CP${charged > 0 ? ` — تم خصم ${charged} كوينز` : ''}`,
    data: { cpRequestId: request.id, feeCoins: charged },
  }).catch((e) => console.warn('[cp] reject notification failed:', e));

  return { request, feeCoins: charged };
}

/** The sender withdrawing their own invitation. Costs nothing either way. */
export async function cancelCpRequest(requestId: number, senderId: number) {
  const request = await prisma.cpRequest.findUnique({ where: { id: requestId } });
  if (!request) throw new CpError('NOT_FOUND', 'الطلب غير موجود', 404);
  if (request.senderId !== senderId) throw new CpError('FORBIDDEN', 'غير مصرح', 403);
  if (request.status !== 'pending') throw new CpError('ALREADY_RESOLVED', 'تم الرد على هذا الطلب بالفعل');
  // Conditional, so a cancel can never overwrite an accept already in flight.
  const done = await prisma.cpRequest.updateMany({
    where: { id: request.id, status: 'pending' },
    data: { status: 'cancelled', resolvedAt: new Date() },
  });
  if (done.count === 0) throw new CpError('ALREADY_RESOLVED', 'تم الرد على هذا الطلب بالفعل');
  return { ...request, status: 'cancelled' };
}

/**
 * #20 — the home-page CP box: "يظهر له كل الاشخاص اللي عامل معاهم CP".
 * Returns the partner on the other side of each pair, whichever column he is in.
 */
export async function listCpPartners(userId: number) {
  const [pairs, owner, cpSettings] = await Promise.all([
    prisma.cpPair.findMany({
      where: { OR: [{ userAId: userId }, { userBId: userId }] },
      orderBy: { createdAt: 'desc' },
      include: {
        // gender colours the partner's ring on the couple card (blue/pink).
        userA: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true, level: true, gender: true } },
        userB: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true, level: true, gender: true } },
      },
    }),
    prisma.user.findUnique({ where: { id: userId }, select: { cpFeaturedPartnerId: true } }),
    readCpSettings(),
  ]);
  const featuredId = owner?.cpFeaturedPartnerId ?? null;

  const giftIds = [...new Set(pairs.map((p) => p.giftId).filter((g): g is string => !!g))];
  const gifts = giftIds.length
    ? await prisma.gift.findMany({
        where: { id: { in: giftIds } },
        // animationUrl/format so the profile card can PLAY the gift that made
        // the pair ("طبعاً الهديه تشكل بردو") instead of showing a still icon.
        select: {
          id: true,
          name: true,
          nameAr: true,
          iconUrl: true,
          animationUrl: true,
          format: true,
        },
      })
    : [];
  const giftById = new Map(gifts.map((g) => [g.id, g]));

  const rows = pairs.map((p) => {
    const partner = p.userAId === userId ? p.userB : p.userA;
    const lvl = computeCpLevel(
      { cpValue: p.cpValue, createdAt: p.createdAt, levelOverride: p.levelOverride },
      cpSettings,
    );
    return {
      pairId: p.id,
      partner,
      gift: p.giftId ? giftById.get(p.giftId) ?? null : null,
      createdAt: p.createdAt,
      // Server-side level (2026-09-22). The app used to derive LV from days on
      // the device; it now prefers these and only falls back when absent.
      level: lvl.level,
      levelName: lvl.levelName,
      cpValue: lvl.cpValue,
      days: lvl.days,
      nextLevelAt: lvl.nextLevelAt,
      levelBasis: lvl.basis,
      // «CP Level Management» artwork for this level (null when unset).
      levelBadgeUrl: lvl.badgeUrl ?? null,
      levelFrameUrl: lvl.frameUrl ?? null,
      levelEffectKey: lvl.effectKey ?? null,
      // "مستخدم CP الظاهر" — the OWNER's choice, so a visitor sees the same
      // pair the owner sees. Falls back to the newest pair when unset.
      featured: featuredId != null && partner.id === featuredId,
    };
  });
  if (rows.length && !rows.some((r) => r.featured)) rows[0]!.featured = true;
  // Featured first: every client that just takes the first row shows the
  // right pair without knowing about the flag.
  rows.sort((a, b) => Number(b.featured) - Number(a.featured));
  return rows;
}

/**
 * "لو انا معايا اكتر من سي بي مين يظهر معايا فوق — خليني احدده من القايمه".
 * Server-side now. `partnerId` null clears the choice (newest pair shows).
 * The partner must currently be paired with the user, so the app cannot pin
 * an arbitrary account on someone's profile.
 */
export async function setFeaturedPartner(userId: number, partnerId: number | null, db: any = prisma) {
  if (partnerId != null) {
    if (partnerId === userId) throw new CpError('SELF_CP', 'لا يمكن اختيار نفسك');
    const [aId, bId] = orderPair(userId, partnerId);
    const pair = await db.cpPair.findUnique({ where: { userAId_userBId: { userAId: aId, userBId: bId } } });
    if (!pair) throw new CpError('NOT_FOUND', 'لا يوجد ارتباط CP مع هذا المستخدم', 404);
  }
  await db.user.update({ where: { id: userId }, data: { cpFeaturedPartnerId: partnerId } });
  return { featuredPartnerId: partnerId };
}

/**
 * "الغاء CP مع فلان؟ نعم / لا" — nothing is refunded, the pairing simply ends
 * and "لا تظهر له مره اخري الا لو عمل CP تاني".
 */
export async function removeCpPair(userId: number, partnerId: number) {
  const [aId, bId] = orderPair(userId, partnerId);
  const pair = await prisma.cpPair.findUnique({
    where: { userAId_userBId: { userAId: aId, userBId: bId } },
  });
  if (!pair) throw new CpError('NOT_FOUND', 'لا يوجد ارتباط CP مع هذا المستخدم', 404);
  await prisma.cpPair.delete({ where: { id: pair.id } });
  // Whoever showed the other now shows his next partner (or nobody).
  await reassignFeaturedAfterRemoval(aId, bId);

  await createNotification({
    userId: partnerId,
    actorId: userId,
    type: 'cp_removed',
    title: 'تم إلغاء الـ CP',
    body: 'تم إلغاء ارتباط الـ CP',
    data: { partnerId: userId },
  }).catch(() => undefined);

  return { removed: true };
}

/** Invitations still waiting on this user, newest first. */
export async function listPendingCpRequests(userId: number) {
  const rows = await prisma.cpRequest.findMany({
    where: { recipientId: userId, status: 'pending' },
    orderBy: { createdAt: 'desc' },
    include: { sender: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
  });
  const giftIds = [...new Set(rows.map((r) => r.giftId))];
  const gifts = giftIds.length
    ? await prisma.gift.findMany({
        where: { id: { in: giftIds } },
        select: { id: true, name: true, nameAr: true, iconUrl: true },
      })
    : [];
  const giftById = new Map(gifts.map((g) => [g.id, g]));
  return rows.map((r) => ({
    id: r.id,
    sender: r.sender,
    gift: giftById.get(r.giftId) ?? null,
    quantity: r.quantity,
    totalCoins: r.totalCoins,
    rejectFeeCoins: Math.floor(r.totalCoins * CP_REJECT_FEE_RATE),
    roomId: r.roomId,
    createdAt: r.createdAt,
  }));
}

// ---------------------------------------------------------------------------
// SPEC52 #8 — CP Top 30 (shown at the top of every room: Top 3, expandable)
// ---------------------------------------------------------------------------
//
// Order: higher CP level first; same level → more coins sent in the pair's CP
// gifts; still tied → whoever reached that level first; then the older pair.
// All of it comes from the server (cp_pairs.cpValue / cpCoins /
// levelReachedAt), never from the phone.
let cpTopCache: { at: number; limit: number; rows: unknown[] } | null = null;

export async function listTopCpPairs(limit = 30) {
  const n = Math.max(1, Math.min(30, Math.floor(limit) || 30));
  if (cpTopCache && cpTopCache.limit >= n && Date.now() - cpTopCache.at < 30_000) {
    return cpTopCache.rows.slice(0, n);
  }
  const { readCpSettings, computeCpLevel } = await import('./cpUnlock.service');
  const { withNameStyle } = await import('./vipStyle.service');
  const cfg = await readCpSettings();
  const pairs = await (prisma as any).cpPair.findMany({
    orderBy: [{ cpValue: 'desc' }, { cpCoins: 'desc' }],
    take: 300,
    include: {
      userA: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true, vipExpiresAt: true, gender: true } },
      userB: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true, vipExpiresAt: true, gender: true } },
    },
  });
  const ranked = pairs
    .map((p: any) => {
      const lv = computeCpLevel(p, cfg);
      return {
        pairId: p.id,
        level: lv.level,
        levelName: lv.levelName,
        badgeUrl: lv.badgeUrl ?? null,
        cpXp: Number(p.cpValue ?? 0),
        cpCoins: Number(p.cpCoins ?? 0),
        levelReachedAt: (p.levelReachedAt ?? p.createdAt)?.toISOString?.() ?? null,
        createdAt: p.createdAt,
        userA: withNameStyle({ ...p.userA, vipExpiresAt: undefined, ...(p.userA?.vipExpiresAt ? { vipExpiresAt: p.userA.vipExpiresAt } : {}) }),
        userB: withNameStyle({ ...p.userB, vipExpiresAt: undefined, ...(p.userB?.vipExpiresAt ? { vipExpiresAt: p.userB.vipExpiresAt } : {}) }),
      };
    })
    .sort((a: any, b: any) =>
      b.level - a.level ||
      b.cpCoins - a.cpCoins ||
      new Date(a.levelReachedAt ?? 0).getTime() - new Date(b.levelReachedAt ?? 0).getTime() ||
      a.pairId - b.pairId,
    )
    .slice(0, 30)
    .map((r: any, i: number) => ({ rank: i + 1, ...r }));
  cpTopCache = { at: Date.now(), limit: 30, rows: ranked };
  return ranked.slice(0, n);
}
