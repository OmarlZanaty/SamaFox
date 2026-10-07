import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import {computeSpin,scoreGrid,PAYLINES,RngStream,validBet,Symbol,MAX_MULTIPLIER,SYMBOLS,weights} from '../fruitJackpot.math';
import { invalidateGameConfigCache } from '../gameConfig.service';
import { __resetHalalForTests } from '../halalGames.service';
import { resolveSpin, verifySpin, rotateServerSeed } from '../fruitJackpot.service';

const rounds=new Map<string,any>();
let failHistory=false;
let transactionCount=0;
let transactionTail=Promise.resolve();
fakePrisma.fruitJackpotRound={
  findUnique:async ({where}:any)=>rounds.get(`${where.userId_requestId.userId}:${where.userId_requestId.requestId}`)??null,
  count:async ({where}:any)=>[...rounds.values()].filter(r=>r.userId===where.userId).length,
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
  accounts.set('GAME_POOL:fruit-jackpot',100000000);accounts.set('PROGRAM',0);balances.set(701,50000);
  invalidateGameConfigCache();__resetHalalForTests();
});

test('all eight lines multiply centre and horizontal rows',()=>{
 for(let line=0;line<8;line++) {
  const grid:Symbol[]=Array(9).fill('multiplier');for(const c of PAYLINES[line]!) grid[c]='cherry';
  assert.equal(scoreGrid(grid,100,3,[2,2,2]).find(w=>w.line===line)!.amount,4000*3*(line<3?2:1));
 }
 assert.equal(validBet(100,8),true);assert.equal(validBet(100,9),false);assert.equal(validBet('100'),false);
});
// Scripted stream in draw order: 9 cells, centre tile, 3 row badges, bonus pick.
const cell=(symbol:Symbol)=>{
  const w=weights(),total=w.reduce((a,b)=>a+b,0),i=SYMBOLS.indexOf(symbol);
  return (w.slice(0,i).reduce((a,b)=>a+b,0)+w[i]!/2)/total;
};
const scripted=(board:Symbol[],centre:number,rows:number[],pick:number)=>{
  const values=[...board.map(cell),centre,...rows,pick];let i=0;
  return {nextFloat:()=>values[i++] ?? 0};
};
// No line on its own: rows, columns and diagonals all mixed.
const mixed:Symbol[]=['lemon','kiwi','plum','banana','raspberry','strawberry','kiwi','plum','lemon'];
test('cells are drawn independently from the weighted strip',()=>{
  const spin=computeSpin(scripted(mixed,0,[.5,.5,.5],0),100);
  assert.deepEqual(spin.grid,mixed);assert.equal(spin.centreMultiplier,1);assert.deepEqual(spin.rowMultipliers,[1,1,1]);
  assert.equal(spin.totalPrize,0);assert.equal(spin.bonusTriggered,false);assert.equal(spin.jackpotTriggered,false);
});
test('a line pays table × bet × centre tile × its row badge',()=>{
  const board:Symbol[]=['lemon','lemon','lemon',...mixed.slice(3)];
  assert.equal(computeSpin(scripted(board,0,[.5,.5,.5],0),100).totalPrize,500);
  const boosted=computeSpin(scripted(board,.95,[0,.5,.5],0),100); // centre 2, top row x2
  assert.equal(boosted.centreMultiplier,2);assert.deepEqual(boosted.rowMultipliers,[2,1,1]);assert.equal(boosted.totalPrize,2000);
});
test('three tokens across the middle row open a precommitted bonus; tokens never pay lines',()=>{
  const board:Symbol[]=['lemon','kiwi','plum','multiplier','multiplier','multiplier','kiwi','plum','lemon'];
  const spin=computeSpin(scripted(board,0,[.5,.5,.5],.7),100);
  assert.equal(spin.bonusTriggered,true);assert.equal(spin.bonusMultiplier,5);assert.equal(spin.bonusPrize,500);
  assert.equal(spin.wins.length,0);assert.equal(spin.totalPrize,500);
  const scattered:Symbol[]=['multiplier','kiwi','multiplier','banana','raspberry','strawberry','multiplier','plum','lemon'];
  assert.equal(computeSpin(scripted(scattered,0,[.5,.5,.5],.7),100).bonusTriggered,false);
});
test('a cherry line with the centre tile on 9 pays the fixed jackpot instead',()=>{
  const board:Symbol[]=['cherry','cherry','cherry',...mixed.slice(3)];
  const spin=computeSpin(scripted(board,.9995,[.5,.5,.5],0),100);
  assert.equal(spin.centreMultiplier,9);assert.equal(spin.jackpotTriggered,true);assert.equal(spin.totalPrize,100000);
  const plain=computeSpin(scripted(board,0,[.5,.5,.5],0),100);
  assert.equal(plain.jackpotTriggered,false);assert.equal(plain.totalPrize,4000);
});
test('round cap and deterministic replay',()=>{
  const all:Symbol[]=Array(9).fill('cherry');
  const capped=computeSpin(scripted(all,.995,[0,0,0],0),100); // centre 5, every row x2: far above the cap
  assert.equal(capped.roundCapHit,true);assert.equal(capped.totalPrize,100*MAX_MULTIPLIER);
  assert.deepEqual(computeSpin(new RngStream('a','b',1),100),computeSpin(new RngStream('a','b',1),100));
});
test('one transaction debits stake, credits prize, splits pool, awards XP and persists history',async()=>{
  const result:any=await resolveSpin(701,100,8,'single');
  assert.equal(transactionCount,1);
  assert.equal(result.balance,50000-100+result.spin.totalPrize);
  assert.equal(accounts.get('PROGRAM'),25);
  assert.equal(accounts.get('GAME_POOL:fruit-jackpot'),100000000+75-result.spin.totalPrize);
  assert.equal(xpAwards.length,1);assert.equal(rounds.size,1);assert.equal(ledger.length,2);
});
test('insufficient balance cannot debit, write history or credit prizes',async()=>{
  balances.set(701,99);
  await assert.rejects(resolveSpin(701,100,8,'poor'),{code:'INSUFFICIENT'});
  assert.equal(balances.get(701),99);assert.equal(rounds.size,0);assert.equal(ledger.length,0);
});
test('history failure rolls back every coin movement and XP',async()=>{
  failHistory=true;
  await assert.rejects(resolveSpin(701,100,8,'rollback'),/history failure/);
  assert.equal(balances.get(701),50000);assert.equal(accounts.get('PROGRAM'),0);
  assert.equal(accounts.get('GAME_POOL:fruit-jackpot'),100000000);assert.equal(ledger.length,0);assert.equal(xpAwards.length,0);
});
test('retry returns the committed round without charging twice; changed payload refused',async()=>{
  const result=await resolveSpin(701,100,8,'retry');
  const replay=await resolveSpin(701,100,8,'retry');
  assert.deepEqual(replay,result);assert.equal(transactionCount,1);
  await assert.rejects(resolveSpin(701,1000,8,'retry'),{code:'IDEMPOTENCY_KEY_REUSED'});
});
test('concurrent spins cannot overdraw the user',async()=>{
  balances.set(701,900);
  const results=await Promise.allSettled([resolveSpin(701,100,8,'race1'),resolveSpin(701,100,8,'race2')]);
  assert.ok(results.some(result=>result.status==='fulfilled'));
  assert.ok(balances.get(701)!>=0);
  assert.equal(rounds.size,results.filter(result=>result.status==='fulfilled').length);
});
test('empty pool, disabled game and total-bet admin limits reject before charging',async()=>{
  accounts.set('GAME_POOL:fruit-jackpot',0);
  await assert.rejects(resolveSpin(701,100,8,'pool'),{code:'PRIZE_POOL_LOW'});
  settings.set('game_config',JSON.stringify({'fruit-jackpot':{enabled:false}}));invalidateGameConfigCache();
  await assert.rejects(resolveSpin(701,100,8,'off'),{code:'GAME_DISABLED'});
  settings.set('game_config',JSON.stringify({'fruit-jackpot':{maxBet:80}}));invalidateGameConfigCache();
  await assert.rejects(resolveSpin(701,100,8,'limit'),{code:'BET_TOO_HIGH'});
  assert.equal(balances.get(701),50000);
});
test('revealed seed verifies committed grid and uncapped prize',async()=>{
  const result:any=await resolveSpin(701,100,8,'fair');
  const rotated=await rotateServerSeed(701);
  const verified=verifySpin(rotated.revealed.serverSeed,result.clientSeed,result.nonce,100,8);
  assert.deepEqual(verified.grid,result.spin.grid);assert.equal(verified.totalPrize,result.spin.requestedPrize);
  assert.deepEqual(verified.centreMultiplier,result.spin.centreMultiplier);assert.deepEqual(verified.rowMultipliers,result.spin.rowMultipliers);
  assert.equal(verified.serverSeedHash,result.serverSeedHash);
  assert.throws(()=>verifySpin('bad','seed',0,100,8),{code:'BAD_VERIFY'});
});
