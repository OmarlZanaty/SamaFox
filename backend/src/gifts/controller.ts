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
    const [gifts, categories] = await Promise.all([
      prisma.gift.findMany({
        where: { isActive: true },
        orderBy: [{ tier: 'asc' }, { sortOrder: 'asc' }, { coinCost: 'asc' }],
      }),
      // B4 — the app's gift-sheet tabs. Shipping them with the catalog means a
      // list created in لوحة التحكم shows up on the next catalog fetch with no
      // app release, which is the whole point of the request.
      prisma.giftCategory.findMany({
        where: { isActive: true },
        orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
        select: { key: true, nameAr: true, sortOrder: true },
      }),
    ]);
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
    const body = JSON.stringify({ success: true, version, gifts: grouped, categories });
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

    // A22 - the centred announcement bar ("<sender> اهدى <gift> الى <recipient>").
    // Emitted for ordinary single sends too, so the bar is not a fan-out-only
    // feature; the batch endpoint emits the "الى الجميع" variant of the same event.
    if (ioRef && payload.roomId != null) {
      ioRef.to(`room:${payload.roomId}`).emit('gift_announcement', {
        senderId,
        senderName: sender?.name ?? null,
        senderAvatarUrl: sender?.avatarUrl ?? null,
        gift: {
          id: result.gift.id,
          name: result.gift.name,
          nameAr: result.gift.nameAr,
          iconUrl: result.gift.iconUrl,
        },
        quantity: payload.quantity,
        recipientCount: 1,
        recipientName: recipientUser?.name ?? null,
        roomId: payload.roomId,
        totalCoins: result.totalCoins,
        ts: Date.now(),
      });
    }

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

/**
 * كأس الدعم — the supporters board: who has spent the most on gifts, ranked.
 *
 * Shared by the two boards the client asked for:
 *   • the whole app (الكاس في البرنامج) — top 30, no room filter
 *   • one room (الكاس في الروم) — top 20, that room's gifts only
 *
 * Self-gifts never count: sending to yourself supports nobody, and it let an
 * agent buy the top of the board at half price.
 *
 * B9 — "تصفير العداد": an account the dashboard has reset (`supportersResetAt`)
 * only counts the gifts it sent AFTER that moment. The client asked for this so
 * the owner, who gifts heavily while testing, stops occupying #1 and real
 * supporters can compete — and explicitly asked that it NOT be permanent:
 * "لو دعم مره تانيه يرجع بالمستوى اللي هو وصل له". Zeroing the window rather
 * than deleting rows is what gives that: the next gift he sends puts him back
 * on the board at exactly what he has earned since the reset.
 */
async function buildSupportersBoard(opts: { roomId?: number; limit: number; sinceMs?: number }) {
  const { roomId, limit, sinceMs } = opts;

  // Only the handful of accounts an admin has actually reset need a per-sender
  // time window; everyone else is matched by the cheap `notIn` branch.
  const resetUsers = await prisma.user.findMany({
    where: { supportersResetAt: { not: null } },
    select: { id: true, supportersResetAt: true },
  });
  const resetIds = resetUsers.map((u) => u.id);

  const rows = await prisma.giftTransaction.groupBy({
    by: ['senderId'],
    where: {
      AND: [
        ...(roomId != null ? [{ roomId }] : []),
        ...(sinceMs ? [{ createdAt: { gte: new Date(Date.now() - sinceMs) } }] : []),
        { NOT: { senderId: { equals: prisma.giftTransaction.fields.recipientId } } },
        ...(resetIds.length
          ? [
              {
                OR: [
                  { senderId: { notIn: resetIds } },
                  ...resetUsers.map((u) => ({
                    senderId: u.id,
                    createdAt: { gte: u.supportersResetAt as Date },
                  })),
                ],
              },
            ]
          : []),
      ],
    },
    _sum: { totalCoins: true, quantity: true },
    orderBy: { _sum: { totalCoins: 'desc' } },
    take: limit,
  });

  const senderIds = rows.map((r) => r.senderId);
  const users = senderIds.length
    ? await prisma.user.findMany({
        where: { id: { in: senderIds } },
        select: { id: true, name: true, avatarUrl: true, displayId: true, level: true, vipLevel: true },
      })
    : [];
  const byId = new Map(users.map((u) => [u.id, u]));

  return rows.map((r, i) => ({
    rank: i + 1,
    user: byId.get(r.senderId) ?? { id: r.senderId, name: 'Unknown', avatarUrl: null, displayId: null, level: 1, vipLevel: 0 },
    coins: Number(r._sum.totalCoins ?? 0),
    gifts: Number(r._sum.quantity ?? 0),
  }));
}

