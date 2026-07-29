import { Server } from 'socket.io';
import crypto from 'crypto';
import prisma from '../utils/prisma';

// ============================================================
// عجلة الحظ — CRAZY WHEEL (54-segment live wheel, Crazy Time format)
// ============================================================
// NOTE ON THE HOUSE RULE: every other game in this project follows the halal
// model (fixed entry price, guaranteed return, no wager on an outcome — see
// skillWheel.service.ts). This game does NOT: it is the classic bet-on-a-
// segment format the client asked for, built to spec, with the halal economy
// layer to be applied across all five games afterwards. Everything that decides
// money lives in this file, so that conversion is a change to the payout
// helpers only — the wheel, the top slot and the bonus games stay as they are.
//
// Round shape:
//   betting (20s) → spinning (9s) → [bonus pick (10s) → bonus reveal (8s)]
//   → result (7s) → next round
//
// The server owns the RNG, the top slot, every bonus outcome and every payout.
// The client animates what the server already decided; a tampered client can
// change nothing but its own animation.
// ============================================================

export const CRAZY_ROOM = 'crazy-wheel:main';

export const CHIP_TIERS = [1000, 5000, 10000, 50000, 100000];
export const MIN_BET = 1000;
export const MAX_BET_PER_SEGMENT = 5_000_000;

// ── Wheel layout ────────────────────────────────────────────
export type SegmentKey = '1' | '2' | '5' | '10' | 'coinflip' | 'cashhunt' | 'pachinko' | 'crazytime';

export const BET_SPOTS: SegmentKey[] = [
  '1', '2', '5', '10', 'coinflip', 'cashhunt', 'pachinko', 'crazytime',
];

/** Base payout as "x to 1" — a winning bet returns stake * (payout + 1). */
const BASE_PAYOUT: Record<SegmentKey, number> = {
  '1': 1, '2': 2, '5': 5, '10': 10,
  // Bonus spots have no base odds: the bonus game itself produces the
  // multiplier, and the stake is returned as part of it.
  coinflip: 0, cashhunt: 0, pachinko: 0, crazytime: 0,
};

/** Segment counts, exactly per spec: 45 number + 9 bonus = 54. */
const SEGMENT_COUNTS: Record<SegmentKey, number> = {
  '1': 21, '2': 13, '5': 7, '10': 4,
  coinflip: 4, cashhunt: 2, pachinko: 2, crazytime: 1,
};

/**
 * The physical ring, built once. The order matters for the animation only —
 * the result is drawn by segment index, so the ring is what the client rotates
 * to. Bonus segments are spread out rather than clustered so the wheel reads
 * like the real thing.
 */
export const WHEEL: SegmentKey[] = buildWheel();

function buildWheel(): SegmentKey[] {
  // Start from a pool, then lay it out by walking a fixed stride around the
  // ring so identical segments never bunch together.
  const pool: SegmentKey[] = [];
  (Object.keys(SEGMENT_COUNTS) as SegmentKey[]).forEach((k) => {
    for (let i = 0; i < SEGMENT_COUNTS[k]; i++) pool.push(k);
  });

  const size = pool.length; // 54
  const ring: (SegmentKey | null)[] = new Array(size).fill(null);

  // Place the rare segments first, evenly spaced, then fill the rest with the
  // common ones — this is what gives the real wheel its "1 between everything"
  // texture.
  const order: SegmentKey[] = ['crazytime', 'pachinko', 'cashhunt', '10', 'coinflip', '5', '2', '1'];
  let cursor = 0;
  for (const key of order) {
    const count = SEGMENT_COUNTS[key];
    const stride = Math.floor(size / count);
    for (let i = 0; i < count; i++) {
      let slot = (cursor + i * stride) % size;
      // Walk forward to the next free slot if the ideal one is taken.
      let guard = 0;
      while (ring[slot] !== null && guard++ < size) slot = (slot + 1) % size;
      ring[slot] = key;
    }
    cursor += 1; // offset each family so they interleave
  }

  return ring.map((s) => s ?? '1');
}

