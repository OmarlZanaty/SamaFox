import crypto from 'crypto';
import { Server } from 'socket.io';
import prisma from '../utils/prisma';

// ============================================================
// طيّار — CRASH (Aviator-style), real coins
// ============================================================
// Round loop: betting (5s) → flying (until the plane crashes) → crashed (4s).
//
// The multiplier is a pure function of elapsed flight time, so every client
// animates the same curve locally and the server never streams ticks. The
// server owns the crash point, the clock and every coin movement.
//
// Fairness is provable: a secret server seed is drawn per round and its SHA-256
// hash is published BEFORE betting opens. Players contribute client seeds. When
// the round ends the server seed is revealed, so anyone can recompute the crash
// point from (serverSeed, clientSeeds, nonce) and check it against what they
// saw. See `verifyCrashPoint` — the client runs the same formula.
//
// NOTE: this is a wagering game — a stake on a random outcome, with total loss
// if you do not cash out. It deliberately breaks the "no قمار" rule the rest of
// the games follow (see skillDice / skillWheel / boxing); the client asked for
// the original Aviator mechanics first, to be de-gambled in a later pass.
// ============================================================

// ── Economy ─────────────────────────────────────────────────
export const CRASH_MIN_BET = Number(process.env.CRASH_MIN_BET ?? 100);
export const CRASH_MAX_BET = Number(process.env.CRASH_MAX_BET ?? 500_000);
export const CRASH_SLOTS = 2; // two independent bet panels, as in Aviator
export const CRASH_MAX_MULTIPLIER = 1000;

/** 1-in-N rounds bust instantly at 1.00x. N = 33 gives a 3% house edge (97% RTP). */
const HOUSE_EDGE_DIVISOR = Number(process.env.CRASH_EDGE_DIVISOR ?? 33);

/**
 * Multiplier growth per millisecond of flight: m(t) = e^(GROWTH * t).
 * 0.0001 → 2x at ~6.9s, 10x at ~23s. The Flutter screen uses the same constant.
 */
export const CRASH_GROWTH = 0.0001;

export const multiplierAt = (elapsedMs: number) =>
  Math.max(1, Math.exp(CRASH_GROWTH * Math.max(0, elapsedMs)));

/** Inverse of `multiplierAt` — how long the plane must fly to reach `m`. */
export const msToReach = (m: number) => Math.log(Math.max(1, m)) / CRASH_GROWTH;

const BETTING_MS = 5_000;
const CRASHED_MS = 4_000;

export const CRASH_ROOM = 'crash:main';

// ── Provably fair ───────────────────────────────────────────
const sha256 = (input: string) => crypto.createHash('sha256').update(input).digest('hex');

export const roundHashInput = (serverSeed: string, clientSeeds: string[], nonce: number) =>
  `${serverSeed}:${clientSeeds.join(',')}:${nonce}`;

/**
 * The bustabit crash formula. Exported so the verification endpoint, the tests
 * and the client all derive the point the exact same way.
 */
export function crashPointFromHash(hash: string): number {
  // 1-in-33 instant bust — this is where the whole house edge lives.
  const seedInt = BigInt('0x' + hash);
  if (seedInt % BigInt(HOUSE_EDGE_DIVISOR) === BigInt(0)) return 1.0;

  const h = parseInt(hash.slice(0, 13), 16); // 52 bits
  const e = 2 ** 52;
  const point = Math.floor((100 * e - h) / (e - h)) / 100;
  return Math.min(CRASH_MAX_MULTIPLIER, Math.max(1, point));
}

export function verifyCrashPoint(serverSeed: string, clientSeeds: string[], nonce: number) {
  const hash = sha256(roundHashInput(serverSeed, clientSeeds, nonce));
  return { hash, crashPoint: crashPointFromHash(hash) };
}

// ── Types ───────────────────────────────────────────────────
type Phase = 'betting' | 'flying' | 'crashed';

interface Bet {
  betId: string;
  userId: number;
  name: string;
  avatarUrl: string | null;
  slot: number;
  amount: number;
  autoCashOut: number | null;
  cashOutMultiplier: number | null;
  payout: number;
  status: 'pending' | 'win' | 'loss' | 'cancelled';
  betTime: number;
  cashOutTime: number | null;
}

interface Round {
  id: number;
  nonce: number;
  phase: Phase;
  serverSeed: string;
  serverSeedHash: string;
  clientSeeds: string[];
  crashPoint: number;
  hash: string;
  endsAt: number; // betting/crashed phases only
  startTime: number | null; // flight start
  endTime: number | null;
  bets: Map<string, Bet>; // key: `${userId}:${slot}`
}

