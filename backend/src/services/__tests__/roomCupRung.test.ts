import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rungDue } from '../roomCupMath';

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
