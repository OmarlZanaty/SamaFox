import crypto from 'crypto';
import prisma from '../utils/prisma';
import {
  getFairness as fairGetFairness,
  reserveNonce,
  rotateServerSeed as fairRotateServerSeed,
  setClientSeed as fairSetClientSeed,
} from './fairSeeds';

const GAME = 'neon_fortune' as const;


// ─────────────────────────────────────────────────────────────────────────────
// NEON FORTUNE: TIGER CITY  (نيون فورتشن — مدينة النمر)
//
// Original fictional 5×3 / 20-payline game with four progressive pools and two
// features (Skyline Rush free spins, Vault of Lights pick bonus). Design review:
// docs/neon-fortune-design-review.md.
//
// Same contract as أثيرفول and بلينكو: one request per spin, the server deals
// the grid, resolves the lines, runs the whole free-spin round and the whole
// vault, and hands the client a finished result to replay. The client never
// decides a symbol, a feature or a payout.
//
// Coins, not "virtual points": this game moves the same purchasable
// `coinsBalance` as every other game in the app, and the client copy says so.
// Decision D1(A) of the design review — no "no monetary value" disclaimer sits
// on top of a real balance here.
// ─────────────────────────────────────────────────────────────────────────────

export const REELS = 5;
export const ROWS = 3;
export const CELLS = REELS * ROWS;
export const LINES = 20;

export const MIN_BET = 50;
export const MAX_BET = 20_000;
export const BET_STEPS = [50, 100, 250, 500, 1000, 2500, 5000, 10_000, 20_000];

const HISTORY_LIMIT = 30;

// ── Symbols ──────────────────────────────────────────────────────────────────

export type PaySymbol =
  | 'TIGER' | 'PANTHER' | 'CRANE' | 'KOI' | 'LANTERN' | 'COIN'
  | 'A' | 'K' | 'Q' | 'J' | 'TEN';
export type SpecialSymbol = 'WILD' | 'SCATTER' | 'TOKEN';
export type Cell = PaySymbol | SpecialSymbol;

export const PAY_SYMBOLS: PaySymbol[] = [
  'TIGER', 'PANTHER', 'CRANE', 'KOI', 'LANTERN', 'COIN', 'A', 'K', 'Q', 'J', 'TEN',
];

// Payouts as a multiple of the TOTAL bet, for 3, 4 and 5 of a kind left-to-right
// from reel 1 — the same convention as أثيرفول's paytable, so the numbers on the
// paytable screen mean "this much of your stake" without a mental division by 20.
// Measured, not claimed: `npm run sim:neon-fortune` replays this exact math and
// fails the run if the return creeps toward 100%.
export const PAYTABLE: Record<PaySymbol, [number, number, number]> = {
  TIGER:   [6.5, 30, 140],
  PANTHER: [5, 18, 85],
  CRANE:   [3.75, 12, 57],
  KOI:     [2.5, 7.5, 34],
  LANTERN: [2, 6, 28],
  COIN:    [1.8, 4.9, 22],
  A:       [1.25, 3, 14],
  K:       [1.25, 3, 14],
  Q:       [0.9, 2.4, 11],
  J:       [0.9, 2.4, 11],
  TEN:     [0.65, 1.8, 8],
};

// ── Reel weights ─────────────────────────────────────────────────────────────
// Per reel, so the specials sit where the rules say they sit: WILD only on the
// three middle reels, TOKEN only on reels 1/3/5 (so three tokens is a genuinely
// rare shape rather than a common one), SCATTER anywhere.

type WeightTable = Partial<Record<Cell, number>>;

const BASE_COMMON: WeightTable = {
  TIGER: 1.2, PANTHER: 2, CRANE: 3, KOI: 5, LANTERN: 7, COIN: 10,
  A: 18, K: 22, Q: 26, J: 30, TEN: 34,
};

function reelWeights(reel: number, freeSpins: boolean): WeightTable {
  const w: WeightTable = { ...BASE_COMMON };
  const middle = reel >= 1 && reel <= 3;
  if (middle) w.WILD = freeSpins ? 7.5 : 4.5;
  // Scatters are rarer inside the round than outside it, so a retrigger stays a
  // moment rather than the norm.
  w.SCATTER = freeSpins ? 2.2 : 3.2;
  if (reel === 0 || reel === 2 || reel === 4) w.TOKEN = 3.5;
  return w;
}

