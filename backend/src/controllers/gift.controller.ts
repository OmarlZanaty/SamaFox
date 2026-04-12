import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { io } from '../index';
import { createNotification } from '../services/notification.service';
import { ensureRelationRingGift, maybeCreateRelationRequestFromRing } from '../services/relationRing.service';
import type { Prisma } from '@prisma/client';


export const getGifts = async (req: Request, res: Response) => {
  try {
    await ensureRelationRingGift();
    const where = { isActive: true };

    const [gifts, total] = await prisma.$transaction([
      prisma.gift.findMany({
        where,
        orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }]
      }),
      prisma.gift.count({ where })
    ]);

    res.json({
      gifts: gifts.map((gift) => ({
        ...gift,
        coinsValue: gift.coinsValue || gift.priceCoins,
      })),
      total,
    });
  } catch (error) {
    console.error('Get gifts error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getGiftHistory = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const pageNum = Number(req.query.page ?? 1);
    const limitNum = Number(req.query.limit ?? 20);
    const page = Number.isFinite(pageNum) && pageNum > 0 ? pageNum : 1;
    const limit = Number.isFinite(limitNum) && limitNum > 0 ? limitNum : 20;
    const skip = (page - 1) * limit;

    const where: Prisma.GiftLogWhereInput = {
      OR: [{ senderId: userId }, { receiverId: userId }],
    };

    const [logs, total] = await Promise.all([
      prisma.giftLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        include: {
          gift: true,
          sender: { select: { id: true, name: true, avatarUrl: true } },
          receiver: { select: { id: true, name: true, avatarUrl: true } },
        },
      }),
      prisma.giftLog.count({ where }),
    ]);

    return res.json({
      logs,
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (e) {
    console.error('getGiftHistory error:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
};


export const sendGift = async (req: Request, res: Response) => {
  try {
    const senderId: number | undefined = (req as any).userId;
    if (!senderId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { receiverId, giftId, roomId, quantity = 1, message } = req.body;

    const gid = Number(giftId);
    const qty = Math.max(1, Number(quantity) || 1);
    const rid = roomId != null ? Number(roomId) : 0;

    const receiverNum: number | undefined =
      receiverId != null ? Number(receiverId) : undefined;

    if (!gid) {
      return res.status(400).json({ error: 'Invalid giftId' });
    }

    

    const gift = await prisma.gift.findUnique({ where: { id: gid } });
    if (!gift || !gift.isActive) {
      return res.status(404).json({ error: 'Gift not found' });
    }

    const sender = await prisma.user.findUnique({
      where: { id: senderId },
      select: { id: true, name: true, avatarUrl: true, coinsBalance: true },
    });
    if (!sender) {
      return res.status(404).json({ error: 'Sender not found' });
    }

    let receiver: { id: number; name: string; avatarUrl: string | null } | null = null;
    if (receiverNum != null) {
      const r = await prisma.user.findUnique({
        where: { id: receiverNum },
        select: { id: true, name: true, avatarUrl: true, coinsBalance: true },
      });
      if (!r) return res.status(404).json({ error: 'Receiver not found' });
      receiver = { id: r.id, name: r.name, avatarUrl: r.avatarUrl };
    }

    const unitCoins = gift.coinsValue || gift.priceCoins;
    const price = BigInt(unitCoins ?? 0);
    const totalCost = price * BigInt(qty);

    if (totalCost <= BigInt(0)) {
      return res.status(400).json({ error: 'Invalid gift price' });
    }

    // Receiver share (50% of total cost) only if receiver exists
    const receiverCoins = receiverNum != null ? totalCost / BigInt(2) : BigInt(0);

    // ✅ Transaction (race-safe): decrement sender only if balance is enough AT UPDATE TIME
    const result = await prisma.$transaction(async (tx) => {
      const updated = await tx.user.updateMany({
        where: {
          id: senderId,
          coinsBalance: { gte: Number(totalCost) },
        },
        data: {
          coinsBalance: { decrement: Number(totalCost) },
        },
      });

      if (updated.count === 0) {
        throw new Error('INSUFFICIENT_COINS');
      }

      // Increment receiver only if receiver exists
      let receiverNewBalance: bigint | null = null;
      if (receiverNum != null) {
        const ur = await tx.user.update({
          where: { id: receiverNum },
          data: { coinsBalance: { increment: Number(receiverCoins) } },
          select: { coinsBalance: true },
        });
        receiverNewBalance = BigInt(ur.coinsBalance);
      }

      const us = await tx.user.findUnique({
        where: { id: senderId },
        select: { coinsBalance: true },
      });

      // ✅ Create log with quantity + message (NO RAW SQL)
      const createdLog = await tx.giftLog.create({
        data: {
          senderId,
          receiverId: receiverNum ?? senderId, // keep DB consistent; if no receiver, use sender as receiver
          giftId: gid,
          roomId: rid || null,
          coinsSpent: Number(totalCost),
          quantity: qty,
          message: message ?? null,
        },
        include: {
          gift: true,
          sender: { select: { id: true, name: true, avatarUrl: true } },
          receiver: { select: { id: true, name: true, avatarUrl: true } },
        },
      });

      // Transactions
      await tx.transaction.create({
        data: {
          userId: senderId,
          type: 'gift_send',
          amountCoins: -Number(totalCost),
          status: 'completed',
        },
      });

      if (receiverNum != null) {
        await tx.transaction.create({
          data: {
            userId: receiverNum,
            type: 'gift_receive',
            amountCoins: Number(receiverCoins),
            status: 'completed',
          },
        });
      }

      return {
        createdLog,
        senderNewBalance: BigInt(us?.coinsBalance ?? 0),
        receiverNewBalance,
      };
    });

    const createdLog = result.createdLog;
    if (receiverNum != null && receiverNum !== senderId) {
      await createNotification({
        userId: receiverNum,
        actorId: senderId,
        type: 'gift_received',
        title: 'You received a gift',
        body: `${createdLog.sender.name} sent you ${qty} × ${createdLog.gift.nameAr || createdLog.gift.name}`,
        data: {
          giftId: createdLog.giftId,
          giftLogId: createdLog.id,
          quantity: qty,
          roomId: rid || null,
        },
      });

      await maybeCreateRelationRequestFromRing({
        senderId,
        receiverId: receiverNum,
        giftId: gid,
      });
    }

    // ✅ Socket emit for RoomScreen realtime overlay
    if (rid && io) {
      const roomInfo = rid ? await prisma.room.findUnique({ where: { id: rid }, select: { id: true, name: true } }) : null;
      const giftPayload = {
        roomId: rid,
        type: 'sent',
        senderName: createdLog.sender.name,
        senderAvatar: createdLog.sender.avatarUrl,
        receiverName: createdLog.receiver.name,
        receiverAvatar: createdLog.receiver.avatarUrl,

        giftEvent: {
  id: createdLog.id,

  giftId: createdLog.giftId,
  giftName: createdLog.gift.nameAr || createdLog.gift.name,
  giftImageUrl: createdLog.gift.imageUrl,

  coinsSpent: Number(totalCost),
  quantity: qty,
  message: message ?? null,

  sender: createdLog.sender,
  receiver: createdLog.receiver,

  senderId,
  senderNewBalance: result.senderNewBalance.toString(),
  receiverId: receiverNum ?? senderId,
  receiverCoins: receiverCoins.toString(),
  receiverNewBalance: result.receiverNewBalance?.toString() ?? null,

  createdAt: createdLog.createdAt,
}
      };

      io.to(`room:${rid}`).emit('gift', giftPayload);

      if ((gift.coinsValue || gift.priceCoins) >= 5000) {
        io.emit('global_gift_broadcast', {
          senderName: createdLog.sender.name,
          receiverName: createdLog.receiver.name,
          giftNameAr: createdLog.gift.nameAr || createdLog.gift.name,
          coinsValue: gift.coinsValue || gift.priceCoins,
          roomName: roomInfo?.name ?? null,
          roomId: rid || null,
          giftImageUrl: createdLog.gift.imageUrl,
          senderAvatar: createdLog.sender.avatarUrl,
          receiverAvatar: createdLog.receiver.avatarUrl,
        });
      }
    }

    // ✅ REST response
    return res.status(201).json({
      message: 'Gift sent successfully',
      gift: {
        id: gift.id,
        name: gift.name,
        nameAr: gift.nameAr || gift.name,
        imageUrl: gift.imageUrl,
        unitPriceCoins: (gift.coinsValue || gift.priceCoins)?.toString?.() ?? String(gift.priceCoins),
        quantity: qty,
        message: message ?? null,
        coinsSpent: Number(totalCost),
      },
      balances: {
        senderId,
        senderNewBalance: result.senderNewBalance.toString(),
        receiverId: receiverNum ?? senderId,
        receiverNewBalance: result.receiverNewBalance?.toString() ?? null,
      },
    });
  } catch (error: any) {
    if (error?.message === 'INSUFFICIENT_COINS') {
      return res.status(400).json({ error: 'Insufficient coins balance' });
    }
    console.error('sendGift error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};
