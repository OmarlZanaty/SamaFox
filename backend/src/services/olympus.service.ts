import crypto from 'crypto';
import prisma from '../utils/prisma';
import {
  getFairness as fairGetFairness,
  reserveNonce,
  rotateServerSeed as fairRotateServerSeed,
  setClientSeed as fairSetClientSeed,
} from './fairSeeds';
import {
  grantStakeValue,
  releasePrize,
  reservePrize,
  scalePaytable,
  settlePrize,
} from './halalGames.service';

const GAME = 'olympus' as const;

// ─────────────────────────────────────────────────────────────────────────────
// بوابات أوليمبوس — GATES OF OLYMPUS
//
// A 6×5 pay-anywhere tumbling game set above the clouds of Mount Olympus, with
// Zeus at the right of the board. Same house contract as بلينكو and أستيريون:
// one tap is one request, the server deals the board, resolves every tumble and
// the whole free-spins feature, and hands back the finished sequence. The client
// replays frames it has already been given — it never decides a symbol, a
// tumble, a multiplier or a payout.
//
// How it differs from the other two pay-anywhere games in this app:
//
//   أثيرفول     wins from 9 symbols, wilds, Ember Charge as a % boost.
//   أستيريون    wins from 8, Storm Orbs *pinned* to the board for the sequence.
//   أوليمبوس    wins from 8, nine paying symbols (five gems, four artefacts),
//               lightning multipliers that fall with gravity like any other
//               symbol and are collected only when the tumbles stop, and a
//               15-spin bonus whose multiplier meter never resets while it runs.
//
// The multipliers are the reason this game feels different from أستيريون even
// though the grid is the same size: they are *not* pinned. A multiplier can be
// pushed down its column by the tumble above it, so a long cascade gathers
// several of them before anything is paid.
// ─────────────────────────────────────────────────────────────────────────────

export const COLS = 6;
export const ROWS = 5;
export const CELLS = COLS * ROWS;
export const MIN_MATCH = 8;

export const MIN_BET = 20;
export const MAX_BET = 20_000;

/**
 * Hard ceiling on one spin, as a multiple of the bet.
 *
 * The bonus meter is additive and never resets inside the feature, so the top
 * of the distribution is a very long tail. The cap keeps the platform's
 * exposure on a single spin bounded and knowable; `npm run sim:olympus` reports
 * both how often it bites and how much RTP it removes.
 */
export const MAX_WIN_MULTIPLE = 5_000;

const HISTORY_LIMIT = 30;

export type StandardSymbol =
  | 'GEM_BLUE'
  | 'GEM_GREEN'
  | 'GEM_YELLOW'
  | 'GEM_PURPLE'
  | 'GEM_RED'
  | 'RING'
  | 'CHALICE'
  | 'HOURGLASS'
  | 'CROWN';
export type SpecialSymbol = 'SCATTER' | 'MULT';
export type Cell = StandardSymbol | SpecialSymbol;

/** Cheapest first — the paytable, the help sheet and the client all read this order. */
export const STANDARD_SYMBOLS: StandardSymbol[] = [
  'GEM_BLUE',
  'GEM_GREEN',
  'GEM_YELLOW',
  'GEM_PURPLE',
  'GEM_RED',
  'RING',
  'CHALICE',
  'HOURGLASS',
  'CROWN',
];

// ── Symbol weights ───────────────────────────────────────────────────────────
// Uniform across all six columns: this is a pay-anywhere board, not payline
// reels, so a column has no identity of its own. The bonus table carries fewer
// scatters and noticeably more multipliers, which is where the feature's extra
// value lives — the meter, not the symbols, is what makes free spins worth
// having.

const WEIGHTS_BASE: Record<Cell, number> = {
  GEM_BLUE: 15,
  GEM_GREEN: 14,
  GEM_YELLOW: 13,
  GEM_PURPLE: 11.5,
  GEM_RED: 10,
  RING: 8.5,
  CHALICE: 7,
  HOURGLASS: 5.5,
  CROWN: 4,
  SCATTER: 2.0,
  MULT: 1.7,
};

