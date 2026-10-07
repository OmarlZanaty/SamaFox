import crypto from 'crypto';

/**
 * Versioned, pure server math. Row-major board (index = row*5 + reel); the
 * client only replays what this returns.
 *
 * v2 round shape:
 *  - Tumbles: every win is paid, the winning cells pop, the symbols above fall
 *    and new ones drop in from the top; repeat until nothing wins. Successive
 *    tumbles in one spin pay ×1, ×2, ×3, then ×5.
 *  - Free spins: 3/4/5+ BONUS anywhere on the opening board award 8/10/12 free
 *    spins at ×2/×3/×5 on everything they win. In free spins a WILD on a middle
 *    reel (2–4) expands to fill that reel. Free spins cannot retrigger.
 *  - Crowns: 3+ JACKPOT from the left on an active line pay a fixed 1000× the
 *    line bet, never multiplied.
 *  - The whole round is capped at MAX_MULTIPLIER × total bet.
 * Everything is drawn from one HMAC stream, so a revealed seed replays it all.
 */
export const MATH_VERSION = 2;
export const PAYLINES = [
  [1,1,1,1,1], [0,0,0,0,0], [2,2,2,2,2], [0,1,2,1,0],
  [2,1,0,1,2], [0,0,1,0,0], [2,2,1,2,2], [1,0,1,2,1], [1,2,1,0,1],
];
// Editable multipliers × bet PER LINE. Not odds or promises of a win.
export const PAYTABLE = {
  strawberry: [6,15,40], cherry: [6,20,60], orange: [8,25,80], lemon: [10,30,100],
  watermelon: [15,50,150], grapes: [20,75,200], candy: [25,100,300],
  diamond: [40,200,750], wild: [50,250,1000],
} as const;
export type PaySymbol = keyof typeof PAYTABLE;
export type Symbol = PaySymbol | 'bonus' | 'jackpot';
export const SYMBOLS = [...Object.keys(PAYTABLE), 'bonus', 'jackpot'] as Symbol[];
export const BET_STEPS = [10,20,50,100,200,500,1000];
export const JACKPOT_MULTIPLIER = 1000;
/** Round cap, in total bets. Also what the prize reservation holds back. */
export const MAX_MULTIPLIER = 1500;
export const TARGET_RTP = 0.70;
export const TUMBLE_MULTIPLIERS = [1,2,3,5];
export const MAX_TUMBLES = 20;
/** BONUS count on the opening board → free spins and their multiplier. */
export const FREE_SPIN_AWARDS: Record<number,{spins:number;multiplier:number}> = {
  3: {spins:8, multiplier:2}, 4: {spins:10, multiplier:3}, 5: {spins:12, multiplier:5},
};
export const EXPANDING_REELS = [1,2,3];
// Virtual weighted strips, sampled independently per cell. Calibrated by
// scripts/yummy-sim.ts --calibrate (Monte Carlo over the full v2 round).
export const WEIGHTS = [24.2,19.5,16,12.5,9.5,7.5,5,3,2,2.3,0.8];

export interface Rng { nextFloat(): number }
export class RngStream implements Rng {
  private block = Buffer.alloc(0);
  private cursor = 0;
  private index = 0;
  constructor(private serverSeed: string, private clientSeed: string, private nonce: number) {}
  nextFloat(): number {
    if (this.cursor + 4 > this.block.length) {
      this.block = crypto.createHmac('sha256', this.serverSeed)
        .update(`${this.clientSeed}:${this.nonce}:${this.index++}`).digest();
      this.cursor = 0;
    }
    const n = this.block.readUInt32BE(this.cursor);
    this.cursor += 4;
    return n / 0x100000000;
  }
}

export interface LineWin { line: number; symbol: Symbol; count: number; cells: number[]; amount: number }
export interface Tumble {
  /** Board this step was scored on. */
  grid: Symbol[];
  wins: LineWin[];
  /** Tumble multiplier × free-spin multiplier (crowns ignore it). */
  multiplier: number;
  /** What this step paid, multipliers included. */
  prize: number;
  /** Cells that pop after this step (empty on the last step). */
  removed: number[];
}
export interface FreeSpin { expandedReels: number[]; tumbles: Tumble[]; prize: number }
export interface FreeSpins { count: number; multiplier: number; trigger: number; spins: FreeSpin[]; prize: number }

export function validBet(bet: unknown, lines: unknown): boolean {
  return typeof bet === 'number' && BET_STEPS.includes(bet) &&
    typeof lines === 'number' && Number.isInteger(lines) && lines >= 1 && lines <= 9;
}

export function scoreGrid(grid: Symbol[], betPerLine: number, activeLines: number): LineWin[] {
  if (grid.length !== 15 || grid.some(s => !SYMBOLS.includes(s))) throw new Error('BAD_GRID');
  if (!validBet(betPerLine, activeLines)) throw new Error('BAD_BET');
  const wins: LineWin[] = [];
  PAYLINES.slice(0, activeLines).forEach((pattern, line) => {
    const cells = pattern.map((row, reel) => row * 5 + reel);
    let best: LineWin | undefined;
    for (const symbol of Object.keys(PAYTABLE) as PaySymbol[]) {
      let count = 0;
      for (const cell of cells) {
        if (grid[cell] === symbol || (symbol !== 'wild' && grid[cell] === 'wild')) count++;
        else break;
      }
      if (count < 3) continue;
      const amount = PAYTABLE[symbol][count - 3]! * betPerLine;
      if (!best || amount > best.amount) best = { line, symbol, count, cells: cells.slice(0,count), amount };
    }
    let crowns = 0;
    for (const cell of cells) { if (grid[cell] === 'jackpot') crowns++; else break; }
    if (crowns >= 3) best = { line, symbol: 'jackpot', count: crowns,
      cells: cells.slice(0,crowns), amount: JACKPOT_MULTIPLIER * betPerLine };
    if (best) wins.push(best);
  });
  return wins;
}