interface HistoryEntry {
  roundId: number;
  nonce: number;
  crashPoint: number;
  serverSeed: string;
  serverSeedHash: string;
  clientSeeds: string[];
  hash: string;
  startTime: number | null;
  endTime: number | null;
}

interface ChatMessage {
  id: string;
  userId: number;
  name: string;
  avatarUrl: string | null;
  text: string;
  at: number;
}

interface Rain {
  id: string;
  amount: number;
  claimsLeft: number;
  expiresAt: number;
  claimed: Set<number>;
}

let io: Server | null = null;
let round: Round | null = null;
let timer: NodeJS.Timeout | null = null;
const autoTimers: NodeJS.Timeout[] = [];
let nextRoundId = 1;
let nonce = 0;

const history: HistoryEntry[] = [];
const chat: ChatMessage[] = [];
let rain: Rain | null = null;

/** Per-user seeds, kept between rounds so a player can pin their own seed. */
const clientSeeds = new Map<number, string>();

export function setClientSeed(userId: number, seed: string) {
  const clean = String(seed).slice(0, 64).replace(/[^\w-]/g, '');
  if (!clean) return { ok: false as const, message: 'بذرة غير صالحة' };
  clientSeeds.set(userId, clean);
  return { ok: true as const, clientSeed: clean };
}

export const getClientSeed = (userId: number) =>
  clientSeeds.get(userId) ?? `u${userId}`;

// ── Public views ────────────────────────────────────────────
const publicBet = (b: Bet) => ({
  betId: b.betId,
  userId: b.userId,
  name: b.name,
  avatarUrl: b.avatarUrl,
  slot: b.slot,
  amount: b.amount,
  autoCashOut: b.autoCashOut,
  cashOutMultiplier: b.cashOutMultiplier,
  payout: b.payout,
  status: b.status,
});

export function getCrashStatePublic() {
  if (!round) return null;
  const now = Date.now();
  return {
    roundId: round.id,
    nonce: round.nonce,
    phase: round.phase,
    serverSeedHash: round.serverSeedHash,
    // Revealed only once the round is over.
    serverSeed: round.phase === 'crashed' ? round.serverSeed : null,
    crashPoint: round.phase === 'crashed' ? round.crashPoint : null,
    msLeft: round.phase === 'flying' ? 0 : Math.max(0, round.endsAt - now),
    startTime: round.startTime,
    elapsedMs: round.startTime ? Math.max(0, now - round.startTime) : 0,
    minBet: CRASH_MIN_BET,
    maxBet: CRASH_MAX_BET,
    slots: CRASH_SLOTS,
    bets: Array.from(round.bets.values()).filter((b) => b.status !== 'cancelled').map(publicBet),
    history: history.slice(0, 30).map((h) => ({ roundId: h.roundId, crashPoint: h.crashPoint })),
    rain: rain ? { id: rain.id, amount: rain.amount, claimsLeft: rain.claimsLeft, expiresAt: rain.expiresAt } : null,
  };
}

const broadcast = () => io?.to(CRASH_ROOM).emit('crash_state', getCrashStatePublic());

const broadcastBets = () =>
  io?.to(CRASH_ROOM).emit('crash_bets', {
    roundId: round?.id ?? 0,
    bets: round ? Array.from(round.bets.values()).filter((b) => b.status !== 'cancelled').map(publicBet) : [],
  });

export const getCrashHistory = (limit = 50) =>
  history.slice(0, limit).map((h) => ({
    roundId: h.roundId,
    nonce: h.nonce,
    crashPoint: h.crashPoint,
    serverSeedHash: h.serverSeedHash,
    serverSeed: h.serverSeed,
    clientSeeds: h.clientSeeds,
    hash: h.hash,
    startTime: h.startTime,
    endTime: h.endTime,
  }));

export const getCrashRoundFairness = (roundId: number) =>
  getCrashHistory(history.length).find((h) => h.roundId === roundId) ?? null;

export const getCrashChat = (limit = 50) => chat.slice(-limit);

// ── Betting ─────────────────────────────────────────────────
const key = (userId: number, slot: number) => `${userId}:${slot}`;