const WEIGHTS_BONUS: Record<Cell, number> = {
  GEM_BLUE: 13.5,
  GEM_GREEN: 13,
  GEM_YELLOW: 12,
  GEM_PURPLE: 11,
  GEM_RED: 10,
  RING: 9,
  CHALICE: 7.5,
  HOURGLASS: 6,
  CROWN: 4.5,
  SCATTER: 1.0,
  MULT: 3.4,
};

// ── Paytable ─────────────────────────────────────────────────────────────────
// Payout as a multiple of the *total bet*, in three count bands: 8-9, 10-11 and
// 12 or more of the 30 visible cells. Pay-anywhere, so position never matters —
// only how many of a symbol are showing.
//
// Tuned to ~97% RTP — a 3% house edge, matching طيّار, أثيرفول and أستيريون —
// and *measured*, not guessed: `npm run sim:olympus` replays this exact math
// over hundreds of thousands of spins and fails loudly if the return creeps
// over 100%. Re-run it after touching anything in this block, the weights above
// or the multiplier table below.
//
// Measured: 96.88% over 1.6M spins at the 20-coin minimum (seed spread
// 95.55–98.40%). Hit rate 27.3% — deliberately lower than أستيريون's 41%,
// because nine paying symbols across thirty cells makes any single symbol
// reaching eight rarer, and that is what gives this game its volatility. Free
// spins fire 1 in ~197 spins and pay ~83x bet, which is ~42 of the 96.9 points;
// base play carries the other ~55. The 5,000x cap did not bite once in 1.6M
// spins, so it costs no measurable RTP and exists purely as a ceiling.
//
// The per-seed spread is wide because the bonus meter is additive and uncapped
// inside the feature: over 40% of the return arrives through a thin tail. Read
// the mean across seeds, never one run.
//
// Every payout is linear in this table, so scaling the whole table scales total
// RTP by the same factor while leaving hit rate, bonus frequency and the shape
// of the game exactly where they were. That makes it the safest lever, and it
// is the one the simulator's tuning note recommends.
const BASE_PAYTABLE: Record<StandardSymbol, [number, number, number]> = {
  GEM_BLUE: [0.22, 0.56, 1.55],
  GEM_GREEN: [0.27, 0.67, 1.85],
  GEM_YELLOW: [0.33, 0.82, 2.25],
  GEM_PURPLE: [0.41, 1.02, 2.85],
  GEM_RED: [0.53, 1.32, 3.65],
  RING: [0.76, 1.95, 5.5],
  CHALICE: [1.12, 2.95, 8.25],
  HOURGLASS: [1.95, 5.0, 14.5],
  CROWN: [3.7, 9.25, 25.5],
};

/**
 * الصعوبة (2026-09-24): every entry above scaled by PRIZE_SCALE and rounded
 * down to what the paytable screen prints. Every payout is linear in this
 * table, so the return drops from ~96.1% to ~80% while hit rate, feature
 * frequency and the shape of the game stay where they were. This scaled table
 * is the one sent to the client, so the screen always shows what pays.
 */
export const PRIZE_SCALE = Number(process.env.OLYMPUS_PRIZE_SCALE ?? 0.83);
export const PAYTABLE: Record<StandardSymbol, [number, number, number]> = scalePaytable(BASE_PAYTABLE, PRIZE_SCALE);

/**
 * What a spin reserves from the prize fund before the stake is taken: a
 * practical ceiling (1,000× bet). A rarer, bigger result is
 * still paid in full — the reservation guards the fund, it never shorts a win.
 */
const PRIZE_RESERVE_MULTIPLE = 1_000;

function bandOf(count: number): 0 | 1 | 2 {
  if (count >= 12) return 2;
  if (count >= 10) return 1;
  return 0;
}