export const SEGMENT_COLORS: Record<SegmentKey, string> = {
  '1': '#1E88E5', '2': '#FDD835', '5': '#EC407A', '10': '#8E24AA',
  coinflip: '#E53935', cashhunt: '#2E7D32', pachinko: '#D81B60', crazytime: '#C62828',
};

// ── RNG ─────────────────────────────────────────────────────
/** Cryptographically strong integer in [0, max). */
function randInt(max: number): number {
  if (max <= 0) return 0;
  return crypto.randomInt(0, max);
}

function pick<T>(arr: readonly T[]): T {
  return arr[randInt(arr.length)]!;
}

// ── Top slot ────────────────────────────────────────────────
const TOP_SLOT_MULTIPLIERS = [2, 3, 4, 5, 7, 10, 15, 20, 25, 50];

interface TopSlot {
  spot: SegmentKey;
  multiplier: number;
}

function rollTopSlot(): TopSlot {
  return { spot: pick(BET_SPOTS), multiplier: pick(TOP_SLOT_MULTIPLIERS) };
}

// ── Bonus games ─────────────────────────────────────────────
export type BonusKind = 'coinflip' | 'cashhunt' | 'pachinko' | 'crazytime';

/** Coin Flip: two multipliers, a coin decides which one pays. */
interface CoinFlipResult {
  kind: 'coinflip';
  red: number;
  blue: number;
  winner: 'red' | 'blue';
  multiplier: number;
}

function rollCoinFlip(): CoinFlipResult {
  const values = [2, 3, 4, 5, 7, 10, 15, 20, 25, 30, 40, 50, 75, 100];
  const red = pick(values);
  const blue = pick(values);
  const winner = randInt(2) === 0 ? 'red' : 'blue';
  return { kind: 'coinflip', red, blue, winner, multiplier: winner === 'red' ? red : blue };
}

/** Cash Hunt: 108 multipliers behind symbols; every player picks one tile. */
interface CashHuntResult {
  kind: 'cashhunt';
  grid: number[]; // 108 multipliers, index = tile
  symbols: number[]; // 108 symbol ids for the shuffle animation
}

function rollCashHunt(): CashHuntResult {
  // Weighted so the board is mostly small values with a handful of big ones —
  // the same shape as the televised game.
  const bag: number[] = [];
  const weights: [number, number][] = [
    [5, 30], [7, 20], [10, 15], [15, 12], [20, 9], [25, 7],
    [35, 5], [50, 4], [75, 3], [100, 2], [200, 1],
  ];
  for (const [value, count] of weights) for (let i = 0; i < count; i++) bag.push(value);
  while (bag.length < 108) bag.push(5);

  // Fisher-Yates with the crypto RNG.
  for (let i = bag.length - 1; i > 0; i--) {
    const j = randInt(i + 1);
    [bag[i], bag[j]] = [bag[j]!, bag[i]!];
  }
  const symbols = bag.map(() => randInt(6));
  return { kind: 'cashhunt', grid: bag.slice(0, 108), symbols };
}

/** Pachinko: the puck drops through 16 rows of pegs into a slot. */
interface PachinkoResult {
  kind: 'pachinko';
  drops: {
    slots: number[]; // slot labels for this drop (0 = DOUBLE)
    path: number[]; // per-row left(-1)/right(1) bounces, for the animation
    landed: number; // slot index
    value: number; // 0 means DOUBLE
  }[];
  multiplier: number; // final, after any DOUBLEs
}

