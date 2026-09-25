import prisma from '../utils/prisma';
import { CpError } from './cpUnlock.service';

/**
 * هدايا CP ← مستوى CP (2026-09-24), and who is shown as "مستخدم CP الظاهر".
 *
 * Kept apart from cp.service (which pulls in the gift/socket stack) so every
 * rule here takes the Prisma client as a parameter and is unit-tested.
 *
 * Level rules:
 *   • Only an ACTIVE gift in the `cp` list raises a pair's CP value — the
 *     accepting gift of an invitation, and any CP gift sent later to a partner.
 *   • Each gift carries its own "مقدار رفع مستوى CP" (`Gift.cpLevelPoints`,
 *     set from the dashboard); unset means the gift's coin price.
 *   • Every increase is written to `cp_value_events` with the value it
 *     produced. `giftTransactionId` is unique, so one gift can never be
 *     counted twice, and `(senderId, requestKey)` is unique, so a resent
 *     request is recognised BEFORE anything is charged.
 */

export const CP_GIFT_CATEGORY = 'cp';

export interface CpGiftLike {
  coinCost: number;
  cpLevelPoints?: number | null;
  category?: string | null;
  isActive?: boolean;
}

export const isCpGift = (g: CpGiftLike | null | undefined): boolean =>
  !!g && g.isActive !== false && String(g.category ?? '').toLowerCase() === CP_GIFT_CATEGORY;

/** Points one send adds: the gift's configured amount (or its price) × quantity. */
export function cpPointsFor(gift: CpGiftLike, quantity: number): number {
  const q = Math.max(1, Math.floor(Number(quantity) || 1));
  const per = gift.cpLevelPoints != null && Number.isFinite(Number(gift.cpLevelPoints))
    ? Math.max(0, Math.floor(Number(gift.cpLevelPoints)))
    : Math.max(0, Math.floor(Number(gift.coinCost) || 0));
  return per * q;
}

export interface CpGiftEventInput {
  pairId: number;
  senderId: number;
  recipientId: number;
  giftId: string;
  quantity: number;
  source: 'accept' | 'partner_gift';
  requestKey?: string | null;
}

const cleanKey = (k: unknown): string | null => {
  const s = String(k ?? '').trim();
  return s ? s.slice(0, 100) : null;
};

/**
 * Claims `requestKey` for this sender before any coins move. A resend of the
 * same request finds the claim: if it already completed, its stored result is
 * returned (`duplicate`) and nothing is charged; if it is still running, 409.
 * No key (an older app) → no claim; the gift is still counted only once.
 */
export async function reserveCpGiftEvent(input: CpGiftEventInput, db: any = prisma) {
  const requestKey = cleanKey(input.requestKey);
  if (!requestKey) return { event: null as any, duplicate: null as any };
  try {
    const event = await db.cpValueEvent.create({
      data: {
        pairId: input.pairId,
        senderId: input.senderId,
        recipientId: input.recipientId,
        giftId: input.giftId,
        quantity: input.quantity,
        points: 0,
        source: input.source,
        requestKey,
        giftTransactionId: null,
      },
    });
    return { event, duplicate: null as any };
  } catch (e: any) {
    if (e?.code !== 'P2002') throw e;
    const existing = await db.cpValueEvent.findFirst({ where: { senderId: input.senderId, requestKey } });
    if (existing?.giftTransactionId) return { event: null as any, duplicate: existing };
    throw new CpError('DUPLICATE_REQUEST', 'جاري تنفيذ نفس الطلب', 409);
  }
}

/** The send failed after the claim: release it so a real retry can go through. */
export async function releaseCpGiftEvent(eventId: number | null | undefined, db: any = prisma) {
  if (!eventId) return;
  await db.cpValueEvent.deleteMany({ where: { id: eventId, giftTransactionId: null } });
}

/**
 * Adds a committed gift's points to the pair and logs the result — once per
 * gift transaction. Returns the pair's value after, and whether this call did
 * the counting (false = that transaction had already been counted).
 */
export async function recordCpGiftValue(
  input: CpGiftEventInput & { points: number; giftTransactionId: string; eventId?: number | null },
  db: any = prisma,
) {
  const giftTransactionId = String(input.giftTransactionId);
  return db.$transaction(async (tx: any) => {
    const already = await tx.cpValueEvent.findFirst({ where: { giftTransactionId } });
    if (already) {
      const pair = await tx.cpPair.findUnique({ where: { id: input.pairId } });
      return { counted: false, event: already, cpValue: Number(pair?.cpValue ?? 0) };
    }
    const pair = await tx.cpPair.update({
      where: { id: input.pairId },
      data: { cpValue: { increment: Math.max(0, Math.floor(input.points)) } },
    });
    const data = {
      pairId: input.pairId,
      senderId: input.senderId,
      recipientId: input.recipientId,
      giftId: input.giftId,
      quantity: input.quantity,
      points: Math.max(0, Math.floor(input.points)),
      source: input.source,
      giftTransactionId,
      cpValueAfter: Number(pair.cpValue),
    };
    const event = input.eventId
      ? await tx.cpValueEvent.update({ where: { id: input.eventId }, data })
      : await tx.cpValueEvent.create({ data: { ...data, requestKey: cleanKey(input.requestKey) } });
    return { counted: true, event, cpValue: Number(pair.cpValue) };
  });
}

// ---------------------------------------------------------------------------
// "مستخدم CP الظاهر" — never replaced by whoever was paired last
// ---------------------------------------------------------------------------

/**
 * On a new pair: a user who has no choice yet gets this partner. Someone who
 * already shows a partner keeps him — a later pair never takes the spot.
 */
export async function pinFeaturedIfUnset(userAId: number, userBId: number, db: any = prisma) {
  await db.user.updateMany({ where: { id: userAId, cpFeaturedPartnerId: null }, data: { cpFeaturedPartnerId: userBId } });
  await db.user.updateMany({ where: { id: userBId, cpFeaturedPartnerId: null }, data: { cpFeaturedPartnerId: userAId } });
}

/**
 * After a pair is dissolved: whoever was showing the other now shows his
 * newest remaining partner (or nobody), so the page never points at someone
 * he is no longer paired with and the next new pair cannot silently take over.
 */
export async function reassignFeaturedAfterRemoval(userAId: number, userBId: number, db: any = prisma) {
  for (const [me, gone] of [[userAId, userBId], [userBId, userAId]] as const) {
    const u = await db.user.findUnique({ where: { id: me }, select: { cpFeaturedPartnerId: true } });
    if (!u || u.cpFeaturedPartnerId !== gone) continue;
    const next = await db.cpPair.findFirst({
      where: { OR: [{ userAId: me }, { userBId: me }] },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    });
    const partner = next ? (next.userAId === me ? next.userBId : next.userAId) : null;
    await db.user.update({ where: { id: me }, data: { cpFeaturedPartnerId: partner } });
  }
}