// ── Lightning multipliers ────────────────────────────────────────────────────
// A multiplier lands as an ordinary cell but behaves unlike any other: it never
// pays on its own and never counts toward a match. It falls with gravity like
// any symbol, so a cascade can push it down the board, and every multiplier
// still showing when the tumbles stop is *added* into one sequence multiplier
// (3x + 5x + 25x = 33x, never 375x — the help panel states the same rule in the
// same words).
export const MULT_VALUES = [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 50, 100, 250, 500] as const;
const MULT_WEIGHTS = [210, 175, 140, 112, 88, 66, 48, 32, 20, 12, 6.5, 2.2, 0.7, 0.13, 0.03];

// ── Free spins tunables ──────────────────────────────────────────────────────
export const SCATTER_TRIGGER = 4;
export const FREE_SPINS = 15;
export const SCATTER_RETRIGGER = 3;
export const RETRIGGER_SPINS = 5;

/** Guard against a pathological retrigger chain running forever. */
const MAX_FREE_SPINS = 300;

// ── Celebration tiers ────────────────────────────────────────────────────────
export type CelebrationTier = 'NICE_WIN' | 'BIG_WIN' | 'MEGA_WIN' | 'EPIC_WIN';

const TIER_THRESHOLDS: [CelebrationTier, number][] = [
  ['EPIC_WIN', 100],
  ['MEGA_WIN', 40],
  ['BIG_WIN', 15],
  ['NICE_WIN', 5],
];

function tierFor(total: number, bet: number): CelebrationTier | null {
  if (bet <= 0) return null;
  const ratio = total / bet;
  for (const [tier, threshold] of TIER_THRESHOLDS) {
    if (ratio >= threshold) return tier;
  }
  return null;
}

// ── Deterministic RNG stream ─────────────────────────────────────────────────
// Same provably-fair contract as بلينكو, طيّار, أثيرفول and أستيريون:
// HMAC-SHA256(serverSeed, `${clientSeed}:${nonce}:${block}`) expanded block by
// block. A spin consumes a variable number of bytes — cascades and the bonus
// are open-ended — so the stream mints blocks on demand rather than pre-sizing
// the way a fixed-row Plinko path can.

class RngStream {
  private block: Buffer;
  private blockIndex = 0;
  private cursor = 0;

  constructor(
    private readonly serverSeed: string,
    private readonly clientSeed: string,
    private readonly nonce: number,
  ) {
    this.block = this.hmacBlock(0);
  }

  private hmacBlock(i: number): Buffer {
    return crypto
      .createHmac('sha256', this.serverSeed)
      .update(`${this.clientSeed}:${this.nonce}:${i}`)
      .digest();
  }

  private nextByte(): number {
    if (this.cursor >= this.block.length) {
      this.blockIndex++;
      this.block = this.hmacBlock(this.blockIndex);
      this.cursor = 0;
    }
    return this.block[this.cursor++]!;
  }

  /** Uniform float in [0, 1). */
  nextFloat(): number {
    return this.nextByte() / 256;
  }
}

function makeSampler(weights: Record<Cell, number>) {
  const keys = Object.keys(weights) as Cell[];
  const w = keys.map((k) => weights[k]);
  const total = w.reduce((a, b) => a + b, 0);
  const cum: number[] = [];
  let acc = 0;
  for (const x of w) {
    acc += x;
    cum.push(acc);
  }
  return (rng: RngStream): Cell => {
    const r = rng.nextFloat() * total;
    for (let i = 0; i < cum.length; i++) {
      if (r < cum[i]!) return keys[i]!;
    }
    return keys[keys.length - 1]!;
  };
}

const sampleBase = makeSampler(WEIGHTS_BASE);
const sampleBonus = makeSampler(WEIGHTS_BONUS);

const multTotalWeight = MULT_WEIGHTS.reduce((a, b) => a + b, 0);
const multCum: number[] = [];
{
  let acc = 0;
  for (const w of MULT_WEIGHTS) {
    acc += w;
    multCum.push(acc);
  }
}

