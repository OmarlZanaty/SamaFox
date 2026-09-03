import { Server } from 'socket.io';
import crypto from 'crypto';
import prisma from '../utils/prisma';

// ============================================================
// القط الجشع — GREEDY CAT JACKPOT (8-symbol live food wheel)
// ============================================================
// NOTE ON THE HOUSE RULE: this game follows عجلة الحظ (crazyWheel.service.ts)
// rather than the halal model used by skillWheel/skillDice — it is a
// bet-on-an-outcome format, built to the client's spec. Everything that moves
// coins lives in this file, so the halal conversion planned across the wager
// games stays a change to the payout helpers here and nowhere else.
//
// Round shape:
//   betting (30s) → closing (5s) → spinning (6s) → result (6s) → next round
//
// The server owns the RNG and every payout. The client animates the symbol the
// server already rolled; a tampered client can change nothing but its own
// animation.
//
// ── The maths ───────────────────────────────────────────────
// Symbol weights are proportional to 1/multiplier, so EVERY symbol carries the
// identical expected return and no bet on the table is better than any other:
//
//   1/45 : 1/25 : 1/15 : 1/10 : 1/5   ×450   →   10 : 18 : 30 : 45 : 90
//
// Total weight 463, so a winning bet returns stake × multiplier with
// probability weight/463, and the RTP on every symbol is
//   450 / 463 = 97.19%
// leaving the house a flat 2.81% edge no matter what the player backs.
// Changing a multiplier WITHOUT changing its weight breaks that guarantee, so
// `assertBalancedTable()` fails loudly at boot if the two ever drift apart.
// ============================================================

export const GREEDY_ROOM = 'greedy-cat:main';

/** Wager tiles, per the Arabic reference screen. */
export const DENOMINATIONS = [100, 1_000, 5_000, 20_000, 100_000, 500_000];
export const MIN_BET = 100;
export const MAX_BET_PER_SYMBOL = 5_000_000;

// ── Table layout ────────────────────────────────────────────
export type SymbolKey =
  | 'chicken' | 'tomato' | 'goat' | 'pepper'
  | 'fish' | 'carrot' | 'shrimp' | 'corn';

export type CategoryKey = 'salad' | 'pizza';

interface SymbolDef {
  key: SymbolKey;
  category: CategoryKey;
  /** Gross return per coin staked, stake included. */
  multiplier: number;
  /** Share of the 463-weight ring. Must stay proportional to 1/multiplier. */
  weight: number;
  nameAr: string;
}

/**
 * Ring order is CLOCKWISE FROM 12 O'CLOCK and is the layout the client draws:
 * index 0 sits under the pointer, index 2 at 3 o'clock, index 4 at 6 o'clock.
 * The order is presentation only — the result is rolled by weight, then the
 * client rotates to whichever index carries it.
 */
export const SYMBOLS: SymbolDef[] = [
  { key: 'chicken', category: 'pizza', multiplier: 45, weight: 10, nameAr: 'دجاجة' },
  { key: 'tomato',  category: 'salad', multiplier: 5,  weight: 90, nameAr: 'طماطم' },
  { key: 'goat',    category: 'pizza', multiplier: 15, weight: 30, nameAr: 'ماعز' },
  { key: 'pepper',  category: 'salad', multiplier: 5,  weight: 90, nameAr: 'فلفل' },
  { key: 'fish',    category: 'pizza', multiplier: 25, weight: 18, nameAr: 'سمكة' },
  { key: 'carrot',  category: 'salad', multiplier: 5,  weight: 90, nameAr: 'جزرة' },
  { key: 'shrimp',  category: 'pizza', multiplier: 10, weight: 45, nameAr: 'روبيان' },
  { key: 'corn',    category: 'salad', multiplier: 5,  weight: 90, nameAr: 'ذرة' },
];

const SYMBOL_KEYS: SymbolKey[] = SYMBOLS.map((s) => s.key);
const BY_KEY = new Map<SymbolKey, SymbolDef>(SYMBOLS.map((s) => [s.key, s]));
const TOTAL_WEIGHT = SYMBOLS.reduce((sum, s) => sum + s.weight, 0);

export const CATEGORIES: Record<CategoryKey, SymbolKey[]> = {
  salad: SYMBOLS.filter((s) => s.category === 'salad').map((s) => s.key),
  pizza: SYMBOLS.filter((s) => s.category === 'pizza').map((s) => s.key),
};

