import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { targetBalance } from '../targetMath';

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
