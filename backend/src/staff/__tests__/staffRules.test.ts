import test from 'node:test';
import assert from 'node:assert/strict';
import * as r from '../staffRules';

test('rank and complete appointment matrix prohibit peer, superior and self appointment', () => {
  assert.deepEqual([r.rank(null), ...['ADMIN', 'SUPER_ADMIN', 'MANAGER'].map(r.rank)], [0, 1, 2, 3]);
  for (const actor of [null, ...r.ROLES]) for (const target of r.ROLES) {
    assert.equal(r.mayAppoint(actor, target), actor === 'MANAGER' && target !== 'MANAGER' || actor === 'SUPER_ADMIN' && target === 'ADMIN');
    assert.equal(r.mayAppoint(actor, target, true), false);
  }
});
const tree = [
  { userId: 1, role: 'MANAGER', parentUserId: null },
  { userId: 2, role: 'SUPER_ADMIN', parentUserId: 1 },
  { userId: 3, role: 'ADMIN', parentUserId: 2 },
  { userId: 4, role: 'ADMIN', parentUserId: 1 },
  { userId: 5, role: 'MANAGER', parentUserId: null },
  { userId: 6, role: 'ADMIN', parentUserId: 5 },
];
test('complete manage matrix respects each manager subtree and direct SA admins', () => {
  const permitted = ['1:2', '1:3', '1:4', '2:3', '5:6'];
  for (const actor of tree) for (const target of tree) assert.equal(r.mayManage(actor, target, tree), permitted.includes(`${actor.userId}:${target.userId}`));
});
test('Manager → SA A → Admin B → Agency 1001 cannot expose Agency 1002 to Admin B', () => {
  const scopes = [{ staffUserId: 3, agencyId: 1001 }, { staffUserId: 4, agencyId: 1002 }, { staffUserId: 6, agencyId: 1003 }];
  assert.deepEqual(r.scopeAgencies(tree, scopes, 3), [1001]);
  assert.deepEqual(r.scopeAgencies(tree, scopes, 2), [1001]);
  assert.deepEqual(r.scopeAgencies(tree, scopes, 1), [1001, 1002]);
  assert.deepEqual(r.scopeAgencies(tree, scopes, 5), [1003]);
  assert.deepEqual(r.subtree([{ userId: 1, parentUserId: 2, role: 'ADMIN' }, { userId: 2, parentUserId: 1, role: 'ADMIN' }], 1), [1, 2]);
});
test('catalog, holding matrix and defaults keep ban independent', () => {
  assert.equal(r.PERMISSION_CATALOG.length, 10);
  for (const p of r.PERMISSION_CATALOG) {
    assert.match(p.label, /[\u0600-\u06ff]/);
    assert.equal(r.mayHold('MANAGER', p.key), true);
    assert.equal(r.mayHold(null, p.key), p.key === 'ban_users');
    assert.equal(r.mayHold('ADMIN', p.key), p.key !== 'manage_admins');
    assert.equal(r.mayHold('SUPER_ADMIN', p.key), true);
  }
  assert.equal(r.mayHold('MANAGER', 'invented'), false);
  assert.deepEqual(r.defaultPermissions('ADMIN'), ['role_panel', 'manage_host_agency', 'follow_agencies']);
  assert.equal(r.defaultPermissions('SUPER_ADMIN').includes('ban_users'), false);
  assert.equal(r.defaultPermissions('MANAGER').includes('ban_users'), true);
});
test('duration bounds, fixed grants, exact expiry and extension arithmetic', () => {
  assert.equal(r.roleDays('MANAGER'), 30);
  for (const value of [0, -1, 366, 1.2, '7', null, NaN]) assert.equal(r.roleDays('MANAGER', value), null);
  assert.equal(r.roleDays('MANAGER', 365), 365);
  assert.equal(r.roleDays('SUPER_ADMIN', 30), 30);
  assert.equal(r.roleDays('SUPER_ADMIN', 31), null);
  assert.equal(r.roleDays('ADMIN', 1), null);
  assert.deepEqual(r.BAN_DURATIONS, { '1d': 1, '7d': 7, '30d': 30, '365d': 365, permanent: null });
  const now = new Date('2026-10-04T00:00:00Z');
  assert.equal(r.extendExpiry(new Date(now.getTime() - 1), now, 1).getTime(), now.getTime() + r.DAY);
  assert.equal(r.extendExpiry(new Date(now.getTime() + r.DAY), now, 7).getTime(), now.getTime() + 8 * r.DAY);
  assert.equal(r.isLive({ status: 'ACTIVE', expiresAt: now }, now), false);
  assert.equal(r.isLive({ status: 'ACTIVE', expiresAt: null }, now), true);
  assert.equal(r.isLive({ status: 'REVOKED', expiresAt: null }, now), false);
});
test('ban target matrix excludes self, platform staff, peers and superiors', () => {
  const target = { id: 9, isAdmin: false, isSuperAdmin: false, role: null as string | null };
  for (const actor of [null, ...r.ROLES]) for (const role of [null, ...r.ROLES]) {
    assert.equal(r.mayBan(1, actor, { ...target, role }), role === null || r.rank(actor) > r.rank(role));
  }
  assert.equal(r.mayBan(9, 'MANAGER', target), false);
  assert.equal(r.mayBan(1, 'MANAGER', { ...target, isAdmin: true }), false);
  assert.equal(r.mayBan(1, 'MANAGER', { ...target, isSuperAdmin: true }), false);
});
test('VIP3 → VIP5 grant → VIP3; higher natural growth survives and does not grant a lower tier', () => {
  const applied = r.applyValue(3, 2, 5, []);
  assert.deepEqual(applied, { allowed: true, previousValue: '3', value: 5 });
  assert.equal(r.restoreValue(applied.previousValue, 2, []), 3);
  assert.equal(r.restoreValue(applied.previousValue, 4, []), 4);
  assert.equal(r.restoreValue(applied.previousValue, 6, []), 6);
  assert.equal(r.applyValue(3, 4, 4, []).allowed, false);
});
test('Level grants preserve natural progress, earliest base and stacking in either expiry order', () => {
  const first = { value: 15, previousValue: '3' };
  const second = r.applyValue(15, 7, 20, [first]);
  assert.equal(second.previousValue, '3');
  assert.equal(second.value, 20);
  assert.equal(r.baseValue(20, 7, [first, second]), 7);
  assert.equal(r.restoreValue(first.previousValue, 7, [second]), 20);
  assert.equal(r.restoreValue(second.previousValue, 7, [first]), 15);
  assert.equal(r.restoreValue(second.previousValue, 7, []), 7);
  assert.equal(r.applyValue(15, 7, 15, [first]).allowed, true);
  assert.equal(r.applyValue(20, 21, 20, [first]).allowed, false);
});
test('item apply and early revoke preserve permanent, later and externally modified ownership', () => {
  const now = new Date('2026-10-04T00:00:00Z');
  const expiry = new Date(now.getTime() + 7 * r.DAY);
  const earlier = new Date(now.getTime() + r.DAY);
  const later = new Date(now.getTime() + 10 * r.DAY);
  assert.equal(r.applyItem(null, now).previousValue, 'none');
  assert.equal(r.applyItem(null, now).expiresAt.getTime(), expiry.getTime());
  assert.equal(r.applyItem({ expiresAt: null }, now).previousValue, 'permanent');
  assert.equal(r.applyItem({ expiresAt: later }, now).action, 'keep');
  assert.equal(r.applyItem({ expiresAt: expiry }, now).action, 'keep');
  const changed = r.applyItem({ expiresAt: earlier }, now);
  assert.equal(changed.previousValue, `until:${earlier.toISOString()}`);
  assert.deepEqual(r.revokeItem({ expiresAt: expiry }, expiry, changed.previousValue), { action: 'restore', expiresAt: earlier });
  assert.deepEqual(r.revokeItem({ expiresAt: expiry }, expiry, 'none'), { action: 'delete' });
  for (const existing of [null, { expiresAt: null }, { expiresAt: later }]) assert.equal(r.revokeItem(existing, expiry, 'none').action, 'keep');
  for (const previous of ['permanent', `later:${later.toISOString()}`]) assert.equal(r.revokeItem({ expiresAt: expiry }, expiry, previous).action, 'keep');
});
