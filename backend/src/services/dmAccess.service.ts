import prisma from '../utils/prisma';

// ============================================================
// قفل الرسائل الخاصة — DM ACCESS
// ============================================================
// The client's rule: "المستخدم يسيبها عامة أو يقفل الرسايل للأصدقاء فقط أو
// يفعل لها عدد كوينز معين للرسالة لكن الكوينزات دي هتروح للبرنامج وليس
// للمستخدم اللي قافل الرسايل".
//
// One function decides, and both send paths (HTTP /messages/send and the
// socket's send_dm) ask it. The order matters:
//
//   1. a block either way ends it (handled by the callers, blockGuard);
//   2. the receiver's own messages in the thread open it — someone who has
//      already replied to you cannot then be "locked" against you;
//   3. public → allowed;
//   4. mutual ACCEPTED follows ("أصدقاء") → allowed under friends AND paid;
//   5. paid → allowed once the thread was unlocked with the fee, else the
//      caller gets the price to show.
//
// The fee is charged ONCE per conversation (not per message): a paid message
// that then gets a reply becomes a normal thread by rule 2 anyway, and a
// per-message meter is how you get "الرسالة اتخصمت ومحدش رد".

export const DM_PRIVACY_VALUES = ['public', 'friends', 'paid'] as const;
export type DmPrivacy = (typeof DM_PRIVACY_VALUES)[number];

/** Price presets the app offers; any value inside the range is accepted. */
export const DM_PRICE_MIN = 1;
export const DM_PRICE_MAX = 100_000;

export interface DmAccess {
  allowed: boolean;
  /** Why it is allowed, or which gate stands in the way. */
  reason: 'public' | 'friends' | 'engaged' | 'unlocked' | 'admin' | 'self' | 'friends_only' | 'fee_required';
  code?: 'DM_FRIENDS_ONLY' | 'DM_FEE_REQUIRED';
  message?: string;
  partnerPrivacy: DmPrivacy;
  priceCoins: number;
  conversationId: number | null;
}

async function areFriends(a: number, b: number): Promise<boolean> {
  const [ab, ba] = await Promise.all([
    prisma.follow.findFirst({ where: { followerId: a, followingId: b, status: 'ACCEPTED' }, select: { id: true } }),
    prisma.follow.findFirst({ where: { followerId: b, followingId: a, status: 'ACCEPTED' }, select: { id: true } }),
  ]);
  return !!ab && !!ba;
}

/** Can `senderId` message `receiverId` right now? */
export async function checkDmAccess(senderId: number, receiverId: number): Promise<DmAccess> {
  const base = { partnerPrivacy: 'public' as DmPrivacy, priceCoins: 0, conversationId: null as number | null };
  if (senderId === receiverId) return { allowed: true, reason: 'self', ...base };

  const [sender, receiver, conv] = await Promise.all([
    prisma.user.findUnique({ where: { id: senderId }, select: { isAdmin: true, isSuperAdmin: true } }),
    prisma.user.findUnique({ where: { id: receiverId }, select: { dmPrivacy: true, dmPriceCoins: true } }),
    prisma.conversation.findUnique({
      where: { userAId_userBId: { userAId: Math.min(senderId, receiverId), userBId: Math.max(senderId, receiverId) } },
      select: { id: true, unlockedByUserId: true },
    }),
  ]);
  if (!receiver) return { allowed: false, reason: 'friends_only', code: 'DM_FRIENDS_ONLY', message: 'المستخدم غير موجود', ...base };

  const privacy = (DM_PRIVACY_VALUES as readonly string[]).includes(receiver.dmPrivacy)
    ? (receiver.dmPrivacy as DmPrivacy)
    : 'public';
  const price = privacy === 'paid' ? Math.max(0, receiver.dmPriceCoins) : 0;
  const ctx = { partnerPrivacy: privacy, priceCoins: price, conversationId: conv?.id ?? null };

  if (privacy === 'public' || (privacy === 'paid' && price <= 0)) return { allowed: true, reason: 'public', ...ctx };
  if (sender?.isAdmin || sender?.isSuperAdmin) return { allowed: true, reason: 'admin', ...ctx };

  // The receiver already wrote in this thread → it is open, whatever the lock.
  if (conv) {
    const replied = await prisma.directMessage.findFirst({
      where: { conversationId: conv.id, senderId: receiverId },
      select: { id: true },
    });
    if (replied) return { allowed: true, reason: 'engaged', ...ctx };
  }

  if (await areFriends(senderId, receiverId)) return { allowed: true, reason: 'friends', ...ctx };

  if (privacy === 'friends') {
    return {
      allowed: false,
      reason: 'friends_only',
      code: 'DM_FRIENDS_ONLY',
      message: 'هذا المستخدم يستقبل الرسائل من الأصدقاء فقط — تابعوا بعض الأول',
      ...ctx,
    };
  }

  // paid
  if (conv?.unlockedByUserId != null) return { allowed: true, reason: 'unlocked', ...ctx };
  return {
    allowed: false,
    reason: 'fee_required',
    code: 'DM_FEE_REQUIRED',
    message: `فتح المحادثة مع هذا المستخدم يكلف ${price} كوينز`,
    ...ctx,
  };
}

