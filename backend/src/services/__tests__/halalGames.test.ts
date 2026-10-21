// The game economy layer (2026-09-26): stakes split 30% program / 70% the
// game's pool, prizes paid only from that pool, per-game caps. Against the real
// engines with an in-memory Prisma. The real-database version of these checks
// is tests/e2e/economy.e2e.ts.
import { accounts, balances, ledger, xpAwards, settings } from './halalStubs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const B = require('node:path').resolve(__dirname, '..') + '/';
const halal = require(B + 'halalGames.service');
const gameConfig = require(B + 'gameConfig.service');
const plinko = require(B + 'plinko.service');
const crash = require(B + 'crash.service');
const crazy = require(B + 'crazyWheel.service');
const dice = require(B + 'skillDice.service');
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const io: any = { to: () => ({ emit: () => {} }), emit: () => {} };

function reset(pools: Record<string, number> = {}, cfg: Record<string, any> = {}) {
  halal.__resetHalalForTests();
  ledger.length = 0;
  xpAwards.length = 0;
  accounts.clear();
  accounts.set('PROGRAM', 0);
  for (const [g, v] of Object.entries(pools)) accounts.set(`GAME_POOL:${g}`, v);
  settings.set('game_config', JSON.stringify(cfg));
  gameConfig.invalidateGameConfigCache();
}

test('reservations are limited by the game pool and by the daily cap, and free up on release', async () => {
  reset({ x: 10_000 }, { x: { dailyMaxWinPerUser: 6_000, maxWinPerRound: 1_000_000 } });
  const a = await halal.reservePrize(1, 'x', 5_000);
  assert.equal(a.ok, true);
  const b = await halal.reservePrize(1, 'x', 2_000);
  assert.deepEqual([b.ok, b.code], [false, 'DAILY_WIN_CAP']);
  const c = await halal.reservePrize(2, 'x', 5_001);
  assert.deepEqual([c.ok, c.code], [false, 'PRIZE_POOL_LOW']);
  halal.releasePrize(a.token);
  assert.equal((await halal.reservePrize(2, 'x', 5_001)).ok, true);
});

test('payPrize: pool debited and player credited together; capped by round max and payout ratio', async () => {
  reset({ x: 100_000 }, { x: { maxWinPerRound: 700, maxPayoutRatio: 5 } });
  balances.set(5, 0);
  const t = await halal.reservePrize(5, 'x', 5_000, 100);
  assert.equal(t.cap, 500, 'min(5000, round 700, 100 × 5)');
  const paid = await halal.payPrize(t.token, 5, 'x', 5_000, 'r1', 100);
  assert.deepEqual([paid.paid, paid.requested, paid.capped], [500, 5_000, true]);
  assert.equal(balances.get(5), 500);
  assert.equal(accounts.get('GAME_POOL:x'), 100_000 - 500);
  const row = ledger.find((l) => l.kind === 'prize');
  assert.deepEqual([row.amount, row.requested, row.capped], [500, 5_000, true]);
});

test('payPrize never mints: an empty pool pays nothing', async () => {
  reset({}, {});
  balances.set(6, 0);
  const paid = await halal.payPrize(null, 6, 'x', 1_000, 'r');
  assert.equal(paid.paid, 0);
  assert.equal(balances.get(6), 0);
});

test('plinko: stake splits 30/70, payout equals the shown multiplier and comes from the pool', async () => {
  reset({ plinko: 10_000_000 });
  balances.set(10, 100_000);
  const r = await plinko.dropBall(10, 'high', 16, 1_000);
  assert.equal(r.ok, true, JSON.stringify(r));
  const shown = plinko.getLayout().tables.high[16][r.drop.slot];
  assert.equal(r.drop.multiplier, shown);
  assert.equal(r.drop.payout, Math.floor(1_000 * shown));
  assert.equal(balances.get(10), 100_000 - 1_000 + r.drop.payout);
  assert.deepEqual(xpAwards, [{ userId: 10, xp: 1_000 }]);
  assert.equal(accounts.get('PROGRAM'), 300);
  assert.equal(accounts.get('GAME_POOL:plinko'), 10_000_000 + 700 - r.drop.payout);
  const stake = ledger.find((l) => l.kind === 'stake');
  assert.deepEqual([stake.amount, stake.programShare, stake.poolShare], [1_000, 300, 700]);
});

test('payPrize: null round and daily caps pay a large prize in full when the pool holds it', async () => {
  reset({ x: 3_000_000 }, { x: { maxWinPerRound: null, dailyMaxWinPerUser: null, maxPayoutRatio: null } });
  balances.set(7, 0);
  const t = await halal.reservePrize(7, 'x', 2_000_000);
  assert.equal(t.ok, true, JSON.stringify(t));
  const paid = await halal.payPrize(t.token, 7, 'x', 2_000_000, 'r2');
  assert.deepEqual([paid.paid, paid.requested, paid.capped], [2_000_000, 2_000_000, false]);
  assert.equal(balances.get(7), 2_000_000);
  assert.equal(accounts.get('GAME_POOL:x'), 1_000_000);
});

test('reservePrize refuses a bet whose possible prize exceeds the pool', async () => {
  reset({ x: 1_999_999 }, { x: { maxWinPerRound: null, dailyMaxWinPerUser: null, maxPayoutRatio: null } });
  balances.set(8, 0);
  const t = await halal.reservePrize(8, 'x', 2_000_000);
  assert.deepEqual([t.ok, t.code], [false, 'PRIZE_POOL_LOW']);
  assert.equal(balances.get(8), 0);
  assert.equal(ledger.length, 0);
});