function pickMultValue(rng: RngStream): number {
  const r = rng.nextFloat() * multTotalWeight;
  for (let i = 0; i < multCum.length; i++) {
    if (r < multCum[i]!) return MULT_VALUES[i]!;
  }
  return MULT_VALUES[0]!;
}

// ── Grid mechanics ───────────────────────────────────────────────────────────

/** One board position. `mult` carries the face value when the cell is a MULT. */
interface Slot {
  cell: Cell;
  mult?: number;
}

interface Board {
  slots: (Slot | null)[];
}

function newBoard(): Board {
  return { slots: Array<Slot | null>(CELLS).fill(null) };
}

/**
 * Gravity refill: surviving symbols in each column fall to the bottom and new
 * symbols enter from the top.
 *
 * Multipliers fall with everything else and carry their face value down the
 * column with them. That is deliberate, and it is the one place this game parts
 * company with أستيريون, whose orbs pin where they land.
 */
function refill(board: Board, rng: RngStream, sampler: (rng: RngStream) => Cell) {
  for (let c = 0; c < COLS; c++) {
    const survivors: Slot[] = [];
    for (let r = ROWS - 1; r >= 0; r--) {
      const slot = board.slots[r * COLS + c];
      if (slot) survivors.push(slot);
    }
    for (let r = ROWS - 1, i = 0; r >= 0; r--, i++) {
      const idx = r * COLS + c;
      if (i < survivors.length) {
        board.slots[idx] = survivors[i]!;
        continue;
      }
      // A fresh multiplier takes its value the moment it lands, so the client
      // can show the number from the frame it appears in.
      const fresh = sampler(rng);
      board.slots[idx] =
        fresh === 'MULT' ? { cell: fresh, mult: pickMultValue(rng) } : { cell: fresh };
    }
  }
}

function dealBoard(rng: RngStream, sampler: (rng: RngStream) => Cell): Board {
  const board = newBoard();
  refill(board, rng, sampler);
  return board;
}

export interface WinEntry {
  symbol: StandardSymbol;
  count: number;
  amount: number;
}

export interface MultCell {
  index: number;
  value: number;
}

export interface TumbleFrame {
  phase: 'base' | 'free';
  /** The board as it should be shown and evaluated for this frame, before removal. */
  grid: Cell[];
  /** Every multiplier on the board in this frame, with its face value. */
  multCells: MultCell[];
  wins: WinEntry[];
  winningCells: number[];

  /** Present on the last frame of a sequence — the frame where nothing more wins. */
  sequenceWin?: number;
  sequenceMultiplier?: number;
  sequenceTotal?: number;

  /** Free-spins only, present on the first frame of each spin. */
  spinNumber?: number;
  spinsLeftAfter?: number;
  scatterCount?: number;
  retriggerAdded?: number;
  /** Free-spins only, on the last frame of a spin: the meter after this spin's multipliers. */
  freeMultiplierAfter?: number;
}

interface SequenceResult {
  frames: TumbleFrame[];
  /** Raw symbol win for the whole sequence, before any multiplier. */
  win: number;
  /** Sum of the face values of every multiplier showing when the tumbles stopped. */
  multiplier: number;
}

function multCellsOf(board: Board): MultCell[] {
  const out: MultCell[] = [];
  board.slots.forEach((slot, index) => {
    if (slot?.cell === 'MULT') out.push({ index, value: slot.mult ?? 2 });
  });
  return out;
}

/**
 * Deals nothing — evaluates whatever board it is handed, clears winners,
 * refills, and repeats until a board pays nothing. Returns every frame, so the
 * client can replay the cascade exactly as the server resolved it.
 *
 * Multipliers are neither counted nor cleared here: they are inert scenery
 * until the sequence ends, at which point the caller reads `multiplier`.
 */