export async function placeCrashBet(
  userId: number,
  slot: number,
  amount: number,
  autoCashOut: number | null,
) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'انتهى وقت الرهان' };
  }
  if (!Number.isInteger(slot) || slot < 0 || slot >= CRASH_SLOTS) {
    return { ok: false as const, code: 'BAD_SLOT', message: 'لوحة رهان غير صحيحة' };
  }
  if (!Number.isFinite(amount) || !Number.isInteger(amount) || amount < CRASH_MIN_BET || amount > CRASH_MAX_BET) {
    return { ok: false as const, code: 'BAD_AMOUNT', message: `الرهان بين ${CRASH_MIN_BET} و ${CRASH_MAX_BET}` };
  }
  if (autoCashOut != null && (!Number.isFinite(autoCashOut) || autoCashOut < 1.01 || autoCashOut > CRASH_MAX_MULTIPLIER)) {
    return { ok: false as const, code: 'BAD_AUTO', message: 'مضاعف السحب التلقائي غير صحيح' };
  }
  if (round.bets.has(key(userId, slot))) {
    return { ok: false as const, code: 'ALREADY_BET', message: 'لديك رهان على هذه اللوحة' };
  }

  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: amount } },
    data: { coinsBalance: { decrement: amount } },
  });
  if (charged.count === 0) {
    return { ok: false as const, code: 'INSUFFICIENT_COINS', message: 'رصيدك لا يكفي' };
  }

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { name: true, avatarUrl: true, coinsBalance: true },
  });

  // The betting window can close while the charge is in flight — refund rather
  // than silently keeping the money.
  if (!round || round.phase !== 'betting') {
    await prisma.user.update({ where: { id: userId }, data: { coinsBalance: { increment: amount } } });
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'انتهى وقت الرهان' };
  }

  const seed = getClientSeed(userId);
  if (!round.clientSeeds.includes(seed)) round.clientSeeds.push(seed);

  round.bets.set(key(userId, slot), {
    betId: `${round.id}-${userId}-${slot}`,
    userId,
    name: user?.name ?? 'لاعب',
    avatarUrl: user?.avatarUrl ?? null,
    slot,
    amount,
    autoCashOut,
    cashOutMultiplier: null,
    payout: 0,
    status: 'pending',
    betTime: Date.now(),
    cashOutTime: null,
  });
  broadcastBets();

  return {
    ok: true as const,
    roundId: round.id,
    balance: user?.coinsBalance ?? 0,
    serverSeedHash: round.serverSeedHash,
    clientSeed: seed,
  };
}

export async function cancelCrashBet(userId: number, slot: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'لا يمكن الإلغاء بعد الإقلاع' };
  }
  const bet = round.bets.get(key(userId, slot));
  if (!bet || bet.status !== 'pending') {
    return { ok: false as const, code: 'NO_BET', message: 'لا يوجد رهان للإلغاء' };
  }

  bet.status = 'cancelled';
  round.bets.delete(key(userId, slot));
  const user = await prisma.user.update({
    where: { id: userId },
    data: { coinsBalance: { increment: bet.amount } },
    select: { coinsBalance: true },
  });
  broadcastBets();
  return { ok: true as const, balance: user.coinsBalance, refunded: bet.amount };
}

/** Settle one bet at `multiplier` and pay it out. Shared by manual and auto. */
async function payOut(bet: Bet, multiplier: number) {
  const m = Math.floor(multiplier * 100) / 100; // never round in the player's favour
  bet.cashOutMultiplier = m;
  bet.payout = Math.floor(bet.amount * m);
  bet.status = 'win';
  bet.cashOutTime = Date.now();

  let balance = 0;
  try {
    const user = await prisma.user.update({
      where: { id: bet.userId },
      data: { coinsBalance: { increment: bet.payout } },
      select: { coinsBalance: true },
    });
    balance = user.coinsBalance;
  } catch (err) {
    console.error('[crash] payout failed', { userId: bet.userId, payout: bet.payout, err });
  }

  io?.to(CRASH_ROOM).emit('crash_cashout', {
    roundId: round?.id ?? 0,
    userId: bet.userId,
    name: bet.name,
    avatarUrl: bet.avatarUrl,
    slot: bet.slot,
    amount: bet.amount,
    multiplier: m,
    payout: bet.payout,
  });
  broadcastBets();
  return balance;
}

export async function cashOutCrashBet(userId: number, slot: number) {
  if (!round || round.phase !== 'flying' || !round.startTime) {
    return { ok: false as const, code: 'NOT_FLYING', message: 'الطائرة ليست في الجو' };
  }
  const bet = round.bets.get(key(userId, slot));
  if (!bet || bet.status !== 'pending') {
    return { ok: false as const, code: 'NO_BET', message: 'لا يوجد رهان نشط' };
  }

  const m = multiplierAt(Date.now() - round.startTime);
  // Guard the boundary: a request that lands after the crash loses, whatever
  // the client's own animation was showing.
  if (m > round.crashPoint) {
    return { ok: false as const, code: 'TOO_LATE', message: 'فات الأوان — طارت الطائرة' };
  }

  const balance = await payOut(bet, m);
  return { ok: true as const, multiplier: bet.cashOutMultiplier!, payout: bet.payout, balance };
}