function rollPachinko(): PachinkoResult {
  const ROWS = 16;
  const SLOTS = 17;
  let slots = buildPachinkoSlots(1);
  const drops: PachinkoResult['drops'] = [];
  let doubles = 0;

  // A DOUBLE re-drops the puck with every value doubled. Cap the chain so a
  // pathological run can't spin forever (the real game caps it the same way).
  for (let attempt = 0; attempt < 8; attempt++) {
    const path: number[] = [];
    let position = 0;
    for (let r = 0; r < ROWS; r++) {
      const dir = randInt(2) === 0 ? -1 : 1;
      path.push(dir);
      position += dir;
    }
    // Map the -16..16 walk onto 0..SLOTS-1.
    const landed = Math.min(SLOTS - 1, Math.max(0, Math.round((position + ROWS) / 2)));
    const value = slots[landed] ?? 0;
    drops.push({ slots: [...slots], path, landed, value });

    if (value === 0 && attempt < 7) {
      doubles++;
      slots = buildPachinkoSlots(Math.pow(2, doubles));
      continue;
    }
    // A DOUBLE on the very last allowed drop still has to pay something.
    return { kind: 'pachinko', drops, multiplier: value === 0 ? slots[landed - 1] ?? 10 : value };
  }
  return { kind: 'pachinko', drops, multiplier: 10 };
}

/** Slot labels: small at the edges, DOUBLE (0) in the middle. */
function buildPachinkoSlots(scale: number): number[] {
  const base = [8, 10, 12, 15, 20, 25, 40, 50, 0, 50, 40, 25, 20, 15, 12, 10, 8];
  return base.map((v) => (v === 0 ? 0 : v * scale));
}

/** Crazy Time: 64-segment virtual wheel, three flappers, DOUBLE/TRIPLE. */
interface CrazyTimeResult {
  kind: 'crazytime';
  spins: {
    ring: (number | 'x2' | 'x3')[]; // 64 segments
    landed: Record<'blue' | 'green' | 'yellow', number>; // segment index per flapper
  }[];
  /** Final multiplier per flapper colour, after DOUBLE/TRIPLE chains. */
  multipliers: Record<'blue' | 'green' | 'yellow', number>;
}

function buildCrazyRing(): (number | 'x2' | 'x3')[] {
  const values = [25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 120, 150, 200, 300, 500, 1000];
  const ring: (number | 'x2' | 'x3')[] = [];
  for (let i = 0; i < 64; i++) {
    if (i % 16 === 5) ring.push('x2');
    else if (i % 21 === 9) ring.push('x3');
    else ring.push(pick(values));
  }
  return ring;
}

function rollCrazyTime(): CrazyTimeResult {
  const colours = ['blue', 'green', 'yellow'] as const;
  const spins: CrazyTimeResult['spins'] = [];
  const multipliers: Record<'blue' | 'green' | 'yellow', number> = { blue: 0, green: 0, yellow: 0 };
  const pending = new Set<'blue' | 'green' | 'yellow'>(colours);
  const scale: Record<'blue' | 'green' | 'yellow', number> = { blue: 1, green: 1, yellow: 1 };

  for (let spin = 0; spin < 6 && pending.size > 0; spin++) {
    const ring = buildCrazyRing();
    const landed = { blue: randInt(64), green: randInt(64), yellow: randInt(64) };
    spins.push({ ring, landed });

    for (const colour of [...pending]) {
      const cell = ring[landed[colour]]!;
      if (cell === 'x2') scale[colour] *= 2;
      else if (cell === 'x3') scale[colour] *= 3;
      else {
        multipliers[colour] = cell * scale[colour];
        pending.delete(colour);
      }
    }
  }
  // Anything still doubling after six spins is settled at the current scale.
  for (const colour of pending) multipliers[colour] = 100 * scale[colour];

  return { kind: 'crazytime', spins, multipliers };
}

type BonusResult = CoinFlipResult | CashHuntResult | PachinkoResult | CrazyTimeResult;

// ── Round state ─────────────────────────────────────────────
type Phase = 'betting' | 'spinning' | 'bonus_pick' | 'bonus_reveal' | 'result';

const BETTING_MS = 20_000;
const SPINNING_MS = 9_000;
const BONUS_PICK_MS = 10_000;
const BONUS_REVEAL_MS = 8_000;
const RESULT_MS = 7_000;