function runSequence(
  board: Board,
  bet: number,
  rng: RngStream,
  sampler: (rng: RngStream) => Cell,
  phase: 'base' | 'free',
): SequenceResult {
  const frames: TumbleFrame[] = [];
  let win = 0;

  for (let guard = 0; guard < 60; guard++) {
    const counts: Partial<Record<Cell, number>> = {};
    for (const slot of board.slots) {
      if (slot) counts[slot.cell] = (counts[slot.cell] ?? 0) + 1;
    }

    const wins: WinEntry[] = [];
    const winningCells = new Set<number>();
    for (const sym of STANDARD_SYMBOLS) {
      const count = counts[sym] ?? 0;
      if (count >= MIN_MATCH) {
        wins.push({ symbol: sym, count, amount: bet * PAYTABLE[sym][bandOf(count)] });
        board.slots.forEach((slot, i) => {
          if (slot?.cell === sym) winningCells.add(i);
        });
      }
    }

    const frame: TumbleFrame = {
      phase,
      grid: board.slots.map((s) => s?.cell ?? 'GEM_BLUE'),
      multCells: multCellsOf(board),
      wins,
      winningCells: [...winningCells],
    };
    frames.push(frame);

    if (wins.length === 0) break;

    win += wins.reduce((a, w) => a + w.amount, 0);
    for (const i of winningCells) board.slots[i] = null;
    refill(board, rng, sampler);
  }

  const multiplier = multCellsOf(board).reduce((a, m) => a + m.value, 0);
  const last = frames[frames.length - 1]!;
  last.sequenceWin = win;
  last.sequenceMultiplier = multiplier;

  return { frames, win, multiplier };
}

/** Multipliers only pay when the sequence won; a multiplier of 0 means "none showing". */
function applyMultiplier(win: number, multiplier: number): number {
  if (win <= 0) return 0;
  return Math.floor(win * (multiplier > 0 ? multiplier : 1));
}

function countScatters(board: Board): number {
  return board.slots.reduce((a, s) => a + (s?.cell === 'SCATTER' ? 1 : 0), 0);
}

// ── Free spins ───────────────────────────────────────────────────────────────
// Four scatters anywhere award 15 spins. The multiplier meter is the whole
// feature: every multiplier collected on a *winning* spin is added to a running
// total that never resets while the bonus lasts, and every later win is
// multiplied by the whole total. Three scatters on a bonus deal add five spins.

interface FreeResult {
  frames: TumbleFrame[];
  win: number;
  spinsPlayed: number;
  finalMultiplier: number;
  retriggers: number;
}

function runFreeSpins(bet: number, rng: RngStream): FreeResult {
  const frames: TumbleFrame[] = [];
  let spinsLeft = FREE_SPINS;
  let spinsPlayed = 0;
  let meter = 0;
  let win = 0;
  let retriggers = 0;

  while (spinsLeft > 0 && spinsPlayed < MAX_FREE_SPINS) {
    spinsLeft--;
    spinsPlayed++;

    const board = dealBoard(rng, sampleBonus);
    const scatters = countScatters(board);
    let retriggerAdded = 0;
    if (scatters >= SCATTER_RETRIGGER) {
      spinsLeft += RETRIGGER_SPINS;
      retriggerAdded = RETRIGGER_SPINS;
      retriggers++;
    }

    const seq = runSequence(board, bet, rng, sampleBonus, 'free');

    const first = seq.frames[0]!;
    first.spinNumber = spinsPlayed;
    first.spinsLeftAfter = spinsLeft;
    first.scatterCount = scatters;
    first.retriggerAdded = retriggerAdded;

    // Unlike base play, the meter grows whether or not the spin paid: a
    // multiplier landing on a dead board during free spins is still collected
    // and still counts for the rest of the bonus. That escalation is the whole
    // point of the feature, and it is why a late win in a long bonus can be
    // worth a hundred times an identical win in base play.
    meter += seq.multiplier;
    if (seq.win > 0) win += applyMultiplier(seq.win, meter);

    const last = seq.frames[seq.frames.length - 1]!;
    last.sequenceTotal = seq.win > 0 ? applyMultiplier(seq.win, meter) : 0;
    last.sequenceMultiplier = meter;
    last.freeMultiplierAfter = meter;

    frames.push(...seq.frames);
  }

  return { frames, win, spinsPlayed, finalMultiplier: meter, retriggers };
}

