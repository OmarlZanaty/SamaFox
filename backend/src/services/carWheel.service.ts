import { Server } from 'socket.io';
import crypto from 'crypto';
import prisma from '../utils/prisma';
import { getGameSettings, checkGamePlayable } from './gameConfig.service';
import { grantStakeValue, payPrize, releasePrize, reservePrize } from './halalGames.service';
import { broadcastGameWin } from './gameBroadcast.service';
import { CHIPS, MAX_PER_KEY, MULTIPLIERS, WHEEL_ORDER, SEGMENTS, maxPayout, parseBetKey, payoutFor, rollFromSeed } from './carWheel.math';

// ============================================================
// عجلة السيارات — shared eight-segment car wheel (one table for everyone)
// ============================================================
// Round shape, like القط الجشع:
//   betting (25s) → closing (3s) → spinning (7s) → result (6s) → next round
//
// The seed is committed (its hash is public) when betting opens and only
// revealed once the result is out; the segment is a weighted sha256(seed:roundId) draw,
// so where the money went can never steer it.
//
// Money:
//  - Each chip is charged and written to car_wheel_stakes in one transaction.
//  - The prize the player could win is reserved as chips go down, so the pool
//    can always pay the whole table (reservations track the player's real
//    maximum over all eight segments, not the sum of every chip).
//  - When betting closes the stakes are split program/pool and buy their XP
//    (grantStakeValue), exactly like the other shared games.
//  - At the result each winner is paid from the pool (payPrize), the chips
//    are marked settled, and the daily board is updated.
//  - A restart cannot keep anyone's coins: chips still `open` from a round
//    that never settled are refunded on boot.
// ============================================================

export const GAME = 'carwheel';
export const CAR_WHEEL_ROOM = 'carwheel:main';
type Phase = 'betting' | 'closing' | 'spinning' | 'result';
export const PHASE_MS: Record<Phase, number> = { betting: 25_000, closing: 3_000, spinning: 7_000, result: 6_000 };
/** Wins of at least this × the player's stake are announced to everyone. */
const BROADCAST_MIN_X = 10;

interface Chip { id: number; key: string; amount: number }
interface Player {
  userId: number;
  name: string;
  avatarUrl: string | null;
  countryCode: string | null;
  stakes: Record<string, number>;
  chips: Chip[];
  /** Prize the pool holds back for this player, and the reservation tokens. */
  reserved: number;
  tokens: string[];
  payout: number;
}
interface Round {
  /** car_wheel_rounds.id once the first chip lands; null on an idle table. */
  dbId: number | null;
  phase: Phase;
  endsAt: number;
  seed: string;
  seedHash: string;
  result: string | null;
  players: Map<number, Player>;
  winners: { userId: number; name: string; avatarUrl: string | null; payout: number }[];
}

let io: Server | null = null;
let round: Round | null = null;
let timer: NodeJS.Timeout | null = null;
/** The number the next round will get, so an idle table still shows one. */
let nextRoundNo = 1;
const results: { round: number; number: string; at: number }[] = [];
const lastStakes = new Map<number, Record<string, number>>();

const ok = <T extends object>(body: T) => ({ ok: true as const, ...body });
const fail = (code: string, message: string) => ({ ok: false as const, code, message });
const closed = () => fail('BETTING_CLOSED', 'أُغلقت الرهانات — انتظر النتيجة');
const sum = (o: Record<string, number>) => Object.values(o).reduce((a, b) => a + b, 0);
const roundNo = () => round?.dbId ?? nextRoundNo;

// One operation at a time per player: a chip, an undo and a clear sent
// together cannot interleave their checks and charges.
const locks = new Map<number, Promise<unknown>>();
function withLock<T>(userId: number, task: () => Promise<T>): Promise<T> {
  const prev = locks.get(userId) ?? Promise.resolve();
  const run = prev.then(task, task);
  const tail = run.catch(() => undefined);
  locks.set(userId, tail);
  tail.then(() => { if (locks.get(userId) === tail) locks.delete(userId); });
  return run;
}