interface PlayerBets {
  userId: number;
  name: string;
  avatarUrl: string | null;
  bets: Record<string, number>; // segment -> staked amount
  /** Bonus choice: cash-hunt tile index, or crazy-time flapper colour. */
  pick: number | string | null;
  payout: number;
  multiplier: number;
}

interface Round {
  id: number;
  phase: Phase;
  endsAt: number;
  /** Winning segment index on WHEEL; null until the spin is rolled. */
  resultIndex: number | null;
  resultSegment: SegmentKey | null;
  topSlot: TopSlot | null;
  bonus: BonusResult | null;
  players: Map<number, PlayerBets>;
  /** Server seed hash published before the spin, seed revealed after. */
  seed: string;
  seedHash: string;
}

export interface HistoryEntry {
  roundId: number;
  segment: SegmentKey;
  topSlot: TopSlot;
  multiplier: number | null;
  at: number;
}

let io: Server | null = null;
let round: Round | null = null;
let timer: NodeJS.Timeout | null = null;
let nextRoundId = 1;
const history: HistoryEntry[] = [];

// ── Public state ────────────────────────────────────────────
export function getPublicState(userId?: number) {
  if (!round) return null;
  const me = userId != null ? round.players.get(userId) : undefined;

  return {
    roundId: round.id,
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    chipTiers: CHIP_TIERS,
    betSpots: BET_SPOTS,
    seedHash: round.seedHash,
    // The seed is only revealed once the outcome is public.
    seed: round.phase === 'result' ? round.seed : null,
    // Nothing about the outcome leaks before the spin starts.
    resultIndex: round.phase === 'betting' ? null : round.resultIndex,
    resultSegment: round.phase === 'betting' ? null : round.resultSegment,
    topSlot: round.phase === 'betting' ? null : round.topSlot,
    // During the pick window the player has to SEE the board to choose a tile
    // or a flapper — but not what is behind it. So the payload goes out with
    // every value stripped, and the real one lands at the reveal.
    bonus:
      round.phase === 'bonus_reveal' || round.phase === 'result'
        ? round.bonus
        : round.phase === 'bonus_pick'
          ? maskBonus(round.bonus)
          : null,
    bonusKind: isBonus(round.resultSegment) && round.phase !== 'betting' ? round.resultSegment : null,
    totals: totalsBySegment(),
    playerCount: round.players.size,
    me: me
      ? {
          bets: me.bets,
          pick: me.pick,
          payout: round.phase === 'result' ? me.payout : 0,
          multiplier: round.phase === 'result' ? me.multiplier : 0,
        }
      : null,
    history: history.slice(-20),
  };
}

/** The pick-phase view of a bonus game: the board, none of its values. */
function maskBonus(bonus: BonusResult | null): BonusResult | null {
  if (!bonus) return null;
  if (bonus.kind === 'cashhunt') return { kind: 'cashhunt', grid: [], symbols: bonus.symbols };
  if (bonus.kind === 'crazytime') return { kind: 'crazytime', spins: [], multipliers: { blue: 0, green: 0, yellow: 0 } };
  return bonus;
}

function totalsBySegment(): Record<string, { amount: number; players: number }> {
  const totals: Record<string, { amount: number; players: number }> = {};
  for (const spot of BET_SPOTS) totals[spot] = { amount: 0, players: 0 };
  if (!round) return totals;
  for (const p of round.players.values()) {
    for (const [spot, amount] of Object.entries(p.bets)) {
      if (!totals[spot] || amount <= 0) continue;
      totals[spot]!.amount += amount;
      totals[spot]!.players += 1;
    }
  }
  return totals;
}

function isBonus(segment: SegmentKey | null): segment is BonusKind {
  return segment === 'coinflip' || segment === 'cashhunt' || segment === 'pachinko' || segment === 'crazytime';
}