// ── Paylines ─────────────────────────────────────────────────────────────────
// 20 fixed lines over 3 rows × 5 reels, given as the row index per reel. Rows
// are 0 (top), 1 (middle), 2 (bottom). Straight lines first, then V shapes, then
// zig-zags — the order the paytable screen draws them in.
export const PAYLINES: number[][] = [
  [1, 1, 1, 1, 1],
  [0, 0, 0, 0, 0],
  [2, 2, 2, 2, 2],
  [0, 1, 2, 1, 0],
  [2, 1, 0, 1, 2],
  [0, 0, 1, 2, 2],
  [2, 2, 1, 0, 0],
  [1, 0, 0, 0, 1],
  [1, 2, 2, 2, 1],
  [0, 1, 1, 1, 0],
  [2, 1, 1, 1, 2],
  [1, 0, 1, 2, 1],
  [1, 2, 1, 0, 1],
  [0, 0, 1, 0, 0],
  [2, 2, 1, 2, 2],
  [1, 1, 0, 1, 1],
  [1, 1, 2, 1, 1],
  [0, 1, 0, 1, 0],
  [2, 1, 2, 1, 2],
  [0, 2, 0, 2, 0],
];

// ── Features ─────────────────────────────────────────────────────────────────

export const SCATTER_TRIGGER = 3;
export const FREE_SPINS_AWARDED = 10;
export const FREE_SPINS_RETRIGGER = 2;
export const FREE_SPINS_CAP = 30;

/** Multiplier printed on a wild during Skyline Rush. */
const WILD_MULTIPLIERS = [2, 3] as const;
const WILD_MULTIPLIER_WEIGHTS = [72, 28];
/** A line can stack wild multipliers, but never past this. */
const WILD_MULTIPLIER_CAP = 27;

export const TOKEN_TRIGGER = 3;
export const VAULT_CAPSULES = 9;
export const VAULT_MATCH = 3;
/** Paid when nine picks reveal no matching trio — never a dead end. */
export const VAULT_CONSOLATION_MULT = 4;

export type JackpotTier = 'SPARK' | 'GLOW' | 'BEACON' | 'CITY';
export const JACKPOT_TIERS: JackpotTier[] = ['SPARK', 'GLOW', 'BEACON', 'CITY'];

/**
 * Pool funding. Each tier takes a slice of every bet — 3.5% of turnover in total;
 * 85% of that slice grows the live pool the player sees, 15% goes to a reserve
 * that re-seeds the pool after a win. The game therefore never pays out more than
 * it has collected — the only house money in the pools is the one-time launch
 * seed below.
 *
 * In the long run every contributed coin is paid back out, so this 3.5% *is* the
 * jackpot share of RTP; base play and Skyline Rush carry the other ~93.5%. Any
 * finite measurement will read higher than that until the launch seed has been
 * won, which is why the simulator reports a steady-state figure alongside the
 * measured one.
 */
const CONTRIBUTION_RATE: Record<JackpotTier, number> = {
  SPARK: 0.0045,
  GLOW: 0.0075,
  BEACON: 0.0100,
  CITY: 0.0130,
};
const RESERVE_SHARE = 0.15;

/** One-time operator seed so the meters are not empty on day one. */
const LAUNCH_SEED: Record<JackpotTier, number> = {
  SPARK: 4_000,
  GLOW: 20_000,
  BEACON: 90_000,
  CITY: 400_000,
};

/** What a pool resets to after it is won, funded from that tier's reserve. */
const RESET_TARGET: Record<JackpotTier, number> = {
  SPARK: 2_000,
  GLOW: 10_000,
  BEACON: 45_000,
  CITY: 200_000,
};

/**
 * Vault outcome weights. Deliberately inverse to pool size, so CITY is roughly a
 * 1-in-70 vault rather than a 1-in-4 — and the vault itself is ~1 in 1,300 spins.
 */
const VAULT_OUTCOME_WEIGHTS: [JackpotTier | 'NONE', number][] = [
  ['SPARK', 44],
  ['GLOW', 19],
  ['BEACON', 5.5],
  ['CITY', 1],
  ['NONE', 30.5],
];

// ── Celebration tiers ────────────────────────────────────────────────────────
export type CelebrationTier = 'WIN' | 'BIG_WIN' | 'MEGA_WIN' | 'CITY_LIGHTS';

