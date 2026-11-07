import test from 'node:test';
import assert from 'node:assert/strict';
import { isValidGiftQuantity } from '../giftLimits';

test('ordinary and CP gift quantities accept every picker option', () => {
  for (const quantity of [1, 7, 77, 777, 7777]) {
    assert.equal(isValidGiftQuantity(quantity), true, `quantity ${quantity}`);
  }
});

test('gift quantities reject values outside the integer range 1..7777', () => {
  for (const quantity of [0, -1, 1.5, 7778, Number.MAX_SAFE_INTEGER, NaN, Infinity]) {
    assert.equal(isValidGiftQuantity(quantity), false, `quantity ${quantity}`);
  }
});
