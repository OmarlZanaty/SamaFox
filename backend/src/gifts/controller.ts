import crypto from 'crypto';
import { giftOperationId, runGiftOperation } from './giftOperation';
import { withNameStyle } from '../services/vipStyle.service';
import type { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { sendGiftAtomic, GiftSendError } from './giftService';
import { readCatalogCache, writeCatalogCache, getCatalogVersion } from './catalogCache';
import { maybeCreateRelationRequestFromRing } from '../services/relationRing.service';
import { batchLuckyStake, getLuckyConfig, getLuckySettings, isLuckyGift, rollLucky, verifyRoll, type LuckyRollResult, type SettledEntry } from './lucky.service';
import type { Server } from 'socket.io';

let ioRef: Server | null = null;
export function setGiftIo(io: Server) {
  ioRef = io;
  void flushGiftDeliveries();
  if (!deliveryTimer) {
    deliveryTimer = setInterval(() => { void flushGiftDeliveries(); }, 5000);
    deliveryTimer.unref();
  }
}

let deliveryTimer: NodeJS.Timeout | null = null;
let delivering = false;
/** Durable at-least-once delivery. Flutter deduplicates by transactionId. */
export async function flushGiftDeliveries() {
  if (!ioRef || delivering) return;
  delivering = true;
  try {
    const rows = await prisma.giftDelivery.findMany({ where: { deliveredAt: null }, orderBy: { createdAt: 'asc' }, take: 100 });
    for (const row of rows) {
      const payload = row.payload as any;
      emitGiftSent(payload, [payload.senderId, payload.recipientId]);
      await prisma.giftDelivery.update({ where: { transactionId: row.transactionId }, data: { deliveredAt: new Date() } });
    }
    // Delivered rows are only an outbox; the gift itself lives in gift_transactions.
    if (Math.random() < 0.02) {
      await prisma.giftDelivery.deleteMany({ where: { deliveredAt: { lt: new Date(Date.now() - 86_400_000) } } });
    }
  } catch (e) { console.warn('[gift delivery]', e); }
  finally { delivering = false; }
}

function operationRequest(req: Request, senderId: number, res: Response) {
  if (res.locals.giftOperation) return res.locals.giftOperation as { id: string; senderId: number; requestHash: string };
  const key = req.get('Idempotency-Key');
  return {
    senderId,
    id: giftOperationId(senderId, key ?? crypto.randomUUID()),
    requestHash: (resHash(req)),
  };
}
function resHash(req: Request) {
  return crypto.createHash('sha256').update(`${req.method}|${req.baseUrl}${req.path}|${JSON.stringify(req.body ?? {})}`).digest('hex');
}

/**
 * @param alsoUserIds — extra per-user rooms to deliver `gift_sent` to, on top
 *   of the room (or the recipient when there is none). A CP gift completes when
 *   the recipient answers, possibly minutes later and possibly after either of
 *   them has left the room it was sent from — so both parties get it directly.
 *   Socket.IO delivers once per socket even when it sits in several of the
 *   targeted rooms, so nobody sees a doubled animation.
 */
export function emitGiftSent(payload: any, alsoUserIds: number[] = []) {
  if (!ioRef) return;
  // Per-room emission for the gift event.
  const targets = new Set<string>(
    payload.roomId != null ? [`room:${payload.roomId}`] : [payload.recipientId.toString()],
  );
  for (const uid of alsoUserIds) targets.add(uid.toString());
  if (payload.gift.tier === 'LEGENDARY') {
    // Pre-warm clients before main event.
    ioRef.emit('gift_legendary_incoming', {
      transactionId: payload.transactionId,
      gift: payload.gift,
      fromRoomId: payload.roomId,
    });
  }
  ioRef.to([...targets]).emit('gift_sent', payload);
  if (payload.broadcast) {
    ioRef.emit('gift_broadcast', payload);
  }
}

/**
 * هدايا الحظ — the events behind the lucky bars.
 *
 *  `lucky_win`       → the room (and the sender wherever they are): every DRAWN
 *                      entry, win or not — the centred "كسب ×N" banner, synced
 *                      for everyone in the room. Everything on it (photo, name,
 *                      ID, room name) is read here from the database; nothing
 *                      comes from the phone that sent the gift.
 *  `lucky_broadcast` → everyone in the app, wins ≥ the admin's threshold.
 *  `lucky_pending`   → the sender only: the entry is waiting for the round to
 *                      have enough players (new app builds show it; older ones
 *                      ignore the event).
 *  `lucky_entry_closed` → the sender only: the round closed without enough
 *                      players — no win, nothing refunded, nothing minted.
 */
export async function emitLuckyOutcome(ev: {
  own: LuckyRollResult | null;
  settled: SettledEntry[];
  senderId: number;
  roomId: number | null;
  /** The sender's entry covered this many recipients (one lucky gift sent to
   *  every mic is one draw on the whole amount). */
  recipientCount?: number;
}) {
  if (!ioRef) return;
  if (ev.own && ev.own.status === 'PENDING') {
    ioRef.to(ev.senderId.toString()).emit('lucky_pending', {
      rollId: ev.own.rollId,
      roundCode: ev.own.roundCode,
      roomId: ev.roomId,
      hostCoins: ev.own.hostCoins,
      serverSeedHash: ev.own.serverSeedHash,
      ts: Date.now(),
    });
  }
  if (!ev.settled.length) return;

  const senderIds = [...new Set(ev.settled.map((e) => e.senderId))];
  const recipientIds = [...new Set(ev.settled.map((e) => e.recipientId))];
  const roomIds = [...new Set(ev.settled.map((e) => e.roomId).filter((r): r is number => r != null))];
  const txIds = ev.settled.map((e) => e.giftTxId);
  const [users, rooms, txs, { broadcastMin }] = await Promise.all([
    prisma.user.findMany({
      where: { id: { in: [...new Set([...senderIds, ...recipientIds])] } },
      select: { id: true, name: true, avatarUrl: true, displayId: true },
    }),
    roomIds.length
      ? prisma.room.findMany({ where: { id: { in: roomIds } }, select: { id: true, name: true } })
      : Promise.resolve([] as { id: number; name: string }[]),
    prisma.giftTransaction.findMany({
      where: { id: { in: txIds } },
      select: { id: true, gift: { select: { id: true, name: true, nameAr: true, iconUrl: true } } },
    }),
    getLuckySettings(),
  ]);
  const userById = new Map(users.map((u) => [u.id, u]));
  const roomById = new Map(rooms.map((r) => [r.id, r]));
  const giftByTx = new Map(txs.map((t) => [t.id, t.gift]));

  for (const e of ev.settled) {
    const sender = userById.get(e.senderId);
    const recipientCount = e.rollId === ev.own?.rollId ? ev.recipientCount ?? 1 : 1;
    const payload = {
      rollId: e.rollId,
      roundCode: e.roundCode,
      status: 'SETTLED',
      senderId: e.senderId,
      senderName: sender?.name ?? null,
      senderAvatarUrl: sender?.avatarUrl ?? null,
      senderDisplayId: sender?.displayId ?? null,
      recipientId: e.recipientId,
      recipientName: recipientCount > 1 ? null : userById.get(e.recipientId)?.name ?? null,
      recipientCount,
      roomId: e.roomId,
      roomName: e.roomId != null ? roomById.get(e.roomId)?.name ?? null : null,
      gift: giftByTx.get(e.giftTxId) ?? null,
      giftCoins: e.giftCoins,
      hostCoins: e.hostCoins,
      multiplier: e.multiplier,
      payoutCoins: e.payoutCoins,
      ts: Date.now(),
    };
    const targets = new Set<string>([e.senderId.toString()]);
    if (e.roomId != null) targets.add(`room:${e.roomId}`);
    ioRef.to([...targets]).emit('lucky_win', payload);
    if (e.multiplier > 0) ioRef.emit('lucky_broadcast', { ...payload, headline: e.multiplier >= broadcastMin });
  }
}

/** Rounds the sweeper closed: tell the room, and each waiting sender. */
export function emitLuckyRoundsClosed(
  closed: { roundId: number; code: string; roomId: number | null; status: string; pending: { rollId: number; senderId: number }[] }[],
) {
  if (!ioRef) return;
  for (const c of closed) {
    if (c.roomId != null) {
      ioRef.to(`room:${c.roomId}`).emit('lucky_round_closed', { roundCode: c.code, roomId: c.roomId, status: c.status });
    }
    for (const p of c.pending) {
      ioRef.to(p.senderId.toString()).emit('lucky_entry_closed', {
        rollId: p.rollId,
        roundCode: c.code,
        roomId: c.roomId,
        status: 'NO_COMPETITION',
      });
    }
  }
}

/** The HTTP view of the sender's own entry. `lucky` keeps its old meaning for
 *  installed apps (a drawn result, or absent); `luckyEntry` is the full state. */
function luckyResponse(own: LuckyRollResult | null) {
  if (!own) return { lucky: null, luckyEntry: null };
  const entry = {
    rollId: own.rollId,
    status: own.status,
    roundCode: own.roundCode,
    multiplier: own.multiplier,
    payoutCoins: own.payoutCoins,
    hostCoins: own.hostCoins,
    serverSeedHash: own.serverSeedHash,
  };
  return { lucky: own.status === 'PENDING' ? null : entry, luckyEntry: entry };
}

/** A22 — the centred "فلان أهدى <هدية> إلى فلان" bar. Room-scoped only. */
export function emitGiftAnnouncement(announcement: { roomId: number | null; [k: string]: any }) {
  if (!ioRef || announcement.roomId == null) return;
  ioRef.to(`room:${announcement.roomId}`).emit('gift_announcement', announcement);
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
        videoFallbackUrl: g.videoFallbackUrl,
        videoMeta: g.videoMeta,
        hasSound: g.hasSound,
        effectType: g.effectType,
        soundUrl: g.soundUrl,
        videoHasAlpha: g.videoHasAlpha,
        fireworksEnabled: g.fireworksEnabled,
        fireworksColors: g.fireworksColors,
        coinCost: g.coinCost,
        tier: g.tier,
        animationMs: g.animationMs,
        isComboEligible: g.isComboEligible,
        broadcastGlobal: g.broadcastGlobal,
        category: g.category,
        isLucky: isLuckyGift(g),
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
    const operation = operationRequest(req, senderId, res);
    const completed = await runGiftOperation(operation, async (context) => {
      const result = await sendGiftAtomic({
        senderId, recipientId: recipient,
        roomId: roomId != null ? Number(roomId) : null,
        giftId, quantity: quantity != null ? Number(quantity) : 1,
        comboKey: comboKey ?? null,
        clientRequestId: operation.id, operationId: operation.id,
      }, context);
      context.afterCommit.push(async () => {
        await flushGiftDeliveries();
        if (result.lucky) await emitLuckyOutcome({ own: result.lucky, settled: result.luckySettled, senderId, roomId: result.event.roomId });
        emitGiftAnnouncement({ ...result.event,
          senderName: result.event.sender?.name, senderAvatarUrl: result.event.sender?.avatarUrl,
          recipientName: result.event.recipient?.name, recipientCount: 1,
        });
        await maybeCreateRelationRequestFromRing({ senderId, receiverId: recipient, giftId });
      });
      return { success: true, transactionId: result.transactionId, senderBalance: result.senderBalance,
        comboCount: result.comboCount, broadcast: result.broadcast, ...luckyResponse(result.lucky) };
    });
    if (completed.replayed) res.setHeader('Idempotent-Replayed', 'true');
    return res.json(completed.body);
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
 * SPEC52 #9 (2026-10-20): self-support COUNTS, in the room cup and the app
 * cup alike (owner's decision, reversing the earlier rule). Each gift row is
 * one transaction and is summed exactly once, so there is no double count.
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
    user: withNameStyle(byId.get(r.senderId) ?? { id: r.senderId, name: 'Unknown', avatarUrl: null, displayId: null, level: 1, vipLevel: 0 }),
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

    // A14 — إجمالي دعم الروم, carried on the board response so the app does not
    // need a second round trip to draw the figure under the cup. The k/m
    // shortening is the client's job; this is the raw number and the window it
    // was measured over.
    const { roomSupportTotal, getRoomSupportWindowHours, pendingSupporterRewards } =
      await import('../services/roomReward.service');
    const [supportTotal, windowHours] = await Promise.all([
      roomSupportTotal(roomId),
      getRoomSupportWindowHours(),
    ]);

    // A15b — rungs THIS viewer can claim right now, so the board can draw the
    // "مكافأة لك" square next to their own name.
    const viewerId = (req as any).userId as number | undefined;
    const myRewards = viewerId ? await pendingSupporterRewards(viewerId, roomId) : [];
    // Room-cup rewards waiting under the owner's name (client 10/11 19:02).
    const { pendingRoomCupClaims } = await import('../services/roomReward.service');
    const myCupRewards = viewerId ? await pendingRoomCupClaims(viewerId, roomId) : [];

    return res.json({
      success: true,
      scope: 'room',
      roomId,
      range,
      board,
      supportTotal,
      supportWindowHours: windowHours,
      myRewards,
      myCupRewards,
    });
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
    const { giftId, recipientIds, roomId, quantity, comboKey, targetType } = req.body ?? {};
    if (typeof giftId !== 'string' || !giftId) throw new GiftSendError('INVALID_GIFT', 'giftId is required');
    const rid = roomId == null ? null : Number(roomId);
    if (rid != null && (!Number.isInteger(rid) || rid <= 0)) throw new GiftSendError('INVALID_ROOM', 'رقم الغرفة غير صالح');
    const operation = operationRequest(req, senderId, res);
    const completed = await runGiftOperation(operation, async (context) => {
      const { giftSeatSnapshot } = await import('../services/socket.service');
      let targets: Array<{ recipientId: number; seatNumber: number | null }>;
      if (targetType === 'all_mics') {
        if (rid == null) throw new GiftSendError('INVALID_ROOM', 'roomId is required');
        const room = await context.tx.room.findUnique({ where: { id: rid }, select: { ownerId: true } });
        if (!room) throw new GiftSendError('INVALID_ROOM', 'الغرفة غير موجودة', 404);
        const snapshot = giftSeatSnapshot(rid);
        const fingerprint = JSON.stringify(snapshot);
        targets = [...new Map(snapshot.map(s => [s.recipientId, s])).values()];
        if (!targets.some(s => s.recipientId === room.ownerId)) targets.push({ recipientId: room.ownerId, seatNumber: null });
        context.beforeCommit.push(() => {
          if (JSON.stringify(giftSeatSnapshot(rid)) !== fingerprint) throw new GiftSendError('SEATS_CHANGED', 'تغيّرت المايكات أثناء الإرسال، حاول مرة أخرى', 409);
        });
      } else {
        const ids = [...new Set<number>((Array.isArray(recipientIds) ? recipientIds : []).map(Number))];
        if (ids.some(id => !Number.isInteger(id) || id <= 0)) throw new GiftSendError('INVALID_RECIPIENT', 'مستلم غير صالح');
        const seats = rid == null ? [] : giftSeatSnapshot(rid);
        targets = ids.map(recipientId => ({ recipientId, seatNumber: seats.find(s => s.recipientId === recipientId)?.seatNumber ?? null }));
      }
      if (!targets.length || targets.length > 60) throw new GiftSendError('INVALID_RECIPIENTS', 'عدد المستلمين غير صالح');
      const sends: Awaited<ReturnType<typeof sendGiftAtomic>>[] = [];
      for (const target of targets) {
        sends.push(await sendGiftAtomic({ senderId, ...target, roomId: rid, giftId,
          quantity: quantity == null ? 1 : Number(quantity), comboKey: comboKey ?? null,
          targetType: targetType === 'all_mics' ? 'all_mics' : 'user', batchSize: targets.length,
          operationId: operation.id, clientRequestId: `${operation.id}:${target.recipientId}`,
          deferLucky: targets.length > 1,
        }, context));
      }
      // A lucky gift to several recipients is ONE entry: the stake is the whole
      // action (price × quantity × recipients) and so is the win (multiplier ×
      // that stake), drawn once — not one small draw per mic.
      let batchLucky: Awaited<ReturnType<typeof rollLucky>> | null = null;
      let senderBalance = sends[sends.length - 1]!.senderBalance;
      const stake = sends[0]!.gift.isLucky
        ? batchLuckyStake(sends.map(s => ({ transactionId: s.transactionId, recipientId: s.event.recipientId,
          totalCoins: s.totalCoins, recipientCoins: s.recipientCoins })))
        : null;
      if (stake) {
        batchLucky = await rollLucky(context.tx, { ...stake, senderId, roomId: rid, cfg: await getLuckyConfig() });
        if (batchLucky.settled.some((e) => e.senderId === senderId && e.payoutCoins > 0)) {
          const after = await context.tx.user.findUnique({ where: { id: senderId }, select: { coinsBalance: true } });
          senderBalance = after?.coinsBalance ?? senderBalance;
        }
      }
      context.afterCommit.push(async () => {
        await flushGiftDeliveries();
        if (batchLucky) {
          await emitLuckyOutcome({ own: batchLucky.own, settled: batchLucky.settled, senderId, roomId: rid, recipientCount: targets.length });
        }
        for (const result of sends) {
          if (result.lucky) await emitLuckyOutcome({ own: result.lucky, settled: result.luckySettled, senderId, roomId: rid });
          await maybeCreateRelationRequestFromRing({ senderId, receiverId: result.event.recipientId, giftId });
        }
        const first = sends[0]!;
        emitGiftAnnouncement({ ...first.event, senderName: first.event.sender?.name,
          senderAvatarUrl: first.event.sender?.avatarUrl,
          recipientName: targets.length === 1 ? first.event.recipient?.name : null,
          recipientCount: targets.length, totalCoins: sends.reduce((n, s) => n + s.totalCoins, 0) });
      });
      return { success: true, operationId: operation.id, sent: sends.length, requested: targets.length,
        senderBalance, broadcast: sends.some(s => s.broadcast),
        results: sends.map(s => ({ recipientId: s.event.recipientId, transactionId: s.transactionId })), failures: [],
        ...(batchLucky ? luckyResponse(batchLucky.own) : {}) };
    });
    if (completed.replayed) res.setHeader('Idempotent-Replayed', 'true');
    return res.json(completed.body);
  } catch (err) {
    if (err instanceof GiftSendError) return res.status(err.status).json({ success: false, code: err.code, message: err.message });
    console.error('[gifts.sendBatch]', err);
    return res.status(500).json({ success: false, message: 'Send failed' });
  }
}

/**
 * A15b — POST /gifts/supporter-rewards/:id/claim — the "مكافأة لك" button.
 */
export async function claimSupporterRewardHandler(req: Request, res: Response) {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const rewardId = Number(req.params.id);
    if (!Number.isFinite(rewardId)) return res.status(400).json({ success: false, message: 'Invalid reward id' });

    const { claimSupporterReward, SupporterRewardError } = await import('../services/roomReward.service');
    try {
      const { coins } = await claimSupporterReward(userId, rewardId);
      return res.json({ success: true, coins, message: `تم إضافة ${coins} كوينز إلى محفظتك` });
    } catch (e: any) {
      if (e instanceof SupporterRewardError) {
        return res.status(e.status).json({ success: false, message: e.message });
      }
      throw e;
    }
  } catch (err) {
    console.error('[gifts.claimSupporterReward]', err);
    return res.status(500).json({ success: false, message: 'Failed to claim reward' });
  }
}

