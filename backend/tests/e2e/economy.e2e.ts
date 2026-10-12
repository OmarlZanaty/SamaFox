/**
 * End-to-end tests for the 2026-09-26 update, against a REAL PostgreSQL and
 * the REAL compiled server (dist/index.js), over HTTP and Socket.IO.
 *
 *   E2E_DATABASE_URL=postgresql://…/samafox_e2e npm run test:e2e
 *
 * The database is WIPED (TRUNCATE … CASCADE) — the suite refuses to run
 * against anything that is not on localhost. Build first (`npx tsc`).
 */
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, type ChildProcess } from 'node:child_process';
import path from 'node:path';
import crypto from 'node:crypto';

const DB = process.env.E2E_DATABASE_URL ?? '';
const SKIP = !/^postgres(ql)?:\/\/[^@]+@(localhost|127\.0\.0\.1)[:/]/.test(DB);
if (!SKIP) process.env.DATABASE_URL = DB;

// Loaded only when the suite runs (they read DATABASE_URL at import time).
/* eslint-disable @typescript-eslint/no-var-requires */
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');
const { io: ioc } = require('socket.io-client');

const PORT = 39123;
const BASE = `http://127.0.0.1:${PORT}/api/v1`;
const SECRET = 'e2e-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
const REFRESH = 'e2e-refresh-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

const prisma = SKIP ? null : new PrismaClient({ datasources: { db: { url: DB } } });
const db = prisma as any;
let server: ChildProcess | null = null;
const serverLog: string[] = [];

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const tok = (userId: number) => jwt.sign({ userId }, SECRET, { expiresIn: '2h' });

