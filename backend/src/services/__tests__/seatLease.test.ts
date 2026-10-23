import { test } from 'node:test';
import assert from 'node:assert/strict';

function loadSeatLease(value?: string): typeof import('../seatLease') {
  const filename = require.resolve('../seatLease');
  const cached = require.cache[filename];
  const previous = process.env.ROOM_SEAT_LEASE_MS;
  try {
    if (value === undefined) delete process.env.ROOM_SEAT_LEASE_MS;
    else process.env.ROOM_SEAT_LEASE_MS = value;
    delete require.cache[filename];
    return require('../seatLease');
  } finally {
    if (previous === undefined) delete process.env.ROOM_SEAT_LEASE_MS;
    else process.env.ROOM_SEAT_LEASE_MS = previous;
    if (cached) require.cache[filename] = cached;
    else delete require.cache[filename];
  }
}

test('seat leases default to 12 hours and become stale after 45 seconds', (t) => {
  const { LeasedSeats, SEAT_LEASE_MS, SEAT_STALE_MS } = loadSeatLease();
  t.mock.method(Date, 'now', () => 1000);
  const seats = new LeasedSeats(() => 'session-1');
  seats.set(1, 5);
  assert.equal(SEAT_LEASE_MS, 43_200_000);
  assert.equal(SEAT_STALE_MS, 45_000);
  assert.equal(seats.leases.get(1)!.leaseExpiresAt, 1000 + 43_200_000);
});

test('ROOM_SEAT_LEASE_MS overrides creation and renewal duration', (t) => {
  const { LeasedSeats, SEAT_LEASE_MS } = loadSeatLease('600000');
  t.mock.method(Date, 'now', () => 1000);
  const seats = new LeasedSeats(() => 'session-1');
  seats.set(1, 5);
  assert.equal(SEAT_LEASE_MS, 600_000);
  assert.equal(seats.leases.get(1)!.leaseExpiresAt, 601_000);
  assert.equal(seats.renew(5, 'session-2', 2000), true);
  assert.equal(seats.leases.get(1)!.leaseExpiresAt, 602_000);
});

test('invalid lease overrides fall back to 12 hours', () => {
  for (const value of ['', '0', '-1', 'NaN', 'invalid', 'Infinity']) {
    assert.equal(loadSeatLease(value).SEAT_LEASE_MS, 43_200_000, value);
  }
});

test('hold keeps the seat until lastHeartbeat plus the lease duration', (t) => {
  const { LeasedSeats, SEAT_LEASE_MS, SEAT_STALE_MS } = loadSeatLease();
  let now = 1000;
  t.mock.method(Date, 'now', () => now);
  const seats = new LeasedSeats(() => 'session-1');
  seats.set(1, 5);
  now = 2000;
  assert.equal(seats.renew(5, 'session-2'), true);
  now += SEAT_STALE_MS + 1;
  assert.equal(seats.hold(5), true);
  assert.equal(seats.get(1), 5);
  assert.deepEqual(seats.leases.get(1), {
    userId: 5, sessionId: 'session-2', status: 'held',
    lastHeartbeat: 2000, leaseExpiresAt: 2000 + SEAT_LEASE_MS,
  });
  now += SEAT_STALE_MS;
  assert.equal(seats.hold(5), false);
  assert.equal(seats.leases.get(1)!.leaseExpiresAt, 2000 + SEAT_LEASE_MS);
});

test('seat holders come from the map regardless of lease status or expiry', () => {
  const { LeasedSeats, seatHolders } = loadSeatLease();
  const seats = new LeasedSeats(() => 'session-1');
  seats.set(1, 5).set(2, 6).set(3, 7);
  seats.hold(5);
  seats.leases.get(1)!.leaseExpiresAt = 0;
  seats.leases.delete(3);
  assert.deepEqual(seatHolders(seats), new Set([5, 6, 7]));
  seats.delete(1);
  assert.deepEqual(seatHolders(seats), new Set([6, 7]));
  assert.equal(seats.leases.has(1), false);
  seats.clear();
  assert.deepEqual(seatHolders(seats), new Set());
  assert.equal(seats.leases.size, 0);
});
