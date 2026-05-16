import prisma from '../../utils/prisma';
import type { GiftTier } from '@prisma/client';

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
 * - Creates GiftV2Transaction.
 * - Creates GiftV2Broadcast for legendary / broadcastGlobal gifts.
 *
 * Returns the full gift object so the socket layer can emit a payload
 * the client can render without an extra lookup.
 */
export async function sendGiftAtomic(input: SendGiftInput): Promise<SendGiftResult> {
  const quantity = Math.max(1, Math.min(MAX_QUANTITY, Math.floor(input.quantity ?? 1)));
  if (input.senderId === input.recipientId) {
    throw new GiftSendError('SELF_GIFT', 'Cannot send a gift to yourself');
  }

  const gift = await prisma.giftV2.findUnique({ where: { id: input.giftId } });
  if (!gift || !gift.isActive) throw new GiftSendError('INVALID_GIFT', 'Gift not found or inactive', 404);

  const totalCoins = gift.coinCost * quantity;
  if (totalCoins <= 0 || !Number.isSafeInteger(totalCoins)) {
    throw new GiftSendError('INVALID_AMOUNT', 'Total cost out of range');
  }

  let comboCount = 1;
  if (input.comboKey && gift.isComboEligible) {
    const cutoff = new Date(Date.now() - 10_000); // 10s combo window
    const existing = await prisma.giftV2Transaction.count({
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

      const recipientUpdate = await tx.user.update({
        where: { id: input.recipientId },
        data: { coinsBalance: { increment: totalCoins } },
        select: { coinsBalance: true },
      });

      const sender = await tx.user.findUnique({
        where: { id: input.senderId },
        select: { coinsBalance: true },
      });

      const txRow = await tx.giftV2Transaction.create({
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

      const broadcast = gift.broadcastGlobal || gift.tier === 'LEGENDARY';
      if (broadcast) {
        await tx.giftV2Broadcast.create({
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
        recipientBalance: recipientUpdate.coinsBalance,
        broadcast,
      };
    },
    { isolationLevel: 'Serializable', maxWait: 5_000, timeout: 10_000 },
  );

  return {
    transactionId: result.transactionId,
    totalCoins,
    senderBalance: result.senderBalance,
    recipientCoinsDelta: totalCoins,
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
