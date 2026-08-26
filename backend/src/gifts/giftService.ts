import prisma from '../utils/prisma';
import type { GiftTier } from '@prisma/client';
import { createNotification } from '../services/notification.service';
import { getCpConfig } from '../controllers/settings.controller';
import { awardUserXP, notifyLevelUp } from '../services/xp.service';
import { checkAchievements } from '../controllers/achievement.controller';

export interface SendGiftInput {
  senderId: number;
  recipientId: number;
  roomId?: number | null;
  giftId: string;
  quantity?: number;
  comboKey?: string | null;
}

export interface SendGiftResult {
  transactionId: string;
  totalCoins: number;
  senderBalance: number;
  recipientCoinsDelta: number;
  comboCount: number;
  broadcast: boolean;
  gift: {
    id: string;
    name: string;
    nameAr: string | null;
    iconUrl: string;
    tier: GiftTier;
    format: string;
    animationMs: number;
    animationHtml: string | null;
    animationUrl: string | null;
    videoHasAlpha: boolean;
    fireworksEnabled: boolean;
    fireworksColors: unknown;
    coinCost: number;
    broadcastGlobal: boolean;
  };
}

export class GiftSendError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}

const MAX_QUANTITY = 99;
const BROADCAST_TTL_MS = 30 * 1000;

/**
 * Atomic gift send. Uses Serializable isolation on PostgreSQL.
 * - Race-safe sender decrement (updateMany guard).
 * - Recipient increment.
 * - Creates GiftTransaction.
 * - Creates GiftBroadcast for legendary / broadcastGlobal gifts.
 *
 * Returns the full gift object so the socket layer can emit a payload
 * the client can render without an extra lookup.
 */
