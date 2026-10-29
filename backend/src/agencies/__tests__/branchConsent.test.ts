import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

type Row = Record<string, any>;
let agency: Row;
let seats: Row[];
let invites: Row[];
let branches: Row[];
let notifications: Row[];
function matches(row: Row, where: Row): boolean {
  return Object.entries(where).every(([key, value]) => {
    if (key === 'OR') return value.some((w: Row) => matches(row, w));
    if (key === 'agencyId_userId' || key === 'parentAgencyId_ownerUserId') return matches(row, value);
    const actual = key === 'agency' ? (row.agency ?? agency) : row[key];
    if (value && typeof value === 'object') {
      if ('not' in value) return actual !== value.not;
      if ('in' in value) return value.in.includes(actual);
      if ('lte' in value) return actual != null && actual <= value.lte;
      if ('gt' in value) return actual != null && actual > value.gt;
      return matches(actual, value);
    }
    return actual === value;
  });
}
function model(rows: () => Row[]) {
  const find = async ({ where }: Row) => {
    const row = rows().find(r => matches(r, where));
    return row ? { ...row, agency } : null;
  };
  return {
    findUnique: find, findFirst: find, findUniqueOrThrow: find,
    findMany: async ({ where }: Row) => rows().filter(r => matches(r, where)),
    count: async ({ where }: Row) => rows().filter(r => matches(r, where)).length,
    create: async ({ data }: Row) => {
      const row = { id: rows().length + 1, status: 'pending', expiresAt: null, ...data };
      rows().push(row); return row;
    },
    updateMany: async ({ where, data }: Row) => {
      const found = rows().filter(r => matches(r, where));
      found.forEach(r => Object.assign(r, data)); return { count: found.length };
    },
    upsert: async ({ where, create, update }: Row) => {
      let row = rows().find(r => matches(r, where));
      if (row) Object.assign(row, update);
      else { row = { id: rows().length + 1, ...create }; rows().push(row); }
      return row;
    },
  };
}
const db = {
  chargingAgency: model(() => [agency]), agencyMember: model(() => seats),
  agencyInvite: model(() => invites), agencyBranch: model(() => branches),
  user: model(() => [10, 20, 30, 40, 50].map(id => ({ id, name: `User ${id}` }))),
  notification: { updateMany: async () => ({ count: 1 }) },
  $transaction: async (fn: (tx: any) => Promise<any>) => {
    const before = { seats: seats.map(r => ({ ...r })), invites: invites.map(r => ({ ...r })), branches: branches.map(r => ({ ...r })) };
    try { return await fn(db); } catch (e) { ({ seats, invites, branches } = before); throw e; }
  },
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('lib/prisma', { prisma: db });
stub('services/notification.service', { createNotification: async (data: Row) => { notifications.push(data); } });
for (const name of ['vip', 'agencyReward', 'broadcast', 'hostTarget', 'targetMovement']) stub(`services/${name}.service`, {});
const { addBranch, respondInvite, getMyInvites }: typeof import('../agency.controller') = require('../agency.controller');
const { createChargingBranch, updateChargingBranch }: typeof import('../../services/agencyIdentity.service') = require('../../services/agencyIdentity.service');
beforeEach(() => {
  agency = { id: 7, userId: 10, type: 'CHARGING', status: 'approved', agencyName: 'Test agency' };
  seats = [{ id: 1, agencyId: 7, userId: 10, role: 'OWNER' }];
  invites = []; branches = []; notifications = [];
});
async function call(handler: any, userId: number, body: Row = {}, params: Row = {}) {
  let status = 200; let response: any;
  const res = { status(code: number) { status = code; return res; }, json(data: any) { response = data; return res; } };
  await handler({ userId, body, params, query: {} }, res);
  return { status, body: response };
}
for (const type of ['CHARGING', 'HOSTING']) {
  test(`${type}: branch invite grants access only on acceptance and notifies both sides`, async () => {
    agency.type = type;
    seats.push({ id: 2, agencyId: 7, userId: 20, role: 'MEMBER' });
    const result = await call(addBranch, 10, { userId: 20, agencyType: type });
    assert.equal(result.status, 201);
    assert.equal(result.body.data.state, 'PENDING');
    assert.equal(result.body.data.invite.role, 'BRANCH');
    assert.equal(seats[1]!.role, 'MEMBER');
    assert.equal(branches.length, 0);
    assert.deepEqual(notifications[0]!.data, { inviteId: 1, agencyId: 7, role: 'BRANCH' });
    assert.equal((await call(getMyInvites, 20)).body.data[0].role, 'BRANCH');
    const accepted = await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 });
    assert.equal(accepted.status, 200);
    assert.equal(accepted.body.role, 'BRANCH');
    assert.equal(seats[1]!.role, 'BRANCH');
    assert.equal(branches.length, type === 'CHARGING' ? 1 : 0);
    assert.deepEqual(notifications.filter(n => n.type === 'AGENCY_BRANCH_ADDED').map(n => n.userId).sort(), [10, 20]);
    const count = notifications.length;
    assert.equal((await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 })).status, 200);
    assert.equal(notifications.length, count);
  });
}
test('rejecting a branch invite leaves the membership untouched', async () => {
  await call(addBranch, 10, { userId: 20 });
  assert.equal((await call(respondInvite, 20, { action: 'reject' }, { inviteId: 1 })).body.state, 'REJECTED');
  assert.equal(invites[0]!.status, 'rejected');
  assert.equal(seats.length, 1);
  assert.equal(branches.length, 0);
});
test('pending member invite gets a clear conflict, never a second pending pair', async () => {
  invites.push({ id: 1, agencyId: 7, inviteeId: 20, role: 'MEMBER', status: 'pending' });
  const result = await call(addBranch, 10, { userId: 20 });
  assert.equal(result.status, 409);
  assert.ok(result.body.message.length > 20);
  assert.equal(invites.length, 1);
  assert.equal(seats.length, 1);
});
test('pending branch reservations count toward capacity including MEMBER upgrades', async () => {
  seats.push({ id: 2, agencyId: 7, userId: 50, role: 'MEMBER' });
  for (const userId of [20, 30, 40]) assert.equal((await call(addBranch, 10, { userId })).status, 201);
  assert.equal((await call(addBranch, 10, { userId: 50 })).status, 400);
  assert.equal((await call(addBranch, 10, { userId: 20 })).status, 201);
  assert.equal(invites.length, 3);
});
test('acceptance rechecks capacity and rolls back on conflict', async () => {
  await call(addBranch, 10, { userId: 20 });
  for (const userId of [30, 40, 50]) seats.push({ id: userId, agencyId: 7, userId, role: 'BRANCH' });
  assert.equal((await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 })).body.code, 'MAX_BRANCHES');
  assert.equal(invites[0]!.status, 'pending');
  assert.equal(branches.length, 0);
});
test('one-agency rule is checked again at acceptance', async () => {
  await call(addBranch, 10, { userId: 20 });
  seats.push({ id: 2, agencyId: 8, userId: 20, role: 'OWNER' });
  assert.equal((await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 })).body.code, 'ALREADY_IN_AGENCY');
  assert.equal(invites[0]!.status, 'pending');
});
test('identity branch entry point also requires consent', async () => {
  const result = await createChargingBranch({ userId: 10 }, 7, 20);
  assert.equal(result.invite.role, 'BRANCH');
  assert.equal(seats.length, 1);
  assert.equal(branches.length, 0);
  await call(respondInvite, 20, { action: 'accept' }, { inviteId: result.invite.id });
  assert.equal(branches[0]!.ownerUserId, 20);
});
test('non-owner cannot invite and another user cannot accept', async () => {
  assert.equal((await call(addBranch, 20, { userId: 30 })).status, 403);
  await call(addBranch, 10, { userId: 20 });
  assert.equal((await call(respondInvite, 30, { action: 'accept' }, { inviteId: 1 })).status, 403);
  assert.equal(seats.length, 1);
});