// ── Public state ────────────────────────────────────────────
function totals() {
  const byKey: Record<string, number> = {};
  for (const p of round?.players.values() ?? []) {
    for (const [k, v] of Object.entries(p.stakes)) if (v > 0) byKey[k] = (byKey[k] ?? 0) + v;
  }
  return byKey;
}

export function getPublicState(userId?: number) {
  if (!round) return null;
  const me = userId != null ? round.players.get(userId) : undefined;
  const byKey = totals();
  const preResult = round.phase === 'betting' || round.phase === 'closing';
  const players = [...round.players.values()]
    .map(p => ({ userId: p.userId, name: p.name, avatarUrl: p.avatarUrl, staked: sum(p.stakes) }))
    .filter(p => p.staked > 0)
    .sort((a, b) => b.staked - a.staked);
  return {
    round: roundNo(),
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    seedHash: round.seedHash,
    seed: round.phase === 'result' ? round.seed : null,
    result: preResult ? null : round.result,
    totals: byKey,
    totalBet: sum(byKey),
    playerCount: players.length,
    players: players.slice(0, 8),
    me: me ? { stakes: me.stakes, staked: sum(me.stakes), chips: me.chips.length, chipList: me.chips,
      payout: round.phase === 'result' ? me.payout : 0 } : null,
    winners: round.phase === 'result' ? round.winners : [],
    history: results.slice(-15).map(r => r.number),
  };
}

let broadcastTimer: NodeJS.Timeout | null = null;
/** Chips arrive in bursts; the table view goes out at most ~4× a second. */
function broadcastSoon() {
  if (broadcastTimer) return;
  broadcastTimer = setTimeout(() => { broadcastTimer = null; broadcast(); }, 250);
}
function broadcast() {
  io?.to(CAR_WHEEL_ROOM).emit('carwheel_state', getPublicState());
}

export function getLayout() {
  return { wheel: WHEEL_ORDER, multipliers: MULTIPLIERS, chips: CHIPS, maxPerKey: MAX_PER_KEY, phases: PHASE_MS,
    segments: SEGMENTS };
}

async function balanceOf(userId: number) {
  return (await prisma.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } }))?.coinsBalance ?? 0;
}

// ── Betting ─────────────────────────────────────────────────
async function playerFor(r: Round, userId: number): Promise<Player> {
  let p = r.players.get(userId);
  if (p) return p;
  const user = await prisma.user.findUnique({ where: { id: userId },
    select: { name: true, avatarUrl: true, countryCode: true } }).catch(() => null);
  p = r.players.get(userId);
  if (p) return p;
  p = { userId, name: user?.name ?? 'لاعب', avatarUrl: user?.avatarUrl ?? null, countryCode: user?.countryCode ?? null,
    stakes: {}, chips: [], reserved: 0, tokens: [], payout: 0 };
  r.players.set(userId, p);
  return p;
}

/** The round's database row, created by its first chip. */
async function ensureRoundRow(r: Round): Promise<number> {
  if (r.dbId != null) return r.dbId;
  const row = await prisma.carWheelRound.create({ data: { seedHash: r.seedHash, seed: r.seed } });
  // Two first chips can race here; the later one adopts the first row.
  if (r.dbId == null) r.dbId = row.id;
  else await prisma.carWheelRound.delete({ where: { id: row.id } }).catch(() => undefined);
  nextRoundNo = r.dbId + 1;
  return r.dbId;
}

