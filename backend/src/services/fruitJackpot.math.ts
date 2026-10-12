import { RngStream, Rng } from './yummy.math';
export { RngStream };
export type { Rng };

/**
 * Fruit Jackpot — versioned, pure server math. Board is row-major 3×3
 * (index = row*3 + col); the client only replays what this returns.
 *
 *  - Every cell is drawn independently from WEIGHTS (no outcome picking).
 *  - 8 lines (3 rows, 3 columns, 2 diagonals) pay PAYTABLE × bet for three
 *    of the same fruit. MULTIPLIER cells never pay a line.
 *  - The centre digital tile shows a per-round multiplier (CENTRE_TABLE) that
 *    multiplies every line win; the centre cell itself still holds a fruit.
 *  - Each row's x2 badge lights independently (ROW_BADGE_CHANCE) and doubles
 *    that row's horizontal line only.
 *  - MULTIPLIER tokens are blanks for lines. Three of them across the middle
 *    row open the bonus: one of 2×/5×/10× bet, drawn here; the card the
 *    player taps only reveals it.
 *  - Jackpot: a winning cherry line while the centre tile shows 9 — pays a
 *    fixed JACKPOT_MULTIPLIER × bet instead of that round's line prizes.
 *  - The round is capped at MAX_MULTIPLIER × bet.
 * `bet` is the whole stake (chips 100 / 1K / 10K / 100K).
 */
export const MATH_VERSION = 2;
export const TARGET_RTP = .70;
export const BET_STEPS = [100,1000,10000,100000];
export const JACKPOT_MULTIPLIER = 1000;
export const MAX_MULTIPLIER = 1000;
// Demo-editable multipliers × bet for a full line. Not odds or promises of a win.
export const PAYTABLE = {lemon:5,raspberry:5,kiwi:5,cherry:40,plum:5,watermelon:20,banana:10,strawberry:10};
export type Fruit = keyof typeof PAYTABLE;
export type Symbol = Fruit | 'multiplier';
export const SYMBOLS = [...Object.keys(PAYTABLE),'multiplier'] as Symbol[];
export const PAYLINES = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]];
// Same order as SYMBOLS. Calibrated by scripts/fruit-jackpot-sim.ts --calibrate
// (fruits are shaped roughly 1/sqrt(pay); TOKEN_WEIGHT is the MULTIPLIER
// token, a blank for lines — RTP falls as it rises).
export let TOKEN_WEIGHT = 12.3;
export const weights = (): number[] => [10,10,10,3.5,10,5,7,7,TOKEN_WEIGHT];
export const setTokenWeight = (w:number) => { TOKEN_WEIGHT = w; };
/** Centre tile value → chance. */
export const CENTRE_TABLE: [number,number][] = [[1,.92],[2,.05],[3,.02],[5,.008],[9,.002]];
export const ROW_BADGE_CHANCE = .03;
/** Cells that must all show the MULTIPLIER token to open the bonus. */
export const BONUS_LINE = [3,4,5];
export const BONUS_TABLE: [number,number][] = [[2,.6],[5,.3],[10,.1]];

export const validBet = (bet:unknown, lines:unknown = 8) =>
  typeof bet === 'number' && BET_STEPS.includes(bet) && lines === 8;

export interface LineWin { line:number; symbol:Fruit; count:3; cells:number[]; amount:number }

export function scoreGrid(grid:Symbol[], bet:number, centre = 1, rowMultipliers = [1,1,1]): LineWin[] {
  if (grid.length !== 9 || grid.some(s=>!SYMBOLS.includes(s))) throw new Error('BAD_GRID');
  if (!validBet(bet) || !CENTRE_TABLE.some(([v])=>v===centre) || rowMultipliers.length!==3 ||
      rowMultipliers.some(m=>m!==1&&m!==2)) throw new Error('BAD_BET');
  return PAYLINES.flatMap((cells,line)=>{
    const symbol=grid[cells[0]!]!;
    if(symbol==='multiplier'||!cells.every(c=>grid[c]===symbol)) return [];
    return [{line,symbol,count:3 as const,cells,amount:PAYTABLE[symbol]*bet*centre*(line<3?rowMultipliers[line]!:1)}];
  });
}

function pickFrom<T>(rng:Rng, table:[T,number][]): T {
  let r=rng.nextFloat();
  for(const [value,chance] of table){ r-=chance; if(r<0) return value; }
  return table[table.length-1]![0];
}

export function drawBoard(rng:Rng): Symbol[] {
  const w=weights(), total=w.reduce((a,b)=>a+b,0);
  return Array.from({length:9},()=>{
    let r=rng.nextFloat()*total;
    for(let i=0;i<SYMBOLS.length;i++){ r-=w[i]!; if(r<0) return SYMBOLS[i]!; }
    return SYMBOLS[SYMBOLS.length-1]!;
  });
}

export function computeSpin(rng:Rng, betPerLine:number, activeLines = 8) {
  if(!validBet(betPerLine,activeLines)) throw new Error('BAD_BET');
  const grid=drawBoard(rng);
  const centreMultiplier=pickFrom(rng,CENTRE_TABLE);
  const rowMultipliers=[0,1,2].map(()=>rng.nextFloat()<ROW_BADGE_CHANCE?2:1);
  const bonusTriggered=BONUS_LINE.every(c=>grid[c]==='multiplier');
  // Always drawn, so the stream position never depends on the outcome.
  const bonusDraw=pickFrom(rng,BONUS_TABLE);
  const bonusMultiplier=bonusTriggered?bonusDraw:0;
  const lineWins=scoreGrid(grid,betPerLine,centreMultiplier,rowMultipliers);
  const jackpotTriggered=centreMultiplier===9 && lineWins.some(w=>w.symbol==='cherry');
  const wins=lineWins;
  const basePrize=jackpotTriggered?JACKPOT_MULTIPLIER*betPerLine:wins.reduce((n,w)=>n+w.amount,0);
  const bonusPrize=bonusMultiplier*betPerLine;
  const uncapped=basePrize+bonusPrize;
  const cap=MAX_MULTIPLIER*betPerLine;
  return {mathVersion:MATH_VERSION,grid,wins,betPerLine,activeLines,totalBet:betPerLine,centreMultiplier,rowMultipliers,
    basePrize,bonusMultiplier,bonusPrize,bonusTriggered,jackpotTriggered,roundCapHit:uncapped>cap,
    totalPrize:Math.min(uncapped,cap)};
}
export type Spin = ReturnType<typeof computeSpin>;
