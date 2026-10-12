/** Offline only: imports the exact shipped math, never Prisma or a server.
 *
 *   npm run sim:yummy                      # check RTP against TARGET_RTP
 *   npm run sim:yummy -- --calibrate       # bisect the strawberry weight
 *   npm run sim:yummy -- --spins 1000000 --seeds 3 --bet 100 --lines 9
 */
import { computeSpin, RngStream, TARGET_RTP, WEIGHTS, MAX_MULTIPLIER } from '../src/services/yummy.math';

const read = (flag:string,fallback:number) => {
  const i=process.argv.indexOf(flag); return i<0 ? fallback : Number(process.argv[i+1]);
};
const bet=read('--bet',100), lines=read('--lines',9);

function run(spins:number, seeds:number, label='sim') {
  let wagered=0,returned=0,hits=0,bonuses=0,jackpots=0,squares=0,capped=0,tumbles=0,biggest=0;
  for(let seed=0;seed<seeds;seed++) {
    for(let nonce=0;nonce<spins;nonce++) {
      const r=computeSpin(new RngStream(`yummy-${label}-${seed}`,'sim',nonce),bet,lines);
      wagered+=r.totalBet; returned+=r.totalPrize;
      hits+=Number(r.totalPrize>0); bonuses+=Number(r.bonusTriggered); jackpots+=Number(r.jackpotTriggered);
      capped+=Number(r.roundCapHit); tumbles+=r.tumbles.length-1;
      const x=r.totalPrize/r.totalBet; squares+=x*x; biggest=Math.max(biggest,x);
    }
  }
  const n=spins*seeds, rtp=returned/wagered;
  return {spins:n,rtp,threeSigma:3*Math.sqrt(Math.max(0,squares/n-rtp**2)/n),hitRate:hits/n,
    freeSpinsEvery:bonuses?Math.round(n/bonuses):null,jackpots,capped,avgTumbles:tumbles/n,biggestX:biggest};
}

if (process.argv.includes('--calibrate')) {
  // The commonest fruit pays, so RTP rises (gently) with its weight.
  let low=18, high=30;
  const per=read('--spins',150000);
  for(let i=0;i<10;i++) {
    const mid=(low+high)/2; WEIGHTS[0]=mid;
    const r=run(per,1,`cal${i}`);
    console.log(`weight ${mid.toFixed(4)} → ${(100*r.rtp).toFixed(2)}%`);
    if(r.rtp>TARGET_RTP) high=mid; else low=mid;
  }
  console.log(JSON.stringify({strawberryWeight:(low+high)/2},null,2));
  process.exit(0);
}

const spins=read('--spins',400000), seeds=read('--seeds',3);
if (![spins,seeds].every(n=>Number.isInteger(n)&&n>0)) throw new Error('Positive integer spins/seeds required');
const r=run(spins,seeds);
console.log(JSON.stringify({betPerLine:bet,activeLines:lines,target:TARGET_RTP,maxMultiplier:MAX_MULTIPLIER,...r},null,2));
if(Math.abs(r.rtp-TARGET_RTP)>Math.max(.015,r.threeSigma) || r.rtp>=1) process.exitCode=1;