/** Puts [amount] on [key]. [anyAmount] lets REPEAT replay a total that no single chip matches. */
async function place(userId: number, key: string, amount: number, anyAmount = false) {
  const r = round;
  if (!r || r.phase !== 'betting') return closed();
  const bet = parseBetKey(key);
  if (!bet) return fail('BAD_TARGET', 'خانة رهان غير صحيحة');
  const validAmount = anyAmount ? Number.isSafeInteger(amount) && amount > 0 && amount % 100 === 0 : CHIPS.includes(amount);
  if (!validAmount) return fail('BAD_AMOUNT', 'قيمة رهان غير صحيحة');
  const player = await playerFor(r, userId);
  if ((player.stakes[key] ?? 0) + amount > MAX_PER_KEY) return fail('MAX_BET', 'تجاوزت الحد الأقصى لهذه الخانة');
  const settings = await getGameSettings(GAME);
  const staked = sum(player.stakes);
  if (settings.maxBet != null && staked + amount > settings.maxBet) {
    return fail('BET_TOO_HIGH', `الحد الأقصى لرهاناتك في الجولة ${settings.maxBet} — المتبقي ${Math.max(0, settings.maxBet - staked)}`);
  }
  // Hold back whatever this chip adds to the player's best possible return.
  const next = { ...player.stakes, [key]: (player.stakes[key] ?? 0) + amount };
  const need = maxPayout(next) - player.reserved;
  let token: string | null = null, cap = 0;
  if (need > 0) {
    const reserved = await reservePrize(userId, GAME, need, staked + amount);
    if (!reserved.ok) return fail(reserved.code, reserved.message);
    token = reserved.token;
    cap = reserved.cap;
  }
  const roundId = await ensureRoundRow(r).catch(e => { releasePrize(token); throw e; });
  let chipId: number;
  try {
    chipId = await prisma.$transaction(async tx => {
      const charged = await tx.user.updateMany({ where: { id: userId, coinsBalance: { gte: amount } },
        data: { coinsBalance: { decrement: amount } } });
      if (charged.count !== 1) throw Object.assign(new Error('INSUFFICIENT'), { code: 'INSUFFICIENT_COINS' });
      return (await tx.carWheelStake.create({ data: { roundId, userId, betKey: key, amount } })).id;
    });
  } catch (e) {
    releasePrize(token);
    if ((e as { code?: string }).code === 'INSUFFICIENT_COINS') return fail('INSUFFICIENT_COINS', 'رصيدك لا يكفي');
    throw e;
  }
  // Betting closed while the charge was in flight: give the chip back.
  if (round !== r || r.phase !== 'betting') {
    releasePrize(token);
    await refundChips([chipId]);
    return closed();
  }
  player.stakes = next;
  player.chips.push({ id: chipId, key, amount });
  if (token) { player.tokens.push(token); player.reserved += cap; }
  broadcastSoon();
  return ok({ stakes: player.stakes, chipList: player.chips, balance: await balanceOf(userId), round: roundNo() });
}

export const placeBet = (userId: number, key: unknown, amount: unknown) =>
  withLock(userId, async () => {
    const verdict = await checkGamePlayable(GAME, Number(amount));
    if (!verdict.ok) return fail(verdict.code, verdict.message);
    return place(userId, String(key), Number(amount));
  });

/** Marks chips refunded and gives their coins back, once each. */
async function refundChips(ids: number[]) {
  for (const id of ids) {
    await prisma.$transaction(async tx => {
      const chip = await tx.carWheelStake.findUnique({ where: { id } });
      if (!chip) return;
      const flipped = await tx.carWheelStake.updateMany({ where: { id, status: 'open' }, data: { status: 'refunded' } });
      if (flipped.count === 1) await tx.user.update({ where: { id: chip.userId }, data: { coinsBalance: { increment: chip.amount } } });
    });
  }
}

function forget(p: Player, chips: Chip[]) {
  for (const c of chips) {
    const left = (p.stakes[c.key] ?? 0) - c.amount;
    if (left > 0) p.stakes[c.key] = left; else delete p.stakes[c.key];
  }
  p.chips = p.chips.filter(c => !chips.includes(c));
  // Reservations only shrink when the table is empty; until then the hold
  // stays (slightly generous) and is released at settlement.
  if (p.chips.length === 0) { for (const t of p.tokens) releasePrize(t); p.tokens = []; p.reserved = 0; }
}

/** Takes the player's last chip back. Betting phase only. */
export const undoBet = (userId: number) => withLock(userId, async () => {
  const r = round;
  if (!r || r.phase !== 'betting') return closed();
  const p = r.players.get(userId);
  const chip = p?.chips[p.chips.length - 1];
  if (!p || !chip) return fail('NO_BET', 'لا يوجد رهان للتراجع عنه');
  await refundChips([chip.id]);
  forget(p, [chip]);
  broadcastSoon();
  return ok({ stakes: p.stakes, chipList: p.chips, balance: await balanceOf(userId), round: roundNo() });
});