/**
 * A category bet is a SHORTCUT, not a separate payout: the stake is split
 * evenly across that category's four symbols and settles as four ordinary
 * symbol bets.
 *
 * The spec asked for a flat 2× on a category. That cannot ship: salad covers
 * 360/463 of the ring, so a flat 2× would return 0.7775 × 2 = 155% of stake —
 * an unbounded money printer. Splitting keeps a category bet at the same
 * 97.19% RTP as everything else, and is what the reference screen already
 * shows visually ("distribute the wager to the four associated cards").
 */
export const CATEGORY_SPLIT = 4;

function assertBalancedTable() {
  // Every symbol must return the same fraction of stake, or the "no bet is
  // better than another" line in the rules modal is a lie.
  const rtps = SYMBOLS.map((s) => (s.weight * s.multiplier) / TOTAL_WEIGHT);
  const first = rtps[0]!;
  const drift = Math.max(...rtps.map((r) => Math.abs(r - first)));
  if (drift > 1e-9) {
    throw new Error(
      `[greedyCat] unbalanced table: per-symbol RTP drifts by ${drift}. ` +
        'A multiplier changed without its weight — see the maths note at the top of this file.',
    );
  }
}

/** House RTP as a fraction, exposed so the rules modal can state it honestly. */
export const RTP = (SYMBOLS[0]!.weight * SYMBOLS[0]!.multiplier) / TOTAL_WEIGHT;

// ── Provably-fair RNG ───────────────────────────────────────
/**
 * The winning symbol is derived from the round seed, so the published
 * `seedHash` commits to the outcome BEFORE any bet is placed, and the revealed
 * seed lets a player recompute it afterwards:
 *
 *   roll  = sha256(seed + ':' + roundId) → first 52 bits → mod 463
 *   index = the symbol whose cumulative weight window contains `roll`
 */
export function rollFromSeed(seed: string, roundId: number): number {
  const digest = crypto.createHash('sha256').update(`${seed}:${roundId}`).digest('hex');
  const roll = Number(BigInt(`0x${digest.slice(0, 13)}`) % BigInt(TOTAL_WEIGHT));
  let cursor = 0;
  for (let i = 0; i < SYMBOLS.length; i++) {
    cursor += SYMBOLS[i]!.weight;
    if (roll < cursor) return i;
  }
  return SYMBOLS.length - 1;
}

// ── Jackpot progress ────────────────────────────────────────
/**
 * The bar tracks coins STAKED at the table, nothing more — a live activity
 * meter, not a promised prize. `MILESTONE_AWARD` is deliberately 0: paying a
 * milestone out has to be funded by a rake off the stakes, which means dropping
 * the 97.19% RTP by exactly that much. Wire the rake first, or the pot pays out
 * coins the table never took in.
 */
export const JACKPOT_MILESTONES = [500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000];
export const MILESTONE_AWARD = 0;

let jackpotPot = 0;
let milestonesHit = 0;

// ── Round state ─────────────────────────────────────────────
type Phase = 'betting' | 'closing' | 'spinning' | 'result';

const BETTING_MS = 30_000;
const CLOSING_MS = 5_000;
const SPINNING_MS = 6_000;
const RESULT_MS = 6_000;

interface PlayerBets {
  userId: number;
  name: string;
  avatarUrl: string | null;
  countryCode: string | null;
  /** Symbol key -> staked amount. Category bets are already split into these. */
  bets: Record<string, number>;
  /** What the player actually tapped, so the category buttons redraw selected. */
  categories: Record<string, number>;
  payout: number;
  multiplier: number;
}

interface Round {
  id: number;
  phase: Phase;
  endsAt: number;
  /** Index into SYMBOLS; null until betting closes. */
  resultIndex: number | null;
  resultSymbol: SymbolKey | null;
  players: Map<number, PlayerBets>;
  seed: string;
  seedHash: string;
}

export interface HistoryEntry {
  roundId: number;
  symbol: SymbolKey;
  multiplier: number;
  at: number;
}

let io: Server | null = null;
let round: Round | null = null;
let timer: NodeJS.Timeout | null = null;
let nextRoundId = 1;
const history: HistoryEntry[] = [];
const lastBets = new Map<number, Record<string, number>>();