const TIER_THRESHOLDS: [CelebrationTier, number][] = [
  ['CITY_LIGHTS', 100],
  ['MEGA_WIN', 20],
  ['BIG_WIN', 5],
  ['WIN', 0.0001],
];

function tierFor(total: number, bet: number): CelebrationTier | null {
  if (bet <= 0 || total <= 0) return null;
  const ratio = total / bet;
  for (const [tier, threshold] of TIER_THRESHOLDS) {
    if (ratio >= threshold) return tier;
  }
  return null;
}

// ── Deterministic RNG stream ─────────────────────────────────────────────────
// Same provably-fair contract as بلينكو، طيّار and أثيرفول:
// HMAC-SHA256(serverSeed, `${clientSeed}:${nonce}:${block}`), expanded block by
// block because a spin with a free-spin round consumes an open-ended number of
// bytes.

export class RngStream {
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

  /** Uniform float in [0, 1) with 16 bits of resolution. */
  nextFloat(): number {
    return (this.nextByte() * 256 + this.nextByte()) / 65_536;
  }
}

function makeSampler(weights: WeightTable) {
  const keys = Object.keys(weights) as Cell[];
  const cum: number[] = [];
  let acc = 0;
  for (const k of keys) {
    acc += weights[k]!;
    cum.push(acc);
  }
  const total = acc;
  return (rng: RngStream): Cell => {
    const r = rng.nextFloat() * total;
    for (let i = 0; i < cum.length; i++) {
      if (r < cum[i]!) return keys[i]!;
    }
    return keys[keys.length - 1]!;
  };
}

const BASE_SAMPLERS = Array.from({ length: REELS }, (_, reel) => makeSampler(reelWeights(reel, false)));
const FREE_SAMPLERS = Array.from({ length: REELS }, (_, reel) => makeSampler(reelWeights(reel, true)));

function pickWeighted<T>(rng: RngStream, entries: [T, number][]): T {
  const total = entries.reduce((a, e) => a + e[1], 0);
  const r = rng.nextFloat() * total;
  let acc = 0;
  for (const [value, weight] of entries) {
    acc += weight;
    if (r < acc) return value;
  }
  return entries[entries.length - 1]![0];
}

// ── Grid ─────────────────────────────────────────────────────────────────────
// Index layout is row-major: cell(row, reel) = row * REELS + reel.

export const cellIndex = (row: number, reel: number) => row * REELS + reel;

function dealGrid(rng: RngStream, freeSpins: boolean): Cell[] {
  const samplers = freeSpins ? FREE_SAMPLERS : BASE_SAMPLERS;
  const grid: Cell[] = new Array(CELLS);
  for (let reel = 0; reel < REELS; reel++) {
    for (let row = 0; row < ROWS; row++) {
      grid[cellIndex(row, reel)] = samplers[reel]!(rng);
    }
  }
  return grid;
}

function countSymbol(grid: Cell[], symbol: Cell): number {
  let n = 0;
  for (const c of grid) if (c === symbol) n++;
  return n;
}

function positionsOf(grid: Cell[], symbol: Cell): number[] {
  const out: number[] = [];
  for (let i = 0; i < grid.length; i++) if (grid[i] === symbol) out.push(i);
  return out;
}

// ── Line evaluation ──────────────────────────────────────────────────────────

export interface LineWin {
  line: number;
  symbol: PaySymbol;
  count: number;
  /** Board indices that make up the win, for the client to outline. */
  cells: number[];
  multiplier: number;
  amount: number;
}

/**
 * Scores one payline. A wild stands in for any paying symbol, so the line is
 * scored once per candidate symbol and the best result wins — which also handles
 * a line that opens with wilds (it simply pays as the best symbol it can extend).
 * Wilds never substitute for SCATTER or TOKEN.
 */