// ── Round loop ──────────────────────────────────────────────
function clearAutoTimers() {
  while (autoTimers.length) clearTimeout(autoTimers.pop()!);
}

/** Arm one timer per auto-cash-out that would fire before the crash. */
function armAutoCashOuts(r: Round) {
  for (const bet of r.bets.values()) {
    const target = bet.autoCashOut;
    if (!target || bet.status !== 'pending') continue;
    if (target > r.crashPoint) continue; // this one busts

    const delay = Math.max(0, msToReach(target) - (Date.now() - (r.startTime ?? Date.now())));
    autoTimers.push(
      setTimeout(() => {
        if (round !== r || r.phase !== 'flying' || bet.status !== 'pending') return;
        payOut(bet, target).catch((err) => console.error('[crash] auto cashout failed', err));
      }, delay),
    );
  }
}

async function settleCrash(r: Round) {
  clearAutoTimers();

  // Anyone still pending when the plane flew away loses their stake — it was
  // already debited when the bet was placed, so nothing moves here.
  for (const bet of r.bets.values()) {
    if (bet.status === 'pending') {
      bet.status = 'loss';
      bet.payout = 0;
    }
  }

  r.endTime = Date.now();
  history.unshift({
    roundId: r.id,
    nonce: r.nonce,
    crashPoint: r.crashPoint,
    serverSeed: r.serverSeed,
    serverSeedHash: r.serverSeedHash,
    clientSeeds: [...r.clientSeeds],
    hash: r.hash,
    startTime: r.startTime,
    endTime: r.endTime,
  });
  if (history.length > 200) history.length = 200;
  recordLedger(r);

  io?.to(CRASH_ROOM).emit('crash_crashed', {
    roundId: r.id,
    crashPoint: r.crashPoint,
    serverSeed: r.serverSeed,
    serverSeedHash: r.serverSeedHash,
    clientSeeds: r.clientSeeds,
    nonce: r.nonce,
    hash: r.hash,
    results: Array.from(r.bets.values()).map(publicBet),
  });

  maybeStartRain();
}

function advance() {
  if (!round) return;
  const r = round;

  if (r.phase === 'betting') {
    r.phase = 'flying';
    r.startTime = Date.now();
    io?.to(CRASH_ROOM).emit('crash_takeoff', {
      roundId: r.id,
      startTime: r.startTime,
      growth: CRASH_GROWTH,
    });
    broadcast();
    armAutoCashOuts(r);
    timer = setTimeout(advance, msToReach(r.crashPoint));
    return;
  }

  if (r.phase === 'flying') {
    r.phase = 'crashed';
    r.endsAt = Date.now() + CRASHED_MS;
    settleCrash(r).catch((err) => console.error('[crash] settle error', err));
    broadcast();
    timer = setTimeout(advance, CRASHED_MS);
    return;
  }

  startNewRound();
}

function startNewRound() {
  const serverSeed = crypto.randomBytes(16).toString('hex');
  nonce += 1;

  // The hash committed here covers the seeds known now. Seeds joined by players
  // who bet during this window are appended and included in the final hash —
  // which is why the reveal ships the full seed list back to the client.
  const r: Round = {
    id: nextRoundId++,
    nonce,
    phase: 'betting',
    serverSeed,
    serverSeedHash: sha256(serverSeed),
    clientSeeds: [],
    crashPoint: 1,
    hash: '',
    endsAt: Date.now() + BETTING_MS,
    startTime: null,
    endTime: null,
    bets: new Map(),
  };
  round = r;
  broadcast();

  // Resolve the crash point at the very end of betting, once every client seed
  // for the round is in.
  timer = setTimeout(() => {
    const { hash, crashPoint } = verifyCrashPoint(r.serverSeed, r.clientSeeds, r.nonce);
    r.hash = hash;
    r.crashPoint = crashPoint;
    advance();
  }, BETTING_MS);
}

// ── Chat ────────────────────────────────────────────────────
export async function postCrashChat(userId: number, text: string) {
  const clean = String(text ?? '').trim().slice(0, 200);
  if (!clean) return { ok: false as const, code: 'EMPTY', message: 'الرسالة فارغة' };

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { name: true, avatarUrl: true },
  });

  const message: ChatMessage = {
    id: `${Date.now()}-${userId}`,
    userId,
    name: user?.name ?? 'لاعب',
    avatarUrl: user?.avatarUrl ?? null,
    text: clean,
    at: Date.now(),
  };
  chat.push(message);
  if (chat.length > 200) chat.splice(0, chat.length - 200);

  io?.to(CRASH_ROOM).emit('crash_chat', message);
  return { ok: true as const, message };
}