/** Takes every chip back. Betting phase only. */
export const clearBets = (userId: number) => withLock(userId, async () => {
  const r = round;
  if (!r || r.phase !== 'betting') return closed();
  const p = r.players.get(userId);
  if (p && p.chips.length) {
    await refundChips(p.chips.map(c => c.id));
    forget(p, [...p.chips]);
    broadcastSoon();
  }
  return ok({ stakes: p?.stakes ?? {}, chipList: p?.chips ?? [], balance: await balanceOf(userId), round: roundNo() });
});

/** Re-places last round's stakes in one charge/insert transaction, or none. */
export const repeatBets = (userId: number) => withLock(userId, async () => {
  const r = round;
  if (!r || r.phase !== 'betting') return closed();
  const previous = lastStakes.get(userId);
  if (!previous || sum(previous) <= 0) return fail('NO_PREVIOUS', 'لا يوجد رهان سابق');
  const amount = sum(previous);
  const verdict = await checkGamePlayable(GAME, amount);
  if (!verdict.ok) return fail(verdict.code, verdict.message);
  const p = await playerFor(r, userId);
  const next = { ...p.stakes };
  for (const [key, value] of Object.entries(previous)) {
    if (!parseBetKey(key)) return fail('BAD_TARGET', 'خانة رهان غير صحيحة');
    if (!Number.isSafeInteger(value) || value <= 0 || value % 100 !== 0) return fail('BAD_AMOUNT', 'قيمة رهان غير صحيحة');
    next[key] = (next[key] ?? 0) + value;
    if (next[key]! > MAX_PER_KEY) return fail('MAX_BET', 'تجاوزت الحد الأقصى لهذه الخانة');
  }
  const settings = await getGameSettings(GAME);
  if (settings.maxBet != null && sum(next) > settings.maxBet) return fail('BET_TOO_HIGH', 'تجاوزت الحد الأقصى للجولة');
  if (await balanceOf(userId) < amount) return fail('INSUFFICIENT_COINS', 'رصيدك لا يكفي');
  const need = maxPayout(next) - p.reserved;
  let token: string | null = null, cap = 0;
  if (need > 0) {
    const held = await reservePrize(userId, GAME, need, sum(next));
    if (!held.ok) return fail(held.code, held.message);
    token = held.token; cap = held.cap;
  }
  let chips: Chip[];
  try {
    const roundId = await ensureRoundRow(r);
    chips = await prisma.$transaction(async tx => {
      const charged = await tx.user.updateMany({ where: { id: userId, coinsBalance: { gte: amount } },
        data: { coinsBalance: { decrement: amount } } });
      if (charged.count !== 1) throw Object.assign(new Error('INSUFFICIENT'), { code: 'INSUFFICIENT_COINS' });
      const added: Chip[] = [];
      for (const [key, value] of Object.entries(previous)) {
        const row = await tx.carWheelStake.create({ data: { roundId, userId, betKey: key, amount: value } });
        added.push({ id: row.id, key, amount: value });
      }
      return added;
    });
  } catch (error) {
    releasePrize(token);
    if ((error as { code?: string }).code === 'INSUFFICIENT_COINS') return fail('INSUFFICIENT_COINS', 'رصيدك لا يكفي');
    throw error;
  }
  if (round !== r || r.phase !== 'betting') {
    releasePrize(token);
    await refundChips(chips.map(c => c.id));
    return closed();
  }
  p.stakes = next;
  p.chips.push(...chips);
  if (token) { p.tokens.push(token); p.reserved += cap; }
  broadcastSoon();
  return ok({ stakes: p.stakes, chipList: p.chips, balance: await balanceOf(userId), round: roundNo() });
});

// ── Settlement ──────────────────────────────────────────────
async function recordDaily(p: Player, staked: number, payout: number) {
  const day = new Date().toISOString().slice(0, 10);
  const where = { game_day_userId: { game: GAME, day, userId: p.userId } };
  const row = await prisma.gameDailyStat.findUnique({ where });
  await prisma.gameDailyStat.upsert({
    where,
    create: { game: GAME, day, userId: p.userId, net: payout - staked, wagered: staked, best: payout, countryCode: p.countryCode },
    update: { net: { increment: payout - staked }, wagered: { increment: staked }, best: Math.max(row?.best ?? 0, payout) },
  });
}

