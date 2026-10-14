import { accounts, balances, settings, fakePrisma } from './halalStubs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const B = require('node:path').resolve(__dirname, '..') + '/';
const halal = require(B + 'halalGames.service');
const greedy = require(B + 'greedyCat.service');
const io: any = { to: () => ({ emit: () => {} }), emit: () => {} };
const config = require(B + 'gameConfig.service');

function prepare(userId: number, maxBet: number | null = 20_000) {
  halal.__resetHalalForTests();
  settings.set('game_config', JSON.stringify({ 'greedy-cat': { enabled: true, maxBet } }));
  config.invalidateGameConfigCache();
  accounts.set('GAME_POOL:greedy-cat', 100_000_000);
  balances.set(userId, 10_000_000);
  greedy.startGreedyCatEngine(io);
}

test('greedy: new table is balanced at 79.75% and the layout says so', () => {
  const layout = greedy.getLayout();
  assert.ok(Math.abs(layout.rtp - 1800 / 2257) < 1e-12);
  const byKey = Object.fromEntries(layout.symbols.map((s: any) => [s.key, s.multiplier]));
  assert.deepEqual(byKey, { chicken: 45, tomato: 4, goat: 15, pepper: 4, fish: 25, carrot: 4, shrimp: 8, corn: 4 });
});

test('greedy: a stake whose prize the pool cannot cover is refused before charging; clear frees it', async () => {
  halal.__resetHalalForTests();
  settings.set('game_config', JSON.stringify({ 'greedy-cat': { enabled: true, minBet: null, maxBet: 50_000, maxWinPerRound: 1_000_000, dailyMaxWinPerUser: 5_000_000 } }));
  require(B + 'gameConfig.service').invalidateGameConfigCache();
  // 45,000 of prize room in the pool.
  accounts.set('GAME_POOL:greedy-cat', 45_000);
  balances.set(40, 100_000);
  greedy.startGreedyCatEngine(io);

  const ok = await greedy.placeBet(40, 'chicken', 1_000); // reserves 45,000
  assert.equal(ok.ok, true, JSON.stringify(ok));
  const no = await greedy.placeBet(40, 'tomato', 100); // needs 400 more
  assert.deepEqual([no.ok, no.code], [false, 'PRIZE_POOL_LOW']);
  assert.equal(balances.get(40), 99_000);

  await greedy.clearBets(40);
  assert.equal(balances.get(40), 100_000);
  const again = await greedy.placeBet(40, 'chicken', 1_000);
  assert.equal(again.ok, true, 'clearing released the reservation');
  greedy.stopGreedyCatEngine();
});

test('greedy: dashboard maxBet caps each symbol, not the round total', async () => {
  halal.__resetHalalForTests();
  settings.set('game_config', JSON.stringify({ 'greedy-cat': { enabled: true, maxBet: 20_000 } }));
  require(B + 'gameConfig.service').invalidateGameConfigCache();
  accounts.set('GAME_POOL:greedy-cat', 2_000_000);
  balances.set(41, 100_000);
  greedy.startGreedyCatEngine(io);

  try {
    const first = await greedy.placeBet(41, 'chicken', 20_000);
    assert.equal(first.ok, true, JSON.stringify(first));
    const second = await greedy.placeBet(41, 'tomato', 20_000);
    assert.equal(second.ok, true, JSON.stringify(second));
    const over = await greedy.placeBet(41, 'chicken', 100);
    assert.deepEqual([over.ok, over.code], [false, 'BET_TOO_HIGH']);
    assert.match(over.message, /الخيار الواحد 20000 كوينز/);
    assert.equal(balances.get(41), 60_000);
  } finally {
    greedy.stopGreedyCatEngine();
  }
});