test('expired invitations release reserved capacity and cannot be accepted', async () => {
  await call(addBranch, 10, { userId: 20 });
  invites[0]!.expiresAt = new Date(0);
  assert.equal((await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 })).status, 410);
  assert.equal(invites[0]!.status, 'expired');
  for (const userId of [30, 40, 50]) assert.equal((await call(addBranch, 10, { userId })).status, 201);
  assert.equal(seats.length, 1);
});
test('accepting one reserved slot succeeds when all three slots are reserved', async () => {
  for (const userId of [20, 30, 40]) await call(addBranch, 10, { userId });
  assert.equal((await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 })).status, 200);
  assert.equal(seats.filter(s => s.role === 'BRANCH').length, 1);
  assert.equal(invites.filter(i => i.status === 'pending').length, 2);
});
test('ordinary MEMBER invitation still creates only a MEMBER', async () => {
  invites.push({ id: 1, agencyId: 7, inviteeId: 20, inviterId: 10, role: 'MEMBER', status: 'pending', expiresAt: null });
  assert.equal((await call(respondInvite, 20, { action: 'accept' }, { inviteId: 1 })).status, 200);
  assert.equal(seats[1]!.role, 'MEMBER');
  assert.equal(branches.length, 0);
  assert.equal(notifications.some(n => n.type === 'AGENCY_BRANCH_ADDED'), false);
});
test('closed or revoked branches cannot regain access through a status patch', async () => {
  branches.push({ id: 1, parentAgencyId: 7, ownerUserId: 20, status: 'CLOSED' });
  for (const status of ['CLOSED', 'ACTIVE']) {
    branches[0]!.status = status;
    await assert.rejects(updateChargingBranch({ userId: 10, body: { status: 'ACTIVE' } }, 7, 1), (e: any) => e.status === 409);
    assert.equal(seats.length, 1);
  }
});
