import crypto from 'crypto';
import prisma from '../utils/prisma';

// ─────────────────────────────────────────────────────────────────────────────
// AETHERFALL: VAULTS OF THE SKYFIRE
//
// Original fictional pay-anywhere / cascading-symbol game (not a copy of any
// published title — see the art-direction brief at the repo root for the
// creative-distinction notes). Like بلينكو, every spin is a single self-contained
// request: the server deals the grid, resolves every tumble in the cascade
// (including the Skyfire Vault bonus, if triggered) and returns the whole
// sequence pre-computed. The client only replays frames it has already been
// handed — it never decides a symbol, a tumble or a payout.
//
// Everything that moves coins lives in `resolveSpin`. The math is deliberately
// transparent end to end (base win → charge contribution → bonus → grand total)
// so the client can show its work instead of hiding a black box.
// ─────────────────────────────────────────────────────────────────────────────

export const COLS = 6;
export const ROWS = 5;
export const CELLS = COLS * ROWS;
export const MIN_MATCH = 9;

export const MIN_BET = 20;
export const MAX_BET = 20_000;

const HISTORY_LIMIT = 30;

export type StandardSymbol = 'L1' | 'L2' | 'L3' | 'L4' | 'H1' | 'H2' | 'H3' | 'H4';
export type SpecialSymbol = 'WILD' | 'KEY' | 'CHARGE';
export type Cell = StandardSymbol | SpecialSymbol;

export const STANDARD_SYMBOLS: StandardSymbol[] = ['L1', 'L2', 'L3', 'L4', 'H1', 'H2', 'H3', 'H4'];

// ── Reel weights ─────────────────────────────────────────────────────────────
// Uniform across all 6 columns (this is a pay-anywhere board, not payline reels).
// The bonus table leans richer in high symbols, wilds and charges so the Skyfire
// Vault feels materially more generous than base play, per the design brief.

const WEIGHTS_BASE: Record<Cell, number> = {
  L1: 17, L2: 16, L3: 15, L4: 13,
  H1: 10, H2: 8, H3: 6, H4: 4,
  WILD: 3, KEY: 2.6, CHARGE: 5.4,
};

const WEIGHTS_BONUS: Record<Cell, number> = {
  L1: 14, L2: 13, L3: 12, L4: 11,
  H1: 11, H2: 9, H3: 7, H4: 5,
  WILD: 5, KEY: 2.6, CHARGE: 8.4,
};

// ── Paytable ─────────────────────────────────────────────────────────────────
// Values are the payout as a multiple of the total bet. Three count bands:
// 9-11, 12-14, 15+ (of the 30 visible cells).
//
// Tuned to ~97% RTP — a 3% house edge, matching طيّار — and *measured*, not
// guessed: `npm run sim:aetherfall` replays this exact math over hundreds of
// thousands of spins and fails loudly if the return creeps back over 100%. An
// earlier version of this table claimed ~94% in a comment but actually returned
// ~102.5%, so the game paid out more than it took in; re-run the simulator after
// touching anything in this block or the weights above.
//
// Measured over 1.2M spins: 96.98% at the 20-coin minimum (seed spread
// 96.45-97.54%), 34.2% hit rate, bonus 1 in 115 paying ~21x bet. RTP drifts up
// slightly with stake — 97.65% at 5,000 coins — because payouts are floored to
// whole coins and that rounding bites proportionally harder on small wins. The
// house edge is therefore widest exactly where it matters least; both ends sit
// well under 100%, which is the line that actually has to hold.
//
// Both base play and the bonus read this one table, and every payout is linear
// in it, so scaling the whole table scales total RTP by the same factor. That
// makes it the safest lever: hit rate, bonus frequency and the shape of the game
// all stay exactly where they were.
export const PAYTABLE: Record<StandardSymbol, [number, number, number]> = {
  L1: [0.95, 2.3, 5.5],
  L2: [1.15, 2.85, 6.5],
  L3: [1.3, 3.2, 7.6],
  L4: [1.8, 4.5, 11],
  H1: [2.75, 6.8, 18],
  H2: [4.5, 11, 32],
  H3: [9, 22, 72],
  H4: [18, 45, 135],
};

function bandOf(count: number): 0 | 1 | 2 {
  if (count >= 15) return 2;
  if (count >= 12) return 1;
  return 0;
}