const parseLimit = (raw: unknown, fallback: number, max: number) => {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? Math.min(max, Math.floor(n)) : fallback;
};

/** Windows the board can be asked for. `all` (default) is the hall of fame. */
const RANGE_MS: Record<string, number | undefined> = {
  all: undefined,
  day: 24 * 60 * 60 * 1000,
  week: 7 * 24 * 60 * 60 * 1000,
  month: 30 * 24 * 60 * 60 * 1000,
};

/** GET /gifts/supporters?limit=30&range=all — the app-wide board. */
export async function topSupporters(req: Request, res: Response) {
  try {
    const limit = parseLimit((req.query as any)?.limit, 30, 100);
    const range = String((req.query as any)?.range ?? 'all');
    const board = await buildSupportersBoard({ limit, sinceMs: RANGE_MS[range] });
    return res.json({ success: true, scope: 'global', range, board });
  } catch (err) {
    console.error('[gifts.topSupporters]', err);
    return res.status(500).json({ success: false, message: 'Failed to load supporters' });
  }
}

/**
 * GET /gifts/leaderboard/:roomId?limit=20&range=all — one room's board.
 * `range` used to be hard-wired to the last 24h, which made the room cup look
 * empty on any quiet day; it now defaults to all-time like the app-wide one.
 */
export async function leaderboard(req: Request, res: Response) {
  try {
    const roomId = Number(req.params.roomId);
    if (!Number.isFinite(roomId)) return res.status(400).json({ success: false, message: 'Invalid roomId' });
    const limit = parseLimit((req.query as any)?.limit, 20, 100);
    const range = String((req.query as any)?.range ?? 'all');
    const board = await buildSupportersBoard({ roomId, limit, sinceMs: RANGE_MS[range] });
    return res.json({ success: true, scope: 'room', roomId, range, board });
  } catch (err) {
    console.error('[gifts.leaderboard]', err);
    return res.status(500).json({ success: false, message: 'Failed to load leaderboard' });
  }
}

/**
 * A27 / #31 — "المايك الكامل" و "جميع الغرفة".
 *
 * The client's rule, exactly: "لو 10 اشخاص على المايك والهدية بـ100 كوينز، كل
 * واحد فيهم ياخذ 100 وينخصم من المُهدي 1000". So this is a fan-out of N full
 * sends, not one gift split N ways.
 *
 * Why a dedicated endpoint rather than the app looping over POST /send:
 *   • one round trip instead of N — on a 30-seat room the loop was 30 requests
 *     deep and the rate limiter would cut it off part-way through
 *   • the balance check for the WHOLE fan-out happens before any coin moves, so
 *     a sender who can afford 6 of 10 no longer ends up having paid for 6 with
 *     no way to explain which 4 failed
 *   • a single "إلى الجميع" announcement (A22) can be emitted for the batch
 *     instead of N separate banners covering the screen
 */
