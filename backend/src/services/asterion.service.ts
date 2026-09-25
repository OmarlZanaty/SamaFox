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

const GAME = 'asterion' as const;

// ─────────────────────────────────────────────────────────────────────────────
// أستيريون — CITADEL OF ASTERION
//
// Original fictional pay-anywhere / tumbling game set in a sky temple ruled by
// Asterion, an invented storm guardian (not a copy of any published title — see
// ASTERION_ARTWORK_BRIEF.md at the repo root for the creative-distinction notes
// and every art prompt).
//
// It shares the 6×5 pay-anywhere shape with أثيرفول and nothing else:
//
//   أثيرفول     wins from 9 symbols, wilds, Ember Charge as a % boost,
//               Constellation Locks, one long bonus of tumbles.
//   أستيريون    wins from 8 symbols, no wild, Storm Orbs that pin themselves to
//               the board and *multiply* the whole sequence, and a free-spin
//               trial whose multiplier meter never resets while it runs.
//
// Like بلينكو, one tap is one request: the server deals, resolves every tumble
// and the whole trial, and hands back the finished sequence. The client only
// replays frames it has already been given — it never decides a symbol, a
// tumble, an orb or a payout.
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
 * The trial multiplier meter is additive and never resets inside the feature,
 * so the top of the distribution is a very long tail. A cap keeps the
 * platform's exposure on any single spin bounded and knowable; the simulator
 * reports both how often it bites and how much RTP it removes.
 */
export const MAX_WIN_MULTIPLE = 5_000;

const HISTORY_LIMIT = 30;

export type StandardSymbol = 'L1' | 'L2' | 'L3' | 'L4' | 'H1' | 'H2' | 'H3' | 'H4';
export type SpecialSymbol = 'CREST' | 'ORB';
export type Cell = StandardSymbol | SpecialSymbol;

export const STANDARD_SYMBOLS: StandardSymbol[] = ['L1', 'L2', 'L3', 'L4', 'H1', 'H2', 'H3', 'H4'];

// ── Symbol weights ───────────────────────────────────────────────────────────
// Uniform across all 6 columns: this is a pay-anywhere board, not payline reels,
// so a column has no identity of its own. The trial table carries more orbs and
// slightly more high symbols, which is where the feature's extra value lives.

const WEIGHTS_BASE: Record<Cell, number> = {
  L1: 17, L2: 16, L3: 15, L4: 13.5,
  H1: 10.5, H2: 8.5, H3: 6.5, H4: 4.5,
  CREST: 2.05, ORB: 1.7,
};

const WEIGHTS_BONUS: Record<Cell, number> = {
  L1: 15.5, L2: 14.5, L3: 13.5, L4: 12.5,
  H1: 11, H2: 9, H3: 7, H4: 5,
  CREST: 1.05, ORB: 2.7,
};

// ── Paytable ─────────────────────────────────────────────────────────────────
// Payout as a multiple of the total bet, in three count bands: 8-9, 10-11 and
// 12+ of the 30 visible cells.
//
// Tuned to ~97% RTP — a 3% house edge, matching طيّار and أثيرفول — and
// *measured*, not guessed: `npm run sim:asterion` replays this exact math over
// hundreds of thousands of spins and fails loudly if the return creeps over
// 100%. Re-run it after touching anything in this block, the weights above or
// the orb table below.
//
// Measured: 96.54% over 2M spins at the 20-coin minimum (seed spread
// 94.96-97.70%), 96.93% at 5,000 coins — RTP drifts up slightly with stake
// because a sequence payout is floored to whole coins and that rounding bites
// proportionally harder on small wins, so the edge is widest exactly where it
// matters least. Hit rate 41.4%; the trial fires 1 in 199 spins and pays ~44x
// bet, which is ~22 of the 96.5 points. The 5,000x cap did not bite once in
// 2.75M spins, so it costs no measurable RTP and exists purely as a ceiling.
//
// The per-seed spread is wide because the trial's multiplier meter is additive
// and uncapped inside the feature: a fifth of the return arrives through a thin
// tail. Read the mean across seeds, never one run.
//
// Every payout is linear in this table, so scaling the whole table scales total
// RTP by the same factor while leaving hit rate, trial frequency and the shape
// of the game exactly where they were. That makes it the safest lever.
const BASE_PAYTABLE: Record<StandardSymbol, [number, number, number]> = {
  L1: [0.12, 0.31, 0.85],
  L2: [0.14, 0.37, 1.00],
  L3: [0.18, 0.45, 1.25],
  L4: [0.25, 0.62, 1.70],
  H1: [0.40, 1.00, 2.85],
  H2: [0.57, 1.55, 4.35],
  H3: [1.00, 2.60, 7.45],
  H4: [1.90, 4.85, 13.5],
};