async function settle(r: Round) {
  const result = r.result!;
  const winners: Round['winners'] = [];
  let totalBet = 0, playerCount = 0;
  for (const p of r.players.values()) {
    const staked = sum(p.stakes);
    if (staked <= 0) { for (const t of p.tokens) releasePrize(t); continue; }
    totalBet += staked;
    playerCount++;
    lastStakes.set(p.userId, { ...p.stakes });
    const prize = payoutFor(p.stakes, result);
    const tokens = p.tokens;
    p.tokens = [];
    let paid = 0;
    if (prize > 0) {
      try {
        paid = (await payPrize(tokens, p.userId, GAME, prize, `round:${r.dbId}`, staked)).paid;
      } catch (err) {
        for (const t of tokens) releasePrize(t);
        console.error('[carwheel] payout failed', { userId: p.userId, prize, err });
      }
    } else {
      for (const t of tokens) releasePrize(t);
    }
    p.payout = paid;
    if (paid > 0) winners.push({ userId: p.userId, name: p.name, avatarUrl: p.avatarUrl, payout: paid });
    if (paid > 0 && paid >= staked * BROADCAST_MIN_X) {
      broadcastGameWin({ game: GAME, userId: p.userId, name: p.name, avatar: p.avatarUrl, prize: paid,
        x: Math.round((paid / staked) * 10) / 10, tier: 'big', at: new Date().toISOString() });
    }
    await recordDaily(p, staked, paid).catch(err => console.error('[carwheel] daily stat failed', err));
  }
  if (r.dbId != null) {
    await prisma.carWheelStake.updateMany({ where: { roundId: r.dbId, status: 'open' }, data: { status: 'settled' } });
    await prisma.carWheelRound.update({ where: { id: r.dbId },
      data: { result, totalBet, players: playerCount, settledAt: new Date() } });
  }
  winners.sort((a, b) => b.payout - a.payout);
  r.winners = winners.slice(0, 5);
  results.push({ round: roundNo(), number: result, at: Date.now() });
  if (results.length > 100) results.splice(0, results.length - 100);

}

// ── Round engine ────────────────────────────────────────────
function schedule(r: Round, phase: Phase) {
  if (timer) clearTimeout(timer);
  r.phase = phase;
  r.endsAt = Date.now() + PHASE_MS[phase];
  timer = setTimeout(() => { advance().catch(err => console.error('[carwheel] advance failed', err)); }, PHASE_MS[phase]);
}

async function advance() {
  const r = round;
  if (!r) return;
  if (r.phase === 'betting') {
    schedule(r, 'closing');
    // Let charges/refunds already in flight finish before locking stake value.
    await Promise.all([...locks.values()]);
    const live = [...r.players.values()].filter(p => sum(p.stakes) > 0);
    if (!live.length) { startRound(); return; }
    // Stakes can no longer come back: split them and deliver their XP.
    for (const p of live) {
      grantStakeValue(p.userId, GAME, sum(p.stakes), `round:${r.dbId}`)
        .catch(err => console.error('[carwheel] stake value grant failed', { userId: p.userId, err }));
    }
    broadcast();
    return;
  }
  if (r.phase === 'closing') {
    r.result = rollFromSeed(r.seed, r.dbId!);
    schedule(r, 'spinning');
    broadcast();
    return;
  }
  if (r.phase === 'spinning') {
    if (timer) clearTimeout(timer);
    // Finish settlement before starting the result timer and revealing the seed.
    // A failed settlement is logged, never allowed to stop the table.
    await settle(r).catch(err => console.error('[carwheel] settle error', err));
    schedule(r, 'result');
    io?.to(CAR_WHEEL_ROOM).emit('carwheel_result', { round: roundNo(), result: r.result, seed: r.seed, winners: r.winners });
    broadcast();
    return;
  }
  startRound();
}