/** POST /gifts/room-cup-claims/:id/claim — «استلم» under the owner's name in the cup. */
export async function claimRoomCupRewardHandler(req: Request, res: Response) {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const claimId = Number(req.params.id);
    if (!Number.isInteger(claimId) || claimId <= 0) return res.status(400).json({ success: false, message: 'Invalid claim id' });
    const { claimRoomCupReward, SupporterRewardError } = await import('../services/roomReward.service');
    try {
      const { coins } = await claimRoomCupReward(userId, claimId);
      return res.json({ success: true, coins, message: `تم إضافة ${coins} كوينز إلى محفظتك` });
    } catch (e: any) {
      if (e instanceof SupporterRewardError) return res.status(e.status).json({ success: false, message: e.message });
      throw e;
    }
  } catch (err) {
    console.error('[gifts.claimRoomCupReward]', err);
    return res.status(500).json({ success: false, message: 'Failed to claim reward' });
  }
}

// GET /gifts/lucky/rolls/:id — the proof behind one roll. Public: the whole
// point is that anyone can check it.
export async function luckyRollProof(req: Request, res: Response) {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ success: false, message: 'id' });
    const roll = await prisma.luckyRoll.findUnique({
      where: { id },
      select: {
        id: true, senderId: true, recipientId: true, roomId: true, giftCoins: true, hostCoins: true,
        multiplier: true, payoutCoins: true, serverSeed: true, serverSeedHash: true, tiersSnapshot: true, createdAt: true,
        roundId: true, giftTxId: true, status: true, settledAt: true,
      },
    });
    if (!roll) return res.status(404).json({ success: false, message: 'not found' });
    // A pending entry's seed is its draw: it stays secret until the draw.
    if (roll.status === 'PENDING') {
      const { serverSeed: _hidden, ...rest } = roll;
      return res.json({ success: true, roll: rest, verification: null });
    }
    return res.json({ success: true, roll, verification: verifyRoll(roll) });
  } catch (err) {
    console.error('[gifts.luckyRollProof]', err);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
}

