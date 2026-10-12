import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { computeSpin, parseBets, maxPrize, RngStream, Rng, WEIGHTS, TOTAL_WEIGHT, SEGMENTS, MULTIPLIERS, CARDS,
  BONUS_BASE, Outcome } from '../fruitWheel.math';
import { invalidateGameConfigCache } from '../gameConfig.service';
import { __resetHalalForTests } from '../halalGames.service';
import { resolveSpin, verifySpin, getTodayPot, __resetForTests } from '../fruitWheel.service';
import { __resetGameBroadcastForTests } from '../gameBroadcast.service';

const rounds=new Map<string,any>();
let failHistory=false;
let transactionCount=0;
fakePrisma.fruitWheelRound={
  findUnique:async ({where}:any)=>rounds.get(`${where.userId_requestId.userId}:${where.userId_requestId.requestId}`)??null,
  create:async ({data}:any)=> {
    if(failHistory) throw new Error('simulated history failure');
    const record={...data,id:`round-${rounds.size}`,createdAt:new Date()};
    rounds.set(`${data.userId}:${data.requestId}`,record);return record;
  },
  count:async ({where}:any)=>[...rounds.values()].filter(r=>r.userId===where.userId).length,
  findMany:async ({where,take}:any)=>[...rounds.values()]
    .filter(row=>(where.userId==null||row.userId===where.userId)&&(!where.createdAt?.gte||row.createdAt>=where.createdAt.gte))
    .reverse().slice(0,take??50),
};
fakePrisma.$transaction=async (callback:any)=> {
  transactionCount++;
  const saved={balances:new Map(balances),accounts:new Map(accounts),rounds:new Map(rounds),ledger:ledger.length,economy:economyLedger.length,xp:xpAwards.length};
  try {return await callback(fakePrisma);}
  catch(error) {
    balances.clear();for(const [k,v] of saved.balances) balances.set(k,v);
    accounts.clear();for(const [k,v] of saved.accounts) accounts.set(k,v);
    rounds.clear();for(const [k,v] of saved.rounds) rounds.set(k,v);
    ledger.length=saved.ledger;economyLedger.length=saved.economy;xpAwards.length=saved.xp;
    throw error;
  }
};
beforeEach(()=>{
  balances.clear();accounts.clear();rounds.clear();settings.clear();ledger.length=0;economyLedger.length=0;xpAwards.length=0;
  failHistory=false;transactionCount=0;
  __resetGameBroadcastForTests();__resetForTests();
  accounts.set('GAME_POOL:fruitwheel',100000000);accounts.set('PROGRAM',0);balances.set(701,500000);
  invalidateGameConfigCache();__resetHalalForTests();
});

// A float that rolls [outcome] on the first draw; later draws come from [rest].
const roll=(outcome:Outcome)=>{
  let before=0;
  for(const [key,weight] of Object.entries(WEIGHTS)){if(key===outcome) return (before+weight/2)/TOTAL_WEIGHT;before+=weight;}
  throw new Error(outcome);
};
const scripted=(outcome:Outcome,rest:number[]=[]):Rng=>{let i=0;const q=[roll(outcome),...rest];return {nextFloat:()=>q[i++]??0.5};};
const bets=(w=0,s=0,p=0)=>({watermelon:w,sevens:s,plum:p});