// ── One spin ─────────────────────────────────────────────────────────────────

export interface SpinResult {
  bet: number;
  initialGrid: Cell[];
  initialMults: MultCell[];
  scattersInitial: number;
  freeTriggered: boolean;

  frames: TumbleFrame[];

  baseWin: number;
  baseMultiplier: number;
  baseTotal: number;

  freeWin: number;
  freeSpins: number;
  freeRetriggers: number;
  freeMultiplier: number;
  freeTotal: number;

  /** Before the cap — kept so the client can say honestly when the cap bit. */
  uncappedTotal: number;
  capped: boolean;
  grandTotal: number;
  tier: CelebrationTier | null;
}

/** Pure — no DB access — so a live spin and provably-fair verification run the same code. */
export function computeSpin(rng: RngStream, bet: number): SpinResult {
  const board = dealBoard(rng, sampleBase);
  const initialGrid = board.slots.map((s) => s?.cell ?? 'GEM_BLUE');
  const initialMults = multCellsOf(board);
  const scattersInitial = countScatters(board);
  const freeTriggered = scattersInitial >= SCATTER_TRIGGER;

  const base = runSequence(board, bet, rng, sampleBase, 'base');
  const baseTotal = applyMultiplier(base.win, base.multiplier);
  base.frames[base.frames.length - 1]!.sequenceTotal = baseTotal;

  let freeFrames: TumbleFrame[] = [];
  let freeWin = 0;
  let freeSpinsPlayed = 0;
  let freeRetriggers = 0;
  let freeMultiplier = 0;

  if (freeTriggered) {
    const bonus = runFreeSpins(bet, rng);
    freeFrames = bonus.frames;
    freeWin = bonus.win;
    freeSpinsPlayed = bonus.spinsPlayed;
    freeRetriggers = bonus.retriggers;
    freeMultiplier = bonus.finalMultiplier;
  }

  const freeTotal = Math.floor(freeWin);
  const uncappedTotal = baseTotal + freeTotal;
  const ceiling = bet * MAX_WIN_MULTIPLE;
  const grandTotal = Math.min(uncappedTotal, ceiling);

  return {
    bet,
    initialGrid,
    initialMults,
    scattersInitial,
    freeTriggered,
    frames: [...base.frames, ...freeFrames],
    baseWin: base.win,
    baseMultiplier: base.multiplier,
    baseTotal,
    freeWin,
    freeSpins: freeSpinsPlayed,
    freeRetriggers,
    freeMultiplier,
    freeTotal,
    uncappedTotal,
    capped: uncappedTotal > ceiling,
    grandTotal,
    tier: tierFor(grandTotal, bet),
  };
}

/** Everything the client needs to draw the board and the paytable before the first spin. */
export function getLayout() {
  return {
    cols: COLS,
    rows: ROWS,
    minMatch: MIN_MATCH,
    minBet: MIN_BET,
    maxBet: MAX_BET,
    maxWinMultiple: MAX_WIN_MULTIPLE,
    paytable: PAYTABLE,
    multValues: MULT_VALUES,
    scatterTrigger: SCATTER_TRIGGER,
    freeSpins: FREE_SPINS,
    scatterRetrigger: SCATTER_RETRIGGER,
    retriggerSpins: RETRIGGER_SPINS,
    tierThresholds: Object.fromEntries(TIER_THRESHOLDS),
    standardSymbols: STANDARD_SYMBOLS,
  };
}

// ── Provably fair seeds ──────────────────────────────────────────────────────
// The seed pair lives in the database, shared with بلينكو, نيون فورتشن,
// أثيرفول and أستيريون — see services/fairSeeds.ts.

export const getFairness = (userId: number) => fairGetFairness(userId, GAME);
export const setClientSeed = (userId: number, seed: string) =>
  fairSetClientSeed(userId, GAME, seed);
export const rotateServerSeed = (userId: number) => fairRotateServerSeed(userId, GAME);