// GET /gifts/lucky/recent — the last wins, for the ticker's cold start (a
// phone that just opened the app has no socket history).
export async function luckyRecent(_req: Request, res: Response) {
  try {
    const { broadcastMin } = await getLuckySettings();
    const rolls = await prisma.luckyRoll.findMany({
      where: { multiplier: { gte: Math.max(1, broadcastMin) } },
      orderBy: { createdAt: 'desc' },
      take: 20,
      select: { id: true, senderId: true, recipientId: true, roomId: true, giftCoins: true, hostCoins: true, multiplier: true, payoutCoins: true, createdAt: true },
    });
    const userIds = [...new Set(rolls.flatMap((r) => [r.senderId, r.recipientId]))];
    const users = await prisma.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true, avatarUrl: true } });
    const byId = new Map(users.map((u) => [u.id, u]));
    return res.json({
      success: true,
      items: rolls.map((r) => ({
        rollId: r.id,
        senderId: r.senderId,
        senderName: byId.get(r.senderId)?.name ?? null,
        senderAvatarUrl: byId.get(r.senderId)?.avatarUrl ?? null,
        recipientId: r.recipientId,
        recipientName: byId.get(r.recipientId)?.name ?? null,
        roomId: r.roomId,
        giftCoins: r.giftCoins,
        hostCoins: r.hostCoins,
        multiplier: r.multiplier,
        payoutCoins: r.payoutCoins,
        ts: r.createdAt.getTime(),
      })),
    });
  } catch (err) {
    console.error('[gifts.luckyRecent]', err);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
}
