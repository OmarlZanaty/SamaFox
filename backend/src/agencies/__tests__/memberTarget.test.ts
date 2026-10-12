import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { giftWindow, targetBalance } from '../targetMath';

/**
 * رصيد التارجت — the commission must be added BEFORE the zero floor, or a
 * وكيل's swapped-out commission comes back on the dashboard (2026-09-30:
 * "حولت الأربعين دولار ومع ذلك فاضل خمسة وتلاتين").
 */
describe('targetBalance', () => {
  test('agent who swapped everything shows 0, not the commission', () => {
    // $5 own gifts + $35 commission, all $40 swapped.
    assert.equal(targetBalance(50_000, -400_000n, 350_000n), 0);
    // What the dashboard used to compute: floor first, commission after.
    assert.equal(Math.max(0, 50_000 - 400_000) + 350_000, 350_000);
  });

  test('partial swap leaves exactly the unswapped remainder', () => {
    assert.equal(targetBalance(50_000, -100_000n, 350_000n), 300_000);
  });

  test('plain host: gifts plus adjustment, no commission', () => {
    assert.equal(targetBalance(120_000, 30_000n, null), 150_000);
  });

  test('never negative', () => {
    assert.equal(targetBalance(0, -10n, undefined), 0);
  });
});

describe('giftWindow', () => {
  const d = (s: string) => new Date(s);

  test('hosting seat owns the gifts; the charging seat of the same day owns none', () => {
    const seats = [
      { id: 56, joinedAt: d('2026-09-20'), hosting: true },
      { id: 57, joinedAt: d('2026-09-20'), hosting: false },
    ];
    assert.deepEqual(giftWindow(seats, 56), { from: d('2026-09-20'), to: null });
    assert.equal(giftWindow(seats, 57), null);
  });

  test('gifts before a later hosting seat stay on the older charging seat', () => {
    const seats = [
      { id: 22, joinedAt: d('2026-07-29'), hosting: false },
      { id: 47, joinedAt: d('2026-09-07'), hosting: true },
    ];
    assert.deepEqual(giftWindow(seats, 47), { from: d('2026-09-07'), to: null });
    assert.deepEqual(giftWindow(seats, 22), { from: d('2026-07-29'), to: d('2026-09-07') });
  });

  test('two charging seats: the earlier one owns everything', () => {
    const seats = [
      { id: 11, joinedAt: d('2026-07-15'), hosting: false },
      { id: 12, joinedAt: d('2026-07-16'), hosting: false },
    ];
    assert.deepEqual(giftWindow(seats, 11), { from: d('2026-07-15'), to: null });
    assert.equal(giftWindow(seats, 12), null);
  });

  test('single seat owns everything; unknown row owns nothing', () => {
    const seats = [{ id: 1, joinedAt: d('2026-08-01'), hosting: true }];
    assert.deepEqual(giftWindow(seats, 1), { from: d('2026-08-01'), to: null });
    assert.equal(giftWindow(seats, 2), null);
  });
});