/**
 * الصعوبة (2026-09-24): every entry above scaled by PRIZE_SCALE and rounded
 * down to what the paytable screen prints. Every payout is linear in this
 * table, so the return drops from ~96.7% to ~80% while hit rate, feature
 * frequency and the shape of the game stay where they were. This scaled table
 * is the one sent to the client, so the screen always shows what pays.
 */
export const PRIZE_SCALE = Number(process.env.ASTERION_PRIZE_SCALE ?? 0.825);
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

// ── Storm Orbs ───────────────────────────────────────────────────────────────
// An orb lands as an ordinary cell but behaves unlike any other: it never pays
// on its own, never counts toward a match, and gravity does not move it. It
// pins where it landed for the rest of the sequence, and every orb showing when
// the tumbles stop is *added* into one sequence multiplier (4x + 6x + 25x = 35x,
// never 600x — the help panel states the same rule in the same words).
export const ORB_VALUES = [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 50, 100, 250] as const;
const ORB_WEIGHTS = [200, 170, 140, 115, 92, 70, 52, 34, 22, 13, 7, 2.4, 0.75, 0.14];

// ── Skyfall Trials tunables ──────────────────────────────────────────────────
export const CREST_TRIGGER = 4;
export const TRIAL_SPINS = 15;
export const CREST_RETRIGGER = 3;
export const RETRIGGER_SPINS = 5;

/** Guard against a pathological retrigger chain running forever. */
const MAX_TRIAL_SPINS = 300;

// ── Celebration tiers ────────────────────────────────────────────────────────
export type CelebrationTier = 'NICE_WIN' | 'GREAT_SURGE' | 'EPIC_STORM' | 'DIVINE_SURGE';