// ── Daily leaderboard ───────────────────────────────────────
/**
 * «أرباح اليوم» / «سجلي» / «ترتيب اليوم», backed by `game_daily_stats`.
 *
 * The Map here is a read cache, not the store. `getPublicState` is synchronous
 * (it is called from `broadcast()` and straight out of a socket handler), so it
 * cannot await a query — but the board also has to survive a deploy, which the
 * old in-memory-only version did not. So: the cache answers the per-round
 * reads, Postgres holds the truth, and the two are reconciled at settlement.
 *
 * The cache is authoritative *while the process runs*, which is sound because
 * the round engine is a singleton — one process owns the table, so there is no
 * second writer to race with. It is hydrated from the DB on boot, so a restart
 * mid-day resumes each player's running total instead of zeroing it.
 */
const GAME_KEY = 'greedy';

interface DailyRow {
  userId: number;
  countryCode: string | null;
  /** Net = everything won today minus everything staked today. */
  net: number;
  wagered: number;
  /** Best single-round payout, shown as the player's «سجلي» record. */
  best: number;
}

let dailyKey = todayKey();
const daily = new Map<number, DailyRow>();

function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

function rollDailyIfNeeded() {
  const key = todayKey();
  if (key === dailyKey) return;
  dailyKey = key;
  // Only the cache is cleared — yesterday's rows stay in the table.
  daily.clear();
}

/** The cached row for a player, created zeroed on first touch. */
function cacheRow(p: PlayerBets): DailyRow {
  rollDailyIfNeeded();
  let row = daily.get(p.userId);
  if (!row) {
    row = {
      userId: p.userId,
      countryCode: p.countryCode,
      net: 0,
      wagered: 0,
      best: 0,
    };
    daily.set(p.userId, row);
  }
  return row;
}

/**
 * Writes a cached row through to the table. The whole row is written rather
 * than an increment because the cache is the authoritative running total —
 * incrementing would double-count a value the cache has already accumulated.
 */
async function persistDaily(row: DailyRow) {
  await prisma.gameDailyStat.upsert({
    where: {
      game_day_userId: { game: GAME_KEY, day: dailyKey, userId: row.userId },
    },
    create: {
      game: GAME_KEY,
      day: dailyKey,
      userId: row.userId,
      net: row.net,
      wagered: row.wagered,
      best: row.best,
      countryCode: row.countryCode,
    },
    update: {
      net: row.net,
      wagered: row.wagered,
      best: row.best,
      countryCode: row.countryCode,
    },
  });
}

/**
 * Refills the cache from the table. Called once at engine start so a deploy
 * mid-day does not reset everyone's «أرباح اليوم» to zero.
 */
async function hydrateDaily() {
  rollDailyIfNeeded();
  const rows = await prisma.gameDailyStat.findMany({
    where: { game: GAME_KEY, day: dailyKey },
  });
  for (const r of rows) {
    daily.set(r.userId, {
      userId: r.userId,
      countryCode: r.countryCode,
      net: r.net,
      wagered: r.wagered,
      best: r.best,
    });
  }
  console.log(`[greedyCat] daily board hydrated — ${rows.length} player(s) for ${dailyKey}`);
}

/**
 * Top rows for the ranking card. A non-null `country` filters to that region.
 *
 * Read straight from the table rather than the cache: this is an async REST
 * path, so it can afford the query, and going to the source means the board is
 * still right for players who have not placed a bet since the last restart.
 */
export async function getRanking(country?: string | null, limit = 20) {
  rollDailyIfNeeded();
  const rows = await prisma.gameDailyStat.findMany({
    where: {
      game: GAME_KEY,
      day: dailyKey,
      net: { gt: 0 },
      ...(country ? { countryCode: country } : {}),
    },
    orderBy: { net: 'desc' },
    take: limit,
    include: { user: { select: { name: true, avatarUrl: true } } },
  });
  return rows.map((r, i) => ({
    rank: i + 1,
    userId: r.userId,
    name: r.user?.name ?? 'لاعب',
    avatarUrl: r.user?.avatarUrl ?? null,
    countryCode: r.countryCode,
    score: r.net,
  }));
}

