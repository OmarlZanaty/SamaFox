import test from 'node:test';
import assert from 'node:assert/strict';
import { PkMatchQueue, RANDOM_PK_WAIT_MS } from '../pkMatchmaking';

test('the first room waits; the next opted-in room is paired with it', () => {
  let t = 1000;
  const q = new PkMatchQueue(() => t);
  assert.equal(q.take({ roomId: 1, userId: 10, durationSec: 300 }), null);
  assert.equal(q.isWaiting(1), true);
  t += 5000;
  const partner = q.take({ roomId: 2, userId: 20, durationSec: 600 });
  assert.deepEqual(partner, { roomId: 1, userId: 10, durationSec: 300, at: 1000 });
  assert.equal(q.isWaiting(1), false);
  assert.equal(q.isWaiting(2), false);
});

test('a room never pairs with itself and re-joining replaces its entry', () => {
  const q = new PkMatchQueue(() => 0);
  assert.equal(q.take({ roomId: 1, userId: 10, durationSec: 300 }), null);
  assert.equal(q.take({ roomId: 1, userId: 11, durationSec: 600 }), null);
  assert.equal(q.take({ roomId: 2, userId: 20, durationSec: 300 })?.userId, 11);
});

test('stale and busy rooms are skipped; cancel leaves the queue', () => {
  let t = 0;
  const q = new PkMatchQueue(() => t);
  q.take({ roomId: 1, userId: 10, durationSec: 300 });
  t = RANDOM_PK_WAIT_MS + 1;
  assert.equal(q.take({ roomId: 2, userId: 20, durationSec: 300 }), null, 'room 1 lapsed');
  q.take({ roomId: 3, userId: 30, durationSec: 300 }, id => id === 2);
  assert.equal(q.isWaiting(2), false, 'busy room dropped');
  assert.equal(q.isWaiting(3), true);
  assert.equal(q.cancel(3), true);
  assert.equal(q.isWaiting(3), false);
});