function broadcast() {
  // Per-user fields (`me`) are fetched over REST; the broadcast carries the
  // shared view only.
  io?.to(CRAZY_ROOM).emit('crazy_state', getPublicState());
}

// ── Betting ─────────────────────────────────────────────────
export async function placeBet(userId: number, segment: string, amount: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الرهان' };
  }
  if (!BET_SPOTS.includes(segment as SegmentKey)) {
    return { ok: false as const, code: 'BAD_SEGMENT', message: 'خانة رهان غير صحيحة' };
  }
  if (!Number.isInteger(amount) || amount < MIN_BET) {
    return { ok: false as const, code: 'BAD_AMOUNT', message: 'قيمة رهان غير صحيحة' };
  }

  const existing = round.players.get(userId)?.bets[segment] ?? 0;
  if (existing + amount > MAX_BET_PER_SEGMENT) {
    return { ok: false as const, code: 'MAX_BET', message: 'تجاوزت الحد الأقصى للرهان' };
  }

  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: amount } },
    data: { coinsBalance: { decrement: amount } },
  });
  if (charged.count === 0) {
    return { ok: false as const, code: 'INSUFFICIENT_COINS', message: 'رصيدك لا يكفي' };
  }

  // Betting can close while the charge is in flight — refund rather than
  // silently keeping the coins.
  if (!round || round.phase !== 'betting') {
    await prisma.user.update({ where: { id: userId }, data: { coinsBalance: { increment: amount } } });
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الرهان' };
  }

  let player = round.players.get(userId);
  if (!player) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { name: true, avatarUrl: true },
    });
    player = {
      userId,
      name: user?.name ?? 'لاعب',
      avatarUrl: user?.avatarUrl ?? null,
      bets: {},
      pick: null,
      payout: 0,
      multiplier: 0,
    };
    round.players.set(userId, player);
  }
  player.bets[segment] = (player.bets[segment] ?? 0) + amount;

  const balance = await balanceOf(userId);
  broadcast();
  return { ok: true as const, bets: player.bets, balance, roundId: round.id };
}

/** Clears every bet for this round and refunds the total. Betting phase only. */
export async function clearBets(userId: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الرهان' };
  }
  const player = round.players.get(userId);
  if (!player) return { ok: true as const, bets: {}, balance: await balanceOf(userId) };

  const total = Object.values(player.bets).reduce((a, b) => a + b, 0);
  player.bets = {};
  if (total > 0) {
    await prisma.user.update({ where: { id: userId }, data: { coinsBalance: { increment: total } } });
  }
  broadcast();
  return { ok: true as const, bets: {}, balance: await balanceOf(userId) };
}

/** Re-places the exact bets from the player's previous round. */
export async function repeatBets(userId: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الرهان' };
  }
  const previous = lastBets.get(userId);
  if (!previous || Object.keys(previous).length === 0) {
    return { ok: false as const, code: 'NO_PREVIOUS', message: 'لا يوجد رهان سابق' };
  }
  for (const [segment, amount] of Object.entries(previous)) {
    const res = await placeBet(userId, segment, amount);
    if (!res.ok) return res;
  }
  return { ok: true as const, bets: round.players.get(userId)?.bets ?? {}, balance: await balanceOf(userId) };
}

/** Bonus choice: a Cash Hunt tile (0-107) or a Crazy Time flapper colour. */
export function submitPick(userId: number, pick: number | string) {
  if (!round || round.phase !== 'bonus_pick') {
    return { ok: false as const, code: 'NOT_PICKING', message: 'ليس وقت الاختيار' };
  }
  const player = round.players.get(userId);
  if (!player || (player.bets[round.resultSegment!] ?? 0) <= 0) {
    return { ok: false as const, code: 'NOT_IN_BONUS', message: 'لم تراهن على هذه الجولة' };
  }
  if (round.resultSegment === 'cashhunt') {
    const tile = Number(pick);
    if (!Number.isInteger(tile) || tile < 0 || tile > 107) {
      return { ok: false as const, code: 'BAD_PICK', message: 'اختيار غير صحيح' };
    }
    player.pick = tile;
  } else if (round.resultSegment === 'crazytime') {
    if (!['blue', 'green', 'yellow'].includes(String(pick))) {
      return { ok: false as const, code: 'BAD_PICK', message: 'اختيار غير صحيح' };
    }
    player.pick = String(pick);
  } else {
    return { ok: false as const, code: 'NO_PICK_NEEDED', message: 'هذه اللعبة لا تحتاج اختيارًا' };
  }
  return { ok: true as const, pick: player.pick };
}