test('plinko: an empty prize pool refuses the drop before any coin moves', async () => {
  reset({});
  balances.set(11, 100_000);
  const r = await plinko.dropBall(11, 'high', 16, 1_000);
  assert.deepEqual([r.ok, r.code], [false, 'PRIZE_POOL_LOW']);
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

test('crash: over the daily cap is refused before charging; cancel refunds with no XP; takeoff delivers XP', async () => {
  reset({ crash: 1_000_000_000 }, { crash: { dailyMaxWinPerUser: 1_000_000, maxWinPerRound: 1_000_000 } });
  balances.set(20, 50_000);
  balances.set(21, 50_000);
  crash.startCrashEngine(io);
  // 20,000 × 100 (no auto) is cut to the 1,000,000 round max; the daily cap holds exactly that.
  const big = await crash.placeCrashBet(20, 0, 20_000, null);
  assert.equal(big.ok, true, JSON.stringify(big));
  assert.equal(big.maxWin, 1_000_000);
  const second = await crash.placeCrashBet(20, 1, 100, null);
  assert.deepEqual([second.ok, second.code], [false, 'DAILY_WIN_CAP']);
  await crash.cancelCrashBet(20, 0);
  assert.equal(balances.get(20), 50_000);

  const b = await crash.placeCrashBet(21, 0, 1_000, 1.01);
  assert.equal(b.ok, true);
  await sleep(5_600); // betting window closes → takeoff
  assert.deepEqual(xpAwards, [{ userId: 21, xp: 1_000 }], 'only the live bet bought XP');
  await sleep(1_500);
  crash.stopCrashEngine();
  const bal = balances.get(21)!;
  assert.ok(bal === 49_000 || bal === 49_000 + 1_010, String(bal));
});

test('crash: the instant-bust rate is 1 in 5 now', () => {
  const crypto = require('crypto');
  let bust = 0;
  const N = 200_000;
  for (let i = 0; i < N; i++) {
    if (crash.crashPointFromHash(crypto.randomBytes(32).toString('hex')) === 1) bust++;
  }
  assert.ok(bust / N > 0.19 && bust / N < 0.23, String(bust / N));
});

test('crazy wheel: top slot is mostly ×1 and a win is capped', () => {
  let ones = 0;
  for (let i = 0; i < 50_000; i++) if (crazy.__crazyMath.rollTopSlot().multiplier === 1) ones++;
  assert.ok(ones / 50_000 > 0.9);
  assert.equal(crazy.getWheelLayout().maxWinMultiplier, crazy.MAX_WIN_MULTIPLIER);
});

test('skill dice: best play pays under the entry; joining delivers XP and funds the pool', async () => {
  reset({ dice: 1_000_000 });
  balances.set(30, 10_000);
  dice.startSkillDiceEngine?.(io) ?? dice.startDiceEngine?.(io);
  const j = await dice.joinRound(30, 1_000);
  assert.equal(j.ok, true, JSON.stringify(j));
  assert.ok(j.maxReward < 1_000, String(j.maxReward));
  assert.deepEqual(xpAwards, [{ userId: 30, xp: 1_000 }]);
  assert.equal(accounts.get('GAME_POOL:dice'), 1_000_000 + 700);
  (dice.stopSkillDiceEngine ?? dice.stopDiceEngine)?.();
});

test('game settings: nonsense is refused (RTP over the pool share, round cap over the daily cap)', () => {
  const base = { enabled: true, minBet: null, maxBet: null, maxWinPerRound: 100, dailyMaxWinPerUser: 1_000, maxPayoutRatio: null, rtpTargetBp: 7000, programShareBp: 3000 };
  assert.equal(gameConfig.validateGameSettings('x', base), null);
  assert.ok(gameConfig.validateGameSettings('x', { ...base, rtpTargetBp: 7001 }));
  assert.ok(gameConfig.validateGameSettings('x', { ...base, maxWinPerRound: 5_000 }));
  assert.ok(gameConfig.validateGameSettings('x', { ...base, minBet: 10, maxBet: 5 }));
  assert.ok(gameConfig.validateGameSettings('x', { ...base, maxPayoutRatio: 0.5 }));
});

test('game settings defaults are 30% program with no win caps', async () => {
  reset({}, {});
  const s = await gameConfig.getGameSettings('plinko');
  assert.deepEqual(
    [s.programShareBp, s.rtpTargetBp, s.maxWinPerRound, s.dailyMaxWinPerUser],
    [3000, 7000, null, null],
  );
  assert.equal(gameConfig.naturalMaxMultiplier('fruitwheel'), 8);
});

test('game settings persist cleared caps, including an old payout-ratio override', async () => {
  reset({}, { carwheel: { maxWinPerRound: 1_000_000, dailyMaxWinPerUser: 5_000_000, maxPayoutRatio: 3 } });
  await gameConfig.setGameSettings('carwheel', {
    maxWinPerRound: null, dailyMaxWinPerUser: null, maxPayoutRatio: null,
  });
  const saved = await gameConfig.getGameSettings('carwheel');
  assert.deepEqual([saved.maxWinPerRound, saved.dailyMaxWinPerUser, saved.maxPayoutRatio], [null, null, null]);
  assert.deepEqual(JSON.parse(settings.get('game_config')!).carwheel.maxWinPerRound, null);
});

test('game guard retains minimum, disabled and other games maximum checks', async () => {
  reset({}, {
    'greedy-cat': { minBet: 100, maxBet: 20_000 },
    carwheel: { maxBet: 20_000 },
    plinko: { enabled: false },
  });
  assert.equal((await gameConfig.checkGamePlayable('greedy-cat', 50)).code, 'BET_TOO_LOW');
  assert.equal((await gameConfig.checkGamePlayable('carwheel', 80_000)).code, 'BET_TOO_HIGH');
  assert.equal((await gameConfig.checkGamePlayable('plinko', 100)).code, 'GAME_DISABLED');
});