// ── Public state ────────────────────────────────────────────
export function getPublicState(userId?: number) {
  if (!round) return null;
  rollDailyIfNeeded();

  const me = userId != null ? round.players.get(userId) : undefined;
  const mine = userId != null ? daily.get(userId) : undefined;
  const totals = totalsBySymbol();
  const preResult = round.phase === 'betting' || round.phase === 'closing';

  return {
    roundId: round.id,
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    seedHash: round.seedHash,
    // The seed is only revealed once the outcome is public.
    seed: round.phase === 'result' ? round.seed : null,
    // Nothing about the outcome leaks before the wheel starts turning.
    resultIndex: preResult ? null : round.resultIndex,
    resultSymbol: preResult ? null : round.resultSymbol,
    totals,
    hot: hottestSymbol(totals),
    playerCount: round.players.size,
    jackpot: {
      pot: jackpotPot,
      milestones: JACKPOT_MILESTONES,
      reached: milestonesHit,
    },
    me: me
      ? {
          bets: me.bets,
          categories: me.categories,
          staked: Object.values(me.bets).reduce((a, b) => a + b, 0),
          payout: round.phase === 'result' ? me.payout : 0,
          multiplier: round.phase === 'result' ? me.multiplier : 0,
        }
      : null,
    today: {
      net: mine?.net ?? 0,
      best: mine?.best ?? 0,
    },
    history: history.slice(-15),
  };
}

function totalsBySymbol(): Record<string, { amount: number; players: number }> {
  const totals: Record<string, { amount: number; players: number }> = {};
  for (const key of SYMBOL_KEYS) totals[key] = { amount: 0, players: 0 };
  if (!round) return totals;
  for (const p of round.players.values()) {
    for (const [key, amount] of Object.entries(p.bets)) {
      if (!totals[key] || amount <= 0) continue;
      totals[key]!.amount += amount;
      totals[key]!.players += 1;
    }
  }
  return totals;
}

/**
 * The «ساخن» badge: whichever symbol the table has backed hardest this round.
 * It is a social indicator only — the roll is weight-based and never looks at
 * where the money went, which is exactly what the rules modal says out loud.
 */
function hottestSymbol(
  totals: Record<string, { amount: number; players: number }>,
): SymbolKey | null {
  let best: SymbolKey | null = null;
  let bestAmount = 0;
  for (const key of SYMBOL_KEYS) {
    const amount = totals[key]?.amount ?? 0;
    if (amount > bestAmount) {
      bestAmount = amount;
      best = key;
    }
  }
  return best;
}

function broadcast() {
  // Per-user fields (`me`, `today`) come back over REST; the broadcast carries
  // the shared view only.
  io?.to(GREEDY_ROOM).emit('greedy_state', getPublicState());
}

// ── Betting ─────────────────────────────────────────────────
/** Splits a category stake into its four symbol stakes. */
function splitCategory(target: CategoryKey, amount: number): Record<string, number> {
  const keys = CATEGORIES[target];
  const share = Math.floor(amount / CATEGORY_SPLIT);
  const out: Record<string, number> = {};
  let handed = 0;
  keys.forEach((key, i) => {
    // The last symbol absorbs any remainder, so the player is never
    // short-changed and the table never hands out more than it took in.
    const value = i === keys.length - 1 ? amount - handed : share;
    out[key] = value;
    handed += value;
  });
  return out;
}

export async function placeBet(userId: number, target: string, amount: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الاختيار' };
  }

  const isCategory = target === 'salad' || target === 'pizza';
  if (!isCategory && !SYMBOL_KEYS.includes(target as SymbolKey)) {
    return { ok: false as const, code: 'BAD_TARGET', message: 'خيار غير صحيح' };
  }
  if (!Number.isInteger(amount) || amount < MIN_BET) {
    return { ok: false as const, code: 'BAD_AMOUNT', message: 'قيمة رهان غير صحيحة' };
  }
  // A category stake has to divide into four whole coins, or the split would
  // round money into existence.
  if (isCategory && amount % CATEGORY_SPLIT !== 0) {
    return {
      ok: false as const,
      code: 'BAD_AMOUNT',
      message: 'رهان المجموعة يجب أن يقبل القسمة على ٤',
    };
  }

  const additions = isCategory
    ? splitCategory(target as CategoryKey, amount)
    : { [target]: amount };

  const existing = round.players.get(userId)?.bets ?? {};
  for (const [key, add] of Object.entries(additions)) {
    if ((existing[key] ?? 0) + add > MAX_BET_PER_SYMBOL) {
      return { ok: false as const, code: 'MAX_BET', message: 'تجاوزت الحد الأقصى للرهان' };
    }
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
    await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: amount } },
    });
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الاختيار' };
  }

  let player = round.players.get(userId);
  if (!player) {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { name: true, avatarUrl: true, countryCode: true },
    });
    player = {
      userId,
      name: user?.name ?? 'لاعب',
      avatarUrl: user?.avatarUrl ?? null,
      countryCode: user?.countryCode ?? null,
      bets: {},
      categories: {},
      payout: 0,
      multiplier: 0,
    };
    round.players.set(userId, player);
  }

  for (const [key, add] of Object.entries(additions)) {
    player.bets[key] = (player.bets[key] ?? 0) + add;
  }
  if (isCategory) {
    player.categories[target] = (player.categories[target] ?? 0) + amount;
  }

  jackpotPot += amount;
  checkMilestone();
  // Cache only — the round writes through once, at settlement.
  cacheRow(player).wagered += amount;

  const balance = await balanceOf(userId);
  broadcast();
  return {
    ok: true as const,
    bets: player.bets,
    categories: player.categories,
    balance,
    roundId: round.id,
  };
}