export async function sendBatch(req: Request, res: Response) {
  try {
    const senderId = req.userId ?? req.authUser?.id;
    if (!senderId) return res.status(401).json({ success: false, message: 'Unauthenticated' });

    const { giftId, recipientIds, roomId, quantity, comboKey } = req.body ?? {};
    if (!giftId || typeof giftId !== 'string') {
      return res.status(400).json({ success: false, message: 'giftId is required' });
    }
    const ids = [
      ...new Set(
        (Array.isArray(recipientIds) ? recipientIds : [])
          .map((v: unknown) => Number(v))
          .filter((n: number) => Number.isFinite(n) && n > 0),
      ),
    ];
    if (ids.length === 0) {
      return res.status(400).json({ success: false, message: 'recipientIds is required' });
    }
    // A whole room is the realistic upper bound; anything larger is a client bug.
    if (ids.length > 60) {
      return res.status(400).json({ success: false, message: 'Too many recipients' });
    }

    const qty = Math.max(1, Math.min(99, Math.floor(Number(quantity ?? 1))));
    const gift = await prisma.gift.findUnique({ where: { id: giftId } });
    if (!gift || !gift.isActive) {
      return res.status(404).json({ success: false, code: 'INVALID_GIFT', message: 'Gift not found or inactive' });
    }

    // Up-front affordability check for the ENTIRE fan-out. sendGiftAtomic still
    // guards each individual debit, so this is a friendlier failure, not the
    // safety mechanism.
    const perRecipient = gift.coinCost * qty;
    const grandTotal = perRecipient * ids.length;
    const sender = await prisma.user.findUnique({
      where: { id: senderId },
      select: { id: true, name: true, avatarUrl: true, coinsBalance: true },
    });
    if (!sender) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    if (sender.coinsBalance < grandTotal) {
      return res.status(402).json({
        success: false,
        code: 'INSUFFICIENT_COINS',
        message: `رصيدك لا يكفي — الهدية لـ${ids.length} مستلمين تكلف ${grandTotal} كوينز`,
      });
    }

    const recipientUsers = await prisma.user.findMany({
      where: { id: { in: ids } },
      select: { id: true, name: true, avatarUrl: true },
    });
    const recipientById = new Map(recipientUsers.map((u) => [u.id, u]));

    const results: Array<{ recipientId: number; transactionId: string }> = [];
    const failures: Array<{ recipientId: number; code: string; message: string }> = [];
    let senderBalance = sender.coinsBalance;
    let anyBroadcast = false;

    for (const rid of ids) {
      if (!recipientById.has(rid)) {
        failures.push({ recipientId: rid, code: 'INVALID_RECIPIENT', message: 'المستخدم غير موجود' });
        continue;
      }
      try {
        const result = await sendGiftAtomic({
          senderId,
          recipientId: rid,
          roomId: roomId != null ? Number(roomId) : null,
          giftId,
          quantity: qty,
          comboKey: comboKey ?? null,
        });
        senderBalance = result.senderBalance;
        anyBroadcast = anyBroadcast || result.broadcast;
        results.push({ recipientId: rid, transactionId: result.transactionId });

        // Per-recipient event so each seat still gets its own flying gift.
        // `batchSize` tells the client this belongs to a fan-out, so it renders
        // ONE "إلى الجميع" banner instead of N stacked ones (A22).
        emitGiftSent({
          transactionId: result.transactionId,
          senderId,
          recipientId: rid,
          roomId: roomId != null ? Number(roomId) : null,
          quantity: qty,
          totalCoins: result.totalCoins,
          comboKey: comboKey ?? null,
          comboCount: result.comboCount,
          broadcast: result.broadcast,
          sender: { id: sender.id, name: sender.name, avatarUrl: sender.avatarUrl },
          recipient: recipientById.get(rid) ?? null,
          gift: result.gift,
          batchSize: ids.length,
          ts: Date.now(),
        });

        maybeCreateRelationRequestFromRing({ senderId, receiverId: rid, giftId }).catch((e) =>
          console.error('[gifts.sendBatch] relation ring hook failed', e),
        );
      } catch (err) {
        if (err instanceof GiftSendError) {
          failures.push({ recipientId: rid, code: err.code, message: err.message });
          // A balance that ran out mid-fan-out will fail for everyone left, so
          // stop rather than burning through 20 doomed transactions.
          if (err.code === 'INSUFFICIENT_COINS') break;
        } else {
          console.error('[gifts.sendBatch]', err);
          failures.push({ recipientId: rid, code: 'SEND_FAILED', message: 'فشل الإرسال' });
        }
      }
    }

    // A22 — the centred announcement bar. One event for the whole fan-out:
    // "فلان أهدى <هدية> إلى الجميع" when it went to more than one person.
    if (results.length > 0 && ioRef) {
      const announcement = {
        senderId,
        senderName: sender.name,
        senderAvatarUrl: sender.avatarUrl,
        gift: {
          id: gift.id,
          name: gift.name,
          nameAr: gift.nameAr,
          iconUrl: gift.iconUrl,
        },
        quantity: qty,
        recipientCount: results.length,
        // Single-recipient batches still name the person; multi says "الجميع".
        recipientName:
          results.length === 1 ? recipientById.get(results[0]!.recipientId)?.name ?? null : null,
        roomId: roomId != null ? Number(roomId) : null,
        totalCoins: perRecipient * results.length,
        ts: Date.now(),
      };
      if (announcement.roomId != null) {
        ioRef.to(`room:${announcement.roomId}`).emit('gift_announcement', announcement);
      }
    }

    return res.json({
      success: results.length > 0,
      sent: results.length,
      requested: ids.length,
      senderBalance,
      broadcast: anyBroadcast,
      results,
      failures,
    });
  } catch (err) {
    console.error('[gifts.sendBatch]', err);
    return res.status(500).json({ success: false, message: 'Send failed' });
  }
}