function scoreLine(
  grid: Cell[],
  lineIndex: number,
  bet: number,
  wildMultipliers: Map<number, number> | null,
): LineWin | null {
  const pattern = PAYLINES[lineIndex]!;
  const cells = pattern.map((row, reel) => cellIndex(row, reel));
  const symbols = cells.map((i) => grid[i]!);

  let best: LineWin | null = null;

  for (const candidate of PAY_SYMBOLS) {
    let count = 0;
    for (const s of symbols) {
      if (s === candidate || s === 'WILD') count++;
      else break;
    }
    if (count < 3) continue;

    const pay = PAYTABLE[candidate]![count - 3]!;
    if (pay <= 0) continue;

    let multiplier = 1;
    if (wildMultipliers) {
      for (let reel = 0; reel < count; reel++) {
        const m = wildMultipliers.get(cells[reel]!);
        if (m) multiplier *= m;
      }
      if (multiplier > WILD_MULTIPLIER_CAP) multiplier = WILD_MULTIPLIER_CAP;
    }

    const amount = Math.floor(pay * bet * multiplier);
    if (amount <= 0) continue;
    if (!best || amount > best.amount) {
      best = {
        line: lineIndex,
        symbol: candidate,
        count,
        cells: cells.slice(0, count),
        multiplier,
        amount,
      };
    }
  }

  return best;
}

function scoreGrid(grid: Cell[], bet: number, wildMultipliers: Map<number, number> | null) {
  const wins: LineWin[] = [];
  let total = 0;
  for (let i = 0; i < LINES; i++) {
    const win = scoreLine(grid, i, bet, wildMultipliers);
    if (win) {
      wins.push(win);
      total += win.amount;
    }
  }
  return { wins, total };
}

// ── Skyline Rush (free spins) ────────────────────────────────────────────────

export interface FreeSpinFrame {
  index: number;
  grid: Cell[];
  /** Board index → multiplier printed on that wild. */
  wildMultipliers: Record<number, number>;
  wins: LineWin[];
  win: number;
  scatters: number;
  retriggered: number;
  spinsLeftAfter: number;
}

export interface FreeSpinRound {
  spinsAwarded: number;
  spinsPlayed: number;
  frames: FreeSpinFrame[];
  total: number;
  bestSingle: number;
}

function runFreeSpins(rng: RngStream, bet: number): FreeSpinRound {
  let spinsLeft = FREE_SPINS_AWARDED;
  let awarded = FREE_SPINS_AWARDED;
  let played = 0;
  let total = 0;
  let bestSingle = 0;
  const frames: FreeSpinFrame[] = [];

  while (spinsLeft > 0) {
    spinsLeft--;
    played++;

    const grid = dealGrid(rng, true);
    const wildMultipliers = new Map<number, number>();
    for (const i of positionsOf(grid, 'WILD')) {
      wildMultipliers.set(
        i,
        pickWeighted(rng, WILD_MULTIPLIERS.map((m, k) => [m, WILD_MULTIPLIER_WEIGHTS[k]!] as [number, number])),
      );
    }

    const { wins, total: win } = scoreGrid(grid, bet, wildMultipliers);
    const scatters = countSymbol(grid, 'SCATTER');

    let retriggered = 0;
    if (scatters >= SCATTER_TRIGGER && awarded < FREE_SPINS_CAP) {
      retriggered = Math.min(FREE_SPINS_RETRIGGER, FREE_SPINS_CAP - awarded);
      awarded += retriggered;
      spinsLeft += retriggered;
    }

    total += win;
    if (win > bestSingle) bestSingle = win;

    frames.push({
      index: played,
      grid,
      wildMultipliers: Object.fromEntries(wildMultipliers),
      wins,
      win,
      scatters,
      retriggered,
      spinsLeftAfter: spinsLeft,
    });
  }

  return { spinsAwarded: awarded, spinsPlayed: played, frames, total, bestSingle };
}

// ── Vault of Lights (pick bonus) ─────────────────────────────────────────────

export interface VaultRound {
  /** What each of the nine capsules holds, in board order. */
  capsules: (JackpotTier | 'SPARKLE')[];
  /** The tier that completes a trio, or null for the consolation path. */
  wonTier: JackpotTier | null;
  /** Coins paid: the pool value on a win, or the consolation on the miss path. */
  amount: number;
  consolation: number;
}

/**
 * The layout is generated so that at most one tier can reach three capsules,
 * which makes the outcome independent of the order the player taps — nine picks
 * reveal every capsule, so a trio that exists is always found, and a trio that
 * does not exist can never be conjured by tapping in a different order.
 */
