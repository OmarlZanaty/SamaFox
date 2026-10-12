// «عندي قائمة محظوظ في الهدايا بس السيستم بتاعها مش شغال» — a gift filed under
// the محظوظ list was shown as lucky by the app but sent as an ordinary gift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { isLuckyGift } from '../lucky.service';

test('the flag alone makes a gift lucky', () => {
  assert.equal(isLuckyGift({ isLucky: true, category: 'love' }), true);
  assert.equal(isLuckyGift({ isLucky: true, category: null }), true);
});

test('the محظوظ list alone makes a gift lucky', () => {
  assert.equal(isLuckyGift({ isLucky: false, category: 'lucky' }), true);
  assert.equal(isLuckyGift({ isLucky: false, category: ' lucky ' }), true);
});

test('any other gift is ordinary', () => {
  assert.equal(isLuckyGift({ isLucky: false, category: 'love' }), false);
  assert.equal(isLuckyGift({ isLucky: false, category: null }), false);
  assert.equal(isLuckyGift({ isLucky: false }), false);
});