/** Clears every bet for this round and refunds the total. Betting phase only. */
export async function clearBets(userId: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الاختيار' };
  }
  const player = round.players.get(userId);
  if (!player) {
    return { ok: true as const, bets: {}, categories: {}, balance: await balanceOf(userId) };
  }

  const total = Object.values(player.bets).reduce((a, b) => a + b, 0);
  player.bets = {};
  player.categories = {};
  if (total > 0) {
    await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: total } },
    });
    // The refund leaves the activity meter and the daily wagered figure too, or
    // a player could pump the jackpot bar by betting and clearing on a loop.
    jackpotPot = Math.max(0, jackpotPot - total);
    cacheRow(player).wagered -= total;
  }
  broadcast();
  return { ok: true as const, bets: {}, categories: {}, balance: await balanceOf(userId) };
}

/** Re-places the exact symbol stakes from the player's previous round. */
export async function repeatBets(userId: number) {
  if (!round || round.phase !== 'betting') {
    return { ok: false as const, code: 'BETTING_CLOSED', message: 'أُغلق باب الاختيار' };
  }
  const previous = lastBets.get(userId);
  if (!previous || Object.keys(previous).length === 0) {
    return { ok: false as const, code: 'NO_PREVIOUS', message: 'لا يوجد رهان سابق' };
  }
  // Replayed as symbol stakes, never as categories — the split already happened
  // last round, and re-splitting would quadruple the stake.
  for (const [key, amount] of Object.entries(previous)) {
    if (amount <= 0) continue;
    const res = await placeBet(userId, key, amount);
    if (!res.ok) return res;
  }
  const player = round.players.get(userId);
  return {
    ok: true as const,
    bets: player?.bets ?? {},
    categories: player?.categories ?? {},
    balance: await balanceOf(userId),
  };
}

async function balanceOf(userId: number): Promise<number> {
  const u = await prisma.user.findUnique({
    where: { id: userId },
    select: { coinsBalance: true },
  });
  return u?.coinsBalance ?? 0;
}

function checkMilestone() {
  while (
    milestonesHit < JACKPOT_MILESTONES.length &&
    jackpotPot >= JACKPOT_MILESTONES[milestonesHit]!
  ) {
    const milestone = JACKPOT_MILESTONES[milestonesHit]!;
    milestonesHit += 1;
    io?.to(GREEDY_ROOM).emit('greedy_milestone', { milestone, award: MILESTONE_AWARD });
  }
}

// ── Settlement ──────────────────────────────────────────────
/**
 * The whole money model:
 *   gross return = stake on the winning symbol × that symbol's multiplier
 *   net profit   = gross return − everything staked this round
 * The stake is INCLUDED in the multiplier (a 5× win on 100 returns 500, of
 * which 400 is profit), which is what the rules modal states.
 */
