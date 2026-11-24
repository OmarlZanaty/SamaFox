import test from 'node:test';
import assert from 'node:assert/strict';
import { advanceTable, drawTable, TABLE_TIERS, validTable } from '../luckyTable';
import { rollHash, verifyRoll } from '../lucky.service';

const thresholds = [8,15,150,375,750,1500,750,1875,3750,7500,1500,3750,7500,15000];
test('client ladder resets exactly at the threshold and wraps after all 14 tiers', () => {
  assert.equal(advanceTable(thresholds, 0, 6, 1).multiplier, 0);
  assert.deepEqual(advanceTable(thresholds, 0, 7, 1), { tier: 1, counter: 0, multiplier: 5, fired: [0] });
  assert.deepEqual(advanceTable(thresholds, 13, 14999, 1), { tier: 0, counter: 0, multiplier: 10000, fired: [13] });
  assert.deepEqual(TABLE_TIERS.slice(0, 6), [[5,0],[10,0],[0,100],[0,250],[0,500],[0,1000]]);
});
test('quantity times mics counts throws and carries excess through sequential tiers', () => {
  assert.deepEqual(advanceTable(thresholds, 0, 0, 3 * 10), { tier: 2, counter: 7, multiplier: 15, fired: [0,1] });
  assert.equal(advanceTable(thresholds, 6, 749, 1).multiplier, 500);
});
test('reject invalid cells, gift values and throw counts', () => {
  assert.equal(validTable(10, thresholds), true);
  for (const value of [0, -1, 1.5, NaN]) assert.equal(validTable(value, thresholds), false);
  for (const bad of [[], thresholds.slice(1), [0, ...thresholds.slice(1)], [1.5, ...thresholds.slice(1)]]) assert.equal(validTable(10, bad), false);
  assert.throws(() => advanceTable(thresholds, 0, 0, 0));
});
test('SQL draw uses unit price, updates only the chosen counter domain and falls back for missing rows', async () => {
  const writes: unknown[][] = [];
  const row = { giftValue: 10, thresholds, tier: 0, counter: 7, testTier: 1, testCounter: 14 };
  const tx: any = { $queryRaw: async (_sql: unknown, value: number) => value === 10 ? [row] : [],
    $executeRaw: async (...args: unknown[]) => { writes.push(args); return 1; } };
  assert.equal(await drawTable(tx, 999, 1), null);
  assert.equal(writes.length, 0);
  const live = await drawTable(tx, 10, 1);
  assert.equal(live?.multiplier, 5);
  assert.match(String(writes[0]![0]), /SET tier/);
  const virtual = await drawTable(tx, 10, 1, true);
  assert.equal(virtual?.multiplier, 10);
  assert.match(String(writes[1]![0]), /testTier/);
  assert.equal(row.counter, 7);
  const seed = 'table-proof';
  assert.equal(verifyRoll({ serverSeed: seed, serverSeedHash: rollHash(seed), tiersSnapshot: live, multiplier: 5 }).matches, true);
});

test('x5 and x10 are independent forever-counters, never blocked by a pending big tier', () => {
  // client rule: x5 every 10 throws, x10 every 20, whatever x1000 needs
  const th = [10, 20, 150, 375, 750, 1000000, 750, 1875, 3750, 7500, 1500, 3750, 7500, 15000];
  let tier = 5, counter = 0, c5 = 0, c10 = 0, total = 0, n5 = 0, n10 = 0;
  for (let i = 0; i < 100; i++) {
    const r = advanceTable(th, tier, counter, 1, { c5, c10 }) as any;
    ({ tier, counter, c5, c10 } = r);
    if (r.fired.includes(0)) n5++;
    if (r.fired.includes(1)) n10++;
    total += r.multiplier;
  }
  assert.equal(n5, 10);
  assert.equal(n10, 5);
  assert.equal(total, 10 * 5 + 5 * 10);
  assert.equal(tier, 5); // the big ladder is still waiting on x1000
});
test('a batch fires x5/x10 several times and keeps the remainders', () => {
  const th = [10, 20, 150, 375, 750, 1500, 750, 1875, 3750, 7500, 1500, 3750, 7500, 15000];
  const r = advanceTable(th, 0, 0, 45, { c5: 0, c10: 0 }) as any;
  assert.equal(r.multiplier, 4 * 5 + 2 * 10);
  assert.equal(r.c5, 5);
  assert.equal(r.c10, 5);
  assert.equal(r.tier, 2);
});
test('big ladder wraps to x100, not back into x5/x10, in fixed mode', () => {
  const th = [10, 20, 150, 375, 750, 1500, 750, 1875, 3750, 7500, 1500, 3750, 7500, 15000];
  const r = advanceTable(th, 13, 14999, 1, { c5: 0, c10: 0 }) as any;
  assert.equal(r.tier, 2);
  assert.equal(r.multiplier, 10000);
});
test('drawTable uses the fixed counters when the columns exist and stores them in the snapshot', async () => {
  const th = [10, 20, 150, 375, 750, 1500, 750, 1875, 3750, 7500, 1500, 3750, 7500, 15000];
  const row: any = { giftValue: 10, thresholds: th, tier: 2, counter: 0, testTier: 0, testCounter: 0, fixed5: 9, fixed10: 19, testFixed5: 0, testFixed10: 0 };
  const writes: any[] = [];
  const tx: any = { $queryRaw: async () => [row], $executeRaw: async (...a: unknown[]) => { writes.push(a); return 1; } };
  const r: any = await drawTable(tx, 10, 1);
  assert.equal(r.multiplier, 15);
  assert.match(String(writes[0][0]), /fixed5/);
  assert.equal(verifyRoll({ serverSeed: 's', serverSeedHash: rollHash('s'), tiersSnapshot: r, multiplier: 15 }).matches, true);
});
