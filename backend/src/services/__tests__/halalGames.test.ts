// The halal games layer («العِوَض + الجائزة»), against the real engines with an
// in-memory Prisma. See docs/halal-games.md.
import { balances, ledger, xpAwards, settings } from './halalStubs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const B = require('node:path').resolve(__dirname, '..') + '/';
const halal = require(B + 'halalGames.service');
const plinko = require(B + 'plinko.service');
const crash = require(B + 'crash.service');
const crazy = require(B + 'crazyWheel.service');
const dice = require(B + 'skillDice.service');
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const io: any = { to: () => ({ emit: () => {} }), emit: () => {} };

function reset(budget = 1_000_000_000, cap = 100_000_000) {
  halal.__resetHalalForTests();
  ledger.length = 0;
  xpAwards.length = 0;
  settings.set('halal_games', JSON.stringify({ dailyPrizeBudget: budget, perUserDailyPrizeCap: cap, xpPerCoin: 1 }));
}

test('reservations respect the daily budget and the per-user cap, and free up on release', async () => {
  reset(10_000, 6_000);
  const a = await halal.reservePrize(1, 'x', 5_000);
  assert.equal(a.ok, true);
  const b = await halal.reservePrize(1, 'x', 2_000);
  assert.deepEqual([b.ok, b.code], [false, 'PRIZE_CAP_REACHED']);
  const c = await halal.reservePrize(2, 'x', 5_001);
  assert.deepEqual([c.ok, c.code], [false, 'PRIZE_FUND_EMPTY']);
  halal.releasePrize(a.token);
  assert.equal((await halal.reservePrize(2, 'x', 5_001)).ok, true);
});

test('a settled prize counts against today, from the ledger', async () => {
  reset(10_000, 10_000);
  const a = await halal.reservePrize(1, 'x', 8_000);
  halal.settlePrize(a.token, 1, 'x', 7_000, 'r1');
  await sleep(5);
  assert.equal(ledger.filter((r) => r.kind === 'prize').reduce((s, r) => s + r.amount, 0), 7_000);
  assert.equal((await halal.reservePrize(3, 'x', 3_001)).ok, false);
  // A fresh process hydrates today's spend from the ledger.
  halal.__resetHalalForTests();
  settings.set('halal_games', JSON.stringify({ dailyPrizeBudget: 10_000, perUserDailyPrizeCap: 10_000, xpPerCoin: 1 }));
  assert.equal((await halal.reservePrize(3, 'x', 3_001)).ok, false);
  assert.equal((await halal.reservePrize(3, 'x', 3_000)).ok, true);
});

test('plinko: stake buys XP, payout equals the shown multiplier, both are in the ledger', async () => {
  reset();
  balances.set(10, 100_000);
  const r = await plinko.dropBall(10, 'high', 16, 1_000);
  assert.equal(r.ok, true);
  const shown = plinko.getLayout().tables.high[16][r.drop.slot];
  assert.equal(r.drop.multiplier, shown);
  assert.equal(r.drop.payout, Math.floor(1_000 * shown));
  assert.equal(balances.get(10), 100_000 - 1_000 + r.drop.payout);
  assert.deepEqual(xpAwards, [{ userId: 10, xp: 1_000 }]);
  await sleep(5);
  assert.equal(ledger.find((l) => l.kind === 'stake')?.amount, 1_000);
  if (r.drop.payout > 0) assert.equal(ledger.find((l) => l.kind === 'prize')?.amount, r.drop.payout);
});

test('plinko: an empty prize fund refuses the drop before any coin moves', async () => {
  reset(1_000, 1_000);
  balances.set(11, 100_000);
  const r = await plinko.dropBall(11, 'high', 16, 1_000);
  assert.deepEqual([r.ok, r.code], [false, 'PRIZE_FUND_EMPTY']);
  assert.equal(balances.get(11), 100_000);
  assert.equal(xpAwards.length, 0);
});

test('plinko tables: every board at or under 80%, and printable as the app prints them', () => {
  for (const risk of ['low', 'medium', 'high']) {
    for (let rows = 8; rows <= 16; rows++) {
      const t = plinko.multipliersFor(risk, rows);
      assert.ok(plinko.tableRtp(t) <= plinko.TARGET_RTP + 1e-9, `${risk}/${rows}`);
      for (const m of t) {
        const printed = m >= 10 ? Number(m.toFixed(0)) : Number(m.toFixed(1));
        assert.equal(printed, m, `${risk}/${rows}: ${m} would print as ${printed}`);
      }
    }
  }
});

test('crash: cancel refunds with no XP; takeoff delivers XP; a loss releases the reservation', async () => {
  reset(1_000_000_000, 1_000_000);
  balances.set(20, 50_000);
  balances.set(21, 50_000);
  crash.startCrashEngine(io);
  // Over the cap: 20,000 × 100 (no auto) = 2,000,000 > 1,000,000.
  const big = await crash.placeCrashBet(20, 0, 20_000, null);
  assert.deepEqual([big.ok, big.code], [false, 'PRIZE_CAP_REACHED']);
  assert.equal(balances.get(20), 50_000);

  const a = await crash.placeCrashBet(20, 0, 1_000, 2);
  assert.equal(a.ok, true, JSON.stringify(a));
  const c = await crash.cancelCrashBet(20, 0);
  assert.equal(c.ok, true);
  assert.equal(balances.get(20), 50_000);

  const b = await crash.placeCrashBet(21, 0, 1_000, 1.01);
  assert.equal(b.ok, true);
  await sleep(5_600); // betting window closes → takeoff
  assert.deepEqual(xpAwards, [{ userId: 21, xp: 1_000 }], 'only the live bet bought XP');
  await sleep(1_500);
  crash.stopCrashEngine();
  const bal = balances.get(21)!;
  // Either it cashed out at 1.01 (prize 1,010) or the plane left at 1.00.
  assert.ok(bal === 49_000 || bal === 49_000 + 1_010, String(bal));
});

test('crash: the instant-bust rate is 1 in 5 now', () => {
  const crypto = require('crypto');
  let bust = 0;
  const N = 200_000;
  for (let i = 0; i < N; i++) {
    if (crash.crashPointFromHash(crypto.randomBytes(32).toString('hex')) === 1) bust++;
  }
  // 20% instant + the formula's own ~1% of sub-1.01 points.
  assert.ok(bust / N > 0.19 && bust / N < 0.23, String(bust / N));
});

test('crazy wheel: top slot is mostly ×1 and a win is capped', () => {
  let ones = 0;
  for (let i = 0; i < 50_000; i++) if (crazy.__crazyMath.rollTopSlot().multiplier === 1) ones++;
  assert.ok(ones / 50_000 > 0.9);
  assert.equal(crazy.getWheelLayout().maxWinMultiplier, crazy.MAX_WIN_MULTIPLIER);
});

test('skill dice: best play pays under the entry; joining delivers XP', async () => {
  reset();
  balances.set(30, 10_000);
  dice.startSkillDiceEngine?.(io) ?? dice.startDiceEngine?.(io);
  const j = await dice.joinRound(30, 1_000);
  assert.equal(j.ok, true, JSON.stringify(j));
  assert.ok(j.maxReward < 1_000, String(j.maxReward));
  assert.deepEqual(xpAwards, [{ userId: 30, xp: 1_000 }]);
  (dice.stopSkillDiceEngine ?? dice.stopDiceEngine)?.();
});