/** Recomputes a past spin from revealed seeds so the player can check it. */
export function verifySpin(
  serverSeed: string,
  clientSeed: string,
  nonce: number,
  bet: number,
): SpinResult {
  const rng = new RngStream(serverSeed, clientSeed, nonce);
  return computeSpin(rng, bet);
}

// ── History ──────────────────────────────────────────────────────────────────

export interface SpinRecord {
  nonce: number;
  bet: number;
  grandTotal: number;
  freeTriggered: boolean;
  tier: CelebrationTier | null;
  at: number;
}

const history = new Map<number, SpinRecord[]>();

export function getHistory(userId: number): SpinRecord[] {
  return history.get(userId) ?? [];
}

function remember(userId: number, record: SpinRecord) {
  const list = history.get(userId) ?? [];
  list.unshift(record);
  if (list.length > HISTORY_LIMIT) list.length = HISTORY_LIMIT;
  history.set(userId, list);
}

// ── Spinning ─────────────────────────────────────────────────────────────────

export async function resolveSpin(userId: number, rawBet: unknown) {
  const bet = Math.trunc(Number(rawBet));
  if (!Number.isFinite(bet) || bet < MIN_BET || bet > MAX_BET) {
    return {
      ok: false as const,
      code: 'BAD_BET',
      message: `الرهان بين ${MIN_BET} و ${MAX_BET} عملة`,
    };
  }

  // Charge first, atomically, same guard as بلينكو so parallel spins can never
  // overdraw a balance.
  // Promise the prize this spin could bring before the stake is taken.
  const reserved = await reservePrize(userId, GAME, bet * PRIZE_RESERVE_MULTIPLE);
  if (!reserved.ok) return { ok: false as const, code: reserved.code, message: reserved.message };

  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: bet } },
    data: { coinsBalance: { decrement: bet } },
  });
  if (charged.count === 0) {
    releasePrize(reserved.token);
    return { ok: false as const, code: 'INSUFFICIENT', message: 'رصيدك لا يكفي' };
  }

  // Reserved from the database, so two spins racing cannot draw the same nonce
  // and a restart cannot hand one out twice.
  let s: Awaited<ReturnType<typeof reserveNonce>>;
  try {
    s = await reserveNonce(userId, GAME);
  } catch (err) {
    releasePrize(reserved.token);
    await prisma.user.update({ where: { id: userId }, data: { coinsBalance: { increment: bet } } });
    console.error('[olympus] nonce reservation failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'SPIN_FAILED', message: 'تعذر تنفيذ الجولة' };
  }
  const nonce = s.nonce;

  // The stake is final: deliver the XP it bought before the reels are dealt.
  await grantStakeValue(userId, GAME, bet, `${userId}:${nonce}`);

  let spin: SpinResult;
  try {
    const rng = new RngStream(s.serverSeed, s.clientSeed, nonce);
    spin = computeSpin(rng, bet);
    if (spin.grandTotal > 0) {
      await prisma.user.update({
        where: { id: userId },
        data: { coinsBalance: { increment: spin.grandTotal } },
      });
    }
  } catch (err) {
    // Never keep the stake if the spin failed to resolve.
    await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: bet } },
    });
    releasePrize(reserved.token);
    console.error('[olympus] spin failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'SPIN_FAILED', message: 'تعذر تنفيذ الجولة' };
  }

  // Whatever the spin paid is a prize from the fund.
  settlePrize(reserved.token, userId, GAME, spin.grandTotal, `${userId}:${nonce}`);

  remember(userId, {
    nonce,
    bet,
    grandTotal: spin.grandTotal,
    freeTriggered: spin.freeTriggered,
    tier: spin.tier,
    at: Date.now(),
  });

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { coinsBalance: true },
  });

  return {
    ok: true as const,
    spin,
    balance: user?.coinsBalance ?? 0,
    serverSeedHash: s.serverSeedHash,
    clientSeed: s.clientSeed,
    nonce,
  };
}