const TOTAL_WEIGHT = () => WEIGHTS.reduce((a,b) => a+b, 0);
function draw(rng: Rng, weight: number): Symbol {
  let pick = rng.nextFloat() * weight;
  for (let i = 0; i < SYMBOLS.length; i++) { pick -= WEIGHTS[i]!; if (pick < 0) return SYMBOLS[i]!; }
  return 'jackpot';
}
export function drawBoard(rng: Rng): Symbol[] {
  const weight = TOTAL_WEIGHT();
  return Array.from({length:15}, () => draw(rng, weight));
}

/** Pop [removed], let each reel fall, and fill the gaps from the top. */
export function collapse(grid: Symbol[], removed: number[], rng: Rng): Symbol[] {
  const weight = TOTAL_WEIGHT();
  const gone = new Set(removed);
  const next = [...grid];
  for (let reel = 0; reel < 5; reel++) {
    const kept: Symbol[] = [];
    for (let row = 2; row >= 0; row--) if (!gone.has(row*5+reel)) kept.push(grid[row*5+reel]!);
    // kept is bottom-up; new symbols are drawn top-down for the empty rows.
    const fresh = 3 - kept.length;
    const drawn = Array.from({length:fresh}, () => draw(rng, weight));
    const column = [...drawn, ...kept.reverse()];
    for (let row = 0; row < 3; row++) next[row*5+reel] = column[row]!;
  }
  return next;
}

/** Free spins only: a WILD on a middle reel fills that reel. Mutates [board]. */
export function expandWilds(board: Symbol[]): number[] {
  const reels = EXPANDING_REELS.filter(reel => [0,1,2].some(row => board[row*5+reel] === 'wild'));
  for (const reel of reels) for (let row = 0; row < 3; row++) board[row*5+reel] = 'wild';
  return reels;
}

/** One spin's tumble chain, from an already drawn board. */
export function tumbleChain(rng: Rng, start: Symbol[], betPerLine: number, activeLines: number, spinMultiplier: number): Tumble[] {
  const steps: Tumble[] = [];
  let grid = start;
  for (let step = 0; step < MAX_TUMBLES; step++) {
    const wins = scoreGrid(grid, betPerLine, activeLines);
    const multiplier = TUMBLE_MULTIPLIERS[Math.min(step, TUMBLE_MULTIPLIERS.length-1)]! * spinMultiplier;
    const prize = wins.reduce((sum,w) => sum + (w.symbol === 'jackpot' ? w.amount : w.amount*multiplier), 0);
    const removed = [...new Set(wins.flatMap(w => w.cells))].sort((a,b) => a-b);
    steps.push({ grid, wins, multiplier, prize, removed });
    if (!removed.length) break;
    grid = collapse(grid, removed, rng);
  }
  const last = steps[steps.length-1]!;
  if (last.removed.length) last.removed = []; // MAX_TUMBLES reached: stop here.
  return steps;
}

export function computeSpin(rng: Rng, betPerLine: number, activeLines: number) {
  if (!validBet(betPerLine, activeLines)) throw new Error('BAD_BET');
  const totalBet = betPerLine * activeLines;
  const grid = drawBoard(rng);
  const tumbles = tumbleChain(rng, grid, betPerLine, activeLines, 1);
  const basePrize = tumbles.reduce((sum,t) => sum+t.prize, 0);
  const trigger = grid.filter(s => s === 'bonus').length;
  let freeSpins: FreeSpins | null = null;
  if (trigger >= 3) {
    const award = FREE_SPIN_AWARDS[Math.min(trigger,5)]!;
    const spins: FreeSpin[] = [];
    for (let i = 0; i < award.spins; i++) {
      const board = drawBoard(rng);
      const expandedReels = expandWilds(board);
      const chain = tumbleChain(rng, board, betPerLine, activeLines, award.multiplier);
      spins.push({ expandedReels, tumbles: chain, prize: chain.reduce((sum,t) => sum+t.prize, 0) });
    }
    freeSpins = { count: award.spins, multiplier: award.multiplier, trigger, spins,
      prize: spins.reduce((sum,s) => sum+s.prize, 0) };
  }
  const uncapped = basePrize + (freeSpins?.prize ?? 0);
  const cap = MAX_MULTIPLIER * totalBet;
  const totalPrize = Math.min(uncapped, cap);
  const jackpotTriggered = [...tumbles, ...(freeSpins?.spins.flatMap(s => s.tumbles) ?? [])]
    .some(t => t.wins.some(w => w.symbol === 'jackpot'));
  return { mathVersion:MATH_VERSION, grid, wins: tumbles[0]!.wins, tumbles, betPerLine, activeLines, totalBet,
    basePrize, freeSpins, bonusTriggered: freeSpins !== null, jackpotTriggered,
    roundCapHit: uncapped > cap, totalPrize };
}
export type Spin = ReturnType<typeof computeSpin>;