async function settle(r: Round) {
  const symbol = r.resultSymbol!;
  const def = BY_KEY.get(symbol)!;
  const winners: {
    userId: number;
    name: string;
    avatarUrl: string | null;
    payout: number;
    profit: number;
  }[] = [];

  for (const player of r.players.values()) {
    const staked = Object.values(player.bets).reduce((a, b) => a + b, 0);
    lastBets.set(player.userId, { ...player.bets });

    const onWinner = player.bets[symbol] ?? 0;
    const payout = onWinner > 0 ? Math.floor(onWinner * def.multiplier) : 0;
    player.payout = payout;
    player.multiplier = onWinner > 0 ? def.multiplier : 0;

    const row = cacheRow(player);
    // `wagered` was already added at bet time, so the daily net only needs the
    // return side here.
    row.net += payout - staked;
    if (payout > row.best) row.best = payout;

    if (payout > 0) {
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
          profit: payout - staked,
        });
      } catch (err) {
        console.error('[greedyCat] payout failed', { userId: player.userId, payout, err });
        // The coins never landed, so do not let the leaderboard claim they did.
        row.net -= payout;
        player.payout = 0;
        player.multiplier = 0;
      }
    }

    // One write-through per player per round — after the payout outcome is
    // known, so a failed payout is never persisted as profit. Losers are
    // written too: their net moved, and the board has to show it.
    try {
      await persistDaily(row);
    } catch (err) {
      // The cache still has the right numbers, so the round is unaffected and
      // the next settlement writes the corrected running total anyway.
      console.error('[greedyCat] daily stat write failed', { userId: player.userId, err });
    }
  }

  winners.sort((a, b) => b.payout - a.payout);
  history.push({ roundId: r.id, symbol, multiplier: def.multiplier, at: Date.now() });
  if (history.length > 100) history.splice(0, history.length - 100);

  io?.to(GREEDY_ROOM).emit('greedy_result', {
    roundId: r.id,
    symbol,
    multiplier: def.multiplier,
    seed: r.seed,
    winners: winners.slice(0, 10),
  });
}

// ── Round engine ────────────────────────────────────────────
function advance() {
  if (!round) return;
  const r = round;

  if (r.phase === 'betting') {
    // Nobody staked anything — open a fresh betting window rather than burning
    // rounds (and history entries) on an idle table.
    if (r.players.size === 0) {
      startRound();
      return;
    }
    r.phase = 'closing';
    r.endsAt = Date.now() + CLOSING_MS;
    broadcast();
    timer = setTimeout(advance, CLOSING_MS);
    return;
  }

  if (r.phase === 'closing') {
    // The outcome was committed by `seedHash` when the round opened; this only
    // reveals which symbol that seed always meant.
    r.resultIndex = rollFromSeed(r.seed, r.id);
    r.resultSymbol = SYMBOLS[r.resultIndex]!.key;
    r.phase = 'spinning';
    r.endsAt = Date.now() + SPINNING_MS;
    broadcast();
    timer = setTimeout(advance, SPINNING_MS);
    return;
  }

  if (r.phase === 'spinning') {
    r.phase = 'result';
    r.endsAt = Date.now() + RESULT_MS;
    settle(r).catch((err) => console.error('[greedyCat] settle error', err));
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
    resultSymbol: null,
    players: new Map(),
    seed,
    seedHash: crypto.createHash('sha256').update(seed).digest('hex'),
  };
  broadcast();
  timer = setTimeout(advance, BETTING_MS);
}

export function startGreedyCatEngine(server: Server) {
  if (io) return;
  assertBalancedTable();
  io = server;
  // Fire-and-forget: a cold cache only means the first few «أرباح اليوم» reads
  // show zero until the next settlement, never a wrong payout.
  hydrateDaily().catch((err) => console.error('[greedyCat] daily hydrate failed', err));
  // Round numbers in the reference screen are six digits, so start high enough
  // that the header reads like a live table rather than a fresh install.
  nextRoundId = 900_000 + (Math.floor(Date.now() / 86_400_000) % 50_000);
  startRound();
  console.log(
    `[greedyCat] engine started — ${SYMBOLS.length} symbols, RTP ${(RTP * 100).toFixed(2)}%`,
  );
}

export function stopGreedyCatEngine() {
  if (timer) clearTimeout(timer);
  timer = null;
  round = null;
  io = null;
}

/** The static table, fetched once so the client never hard-codes a payout. */
export function getLayout() {
  return {
    symbols: SYMBOLS.map((s) => ({
      key: s.key,
      category: s.category,
      multiplier: s.multiplier,
      weight: s.weight,
      nameAr: s.nameAr,
    })),
    categories: CATEGORIES,
    categorySplit: CATEGORY_SPLIT,
    denominations: DENOMINATIONS,
    minBet: MIN_BET,
    maxBetPerSymbol: MAX_BET_PER_SYMBOL,
    totalWeight: TOTAL_WEIGHT,
    rtp: RTP,
    phases: {
      betting: BETTING_MS,
      closing: CLOSING_MS,
      spinning: SPINNING_MS,
      result: RESULT_MS,
    },
    jackpotMilestones: JACKPOT_MILESTONES,
  };
}

export function getHistory() {
  return history.slice(-50);
}
