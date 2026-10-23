import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

// 2026-10-23 — exercise the handlers without starting the server or a database.
type Row = Record<string, any>;
let invites: Row[];
let notifications: Row[];
let pendingQueries: number;
let failNotificationWrite: boolean;
let inTransaction = false;

function matches(row: Row, where: Row): boolean {
  return Object.entries(where).every(([key, value]) => {
    if (key === 'OR') return value.some((part: Row) => matches(row, part));
    const actual = row[key];
    if (value !== null && typeof value === 'object') {
      if ('path' in value) return actual?.[value.path[0]] === value.equals;
      if ('gt' in value) return actual !== null && actual > value.gt;
      if ('lte' in value) return actual !== null && actual <= value.lte;
      if ('in' in value) return value.in.includes(actual);
      if ('notIn' in value) return !value.notIn.includes(actual);
      throw new Error(`Unsupported predicate: ${key}`);
    }
    return actual === value;
  });
}

function update(rows: Row[], { where, data }: Row) {
  const found = rows.filter(row => matches(row, where));
  for (const row of found) Object.assign(row, data);
  return { count: found.length };
}

const db = {
  agencyInvite: {
    findMany: async ({ where }: Row) => {
      pendingQueries++;
      return invites.filter(row => matches(row, where));
    },
    findUnique: async ({ where }: Row) => invites.find(row => matches(row, where)) ?? null,
    findUniqueOrThrow: async ({ where }: Row) => {
      const invite = invites.find(row => matches(row, where));
      assert.ok(invite);
      return invite;
    },
    updateMany: async (args: Row) => update(invites, args),
  },
  notification: {
    findFirst: async ({ where }: Row) => notifications.find(row => matches(row, where)) ?? null,
    findMany: async ({ where }: Row) => notifications.filter(row => matches(row, where)),
    updateMany: async (args: Row) => {
      assert.equal(inTransaction, false, 'notification cleanup must follow commit');
      if (failNotificationWrite) throw new Error('notification write failed');
      return update(notifications, args);
    },
  },
  chargingAgency: { findUnique: async () => ({ agencyName: 'Agency' }) },
  agencyMember: {
    findFirst: async ({ where }: Row) => where.userId === 20
      ? { id: 1, agencyId: 7, agency: { type: 'HOSTING' } } : null,
    upsert: async ({ create }: Row) => ({ id: 2, ...create }),
  },
  $transaction: async (fn: (tx: any) => Promise<any>) => {
    inTransaction = true;
    try { return await fn(db); } finally { inTransaction = false; }
  },
};

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/notification.service', {
  createNotification: async (data: Row) => notifications.push({
    id: notifications.length + 100, isRead: false, readAt: null, ...data,
  }),
});
stub('services/vip.service', {});
stub('services/broadcast.service', {});
stub('services/hostTarget.service', {});
stub('services/targetMovement.service', {});
const { markNotificationRead, markAllNotificationsRead }: typeof import('../notification.controller') = require('../notification.controller');
const { markInviteNotificationsRead, changePendingInvite }: typeof import('../../services/agencyInvites.service') = require('../../services/agencyInvites.service');
const { respondInvite, reviewJoinRequest }: typeof import('../../agencies/agency.controller') = require('../../agencies/agency.controller');

beforeEach(() => {
  invites = [{ id: 154, inviteeId: 10, inviterId: 20, agencyId: 7, status: 'pending', expiresAt: null,
    agency: { id: 7, userId: 20, type: 'HOSTING', status: 'approved' } }];
  notifications = [{ id: 1, userId: 10, type: 'AGENCY_INVITE', data: { inviteId: 154 }, isRead: false, readAt: null }];
  pendingQueries = 0;
  failNotificationWrite = false;
});

async function call(handler: (req: any, res: any) => Promise<any>, overrides: Row = {}) {
  let status = 200;
  let body: any;
  const res = { status: (code: number) => { status = code; return res; }, json: (value: any) => { body = value; return res; } };
  await handler({ userId: 10, params: { id: '1', inviteId: '154' }, query: {}, body: {}, ...overrides }, res);
  assert.equal(status, 200);
  assert.equal(body.success, true);
}