function buildVault(rng: RngStream, target: JackpotTier | 'NONE'): (JackpotTier | 'SPARKLE')[] {
  const capsules: (JackpotTier | 'SPARKLE')[] = [];
  const remaining: Record<JackpotTier, number> = { SPARK: 2, GLOW: 2, BEACON: 2, CITY: 2 };

  if (target !== 'NONE') {
    for (let i = 0; i < VAULT_MATCH; i++) capsules.push(target);
    remaining[target] = 0;
  }

  while (capsules.length < VAULT_CAPSULES) {
    const options: [JackpotTier | 'SPARKLE', number][] = [['SPARKLE', 3]];
    for (const tier of JACKPOT_TIERS) {
      if (remaining[tier] > 0) options.push([tier, 4]);
    }
    const pick = pickWeighted(rng, options);
    if (pick !== 'SPARKLE') remaining[pick]--;
    capsules.push(pick);
  }

  // Fisher-Yates from the same stream, so the layout is reproducible from seeds.
  for (let i = capsules.length - 1; i > 0; i--) {
    const j = Math.floor(rng.nextFloat() * (i + 1));
    [capsules[i], capsules[j]] = [capsules[j]!, capsules[i]!];
  }
  return capsules;
}

// ── Jackpot pools ────────────────────────────────────────────────────────────

interface PoolState {
  pool: number;
  reserve: number;
}

export type Pools = Record<JackpotTier, PoolState>;

const POOL_SETTING_KEY = 'neon_fortune_jackpots';

function freshPools(): Pools {
  return {
    SPARK: { pool: LAUNCH_SEED.SPARK, reserve: 0 },
    GLOW: { pool: LAUNCH_SEED.GLOW, reserve: 0 },
    BEACON: { pool: LAUNCH_SEED.BEACON, reserve: 0 },
    CITY: { pool: LAUNCH_SEED.CITY, reserve: 0 },
  };
}

let pools: Pools = freshPools();
let poolsLoaded = false;
let lastPersist = 0;

async function loadPools(): Promise<void> {
  if (poolsLoaded) return;
  poolsLoaded = true;
  try {
    const row = await prisma.appSetting.findUnique({ where: { key: POOL_SETTING_KEY } });
    if (row?.value) {
      const parsed = JSON.parse(row.value) as Partial<Pools>;
      for (const tier of JACKPOT_TIERS) {
        const s = parsed[tier];
        if (s && Number.isFinite(s.pool) && Number.isFinite(s.reserve)) {
          pools[tier] = { pool: Math.max(0, s.pool), reserve: Math.max(0, s.reserve) };
        }
      }
    }
  } catch (err) {
    console.error('[neon-fortune] could not load jackpot pools, using launch seed', err);
  }
}

async function persistPools(force = false): Promise<void> {
  const now = Date.now();
  if (!force && now - lastPersist < 5_000) return;
  lastPersist = now;
  try {
    const value = JSON.stringify(pools);
    await prisma.appSetting.upsert({
      where: { key: POOL_SETTING_KEY },
      update: { value },
      create: { key: POOL_SETTING_KEY, value },
    });
  } catch (err) {
    console.error('[neon-fortune] could not persist jackpot pools', err);
  }
}

/** Adds one bet's contribution to every pool. Pure — the caller owns `state`. */
export function contribute(state: Pools, bet: number): number {
  let taken = 0;
  for (const tier of JACKPOT_TIERS) {
    const slice = bet * CONTRIBUTION_RATE[tier]!;
    state[tier].pool += slice * (1 - RESERVE_SHARE);
    state[tier].reserve += slice * RESERVE_SHARE;
    taken += slice;
  }
  return taken;
}

/** Pays out a tier and re-seeds it from its own reserve. Pure. */
export function claimPool(state: Pools, tier: JackpotTier): number {
  const amount = Math.floor(state[tier].pool);
  const reseed = Math.min(state[tier].reserve, RESET_TARGET[tier]!);
  state[tier].pool = reseed;
  state[tier].reserve -= reseed;
  return amount;
}

export function poolValues(state: Pools = pools): Record<JackpotTier, number> {
  return {
    SPARK: Math.floor(state.SPARK.pool),
    GLOW: Math.floor(state.GLOW.pool),
    BEACON: Math.floor(state.BEACON.pool),
    CITY: Math.floor(state.CITY.pool),
  };
}

// ── Spin ─────────────────────────────────────────────────────────────────────

export interface SpinResult {
  bet: number;
  grid: Cell[];
  wins: LineWin[];
  baseWin: number;

