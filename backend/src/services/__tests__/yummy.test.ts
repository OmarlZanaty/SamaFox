import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { computeSpin, scoreGrid, collapse, tumbleChain, expandWilds, PAYLINES, RngStream, validBet, Symbol, Rng,
  SYMBOLS, WEIGHTS, MAX_TUMBLES, MAX_MULTIPLIER, FREE_SPIN_AWARDS } from '../yummy.math';
import { invalidateGameConfigCache } from '../gameConfig.service';
import { __resetHalalForTests } from '../halalGames.service';
import { resolveSpin, verifySpin, rotateServerSeed } from '../yummy.service';

const rounds=new Map<string,any>();
let failHistory=false;
let transactionCount=0;
let transactionTail=Promise.resolve();
fakePrisma.yummyRound={
  findUnique:async ({where}:any)=>rounds.get(`${where.userId_requestId.userId}:${where.userId_requestId.requestId}`)??null,
  create:async ({data}:any)=> {
    if(failHistory) throw new Error('simulated history failure');
    const record={...data,id:`round-${rounds.size}`,createdAt:new Date()};
    rounds.set(`${data.userId}:${data.requestId}`,record);return record;
  },
  findMany:async ({where}:any)=>[...rounds.values()].filter(row=>row.userId===where.userId).reverse().slice(0,50),
};
fakePrisma.$transaction=async (callback:any)=> {
  let release!:()=>void;
  const previous=transactionTail;
  transactionTail=new Promise<void>(resolve=>{release=resolve;});
  await previous;
  transactionCount++;
  const saved={balances:new Map(balances),accounts:new Map(accounts),rounds:new Map(rounds),ledger:ledger.length,economy:economyLedger.length,xp:xpAwards.length};
  try {return await callback(fakePrisma);}
  catch(error) {
    balances.clear();for(const [key,value] of saved.balances) balances.set(key,value);
    accounts.clear();for(const [key,value] of saved.accounts) accounts.set(key,value);
    rounds.clear();for(const [key,value] of saved.rounds) rounds.set(key,value);
    ledger.length=saved.ledger;economyLedger.length=saved.economy;xpAwards.length=saved.xp;
    throw error;
  } finally {release();}
};

beforeEach(()=>{
  balances.clear();accounts.clear();rounds.clear();settings.clear();ledger.length=0;economyLedger.length=0;xpAwards.length=0;
  failHistory=false;transactionCount=0;
  accounts.set('GAME_POOL:yummy',100000000);accounts.set('PROGRAM',0);balances.set(701,50000);
  invalidateGameConfigCache();__resetHalalForTests();
});
const board=():Symbol[]=>Array(15).fill('bonus');

test('strict bet steps, line bounds, and numeric types',()=>{
  assert.equal(validBet(100,9),true);
  for(const [bet,lines] of [[0,9],[15,9],[100,0],[100,10],[100,1.5],['100',9],[Infinity,9]]) assert.equal(validBet(bet,lines),false);
});
test('horizontal and all nine specified line shapes pay from the left',()=>{
  for(let line=0;line<9;line++) {
    const grid=board();PAYLINES[line]!.forEach((row,reel)=>{grid[row*5+reel]='cherry';});
    const win=scoreGrid(grid,100,9).find(win=>win.line===line)!;
    assert.equal(win.count,5);assert.equal(win.amount,6000);
  }
  const grid=board();grid[7]=grid[8]=grid[9]='cherry';assert.equal(scoreGrid(grid,100,1).length,0);
});
test('only active lines pay; wild picks best eligible prize once',()=>{
  const grid=board();grid[0]=grid[1]=grid[2]='diamond';assert.deepEqual(scoreGrid(grid,100,1),[]);
  grid[5]='wild';grid[6]='diamond';grid[7]='wild';
  const wins=scoreGrid(grid,100,1);assert.equal(wins.length,1);assert.equal(wins[0]!.amount,4000);
  grid[5]=grid[6]=grid[7]='wild';assert.equal(scoreGrid(grid,100,1)[0]!.amount,5000);
});
test('bonus and jackpot cannot substitute as wilds',()=>{
  const grid=board();grid[5]='diamond';grid[6]='bonus';grid[7]='diamond';assert.deepEqual(scoreGrid(grid,100,1),[]);
  grid[5]='jackpot';grid[6]='wild';grid[7]='jackpot';assert.deepEqual(scoreGrid(grid,100,1),[]);
  grid[6]='jackpot';assert.equal(scoreGrid(grid,100,1)[0]!.amount,100000);
});
// A float that draws [symbol] from the weighted strip.
const pick=(symbol:Symbol)=>{
  const total=WEIGHTS.reduce((a,b)=>a+b,0);let before=0;
  for(let i=0;i<SYMBOLS.length;i++){if(SYMBOLS[i]===symbol) return (before+WEIGHTS[i]!/2)/total;before+=WEIGHTS[i]!;}
  throw new Error(symbol);
};
// Plays [script] symbols in draw order, then [rest] forever.
const scripted=(script:Symbol[],rest:Symbol='bonus'):Rng=>{let i=0;return {nextFloat:()=>pick(script[i++]??rest)};};
const constant=(symbol:Symbol)=>scripted([],symbol);