// ── Rain ────────────────────────────────────────────────────
const RAIN_CHANCE = Number(process.env.CRASH_RAIN_CHANCE ?? 0.06);
const RAIN_AMOUNT = Number(process.env.CRASH_RAIN_AMOUNT ?? 500);
const RAIN_CLAIMS = Number(process.env.CRASH_RAIN_CLAIMS ?? 10);
const RAIN_WINDOW_MS = 30_000;

function maybeStartRain() {
  if (rain && rain.expiresAt > Date.now() && rain.claimsLeft > 0) return;
  if (Math.random() > RAIN_CHANCE) return;

  rain = {
    id: `rain-${Date.now()}`,
    amount: RAIN_AMOUNT,
    claimsLeft: RAIN_CLAIMS,
    expiresAt: Date.now() + RAIN_WINDOW_MS,
    claimed: new Set(),
  };
  io?.to(CRASH_ROOM).emit('crash_rain', {
    id: rain.id,
    amount: rain.amount,
    claimsLeft: rain.claimsLeft,
    expiresAt: rain.expiresAt,
  });
}

export async function claimCrashRain(userId: number) {
  if (!rain || rain.expiresAt <= Date.now() || rain.claimsLeft <= 0) {
    return { ok: false as const, code: 'NO_RAIN', message: 'لا يوجد مطر متاح الآن' };
  }
  if (rain.claimed.has(userId)) {
    return { ok: false as const, code: 'ALREADY_CLAIMED', message: 'حصلت على نصيبك بالفعل' };
  }

  rain.claimed.add(userId);
  rain.claimsLeft -= 1;
  const amount = rain.amount;

  const user = await prisma.user.update({
    where: { id: userId },
    data: { coinsBalance: { increment: amount } },
    select: { coinsBalance: true },
  });

  io?.to(CRASH_ROOM).emit('crash_rain_claimed', {
    id: rain.id,
    userId,
    claimsLeft: rain.claimsLeft,
  });
  return { ok: true as const, amount, balance: user.coinsBalance };
}

// ── Player stats ────────────────────────────────────────────
/** Derived from the in-memory history window — no schema change needed. */
export function getCrashPlayerStats(userId: number) {
  let rounds = 0;
  let wagered = 0;
  let won = 0;
  let wins = 0;
  let bestMultiplier = 0;
  let bestPayout = 0;
  let multiplierSum = 0;

  for (const h of history) {
    multiplierSum += h.crashPoint;
  }

  for (const bet of playerLedger.get(userId) ?? []) {
    rounds += 1;
    wagered += bet.amount;
    won += bet.payout;
    if (bet.status === 'win') {
      wins += 1;
      bestMultiplier = Math.max(bestMultiplier, bet.cashOutMultiplier ?? 0);
      bestPayout = Math.max(bestPayout, bet.payout);
    }
  }

  return {
    rounds,
    wagered,
    won,
    net: won - wagered,
    wins,
    losses: rounds - wins,
    bestMultiplier,
    bestPayout,
    averageRoundMultiplier: history.length ? multiplierSum / history.length : 0,
  };
}

/** Last 100 settled bets per player, for the stats panel and bet history. */
const playerLedger = new Map<number, Bet[]>();

export const getCrashPlayerBets = (userId: number, limit = 50) =>
  (playerLedger.get(userId) ?? []).slice(0, limit).map((b) => ({
    betId: b.betId,
    amount: b.amount,
    cashOutMultiplier: b.cashOutMultiplier,
    payout: b.payout,
    status: b.status,
    betTime: b.betTime,
    cashOutTime: b.cashOutTime,
  }));

function recordLedger(r: Round) {
  for (const bet of r.bets.values()) {
    if (bet.status === 'cancelled') continue;
    const list = playerLedger.get(bet.userId) ?? [];
    list.unshift(bet);
    if (list.length > 100) list.length = 100;
    playerLedger.set(bet.userId, list);
  }
}

// ── Engine lifecycle ────────────────────────────────────────
export function startCrashEngine(server: Server) {
  if (io) return; // already running
  io = server;
  startNewRound();
  console.log('[crash] round engine started');
}

export function stopCrashEngine() {
  if (timer) clearTimeout(timer);
  clearAutoTimers();
  timer = null;
  round = null;
  io = null;
}
