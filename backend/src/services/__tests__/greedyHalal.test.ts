import { balances, settings } from './halalStubs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const B = require('node:path').resolve(__dirname, '..') + '/';
const halal = require(B + 'halalGames.service');
const greedy = require(B + 'greedyCat.service');
const io: any = { to: () => ({ emit: () => {} }), emit: () => {} };

test('greedy: new table is balanced at 79.75% and the layout says so', () => {
  const layout = greedy.getLayout();
  assert.ok(Math.abs(layout.rtp - 1800 / 2257) < 1e-12);
  const byKey = Object.fromEntries(layout.symbols.map((s: any) => [s.key, s.multiplier]));
  assert.deepEqual(byKey, { chicken: 45, tomato: 4, goat: 15, pepper: 4, fish: 25, carrot: 4, shrimp: 8, corn: 4 });
});

test('greedy: a stake whose prize the fund cannot cover is refused before charging; clear frees the fund', async () => {
  halal.__resetHalalForTests();
  settings.set('game_config', JSON.stringify({ 'greedy-cat': { enabled: true, minBet: null, maxBet: 50_000 } }));
  // 45,000 of prize room for this player.
  settings.set('halal_games', JSON.stringify({ dailyPrizeBudget: 1e9, perUserDailyPrizeCap: 45_000, xpPerCoin: 1 }));
  balances.set(40, 100_000);
  greedy.startGreedyCatEngine(io);

  const ok = await greedy.placeBet(40, 'chicken', 1_000); // reserves 45,000
  assert.equal(ok.ok, true, JSON.stringify(ok));
  const no = await greedy.placeBet(40, 'tomato', 100); // needs 400 more
  assert.deepEqual([no.ok, no.code], [false, 'PRIZE_CAP_REACHED']);
  assert.equal(balances.get(40), 99_000);

  await greedy.clearBets(40);
  assert.equal(balances.get(40), 100_000);
  const again = await greedy.placeBet(40, 'chicken', 1_000);
  assert.equal(again.ok, true, 'clearing released the reservation');
  greedy.stopGreedyCatEngine();
});