  scatters: number;
  scatterCells: number[];
  freeSpinsTriggered: boolean;
  freeSpins: FreeSpinRound | null;
  freeSpinsWin: number;

  tokens: number;
  tokenCells: number[];
  vaultTriggered: boolean;
  vault: VaultRound | null;
  vaultWin: number;

  grandTotal: number;
  tier: CelebrationTier | null;
}

/**
 * Pure — no DB, no pool mutation — so the same function serves a live spin, the
 * provably-fair verifier and the RTP simulator. The vault's *tier* is drawn here;
 * turning that tier into coins is the caller's job, because only the caller knows
 * the live pool.
 */
export function computeSpin(rng: RngStream, bet: number): Omit<SpinResult, 'vaultWin' | 'grandTotal' | 'tier'> & {
  vaultTier: JackpotTier | 'NONE' | null;
} {
  const grid = dealGrid(rng, false);
  const { wins, total: baseWin } = scoreGrid(grid, bet, null);

  const scatterCells = positionsOf(grid, 'SCATTER');
  const tokenCells = positionsOf(grid, 'TOKEN');
  const freeSpinsTriggered = scatterCells.length >= SCATTER_TRIGGER;
  const vaultTriggered = tokenCells.length >= TOKEN_TRIGGER;

  const freeSpins = freeSpinsTriggered ? runFreeSpins(rng, bet) : null;

  let vaultTier: JackpotTier | 'NONE' | null = null;
  let vault: VaultRound | null = null;
  if (vaultTriggered) {
    vaultTier = pickWeighted(rng, VAULT_OUTCOME_WEIGHTS);
    vault = {
      capsules: buildVault(rng, vaultTier),
      wonTier: vaultTier === 'NONE' ? null : vaultTier,
      amount: 0, // filled in by the caller, which owns the pools
      consolation: Math.floor(bet * VAULT_CONSOLATION_MULT),
    };
  }

  return {
    bet,
    grid,
    wins,
    baseWin,
    scatters: scatterCells.length,
    scatterCells,
    freeSpinsTriggered,
    freeSpins,
    freeSpinsWin: freeSpins?.total ?? 0,
    tokens: tokenCells.length,
    tokenCells,
    vaultTriggered,
    vault,
    vaultTier,
  };
}

/** Applies a computed spin's vault outcome to a pool set and finishes the result. */
export function settleSpin(
  computed: ReturnType<typeof computeSpin>,
  state: Pools,
): SpinResult {
  let vaultWin = 0;
  if (computed.vault) {
    if (computed.vault.wonTier) {
      vaultWin = claimPool(state, computed.vault.wonTier);
    } else {
      vaultWin = computed.vault.consolation;
    }
    computed.vault.amount = vaultWin;
  }

  const grandTotal = computed.baseWin + computed.freeSpinsWin + vaultWin;
  const { vaultTier: _drop, ...rest } = computed;

  return {
    ...rest,
    vaultWin,
    grandTotal,
    tier: tierFor(grandTotal, computed.bet),
  };
}

/** Everything the client needs to draw the cabinet before the first spin. */
export function getLayout() {
  return {
    reels: REELS,
    rows: ROWS,
    lines: LINES,
    paylines: PAYLINES,
    minBet: MIN_BET,
    maxBet: MAX_BET,
    betSteps: BET_STEPS,
    paytable: PAYTABLE,
    paySymbols: PAY_SYMBOLS,
    scatterTrigger: SCATTER_TRIGGER,
    freeSpinsAwarded: FREE_SPINS_AWARDED,
    freeSpinsRetrigger: FREE_SPINS_RETRIGGER,
    freeSpinsCap: FREE_SPINS_CAP,
    wildMultipliers: WILD_MULTIPLIERS,
    tokenTrigger: TOKEN_TRIGGER,
    vaultCapsules: VAULT_CAPSULES,
    vaultMatch: VAULT_MATCH,
    vaultConsolationMult: VAULT_CONSOLATION_MULT,
    jackpotTiers: JACKPOT_TIERS,
    contributionRate: CONTRIBUTION_RATE,
    tierThresholds: Object.fromEntries(TIER_THRESHOLDS),
  };
}

// ── Provably fair seeds ──────────────────────────────────────────────────────

export const getFairness = (userId: number) => fairGetFairness(userId, GAME);
export const setClientSeed = (userId: number, seed: string) =>
  fairSetClientSeed(userId, GAME, seed);
