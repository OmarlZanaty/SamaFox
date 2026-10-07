/** Offline only: imports the exact shipped math, never Prisma or a server. */
import { computeSpin, RngStream, TARGET_RTP, WEIGHTS, SYMBOLS, scoreGrid, Symbol } from '../src/services/yummy.math';
if (process.argv.includes('--calibrate')) {
  const outcomes: {counts:number[]; prize:number}[] = [];
  const combinations = SYMBOLS.length ** 5;
  for (let combination=0; combination<combinations; combination++) {
    let remaining=combination;
    const board:Symbol[]=Array(15).fill('bonus');
    const counts=Array<number>(SYMBOLS.length).fill(0);
    for (let reel=0;reel<5;reel++) {
      const index=remaining % SYMBOLS.length;
      remaining=Math.floor(remaining/SYMBOLS.length);
      board[5+reel]=SYMBOLS[index]!;
      counts[index]++;
    }
    const prize=scoreGrid(board,100,1).reduce((sum,win)=>sum+win.amount,0)/100;
    if(prize>0) outcomes.push({counts,prize});
  }
  const exact=(firstWeight:number)=> {
    const weights=[firstWeight,...WEIGHTS.slice(1)];
    const total=weights.reduce((sum,weight)=>sum+weight,0);
    const probabilities=weights.map(weight=>weight/total);
    const lines=outcomes.reduce((sum,outcome)=>sum+outcome.prize*outcome.counts.reduce((probability,count,index)=>probability*probabilities[index]!**count,1),0);
    const bonus=probabilities[SYMBOLS.indexOf('bonus')]!;
    const noBonus=(1-bonus)**15+15*bonus*(1-bonus)**14+105*bonus**2*(1-bonus)**13;
    return lines+(1-noBonus)*17/3;
  };
  let low=20,high=60;
  for(let iteration=0;iteration<40;iteration++) { const middle=(low+high)/2; if(exact(middle)>TARGET_RTP) high=middle; else low=middle; }
  console.log({strawberryWeight:(low+high)/2,exactRtp:exact((low+high)/2),currentRtp:exact(WEIGHTS[0]!)});
  process.exit(0);
}
const read = (flag:string,fallback:number) => {
  const i=process.argv.indexOf(flag); return i<0 ? fallback : Number(process.argv[i+1]);
};
const spins=read('--spins',400000), seeds=read('--seeds',3), bet=read('--bet',100), lines=read('--lines',9);
if (![spins,seeds].every(n=>Number.isInteger(n)&&n>0)) throw new Error('Positive integer spins/seeds required');
let wagered=0,returned=0,hits=0,bonuses=0,jackpots=0,squares=0;
for(let seed=0;seed<seeds;seed++) {
  let paid=0;
  for(let nonce=0;nonce<spins;nonce++) {
    const r=computeSpin(new RngStream(`yummy-sim-${seed}`,'sim',nonce),bet,lines);
    wagered+=r.totalBet; returned+=r.totalPrize; paid+=r.totalPrize;
    hits+=Number(r.totalPrize>0); bonuses+=Number(r.bonusTriggered); jackpots+=Number(r.jackpotTriggered);
    squares+=(r.totalPrize/r.totalBet)**2;
  }
  console.log(`seed ${seed}: ${(100*paid/(spins*bet*lines)).toFixed(3)}%`);
}
const n=spins*seeds,rtp=returned/wagered;
const error=3*Math.sqrt(Math.max(0,squares/n-rtp**2)/n);
console.log(JSON.stringify({spins:n,betPerLine:bet,activeLines:lines,rtp,target:TARGET_RTP,threeSigma:error,hitRate:hits/n,bonuses,jackpots},null,2));
if(Math.abs(rtp-TARGET_RTP)>Math.max(.015,error) || rtp>=1) process.exitCode=1;