test('greedy: category request passes the guard and caps each split symbol', async (t) => {
  prepare(42);
  t.after(() => greedy.stopGreedyCatEngine());
  let next = false;
  await config.gameGuard('greedy-cat')({ body: { amount: 80_000 } }, {
    status: () => { assert.fail('category total must not be rejected by the guard'); },
  }, () => { next = true; });
  assert.equal(next, true);
  const category = await greedy.placeBet(42, 'salad', 80_000);
  assert.equal(category.ok, true, JSON.stringify(category));
  assert.deepEqual(Object.values(category.bets), [20_000, 20_000, 20_000, 20_000]);
  const before = balances.get(42);
  const over = await greedy.placeBet(42, 'tomato', 100);
  assert.equal(over.code, 'BET_TOO_HIGH');
  assert.equal(balances.get(42), before);
  const meat = await greedy.placeBet(42, 'chicken', 20_000);
  assert.equal(meat.ok, true, JSON.stringify(meat));
});

test('greedy: simultaneous requests share the per-symbol allowance', async (t) => {
  prepare(43);
  t.after(() => greedy.stopGreedyCatEngine());
  const results = await Promise.all([
    greedy.placeBet(43, 'chicken', 20_000),
    greedy.placeBet(43, 'chicken', 100),
    greedy.placeBet(43, 'tomato', 20_000),
  ]);
  assert.deepEqual(results.map(r => r.ok), [true, false, true]);
  assert.equal(results[1].code, 'BET_TOO_HIGH');
  const over = await greedy.placeBet(43, 'tomato', 100);
  assert.equal(over.code, 'BET_TOO_HIGH');
  assert.equal(balances.get(43), 9_960_000);
});

test('greedy: unset maxBet uses the per-symbol game limit', async (t) => {
  prepare(44, null);
  t.after(() => greedy.stopGreedyCatEngine());
  const limit = greedy.getLayout().maxBetPerSymbol;
  assert.ok(Number.isInteger(limit));
  assert.equal((await greedy.placeBet(44, 'tomato', limit)).ok, true);
  assert.equal((await greedy.placeBet(44, 'pepper', limit)).ok, true);
  assert.equal((await greedy.placeBet(44, 'tomato', 100)).code, 'BET_TOO_HIGH');
});

test('greedy: repeat accepts multiple full symbols and rejects an overflowing item before charging', async (t) => {
  const scheduled: Array<() => void> = [];
  const realTimeout = global.setTimeout;
  t.mock.method(global, 'setTimeout', ((callback: (...callbackArgs: any[]) => void, ms: number, ...args: any[]) => {
    if (ms >= 1000) { scheduled.push(callback); return undefined; }
    return realTimeout(() => callback(...args), ms);
  }) as any);
  prepare(45);
  t.after(() => greedy.stopGreedyCatEngine());
  await greedy.placeBet(45, 'chicken', 20_000);
  await greedy.placeBet(45, 'tomato', 20_000);
  scheduled.shift()!(); // close betting
  scheduled.shift()!(); // spin
  scheduled.shift()!(); // settle
  await new Promise<void>(resolve => setImmediate(resolve));
  scheduled.shift()!(); // next round
  const replay = await greedy.repeatBets(45);
  assert.equal(replay.ok, true, JSON.stringify(replay));
  assert.deepEqual(replay.bets, { chicken: 20_000, tomato: 20_000 });
  await greedy.clearBets(45);
  await greedy.placeBet(45, 'tomato', 100);
  const before = balances.get(45);
  const over = await greedy.repeatBets(45);
  assert.equal(over.code, 'BET_TOO_HIGH');
  assert.equal(balances.get(45), before, 'repeat preflights every symbol before taking coins');
});

test('greedy: failed reservation releases the pending symbol allowance', async (t) => {
  prepare(46);
  t.after(() => greedy.stopGreedyCatEngine());
  const lookup = fakePrisma.economyAccount.findUnique;
  fakePrisma.economyAccount.findUnique = async () => { throw new Error('pool read failed'); };
  try {
    await assert.rejects(greedy.placeBet(46, 'chicken', 20_000), /pool read failed/);
  } finally {
    fakePrisma.economyAccount.findUnique = lookup;
  }
  assert.equal((await greedy.placeBet(46, 'chicken', 20_000)).ok, true);
});