// ── Ember Charge values ───────────────────────────────────────────────────────
// Charge symbols collected during a winning tumble are summed and applied as a
// percentage boost to the sequence (base game) or banked for the whole bonus
// (Skyfire Vault) — see runBonus. Capped, unlike an uncapped orb-multiplier
// system, so the platform's exposure per spin stays bounded.
export const CHARGE_VALUES = [2, 3, 5, 8, 12, 20, 35, 60] as const;
const CHARGE_WEIGHTS = [30, 25, 20, 12, 7, 3.5, 1.8, 0.7];

// ── Skyfire Vault bonus tunables ─────────────────────────────────────────────
export const VAULT_KEY_TRIGGER = 4;
// 13, not 12: making Constellation Lock actually pin cells cost the bonus about
// 1.3 points of RTP, because a pinned symbol resists the refill and so reduces
// the churn that generates fresh wins. The tumble that buys it back is spent
// where the value was lost. Re-measure with `npm run sim:aetherfall`.
export const VAULT_BONUS_START_TUMBLES = 13;
export const VAULT_RETRIGGER_KEYS = 3;
export const VAULT_RETRIGGER_TUMBLES = 3;
export const CONSTELLATION_LOCK_TARGET = 3;

// ── Celebration tiers ────────────────────────────────────────────────────────
export type CelebrationTier = 'BRIGHT_HIT' | 'SKYFIRE_SURGE' | 'CELESTIAL_BREAK' | 'AETHERFALL';