test('collapse drops survivors down each reel and refills from the top',()=>{
  const grid=board();grid[0]='cherry';grid[5]='lemon';grid[10]='orange';grid[4]='diamond';
  const next=collapse(grid,[5,10,14],constant('grapes'));
  assert.deepEqual([next[0],next[5],next[10]],['grapes','grapes','cherry']);
  assert.deepEqual([next[4],next[9],next[14]],['grapes','diamond','bonus']);
  assert.equal(next[1],'bonus');
});
test('tumbles pay ×1, ×2, ×3, then ×5 and stop after MAX_TUMBLES',()=>{
  const grid=board();for(const cell of [5,6,7,8,9]) grid[cell]='cherry';
  // Every refill is cherry, so each collapse completes the top row again.
  const steps=tumbleChain(constant('cherry'),grid,100,9,1);
  assert.equal(steps.length,MAX_TUMBLES);
  assert.deepEqual(steps.slice(0,5).map(t=>t.multiplier),[1,2,3,5,5]);
  assert.equal(steps[0]!.prize,6000);assert.equal(steps[1]!.prize,12000);
  assert.deepEqual(steps[0]!.removed,[5,6,7,8,9]);
  assert.deepEqual(steps[steps.length-1]!.removed,[]);
});
test('a chain stops at the first board without a win',()=>{
  const grid=board();for(const cell of [5,6,7]) grid[cell]='lemon';
  const steps=tumbleChain(constant('bonus'),grid,100,9,1);
  assert.equal(steps.length,2);assert.equal(steps[0]!.prize,1000);assert.equal(steps[1]!.prize,0);
  assert.deepEqual(steps[1]!.removed,[]);
});
test('crowns pay a fixed 1000× line bet that no multiplier touches',()=>{
  const steps=tumbleChain(constant('jackpot'),Array(15).fill('jackpot'),100,1,5);
  assert.ok(steps.length>2);
  for(const step of steps) assert.equal(step.prize,100000);
  assert.equal(steps[1]!.multiplier,10);
});
test('3/4/5+ BONUS award 8/10/12 free spins at ×2/×3/×5',()=>{
  for(const [count,award] of [[3,FREE_SPIN_AWARDS[3]],[4,FREE_SPIN_AWARDS[4]],[9,FREE_SPIN_AWARDS[5]]] as const) {
    const opening:Symbol[]=Array.from({length:15},(_,i)=>i%5===0?'strawberry':i%5===1?'cherry':'lemon');
    for(let i=0;i<count;i++) opening[[2,3,4,7,8,9,12,13,14][i]!]='bonus';
    const result=computeSpin(scripted(opening),100,9);
    assert.equal(result.bonusTriggered,true);assert.equal(result.freeSpins!.trigger,count);
    assert.equal(result.freeSpins!.count,award!.spins);assert.equal(result.freeSpins!.spins.length,award!.spins);
    assert.equal(result.freeSpins!.multiplier,award!.multiplier);
  }
  const quiet=computeSpin(scripted(['bonus','bonus','cherry','lemon','orange'],'strawberry'),100,9);
  assert.equal(quiet.bonusTriggered,false);assert.equal(quiet.freeSpins,null);
});
test('free-spin WILD on reels 2–4 expands to the whole reel; edge reels never do',()=>{
  const b=board();b[2]='wild';b[4]='wild';b[10]='wild';
  assert.deepEqual(expandWilds(b),[2]);
  assert.deepEqual([b[2],b[7],b[12],b[9],b[14],b[5]],['wild','wild','wild','bonus','bonus','bonus']);
  // Opening: strawberry/cherry reels and BONUS elsewhere (9 BONUS → 12 spins at ×5).
  const opening:Symbol[]=Array.from({length:15},(_,i)=>i%5===0?'strawberry':i%5===1?'cherry':'bonus');
  const first:Symbol[]=Array.from({length:15},(_,i)=>i%5<2?'cherry':'bonus');first[2]='wild';
  const result=computeSpin(scripted([...opening,...first]),100,9);
  const spin=result.freeSpins!.spins[0]!;
  assert.deepEqual(spin.expandedReels,[2]);
  assert.deepEqual([2,7,12].map(c=>spin.tumbles[0]!.grid[c]),['wild','wild','wild']);
  assert.equal(spin.tumbles[0]!.wins.length,9);
  assert.equal(spin.tumbles[0]!.prize,9*600*5);
  assert.equal(result.basePrize,0);assert.equal(result.totalPrize,result.freeSpins!.prize);
});
test('a round never pays more than MAX_MULTIPLIER × total bet',()=>{
  const result=computeSpin(constant('wild'),100,9);
  assert.equal(result.roundCapHit,true);assert.equal(result.totalPrize,MAX_MULTIPLIER*900);
  assert.equal(result.tumbles.length,MAX_TUMBLES);
});
test('HMAC streams reproduce rounds exactly and change across nonces',()=>{
  const spin=computeSpin(new RngStream('a'.repeat(64),'client',0),100,9);
  assert.deepEqual(computeSpin(new RngStream('a'.repeat(64),'client',0),100,9),spin);
  // Free spins and tumbles replay too: find a nonce that triggers them.
  let nonce=0,bonus;
  while(!(bonus=computeSpin(new RngStream('b'.repeat(64),'client',nonce),100,9)).bonusTriggered) nonce++;
  assert.deepEqual(computeSpin(new RngStream('b'.repeat(64),'client',nonce),100,9),bonus);
  assert.equal(bonus.mathVersion,2);
  assert.notDeepEqual(computeSpin(new RngStream('a'.repeat(64),'client',1),100,9).grid,spin.grid);
});
test('one transaction debits stake, credits prize, splits pool, awards XP and persists history',async()=>{
  const result:any=await resolveSpin(701,100,9,'single');
  assert.equal(transactionCount,1);
  assert.equal(result.balance,50000-900+result.spin.totalPrize);
  assert.equal(accounts.get('PROGRAM'),225);
  assert.equal(accounts.get('GAME_POOL:yummy'),100000000+675-result.spin.totalPrize);
  assert.equal(xpAwards.length,1);assert.equal(rounds.size,1);assert.equal(ledger.length,2);
});
test('insufficient balance cannot debit, write history or credit prizes',async()=>{
  balances.set(701,899);
  await assert.rejects(resolveSpin(701,100,9,'poor'),{code:'INSUFFICIENT'});
  assert.equal(balances.get(701),899);assert.equal(rounds.size,0);assert.equal(ledger.length,0);
});
test('history failure rolls back every coin movement and XP',async()=>{
  failHistory=true;
  await assert.rejects(resolveSpin(701,100,9,'rollback'),/history failure/);
  assert.equal(balances.get(701),50000);assert.equal(accounts.get('PROGRAM'),0);
  assert.equal(accounts.get('GAME_POOL:yummy'),100000000);assert.equal(ledger.length,0);assert.equal(xpAwards.length,0);
});
test('retry returns the committed round without charging twice; changed payload refused',async()=>{
  const result=await resolveSpin(701,100,9,'retry');
  const replay=await resolveSpin(701,100,9,'retry');
  assert.deepEqual(replay,result);assert.equal(transactionCount,1);
  await assert.rejects(resolveSpin(701,200,9,'retry'),{code:'IDEMPOTENCY_KEY_REUSED'});
});
test('concurrent spins cannot overdraw the user',async()=>{
  balances.set(701,900);
  const results=await Promise.allSettled([resolveSpin(701,100,9,'race1'),resolveSpin(701,100,9,'race2')]);
  assert.ok(results.some(result=>result.status==='fulfilled'));
  assert.ok(balances.get(701)!>=0);
  assert.equal(rounds.size,results.filter(result=>result.status==='fulfilled').length);
});
test('empty pool, disabled game and total-bet admin limits reject before charging',async()=>{
  accounts.set('GAME_POOL:yummy',0);
  await assert.rejects(resolveSpin(701,100,9,'pool'),{code:'PRIZE_POOL_LOW'});
  settings.set('game_config',JSON.stringify({yummy:{enabled:false}}));invalidateGameConfigCache();
  await assert.rejects(resolveSpin(701,100,9,'off'),{code:'GAME_DISABLED'});
  settings.set('game_config',JSON.stringify({yummy:{maxBet:800}}));invalidateGameConfigCache();
  await assert.rejects(resolveSpin(701,100,9,'limit'),{code:'BET_TOO_HIGH'});
  assert.equal(balances.get(701),50000);
});
test('revealed seed verifies committed grid and uncapped prize',async()=>{
  const result:any=await resolveSpin(701,100,9,'fair');
  const rotated=await rotateServerSeed(701);
  const verified=verifySpin(rotated.revealed.serverSeed,result.clientSeed,result.nonce,100,9);
  assert.deepEqual(verified.grid,result.spin.grid);assert.equal(verified.totalPrize,result.spin.requestedPrize);
  assert.deepEqual(verified.tumbles,result.spin.tumbles);assert.deepEqual(verified.freeSpins,result.spin.freeSpins);
  assert.equal(verified.serverSeedHash,result.serverSeedHash);
  assert.throws(()=>verifySpin('bad','seed',0,100,9),{code:'BAD_VERIFY'});
});
