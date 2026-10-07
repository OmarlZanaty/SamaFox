import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { computeSpin, scoreGrid, PAYLINES, RngStream, validBet, Symbol } from '../yummy.math';
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
    assert.equal(win.count,5);assert.equal(win.amount,3000);
  }
  const grid=board();grid[7]=grid[8]=grid[9]='cherry';assert.equal(scoreGrid(grid,100,1).length,0);
});
test('only active lines pay; wild picks best eligible prize once',()=>{
  const grid=board();grid[0]=grid[1]=grid[2]='diamond';assert.deepEqual(scoreGrid(grid,100,1),[]);
  grid[5]='wild';grid[6]='diamond';grid[7]='wild';
  const wins=scoreGrid(grid,100,1);assert.equal(wins.length,1);assert.equal(wins[0]!.amount,2000);
  grid[5]=grid[6]=grid[7]='wild';assert.equal(scoreGrid(grid,100,1)[0]!.amount,2500);
});
test('bonus and jackpot cannot substitute as wilds',()=>{
  const grid=board();grid[5]='diamond';grid[6]='bonus';grid[7]='diamond';assert.deepEqual(scoreGrid(grid,100,1),[]);
  grid[5]='jackpot';grid[6]='wild';grid[7]='jackpot';assert.deepEqual(scoreGrid(grid,100,1),[]);
  grid[6]='jackpot';assert.equal(scoreGrid(grid,100,1)[0]!.amount,100000);
});
test('three bonus symbols trigger one precomputed 2/5/10× total-bet award',()=>{
  const result=computeSpin({nextFloat:()=>.995},100,9);
  assert.equal(result.bonusTriggered,true);assert.equal(result.bonusMultiplier,10);
  assert.equal(result.totalBet,900);assert.equal(result.bonusPrize,9000);
  assert.equal(result.totalPrize,9000);
});
test('HMAC streams reproduce rounds exactly and change across nonces',()=>{
  const spin=computeSpin(new RngStream('a'.repeat(64),'client',0),100,9);
  assert.deepEqual(computeSpin(new RngStream('a'.repeat(64),'client',0),100,9),spin);
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
  assert.equal(verified.serverSeedHash,result.serverSeedHash);
  assert.throws(()=>verifySpin('bad','seed',0,100,9),{code:'BAD_VERIFY'});
});