test('reading a pending invite is a successful no-op, with or without an expiry', async () => {
  for (const expiresAt of [null, new Date(Date.now() + 60_000)]) {
    invites[0]!.expiresAt = expiresAt;
    await call(markNotificationRead);
    assert.equal(notifications[0]!.isRead, false);
    assert.equal(notifications[0]!.readAt, null);
  }
  assert.equal(pendingQueries, 2);
});

test('reading the same notification after acceptance works', async () => {
  await call(markNotificationRead);
  invites[0]!.status = 'accepted';
  await call(markNotificationRead);
  assert.equal(notifications[0]!.isRead, true);
  assert.ok(notifications[0]!.readAt instanceof Date);
});

test('expired pending invites can be marked read', async () => {
  invites[0]!.expiresAt = new Date(Date.now() - 60_000);
  await call(markNotificationRead);
  assert.equal(notifications[0]!.isRead, true);
});

test('read-all skips live invites and marks accepted, expired and ordinary notices', async () => {
  invites.push({ id: 157, inviteeId: 10, status: 'accepted', expiresAt: null },
    { id: 158, inviteeId: 10, status: 'pending', expiresAt: new Date(Date.now() - 60_000) });
  notifications.push(
    { ...notifications[0], id: 2, data: { inviteId: 157 } },
    { ...notifications[0], id: 3, data: { inviteId: 158 } },
    { ...notifications[0], id: 4, type: 'MESSAGE' },
    { ...notifications[0], id: 5, userId: 99 },
    { ...notifications[0], id: 6, data: null },
  );
  await call(markAllNotificationsRead);
  assert.deepEqual(notifications.map(row => row.isRead), [false, true, true, true, false, true]);
  assert.equal(pendingQueries, 1);
});

test('agency-only read-all preserves category and user scoping', async () => {
  notifications.push(
    { ...notifications[0], id: 2, type: 'AGENCY_COMMISSION' },
    { ...notifications[0], id: 3, type: 'MESSAGE' },
    { ...notifications[0], id: 4, type: 'AGENCY_COMMISSION', userId: 99 },
  );
  await call(markAllNotificationsRead, { query: { category: 'agency' } });
  assert.deepEqual(notifications.map(row => row.isRead), [false, true, false, false]);
});

test('single-read preserves ownership and treats non-invite notifications normally', async () => {
  await call(markNotificationRead, { userId: 99 });
  assert.equal(notifications[0]!.isRead, false);
  notifications[0]!.type = 'MESSAGE';
  await call(markNotificationRead);
  assert.equal(notifications[0]!.isRead, true);
});

test('cleanup marks only the invitee\'s matching invite notices', async () => {
  notifications.push(
    { ...notifications[0], id: 2 },
    { ...notifications[0], id: 3, data: { inviteId: 157 } },
    { ...notifications[0], id: 4, userId: 99 },
    { ...notifications[0], id: 5, type: 'MESSAGE' },
  );
  await markInviteNotificationsRead(10, 154);
  assert.deepEqual(notifications.map(row => row.isRead), [true, true, false, false, false]);
});

for (const action of ['accept', 'reject']) {
  test(`host ${action} clears invite notifications after commit`, async () => {
    await call(respondInvite, { body: { action } });
    assert.equal(notifications[0]!.isRead, true);
    assert.equal(invites[0]!.status, action === 'accept' ? 'accepted' : 'rejected');
  });

  test(`agent ${action} clears the invitee's notifications after commit`, async () => {
    await call(reviewJoinRequest, { userId: 20, body: { action } });
    assert.equal(notifications[0]!.isRead, true);
  });
}

test('cancellation clears old notices', async () => {
  await changePendingInvite(20, 154, false);
  assert.equal(invites[0]!.status, 'cancelled');
  assert.equal(notifications[0]!.isRead, true);
});

test('resend clears old notices before creating the new unread notice', async () => {
  await changePendingInvite(20, 154, true);
  assert.equal(invites[0]!.status, 'pending');
  assert.deepEqual(notifications.map(row => row.isRead), [true, false]);
  assert.equal(notifications[1]!.data.inviteId, 154);
});

test('cleanup failure warns without failing an accepted invite', async (t) => {
  failNotificationWrite = true;
  const warn = t.mock.method(console, 'warn', () => {});
  await call(respondInvite, { body: { action: 'accept' } });
  assert.equal(invites[0]!.status, 'accepted');
  assert.equal(warn.mock.callCount(), 1);
});