const lastBets = new Map<number, Record<string, number>>();

async function balanceOf(userId: number): Promise<number> {
  const u = await prisma.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } });
  return u?.coinsBalance ?? 0;
}

// ── Settlement ──────────────────────────────────────────────
/**
 * The whole money model lives here. A winning bet returns
 *   stake * (basePayout + 1) * topSlotMultiplier   for number segments
 *   stake * bonusMultiplier * topSlotMultiplier    for bonus segments
 * and the top-slot multiplier only applies when the top slot landed on the same
 * spot the wheel did. Every other bet on the round is lost.
 */
function multiplierFor(player: PlayerBets, r: Round): number {
  const segment = r.resultSegment!;
  const topMatches = r.topSlot?.spot === segment;
  const top = topMatches ? r.topSlot!.multiplier : 1;

  if (!isBonus(segment)) return (BASE_PAYOUT[segment] + 1) * top;

  const bonus = r.bonus;
  if (!bonus) return 0;
  if (bonus.kind === 'coinflip') return bonus.multiplier * top;
  if (bonus.kind === 'pachinko') return bonus.multiplier * top;
  if (bonus.kind === 'cashhunt') {
    // A player who never picked gets a tile assigned so they are still paid.
    const tile = typeof player.pick === 'number' ? player.pick : randInt(108);
    player.pick = tile;
    return (bonus.grid[tile] ?? 5) * top;
  }
  // Crazy Time: default to blue for anyone who did not choose a flapper.
  const colour = (typeof player.pick === 'string' ? player.pick : 'blue') as 'blue' | 'green' | 'yellow';
  player.pick = colour;
  return bonus.multipliers[colour] * top;
}

async function settle(r: Round) {
  const winners: { userId: number; name: string; avatarUrl: string | null; payout: number; multiplier: number }[] = [];

  for (const player of r.players.values()) {
    const staked = player.bets[r.resultSegment!] ?? 0;
    lastBets.set(player.userId, { ...player.bets });
    if (staked <= 0) continue;

    const multiplier = multiplierFor(player, r);
    const payout = Math.floor(staked * multiplier);
    player.multiplier = multiplier;
    player.payout = payout;
    if (payout <= 0) continue;

    try {
      await prisma.user.update({
        where: { id: player.userId },
        data: { coinsBalance: { increment: payout } },
      });
      winners.push({
        userId: player.userId,
        name: player.name,
        avatarUrl: player.avatarUrl,
        payout,
        multiplier,
      });
    } catch (err) {
      console.error('[crazyWheel] payout failed', { userId: player.userId, payout, err });
    }
  }

  winners.sort((a, b) => b.payout - a.payout);
  history.push({
    roundId: r.id,
    segment: r.resultSegment!,
    topSlot: r.topSlot!,
    multiplier: isBonus(r.resultSegment) ? bonusHeadline(r.bonus) : null,
    at: Date.now(),
  });
  if (history.length > 100) history.splice(0, history.length - 100);

  io?.to(CRAZY_ROOM).emit('crazy_result', {
    roundId: r.id,
    segment: r.resultSegment,
    topSlot: r.topSlot,
    bonus: r.bonus,
    seed: r.seed,
    winners: winners.slice(0, 20),
  });
}

