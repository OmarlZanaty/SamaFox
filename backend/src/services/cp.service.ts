import prisma from '../utils/prisma';
import { createNotification } from './notification.service';
import { sendGiftAtomic } from '../gifts/giftService';

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

export class CpError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}

/** Rejection fee, as a fraction of the gift's full price. Client-specified. */
export const CP_REJECT_FEE_RATE = Number(process.env.CP_REJECT_FEE_RATE ?? 0.3);

/** A pair is stored once, with the lower id first, so (a,b) == (b,a). */
const orderPair = (x: number, y: number): [number, number] => (x < y ? [x, y] : [y, x]);

const MAX_QUANTITY = 99;

export interface CreateCpRequestInput {
  senderId: number;
  recipientId: number;
  giftId: string;
  quantity?: number;
  roomId?: number | null;
}

/** Sends the CP invitation. Charges nothing yet — see the note above. */
export async function createCpRequest(input: CreateCpRequestInput) {
  const quantity = Math.max(1, Math.min(MAX_QUANTITY, Math.floor(input.quantity ?? 1)));
  if (input.senderId === input.recipientId) {
    throw new CpError('SELF_CP', 'لا يمكنك إرسال هدية CP لنفسك');
  }

  const [gift, recipient] = await Promise.all([
    prisma.gift.findUnique({ where: { id: input.giftId } }),
    prisma.user.findUnique({ where: { id: input.recipientId }, select: { id: true, name: true } }),
  ]);
  if (!gift || !gift.isActive) throw new CpError('INVALID_GIFT', 'الهدية غير متاحة', 404);
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
  if (already) throw new CpError('ALREADY_PAIRED', 'لديكما ارتباط CP بالفعل');

  // One live invitation per direction; re-sending just returns the open one so
  // a double-tap cannot queue two charges against the same person.
  const open = await prisma.cpRequest.findFirst({
    where: { senderId: input.senderId, recipientId: input.recipientId, status: 'pending' },
  });
  if (open) return open;

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

  return request;
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
export async function acceptCpRequest(requestId: number, recipientId: number) {
  const request = await loadPending(requestId, recipientId);

  const giftResult = await sendGiftAtomic({
    senderId: request.senderId,
    recipientId: request.recipientId,
    roomId: request.roomId,
    giftId: request.giftId,
    quantity: request.quantity,
  });

  const [aId, bId] = orderPair(request.senderId, request.recipientId);
  const pair = await prisma.cpPair.upsert({
    where: { userAId_userBId: { userAId: aId, userBId: bId } },
    update: { giftId: request.giftId },
    create: { userAId: aId, userBId: bId, giftId: request.giftId },
  });

  await prisma.cpRequest.update({
    where: { id: request.id },
    data: { status: 'accepted', resolvedAt: new Date() },
  });

  const recipient = await prisma.user.findUnique({
    where: { id: request.recipientId },
    select: { name: true },
  });
  await createNotification({
    userId: request.senderId,
    actorId: request.recipientId,
    type: 'cp_accepted',
    title: 'تم قبول الـ CP 💞',
    body: `${recipient?.name ?? 'المستخدم'} قبل هدية الـ CP — أصبحتما مرتبطين`,
    data: { cpRequestId: request.id, pairId: pair.id, partnerId: request.recipientId },
  }).catch((e) => console.warn('[cp] accept notification failed:', e));

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
    await tx.cpRequest.update({
      where: { id: request.id },
      data: { status: 'rejected', resolvedAt: new Date() },
    });
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
  return prisma.cpRequest.update({
    where: { id: request.id },
    data: { status: 'cancelled', resolvedAt: new Date() },
  });
}

/**
 * #20 — the home-page CP box: "يظهر له كل الاشخاص اللي عامل معاهم CP".
 * Returns the partner on the other side of each pair, whichever column he is in.
 */
export async function listCpPartners(userId: number) {
  const pairs = await prisma.cpPair.findMany({
    where: { OR: [{ userAId: userId }, { userBId: userId }] },
    orderBy: { createdAt: 'desc' },
    include: {
      userA: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true, level: true } },
      userB: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true, level: true } },
    },
  });

  const giftIds = [...new Set(pairs.map((p) => p.giftId).filter((g): g is string => !!g))];
  const gifts = giftIds.length
    ? await prisma.gift.findMany({
        where: { id: { in: giftIds } },
        select: { id: true, name: true, nameAr: true, iconUrl: true },
      })
    : [];
  const giftById = new Map(gifts.map((g) => [g.id, g]));

  return pairs.map((p) => ({
    pairId: p.id,
    partner: p.userAId === userId ? p.userB : p.userA,
    gift: p.giftId ? giftById.get(p.giftId) ?? null : null,
    createdAt: p.createdAt,
  }));
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
