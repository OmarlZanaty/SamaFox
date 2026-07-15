import prisma from '../utils/prisma';
import type { GiftTier } from '@prisma/client';
import { createNotification } from '../services/notification.service';
import { getCpConfig } from '../controllers/settings.controller';

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

      // Account power (CP): only gifts flagged cpEligible strengthen the sender's
      // account. Rate is admin-configurable (cp_per_coin, default 1). No client
      // spec yet — professional default. See settings.controller CP_DEFAULTS.
      if (gift.cpEligible) {
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
      //   • everyone else (not in a hosting agency) -> half the coins land in
      //     their spendable balance, the other half is burned.
      //   • self-gift -> same 50% rule applies to the sender: still a net
      //     50% loss each time (not a duplication exploit), just a way to
      //     partially cash out coins into "confirmed" spendable balance.
      const isSelfGift = input.recipientId === input.senderId;
      let recipientCredit = 0;
      const hostMembership = await tx.agencyMember.findFirst({
        where: { userId: input.recipientId, agency: { type: 'HOSTING' } },
        select: { id: true },
      });
      recipientCredit = hostMembership && !isSelfGift ? 0 : Math.floor(totalCoins / 2);

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
      };
    },
    { isolationLevel: 'Serializable', maxWait: 5_000, timeout: 10_000 },
  );

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