/**
 * Rotates the server seed and reveals the retired one so the player can verify
 * everything they played under it.
 */
export const rotateServerSeed = (userId: number) => fairRotateServerSeed(userId, GAME);

/**
 * Recomputes a past spin from revealed seeds. The reels, the features and the
 * vault layout all reproduce exactly; the jackpot *amount* cannot, because it
 * depended on the pool at that moment — so it is reported as the tier, not a
 * coin figure.
 */
export function verifySpin(serverSeed: string, clientSeed: string, nonce: number, bet: number) {
  const rng = new RngStream(serverSeed, clientSeed, nonce);
  return computeSpin(rng, bet);
}

// ── History ──────────────────────────────────────────────────────────────────

export interface SpinRecord {
  nonce: number;
  bet: number;
  grandTotal: number;
  freeSpinsTriggered: boolean;
  vaultTier: JackpotTier | null;
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

// ── Recent wins feed ─────────────────────────────────────────────────────────
// Real wins by real players (D3 of the design review — nothing here is invented).
// Empty until somebody actually wins.

export interface FeedEntry {
  name: string;
  amount: number;
  tier: CelebrationTier | null;
  jackpot: JackpotTier | null;
  at: number;
}

const FEED_LIMIT = 20;
const feed: FeedEntry[] = [];

export function getFeed(): FeedEntry[] {
  return feed;
}

function pushFeed(entry: FeedEntry) {
  feed.unshift(entry);
  if (feed.length > FEED_LIMIT) feed.length = FEED_LIMIT;
}

// ── Lucky Drop ───────────────────────────────────────────────────────────────
// A free, claimable coin drop on a fixed cooldown. It *mints* coins into the
// same purchasable balance the rest of the app uses, so the two numbers below
// are a business decision, not a game-design one — they are deliberately small
// and sit here alone so they are easy to find and change.

export const LUCKY_DROP_REWARD = 250;
export const LUCKY_DROP_COOLDOWN_MS = 6 * 60 * 60 * 1000;

const LUCKY_SETTING_KEY = 'neon_fortune_lucky_drop';

/** userId → epoch ms of last claim. Only entries inside the cooldown matter. */
let luckyClaims = new Map<number, number>();
let luckyLoaded = false;

async function loadLucky(): Promise<void> {
  if (luckyLoaded) return;
  luckyLoaded = true;
  try {
    const row = await prisma.appSetting.findUnique({ where: { key: LUCKY_SETTING_KEY } });
    if (row?.value) {
      const parsed = JSON.parse(row.value) as Record<string, number>;
      for (const [id, at] of Object.entries(parsed)) {
        if (Number.isFinite(at)) luckyClaims.set(Number(id), at);
      }
    }
  } catch (err) {
    console.error('[neon-fortune] could not load lucky drop claims', err);
  }
}

/**
 * Persists the claim table, dropping anything already off cooldown — an expired
 * entry carries no information, so the stored map stays proportional to the
 * players active in the last six hours rather than to the user table.
 */
async function persistLucky(): Promise<void> {
  const cutoff = Date.now() - LUCKY_DROP_COOLDOWN_MS;
  const kept = new Map<number, number>();
  for (const [id, at] of luckyClaims) {
    if (at > cutoff) kept.set(id, at);
  }
  luckyClaims = kept;
  try {
    const value = JSON.stringify(Object.fromEntries(kept));
    await prisma.appSetting.upsert({
      where: { key: LUCKY_SETTING_KEY },
      update: { value },
      create: { key: LUCKY_SETTING_KEY, value },
    });
  } catch (err) {
    console.error('[neon-fortune] could not persist lucky drop claims', err);
  }
}

export interface LuckyDropStatus {
  reward: number;
  cooldownMs: number;
  canClaim: boolean;
  /** Epoch ms when the next claim opens; null when it is available now. */
  nextClaimAt: number | null;
}

export async function getLuckyDrop(userId: number): Promise<LuckyDropStatus> {
  await loadLucky();
  const last = luckyClaims.get(userId);
  const nextAt = last === undefined ? null : last + LUCKY_DROP_COOLDOWN_MS;
  const canClaim = nextAt === null || nextAt <= Date.now();
  return {
    reward: LUCKY_DROP_REWARD,
    cooldownMs: LUCKY_DROP_COOLDOWN_MS,
    canClaim,
    nextClaimAt: canClaim ? null : nextAt,
  };
}

export async function claimLuckyDrop(userId: number) {
  await loadLucky();
  const status = await getLuckyDrop(userId);
  if (!status.canClaim) {
    return {
      ok: false as const,
      code: 'COOLDOWN',
      message: 'الصندوق لم يجهز بعد',
      lucky: status,
    };
  }

  // Record the claim before crediting: a double-tap that races here finds the
  // cooldown already set and is refused, so the drop can only pay once.
  luckyClaims.set(userId, Date.now());
  let balance = 0;
  try {
    const user = await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: LUCKY_DROP_REWARD } },
      select: { coinsBalance: true },
    });
    balance = user.coinsBalance;
  } catch (err) {
    luckyClaims.delete(userId);
    console.error('[neon-fortune] lucky drop credit failed', { userId, err });
    return {
      ok: false as const,
      code: 'CLAIM_FAILED',
      message: 'تعذر فتح الصندوق',
      lucky: await getLuckyDrop(userId),
    };
  }

  await persistLucky();
  return {
    ok: true as const,
    reward: LUCKY_DROP_REWARD,
    balance,
    lucky: await getLuckyDrop(userId),
  };
}

