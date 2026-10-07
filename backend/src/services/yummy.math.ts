import crypto from 'crypto';

/** Versioned, pure server math. Row-major board; the client only replays it. */
export const MATH_VERSION = 1;
export const PAYLINES = [
  [1,1,1,1,1], [0,0,0,0,0], [2,2,2,2,2], [0,1,2,1,0],
  [2,1,0,1,2], [0,0,1,0,0], [2,2,1,2,2], [1,0,1,2,1], [1,2,1,0,1],
];
// Editable multipliers × bet PER LINE. Not odds or promises of a win.
export const PAYTABLE = {
  strawberry: [2,8,20], cherry: [3,10,30], orange: [4,12,40], lemon: [5,15,50],
  watermelon: [8,25,80], grapes: [10,35,100], candy: [12,50,150],
  diamond: [20,100,500], wild: [25,150,1000],
} as const;
export type PaySymbol = keyof typeof PAYTABLE;
export type Symbol = PaySymbol | 'bonus' | 'jackpot';
export const SYMBOLS = [...Object.keys(PAYTABLE), 'bonus', 'jackpot'] as Symbol[];
export const BET_STEPS = [10,20,50,100,200,500,1000];
export const JACKPOT_MULTIPLIER = 1000;
export const MAX_MULTIPLIER = 1010; // At most 1000× per line + 10× total-bet bonus.
export const TARGET_RTP = 0.70;
// Virtual weighted strips, independently sampled per reel/cell. Calibrated by
// scripts/yummy-sim.ts, including scatters and the fixed jackpot award.
export const WEIGHTS = [41.109403676874,12,10,9,7,6,4,2,1,1,0.3];
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
export function computeSpin(rng: Rng, betPerLine: number, activeLines: number) {
  if (!validBet(betPerLine, activeLines)) throw new Error('BAD_BET');
  const weight = WEIGHTS.reduce((a,b) => a+b,0);
  const grid = Array.from({length:15}, (): Symbol => {
    let pick = rng.nextFloat() * weight;
    for (let i=0;i<SYMBOLS.length;i++) { pick -= WEIGHTS[i]!; if (pick < 0) return SYMBOLS[i]!; }
    return 'jackpot';
  });
  const wins = scoreGrid(grid,betPerLine,activeLines);
  const bonusTriggered = grid.filter(s => s === 'bonus').length >= 3;
  // Choice only reveals this precommitted award. Never a second money request.
  const bonusMultiplier = bonusTriggered ? [2,5,10][Math.floor(rng.nextFloat()*3)]! : 0;
  const totalBet = betPerLine * activeLines;
  const bonusPrize = bonusMultiplier * totalBet;
  const totalPrize = wins.reduce((sum,w) => sum+w.amount,0) + bonusPrize;
  return { mathVersion:MATH_VERSION, grid, wins, betPerLine, activeLines, totalBet,
    bonusTriggered, bonusMultiplier, bonusPrize, jackpotTriggered:wins.some(w => w.symbol === 'jackpot'), totalPrize };
}
export type Spin = ReturnType<typeof computeSpin>;