test('bets: whole chips on known cards, total within range',()=>{
  assert.deepEqual(parseBets({watermelon:100}),bets(100));
  assert.deepEqual(parseBets({watermelon:1000,sevens:100,plum:200}),bets(1000,100,200));
  for(const bad of [null,[],{},{watermelon:0},{watermelon:150},{watermelon:-100},{watermelon:'100'},{banana:100},
    {watermelon:1.5},{watermelon:300100}]) assert.equal(parseBets(bad),null,JSON.stringify(bad));
});
test('every card returns the same share of its stake',()=>{
  const rtps=CARDS.map(c=>WEIGHTS[c]*MULTIPLIERS[c]/TOTAL_WEIGHT);
  for(const r of rtps) assert.ok(Math.abs(r-rtps[0]!)<1e-9);
  assert.ok(rtps[0]!<0.7);
});
test('the matching card pays stake × multiplier; the others lose',()=>{
  const w=computeSpin(scripted('watermelon'),bets(1000,500,700));
  assert.equal(w.winner,'watermelon');assert.equal(w.totalPrize,2000);assert.equal(w.totalBet,2200);
  const s=computeSpin(scripted('sevens'),bets(1000,500,700));
  assert.equal(s.winner,'sevens');assert.equal(s.totalPrize,1500);
  const p=computeSpin(scripted('plum'),bets(1000,0,0));
  assert.equal(p.totalPrize,0);assert.equal(p.orbs,null);
});
test('the wheel stops on a segment that shows the outcome, away from its borders',()=>{
  for(const outcome of ['watermelon','plum','sevens','bonus'] as Outcome[]) {
    for(const pick of [0,0.3,0.99]) {
      const spin=computeSpin(scripted(outcome,[pick,0.999]),bets(100));
      assert.equal(SEGMENTS[spin.segment],outcome);
      assert.ok(spin.offset>=0.15&&spin.offset<=0.85);
    }
  }
});
test('BONUS: card bets lose and the orb pays its multiplier × a tenth of the stake',()=>{
  const spin=computeSpin(scripted('bonus',[0,0.5,0.99,0.1]),bets(1000,1000,1000));
  assert.equal(spin.winner,null);assert.equal(spin.cardPrize,0);
  assert.equal(spin.orbs!.length,3);assert.deepEqual([...spin.orbs!].sort(),[2,3,5]);
  assert.equal(spin.bonusPrize,3000*BONUS_BASE*spin.orbs![0]!);assert.equal(spin.totalPrize,spin.bonusPrize);
});
test('maxPrize covers every outcome',()=>{
  const b=bets(1000,2000,300);
  assert.equal(maxPrize(b),6000);
  for(let n=0;n<300;n++) assert.ok(computeSpin(new RngStream('c'.repeat(64),'x',n),b).totalPrize<=maxPrize(b));
});
test('HMAC streams replay exactly; verify matches the round',()=>{
  const seed='a'.repeat(64);
  const spin=computeSpin(new RngStream(seed,'client',4),bets(100,100,100));
  assert.deepEqual(computeSpin(new RngStream(seed,'client',4),bets(100,100,100)),spin);
  const verified=verifySpin(seed,'client',4,bets(100,100,100));
  assert.equal(verified.segment,spin.segment);assert.equal(verified.totalPrize,spin.totalPrize);
  assert.throws(()=>verifySpin('zz','client',4,bets(100)),{code:'BAD_VERIFY'});
});
test('measured RTP is close to the stated 69.4%',()=>{
  let staked=0,paid=0;
  for(let n=0;n<60000;n++){const r=computeSpin(new RngStream('d'.repeat(64),'sim',n),bets(100,100,100));staked+=r.totalBet;paid+=r.totalPrize;}
  assert.ok(Math.abs(paid/staked-0.694)<0.02,String(paid/staked));
});
test('one transaction debits once, splits the stake, pays, numbers the round and stores it',async()=>{
  const result:any=await resolveSpin(701,bets(1000,0,1000),'first');
  assert.equal(transactionCount,1);
  assert.equal(result.balance,500000-2000+result.spin.totalPrize);
  assert.equal(accounts.get('PROGRAM'),500);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'),100000000+1500-result.spin.totalPrize);
  assert.equal(result.round,1);assert.equal(rounds.size,1);assert.equal(ledger.length,2);
  const second:any=await resolveSpin(701,bets(100),'second');
  assert.equal(second.round,2);assert.notEqual(second.nonce,result.nonce);
});
test('insufficient balance and bad bets are refused before any coin moves',async()=>{
  balances.set(701,999);
  await assert.rejects(resolveSpin(701,bets(1000),'poor'),{code:'INSUFFICIENT'});
  await assert.rejects(resolveSpin(701,bets(150),'odd'),{code:'BAD_BET'});
  assert.equal(balances.get(701),999);assert.equal(rounds.size,0);assert.equal(ledger.length,0);
});
test('history failure rolls back every coin movement',async()=>{
  failHistory=true;
  await assert.rejects(resolveSpin(701,bets(1000),'rollback'),/history failure/);
  assert.equal(balances.get(701),500000);assert.equal(accounts.get('GAME_POOL:fruitwheel'),100000000);assert.equal(ledger.length,0);
});
test('a retry returns the committed round without charging twice; a changed payload is refused',async()=>{
  const result=await resolveSpin(701,bets(1000),'retry');
  assert.deepEqual(await resolveSpin(701,bets(1000),'retry'),result);assert.equal(transactionCount,1);
  await assert.rejects(resolveSpin(701,bets(0,1000),'retry'),{code:'IDEMPOTENCY_KEY_REUSED'});
});
test('the daily card totals add every player chips',async()=>{
  await resolveSpin(701,bets(1000,100,0),'a');
  balances.set(702,10000);await resolveSpin(702,bets(0,0,500),'b');
  __resetForTests();
  assert.deepEqual((await getTodayPot()).totals,{watermelon:1000,sevens:100,plum:500});
});
test('the weekly board resets at Saturday midnight in Cairo',async()=>{
  const { weekEndsIn } = await import('../fruitWheel.service');
  // Friday 2026-10-09 21:00 UTC = Saturday 00:00 Cairo (UTC+3): a whole week left.
  assert.equal(weekEndsIn(new Date('2026-10-09T21:00:00Z')),7*86_400_000);
  assert.equal(weekEndsIn(new Date('2026-10-09T20:00:00Z')),3_600_000);
});
