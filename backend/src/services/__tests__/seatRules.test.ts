import test from 'node:test';
import assert from 'node:assert/strict';
import { seatsAboveMax, moveRejection, shouldReconcileMute } from '../seatRules';
import { LeasedSeats } from '../seatLease';

test('reducing the mic count finds the stuck seats, and the user can sit again after release', () => {
  const seats = new LeasedSeats(() => 's');
  seats.set(1, 10); seats.set(7, 20); seats.set(8, 30);
  const stuck = seatsAboveMax(seats.entries(), 6);
  assert.deepEqual(stuck, [[7, 20], [8, 30]]);
  for (const [sn] of stuck) seats.delete(sn);
  // take_seat's "already seated" scan no longer finds user 20
  assert.equal([...seats.entries()].some(([, u]) => u === 20), false);
  assert.deepEqual(seatsAboveMax(seats.entries(), 6), []);
});

const base = () => ({ seats: new Map([[2, 5]]), locked: new Set<number>([4]), uid: 5, from: 2, to: 3, maxSeats: 8 });

test('moveSeat rejection paths', () => {
  assert.equal(moveRejection(base()), null);
  assert.ok(moveRejection({ ...base(), from: 1 }));            // not his seat
  assert.ok(moveRejection({ ...base(), to: 4 }));              // locked
  assert.ok(moveRejection({ ...base(), seats: new Map([[2, 5], [3, 9]]) })); // taken
  assert.ok(moveRejection({ ...base(), to: 9 }));              // above max
  assert.ok(moveRejection({ ...base(), to: 0 }));              // below 1
  assert.ok(moveRejection({ ...base(), to: 2 }));              // same seat
});

test('heartbeat mute reconcile: mute always allowed, unmute only when live, outside grace, not forced', () => {
  const ok = { micMuted: false, seated: true, adminMuted: false, forceMuted: false, current: true as boolean | undefined, voiceState: 'publishing' as unknown, msSinceServerChange: undefined as number | undefined };
  assert.equal(shouldReconcileMute(ok), true);
  assert.equal(shouldReconcileMute({ ...ok, current: false }), false);
  assert.equal(shouldReconcileMute({ ...ok, forceMuted: true }), false);
  assert.equal(shouldReconcileMute({ ...ok, adminMuted: true }), false);
  assert.equal(shouldReconcileMute({ ...ok, seated: false }), false);
  assert.equal(shouldReconcileMute({ ...ok, micMuted: undefined }), false);
  assert.equal(shouldReconcileMute({ ...ok, voiceState: 'muted' }), false);
  assert.equal(shouldReconcileMute({ ...ok, voiceState: 'listening' }), false);
  assert.equal(shouldReconcileMute({ ...ok, voiceState: undefined }), false);
  assert.equal(shouldReconcileMute({ ...ok, msSinceServerChange: 5_000 }), false);
  assert.equal(shouldReconcileMute({ ...ok, msSinceServerChange: 16_000 }), true);
  // mute direction: always safe even if force/admin muted or phone not 'publishing'
  assert.equal(shouldReconcileMute({ ...ok, micMuted: true, current: false, forceMuted: true, adminMuted: true, voiceState: 'muted' }), true);
  assert.equal(shouldReconcileMute({ ...ok, micMuted: true, current: undefined }), false);
  assert.equal(shouldReconcileMute({ ...ok, micMuted: true, current: false, msSinceServerChange: 1_000 }), false);
});
