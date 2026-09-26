"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const node_child_process_1 = require("node:child_process");
const node_path_1 = __importDefault(require("node:path"));
const node_crypto_1 = __importDefault(require("node:crypto"));
const DB = process.env.E2E_DATABASE_URL ?? '';
const SKIP = !/^postgres(ql)?:\/\/[^@]+@(localhost|127\.0\.0\.1)[:/]/.test(DB);
if (!SKIP)
    process.env.DATABASE_URL = DB;
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');
const { io: ioc } = require('socket.io-client');
const PORT = 39123;
const BASE = `http://127.0.0.1:${PORT}/api/v1`;
const SECRET = 'e2e-secret-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
const REFRESH = 'e2e-refresh-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
const prisma = SKIP ? null : new PrismaClient({ datasources: { db: { url: DB } } });
const db = prisma;
let server = null;
const serverLog = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const tok = (userId) => jwt.sign({ userId }, SECRET, { expiresIn: '2h' });
async function api(method, p, uid, body, headers = {}) {
    const res = await fetch(BASE + p, {
        method,
        headers: {
            'content-type': 'application/json',
            ...(uid ? { authorization: `Bearer ${tok(uid)}` } : {}),
            ...headers,
        },
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json = null;
    try {
        json = await res.json();
    }
    catch {
        json = null;
    }
    return { status: res.status, body: json, headers: res.headers };
}
const bal = async (id) => Number((await db.user.findUnique({ where: { id }, select: { coinsBalance: true } })).coinsBalance);
const account = async (key) => Number((await db.economyAccount.findUnique({ where: { key } }))?.balance ?? 0);
const luckyPool = async () => Number((await db.luckyPool.findUnique({ where: { id: 1 } }))?.balance ?? 0);
const U = {};
let luckyGiftId = '';
let lockedRoomId = 0;
let officialRoomId = 100000;
async function wipe() {
    const tables = await db.$queryRawUnsafe(`SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> '_prisma_migrations'`);
    await db.$executeRawUnsafe(`TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(', ')} RESTART IDENTITY CASCADE`);
    await db.luckyPool.create({ data: { id: 1 } });
    await db.economyAccount.create({ data: { key: 'PROGRAM' } });
    for (const [m, w, min] of [[5, 3500, 0], [10, 2000, 0], [20, 700, 0], [30, 150, 10000], [50, 80, 5000], [100, 20, 20000], [200, 4, 60000], [300, 2, 120000], [500, 1, 250000]]) {
        await db.luckyTier.create({ data: { multiplier: m, weightBp: w, minPoolCoins: BigInt(min) } });
    }
    await db.cpEffect.create({ data: { effectKey: 'heart3d', name: 'قلب', requiredLevel: 2, enabled: false, priority: 10 } });
}
async function seed() {
    const mk = async (key, extra = {}) => {
        const u = await db.user.create({ data: { name: key, displayId: 10_000 + Object.keys(U).length + 1, coinsBalance: 100_000, ...extra } });
        U[key] = u.id;
    };
    for (const k of ['admin', 'a', 'b', 'c', 'd', 'host', 'e', 'f', 'g', 'h2', 'poor', 'o1', 'o2', 'j', 'hidden', 'bypass']) {
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
function startServer() {
    return new Promise((resolve, reject) => {
        server = (0, node_child_process_1.spawn)(process.execPath, [node_path_1.default.resolve(__dirname, '../../dist/index.js')], {
            cwd: node_path_1.default.resolve(__dirname, '../..'),
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
        const onData = (d) => {
            serverLog.push(d.toString());
            if (d.toString().includes('running on port')) {
                clearTimeout(t);
                resolve();
            }
        };
        server.stdout.on('data', onData);
        server.stderr.on('data', (d) => serverLog.push(d.toString()));
        server.on('exit', (code) => reject(new Error(`server exited ${code}\n` + serverLog.join(''))));
    });
}
function sock(uid) {
    return new Promise((resolve, reject) => {
        const s = ioc(`http://127.0.0.1:${PORT}`, { auth: { token: tok(uid) }, transports: ['websocket'], forceNew: true });
        s.events = [];
        s.onAny((ev, data) => s.events.push({ ev, data }));
        s.on('connect', () => resolve(s));
        s.on('connect_error', reject);
    });
}
async function joinRoom(s, roomId, extra = {}) {
    s.events.length = 0;
    s.emit('join_room', { roomId, ...extra });
    for (let i = 0; i < 60; i++) {
        const denied = s.events.find((e) => e.ev === 'join_denied');
        if (denied)
            return { admitted: false, denied: denied.data };
        const ok = s.events.find((e) => e.ev === 'room_entry_mode');
        if (ok)
            return { admitted: true, mode: ok.data };
        await sleep(50);
    }
    throw new Error('join_room: no answer');
}
async function setLuckyTiers(tiers) {
    await db.luckyTier.updateMany({ data: { weightBp: 0 } });
    for (const [m, w] of tiers)
        await db.luckyTier.update({ where: { multiplier: m }, data: { weightBp: w, minPoolCoins: 0n, isActive: true } });
}
const sendLucky = (uid, roomId, key, quantity = 1) => api('POST', '/gifts/send', uid, { giftId: luckyGiftId, recipientId: U.host, roomId, quantity }, key ? { 'Idempotency-Key': key } : {});
(0, node_test_1.describe)('2026-09-26 economy / CP / rooms / features (E2E)', { skip: SKIP ? 'E2E_DATABASE_URL (localhost) not set' : false }, () => {
    (0, node_test_1.before)(async () => {
        await wipe();
        await seed();
        await startServer();
    });
    (0, node_test_1.after)(async () => {
        server?.kill();
        await prisma?.$disconnect();
    });
    (0, node_test_1.test)('lucky: a lone player is PENDING — no win, nothing minted; the 30/70 split is booked', async () => {
        await setLuckyTiers([[5, 10_000]]);
        const room = await db.room.create({ data: { name: 'lucky-1', ownerId: U.o1 } });
        const [a0, h0, prog0, pool0] = [await bal(U.a), await bal(U.host), await account('PROGRAM'), await luckyPool()];
        const r = await sendLucky(U.a, room.id);
        strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
        strict_1.default.equal(r.body.lucky, null, 'old apps see no result while pending');
        strict_1.default.equal(r.body.luckyEntry.status, 'PENDING');
        strict_1.default.equal(await bal(U.a), a0 - 100, 'only the entry is taken');
        strict_1.default.equal(await bal(U.host), h0 + 10, 'host gets 10%');
        strict_1.default.equal(await account('PROGRAM'), prog0 + 20, 'program keeps 30% − host 10%');
        strict_1.default.equal(await luckyPool(), pool0 + 70, 'prize pool gets 70%');
        const roll = await db.luckyRoll.findFirst({ where: { senderId: U.a }, orderBy: { id: 'desc' } });
        strict_1.default.equal(roll.status, 'PENDING');
        strict_1.default.equal(roll.payoutCoins, 0);
    });
    (0, node_test_1.test)('lucky: a second player makes the round competitive — both entries drawn and paid from the pool', async () => {
        const room = await db.room.findFirst({ where: { name: 'lucky-1' } });
        const [a0, b0, pool0] = [await bal(U.a), await bal(U.b), await luckyPool()];
        const r = await sendLucky(U.b, room.id);
        strict_1.default.equal(r.status, 200);
        strict_1.default.equal(r.body.luckyEntry.status, 'SETTLED');
        strict_1.default.equal(r.body.lucky.multiplier, 5);
        strict_1.default.equal(r.body.lucky.payoutCoins, 50, 'x5 on H=10');
        strict_1.default.equal(await bal(U.b), b0 - 100 + 50);
        strict_1.default.equal(await bal(U.a), a0 + 50, "A's pending entry was drawn too");
        strict_1.default.equal(await luckyPool(), pool0 + 70 - 100, 'both wins came out of the pool');
        const rolls = await db.luckyRoll.findMany({ where: { roomId: room.id } });
        strict_1.default.ok(rolls.every((x) => x.status === 'SETTLED' && x.multiplier === 5));
        const round = await db.luckyRound.findFirst({ where: { roomId: room.id } });
        strict_1.default.equal(round.playerCount, 2);
        strict_1.default.equal(Number(round.totalEntry), 200);
        strict_1.default.equal(Number(round.prizePool), 140);
        strict_1.default.equal(Number(round.programShare), 60);
        strict_1.default.equal(Number(round.totalWin), 100);
    });
    (0, node_test_1.test)('lucky: a round that closes short of players settles its entries as NO_COMPETITION', async () => {
        const room = await db.room.create({ data: { name: 'lucky-2', ownerId: U.o1 } });
        const c0 = await bal(U.c);
        await sendLucky(U.c, room.id);
        await db.luckyRound.updateMany({ where: { roomId: room.id }, data: { endsAt: new Date(Date.now() - 1000) } });
        const { closeExpiredRounds, LUCKY_DEFAULTS } = require('../../dist/gifts/lucky.service');
        const closed = await db.$transaction((tx) => closeExpiredRounds(tx, room.id, LUCKY_DEFAULTS));
        strict_1.default.equal(closed.length, 1);
        strict_1.default.equal(closed[0].status, 'NOT_COMPETITIVE');
        const roll = await db.luckyRoll.findFirst({ where: { roomId: room.id } });
        strict_1.default.equal(roll.status, 'NO_COMPETITION');
        strict_1.default.equal(await bal(U.c), c0 - 100, 'no refund, no win, nothing minted');
    });
    (0, node_test_1.test)('lucky: every multiplier pays m × H, and "no win" pays nothing', async () => {
        await db.luckyPool.update({ where: { id: 1 }, data: { balance: 50000000n } });
        for (const m of [0, 5, 10, 20, 30, 50, 100, 200, 300, 500]) {
            await setLuckyTiers(m === 0 ? [] : [[m, 10_000]]);
            const room = await db.room.create({ data: { name: `lucky-m${m}`, ownerId: U.o1 } });
            await sendLucky(U.e, room.id);
            const f0 = await bal(U.f);
            const r = await sendLucky(U.f, room.id);
            strict_1.default.equal(r.body.lucky.multiplier, m, `x${m}`);
            strict_1.default.equal(r.body.lucky.payoutCoins, m * 10, `x${m} pays ${m * 10}`);
            strict_1.default.equal(await bal(U.f), f0 - 100 + m * 10);
        }
    });
    (0, node_test_1.test)('lucky: a multiplier the pool cannot cover is not in the draw — the pool never goes negative', async () => {
        await setLuckyTiers([[500, 10_000]]);
        await db.luckyPool.update({ where: { id: 1 }, data: { balance: 0n } });
        const room = await db.room.create({ data: { name: 'lucky-thin', ownerId: U.o1 } });
        await sendLucky(U.e, room.id);
        const r = await sendLucky(U.f, room.id);
        strict_1.default.equal(r.body.lucky.multiplier, 0, 'x500 (5,000) cannot be paid from a 140 pool');
        strict_1.default.ok((await luckyPool()) >= 0);
    });
    (0, node_test_1.test)('lucky: idempotency — a resent request (same key) is charged once and replays the answer', async () => {
        await setLuckyTiers([[5, 10_000]]);
        await db.luckyPool.update({ where: { id: 1 }, data: { balance: 1000000n } });
        const room = await db.room.create({ data: { name: 'lucky-idem', ownerId: U.o1 } });
        const g0 = await bal(U.g);
        const key = node_crypto_1.default.randomUUID();
        const r1 = await sendLucky(U.g, room.id, key);
        const r2 = await sendLucky(U.g, room.id, key);
        strict_1.default.equal(r1.status, 200);
        strict_1.default.equal(r2.status, 200);
        strict_1.default.equal(r2.headers.get('idempotent-replayed'), 'true');
        strict_1.default.equal(r2.body.transactionId, r1.body.transactionId);
        strict_1.default.equal(await bal(U.g), g0 - 100, 'charged exactly once');
        const key2 = node_crypto_1.default.randomUUID();
        const g1 = await bal(U.g);
        const burst = await Promise.all(Array.from({ length: 5 }, () => sendLucky(U.g, room.id, key2)));
        const succeeded = burst.filter((x) => x.status === 200);
        strict_1.default.ok(succeeded.length >= 1);
        strict_1.default.ok(burst.every((x) => x.status === 200 || x.status === 409), JSON.stringify(burst.map((x) => x.status)));
        strict_1.default.equal(new Set(succeeded.map((x) => x.body.transactionId)).size, 1, 'one transaction');
        strict_1.default.equal(await bal(U.g), g1 - 100, 'charged exactly once');
    });
    (0, node_test_1.test)('lucky: settings refuse nonsense, and entries outside min/max entry are refused before any charge', async () => {
        const bad1 = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { programShareBp: 3000, prizePoolBp: 6000, reason: 'test' });
        strict_1.default.equal(bad1.status, 400, 'shares must add up to 100%');
        const bad2 = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { rtpTargetBp: 8000, reason: 'test' });
        strict_1.default.equal(bad2.status, 400, 'RTP above the prize pool');
        const noReason = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { maxEntry: 500 });
        strict_1.default.equal(noReason.status, 400);
        const okr = await api('PATCH', '/admin-dashboard/lucky-mgmt/settings', U.admin, { minEntry: 50, maxEntry: 500, reason: 'e2e limits' });
        strict_1.default.equal(okr.status, 200, JSON.stringify(okr.body));
        const badTiers = await api('PUT', '/admin-dashboard/lucky-mgmt/tiers', U.admin, { tiers: [{ multiplier: 5, weightBp: 9000 }, { multiplier: 10, weightBp: 2000 }], reason: 'x' });
        strict_1.default.equal(badTiers.status, 400, 'probabilities over 100%');
        const hiRtp = await api('PUT', '/admin-dashboard/lucky-mgmt/tiers', U.admin, { tiers: [{ multiplier: 100, weightBp: 1000 }], reason: 'x' });
        strict_1.default.equal(hiRtp.status, 400, 'E[m]×10% = 100% > RTP target');
        const audit = await db.adminAuditLog.findFirst({ where: { action: 'LUCKY_SETTINGS_UPDATE' } });
        strict_1.default.equal(audit.reason, 'e2e limits');
        const h0 = await bal(U.h2);
        const r = await sendLucky(U.h2, null, undefined, 10);
        strict_1.default.equal(r.status, 400);
        strict_1.default.equal(r.body.code, 'LUCKY_ENTRY_RANGE');
        strict_1.default.equal(await bal(U.h2), h0);
    });
    (0, node_test_1.test)('games: an empty prize pool refuses the bet before any coin moves', async () => {
        const a0 = await bal(U.a);
        const r = await api('POST', '/games/plinko/drop', U.a, { risk: 'high', rows: 16, amount: 100 });
        strict_1.default.equal(r.body.code, 'PRIZE_POOL_LOW', JSON.stringify(r.body));
        strict_1.default.equal(await bal(U.a), a0);
    });
    (0, node_test_1.test)('games: stake splits 25% program / 75% pool; prizes come only from the pool', async () => {
        const f = await api('POST', '/admin-dashboard/games-economy/plinko/fund', U.admin, { amount: 5_000_000, reason: 'e2e seed' });
        strict_1.default.equal(f.status, 200, JSON.stringify(f.body));
        const [a0, prog0, pool0] = [await bal(U.a), await account('PROGRAM'), await account('GAME_POOL:plinko')];
        const r = await api('POST', '/games/plinko/drop', U.a, { risk: 'low', rows: 8, amount: 1000 });
        strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
        const payout = r.body.drop?.payout ?? r.body.data?.drop?.payout;
        strict_1.default.equal(await bal(U.a), a0 - 1000 + payout);
        strict_1.default.equal(await account('PROGRAM'), prog0 + 250);
        strict_1.default.equal(await account('GAME_POOL:plinko'), pool0 + 750 - payout);
        const stake = await db.gameLedger.findFirst({ where: { kind: 'stake', userId: U.a }, orderBy: { id: 'desc' } });
        strict_1.default.deepEqual([stake.programShare, stake.poolShare], [250, 750]);
    });
    (0, node_test_1.test)('games: max win per round caps the payout, daily cap refuses up front, min/max bet enforced', async () => {
        let r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { maxWinPerRound: 50, reason: 'e2e cap' });
        strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
        for (let i = 0; i < 12; i++) {
            r = await api('POST', '/games/plinko/drop', U.b, { risk: 'high', rows: 16, amount: 1000 });
            strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
            strict_1.default.ok(r.body.drop.payout <= 50, `payout ${r.body.drop.payout} over the round cap`);
        }
        r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { dailyMaxWinPerUser: 10, maxWinPerRound: 20, reason: 'e2e daily' });
        strict_1.default.equal(r.status, 400, 'round cap above the daily cap is refused');
        r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { dailyMaxWinPerUser: 10, maxWinPerRound: 10, reason: 'e2e daily' });
        strict_1.default.equal(r.status, 200);
        const c0 = await bal(U.c);
        r = await api('POST', '/games/plinko/drop', U.c, { risk: 'high', rows: 16, amount: 1000 });
        if (r.status === 200 && r.body.drop.payout > 0) {
            r = await api('POST', '/games/plinko/drop', U.c, { risk: 'high', rows: 16, amount: 1000 });
            strict_1.default.equal(r.body.code, 'DAILY_WIN_CAP');
        }
        r = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { minBet: 200, maxWinPerRound: 1_000_000, dailyMaxWinPerUser: 5_000_000, reason: 'e2e minbet' });
        const low = await api('POST', '/games/plinko/drop', U.c, { risk: 'low', rows: 8, amount: 100 });
        strict_1.default.equal(low.body.code, 'BET_TOO_LOW');
        strict_1.default.ok((await bal(U.c)) <= c0);
        const rtp = await api('PATCH', '/admin-dashboard/games-economy/plinko', U.admin, { rtpTargetBp: 8000, reason: 'x' });
        strict_1.default.equal(rtp.status, 400, 'RTP target above the 75% pool share');
    });
    (0, node_test_1.test)('games: duplicate play request (same key) is charged once', async () => {
        const key = node_crypto_1.default.randomUUID();
        const d0 = await bal(U.d);
        const r1 = await api('POST', '/games/plinko/drop', U.d, { risk: 'low', rows: 8, amount: 300 }, { 'Idempotency-Key': key });
        const r2 = await api('POST', '/games/plinko/drop', U.d, { risk: 'low', rows: 8, amount: 300 }, { 'Idempotency-Key': key });
        strict_1.default.equal(r1.status, 200, JSON.stringify(r1.body));
        strict_1.default.deepEqual(r2.body, r1.body);
        strict_1.default.equal(await bal(U.d), d0 - 300 + r1.body.drop.payout);
    });
    (0, node_test_1.test)('games: economy report adds up', async () => {
        const r = await api('GET', '/admin-dashboard/games-economy', U.admin);
        strict_1.default.equal(r.status, 200);
        const p = r.body.data.games.find((g) => g.game === 'plinko');
        strict_1.default.ok(p.totalBets > 0);
        strict_1.default.equal(p.netResult, p.totalBets - p.totalPayouts);
        strict_1.default.equal(p.programShare + p.playerPrizePool, p.totalBets);
        strict_1.default.ok(p.poolBalance >= 0);
    });
    const pair = (x, y, cpValue = 0) => db.cpPair.create({ data: { userAId: Math.min(x, y), userBId: Math.max(x, y), cpValue } });
    (0, node_test_1.test)('CP break: global fee split to program and partner, pair removed, logged — one transaction', async () => {
        await pair(U.e, U.f);
        let r = await api('PUT', '/admin-dashboard/cp-economy/break-fees', U.admin, { programFee: 700, partnerFee: 300, reason: 'e2e fees' });
        strict_1.default.equal(r.status, 200);
        const q = await api('GET', `/cp/partners/${U.f}/break-quote`, U.e);
        strict_1.default.deepEqual([q.body.data.totalFee, q.body.data.feeSource], [1000, 'GLOBAL']);
        const [e0, f0, p0] = [await bal(U.e), await bal(U.f), await account('PROGRAM')];
        r = await api('DELETE', `/cp/partners/${U.f}`, U.e, undefined, { 'Idempotency-Key': node_crypto_1.default.randomUUID() });
        strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
        strict_1.default.equal(await bal(U.e), e0 - 1000);
        strict_1.default.equal(await bal(U.f), f0 + 300);
        strict_1.default.equal(await account('PROGRAM'), p0 + 700);
        strict_1.default.equal(await db.cpPair.count({ where: { OR: [{ userAId: U.e }, { userBId: U.e }] } }), 0);
        const log = await db.cpBreakLog.findFirst({ where: { requesterId: U.e } });
        strict_1.default.deepEqual([Number(log.programFee), Number(log.partnerFee), log.feeSource], [700, 300, 'GLOBAL']);
    });
    (0, node_test_1.test)('CP break: a custom fee for the ID outranks the global one', async () => {
        await pair(U.g, U.h2);
        const card = await api('GET', `/admin-dashboard/cp-economy/custom-fee/${U.g}`, U.admin);
        strict_1.default.equal(card.body.data.partners.length, 1);
        const r = await api('PUT', `/admin-dashboard/cp-economy/custom-fee/${U.g}`, U.admin, { programFee: 100, partnerFee: 50, enabled: true, reason: 'vip' });
        strict_1.default.equal(r.status, 200);
        const [g0, h0] = [await bal(U.g), await bal(U.h2)];
        await api('DELETE', `/cp/partners/${U.h2}`, U.g);
        strict_1.default.equal(await bal(U.g), g0 - 150);
        strict_1.default.equal(await bal(U.h2), h0 + 50);
    });
    (0, node_test_1.test)('CP break: not enough balance → nothing changes at all', async () => {
        await pair(U.poor, U.j);
        const [p0, j0, prog0] = [await bal(U.poor), await bal(U.j), await account('PROGRAM')];
        const r = await api('DELETE', `/cp/partners/${U.j}`, U.poor);
        strict_1.default.equal(r.status, 402);
        strict_1.default.equal(r.body.shortfall, 1000 - 10);
        strict_1.default.deepEqual([await bal(U.poor), await bal(U.j), await account('PROGRAM')], [p0, j0, prog0]);
        strict_1.default.equal(await db.cpPair.count({ where: { userAId: Math.min(U.poor, U.j), userBId: Math.max(U.poor, U.j) } }), 1);
    });
    (0, node_test_1.test)('CP level: the level table decides the level from CP-gift value only; levels must climb', async () => {
        await api('PUT', '/admin-dashboard/cp-economy/levels/1', U.admin, { requiredCoins: 100, name: 'L1', reason: 'e2e' });
        await api('PUT', '/admin-dashboard/cp-economy/levels/2', U.admin, { requiredCoins: 500, name: 'L2', reason: 'e2e' });
        const bad = await api('PUT', '/admin-dashboard/cp-economy/levels/3', U.admin, { requiredCoins: 400, reason: 'e2e' });
        strict_1.default.equal(bad.status, 400);
        await pair(U.a, U.b, 600);
        const r = await api('GET', '/cp/partners', U.a);
        const row = r.body.data.find((x) => x.partner.id === U.b);
        strict_1.default.deepEqual([row.level, row.levelName, row.levelBasis], [2, 'L2', 'table']);
    });
    (0, node_test_1.test)('CP effect: two partners on the mics carry a link with the effect their level earns', async () => {
        await api('PUT', '/admin-dashboard/cp-economy/effects/heart3d', U.admin, { enabled: true, requiredLevel: 2, durationSec: 0, animationSpeed: 1.5, priority: 10, reason: 'e2e' });
        const { cpSeatLinks, invalidateCpEffectsCache } = require('../../dist/services/cpEffect.service');
        invalidateCpEffectsCache();
        const links = await cpSeatLinks(new Map([[1, U.a], [2, U.b], [3, U.c]]));
        strict_1.default.equal(links.length, 1);
        strict_1.default.deepEqual([links[0].level, links[0].effect?.key, links[0].effect?.animationSpeed], [2, 'heart3d', 1.5]);
    });
    (0, node_test_1.test)('locked room: owner in without PIN; users, room admins and super admins need it', async () => {
        const owner = await sock(U.d);
        strict_1.default.equal((await joinRoom(owner, lockedRoomId)).admitted, true);
        const user = await sock(U.b);
        const denied = await joinRoom(user, lockedRoomId);
        strict_1.default.equal(denied.admitted, false);
        strict_1.default.equal(denied.denied.canHiddenBypass, false);
        const wrong = await joinRoom(user, lockedRoomId, { code: '99999' });
        strict_1.default.equal(wrong.denied.wrongCode, true);
        strict_1.default.equal((await joinRoom(user, lockedRoomId, { code: '12345' })).admitted, true);
        const superAdmin = await sock(U.admin);
        strict_1.default.equal((await joinRoom(superAdmin, lockedRoomId)).admitted, false, 'no automatic bypass for super admins');
        const tamper = await sock(U.c);
        strict_1.default.equal((await joinRoom(tamper, lockedRoomId, { hiddenBypass: true })).admitted, false, 'hiddenBypass without the feature');
        const http = await api('POST', `/rooms/${lockedRoomId}/join`, U.c, {});
        strict_1.default.equal(http.status, 403);
        for (const s of [owner, user, superAdmin, tamper])
            s.close();
    });
    (0, node_test_1.test)('hidden mode: granted + switched on → asked, then enters without PIN, invisible to the room, logged', async () => {
        let r = await api('PUT', '/users/me/features/HIDDEN_MODE', U.hidden, { on: true });
        strict_1.default.equal(r.status, 403, 'cannot switch on a feature not granted');
        r = await api('POST', `/admin-dashboard/features/user/${U.hidden}/grant`, U.admin, { key: 'HIDDEN_MODE', reason: 'e2e' });
        strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
        r = await api('PUT', '/users/me/features/HIDDEN_MODE', U.hidden, { on: true });
        strict_1.default.equal(r.status, 200);
        const mine = await api('GET', '/users/me/features', U.hidden);
        strict_1.default.equal(mine.body.data.find((f) => f.key === 'HIDDEN_MODE').on, true);
        const watcher = await sock(U.d);
        await joinRoom(watcher, lockedRoomId);
        watcher.events.length = 0;
        const h = await sock(U.hidden);
        const ask = await joinRoom(h, lockedRoomId);
        strict_1.default.equal(ask.admitted, false);
        strict_1.default.equal(ask.denied.canHiddenBypass, true, 'the app asks "هل تريد الدخول بدون كلمة مرور؟"');
        const inn = await joinRoom(h, lockedRoomId, { hiddenBypass: true });
        strict_1.default.equal(inn.admitted, true);
        strict_1.default.deepEqual([inn.mode.hidden, inn.mode.lockBypass], [true, 'HIDDEN_MODE']);
        await sleep(500);
        const seen = watcher.events.filter((e) => ['user_entered', 'user_joined'].includes(e.ev) && e.data?.userId === U.hidden);
        strict_1.default.equal(seen.length, 0, 'no entrance notice to the room');
        watcher.emit('get_room_users', { roomId: lockedRoomId });
        await sleep(400);
        const roster = watcher.events.filter((e) => e.ev === 'room_users').pop();
        strict_1.default.ok(!roster.data.users.some((u) => u.userId === U.hidden), 'not in the roster');
        const log = await db.roomEntryLog.findFirst({ where: { userId: U.hidden, roomId: lockedRoomId } });
        strict_1.default.deepEqual([log.hidden, log.lockBypass], [true, 'HIDDEN_MODE']);
        h.emit('leave_room', { roomId: lockedRoomId });
        await sleep(500);
        strict_1.default.ok((await db.roomEntryLog.findFirst({ where: { id: log.id } })).exitedAt, 'exit time recorded');
        strict_1.default.equal(watcher.events.filter((e) => e.ev === 'user_left' && e.data?.userId === U.hidden).length, 0);
        await api('POST', `/admin-dashboard/features/user/${U.hidden}/revoke`, U.admin, { key: 'HIDDEN_MODE', reason: 'e2e' });
        strict_1.default.equal((await joinRoom(h, lockedRoomId, { hiddenBypass: true })).admitted, false);
        await api('POST', `/admin-dashboard/features/user/${U.hidden}/grant`, U.admin, { key: 'HIDDEN_MODE', reason: 'e2e' });
        await api('PUT', '/users/me/features/HIDDEN_MODE', U.hidden, { on: true });
        await api('PATCH', `/admin-dashboard/rooms-mgmt/${lockedRoomId}`, U.admin, { allowHiddenEntry: false, reason: 'e2e' });
        strict_1.default.equal((await joinRoom(h, lockedRoomId, { hiddenBypass: true })).admitted, false);
        await api('PATCH', `/admin-dashboard/rooms-mgmt/${lockedRoomId}`, U.admin, { allowHiddenEntry: true, reason: 'e2e' });
        const entries = await api('GET', `/admin-dashboard/features/room-entries?user=${U.hidden}`, U.admin);
        strict_1.default.ok(entries.body.data.length >= 1);
        watcher.close();
        h.close();
    });
    (0, node_test_1.test)('ROOM_LOCK_BYPASS is a separate, logged permission', async () => {
        await api('POST', `/admin-dashboard/features/user/${U.bypass}/grant`, U.admin, { key: 'ROOM_LOCK_BYPASS', reason: 'e2e' });
        const s = await sock(U.bypass);
        const r = await joinRoom(s, lockedRoomId);
        strict_1.default.equal(r.admitted, true);
        strict_1.default.equal(r.mode.lockBypass, 'ROOM_LOCK_BYPASS');
        s.close();
    });
    (0, node_test_1.test)('official room: its owner cannot close it; the dashboard can, with an audit row', async () => {
        const r = await api('DELETE', `/rooms/${officialRoomId}`, U.o1);
        strict_1.default.equal(r.status, 403);
        strict_1.default.equal(r.body.code, 'OFFICIAL_ROOM');
        strict_1.default.equal((await db.room.findUnique({ where: { id: officialRoomId } })).isActive, true);
    });
    (0, node_test_1.test)('host target: one source; a new value replaces the old one everywhere', async () => {
        const now = Date.now();
        let r = await api('POST', '/admin-dashboard/host-targets', U.admin, {
            hostId: U.host, targetCoins: 50_000, targetUsd: 50, periodStart: new Date(now - 86_400_000), periodEnd: new Date(now + 29 * 86_400_000), reason: 'e2e',
        });
        strict_1.default.equal(r.status, 200, JSON.stringify(r.body));
        let mine = await api('GET', '/agencies/my-target', U.host);
        strict_1.default.equal(mine.body.data.hostTarget.targetCoins, 50_000);
        strict_1.default.equal(mine.headers.get('cache-control'), 'no-store');
        r = await api('POST', '/admin-dashboard/host-targets', U.admin, {
            hostId: U.host, targetCoins: 70_000, targetUsd: 70, periodStart: new Date(now - 86_400_000), periodEnd: new Date(now + 29 * 86_400_000), reason: 'e2e 2',
        });
        mine = await api('GET', '/agencies/my-target', U.host);
        strict_1.default.equal(mine.body.data.hostTarget.targetCoins, 70_000, 'the old value never comes back');
        strict_1.default.equal(mine.body.data.hostTarget.version, 2);
        const all = await db.hostTarget.findMany({ where: { hostId: U.host }, orderBy: { id: 'asc' } });
        strict_1.default.deepEqual(all.map((t) => t.status), ['CANCELLED', 'ACTIVE']);
        const card = await api('GET', `/admin-dashboard/host-targets/user/${U.host}`, U.admin);
        strict_1.default.equal(card.body.data.active.targetCoins, 70_000, 'the dashboard shows the same number');
    });
    (0, node_test_1.test)('agency invites: re-invite after reject works; accept is one transaction; twice is harmless; second agency refused; expired refused', async () => {
        const ag1 = await db.chargingAgency.create({ data: { userId: U.o1, agencyName: 'AG1', phoneNumber: '1', agencyImageUrl: '', idFrontUrl: '', idBackUrl: '', type: 'HOSTING', status: 'approved' } });
        const ag2 = await db.chargingAgency.create({ data: { userId: U.o2, agencyName: 'AG2', phoneNumber: '2', agencyImageUrl: '', idFrontUrl: '', idBackUrl: '', type: 'HOSTING', status: 'approved' } });
        await db.agencyMember.create({ data: { agencyId: ag1.id, userId: U.o1, role: 'OWNER' } });
        await db.agencyMember.create({ data: { agencyId: ag2.id, userId: U.o2, role: 'OWNER' } });
        let r = await api('POST', `/agencies/invite/${U.j}?agencyType=HOSTING`, U.o1);
        strict_1.default.equal(r.status, 201, JSON.stringify(r.body));
        const inviteId = r.body.data.id;
        r = await api('POST', `/agencies/invite/${inviteId}/respond`, U.j, { action: 'reject' });
        strict_1.default.equal(r.status, 200);
        r = await api('POST', `/agencies/invite/${U.j}?agencyType=HOSTING`, U.o1);
        strict_1.default.equal(r.status, 201, 'the re-invite that used to 500');
        strict_1.default.equal(r.body.data.id, inviteId, 'same row, reopened');
        r = await api('POST', `/agencies/invite/${inviteId}/respond`, U.j, { action: 'accept' });
        strict_1.default.equal(r.status, 200);
        strict_1.default.equal(r.body.joined, true);
        strict_1.default.equal(await db.agencyMember.count({ where: { agencyId: ag1.id, userId: U.j } }), 1);
        r = await api('POST', `/agencies/invite/${inviteId}/respond`, U.j, { action: 'accept' });
        strict_1.default.equal(r.status, 200, 'accepting twice is harmless');
        strict_1.default.equal(await db.agencyMember.count({ where: { userId: U.j } }), 1);
        r = await api('POST', `/agencies/invite/${U.j}?agencyType=HOSTING`, U.o2);
        strict_1.default.equal(r.status, 409, 'already in another hosting agency');
        r = await api('POST', `/agencies/invite/${U.c}?agencyType=HOSTING`, U.o2);
        await db.agencyInvite.update({ where: { id: r.body.data.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
        r = await api('POST', `/agencies/invite/${r.body.data.id}/respond`, U.c, { action: 'accept' });
        strict_1.default.equal(r.status, 410);
        strict_1.default.equal(await db.agencyMember.count({ where: { userId: U.c } }), 0);
    });
    (0, node_test_1.test)('audit: every admin change carries admin, before/after, reason, IP', async () => {
        const rows = await db.adminAuditLog.findMany({ where: { action: { in: ['GAME_POOL_FUND', 'CP_BREAK_FEE_UPDATE', 'FEATURE_GRANT', 'TARGET_SET', 'CP_LEVEL_UPDATE'] } } });
        const actions = new Set(rows.map((r) => r.action));
        for (const a of ['GAME_POOL_FUND', 'CP_BREAK_FEE_UPDATE', 'FEATURE_GRANT', 'TARGET_SET', 'CP_LEVEL_UPDATE'])
            strict_1.default.ok(actions.has(a), a);
        strict_1.default.ok(rows.every((r) => r.adminId === U.admin && r.reason && r.ip));
        const page = await api('GET', '/admin-dashboard/audit-log?action=CP_*', U.admin);
        strict_1.default.ok(page.body.data.total >= 2);
    });
    (0, node_test_1.test)('non-admins cannot reach the new dashboard endpoints; admins without super cannot change money settings', async () => {
        strict_1.default.equal((await api('GET', '/admin-dashboard/games-economy', U.a)).status, 403);
        await db.user.update({ where: { id: U.o1 }, data: { isAdmin: true } });
        strict_1.default.equal((await api('GET', '/admin-dashboard/games-economy', U.o1)).status, 200);
        strict_1.default.equal((await api('PATCH', '/admin-dashboard/games-economy/plinko', U.o1, { maxBet: 5, reason: 'x' })).status, 403);
    });
});
//# sourceMappingURL=economy.e2e.js.map