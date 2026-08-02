import type { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { sendGiftAtomic, GiftSendError } from './giftService';
import { readCatalogCache, writeCatalogCache, getCatalogVersion } from './catalogCache';
import { maybeCreateRelationRequestFromRing } from '../services/relationRing.service';
import type { Server } from 'socket.io';

let ioRef: Server | null = null;
export function setGiftIo(io: Server) {
  ioRef = io;
}

export function emitGiftSent(payload: any) {
  if (!ioRef) return;
  // Per-room emission for the gift event.
  if (payload.roomId != null) {
    ioRef.to(`room:${payload.roomId}`).emit('gift_sent', payload);
  } else {
    ioRef.to(payload.recipientId.toString()).emit('gift_sent', payload);
  }
  if (payload.gift.tier === 'LEGENDARY') {
    // Pre-warm clients before main event.
    ioRef.emit('gift_legendary_incoming', {
      transactionId: payload.transactionId,
      gift: payload.gift,
      fromRoomId: payload.roomId,
    });
  }
  if (payload.broadcast) {
    ioRef.emit('gift_broadcast', payload);
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
    const gifts = await prisma.gift.findMany({
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
        createdAt: g.createdAt,
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

    // Fire-and-forget: if the gift is a relation-ring, auto-create a relation request.
    maybeCreateRelationRequestFromRing({
      senderId,
      receiverId: recipient,
      giftId,
    }).catch((e) => console.error('[gifts.send] relation ring hook failed', e));

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
      prisma.giftTransaction.findMany({
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
      prisma.giftTransaction.count({ where }),
    ]);
    return res.json({ success: true, page, limit, total, items });
  } catch (err) {
    console.error('[gifts.transactions]', err);
    return res.status(500).json({ success: false, message: 'Failed to load transactions' });
  }
}

// GET /gifts/received-summary/:userId — distinct gifts a user has received + how many times.
export async function receivedSummary(req: Request, res: Response) {
  try {
    const userId = Number(req.params.userId) || (req.userId ?? req.authUser?.id);
    if (!userId) return res.status(400).json({ success: false, message: 'userId required' });

    const rows = await prisma.giftTransaction.groupBy({
      by: ['giftId'],
      where: { recipientId: userId },
      _sum: { quantity: true, totalCoins: true },
      _count: { _all: true },
    });
    const giftIds = rows.map((r) => r.giftId);
    const gifts = giftIds.length
      ? await prisma.gift.findMany({
          where: { id: { in: giftIds } },
          select: { id: true, name: true, nameAr: true, iconUrl: true, tier: true, coinCost: true },
        })
      : [];
    const byId = new Map(gifts.map((g) => [g.id, g]));
    const data = rows
      .map((r) => ({
        gift: byId.get(r.giftId) ?? null,
        count: r._sum.quantity ?? r._count._all,
        totalCoins: r._sum.totalCoins ?? 0,
      }))
      .filter((d) => d.gift)
      .sort((a, b) => (b.totalCoins as number) - (a.totalCoins as number));
    return res.json({ success: true, data });
  } catch (err) {
    console.error('[gifts.receivedSummary]', err);
    return res.status(500).json({ success: false, message: 'Failed to load received gifts' });
  }
}

export async function leaderboard(req: Request, res: Response) {
  try {
    const roomId = Number(req.params.roomId);
    if (!Number.isFinite(roomId)) return res.status(400).json({ success: false, message: 'Invalid roomId' });
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const rows = await prisma.giftTransaction.groupBy({
      by: ['senderId'],
      // Self-gifts don't count: sending to yourself is not supporting anyone,
      // and it let agents buy the top of the room board at half price.
      where: {
        roomId,
        createdAt: { gte: since },
        NOT: { senderId: { equals: prisma.giftTransaction.fields.recipientId } },
      },
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
