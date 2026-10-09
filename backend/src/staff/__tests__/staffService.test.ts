import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { DAY } from '../staffRules';

// Replace every boundary before loading the service: these tests cannot load
// index.ts, start a listener, or instantiate a database client.
type Row = Record<string, any>;
const tables: Record<string, Row[]> = {};
const events: Row[] = [];
const notifications: Row[] = [];
const earnedRewards: Row[] = [];
const names = ['user', 'staffRole', 'staffPermission', 'staffAgencyScope', 'temporaryEntitlement', 'banRecord', 'appSetting', 'item', 'userItem', 'adminAuditLog', 'chargingAgency', 'agencyMember'];
function match(row: Row, where: Row = {}): boolean {
  return Object.entries(where).every(([key, value]) => {
    if (value === undefined) return true;
    if (key === 'OR') return value.some((v: Row) => match(row, v));
    if (key === 'AND') return (Array.isArray(value) ? value : [value]).every((v: Row) => match(row, v));
    if (key.includes('_')) return match(row, value);
    const actual = row[key];
    if (value instanceof Date) return actual?.getTime() === value.getTime();
    if (value !== null && typeof value === 'object') return Object.entries(value).every(([operator, expected]: [string, any]) => {
      if (operator === 'in') return expected.includes(actual);
      if (operator === 'not') return actual !== expected;
      if (operator === 'gt') return actual !== null && actual > expected;
      if (operator === 'lte') return actual !== null && actual <= expected;
      if (operator === 'startsWith') return actual.startsWith(expected);
      throw new Error(`Unsupported fake predicate ${operator}`);
    });
    return actual === value;
  });
}
const db: any = {};
for (const name of names) {
  db[name] = {
    findMany: async ({ where, orderBy, skip = 0, take }: Row = {}) => {
      const rows = tables[name]!.filter(r => match(r, where));
      const order = orderBy ? (Array.isArray(orderBy) ? orderBy : [orderBy]) : [];
      rows.sort((a, b) => {
        for (const part of order) for (const [key, direction] of Object.entries(part)) {
          if (a[key] !== b[key]) return (a[key] > b[key] ? 1 : -1) * (direction === 'desc' ? -1 : 1);
        }
        return 0;
      });
      return structuredClone(rows.slice(skip, take == null ? undefined : skip + take));
    },
    findFirst: async (args: Row) => (await db[name].findMany(args))[0] ?? null,
    findUnique: async ({ where }: Row) => structuredClone(tables[name]!.find(r => match(r, where)) ?? null),
    findUniqueOrThrow: async (args: Row) => { const row = await db[name].findUnique(args); assert.ok(row, `${name} missing`); return row; },
    count: async ({ where }: Row) => tables[name]!.filter(r => match(r, where)).length,
    create: async ({ data }: Row) => {
      const now = new Date();
      const row = { id: Math.max(0, ...tables[name]!.map(r => Number(r.id) || 0)) + 1, status: 'ACTIVE', expiresAt: null,
        startedAt: now, createdAt: now, grantedAt: now, staffRoleId: null, source: 'GRANT', endedAt: null, ...structuredClone(data) };
      tables[name]!.push(row); return structuredClone(row);
    },
    update: async ({ where, data }: Row) => {
      const row = tables[name]!.find(r => match(r, where)); assert.ok(row, `${name} missing for update`);
      Object.assign(row, structuredClone(data)); return structuredClone(row);
    },
    updateMany: async ({ where, data }: Row) => {
      const rows = tables[name]!.filter(r => match(r, where)); rows.forEach(r => Object.assign(r, structuredClone(data))); return { count: rows.length };
    },
    deleteMany: async ({ where }: Row) => { const old = tables[name]!.length; tables[name] = tables[name]!.filter(r => !match(r, where)); return { count: old - tables[name]!.length }; },
    upsert: async ({ where, create, update }: Row) => (await db[name].findUnique({ where })) ? db[name].update({ where, data: update }) : db[name].create({ data: create }),
  };
}
db.$transaction = async (fn: (client: any) => Promise<any>) => {
  const snapshot = structuredClone(tables);
  try { return await fn(db); } catch (error) { for (const name of names) tables[name] = snapshot[name]!; throw error; }
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/socket.service', { emitToUser: (userId: number, event: string, payload: any) => events.push({ userId, event, payload }), kickBannedUser: async () => {} });
stub('services/notification.service', { createNotification: async (input: Row) => notifications.push(input) });
stub('utils/banGuard', { invalidateBanCache: () => {} });
stub('services/vip.service', { getVipThresholdOverrides: async () => new Map(), computeVipLevelWithOverrides: (value: number) => value,
  grantVipRewardsForRange: async (userId: number, from: number, to: number) => earnedRewards.push({ type: 'VIP', userId, from, to }) });
stub('services/xp.service', { getLevelThresholdOverrides: async () => new Map(), calculateLevelWithOverrides: (value: number) => value,
  grantLevelRewards: async (userId: number, level: number) => earnedRewards.push({ type: 'LEVEL', userId, level }) });
stub('agencies/agency.controller', { computeAgencyEarnedCoins: async () => 10, memberTargetEarned: async () => 5 });
stub('services/broadcast.service', { getBroadcastSeconds: async () => 3600 });
const service: typeof import('../staff.service') = require('../staff.service');
const call = (userId: number, op: import('../staff.service').Operation, body: Row = {}, params: Row = {}, dashboard = false, query: Row = {}): Promise<any> =>
  service.runStaffAction({ userId, dashboard, ip: '127.0.0.1', userAgent: 'device | test' }, op, body, params, query);
const reject = (promise: Promise<unknown>, status: number) => assert.rejects(promise, (e: any) => e instanceof service.StaffError && e.status === status && /[\u0600-\u06ff]/.test(e.message));
function row(name: string, id: number) { return tables[name]!.find(r => r.id === id)!; }
beforeEach(async () => {
  for (const name of names) tables[name] = [];
  events.length = notifications.length = earnedRewards.length = 0;
  for (let id = 1; id <= 15; id++) tables.user!.push({ id, displayId: id + 10000, name: `u${id}`, isBanned: false,
    banExpiresAt: null, isAdmin: false, isSuperAdmin: false, vipLevel: 3, totalRecharge: 3, level: 3, xp: 3 });
  for (const [id, role, parentUserId] of [[1, 'MANAGER', null], [2, 'SUPER_ADMIN', 1], [3, 'ADMIN', 2], [4, 'MANAGER', null]] as const) {
    await db.staffRole.create({ data: { id, userId: id, role, parentUserId, expiresAt: new Date(Date.now() + 30 * DAY), allowedItemIds: ['frame'], rewardItemIds: [] } });
  }
  for (const userId of [2, 3]) for (const permission of ['role_panel', 'manage_host_agency', 'follow_agencies', ...(userId === 2 ? ['manage_admins', 'grant_vip', 'grant_frame'] : [])]) {
    await db.staffPermission.create({ data: { userId, staffRoleId: userId, permission } });
  }
  tables.item!.push({ id: 'frame', type: 'FRAME', name: 'إطار', assetUrl: '/frame', previewUrl: null });
  tables.appSetting!.push({ key: 'staff_grantable_items', value: '["frame"]' });
});

test('live role/permission expiry and suspension block actions before the job runs', async () => {
  await reject(call(3, 'vipGrant', { userId: 8, level: 5 }), 403);
  row('staffRole', 2).expiresAt = new Date(Date.now() - 1);
  const me = await call(2, 'me');
  assert.equal(me.role, null); assert.equal(me.panels.superAdmin, false);
  await reject(call(2, 'vipGrant', { userId: 8, level: 5 }), 403);
  row('staffRole', 2).expiresAt = new Date(Date.now() + DAY);
  const panel = tables.staffPermission!.find(p => p.userId === 2 && p.permission === 'role_panel')!;
  panel.expiresAt = new Date(Date.now() - 1);
  assert.equal((await call(2, 'me')).panels.superAdmin, false);
  await reject(call(2, 'members'), 403);
});
test('appointments enforce subtree, self, conflict, role caps and audit metadata', async () => {
  await reject(call(2, 'appoint', { userId: 8, role: 'SUPER_ADMIN' }), 403);
  await reject(call(1, 'appoint', { userId: 1, role: 'ADMIN' }), 403);
  await reject(call(1, 'appoint', { userId: 2, role: 'ADMIN' }), 409);
  await reject(call(2, 'extend', { days: 31 }, { roleId: 3 }), 400);
  await reject(call(4, 'extend', { days: 1 }, { roleId: 3 }), 403);
  const next = await call(1, 'appoint', { displayId: 10008, role: 'ADMIN', allowedItemIds: ['frame'] });
  assert.equal(next.parentUserId, 1);
  assert.equal((await call(8, 'me')).role, 'ADMIN');
  assert.ok(events.some(e => e.userId === 8 && e.event === 'staff_access_changed'));
  const audit = tables.adminAuditLog!.find(r => r.action === 'STAFF_APPOINT')!;
  assert.equal(audit.adminId, 1); assert.equal(audit.ip, '127.0.0.1'); assert.equal(audit.userAgent, 'device | test');
});
test('permission delegation restricts SA to own keys and Managers alone control bans', async () => {
  await reject(call(2, 'permissions', { permissions: { grant_level: true } }, { roleId: 3 }), 403);
  await reject(call(2, 'permissions', { permissions: { ban_users: true } }, { roleId: 3 }), 403);
  await call(1, 'permissions', { permissions: { grant_vip: true }, expiresInDays: { grant_vip: 1 } }, { roleId: 3 });
  assert.ok((await call(3, 'me')).permissions.includes('grant_vip'));
  await call(1, 'permissions', { permissions: { role_panel: false } }, { roleId: 3 });
  await reject(call(3, 'vipGrant', { userId: 8, level: 5 }), 403);
});
test('standalone bans survive role loss while role-linked ban permission ends', async () => {
  await call(1, 'banHolderGrant', { userId: 8, days: 7 });
  await call(1, 'banHolderGrant', { userId: 3 });
  assert.equal((await call(8, 'me')).banSystem, true);
  await call(1, 'revoke', {}, { roleId: 3 });
  assert.equal((await call(3, 'me')).banSystem, false);
  assert.equal((await call(8, 'me')).banSystem, true);
  await reject(call(8, 'ban', { userId: 2, duration: '1d', reason: 'مخالفة' }), 403);
  const ban = await call(8, 'ban', { userId: 9, duration: '1d', reason: 'مخالفة' });
  assert.equal(row('user', 9).banSource, 'staff');
  assert.equal(ban.status, 'ACTIVE');
  await call(8, 'unban', {}, { userId: 9 });
  assert.equal(row('user', 9).isBanned, false);
  await call(1, 'banHolderRevoke', {}, { userId: 8 });
  await reject(call(8, 'ban', { userId: 9, duration: '1d', reason: 'مخالفة' }), 403);
});
test('revoking SA reparents Admins and preserves agency coverage; staff under a revoked Manager keep their term', async () => {
  await db.staffAgencyScope.create({ data: { staffUserId: 2, agencyId: 1001, kind: 'CREATED' } });
  await call(1, 'revoke', {}, { roleId: 2 });
  assert.equal(row('staffRole', 3).parentUserId, 1);
  assert.ok(tables.staffAgencyScope!.some(s => s.staffUserId === 1 && s.agencyId === 1001 && s.kind === 'ASSIGNED'));
  assert.equal((await call(3, 'me')).role, 'ADMIN');
  await call(15, 'revoke', {}, { roleId: 1 }, true);
  assert.equal(row('staffRole', 3).parentUserId, null);
  // Detached, not suspended: the Admin was given a term and keeps it.
  assert.equal((await call(3, 'me')).role, 'ADMIN');
  await call(15, 'parent', { parentUserId: 4 }, { roleId: 3 }, true);
  assert.equal(row('staffRole', 3).parentUserId, 4);
  assert.equal((await call(3, 'me')).role, 'ADMIN');
});
test('renewal creates history and retains the old checklist instead of defaulting disabled permissions on', async () => {
  await call(1, 'permissions', { permissions: { follow_agencies: false, grant_vip: true } }, { roleId: 3 });
  await call(1, 'revoke', {}, { roleId: 3 });
  const renewed = await call(1, 'renew', { days: 10 }, { roleId: 3 });
  assert.notEqual(renewed.id, 3);
  assert.equal(row('staffRole', 3).status, 'REVOKED');
  const me = await call(3, 'me');
  assert.ok(me.permissions.includes('grant_vip'));
  assert.equal(me.permissions.includes('follow_agencies'), false);
});
test('VIP original value and natural Level growth survive stacked grants and sweeps', async () => {
  const vip = await call(1, 'vipGrant', { userId: 8, level: 5 });
  assert.equal(row('user', 8).vipLevel, 5);
  assert.equal(earnedRewards.length, 0);
  await call(1, 'grantRevoke', {}, { id: vip.id });
  assert.equal(row('user', 8).vipLevel, 3);
  const first = await call(1, 'levelGrant', { userId: 8, level: 15 });
  const second = await call(1, 'levelGrant', { userId: 8, level: 20 });
  row('user', 8).xp = 8;
  await call(1, 'grantRevoke', {}, { id: first.id });
  assert.equal(row('user', 8).level, 20);
  row('temporaryEntitlement', second.id).expiresAt = new Date(Date.now() - 1);
  await service.sweepStaffExpiry();
  assert.equal(row('user', 8).level, 8);
  assert.ok(earnedRewards.some(r => r.type === 'LEVEL' && r.level === 8));
  assert.ok(tables.adminAuditLog!.some(r => r.action === 'STAFF_GRANT_EXPIRED' && r.adminId === 0));
});
test('temporary item revoke clears equipped frames, preserves permanent ownership and handles overlapping grants', async () => {
  const grant = await call(1, 'itemGrant', { userId: 8, itemId: 'frame' });
  row('user', 8).activeFrameId = 'frame'; row('user', 8).avatarFrameUrl = '/frame';
  await call(1, 'grantRevoke', {}, { id: grant.id });
  assert.equal(tables.userItem!.length, 0);
  assert.equal(row('user', 8).activeFrameId, null);
  await db.userItem.create({ data: { userId: 8, itemId: 'frame', expiresAt: null } });
  const permanent = await call(1, 'itemGrant', { userId: 8, itemId: 'frame' });
  assert.match(permanent.message, /دائم/);
  await call(1, 'grantRevoke', {}, { id: permanent.id });
  assert.equal(tables.userItem![0]!.expiresAt, null);
  tables.userItem = [];
  const first = await call(1, 'itemGrant', { userId: 8, itemId: 'frame' });
  const second = await call(1, 'itemGrant', { userId: 8, itemId: 'frame' });
  await call(1, 'grantRevoke', {}, { id: first.id });
  assert.equal(tables.userItem!.length, 1);
  await call(1, 'grantRevoke', {}, { id: second.id });
  assert.equal(tables.userItem!.length, 0);
});
test('role rewards extend with appointment and are removed on role expiry', async () => {
  await call(1, 'rewardItems', { itemIds: ['frame'] }, { roleId: 3 });
  const reward = tables.temporaryEntitlement!.find(g => g.staffRoleId === 3)!;
  await call(1, 'extend', { days: 10 }, { roleId: 3 });
  assert.equal(row('temporaryEntitlement', reward.id).expiresAt.getTime(), row('staffRole', 3).expiresAt.getTime());
  assert.equal(tables.userItem![0]!.expiresAt.getTime(), row('staffRole', 3).expiresAt.getTime());
  await service.sweepStaffExpiry(new Date(Date.now() + 41 * DAY));
  assert.equal(tables.userItem!.length, 0);
  assert.equal(row('staffRole', 3).status, 'EXPIRED');
});
test('out-of-scope agency lookup fails and audit reads are scoped and append-only', async () => {
  await reject(call(3, 'agency', {}, { id: 1002 }), 403);
  await call(1, 'vipGrant', { userId: 8, level: 5 });
  await call(4, 'vipGrant', { userId: 9, level: 5 });
  const audit = await call(1, 'audit');
  assert.equal(audit.rows.length, 1);
  assert.equal(audit.rows[0].adminId, 1);
  assert.equal((await call(3, 'audit')).rows.length, 0);
  assert.equal((await call(15, 'audit', {}, {}, true)).rows.length, 2);
});
test('failed compound appointment rolls back role, permissions, audit and all external effects', async () => {
  const roles = tables.staffRole!.length;
  await reject(call(1, 'appoint', { userId: 8, role: 'ADMIN', permissions: { invented_permission: true } }), 400);
  assert.equal(tables.staffRole!.length, roles);
  assert.equal(tables.adminAuditLog!.length, 0);
  assert.equal(events.length, 0);
  assert.equal(notifications.length, 0);
});
test('reward extension preserves the restore chain of overlapping seven-day items', async () => {
  await call(1, 'rewardItems', { itemIds: ['frame'] }, { roleId: 3 });
  const extra = await call(1, 'itemGrant', { userId: 3, itemId: 'frame' });
  await call(1, 'extend', { days: 10 }, { roleId: 3 });
  await call(1, 'rewardItems', { itemIds: [] }, { roleId: 3 });
  assert.equal(tables.userItem![0]!.expiresAt.getTime(), extra.expiresAt.getTime());
  await call(1, 'grantRevoke', {}, { id: extra.id });
  assert.equal(tables.userItem!.length, 0);
});
test('reward that outgrows original later ownership restores that ownership on revoke', async () => {
  const original = new Date(Date.now() + 35 * DAY);
  await db.userItem.create({ data: { userId: 3, itemId: 'frame', expiresAt: original } });
  await call(1, 'rewardItems', { itemIds: ['frame'] }, { roleId: 3 });
  await call(1, 'extend', { days: 10 }, { roleId: 3 });
  assert.ok(tables.userItem![0]!.expiresAt > original);
  await call(1, 'rewardItems', { itemIds: [] }, { roleId: 3 });
  assert.equal(tables.userItem![0]!.expiresAt.getTime(), original.getTime());
});
test('expired standalone ban permissions disappear immediately and are audited by the job', async () => {
  await call(1, 'banHolderGrant', { userId: 8, days: 1 });
  tables.staffPermission!.find(p => p.userId === 8)!.expiresAt = new Date(Date.now() - 1);
  assert.equal((await call(8, 'me')).banSystem, false);
  assert.equal((await call(1, 'banHolders')).some((p: Row) => p.userId === 8), false);
  await reject(call(8, 'bans'), 403);
  await service.sweepStaffExpiry();
  assert.ok(tables.adminAuditLog!.some(a => a.action === 'STAFF_PERMISSION_EXPIRED' && a.adminId === 0));
});
test('a Super Admin missing a default permission can still appoint; the Admin gets only what he holds', async () => {
  await call(1, 'permissions', { permissions: { follow_agencies: false } }, { roleId: 2 });
  const admin = await call(2, 'appoint', { userId: 9, role: 'ADMIN', days: 10 });
  assert.equal(admin.parentUserId, 2);
  const me = await call(9, 'me');
  assert.ok(me.permissions.includes('role_panel'));
  assert.ok(me.permissions.includes('manage_host_agency'));
  assert.equal(me.permissions.includes('follow_agencies'), false);
  // Asking for it explicitly is still refused.
  await reject(call(2, 'appoint', { userId: 10, role: 'ADMIN', days: 10, permissions: { follow_agencies: true } }), 403);
});
test('staff reward products come from the role-reward list without becoming grantable to users', async () => {
  tables.item!.push({ id: 'badge', type: 'BADGE', name: 'شارة Admin', assetUrl: '/badge', previewUrl: null });
  tables.appSetting!.push({ key: 'staff_role_rewards', value: JSON.stringify({ MANAGER: [], SUPER_ADMIN: [], ADMIN: ['badge'] }) });
  await call(1, 'rewardItems', { itemIds: ['badge'] }, { roleId: 3 });
  assert.deepEqual(row('staffRole', 3).rewardItemIds, ['badge']);
  await reject(call(1, 'allowedItems', { itemIds: ['badge'] }, { roleId: 3 }), 403);
  await reject(call(2, 'rewardItems', { itemIds: ['badge'] }, { roleId: 3 }), 403);
});
test('an id too large for the database is a clear 400, not a server error', async () => {
  await reject(call(1, 'lookup', {}, {}, false, { id: '100010100010' }), 400);
  await reject(call(1, 'vipGrant', { userId: 99999999999, level: 2 }), 400);
});