const TIER_THRESHOLDS: [CelebrationTier, number][] = [
  ['AETHERFALL', 100],
  ['CELESTIAL_BREAK', 50],
  ['SKYFIRE_SURGE', 25],
  ['BRIGHT_HIT', 10],
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
// Same provably-fair contract as بلينكو and طيّار: HMAC-SHA256(serverSeed,
// `${clientSeed}:${nonce}:${block}`) expanded block by block. A spin consumes a
// variable number of bytes (cascades and the bonus are open-ended), so the
// stream just keeps minting blocks on demand rather than pre-sizing like a
// fixed-row Plinko path.

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

const chargeTotalWeight = CHARGE_WEIGHTS.reduce((a, b) => a + b, 0);
const chargeCum: number[] = [];
{
  let acc = 0;
  for (const w of CHARGE_WEIGHTS) {
    acc += w;
    chargeCum.push(acc);
  }
}

function pickCharge(rng: RngStream): number {
  const r = rng.nextFloat() * chargeTotalWeight;
  for (let i = 0; i < chargeCum.length; i++) {
    if (r < chargeCum[i]!) return CHARGE_VALUES[i]!;
  }
  return CHARGE_VALUES[0];
}

// ── Grid mechanics ───────────────────────────────────────────────────────────

function dealGrid(rng: RngStream, sampler: (rng: RngStream) => Cell): Cell[] {
  return Array.from({ length: CELLS }, () => sampler(rng));
}

/** Gravity refill: existing symbols in each column fall to the bottom, new symbols enter from the top. */
/**
 * Gravity refill: surviving symbols in each column fall to the bottom and new
 * symbols enter from the top.
 *
 * Constellation-locked cells are pinned — they keep both their symbol and their
 * row while everything else falls around them. A lock only resists gravity; it
 * does not protect the cell from winning, and `evalAndAdvance` releases the lock
 * of any cell it clears, which is what keeps a locked winning symbol from
 * re-winning forever.
 */
function refill(
  grid: (Cell | null)[],
  rng: RngStream,
  sampler: (rng: RngStream) => Cell,
  locked: ReadonlySet<number> = new Set(),
) {
  for (let c = 0; c < COLS; c++) {
    // Rows this column may write to, bottom-up, skipping pinned cells.
    const openRows: number[] = [];
    const survivors: Cell[] = [];
    for (let r = ROWS - 1; r >= 0; r--) {
      const idx = r * COLS + c;
      if (locked.has(idx)) continue;
      openRows.push(r);
      const v = grid[idx];
      if (v) survivors.push(v);
    }
    for (let i = 0; i < openRows.length; i++) {
      const idx = openRows[i]! * COLS + c;
      grid[idx] = i < survivors.length ? survivors[i]! : sampler(rng);
    }
  }
}

export interface WinEntry {
  symbol: StandardSymbol;
  count: number;
  amount: number;
}

export interface ChargeCell {
  index: number;
  value: number;
}

export interface TumbleFrame {
  phase: 'base' | 'bonus';
  /** The grid as it should be shown/evaluated for this frame, before any removal. */
  grid: Cell[];
  wins: WinEntry[];
  winningCells: number[];
  chargeCells: ChargeCell[];
  /** Bonus-only metadata, present on the first frame of each free tumble. */
  tumbleNumber?: number;
  tumblesLeftAfter?: number;
  retriggerAdded?: number;
  isStarburst?: boolean;
  chargeBankAfter?: number;
  locksAfter?: number;
  /** Bonus-only: board indices currently pinned by a Constellation Lock. */
  lockedCells?: number[];
}

/**
 * Evaluates the grid currently shown, then (if it won) clears the winning and
 * charge cells and refills — mutating `grid` in place so the caller can loop.
 * Returns a frame carrying the pre-removal snapshot, so the client always has
 * something meaningful to render even on the terminal (no-win) frame.
 */
function evalAndAdvance(
  grid: Cell[],
  bet: number,
  rng: RngStream,
  sampler: (rng: RngStream) => Cell,
  phase: 'base' | 'bonus',
  forceWild = false,
  locked?: Set<number>,
): { frame: TumbleFrame; hadWin: boolean } {
  if (forceWild && !grid.includes('WILD')) {
    const idx = Math.floor(rng.nextFloat() * CELLS);
    grid[idx] = 'WILD';
  }

  const counts: Partial<Record<Cell, number>> = {};
  for (const s of grid) counts[s] = (counts[s] ?? 0) + 1;
  const wildCount = counts.WILD ?? 0;

  const wins: WinEntry[] = [];
  const winningCells = new Set<number>();
  for (const sym of STANDARD_SYMBOLS) {
    const total = (counts[sym] ?? 0) + wildCount;
    if (total >= MIN_MATCH) {
      const amount = bet * PAYTABLE[sym][bandOf(total)];
      wins.push({ symbol: sym, count: total, amount });
      grid.forEach((v, i) => {
        if (v === sym || v === 'WILD') winningCells.add(i);
      });
    }
  }

  const hadWin = wins.length > 0;
  const chargeCells: ChargeCell[] = [];
  if (hadWin) {
    grid.forEach((v, i) => {
      if (v === 'CHARGE') chargeCells.push({ index: i, value: pickCharge(rng) });
    });
  }

  const frame: TumbleFrame = {
    phase,
    grid: grid.slice(),
    wins,
    winningCells: [...winningCells],
    chargeCells,
  };

  if (hadWin) {
    const toClear = new Set<number>([...winningCells, ...chargeCells.map((c) => c.index)]);
    for (const i of toClear) {
      (grid as (Cell | null)[])[i] = null;
      // A cleared cell gives up its lock; otherwise a pinned winning symbol
      // would be re-counted on every following tumble.
      locked?.delete(i);
    }
    refill(grid as (Cell | null)[], rng, sampler, locked);

    // The new lock is placed after the refill so it pins a symbol that is
    // actually on the board, and never a special one.
    if (locked && phase === 'bonus') {
      const candidates: number[] = [];
      grid.forEach((v, i) => {
        if (!locked.has(i) && (STANDARD_SYMBOLS as readonly Cell[]).includes(v)) candidates.push(i);
      });
      if (candidates.length > 0) {
        locked.add(candidates[Math.floor(rng.nextFloat() * candidates.length)]!);
      }
    }
  }

  frame.lockedCells = locked ? [...locked] : undefined;
  return { frame, hadWin };
}

function runBaseSequence(initialGrid: Cell[], bet: number, rng: RngStream) {
  const frames: TumbleFrame[] = [];
  let win = 0;
  let charge = 0;
  const grid = initialGrid.slice();

  while (true) {
    const { frame, hadWin } = evalAndAdvance(grid, bet, rng, sampleBase, 'base');
    frames.push(frame);
    if (!hadWin) break;
    win += frame.wins.reduce((a, w) => a + w.amount, 0);
    charge += frame.chargeCells.reduce((a, c) => a + c.value, 0);
  }

  return { frames, baseWin: win, baseCharge: charge };
}

function runBonus(bet: number, rng: RngStream) {
  const frames: TumbleFrame[] = [];
  let tumblesLeft = VAULT_BONUS_START_TUMBLES;
  let chargeBank = 0;
  let bonusWin = 0;
  let tumbleNumber = 0;
  let guard = 0;

  // Cells pinned by a Constellation Lock. Lives across the whole bonus, not one
  // tumble, so a thread survives into the next free tumble the way the feature
  // is described in the help panel.
  const locked = new Set<number>();
  let lastGrid: Cell[] | null = null;

  while (tumblesLeft > 0 && guard < 400) {
    guard++;
    tumbleNumber++;
    tumblesLeft--;

    const grid = dealGrid(rng, sampleBonus);
    // A fresh deal would wipe the pinned symbols, so they are carried over from
    // where the previous tumble left them.
    if (lastGrid) {
      for (const i of locked) {
        const held = lastGrid[i];
        if (held) grid[i] = held;
      }
    }

    const keys = grid.filter((s) => s === 'KEY').length;
    let retriggerAdded = 0;
    if (keys >= VAULT_RETRIGGER_KEYS) {
      tumblesLeft += VAULT_RETRIGGER_TUMBLES;
      retriggerAdded = VAULT_RETRIGGER_TUMBLES;
    }

    let isFirstFrameOfTumble = true;
    while (true) {
      const { frame, hadWin } = evalAndAdvance(
        grid, bet, rng, sampleBonus, 'bonus', false, locked,
      );
      if (isFirstFrameOfTumble) {
        frame.tumbleNumber = tumbleNumber;
        frame.tumblesLeftAfter = tumblesLeft;
        frame.retriggerAdded = retriggerAdded;
        isFirstFrameOfTumble = false;
      }
      frames.push(frame);
      if (!hadWin) break;

      bonusWin += frame.wins.reduce((a, w) => a + w.amount, 0);
      chargeBank += frame.chargeCells.reduce((a, c) => a + c.value, 0);
      frame.chargeBankAfter = chargeBank;
      frame.locksAfter = locked.size;

      if (locked.size >= CONSTELLATION_LOCK_TARGET) {
        // The threads connect: the pins are spent on a free tumble that is
        // guaranteed a Prism Wild.
        locked.clear();
        const sb = evalAndAdvance(grid, bet, rng, sampleBonus, 'bonus', true, locked);
        sb.frame.isStarburst = true;
        sb.frame.locksAfter = locked.size;
        frames.push(sb.frame);
        if (sb.hadWin) {
          bonusWin += sb.frame.wins.reduce((a, w) => a + w.amount, 0);
          chargeBank += sb.frame.chargeCells.reduce((a, c) => a + c.value, 0);
          sb.frame.chargeBankAfter = chargeBank;
        }
      }
    }

    lastGrid = grid;
  }

  return { frames, bonusWin, chargeBank, tumblesUsed: tumbleNumber };
}

export interface SpinResult {
  bet: number;
  initialGrid: Cell[];
  vaultKeysInitial: number;
  bonusTriggered: boolean;
  frames: TumbleFrame[];
  baseWin: number;
  baseCharge: number;
  baseTotal: number;
  bonusWin: number;
  bonusCharge: number;
  bonusTumblesUsed: number;
  bonusTotal: number;
  grandTotal: number;
  tier: CelebrationTier | null;
}

/** Pure — no DB access — so it can be reused for both a live spin and provably-fair verification. */
export function computeSpin(rng: RngStream, bet: number): SpinResult {
  const initialGrid = dealGrid(rng, sampleBase);
  const vaultKeysInitial = initialGrid.filter((s) => s === 'KEY').length;
  const bonusTriggered = vaultKeysInitial >= VAULT_KEY_TRIGGER;

  const { frames: baseFrames, baseWin, baseCharge } = runBaseSequence(initialGrid, bet, rng);
  const baseTotal = Math.floor(baseWin * (1 + baseCharge / 100));

  let bonusFrames: TumbleFrame[] = [];
  let bonusWin = 0;
  let bonusCharge = 0;
  let bonusTumblesUsed = 0;
  let bonusTotal = 0;

  if (bonusTriggered) {
    const b = runBonus(bet, rng);
    bonusFrames = b.frames;
    bonusWin = b.bonusWin;
    bonusCharge = b.chargeBank;
    bonusTumblesUsed = b.tumblesUsed;
    bonusTotal = Math.floor(bonusWin * (1 + bonusCharge / 100));
  }

  const grandTotal = baseTotal + bonusTotal;

  return {
    bet,
    initialGrid,
    vaultKeysInitial,
    bonusTriggered,
    frames: [...baseFrames, ...bonusFrames],
    baseWin,
    baseCharge,
    baseTotal,
    bonusWin,
    bonusCharge,
    bonusTumblesUsed,
    bonusTotal,
    grandTotal,
    tier: tierFor(grandTotal, bet),
  };
}

/** Everything the client needs to draw the board and paytable before the first spin. */
export function getLayout() {
  return {
    cols: COLS,
    rows: ROWS,
    minMatch: MIN_MATCH,
    minBet: MIN_BET,
    maxBet: MAX_BET,
    paytable: PAYTABLE,
    chargeValues: CHARGE_VALUES,
    vaultKeyTrigger: VAULT_KEY_TRIGGER,
    vaultBonusStartTumbles: VAULT_BONUS_START_TUMBLES,
    vaultRetriggerKeys: VAULT_RETRIGGER_KEYS,
    vaultRetriggerTumbles: VAULT_RETRIGGER_TUMBLES,
    constellationLockTarget: CONSTELLATION_LOCK_TARGET,
    tierThresholds: Object.fromEntries(TIER_THRESHOLDS),
    standardSymbols: STANDARD_SYMBOLS,
  };
}

// ── Provably fair seeds ───────────────────────────────────────────────────────

const sha256 = (input: string) => crypto.createHash('sha256').update(input).digest('hex');

interface SeedState {
  serverSeed: string;
  serverSeedHash: string;
  clientSeed: string;
  nonce: number;
}

const seeds = new Map<number, SeedState>();

function freshServerSeed(): { serverSeed: string; serverSeedHash: string } {
  const serverSeed = crypto.randomBytes(32).toString('hex');
  return { serverSeed, serverSeedHash: sha256(serverSeed) };
}

function seedsFor(userId: number): SeedState {
  let s = seeds.get(userId);
  if (!s) {
    s = { ...freshServerSeed(), clientSeed: `u${userId}`, nonce: 0 };
    seeds.set(userId, s);
  }
  return s;
}

export function getFairness(userId: number) {
  const s = seedsFor(userId);
  return { serverSeedHash: s.serverSeedHash, clientSeed: s.clientSeed, nonce: s.nonce };
}

export function setClientSeed(userId: number, seed: string) {
  const clean = String(seed ?? '').trim().slice(0, 64);
  if (!clean) return { ok: false as const, code: 'BAD_SEED', message: 'البذرة غير صالحة' };
  const s = seedsFor(userId);
  s.clientSeed = clean;
  return { ok: true as const, clientSeed: clean };
}

export function rotateServerSeed(userId: number) {
  const s = seedsFor(userId);
  const revealed = { serverSeed: s.serverSeed, serverSeedHash: s.serverSeedHash, nonce: s.nonce };
  const next = freshServerSeed();
  s.serverSeed = next.serverSeed;
  s.serverSeedHash = next.serverSeedHash;
  s.nonce = 0;
  return { revealed, serverSeedHash: next.serverSeedHash };
}

/** Recomputes a past spin from revealed seeds so the player can check it. */
export function verifySpin(serverSeed: string, clientSeed: string, nonce: number, bet: number): SpinResult {
  const rng = new RngStream(serverSeed, clientSeed, nonce);
  return computeSpin(rng, bet);
}

// ── History ──────────────────────────────────────────────────────────────────

export interface SpinRecord {
  nonce: number;
  bet: number;
  grandTotal: number;
  bonusTriggered: boolean;
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

  // Charge first, atomically, same guard pattern as بلينكو so parallel spins
  // can never overdraw a balance.
  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: bet } },
    data: { coinsBalance: { decrement: bet } },
  });
  if (charged.count === 0) {
    return { ok: false as const, code: 'INSUFFICIENT', message: 'رصيدك لا يكفي' };
  }

  const s = seedsFor(userId);
  const nonce = s.nonce++;

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
    console.error('[aetherfall] spin failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'SPIN_FAILED', message: 'تعذر تنفيذ الجولة' };
  }

  remember(userId, {
    nonce,
    bet,
    grandTotal: spin.grandTotal,
    bonusTriggered: spin.bonusTriggered,
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