function bonusHeadline(bonus: BonusResult | null): number | null {
  if (!bonus) return null;
  if (bonus.kind === 'coinflip' || bonus.kind === 'pachinko') return bonus.multiplier;
  if (bonus.kind === 'crazytime') {
    return Math.max(bonus.multipliers.blue, bonus.multipliers.green, bonus.multipliers.yellow);
  }
  return Math.max(...bonus.grid);
}

// ── Round engine ────────────────────────────────────────────
function advance() {
  if (!round) return;
  const r = round;

  if (r.phase === 'betting') {
    // Nobody staked anything — roll straight into a fresh betting window so an
    // idle table isn't burning through spins.
    if (r.players.size === 0) {
      startRound();
      return;
    }
    r.resultIndex = randInt(WHEEL.length);
    r.resultSegment = WHEEL[r.resultIndex]!;
    r.topSlot = rollTopSlot();
    r.phase = 'spinning';
    r.endsAt = Date.now() + SPINNING_MS;
    broadcast();
    timer = setTimeout(advance, SPINNING_MS);
    return;
  }

  if (r.phase === 'spinning') {
    if (isBonus(r.resultSegment)) {
      r.bonus =
        r.resultSegment === 'coinflip' ? rollCoinFlip()
        : r.resultSegment === 'cashhunt' ? rollCashHunt()
        : r.resultSegment === 'pachinko' ? rollPachinko()
        : rollCrazyTime();

      // Only Cash Hunt and Crazy Time ask the player for anything; the other
      // two go straight to the reveal.
      const needsPick = r.resultSegment === 'cashhunt' || r.resultSegment === 'crazytime';
      r.phase = needsPick ? 'bonus_pick' : 'bonus_reveal';
      r.endsAt = Date.now() + (needsPick ? BONUS_PICK_MS : BONUS_REVEAL_MS);
      broadcast();
      timer = setTimeout(advance, needsPick ? BONUS_PICK_MS : BONUS_REVEAL_MS);
      return;
    }
    r.phase = 'result';
    r.endsAt = Date.now() + RESULT_MS;
    settle(r).catch((err) => console.error('[crazyWheel] settle error', err));
    broadcast();
    timer = setTimeout(advance, RESULT_MS);
    return;
  }

  if (r.phase === 'bonus_pick') {
    r.phase = 'bonus_reveal';
    r.endsAt = Date.now() + BONUS_REVEAL_MS;
    broadcast();
    timer = setTimeout(advance, BONUS_REVEAL_MS);
    return;
  }

  if (r.phase === 'bonus_reveal') {
    r.phase = 'result';
    r.endsAt = Date.now() + RESULT_MS;
    settle(r).catch((err) => console.error('[crazyWheel] settle error', err));
    broadcast();
    timer = setTimeout(advance, RESULT_MS);
    return;
  }

  startRound();
}

function startRound() {
  const seed = crypto.randomBytes(16).toString('hex');
  round = {
    id: nextRoundId++,
    phase: 'betting',
    endsAt: Date.now() + BETTING_MS,
    resultIndex: null,
    resultSegment: null,
    topSlot: null,
    bonus: null,
    players: new Map(),
    seed,
    seedHash: crypto.createHash('sha256').update(seed).digest('hex'),
  };
  broadcast();
  timer = setTimeout(advance, BETTING_MS);
}

export function startCrazyWheelEngine(server: Server) {
  if (io) return;
  io = server;
  startRound();
  console.log(`[crazyWheel] engine started — ${WHEEL.length} segments`);
}

export function stopCrazyWheelEngine() {
  if (timer) clearTimeout(timer);
  timer = null;
  round = null;
  io = null;
}

export function getWheelLayout() {
  return {
    wheel: WHEEL,
    colors: SEGMENT_COLORS,
    payouts: BASE_PAYOUT,
    betSpots: BET_SPOTS,
    chipTiers: CHIP_TIERS,
  };
}

export function getHistory() {
  return history.slice(-50);
}