export class DmUnlockError extends Error {
  constructor(public code: 'NOT_LOCKED' | 'INSUFFICIENT_COINS' | 'NOT_PARTICIPANT', message: string, public status = 400) {
    super(message);
  }
}

/**
 * Pay the receiver's fee for one conversation. The coins leave the payer and
 * go nowhere — a DM_FEE transaction is the platform's record of them. Charged
 * once: a second call on an unlocked thread is a no-op.
 */
export async function unlockConversationWithFee(payerId: number, conversationId: number) {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    select: { id: true, userAId: true, userBId: true, unlockedByUserId: true },
  });
  if (!conv || (conv.userAId !== payerId && conv.userBId !== payerId)) {
    throw new DmUnlockError('NOT_PARTICIPANT', 'Not a participant', 403);
  }
  const receiverId = conv.userAId === payerId ? conv.userBId : conv.userAId;
  if (conv.unlockedByUserId != null) {
    const u = await prisma.user.findUnique({ where: { id: payerId }, select: { coinsBalance: true } });
    return { charged: 0, balance: u?.coinsBalance ?? 0, alreadyUnlocked: true };
  }

  const access = await checkDmAccess(payerId, receiverId);
  if (access.allowed) {
    // Nothing to pay (friends, engaged, public…): mark it open so the app
    // stops asking, charge nothing.
    await prisma.conversation.update({ where: { id: conv.id }, data: { unlockedByUserId: payerId, unlockedAt: new Date() } });
    const u = await prisma.user.findUnique({ where: { id: payerId }, select: { coinsBalance: true } });
    return { charged: 0, balance: u?.coinsBalance ?? 0, alreadyUnlocked: true };
  }
  if (access.code !== 'DM_FEE_REQUIRED') {
    throw new DmUnlockError('NOT_LOCKED', access.message ?? 'locked', 403);
  }
  const price = access.priceCoins;

  return prisma.$transaction(async (tx) => {
    const debited = await tx.user.updateMany({
      where: { id: payerId, coinsBalance: { gte: price } },
      data: { coinsBalance: { decrement: price } },
    });
    if (debited.count !== 1) {
      throw new DmUnlockError('INSUFFICIENT_COINS', `رصيدك لا يكفي — فتح المحادثة يكلف ${price} كوينز`, 402);
    }
    await tx.transaction.create({
      data: {
        userId: payerId,
        type: 'DM_FEE',
        amountCoins: price,
        status: 'completed',
        externalId: `conversation:${conv.id}`,
        senderId: receiverId, // whose lock was paid for — the coins did NOT go to them
      },
    });
    await tx.conversation.update({
      where: { id: conv.id },
      data: { unlockedByUserId: payerId, unlockedAt: new Date() },
    });
    const u = await tx.user.findUnique({ where: { id: payerId }, select: { coinsBalance: true } });
    return { charged: price, balance: u?.coinsBalance ?? 0, alreadyUnlocked: false };
  });
}
