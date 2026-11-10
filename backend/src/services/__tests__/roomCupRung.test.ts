import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rungDue, rungIncrement } from '../roomCupMath';

const now = new Date('2026-10-03T12:00:00Z');
const hoursAgo = (h: number) => new Date(now.getTime() - h * 3600_000);

test('a rung never paid is due', () => {
  assert.equal(rungDue(null, 24, now), true);
  assert.equal(rungDue(undefined, 0, now), true);
});

test('with a 24h window a rung pays again once the window has passed', () => {
  assert.equal(rungDue(hoursAgo(23), 24, now), false);
  assert.equal(rungDue(hoursAgo(24), 24, now), true);
  assert.equal(rungDue(hoursAgo(72), 24, now), true);
});

test('with an all-time total a rung pays once per room', () => {
  assert.equal(rungDue(hoursAgo(1000), 0, now), false);
});

test('rung rewards are cumulative: 1M→30k then 2M→60k pays 60k in all, not 90k', () => {
  const rewards = [30_000n, 60_000n];
  const paid = rungIncrement(rewards, 0) + rungIncrement(rewards, 1);
  assert.equal(rungIncrement(rewards, 0), 30_000n);
  assert.equal(rungIncrement(rewards, 1), 30_000n);
  assert.equal(paid, 60_000n);
});

test('three rungs reached in one gift still total the top reward', () => {
  const rewards = [30_000n, 60_000n, 150_000n];
  assert.equal(rewards.reduce((sum, _, i) => sum + rungIncrement(rewards, i), 0n), 150_000n);
});

test('a rung worth no more than a lower one pays nothing', () => {
  assert.equal(rungIncrement([50_000n, 40_000n], 1), 0n);
  assert.equal(rungIncrement([50_000n, 40_000n, 60_000n], 2), 10_000n);
});