// ── Spinning ─────────────────────────────────────────────────────────────────

export async function getState(userId: number) {
  await loadPools();
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { coinsBalance: true },
  });
  return {
    layout: getLayout(),
    balance: user?.coinsBalance ?? 0,
    jackpots: poolValues(),
    history: getHistory(userId),
    feed: getFeed(),
    fairness: await getFairness(userId),
    lucky: await getLuckyDrop(userId),
  };
}

export async function resolveSpin(userId: number, rawBet: unknown) {
  const bet = Math.trunc(Number(rawBet));
  if (!Number.isFinite(bet) || bet < MIN_BET || bet > MAX_BET) {
    return {
      ok: false as const,
      code: 'BAD_BET',
      message: `الرهان بين ${MIN_BET} و ${MAX_BET} عملة`,
    };
  }

  await loadPools();

  // Charge first, atomically, same guard as بلينكو and أثيرفول so parallel spins
  // can never overdraw a balance.
  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: bet } },
    data: { coinsBalance: { decrement: bet } },
  });
  if (charged.count === 0) {
    return { ok: false as const, code: 'INSUFFICIENT', message: 'رصيدك لا يكفي' };
  }

  // Reserved from the database, so two plays racing cannot draw the same nonce
  // and a restart cannot hand one out twice.
  const s = await reserveNonce(userId, GAME);
  const nonce = s.nonce;

  let spin: SpinResult;
  try {
    const rng = new RngStream(s.serverSeed, s.clientSeed, nonce);
    const computed = computeSpin(rng, bet);
    contribute(pools, bet);
    spin = settleSpin(computed, pools);

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
    console.error('[neon-fortune] spin failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'SPIN_FAILED', message: 'تعذر تنفيذ الجولة' };
  }

  const wonTier = spin.vault?.wonTier ?? null;
  await persistPools(wonTier !== null);

  remember(userId, {
    nonce,
    bet,
    grandTotal: spin.grandTotal,
    freeSpinsTriggered: spin.freeSpinsTriggered,
    vaultTier: wonTier,
    tier: spin.tier,
    at: Date.now(),
  });

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { coinsBalance: true, name: true },
  });

  // Only meaningful wins reach the feed, and only ones that actually happened.
  if (spin.grandTotal >= bet * 5) {
    pushFeed({
      name: user?.name || 'لاعب',
      amount: spin.grandTotal,
      tier: spin.tier,
      jackpot: wonTier,
      at: Date.now(),
    });
  }

  return {
    ok: true as const,
    spin,
    balance: user?.coinsBalance ?? 0,
    jackpots: poolValues(),
    serverSeedHash: s.serverSeedHash,
    clientSeed: s.clientSeed,
    nonce,
  };
}

/** Test hook: scores one board directly, for `npm run check:neon-fortune`. */
export function scoreGridForTest(
  grid: Cell[],
  bet: number,
  wildMultipliers?: Map<number, number>,
) {
  return scoreGrid(grid, bet, wildMultipliers ?? null);
}

/** Test hook: the simulator needs a pool set it owns, not the live one. */
export function simPools(): Pools {
  return freshPools();
}
