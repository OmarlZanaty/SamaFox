import type { Request, Response } from 'express';
import prisma from '../../utils/prisma';
import { sendGiftAtomic, GiftSendError } from './giftService';
import { readCatalogCache, writeCatalogCache, getCatalogVersion } from './catalogCache';
import type { Server } from 'socket.io';

let ioRef: Server | null = null;
export function setGiftIo(io: Server) {
  ioRef = io;
}

export function emitGiftSent(payload: any) {
  if (!ioRef) return;
  // Per-room emission for the gift event.
  if (payload.roomId != null) {
    ioRef.to(`room:${payload.roomId}`).emit('gift_v2_sent', payload);
  } else {
    ioRef.to(payload.recipientId.toString()).emit('gift_v2_sent', payload);
  }
  if (payload.gift.tier === 'LEGENDARY') {
    // Pre-warm clients before main event.
    ioRef.emit('gift_v2_legendary_incoming', {
      transactionId: payload.transactionId,
      gift: payload.gift,
      fromRoomId: payload.roomId,
    });
  }
  if (payload.broadcast) {
    ioRef.emit('gift_v2_broadcast', payload);
  }
}

export async function listCatalog(_req: Request, res: Response) {
  try {
    const cached = await readCatalogCache();
    if (cached) {
      res.setHeader('X-Gifts-Catalog-Version', String(cached.version));
      res.setHeader('Cache-Control', 'public, max-age=30');
      return res.type('application/json').send(cached.payload);
    }
    const version = await getCatalogVersion();
    const gifts = await prisma.giftV2.findMany({
      where: { isActive: true },
      orderBy: [{ tier: 'asc' }, { sortOrder: 'asc' }, { coinCost: 'asc' }],
    });
    const grouped: Record<string, any[]> = { SMALL: [], MEDIUM: [], LARGE: [], LEGENDARY: [] };
    for (const g of gifts) {
      const bucket = grouped[g.tier] ?? (grouped[g.tier] = []);
      bucket.push({
        id: g.id,
        name: g.name,
        nameAr: g.nameAr,
        iconUrl: g.iconUrl,
        format: g.format,
        animationHtml: g.animationHtml,
        animationUrl: g.animationUrl,
        videoHasAlpha: g.videoHasAlpha,
        fireworksEnabled: g.fireworksEnabled,
        fireworksColors: g.fireworksColors,
        coinCost: g.coinCost,
        tier: g.tier,
        animationMs: g.animationMs,
        isComboEligible: g.isComboEligible,
        broadcastGlobal: g.broadcastGlobal,
        category: g.category,
        sortOrder: g.sortOrder,
      });
    }
    const body = JSON.stringify({ success: true, version, gifts: grouped });
    await writeCatalogCache(version, body);
    res.setHeader('X-Gifts-Catalog-Version', String(version));
    res.setHeader('Cache-Control', 'public, max-age=30');
    return res.type('application/json').send(body);
  } catch (err) {
    console.error('[gifts.listCatalog]', err);
    return res.status(500).json({ success: false, message: 'Failed to load gift catalog' });
  }
}

export async function send(req: Request, res: Response) {
  try {
    const senderId = req.userId ?? req.authUser?.id;
    if (!senderId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const { giftId, recipientId, roomId, quantity, comboKey } = req.body ?? {};
    if (!giftId || typeof giftId !== 'string') {
      return res.status(400).json({ success: false, message: 'giftId is required' });
    }
    const recipient = Number(recipientId);
    if (!Number.isFinite(recipient) || recipient <= 0) {
      return res.status(400).json({ success: false, message: 'recipientId is required' });
    }
    const result = await sendGiftAtomic({
      senderId,
      recipientId: recipient,
      roomId: roomId != null ? Number(roomId) : null,
      giftId,
      quantity: quantity != null ? Number(quantity) : 1,
      comboKey: comboKey ?? null,
    });

    const sender = await prisma.user.findUnique({
      where: { id: senderId },
      select: { id: true, name: true, avatarUrl: true },
    });
    const recipientUser = await prisma.user.findUnique({
      where: { id: recipient },
      select: { id: true, name: true, avatarUrl: true },
    });

    const payload = {
      transactionId: result.transactionId,
      senderId,
      recipientId: recipient,
      roomId: roomId != null ? Number(roomId) : null,
      quantity: quantity != null ? Number(quantity) : 1,
      totalCoins: result.totalCoins,
      comboKey: comboKey ?? null,
      comboCount: result.comboCount,
      broadcast: result.broadcast,
      sender,
      recipient: recipientUser,
      gift: result.gift,
      ts: Date.now(),
    };

    emitGiftSent(payload);

    return res.json({
      success: true,
      transactionId: result.transactionId,
      senderBalance: result.senderBalance,
      comboCount: result.comboCount,
      broadcast: result.broadcast,
    });
  } catch (err) {
    if (err instanceof GiftSendError) {
      return res.status(err.status).json({ success: false, code: err.code, message: err.message });
    }
    console.error('[gifts.send]', err);
    return res.status(500).json({ success: false, message: 'Send failed' });
  }
}

export async function transactions(req: Request, res: Response) {
  try {
    const userId = req.userId ?? req.authUser?.id;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
    const skip = (page - 1) * limit;
    const direction = (req.query.direction as string) || 'all';
    const where =
      direction === 'sent' ? { senderId: userId }
      : direction === 'received' ? { recipientId: userId }
      : { OR: [{ senderId: userId }, { recipientId: userId }] };

    const [items, total] = await Promise.all([
      prisma.giftV2Transaction.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        include: {
          gift: { select: { id: true, name: true, nameAr: true, iconUrl: true, tier: true, coinCost: true } },
          sender: { select: { id: true, name: true, avatarUrl: true } },
          recipient: { select: { id: true, name: true, avatarUrl: true } },
        },
      }),
      prisma.giftV2Transaction.count({ where }),
    ]);
    return res.json({ success: true, page, limit, total, items });
  } catch (err) {
    console.error('[gifts.transactions]', err);
    return res.status(500).json({ success: false, message: 'Failed to load transactions' });
  }
}

export async function leaderboard(req: Request, res: Response) {
  try {
    const roomId = Number(req.params.roomId);
    if (!Number.isFinite(roomId)) return res.status(400).json({ success: false, message: 'Invalid roomId' });
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const rows = await prisma.giftV2Transaction.groupBy({
      by: ['senderId'],
      where: { roomId, createdAt: { gte: since } },
      _sum: { totalCoins: true },
      orderBy: { _sum: { totalCoins: 'desc' } },
      take: 20,
    });
    const senderIds = rows.map((r) => r.senderId);
    const users = await prisma.user.findMany({
      where: { id: { in: senderIds } },
      select: { id: true, name: true, avatarUrl: true },
    });
    const byId = new Map(users.map((u) => [u.id, u]));
    const board = rows.map((r) => ({
      user: byId.get(r.senderId) ?? { id: r.senderId, name: 'Unknown', avatarUrl: null },
      coins: r._sum.totalCoins ?? 0,
    }));
    return res.json({ success: true, roomId, since, board });
  } catch (err) {
    console.error('[gifts.leaderboard]', err);
    return res.status(500).json({ success: false, message: 'Failed to load leaderboard' });
  }
}