export async function sendGiftAtomic(input: SendGiftInput): Promise<SendGiftResult> {
  const quantity = Math.max(1, Math.min(MAX_QUANTITY, Math.floor(input.quantity ?? 1)));
  // Self-gift is allowed (used for displaying animation to oneself / testing in empty rooms).

  const gift = await prisma.gift.findUnique({ where: { id: input.giftId } });
  if (!gift || !gift.isActive) throw new GiftSendError('INVALID_GIFT', 'Gift not found or inactive', 404);

  // CP accrual rate (admin-configurable; professional default = 1 CP per coin).
  const { cpPerCoin } = await getCpConfig();

  const totalCoins = gift.coinCost * quantity;
  if (totalCoins <= 0 || !Number.isSafeInteger(totalCoins)) {
    throw new GiftSendError('INVALID_AMOUNT', 'Total cost out of range');
  }

  let comboCount = 1;
  if (input.comboKey && gift.isComboEligible) {
    const cutoff = new Date(Date.now() - 10_000); // 10s combo window
    const existing = await prisma.giftTransaction.count({
      where: {
        comboKey: input.comboKey,
        senderId: input.senderId,
        recipientId: input.recipientId,
        giftId: gift.id,
        createdAt: { gte: cutoff },
      },
    });
    comboCount = existing + 1;
  }

  const result = await prisma.$transaction(
    async (tx) => {
      const decremented = await tx.user.updateMany({
        where: { id: input.senderId, coinsBalance: { gte: totalCoins } },
        data: { coinsBalance: { decrement: totalCoins } },
      });
      if (decremented.count === 0) {
        throw new GiftSendError('INSUFFICIENT_COINS', 'Insufficient balance', 402);
      }

      const isSelfGift = input.recipientId === input.senderId;

      // Account power (CP): only gifts flagged cpEligible strengthen the sender's
      // account. Rate is admin-configurable (cp_per_coin, default 1). No client
      // spec yet — professional default. See settings.controller CP_DEFAULTS.
      // Self-gifts are excluded: gifting yourself is not a display of support,
      // and letting it build CP let agents buy standing at half price.
      if (gift.cpEligible && !isSelfGift) {
        const cpGained = totalCoins * cpPerCoin;
        if (cpGained > 0) {
          await tx.user.update({
            where: { id: input.senderId },
            data: { cpPoints: { increment: cpGained } },
          });
        }
      }

      // ---- Recipient crediting rules (client spec, 2026-07) --------------
      //   • registered hosting-agency member -> 0 coins to balance; the full
      //     value is "earnings"/target, tracked via GiftTransaction below.
      //     This now holds for SELF-gifts too (2026-08): the old `!isSelfGift`
      //     escape hatch let a وكيل gift himself and take 50% straight to
      //     balance, bypassing التارجت entirely — the "بيرجع النص" complaint.
      //   • everyone else (not in a hosting agency) -> half the coins land in
      //     their spendable balance, the other half is burned. Self-gifts by
      //     ordinary users keep this 50% rule, unchanged.
      let recipientCredit = 0;
      // MUST match the membership that `getMyTarget` / `convertTarget` accept,
      // which both require an APPROVED agency. Without the status filter a
      // pending or rejected membership still zeroed the recipient's credit
      // while their target stayed invisible and unconvertible — the coins
      // reached neither the host nor the owner and were simply lost.
      // `orderBy` makes the choice deterministic for someone who somehow
      // belongs to more than one hosting agency, so the commission always
      // goes to the same (oldest) one instead of an arbitrary row.
      const hostMembership = await tx.agencyMember.findFirst({
        where: {
          userId: input.recipientId,
          agency: { type: 'HOSTING', status: 'approved' },
        },
        orderBy: { joinedAt: 'asc' },
        select: { id: true, agencyId: true, role: true },
      });

      // 2026-08-23 — a وكيل شحن (and his فروع) is in the same boat as a host:
      // "ولو اترمي عليه هدايا لا ياخذ نصف قيمتها كوينزات لا لا لا — قيمة الهدايا
      // هتروح في التارجيت عنده". Only the 50% wallet credit is suppressed; the
      // 20% owner commission below stays HOSTING-only, because a charging agent
      // already took his cut at charge time ("نسبته اخذها وقت الشحن").
      const chargingMembership = hostMembership
        ? null
        : await tx.agencyMember.findFirst({
            where: {
              userId: input.recipientId,
              role: { in: ['OWNER', 'BRANCH'] },
              agency: { type: 'CHARGING', status: 'approved' },
            },
            orderBy: { joinedAt: 'asc' },
            select: { id: true },
          });

      recipientCredit = hostMembership || chargingMembership ? 0 : Math.floor(totalCoins / 2);

      // #4: agency owner's 20% commission on a host's gift earnings, cut from
      // every gift a hosting-agency member receives.
      //
      // 2026-08 (client complaint "عمولة الوكيل بتروح كوينزات اضافيه"): the
      // commission used to be credited straight to the owner's coinsBalance,
      // which minted spendable coins out of thin air on every gift. It now
      // only raises the owner's OWN TARGET (`commissionTargetCoins`), so he
      // cashes it out through the normal 50% تبديل الكوينزات path like any
      // other earned target — no wallet credit here.
      //
      // 2026-08 (client complaint "لو رمي هدايا علي نفسه او حد رمي عليه هدايا
      // لا تحسب له عموله"): the commission is now COUNTED on every such gift —
      // the old `!isSelfGift` and `role !== 'OWNER'` guards dropped it silently
      // when a host gifted himself and when the recipient was the وكيل himself.
      // What those cases must NOT do is pay out early, and that is handled by
      // the release gate, not by skipping the accrual: the mirror copy on the
      // SOURCE member's row (`commissionGeneratedCoins`) keeps the commission
      // locked until that member completes their target — see
      // `computeCommissionSplit` in agency.controller.
      let commission: { ownerId: number; agencyId: number; amount: number } | null = null;
      if (hostMembership) {
        const COMMISSION_RATE = Number(process.env.AGENCY_COMMISSION_RATE ?? 0.2);
        const owner = await tx.agencyMember.findFirst({
          where: { agencyId: hostMembership.agencyId, role: 'OWNER' },
          select: { id: true, userId: true },
        });
        if (owner) {
          const amount = Math.floor(totalCoins * COMMISSION_RATE);
          if (amount > 0) {
            if (owner.id === hostMembership.id) {
              // The recipient IS the وكيل: both sides of the ledger are the
              // same row, so one update (two increments) instead of two.
              await tx.agencyMember.update({
                where: { id: owner.id },
                data: {
                  commissionTargetCoins: { increment: BigInt(amount) },
                  commissionGeneratedCoins: { increment: BigInt(amount) },
                },
              });
            } else {
              await tx.agencyMember.update({
                where: { id: owner.id },
                data: { commissionTargetCoins: { increment: BigInt(amount) } },
              });
              await tx.agencyMember.update({
                where: { id: hostMembership.id },
                data: { commissionGeneratedCoins: { increment: BigInt(amount) } },
              });
            }
            commission = { ownerId: owner.userId, agencyId: hostMembership.agencyId, amount };
          }
        }
      }

      let recipientBalance: number;
      if (recipientCredit > 0) {
        const recipientUpdate = await tx.user.update({
          where: { id: input.recipientId },
          data: { coinsBalance: { increment: recipientCredit } },
          select: { coinsBalance: true },
        });
        recipientBalance = recipientUpdate.coinsBalance;
      } else {
        const r = await tx.user.findUnique({
          where: { id: input.recipientId },
          select: { coinsBalance: true },
        });
        recipientBalance = r?.coinsBalance ?? 0;
      }

      const sender = await tx.user.findUnique({
        where: { id: input.senderId },
        select: { coinsBalance: true },
      });

      // Level/XP (2026-08-23 client spec: "عندما ينفق المستخدم هدايا على
      // المستخدمين كل عدد محدد بلوحة التحكم يرتفع الليفل الخاص به").
      //
      // The level belongs to the SENDER and tracks coins SPENT on gifts — it
      // used to be credited to the recipient, which is why supporting nobody
      // still moved a level and why the dashboard thresholds looked inert.
      // XP is 1:1 with coins spent so the numbers an admin types into the LV
      // table are literally "كوينزات مُهداة", not an invisible XP currency.
      // Self-gifts excluded — otherwise a user levels himself up by cycling
      // coins through his own account.
      const XP_PER_COIN = Number(process.env.GIFT_XP_PER_COIN ?? 1);
      const xpGained = Math.floor(totalCoins * XP_PER_COIN);
      let levelUp: { level: number; grantedItemCount: number } | null = null;
      if (xpGained > 0 && !isSelfGift) {
        const xpResult: any = await awardUserXP(input.senderId, xpGained, tx);
        // The LevelConfig items are granted inside awardUserXP (atomically with
        // the level change); the notification waits until this transaction
        // commits, so a rollback can't announce a level-up that never happened.
        if (xpResult?.leveledUp) {
          levelUp = {
            level: xpResult.level,
            grantedItemCount: (xpResult.grantedItemIds ?? []).length,
          };
        }
      }

      const txRow = await tx.giftTransaction.create({
        data: {
          senderId: input.senderId,
          recipientId: input.recipientId,
          roomId: input.roomId ?? null,
          giftId: gift.id,
          quantity,
          totalCoins,
          comboKey: input.comboKey ?? null,
          comboCount,
        },
      });

      // Any gift worth more than 5,000 coins is broadcast globally.
      const broadcast = gift.broadcastGlobal || gift.tier === 'LEGENDARY' || totalCoins > 5000;
      if (broadcast) {
        await tx.giftBroadcast.create({
          data: {
            transactionId: txRow.id,
            fromRoomId: input.roomId ?? null,
            giftId: gift.id,
            expiresAt: new Date(Date.now() + BROADCAST_TTL_MS),
          },
        });
      }

      return {
        transactionId: txRow.id,
        senderBalance: sender?.coinsBalance ?? 0,
        recipientBalance,
        recipientCredit,
        broadcast,
        commission,
        levelUp,
      };
    },
    { isolationLevel: 'Serializable', maxWait: 5_000, timeout: 10_000 },
  );

  // Level-up notice, once the XP/level/item grants are safely committed.
  if (result.levelUp) {
    await notifyLevelUp(
      input.senderId,
      result.levelUp.level,
      result.levelUp.grantedItemCount,
    );
  }

  // Notify the recipient (best-effort; never blocks the gift). Skip self-gifts.
  if (input.recipientId !== input.senderId) {
    try {
      const senderUser = await prisma.user.findUnique({
        where: { id: input.senderId },
        select: { name: true },
      });
      await createNotification({
        userId: input.recipientId,
        actorId: input.senderId,
        type: 'gift_received',
        title: 'هدية جديدة 🎁',
        body: `${senderUser?.name ?? 'مستخدم'} أرسل لك ${gift.nameAr ?? gift.name}${quantity > 1 ? ' ×' + quantity : ''}`,
        data: { giftId: gift.id, quantity, senderId: input.senderId },
      });
    } catch (e) {
      console.warn('gift notification failed:', e);
    }
  }

  // #4: notify the agency owner about their commission (best-effort, mirrors
  // the recipient notification above — never blocks the gift itself).
  if (result.commission) {
    try {
      const recipientUser = await prisma.user.findUnique({
        where: { id: input.recipientId },
        select: { name: true },
      });
      await createNotification({
        userId: result.commission.ownerId,
        type: 'AGENCY_COMMISSION',
        title: '💰 عمولة وكيل',
        body: `أضيفت ${result.commission.amount} كوينز إلى التارجت الخاص بك كعمولة من هدية استلمها ${recipientUser?.name ?? 'أحد أعضاء وكالتك'} — تصبح قابلة للتبديل بعد إكماله التارجت المحدد`,
        data: { agencyId: result.commission.agencyId, amount: result.commission.amount, fromUserId: input.recipientId },
      });
    } catch (e) {
      console.warn('agency commission notification failed:', e);
    }
  }

  // Medals: unlock any gifts_sent / level achievements this send earned.
  // Best-effort and non-blocking — checkAchievements existed but had no
  // caller anywhere, so no medal could ever unlock before this.
  try {
    const [giftsSent, sender] = await Promise.all([
      prisma.giftTransaction.count({ where: { senderId: input.senderId } }),
      prisma.user.findUnique({ where: { id: input.recipientId }, select: { level: true } }),
    ]);
    await checkAchievements(input.senderId, 'gifts_sent', giftsSent);
    if (sender?.level != null) {
      await checkAchievements(input.recipientId, 'level', sender.level);
    }
  } catch (e) {
    console.warn('achievement check failed:', e);
  }

  return {
    transactionId: result.transactionId,
    totalCoins,
    senderBalance: result.senderBalance,
    // Actual coins that landed in the recipient's spendable balance (0 for
    // agency hosts / self-gifts, 50% for non-members). Not always == totalCoins.
    recipientCoinsDelta: result.recipientCredit,
    comboCount,
    broadcast: result.broadcast,
    gift: {
      id: gift.id,
      name: gift.name,
      nameAr: gift.nameAr,
      iconUrl: gift.iconUrl,
      tier: gift.tier,
      format: gift.format,
      animationMs: gift.animationMs,
      animationHtml: gift.animationHtml,
      animationUrl: gift.animationUrl,
      videoHasAlpha: gift.videoHasAlpha,
      fireworksEnabled: gift.fireworksEnabled,
      fireworksColors: gift.fireworksColors,
      coinCost: gift.coinCost,
      broadcastGlobal: gift.broadcastGlobal,
    },
  };
}
