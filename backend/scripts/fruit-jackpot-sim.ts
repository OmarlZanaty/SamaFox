/** Offline only: imports the exact shipped math, never Prisma or a server.
 *
 *   npx ts-node --transpile-only scripts/fruit-jackpot-sim.ts               # check RTP
 *   npx ts-node --transpile-only scripts/fruit-jackpot-sim.ts --calibrate   # bisect TOKEN_WEIGHT
 */
import {computeSpin,RngStream,TARGET_RTP,TOKEN_WEIGHT,setTokenWeight} from '../src/services/fruitJackpot.math';

const read=(flag:string,fallback:number)=>{const i=process.argv.indexOf(flag);return i<0?fallback:Number(process.argv[i+1]);};

function run(spins:number,seeds:number,label='sim') {
  let paid=0,hits=0,bonuses=0,jackpots=0,capped=0,squares=0,lineHits=0;
  for(let seed=0;seed<seeds;seed++) for(let nonce=0;nonce<spins;nonce++) {
    const s=computeSpin(new RngStream(`fruit-${label}-${seed}`,'sim',nonce),100);
    paid+=s.totalPrize; hits+=Number(s.totalPrize>0); lineHits+=Number(s.wins.length>0);
    bonuses+=Number(s.bonusTriggered); jackpots+=Number(s.jackpotTriggered); capped+=Number(s.roundCapHit);
    squares+=(s.totalPrize/100)**2;
  }
  const n=spins*seeds, rtp=paid/(n*100);
  return {spins:n,rtp,threeSigma:3*Math.sqrt(Math.max(0,squares/n-rtp**2)/n),hitRate:hits/n,lineHitRate:lineHits/n,
    bonusEvery:bonuses?Math.round(n/bonuses):null,jackpots,capped};
}

if(process.argv.includes('--calibrate')) {
  let low=2,high=60;
  for(let i=0;i<14;i++){
    const mid=(low+high)/2; setTokenWeight(mid);
    const r=run(read('--spins',200000),1,`cal${i}`);
    console.log(`token weight ${mid.toFixed(4)} â†’ ${(100*r.rtp).toFixed(2)}%`);
    if(r.rtp>TARGET_RTP) low=mid; else high=mid;
  }
  console.log(JSON.stringify({tokenWeight:(low+high)/2},null,2));
  process.exit(0);
}

const r=run(read('--spins',400000),read('--seeds',3));
console.log(JSON.stringify({tokenWeight:TOKEN_WEIGHT,target:TARGET_RTP,...r},null,2));
if(Math.abs(r.rtp-TARGET_RTP)>Math.max(.015,r.threeSigma)||r.rtp>=1) process.exitCode=1;