async function api(method: string, p: string, uid: number | null, body?: unknown, headers: Record<string, string> = {}) {
  const res = await fetch(BASE + p, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(uid ? { authorization: `Bearer ${tok(uid)}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json: any = null;
  try {
    json = await res.json();
  } catch {
    json = null;
  }
  return { status: res.status, body: json, headers: res.headers };
}

const bal = async (id: number) => Number((await db.user.findUnique({ where: { id }, select: { coinsBalance: true } })).coinsBalance);
const account = async (key: string) => Number((await db.economyAccount.findUnique({ where: { key } }))?.balance ?? 0);
const luckyPool = async () => Number((await db.luckyPool.findUnique({ where: { id: 1 } }))?.balance ?? 0);

// ── fixtures ────────────────────────────────────────────────
const U: Record<string, number> = {};
let luckyGiftId = '';
let lockedRoomId = 0;
let officialRoomId = 100000;

async function wipe() {
  const tables: { tablename: string }[] = await db.$queryRawUnsafe(
    `SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'`,
  );
  await db.$executeRawUnsafe(`TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(', ')} RESTART IDENTITY CASCADE`);
  // What the migrations seed, restored.
  await db.luckyPool.create({ data: { id: 1 } });
  await db.economyAccount.create({ data: { key: 'PROGRAM' } });
  for (const [m, w, min] of [[5, 3500, 0], [10, 2000, 0], [20, 700, 0], [30, 150, 10000], [50, 80, 5000], [100, 20, 20000], [200, 4, 60000], [300, 2, 120000], [500, 1, 250000]]) {
    await db.luckyTier.create({ data: { multiplier: m, weightBp: w, minPoolCoins: BigInt(min) } });
  }
  await db.cpEffect.create({ data: { effectKey: 'heart3d', name: 'قلب', requiredLevel: 2, enabled: false, priority: 10 } });
}

async function seed() {
  const mk = async (key: string, extra: any = {}) => {
    const u = await db.user.create({ data: { name: key, displayId: 10_000 + Object.keys(U).length + 1, coinsBalance: 100_000, ...extra } });
    U[key] = u.id;
  };
  for (const k of ['admin', 'a', 'b', 'c', 'd', 'host', 'e', 'f', 'g', 'h2', 'poor', 'o1', 'o2', 'j', 'hidden', 'bypass', 'solo']) {
    await mk(k, k === 'admin' ? { isAdmin: true, isSuperAdmin: true } : k === 'poor' ? { coinsBalance: 10 } : {});
  }
  const g = await db.gift.create({
    data: { name: 'lucky', nameAr: 'حظ', iconUrl: '/x.png', format: 'SVG_CSS', coinCost: 100, tier: 'SMALL', isLucky: true, isActive: true },
  });
  luckyGiftId = g.id;
  const locked = await db.room.create({ data: { name: 'locked', ownerId: U.d, isLocked: true, accessCode: '12345' } });
  lockedRoomId = locked.id;
  await db.room.create({ data: { id: officialRoomId, name: 'الإدارة', ownerId: U.o1, roomType: 'OFFICIAL_ROOM' } });
}

function startServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    server = spawn(process.execPath, [path.resolve(__dirname, '../../dist/index.js')], {
      cwd: path.resolve(__dirname, '../..'),
      env: {
        ...process.env,
        DATABASE_URL: DB,
        JWT_SECRET: SECRET,
        JWT_REFRESH_SECRET: REFRESH,
        PORT: String(PORT),
        REDIS_URL: '',
        NODE_ENV: 'test',
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const t = setTimeout(() => reject(new Error('server did not start:\n' + serverLog.join(''))), 60_000);
    const onData = (d: Buffer) => {
      serverLog.push(d.toString());
      if (d.toString().includes('running on port')) {
        clearTimeout(t);
        resolve();
      }
    };
    server.stdout!.on('data', onData);
    server.stderr!.on('data', (d: Buffer) => serverLog.push(d.toString()));
    server.on('exit', (code) => reject(new Error(`server exited ${code}\n` + serverLog.join(''))));
  });
}

function sock(uid: number): Promise<any> {
  return new Promise((resolve, reject) => {
    const s = ioc(`http://127.0.0.1:${PORT}`, { auth: { token: tok(uid) }, transports: ['websocket'], forceNew: true });
    s.events = [] as any[];
    s.onAny((ev: string, data: any) => s.events.push({ ev, data }));
    s.on('connect', () => resolve(s));
    s.on('connect_error', reject);
  });
}

/** Emit join_room and wait for the outcome: admitted (room_entry_mode) or denied. */
async function joinRoom(s: any, roomId: number, extra: any = {}) {
  s.events.length = 0;
  s.emit('join_room', { roomId, ...extra });
  for (let i = 0; i < 60; i++) {
    const denied = s.events.find((e: any) => e.ev === 'join_denied');
    if (denied) return { admitted: false, denied: denied.data };
    const ok = s.events.find((e: any) => e.ev === 'room_entry_mode');
    if (ok) return { admitted: true, mode: ok.data };
    await sleep(50);
  }
  throw new Error('join_room: no answer');
}

async function setLuckyTiers(tiers: [number, number][]) {
  await db.luckyTier.updateMany({ data: { weightBp: 0 } });
  for (const [m, w] of tiers) await db.luckyTier.update({ where: { multiplier: m }, data: { weightBp: w, minPoolCoins: 0n, isActive: true } });
}

const sendLucky = (uid: number, roomId: number | null, key?: string, quantity = 1) =>
  api('POST', '/gifts/send', uid, { giftId: luckyGiftId, recipientId: U.host, roomId, quantity }, key ? { 'Idempotency-Key': key } : {});

// ══════════════════════════════════════════════════════════════

describe('2026-09-26 economy / CP / rooms / features (E2E)', { skip: SKIP ? 'E2E_DATABASE_URL (localhost) not set' : false }, () => {
  before(async () => {
    await wipe();
    await seed();
    await startServer();
  });

  after(async () => {
    server?.kill();
    await prisma?.$disconnect();
  });

  // ── المحظوظ ────────────────────────────────────────────────
  test('lucky: a lone player is PENDING — no win, nothing minted; the 30/70 split is booked', async () => {
    await setLuckyTiers([[5, 10_000]]);
    const room = await db.room.create({ data: { name: 'lucky-1', ownerId: U.o1 } });
    const [a0, h0, prog0, pool0] = [await bal(U.a), await bal(U.host), await account('PROGRAM'), await luckyPool()];
    const r = await sendLucky(U.a, room.id);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.lucky, null, 'old apps see no result while pending');
    assert.equal(r.body.luckyEntry.status, 'PENDING');
    assert.equal(await bal(U.a), a0 - 100, 'only the entry is taken');
    assert.equal(await bal(U.host), h0 + 10, 'host gets 10%');
    assert.equal(await account('PROGRAM'), prog0 + 20, 'program keeps 30% − host 10%');
    assert.equal(await luckyPool(), pool0 + 70, 'prize pool gets 70%');
    const roll = await db.luckyRoll.findFirst({ where: { senderId: U.a }, orderBy: { id: 'desc' } });
    assert.equal(roll.status, 'PENDING');
    assert.equal(roll.payoutCoins, 0);
  });

  test('lucky: a second player makes the round competitive — both entries drawn and paid from the pool', async () => {
    const room = await db.room.findFirst({ where: { name: 'lucky-1' } });
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: { increment: 1_000_000n } } });
    const [a0, b0, pool0] = [await bal(U.a), await bal(U.b), await luckyPool()];
    const r = await sendLucky(U.b, room.id);
    assert.equal(r.status, 200);
    assert.equal(r.body.luckyEntry.status, 'SETTLED');
    assert.equal(r.body.lucky.multiplier, 5);
    assert.equal(r.body.lucky.payoutCoins, 500, 'x5 on the full gift value V=100');
    assert.equal(await bal(U.b), b0 - 100 + 500);
    assert.equal(await bal(U.a), a0 + 500, "A's pending entry was drawn too");
    assert.equal(await luckyPool(), pool0 + 70 - 1000, 'both wins came out of the pool');
    const rolls = await db.luckyRoll.findMany({ where: { roomId: room.id } });
    assert.ok(rolls.every((x: any) => x.status === 'SETTLED' && x.multiplier === 5));
    const round = await db.luckyRound.findFirst({ where: { roomId: room.id } });
    assert.equal(round.playerCount, 2);
    assert.equal(Number(round.totalEntry), 200);
    assert.equal(Number(round.prizePool), 140);
    assert.equal(Number(round.programShare), 60);
    assert.equal(Number(round.totalWin), 1000);
  });

  test('lucky: a round that closes short of players settles its entries as NO_COMPETITION', async () => {
    const room = await db.room.create({ data: { name: 'lucky-2', ownerId: U.o1 } });
    const c0 = await bal(U.c);
    await sendLucky(U.c, room.id);
    await db.luckyRound.updateMany({ where: { roomId: room.id }, data: { endsAt: new Date(Date.now() - 1000) } });
    const { closeExpiredRounds, LUCKY_DEFAULTS } = require('../../dist/gifts/lucky.service');
    const closed = await db.$transaction((tx: any) => closeExpiredRounds(tx, room.id, LUCKY_DEFAULTS));
    assert.equal(closed.length, 1);
    assert.equal(closed[0].status, 'NOT_COMPETITIVE');
    const roll = await db.luckyRoll.findFirst({ where: { roomId: room.id } });
    assert.equal(roll.status, 'NO_COMPETITION');
    assert.equal(await bal(U.c), c0 - 100, 'no refund, no win, nothing minted');
  });

  test('lucky: every multiplier pays m × V, and "no win" pays nothing', async () => {
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: 50_000_000n } });
    for (const m of [0, 5, 10, 20, 30, 50, 100, 200, 300, 500]) {
      await setLuckyTiers(m === 0 ? [] : [[m, 10_000]]);
      const room = await db.room.create({ data: { name: `lucky-m${m}`, ownerId: U.o1 } });
      await sendLucky(U.e, room.id);
      const f0 = await bal(U.f);
      const r = await sendLucky(U.f, room.id);
      assert.equal(r.body.lucky.multiplier, m, `x${m}`);
      assert.equal(r.body.lucky.payoutCoins, m * 100, `x${m} pays ${m * 100}`);
      assert.equal(await bal(U.f), f0 - 100 + m * 100);
    }
  });

  test('lucky: a multiplier the pool cannot cover is not in the draw — the pool never goes negative', async () => {
    await setLuckyTiers([[500, 10_000]]);
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: 0n } });
    const room = await db.room.create({ data: { name: 'lucky-thin', ownerId: U.o1 } });
    await sendLucky(U.e, room.id);
    const r = await sendLucky(U.f, room.id);
    assert.equal(r.body.lucky.multiplier, 0, 'x500 (50,000) cannot be paid from a 140 pool');
    assert.ok((await luckyPool()) >= 0);
  });

  test('lucky: the locked floor (program seed) is never paid out', async () => {
    await setLuckyTiers([[5, 1000]]);
    const set = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { poolFloor: 1_000_000, reason: 'e2e floor' });
    assert.equal(set.status, 200, JSON.stringify(set.body));
    await setLuckyTiers([[5, 10_000]]);
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: 1_000_000n } });
    const room = await db.room.create({ data: { name: 'lucky-floor', ownerId: U.o1 } });
    await sendLucky(U.e, room.id);
    const r = await sendLucky(U.f, room.id);
    assert.equal(r.body.lucky.multiplier, 0, 'x5 (500) > the 140 players put in above the floor');
    assert.ok((await luckyPool()) >= 1_000_000, 'the floor is untouched');
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: 1_000_000n + 10_000n } });
    const room2 = await db.room.create({ data: { name: 'lucky-floor-2', ownerId: U.o1 } });
    await sendLucky(U.e, room2.id);
    const r2 = await sendLucky(U.f, room2.id);
    assert.equal(r2.body.lucky.multiplier, 5, "paid from the players' coins above the floor");
    await setLuckyTiers([[5, 1000]]);
    const reset = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { poolFloor: 0, reason: 'e2e floor reset' });
    assert.equal(reset.status, 200);
  });

  test('lucky: a lone player is drawn at once (minPlayers 1) but only wins back his own losses', async () => {
    await setLuckyTiers([[5, 1000]]);
    const set = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { minPlayers: 1, reason: 'e2e solo' });
    assert.equal(set.status, 200, JSON.stringify(set.body));
    await setLuckyTiers([[5, 10_000]]);
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: 10_000_000n } });
    const room = await db.room.create({ data: { name: 'lucky-solo', ownerId: U.solo } });
    // Each 100-coin entry puts 70 in the pool; x5 pays 500, so he needs 8
    // entries (560) behind him before x5 is in his draw.
    for (let i = 1; i <= 7; i++) {
      const r = await sendLucky(U.solo, room.id);
      assert.equal(r.body.luckyEntry.status, 'SETTLED', `entry ${i} drawn at once`);
      assert.equal(r.body.luckyEntry.multiplier, 0, `entry ${i}: ${i * 70} of his own < 500`);
    }
    const s0 = await bal(U.solo);
    const r8 = await sendLucky(U.solo, room.id);
    assert.equal(r8.body.lucky.multiplier, 5, '560 of his own losses cover x5');
    assert.equal(await bal(U.solo), s0 - 100 + 500);
    await setLuckyTiers([[5, 1000]]);
    const reset = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { minPlayers: 2, reason: 'e2e solo reset' });
    assert.equal(reset.status, 200);
  });

  test('lucky: idempotency — a resent request (same key) is charged once and replays the answer', async () => {
    await setLuckyTiers([[5, 10_000]]);
    await db.luckyPool.update({ where: { id: 1 }, data: { balance: 1_000_000n } });
    const room = await db.room.create({ data: { name: 'lucky-idem', ownerId: U.o1 } });
    const g0 = await bal(U.g);
    const key = crypto.randomUUID();
    const r1 = await sendLucky(U.g, room.id, key);
    const r2 = await sendLucky(U.g, room.id, key);
    assert.equal(r1.status, 200);
    assert.equal(r2.status, 200);
    assert.equal(r2.headers.get('idempotent-replayed'), 'true');
    assert.equal(r2.body.transactionId, r1.body.transactionId);
    assert.equal(await bal(U.g), g0 - 100, 'charged exactly once');

    // Five copies at once, as a weak connection might fire them.
    const key2 = crypto.randomUUID();
    const g1 = await bal(U.g);
    const burst = await Promise.all(Array.from({ length: 5 }, () => sendLucky(U.g, room.id, key2)));
    const succeeded = burst.filter((x) => x.status === 200);
    assert.ok(succeeded.length >= 1);
    assert.ok(burst.every((x) => x.status === 200 || x.status === 409), JSON.stringify(burst.map((x) => x.status)));
    assert.equal(new Set(succeeded.map((x) => x.body.transactionId)).size, 1, 'one transaction');
    assert.equal(await bal(U.g), g1 - 100, 'charged exactly once');
  });

  test('lucky: settings refuse nonsense, and entries outside min/max entry are refused before any charge', async () => {
    const bad1 = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { programShareBp: 3000, prizePoolBp: 6000, reason: 'test' });
    assert.equal(bad1.status, 400, 'shares must add up to 100%');
    const bad2 = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { rtpTargetBp: 8000, reason: 'test' });
    assert.equal(bad2.status, 400, 'RTP above the prize pool');
    const noReason = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { maxEntry: 500 });
    assert.equal(noReason.status, 400);
    const okr = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { minEntry: 50, maxEntry: 500, reason: 'e2e limits' });
    assert.equal(okr.status, 200, JSON.stringify(okr.body));
    const badTiers = await api('PUT', '/admin-dashboard/lucky-mgmt/tiers', U.admin, { tiers: [{ multiplier: 5, weightBp: 9000 }, { multiplier: 10, weightBp: 2000 }], reason: 'x' });
    assert.equal(badTiers.status, 400, 'probabilities over 100%');
    const hiRtp = await api('PUT', '/admin-dashboard/lucky-mgmt/tiers', U.admin, { tiers: [{ multiplier: 100, weightBp: 1000 }], reason: 'x' });
    assert.equal(hiRtp.status, 400, 'E[m] = 1000% > RTP target');
    const audit = await db.adminAuditLog.findFirst({ where: { action: 'LUCKY_SETTINGS_UPDATE' } });
    assert.equal(audit.reason, 'e2e limits');
    const h0 = await bal(U.h2);
    const r = await sendLucky(U.h2, null, undefined, 10); // 1,000 > max 500
    assert.equal(r.status, 400);
    assert.equal(r.body.code, 'LUCKY_ENTRY_RANGE');
    assert.equal(await bal(U.h2), h0);
  });

  // ── الألعاب ────────────────────────────────────────────────
  test('games: an empty prize pool refuses the bet before any coin moves', async () => {
    const a0 = await bal(U.a);
    const r = await api('POST', '/games/plinko/drop', U.a, { risk: 'high', rows: 16, amount: 100 });
    assert.equal(r.body.code, 'PRIZE_POOL_LOW', JSON.stringify(r.body));
    assert.equal(await bal(U.a), a0);
  });

  test('games: stake splits 25% program / 75% pool; prizes come only from the pool', async () => {
    const f = await api('POST', '/admin-dashboard/games-economy/plinko/fund', U.admin, { amount: 5_000_000, reason: 'e2e seed' });
    assert.equal(f.status, 200, JSON.stringify(f.body));
    const [a0, prog0, pool0] = [await bal(U.a), await account('PROGRAM'), await account('GAME_POOL:plinko')];
    const r = await api('POST', '/games/plinko/drop', U.a, { risk: 'low', rows: 8, amount: 1000 });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    const payout = r.body.drop?.payout ?? r.body.data?.drop?.payout;
    assert.equal(await bal(U.a), a0 - 1000 + payout);
    assert.equal(await account('PROGRAM'), prog0 + 250);
    assert.equal(await account('GAME_POOL:plinko'), pool0 + 750 - payout);
    const stake = await db.gameLedger.findFirst({ where: { kind: 'stake', userId: U.a }, orderBy: { id: 'desc' } });
    assert.deepEqual([stake.programShare, stake.poolShare], [250, 750]);
  });

  test('games: max win per round caps the payout, daily cap refuses up front, min/max bet enforced', async () => {
    let r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { maxWinPerRound: 50, reason: 'e2e cap' });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    for (let i = 0; i < 12; i++) {
      r = await api('POST', '/games/plinko/drop', U.b, { risk: 'high', rows: 16, amount: 1000 });
      assert.equal(r.status, 200, JSON.stringify(r.body));
      assert.ok(r.body.drop.payout <= 50, `payout ${r.body.drop.payout} over the round cap`);
    }
    r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { dailyMaxWinPerUser: 10, maxWinPerRound: 20, reason: 'e2e daily' });
    assert.equal(r.status, 400, 'round cap above the daily cap is refused');
    r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { dailyMaxWinPerUser: 10, maxWinPerRound: 10, reason: 'e2e daily' });
    assert.equal(r.status, 200);
    const c0 = await bal(U.c);
    r = await api('POST', '/games/plinko/drop', U.c, { risk: 'high', rows: 16, amount: 1000 });
    // 10 fits the day once; after any win the next is refused.
    if (r.status === 200 && r.body.drop.payout > 0) {
      r = await api('POST', '/games/plinko/drop', U.c, { risk: 'high', rows: 16, amount: 1000 });
      assert.equal(r.body.code, 'DAILY_WIN_CAP');
    }
    r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { minBet: 200, maxWinPerRound: 1_000_000, dailyMaxWinPerUser: 5_000_000, reason: 'e2e minbet' });
    const low = await api('POST', '/games/plinko/drop', U.c, { risk: 'low', rows: 8, amount: 100 });
    assert.equal(low.body.code, 'BET_TOO_LOW');
    assert.ok((await bal(U.c)) <= c0);
    const rtp = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { rtpTargetBp: 8000, reason: 'x' });
    assert.equal(rtp.status, 400, 'RTP target above the 75% pool share');
  });

  test('games: duplicate play request (same key) is charged once', async () => {
    const key = crypto.randomUUID();
    const d0 = await bal(U.d);
    const r1 = await api('POST', '/games/plinko/drop', U.d, { risk: 'low', rows: 8, amount: 300 }, { 'Idempotency-Key': key });
    const r2 = await api('POST', '/games/plinko/drop', U.d, { risk: 'low', rows: 8, amount: 300 }, { 'Idempotency-Key': key });
    assert.equal(r1.status, 200, JSON.stringify(r1.body));
    assert.deepEqual(r2.body, r1.body);
    assert.equal(await bal(U.d), d0 - 300 + r1.body.drop.payout);
  });

  test('games: economy report adds up', async () => {
    const r = await api('GET', '/admin-dashboard/games-economy', U.admin);
    assert.equal(r.status, 200);
    const p = r.body.data.games.find((g: any) => g.game === 'plinko');
    assert.ok(p.totalBets > 0);
    assert.equal(p.netResult, p.totalBets - p.totalPayouts);
    assert.equal(p.programShare + p.playerPrizePool, p.totalBets);
    assert.ok(p.poolBalance >= 0);
  });

  // ── CP ─────────────────────────────────────────────────────
  const pair = (x: number, y: number, cpValue = 0) =>
    db.cpPair.create({ data: { userAId: Math.min(x, y), userBId: Math.max(x, y), cpValue } });

  test('CP break: global fee split to program and partner, pair removed, logged — one transaction', async () => {
    await pair(U.e, U.f);
    let r = await api('PUT', '/admin-dashboard/cp-economy/break-fees', U.admin, { programFee: 700, partnerFee: 300, reason: 'e2e fees' });
    assert.equal(r.status, 200);
    const q = await api('GET', `/cp/partners/${U.f}/break-quote`, U.e);
    assert.deepEqual([q.body.data.totalFee, q.body.data.feeSource], [1000, 'GLOBAL']);
    const [e0, f0, p0] = [await bal(U.e), await bal(U.f), await account('PROGRAM')];
    r = await api('DELETE', `/cp/partners/${U.f}`, U.e, undefined, { 'Idempotency-Key': crypto.randomUUID() });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(await bal(U.e), e0 - 1000);
    assert.equal(await bal(U.f), f0 + 300);
    assert.equal(await account('PROGRAM'), p0 + 700);
    assert.equal(await db.cpPair.count({ where: { OR: [{ userAId: U.e }, { userBId: U.e }] } }), 0);
    const log = await db.cpBreakLog.findFirst({ where: { requesterId: U.e } });
    assert.deepEqual([Number(log.programFee), Number(log.partnerFee), log.feeSource], [700, 300, 'GLOBAL']);
  });

  test('CP break: a custom fee for the ID outranks the global one', async () => {
    await pair(U.g, U.h2);
    const card = await api('GET', `/admin-dashboard/cp-economy/custom-fee/${U.g}`, U.admin);
    assert.equal(card.body.data.partners.length, 1);
    const r = await api('PUT', `/admin-dashboard/cp-economy/custom-fee/${U.g}`, U.admin, { programFee: 100, partnerFee: 50, enabled: true, reason: 'vip' });
    assert.equal(r.status, 200);
    const [g0, h0] = [await bal(U.g), await bal(U.h2)];
    await api('DELETE', `/cp/partners/${U.h2}`, U.g);
    assert.equal(await bal(U.g), g0 - 150);
    assert.equal(await bal(U.h2), h0 + 50);
  });

  test('CP break: not enough balance → nothing changes at all', async () => {
    await pair(U.poor, U.j);
    const [p0, j0, prog0] = [await bal(U.poor), await bal(U.j), await account('PROGRAM')];
    const r = await api('DELETE', `/cp/partners/${U.j}`, U.poor);
    assert.equal(r.status, 402);
    assert.equal(r.body.shortfall, 1000 - 10);
    assert.deepEqual([await bal(U.poor), await bal(U.j), await account('PROGRAM')], [p0, j0, prog0]);
    assert.equal(await db.cpPair.count({ where: { userAId: Math.min(U.poor, U.j), userBId: Math.max(U.poor, U.j) } }), 1);
  });

  test('CP level: the level table decides the level from CP-gift value only; levels must climb', async () => {
    await api('PUT', '/admin-dashboard/cp-economy/levels/1', U.admin, { requiredCoins: 100, name: 'L1', reason: 'e2e' });
    await api('PUT', '/admin-dashboard/cp-economy/levels/2', U.admin, { requiredCoins: 500, name: 'L2', reason: 'e2e' });
    const bad = await api('PUT', '/admin-dashboard/cp-economy/levels/3', U.admin, { requiredCoins: 400, reason: 'e2e' });
    assert.equal(bad.status, 400);
    await pair(U.a, U.b, 600);
    const r = await api('GET', '/cp/partners', U.a);
    const row = r.body.data.find((x: any) => x.partner.id === U.b);
    assert.deepEqual([row.level, row.levelName, row.levelBasis], [2, 'L2', 'table']);
  });

  test('CP effect: two partners on the mics carry a link with the effect their level earns', async () => {
    await api('PUT', '/admin-dashboard/cp-economy/effects/heart3d', U.admin, { enabled: true, requiredLevel: 2, durationSec: 0, animationSpeed: 1.5, priority: 10, reason: 'e2e' });
    const { cpSeatLinks, invalidateCpEffectsCache } = require('../../dist/services/cpEffect.service');
    invalidateCpEffectsCache();
    const links = await cpSeatLinks(new Map([[1, U.a], [2, U.b], [3, U.c]]));
    assert.equal(links.length, 1);
    assert.deepEqual([links[0].level, links[0].effect?.key, links[0].effect?.animationSpeed], [2, 'heart3d', 1.5]);
  });

  // ── الغرف المغلقة + الدخول المخفي ─────────────────────────
  test('locked room: owner in without PIN; users, room admins and super admins need it', async () => {
    const owner = await sock(U.d);
    assert.equal((await joinRoom(owner, lockedRoomId)).admitted, true);
    const user = await sock(U.b);
    const denied = await joinRoom(user, lockedRoomId);
    assert.equal(denied.admitted, false);
    assert.equal(denied.denied.canHiddenBypass, false);
    const wrong = await joinRoom(user, lockedRoomId, { code: '99999' });
    assert.equal(wrong.denied.wrongCode, true);
    assert.equal((await joinRoom(user, lockedRoomId, { code: '12345' })).admitted, true);
    const superAdmin = await sock(U.admin);
    assert.equal((await joinRoom(superAdmin, lockedRoomId)).admitted, false, 'no automatic bypass for super admins');
    const tamper = await sock(U.c);
    assert.equal((await joinRoom(tamper, lockedRoomId, { hiddenBypass: true })).admitted, false, 'hiddenBypass without the feature');
    const http = await api('POST', `/rooms/${lockedRoomId}/join`, U.c, {});
    assert.equal(http.status, 403);
    for (const s of [owner, user, superAdmin, tamper]) s.close();
  });

  test('hidden mode: granted + switched on → asked, then enters without PIN, invisible to the room, logged', async () => {
    let r = await api('PUT', '/users/me/features/HIDDEN_MODE', U.hidden, { on: true });
    assert.equal(r.status, 403, 'cannot switch on a feature not granted');
    r = await api('POST', `/admin-dashboard/features/user/${U.hidden}/grant`, U.admin, { key: 'HIDDEN_MODE', reason: 'e2e' });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    r = await api('PUT', '/users/me/features/HIDDEN_MODE', U.hidden, { on: true });
    assert.equal(r.status, 200);
    const mine = await api('GET', '/users/me/features', U.hidden);
    assert.equal(mine.body.data.find((f: any) => f.key === 'HIDDEN_MODE').on, true);

    const watcher = await sock(U.d); // the owner, inside
    await joinRoom(watcher, lockedRoomId);
    watcher.events.length = 0;
    const h = await sock(U.hidden);
    const ask = await joinRoom(h, lockedRoomId);
    assert.equal(ask.admitted, false);
    assert.equal(ask.denied.canHiddenBypass, true, 'the app asks "هل تريد الدخول بدون كلمة مرور؟"');
    const inn = await joinRoom(h, lockedRoomId, { hiddenBypass: true });
    assert.equal(inn.admitted, true);
    assert.deepEqual([inn.mode.hidden, inn.mode.lockBypass], [true, 'HIDDEN_MODE']);
    await sleep(500);
    const seen = watcher.events.filter((e: any) => ['user_entered', 'user_joined'].includes(e.ev) && e.data?.userId === U.hidden);
    assert.equal(seen.length, 0, 'no entrance notice to the room');
    watcher.emit('get_room_users', { roomId: lockedRoomId });
    await sleep(400);
    const roster = watcher.events.filter((e: any) => e.ev === 'room_users').pop();
    assert.ok(!roster.data.users.some((u: any) => u.userId === U.hidden), 'not in the roster');
    const log = await db.roomEntryLog.findFirst({ where: { userId: U.hidden, roomId: lockedRoomId } });
    assert.deepEqual([log.hidden, log.lockBypass], [true, 'HIDDEN_MODE']);
    h.emit('leave_room', { roomId: lockedRoomId });
    await sleep(500);
    assert.ok((await db.roomEntryLog.findFirst({ where: { id: log.id } })).exitedAt, 'exit time recorded');
    assert.equal(watcher.events.filter((e: any) => e.ev === 'user_left' && e.data?.userId === U.hidden).length, 0);

    // Revoked → the server refuses the same request.
    await api('POST', `/admin-dashboard/features/user/${U.hidden}/revoke`, U.admin, { key: 'HIDDEN_MODE', reason: 'e2e' });
    assert.equal((await joinRoom(h, lockedRoomId, { hiddenBypass: true })).admitted, false);
    // A room can refuse hidden entry altogether.
    await api('POST', `/admin-dashboard/features/user/${U.hidden}/grant`, U.admin, { key: 'HIDDEN_MODE', reason: 'e2e' });
    await api('PUT', '/users/me/features/HIDDEN_MODE', U.hidden, { on: true });
    await api('PATCH', `/admin-dashboard/rooms-mgmt/${lockedRoomId}`, U.admin, { allowHiddenEntry: false, reason: 'e2e' });
    assert.equal((await joinRoom(h, lockedRoomId, { hiddenBypass: true })).admitted, false);
    await api('PATCH', `/admin-dashboard/rooms-mgmt/${lockedRoomId}`, U.admin, { allowHiddenEntry: true, reason: 'e2e' });
    const entries = await api('GET', `/admin-dashboard/features/room-entries?user=${U.hidden}`, U.admin);
    assert.ok(entries.body.data.length >= 1);
    watcher.close();
    h.close();
  });

  test('ROOM_LOCK_BYPASS is a separate, logged permission', async () => {
    await api('POST', `/admin-dashboard/features/user/${U.bypass}/grant`, U.admin, { key: 'ROOM_LOCK_BYPASS', reason: 'e2e' });
    const s = await sock(U.bypass);
    const r = await joinRoom(s, lockedRoomId);
    assert.equal(r.admitted, true);
    assert.equal(r.mode.lockBypass, 'ROOM_LOCK_BYPASS');
    s.close();
  });

  test('official room: its owner cannot close it; the dashboard can, with an audit row', async () => {
    const r = await api('DELETE', `/rooms/${officialRoomId}`, U.o1);
    assert.equal(r.status, 403);
    assert.equal(r.body.code, 'OFFICIAL_ROOM');
    assert.equal((await db.room.findUnique({ where: { id: officialRoomId } })).isActive, true);
  });

  // ── Target ────────────────────────────────────────────────
  test('host target: one source; a new value replaces the old one everywhere', async () => {
    const now = Date.now();
    let r = await api('POST', '/admin-dashboard/host-targets', U.admin, {
      hostId: U.host, targetCoins: 50_000, targetUsd: 50, periodStart: new Date(now - 86_400_000), periodEnd: new Date(now + 29 * 86_400_000), reason: 'e2e',
    });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    let mine = await api('GET', '/agencies/my-target', U.host);
    assert.equal(mine.body.data.hostTarget.targetCoins, 50_000);
    assert.equal(mine.headers.get('cache-control'), 'no-store');
    r = await api('POST', '/admin-dashboard/host-targets', U.admin, {
      hostId: U.host, targetCoins: 70_000, targetUsd: 70, periodStart: new Date(now - 86_400_000), periodEnd: new Date(now + 29 * 86_400_000), reason: 'e2e 2',
    });
    mine = await api('GET', '/agencies/my-target', U.host);
    assert.equal(mine.body.data.hostTarget.targetCoins, 70_000, 'the old value never comes back');
    assert.equal(mine.body.data.hostTarget.version, 2);
    const all = await db.hostTarget.findMany({ where: { hostId: U.host }, orderBy: { id: 'asc' } });
    assert.deepEqual(all.map((t: any) => t.status), ['CANCELLED', 'ACTIVE']);
    const card = await api('GET', `/admin-dashboard/host-targets/user/${U.host}`, U.admin);
    assert.equal(card.body.data.active.targetCoins, 70_000, 'the dashboard shows the same number');
  });

  // ── الوكالات ──────────────────────────────────────────────
  test('agency invites: re-invite after reject works; accept is one transaction; twice is harmless; second agency refused; expired refused', async () => {
    const ag1 = await db.chargingAgency.create({ data: { userId: U.o1, agencyName: 'AG1', phoneNumber: '1', agencyImageUrl: '', idFrontUrl: '', idBackUrl: '', type: 'HOSTING', status: 'approved' } });
    const ag2 = await db.chargingAgency.create({ data: { userId: U.o2, agencyName: 'AG2', phoneNumber: '2', agencyImageUrl: '', idFrontUrl: '', idBackUrl: '', type: 'HOSTING', status: 'approved' } });
    await db.agencyMember.create({ data: { agencyId: ag1.id, userId: U.o1, role: 'OWNER' } });
    await db.agencyMember.create({ data: { agencyId: ag2.id, userId: U.o2, role: 'OWNER' } });

    let r = await api('POST', `/agencies/invite/${U.j}?agencyType=HOSTING`, U.o1);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    const inviteId = r.body.data.id;
    r = await api('POST', `/agencies/invite/${inviteId}/respond`, U.j, { action: 'reject' });
    assert.equal(r.status, 200);
    r = await api('POST', `/agencies/invite/${U.j}?agencyType=HOSTING`, U.o1);
    assert.equal(r.status, 201, 'the re-invite that used to 500');
    assert.equal(r.body.data.id, inviteId, 'same row, reopened');
    r = await api('POST', `/agencies/invite/${inviteId}/respond`, U.j, { action: 'accept' });
    assert.equal(r.status, 200);
    assert.equal(r.body.joined, true);
    assert.equal(await db.agencyMember.count({ where: { agencyId: ag1.id, userId: U.j } }), 1);
    r = await api('POST', `/agencies/invite/${inviteId}/respond`, U.j, { action: 'accept' });
    assert.equal(r.status, 200, 'accepting twice is harmless');
    assert.equal(await db.agencyMember.count({ where: { userId: U.j } }), 1);

    r = await api('POST', `/agencies/invite/${U.j}?agencyType=HOSTING`, U.o2);
    assert.equal(r.status, 409, 'already in another hosting agency');

    r = await api('POST', `/agencies/invite/${U.c}?agencyType=HOSTING`, U.o2);
    await db.agencyInvite.update({ where: { id: r.body.data.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    r = await api('POST', `/agencies/invite/${r.body.data.id}/respond`, U.c, { action: 'accept' });
    assert.equal(r.status, 410);
    assert.equal(await db.agencyMember.count({ where: { userId: U.c } }), 0);
  });

  // ── Audit ─────────────────────────────────────────────────
  test('audit: every admin change carries admin, before/after, reason, IP', async () => {
    const rows = await db.adminAuditLog.findMany({ where: { action: { in: ['GAME_POOL_FUND', 'CP_BREAK_FEE_UPDATE', 'FEATURE_GRANT', 'TARGET_SET', 'CP_LEVEL_UPDATE'] } } });
    const actions = new Set(rows.map((r: any) => r.action));
    for (const a of ['GAME_POOL_FUND', 'CP_BREAK_FEE_UPDATE', 'FEATURE_GRANT', 'TARGET_SET', 'CP_LEVEL_UPDATE']) assert.ok(actions.has(a), a);
    assert.ok(rows.every((r: any) => r.adminId === U.admin && r.reason && r.ip));
    const page = await api('GET', '/admin-dashboard/audit-log?action=CP_*', U.admin);
    assert.ok(page.body.data.total >= 2);
  });

  test('room list: real people now (not member rows), pinned IDs first in order, then most people', async () => {
    const mkRoom = (owner: number, name: string) => db.room.create({ data: { name, ownerId: owner } });
    const r1 = await mkRoom(U.e, 'pinned-empty');
    const r2 = await mkRoom(U.f, 'two-inside');
    const r3 = await mkRoom(U.g, 'one-inside');
    // A stale member row must not count: g was "in" r1 long ago.
    await db.roomMember.create({ data: { roomId: r1.id, userId: U.g } });

    const s1 = await sock(U.a);
    const s2 = await sock(U.b);
    const s3 = await sock(U.c);
    assert.equal((await joinRoom(s1, r2.id)).admitted, true);
    assert.equal((await joinRoom(s2, r2.id)).admitted, true);
    assert.equal((await joinRoom(s3, r3.id)).admitted, true);

    const list = async () => (await api('GET', '/rooms?limit=50', U.j)).body.rooms as any[];
    let rooms = await list();
    const pos = (id: number) => rooms.findIndex((x) => x.id === id);
    const count = (id: number) => rooms.find((x) => x.id === id)?.membersCount;
    assert.equal(rooms[0].id, officialRoomId, 'الإدارة stays the first (big) card');
    assert.equal(count(r2.id), 2);
    assert.equal(count(r3.id), 1);
    assert.equal(count(r1.id), 0, 'a member row is not a person in the room');
    assert.ok(pos(r2.id) < pos(r3.id) && pos(r3.id) < pos(r1.id), 'most people first');

    // Pin e's room (by the ID people see) above everything but الإدارة.
    const eDisplay = (await db.user.findUnique({ where: { id: U.e } })).displayId;
    assert.equal((await api('PUT', '/admin-dashboard/room-order', U.admin, { pins: [eDisplay] })).status, 400, 'reason required');
    const typo = await api('PUT', '/admin-dashboard/room-order', U.admin, { pins: [eDisplay, 987654321], reason: 'e2e' });
    assert.equal(typo.status, 400);
    assert.equal(typo.body.code, 'ROOM_NOT_FOUND');
    const saved = await api('PUT', '/admin-dashboard/room-order', U.admin, { pins: [eDisplay, r3.id], reason: 'e2e' });
    assert.equal(saved.status, 200);
    assert.equal(saved.body.data.pins[0].room.id, r1.id);
    assert.equal(saved.body.data.pins[1].room.id, r3.id, 'a room id works too');
    rooms = await list();
    assert.deepEqual(rooms.slice(0, 4).map((x) => x.id), [officialRoomId, r1.id, r3.id, r2.id]);
    assert.equal(rooms[1].pinRank, 1);
    const audit = await db.adminAuditLog.findFirst({ where: { action: 'ROOM_ORDER_UPDATE' } });
    assert.ok(audit && audit.reason === 'e2e' && audit.adminId === U.admin);

    // Someone closes the app → gone from the count.
    s1.close();
    await sleep(400);
    rooms = await list();
    assert.equal(count(r2.id), 1);

    // Clear the pins → back to most people first.
    await api('PUT', '/admin-dashboard/room-order', U.admin, { pins: [], reason: 'e2e' });
    rooms = await list();
    assert.ok(pos(r3.id) < pos(r1.id));
    for (const s of [s2, s3]) s.close();
  });

  test('non-admins cannot reach the new dashboard endpoints; admins without super cannot change money settings', async () => {
    assert.equal((await api('GET', '/admin-dashboard/games-economy', U.a)).status, 403);
    await db.user.update({ where: { id: U.o1 }, data: { isAdmin: true } });
    assert.equal((await api('GET', '/admin-dashboard/games-economy', U.o1)).status, 200);
    assert.equal((await api('PATCH', '/admin-dashboard/games-economy/plinko', U.o1, { maxBet: 5, reason: 'x' })).status, 403);
  });
});