const TIER_THRESHOLDS: [CelebrationTier, number][] = [
  ['DIVINE_SURGE', 100],
  ['EPIC_STORM', 40],
  ['GREAT_SURGE', 15],
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
// Same provably-fair contract as بلينكو, طيّار and أثيرفول:
// HMAC-SHA256(serverSeed, `${clientSeed}:${nonce}:${block}`) expanded block by
// block. A spin consumes a variable number of bytes — cascades and the trial
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

const orbTotalWeight = ORB_WEIGHTS.reduce((a, b) => a + b, 0);
const orbCum: number[] = [];
{
  let acc = 0;
  for (const w of ORB_WEIGHTS) {
    acc += w;
    orbCum.push(acc);
  }
}

function pickOrbValue(rng: RngStream): number {
  const r = rng.nextFloat() * orbTotalWeight;
  for (let i = 0; i < orbCum.length; i++) {
    if (r < orbCum[i]!) return ORB_VALUES[i]!;
  }
  return ORB_VALUES[0]!;
}

// ── Grid mechanics ───────────────────────────────────────────────────────────

/** One board position. `orb` carries the orb's face value when the cell is an ORB. */
interface Board {
  cells: (Cell | null)[];
  /** index → face value, for cells currently holding an orb. */
  orbs: Map<number, number>;
}

function newBoard(): Board {
  return { cells: Array<Cell | null>(CELLS).fill(null), orbs: new Map() };
}

/**
 * Gravity refill: surviving symbols in each column fall to the bottom and new
 * symbols enter from the top.
 *
 * Orbs are the exception — they are pinned, so their cell is skipped entirely
 * and everything else falls around them. That is the whole reason an orb stays
 * legible for the length of a sequence instead of sliding away between tumbles.
 */
function refill(board: Board, rng: RngStream, sampler: (rng: RngStream) => Cell) {
  for (let c = 0; c < COLS; c++) {
    const openRows: number[] = [];
    const survivors: Cell[] = [];
    for (let r = ROWS - 1; r >= 0; r--) {
      const idx = r * COLS + c;
      if (board.orbs.has(idx)) continue;
      openRows.push(r);
      const v = board.cells[idx];
      if (v) survivors.push(v);
    }
    for (let i = 0; i < openRows.length; i++) {
      const idx = openRows[i]! * COLS + c;
      if (i < survivors.length) {
        board.cells[idx] = survivors[i]!;
      } else {
        const fresh = sampler(rng);
        board.cells[idx] = fresh;
        // A fresh orb takes its value the moment it lands, so the client can
        // show the number from the frame it appears in.
        if (fresh === 'ORB') board.orbs.set(idx, pickOrbValue(rng));
      }
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

export interface OrbCell {
  index: number;
  value: number;
}

export interface TumbleFrame {
  phase: 'base' | 'trial';
  /** The board as it should be shown and evaluated for this frame, before removal. */
  grid: Cell[];
  /** Every orb on the board in this frame, with its face value. */
  orbCells: OrbCell[];
  wins: WinEntry[];
  winningCells: number[];

  /** Present on the last frame of a sequence — the frame where nothing more wins. */
  sequenceWin?: number;
  sequenceMultiplier?: number;
  sequenceTotal?: number;

  /** Trial-only, present on the first frame of each free spin. */
  spinNumber?: number;
  spinsLeftAfter?: number;
  crestCount?: number;
  retriggerAdded?: number;
  /** Trial-only, on the last frame of a free spin: the meter after this spin's orbs. */
  trialMultiplierAfter?: number;
}

interface SequenceResult {
  frames: TumbleFrame[];
  /** Raw symbol win for the whole sequence, before any multiplier. */
  win: number;
  /** Sum of the face values of every orb showing when the tumbles stopped. */
  multiplier: number;
}

/**
 * Deals nothing — evaluates whatever board it is handed, clears winners,
 * refills, and repeats until a board pays nothing. Returns every frame, so the
 * client can replay the cascade exactly as the server resolved it.
 *
 * Orbs are neither counted nor cleared here: they are inert scenery until the
 * sequence ends, at which point the caller reads `multiplier`.
 */
function runSequence(
  board: Board,
  bet: number,
  rng: RngStream,
  sampler: (rng: RngStream) => Cell,
  phase: 'base' | 'trial',
): SequenceResult {
  const frames: TumbleFrame[] = [];
  let win = 0;

  for (let guard = 0; guard < 60; guard++) {
    const counts: Partial<Record<Cell, number>> = {};
    for (const s of board.cells) {
      if (s) counts[s] = (counts[s] ?? 0) + 1;
    }

    const wins: WinEntry[] = [];
    const winningCells = new Set<number>();
    for (const sym of STANDARD_SYMBOLS) {
      const count = counts[sym] ?? 0;
      if (count >= MIN_MATCH) {
        wins.push({ symbol: sym, count, amount: bet * PAYTABLE[sym][bandOf(count)] });
        board.cells.forEach((v, i) => {
          if (v === sym) winningCells.add(i);
        });
      }
    }

    const frame: TumbleFrame = {
      phase,
      grid: board.cells.map((c) => c ?? 'L1'),
      orbCells: [...board.orbs].map(([index, value]) => ({ index, value })),
      wins,
      winningCells: [...winningCells],
    };
    frames.push(frame);

    if (wins.length === 0) break;

    win += wins.reduce((a, w) => a + w.amount, 0);
    for (const i of winningCells) board.cells[i] = null;
    refill(board, rng, sampler);
  }

  const multiplier = [...board.orbs.values()].reduce((a, v) => a + v, 0);
  const last = frames[frames.length - 1]!;
  last.sequenceWin = win;
  last.sequenceMultiplier = multiplier;

  return { frames, win, multiplier };
}

/** Orbs only pay when the sequence actually won something; a multiplier of 0 means "no orbs". */
function applyMultiplier(win: number, multiplier: number): number {
  if (win <= 0) return 0;
  return Math.floor(win * (multiplier > 0 ? multiplier : 1));
}

function countCrests(board: Board): number {
  return board.cells.reduce((a, c) => a + (c === 'CREST' ? 1 : 0), 0);
}

// ── Skyfall Trials ───────────────────────────────────────────────────────────
// 15 free spins. The multiplier meter is the whole feature: every orb collected
// on a *winning* trial spin is added to a running total that never resets while
// the trial lasts, and every later win is multiplied by the whole total. Three
// crests on a trial deal add five more spins.

interface TrialResult {
  frames: TumbleFrame[];
  win: number;
  spinsPlayed: number;
  finalMultiplier: number;
  retriggers: number;
}

function runTrial(bet: number, rng: RngStream): TrialResult {
  const frames: TumbleFrame[] = [];
  let spinsLeft = TRIAL_SPINS;
  let spinsPlayed = 0;
  let meter = 0;
  let win = 0;
  let retriggers = 0;

  while (spinsLeft > 0 && spinsPlayed < MAX_TRIAL_SPINS) {
    spinsLeft--;
    spinsPlayed++;

    const board = dealBoard(rng, sampleBonus);
    const crests = countCrests(board);
    let retriggerAdded = 0;
    if (crests >= CREST_RETRIGGER) {
      spinsLeft += RETRIGGER_SPINS;
      retriggerAdded = RETRIGGER_SPINS;
      retriggers++;
    }

    const seq = runSequence(board, bet, rng, sampleBonus, 'trial');

    const first = seq.frames[0]!;
    first.spinNumber = spinsPlayed;
    first.spinsLeftAfter = spinsLeft;
    first.crestCount = crests;
    first.retriggerAdded = retriggerAdded;

    // The meter only grows on a spin that won: an orb landing on a dead board
    // is scenery, exactly as in base play.
    if (seq.win > 0) {
      meter += seq.multiplier;
      win += applyMultiplier(seq.win, meter);
    }

    const last = seq.frames[seq.frames.length - 1]!;
    last.sequenceTotal = seq.win > 0 ? applyMultiplier(seq.win, meter) : 0;
    last.sequenceMultiplier = meter;
    last.trialMultiplierAfter = meter;

    frames.push(...seq.frames);
  }

  return { frames, win, spinsPlayed, finalMultiplier: meter, retriggers };
}

// ── One spin ─────────────────────────────────────────────────────────────────

export interface SpinResult {
  bet: number;
  initialGrid: Cell[];
  initialOrbs: OrbCell[];
  crestsInitial: number;
  trialTriggered: boolean;

  frames: TumbleFrame[];

  baseWin: number;
  baseMultiplier: number;
  baseTotal: number;

  trialWin: number;
  trialSpins: number;
  trialRetriggers: number;
  trialMultiplier: number;
  trialTotal: number;

  /** Before the cap — kept so the client can say honestly when the cap bit. */
  uncappedTotal: number;
  capped: boolean;
  grandTotal: number;
  tier: CelebrationTier | null;
}

/** Pure — no DB access — so a live spin and provably-fair verification run the same code. */
export function computeSpin(rng: RngStream, bet: number): SpinResult {
  const board = dealBoard(rng, sampleBase);
  const initialGrid = board.cells.map((c) => c ?? 'L1');
  const initialOrbs = [...board.orbs].map(([index, value]) => ({ index, value }));
  const crestsInitial = countCrests(board);
  const trialTriggered = crestsInitial >= CREST_TRIGGER;

  const base = runSequence(board, bet, rng, sampleBase, 'base');
  const baseTotal = applyMultiplier(base.win, base.multiplier);
  base.frames[base.frames.length - 1]!.sequenceTotal = baseTotal;

  let trialFrames: TumbleFrame[] = [];
  let trialWin = 0;
  let trialSpins = 0;
  let trialRetriggers = 0;
  let trialMultiplier = 0;

  if (trialTriggered) {
    const trial = runTrial(bet, rng);
    trialFrames = trial.frames;
    trialWin = trial.win;
    trialSpins = trial.spinsPlayed;
    trialRetriggers = trial.retriggers;
    trialMultiplier = trial.finalMultiplier;
  }

  const trialTotal = Math.floor(trialWin);
  const uncappedTotal = baseTotal + trialTotal;
  const ceiling = bet * MAX_WIN_MULTIPLE;
  const grandTotal = Math.min(uncappedTotal, ceiling);

  return {
    bet,
    initialGrid,
    initialOrbs,
    crestsInitial,
    trialTriggered,
    frames: [...base.frames, ...trialFrames],
    baseWin: base.win,
    baseMultiplier: base.multiplier,
    baseTotal,
    trialWin,
    trialSpins,
    trialRetriggers,
    trialMultiplier,
    trialTotal,
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
    orbValues: ORB_VALUES,
    crestTrigger: CREST_TRIGGER,
    trialSpins: TRIAL_SPINS,
    crestRetrigger: CREST_RETRIGGER,
    retriggerSpins: RETRIGGER_SPINS,
    tierThresholds: Object.fromEntries(TIER_THRESHOLDS),
    standardSymbols: STANDARD_SYMBOLS,
  };
}

// ── Provably fair seeds ──────────────────────────────────────────────────────
// The seed pair lives in the database, shared with بلينكو, نيون فورتشن and
// أثيرفول — see services/fairSeeds.ts for why it is not a Map any more.

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
  trialTriggered: boolean;
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
    console.error('[asterion] nonce reservation failed, bet refunded', { userId, bet, err });
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
    console.error('[asterion] spin failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'SPIN_FAILED', message: 'تعذر تنفيذ الجولة' };
  }

  // Whatever the spin paid is a prize from the fund.
  settlePrize(reserved.token, userId, GAME, spin.grandTotal, `${userId}:${nonce}`);

  remember(userId, {
    nonce,
    bet,
    grandTotal: spin.grandTotal,
    trialTriggered: spin.trialTriggered,
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