function startRound() {
  const seed = crypto.randomBytes(16).toString('hex');
  round = { dbId: null, phase: 'betting', endsAt: 0, seed, seedHash: crypto.createHash('sha256').update(seed).digest('hex'),
    result: null, players: new Map(), winners: [] };
  schedule(round, 'betting');
  broadcast();
}

/** Chips left `open` by a process that stopped before settling are refunded. */
export async function refundOrphans() {
  const open = await prisma.carWheelStake.findMany({ where: { status: 'open' }, select: { id: true } });
  if (open.length) {
    await refundChips(open.map(c => c.id));
    console.log(`[carwheel] refunded ${open.length} chip(s) from an unfinished round`);
  }
}

async function hydrate() {
  const last = await prisma.carWheelRound.findMany({ where: { settledAt: { not: null } }, orderBy: { id: 'desc' }, take: 50,
    select: { id: true, result: true, settledAt: true } });
  for (const row of last.reverse()) results.push({ round: row.id, number: row.result!, at: row.settledAt!.getTime() });
  const top = await prisma.carWheelRound.aggregate({ _max: { id: true } });
  nextRoundNo = (top._max.id ?? 0) + 1;
}

export async function startCarWheelEngine(server: Server) {
  if (io) return;
  io = server;
  try {
    await refundOrphans();
    await hydrate();
  } catch (err) {
    console.error('[carwheel] boot recovery failed', err);
  }
  startRound();
  console.log('[carwheel] engine started — eight weighted segments');
}

export function stopCarWheelEngine() {
  if (timer) clearTimeout(timer);
  if (broadcastTimer) clearTimeout(broadcastTimer);
  timer = broadcastTimer = null;
  round = null;
  io = null;
  results.length = 0;
  lastStakes.clear();
}

// ── Reads ───────────────────────────────────────────────────
/** The player's last 50 rounds with their stakes and what they paid. */
export async function getHistory(userId: number) {
  const recent = await prisma.carWheelRound.findMany({
    where: { settledAt: { not: null }, stakes: { some: { userId, status: 'settled' } } },
    orderBy: { id: 'desc' }, take: 50, select: { id: true },
  });
  const chips = await prisma.carWheelStake.findMany({ where: { userId, status: 'settled', roundId: { in: recent.map(r => r.id) } },
    orderBy: { id: 'desc' }, include: { round: { select: { id: true, result: true, settledAt: true } } } });
  const byRound = new Map<number, { round: number; at: string; result: string; stakes: Record<string, number> }>();
  for (const c of chips) {
    if (c.round.result == null) continue;
    let row = byRound.get(c.roundId);
    if (!row) {
      if (byRound.size >= 50) continue;
      row = { round: c.roundId, at: (c.round.settledAt ?? c.createdAt).toISOString(), result: c.round.result, stakes: {} };
      byRound.set(c.roundId, row);
    }
    row.stakes[c.betKey] = (row.stakes[c.betKey] ?? 0) + c.amount;
  }
  return [...byRound.values()].map(r => ({ ...r, bet: Object.values(r.stakes).reduce((a, b) => a + b, 0),
    prize: payoutFor(r.stakes, r.result) }));
}

/** Today's best net winners (UTC day). */
export async function getRanking(userId: number) {
  const day = new Date().toISOString().slice(0, 10);
  const rows = await prisma.gameDailyStat.findMany({ where: { game: GAME, day, net: { gt: 0 } }, orderBy: { net: 'desc' }, take: 20,
    include: { user: { select: { name: true, avatarUrl: true } } } });
  const mine = await prisma.gameDailyStat.findUnique({ where: { game_day_userId: { game: GAME, day, userId } } });
  const rank = rows.findIndex(r => r.userId === userId);
  return {
    day,
    entries: rows.map((r, i) => ({ rank: i + 1, userId: r.userId, name: r.user?.name ?? 'لاعب', avatarUrl: r.user?.avatarUrl ?? null, net: r.net })),
    me: { rank: rank < 0 ? null : rank + 1, net: mine?.net ?? 0, wagered: mine?.wagered ?? 0, best: mine?.best ?? 0 },
  };
}

export const __test = { advance, getRound: () => round, results, lastStakes, setIo: (s: Server | null) => { io = s; } };
