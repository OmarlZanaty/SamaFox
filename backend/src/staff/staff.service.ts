import { Prisma, StaffRole, TemporaryEntitlement } from '@prisma/client';
import prisma from '../utils/prisma';
import { recordAdminAudit, AdminAuditInput } from '../services/adminAudit.service';
import { emitToUser, kickBannedUser } from '../services/socket.service';
import { createNotification } from '../services/notification.service';
import { invalidateBanCache } from '../utils/banGuard';
import { computeVipLevelWithOverrides, getVipThresholdOverrides, grantVipRewardsForRange } from '../services/vip.service';
import { calculateLevelWithOverrides, getLevelThresholdOverrides, grantLevelRewards } from '../services/xp.service';
import { computeAgencyEarnedCoins, memberTargetEarned } from '../agencies/agency.controller';
import { getBroadcastSeconds } from '../services/broadcast.service';
import * as rules from './staffRules';

type Db = Prisma.TransactionClient;
type Body = Record<string, any>;
export class StaffError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
function fail(status: number, message: string): never { throw new StaffError(status, message); }
const denied = (): never => fail(403, 'ليس لديك الصلاحية المطلوبة');
export function positiveId(value: unknown): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) fail(400, 'معرّف غير صالح');
  const id = Number(value);
  if (!Number.isSafeInteger(id) || id <= 0) fail(400, 'معرّف غير صالح');
  return id;
}
const liveWhere = (now: Date) => ({ status: 'ACTIVE', OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] });
const userSelect = { id: true, name: true, displayId: true, avatarUrl: true, vipLevel: true, level: true,
  isBanned: true, banExpiresAt: true } as const;
const itemSelect = { id: true, name: true, type: true, assetUrl: true, previewUrl: true } as const;
type Effect = () => Promise<unknown> | void;
export interface ActorContext {
  userId: number;
  dashboard?: boolean;
  ip?: string | null;
  userAgent?: string | null;
  reason?: string | null;
}
interface Context extends ActorContext { db: Db; now: Date; effects: Effect[]; access: Access }
export interface Access {
  role: StaffRole | null;
  permissions: rules.Permission[];
  tree: StaffRole[];
  ids: number[];
}

async function treeRows(db: Db): Promise<StaffRole[]> {
  const rows = await db.staffRole.findMany({ orderBy: [{ createdAt: 'desc' }, { id: 'desc' }] });
  // One current lineage per user prevents a former manager inheriting a new appointment.
  const latest = new Map<number, StaffRole>();
  for (const row of rows) if (!latest.has(row.userId)) latest.set(row.userId, row);
  return [...latest.values()];
}
export async function resolveAccess(db: Db, userId: number, now = new Date()): Promise<Access> {
  const tree = await treeRows(db);
  // A live appointment is valid in its own right. When the Manager above it
  // ends, the staff under him keep working for the term they were given
  // (spec B12); the dashboard re-attaches them to another Manager.
  const role = tree.find(r => r.userId === userId && rules.isLive(r, now)) ?? null;
  const rows = await db.staffPermission.findMany({ where: { userId, ...liveWhere(now) } });
  const permissions = role?.role === 'MANAGER' ? [...rules.permissionKeys] :
    [...new Set(rows.filter(p => p.staffRoleId === null ? p.permission === 'ban_users' : p.staffRoleId === role?.id)
      .filter(p => rules.mayHold(role?.role ?? null, p.permission)).map(p => p.permission as rules.Permission))];
  return { role, permissions, tree, ids: role ? rules.subtree(tree, userId) : [userId] };
}
function requirePermission(c: Context, key: string) {
  if (!c.dashboard && !c.access.permissions.includes(key as rules.Permission)) denied();
}
function manager(c: Context) { if (!c.dashboard && c.access.role?.role !== 'MANAGER') denied(); }
function noSelf(c: Context, userId: number) { if (c.userId === userId) fail(403, 'لا يمكنك تنفيذ العملية على نفسك'); }
function checkTarget(c: Context, user: { id: number; isBanned: boolean; banExpiresAt: Date | null }) {
  noSelf(c, user.id);
  if (user.isBanned && (!user.banExpiresAt || user.banExpiresAt > c.now)) fail(400, 'المستخدم محظور');
}
async function targetUser(c: Context, body: Body) {
  if (body.userId == null && body.displayId == null) fail(400, 'معرّف المستخدم مطلوب');
  const user = await c.db.user.findUnique({ where: body.userId != null ? { id: positiveId(body.userId) } :
    { displayId: positiveId(body.displayId) }, select: userSelect });
  if (!user) return fail(404, 'المستخدم غير موجود');
  return user;
}
function audit(c: Context, action: string, targetType: string, targetId: number | string,
  targetUserId?: number | null, before?: unknown, after?: unknown) {
  const input: AdminAuditInput = { adminId: c.userId, action, targetType, targetId, targetUserId,
    before, after, ip: c.ip, userAgent: c.userAgent, reason: c.reason };
  return recordAdminAudit(input, c.db);
}
function changed(c: Context, userId: number, body = 'تم تحديث صلاحيات الإدارة الخاصة بك') {
  c.effects.push(() => emitToUser(userId, 'staff_access_changed', { userId }));
  notify(c, userId, body);
}
function notify(c: Context, userId: number, body: string) {
  c.effects.push(() => createNotification({ userId, actorId: c.userId || null, type: 'STAFF_UPDATE',
    title: 'نظام الإدارة', body, data: { userId } }));
}
async function readSetting<T>(db: Db, key: string, fallback: T): Promise<T> {
  const row = await db.appSetting.findUnique({ where: { key } });
  return row ? JSON.parse(row.value) as T : fallback;
}
const pool = (db: Db) => readSetting<string[]>(db, 'staff_grantable_items', []);
const rewards = (db: Db) => readSetting<Record<rules.StaffRoleName, string[]>>(db, 'staff_role_rewards', { MANAGER: [], SUPER_ADMIN: [], ADMIN: [] });
function itemIds(value: unknown): string[] {
  if (!Array.isArray(value) || value.some(id => typeof id !== 'string' || !id.trim())) return fail(400, 'قائمة المنتجات غير صالحة');
  return [...new Set(value as string[])];
}
/**
 * Products an actor may hand out. 'grant' = what may be given to users (the
 * dashboard pool, narrowed to the actor's own list below Manager). 'reward' =
 * perks for staff themselves (Admin Frame / Badge …), which are usually NOT in
 * the grantable pool: the dashboard's role-reward list counts too, so a Manager
 * can pick them without making them grantable to every user.
 */
async function assignableItems(c: Context, mode: 'grant' | 'reward'): Promise<string[]> {
  const available = await pool(c.db);
  const own = c.access.role?.role === 'MANAGER' ? available : (c.access.role?.allowedItemIds ?? []).filter(id => available.includes(id));
  if (mode === 'grant') return own;
  const config = await rewards(c.db);
  const rewardIds = c.access.role?.role === 'MANAGER' ? Object.values(config).flat() : [];
  return [...new Set([...own, ...rewardIds])];
}
async function validateItems(c: Context, value: unknown, mode: 'grant' | 'reward' = 'grant'): Promise<string[]> {
  const ids = itemIds(value);
  if (await c.db.item.count({ where: { id: { in: ids } } }) !== ids.length) fail(400, 'أحد المنتجات غير موجود');
  if (!c.dashboard) {
    const allowed = await assignableItems(c, mode);
    if (ids.some(id => !allowed.includes(id))) denied();
  }
  return ids;
}
async function managedRole(c: Context, id: number, readOnly = false): Promise<StaffRole> {
  const role = await c.db.staffRole.findUnique({ where: { id } });
  if (!role) return fail(404, 'التعيين غير موجود');
  if (!(c.dashboard && readOnly)) noSelf(c, role.userId);
  if (!c.dashboard && (!c.access.role || !rules.mayManage(c.access.role, role,
    [...c.access.tree.filter(r => r.userId !== role.userId), role]))) denied();
  return role;
}
async function agencyIds(c: Context, userId = c.userId): Promise<number[]> {
  const scopes = await c.db.staffAgencyScope.findMany();
  return rules.scopeAgencies(c.access.tree, scopes, userId);
}
async function scopedAgency(c: Context, id: number) {
  if (!(await agencyIds(c)).includes(id)) fail(403, 'الوكالة خارج نطاق صلاحياتك');
  const agency = await c.db.chargingAgency.findFirst({ where: { id, type: 'HOSTING' },
    select: { id: true, agencyName: true, status: true, createdAt: true, user: { select: userSelect }, _count: { select: { members: true } } } });
  if (!agency) return fail(404, 'الوكالة غير موجودة');
  return agency;
}

async function naturalValue(c: Context, userId: number, type: string): Promise<{ current: number; natural: number }> {
  const user = await c.db.user.findUniqueOrThrow({ where: { id: userId }, select: { vipLevel: true, level: true, totalRecharge: true, xp: true } });
  return type === 'VIP' ? { current: user.vipLevel, natural: computeVipLevelWithOverrides(user.totalRecharge, await getVipThresholdOverrides()) } :
    { current: user.level, natural: calculateLevelWithOverrides(user.xp, await getLevelThresholdOverrides(c.db)) };
}
async function applyItemGrant(c: Context, userId: number, itemId: string, expiresAt: Date,
  source = 'GRANT', staffRoleId: number | null = null) {
  const item = await c.db.item.findUnique({ where: { id: itemId }, select: itemSelect });
  if (!item) return fail(404, 'المنتج غير موجود');
  const existing = await c.db.userItem.findUnique({ where: { userId_itemId: { userId, itemId } } });
  const decision = rules.applyItem(existing, c.now, expiresAt);
  if (decision.action === 'create') await c.db.userItem.create({ data: { userId, itemId, expiresAt } });
  if (decision.action === 'update') await c.db.userItem.update({ where: { userId_itemId: { userId, itemId } }, data: { expiresAt } });
  const grant = await c.db.temporaryEntitlement.create({ data: { userId, type: 'ITEM', itemId, itemType: item.type,
    previousValue: decision.previousValue, source, staffRoleId, grantedById: c.userId || null, expiresAt } });
  await audit(c, 'STAFF_GRANT_ITEM', 'grant', grant.id, userId, existing, grant);
  notify(c, userId, 'تم منحك منتجاً مؤقتاً');
  return { ...grant, message: decision.previousValue === 'permanent' ? 'المستخدم يملك المنتج بشكل دائم بالفعل' : 'تم منح المنتج' };
}

async function endGrant(c: Context, grant: TemporaryEntitlement, status: 'EXPIRED' | 'REVOKED') {
  if (grant.status !== 'ACTIVE') return grant;
  await c.db.temporaryEntitlement.update({ where: { id: grant.id }, data: { status, endedAt: c.now, endedById: c.userId } });
  if (grant.type === 'VIP' || grant.type === 'LEVEL') {
    const { natural } = await naturalValue(c, grant.userId, grant.type);
    const remaining = await c.db.temporaryEntitlement.findMany({ where: { userId: grant.userId, type: grant.type, status: 'ACTIVE', expiresAt: { gt: c.now } } });
    const value = rules.restoreValue(grant.previousValue, natural, remaining);
    await c.db.user.update({ where: { id: grant.userId }, data: grant.type === 'VIP' ? { vipLevel: value } : { level: value } });
    // Rewards earned while a temporary column masked progression must still be delivered.
    const previous = Number(grant.previousValue ?? 0);
    if (grant.type === 'VIP') c.effects.push(() => grantVipRewardsForRange(grant.userId, previous, natural));
    else for (let level = previous + 1; level <= natural; level++) {
      const earnedLevel = level;
      c.effects.push(() => grantLevelRewards(grant.userId, earnedLevel));
    }
  } else if (grant.itemId) {
    const itemId = grant.itemId;
    const existing = await c.db.userItem.findUnique({ where: { userId_itemId: { userId: grant.userId, itemId } } });
    // Splice overlapping grants out of the restore chain: revoking the later one
    // must not resurrect an earlier grant that was already withdrawn.
    const other = await c.db.temporaryEntitlement.findMany({ where: { userId: grant.userId, itemId, type: 'ITEM', status: 'ACTIVE', id: { not: grant.id } } });
    for (const next of other) {
      if (next.previousValue === `until:${grant.expiresAt.toISOString()}` || next.previousValue === `later:${grant.expiresAt.toISOString()}`) {
        await c.db.temporaryEntitlement.update({ where: { id: next.id }, data: { previousValue: grant.previousValue } });
      }
    }
    if (status === 'REVOKED' || grant.source === 'ROLE_REWARD') {
      const decision = rules.revokeItem(existing, grant.expiresAt, grant.previousValue);
      const remaining = other.filter(g => g.expiresAt > c.now).sort((a, b) => b.expiresAt.getTime() - a.expiresAt.getTime());
      if (decision.action !== 'keep' && remaining.length) {
        const expiry = decision.expiresAt && decision.expiresAt > remaining[0]!.expiresAt ? decision.expiresAt : remaining[0]!.expiresAt;
        await c.db.userItem.update({ where: { userId_itemId: { userId: grant.userId, itemId } }, data: { expiresAt: expiry } });
      } else if (decision.action === 'delete') {
        await c.db.user.updateMany({ where: { id: grant.userId, activeFrameId: itemId }, data: { activeFrameId: null, avatarFrameUrl: null } });
        await c.db.userItem.deleteMany({ where: { userId: grant.userId, itemId, expiresAt: grant.expiresAt } });
      } else if (decision.action === 'restore') {
        await c.db.userItem.updateMany({ where: { userId: grant.userId, itemId, expiresAt: grant.expiresAt }, data: { expiresAt: decision.expiresAt } });
      }
    }
  }
  await audit(c, status === 'EXPIRED' ? 'STAFF_GRANT_EXPIRED' : 'STAFF_GRANT_REVOKE', 'grant', grant.id, grant.userId, grant, { status });
  return { ...grant, status };
}

async function syncRewards(c: Context, role: StaffRole) {
  const config = await rewards(c.db);
  const desired = [...new Set([...(config[role.role as rules.StaffRoleName] ?? []), ...role.rewardItemIds])];
  const active = await c.db.temporaryEntitlement.findMany({ where: { staffRoleId: role.id, source: 'ROLE_REWARD', status: 'ACTIVE' } });
  for (const grant of active) {
    if (!desired.includes(grant.itemId!)) await endGrant(c, grant, 'REVOKED');
    else if (grant.expiresAt.getTime() !== role.expiresAt.getTime()) {
      const existing = await c.db.userItem.findUnique({ where: { userId_itemId: { userId: role.userId, itemId: grant.itemId! } } });
      let previousValue = grant.previousValue;
      if (!existing) await c.db.userItem.create({ data: { userId: role.userId, itemId: grant.itemId!, expiresAt: role.expiresAt } });
      else if (existing.expiresAt && existing.expiresAt < role.expiresAt) {
        // A reward that originally changed nothing may start extending an owned
        // item after a role extension. It now needs a restorable baseline.
        if (previousValue?.startsWith('later:')) previousValue = `until:${previousValue.slice(6)}`;
        await c.db.userItem.update({ where: { id: existing.id }, data: { expiresAt: role.expiresAt } });
      }
      const linked = await c.db.temporaryEntitlement.findMany({ where: { userId: role.userId, itemId: grant.itemId,
        type: 'ITEM', status: 'ACTIVE', id: { not: grant.id } } });
      for (const next of linked) {
        for (const prefix of ['until:', 'later:']) if (next.previousValue === `${prefix}${grant.expiresAt.toISOString()}`) {
          await c.db.temporaryEntitlement.update({ where: { id: next.id }, data: { previousValue: `${prefix}${role.expiresAt.toISOString()}` } });
        }
      }
      await c.db.temporaryEntitlement.update({ where: { id: grant.id }, data: { expiresAt: role.expiresAt, previousValue } });
    }
  }
  for (const id of desired) if (!active.some(g => g.itemId === id)) await applyItemGrant(c, role.userId, id, role.expiresAt, 'ROLE_REWARD', role.id);
}

async function endRole(c: Context, role: StaffRole, status: 'EXPIRED' | 'REVOKED') {
  if (role.status !== 'ACTIVE') return role;
  const ended = await c.db.staffRole.update({ where: { id: role.id }, data: { status, endedAt: c.now, endedById: c.userId, endReason: c.reason } });
  const permissions = await c.db.staffPermission.findMany({ where: { staffRoleId: role.id, status: 'ACTIVE' } });
  for (const permission of permissions) {
    await c.db.staffPermission.update({ where: { id: permission.id }, data: { status, endedAt: c.now, endedById: c.userId } });
    await audit(c, status === 'EXPIRED' ? 'STAFF_PERMISSION_EXPIRED' : 'STAFF_PERMISSION_REVOKE', 'staff', role.id, role.userId, permission, { status });
  }
  const grants = await c.db.temporaryEntitlement.findMany({ where: { staffRoleId: role.id, source: 'ROLE_REWARD', status: 'ACTIVE' } });
  for (const grant of grants) await endGrant(c, grant, status);
  if (role.role !== 'ADMIN') {
    const parentUserId = role.role === 'SUPER_ADMIN' ? role.parentUserId : null;
    const children = await c.db.staffRole.findMany({ where: { parentUserId: role.userId, status: 'ACTIVE' } });
    for (const child of children) {
      await c.db.staffRole.update({ where: { id: child.id }, data: { parentUserId } });
      await audit(c, 'STAFF_REPARENT', 'staff', child.id, child.userId, { parentUserId: role.userId }, { parentUserId });
      changed(c, child.userId);
      for (const descendant of rules.subtree(c.access.tree, child.userId).filter(id => id !== child.userId)) changed(c, descendant);
    }
    if (parentUserId) {
      const scopes = await c.db.staffAgencyScope.findMany({ where: { staffUserId: role.userId } });
      for (const scope of scopes) await c.db.staffAgencyScope.upsert({ where: { staffUserId_agencyId: { staffUserId: parentUserId, agencyId: scope.agencyId } },
        update: {}, create: { staffUserId: parentUserId, agencyId: scope.agencyId, kind: 'ASSIGNED', assignedById: c.userId } });
    }
  }
  // Retain the exact checklist for renewal; millisecond timestamps alone cannot
  // distinguish a permission switched off just before the role was withdrawn.
  await audit(c, status === 'EXPIRED' ? 'STAFF_EXPIRED' : 'STAFF_REVOKE', 'staff', role.id, role.userId,
    { ...role, permissions: permissions.filter(p => p.expiresAt === null || (status === 'EXPIRED' ? p.expiresAt >= role.expiresAt : p.expiresAt > c.now)) }, ended);
  changed(c, role.userId, status === 'EXPIRED' ? 'انتهت مدة الإدارة الخاصة بك' : 'تم سحب الإدارة الخاصة بك');
  return ended;
}

async function setPermissions(c: Context, role: StaffRole, values: unknown, terms: Body = {}) {
  if (!values || typeof values !== 'object' || Array.isArray(values)) fail(400, 'الصلاحيات غير صالحة');
  if (!terms || typeof terms !== 'object' || Array.isArray(terms) || Object.keys(terms).some(key => !Object.prototype.hasOwnProperty.call(values, key))) fail(400, 'مدد الصلاحيات غير صالحة');
  for (const [key, enabled] of Object.entries(values as Body)) {
    if (typeof enabled !== 'boolean' || !rules.mayHold(role.role, key) || role.role === 'MANAGER') fail(400, 'صلاحية غير متاحة لهذا الدور');
    if (key === 'ban_users') manager(c);
    else if (!c.dashboard && c.access.role?.role === 'SUPER_ADMIN') requirePermission(c, key);
    const days = terms[key];
    if (days != null && !rules.PERMISSION_DAYS.includes(days)) fail(400, 'مدة الصلاحية غير صالحة');
    const previous = await c.db.staffPermission.findMany({ where: { staffRoleId: role.id, permission: key, status: 'ACTIVE' } });
    await c.db.staffPermission.updateMany({ where: { staffRoleId: role.id, permission: key, status: 'ACTIVE' },
      data: { status: 'REVOKED', endedAt: c.now, endedById: c.userId } });
    const next = enabled ? await c.db.staffPermission.create({ data: { userId: role.userId, staffRoleId: role.id,
      permission: key, grantedById: c.userId, expiresAt: days == null ? null : new Date(c.now.getTime() + days * rules.DAY) } }) : null;
    await audit(c, enabled ? 'STAFF_PERMISSION_GRANT' : 'STAFF_PERMISSION_REVOKE', 'staff', role.id, role.userId, previous, next);
  }
}

async function appoint(c: Context, body: Body, previous?: StaffRole) {
  const user = await targetUser(c, body);
  checkTarget(c, user);
  const role = String(body.role);
  if (!rules.ROLES.includes(role as rules.StaffRoleName)) fail(400, 'نوع الإدارة غير صالح');
  if (c.dashboard ? role !== 'MANAGER' && !previous : !rules.mayAppoint(c.access.role?.role ?? null, role)) denied();
  if (c.dashboard && body.days == null) fail(400, 'مدة الإدارة مطلوبة');
  const days = rules.roleDays(c.dashboard ? 'MANAGER' : c.access.role?.role ?? '', body.days);
  if (days === null) fail(400, 'مدة الإدارة غير صالحة');
  const existing = await c.db.staffRole.findFirst({ where: { userId: user.id, status: 'ACTIVE' } });
  if (existing) {
    if (rules.isLive(existing, c.now)) fail(409, 'للمستخدم إدارة نشطة؛ قم بالتمديد أو السحب أولاً');
    await endRole({ ...c, userId: 0 }, existing, 'EXPIRED');
  }
  // A Super Admin hands on only what he holds himself. Defaults and a renewal's
  // copied checklist / product lists are narrowed to that instead of refusing
  // the whole appointment; anything he names explicitly is still checked (403).
  const narrowPermissions = !c.dashboard && c.access.role?.role === 'SUPER_ADMIN';
  const holdable = (p: Body = {}) => narrowPermissions
    ? Object.fromEntries(Object.entries(p).filter(([key]) => c.access.permissions.includes(key as rules.Permission))) : p;
  const narrowItems = async (ids: unknown, mode: 'grant' | 'reward') => {
    if (!previous || c.dashboard) return ids ?? [];
    const allowed = await assignableItems(c, mode);
    return itemIds(ids ?? []).filter(id => allowed.includes(id));
  };
  const allowedItemIds = await validateItems(c, await narrowItems(body.allowedItemIds, 'grant'));
  const rewardItemIds = await validateItems(c, await narrowItems(body.rewardItemIds, 'reward'), 'reward');
  const next = await c.db.staffRole.create({ data: { userId: user.id, role,
    assignedById: c.dashboard ? null : c.userId, parentUserId: previous ? previous.parentUserId : c.dashboard ? null : c.userId,
    expiresAt: new Date(c.now.getTime() + days! * rules.DAY), allowedItemIds, rewardItemIds } });
  if (role !== 'MANAGER') {
    const defaults = holdable(Object.fromEntries(rules.defaultPermissions(role as rules.StaffRoleName).map(key => [key, true])));
    // Renewals copy the old checklist rather than silently re-enabling defaults.
    const permissions = previous ? holdable(body.permissions) : { ...defaults, ...(body.permissions ?? {}) };
    const terms = Object.fromEntries(Object.entries(body.expiresInDays ?? {}).filter(([key]) => key in permissions));
    await setPermissions(c, next, permissions, terms);
  }
  await syncRewards(c, next);
  await audit(c, previous ? 'STAFF_RENEW' : 'STAFF_APPOINT', 'staff', next.id, user.id,
    previous ?? null, { ...next, oldExpiresAt: previous?.expiresAt ?? null, newExpiresAt: next.expiresAt });
  changed(c, user.id, previous ? 'تم تجديد مدة الإدارة الخاصة بك' : 'تم تعيينك في نظام الإدارة');
  return next;
}

async function agencySummary(c: Context, id: number, detail = false) {
  const agency = await c.db.chargingAgency.findFirst({ where: { id, type: 'HOSTING' },
    select: { id: true, agencyName: true, createdAt: true, status: true, user: { select: userSelect }, _count: { select: { members: true } } } });
  if (!agency) return null;
  const scopes = await c.db.staffAgencyScope.findMany({ where: { agencyId: id } });
  const staff = await c.db.user.findMany({ where: { id: { in: scopes.map(s => s.staffUserId) } }, select: userSelect });
  const production = await computeAgencyEarnedCoins(id);
  const base = { id: agency.id, agencyName: agency.agencyName, status: agency.status, createdAt: agency.createdAt,
    owner: agency.user, membersCount: agency._count.members, production,
    creator: staff.find(u => scopes.some(s => s.kind === 'CREATED' && s.staffUserId === u.id)) ?? null,
    followers: staff.filter(u => scopes.some(s => s.kind === 'ASSIGNED' && s.staffUserId === u.id)) };
  if (!detail) return base;
  const members = await c.db.agencyMember.findMany({ where: { agencyId: id }, include: { user: { select: userSelect } } });
  const from = new Date(Date.UTC(c.now.getUTCFullYear(), c.now.getUTCMonth(), 1));
  const hosts = await Promise.all(members.map(async m => ({ user: m.user, role: m.role, joinedAt: m.joinedAt,
    target: await memberTargetEarned(m), broadcastHours: (await getBroadcastSeconds(m.userId, from, c.now)) / 3600 })));
  return { ...base, hosts };
}

function statusFilter(value: unknown, allowed: string[]): string | undefined {
  if (value == null || value === '') return undefined;
  if (typeof value !== 'string' || !allowed.includes(value)) fail(400, 'الحالة غير صالحة');
  return value as string;
}
/**
 * Attach the people a row points at ({field}Id → {field}), so the app and the
 * dashboard can say "أحمد منح محمد VIP 5" instead of printing raw ids.
 */
async function withPeople<T extends Record<string, any>>(c: Context, rows: T[], fields: string[]): Promise<T[]> {
  const ids = [...new Set(rows.flatMap(r => fields.map(f => r[`${f}Id`])).filter((id): id is number => typeof id === 'number' && id > 0))];
  if (!ids.length) return rows;
  const users = await c.db.user.findMany({ where: { id: { in: ids } }, select: userSelect });
  return rows.map(r => ({ ...r, ...Object.fromEntries(fields.map(f => [f, users.find(u => u.id === r[`${f}Id`]) ?? null])) }));
}
/**
 * Whose operations this actor oversees: his subtree, plus anyone his subtree
 * gave نظام الحظر to without a role — a Manager must see the bans made with
 * the permission he handed out.
 */
async function overseenIds(c: Context): Promise<number[]> {
  const delegates = await c.db.staffPermission.findMany({
    where: { permission: 'ban_users', staffRoleId: null, grantedById: { in: c.access.ids } }, select: { userId: true },
  });
  return [...new Set([...c.access.ids, ...delegates.map(d => d.userId)])];
}
async function auditRows(c: Context, query: Body, own?: number) {
  const page = query.page == null ? 1 : positiveId(query.page);
  const actorId = query.actorId == null ? undefined : query.actorId === '0' || query.actorId === 0 ? 0 : positiveId(query.actorId);
  const action = query.action == null ? undefined : String(query.action);
  if (action && !action.startsWith('STAFF_')) fail(400, 'نوع العملية غير صالح');
  const where: Prisma.AdminAuditLogWhereInput = { action: action ?? { startsWith: 'STAFF_' },
    adminId: own ?? actorId, ...(!c.dashboard && own == null ?
      { AND: c.access.role?.role === 'ADMIN' || !c.access.role ? [{ adminId: c.userId }] :
        [{ OR: [{ adminId: { in: await overseenIds(c) } }, { targetUserId: { in: c.access.ids } }] }] } : {}) };
  const [rows, total] = await Promise.all([c.db.adminAuditLog.findMany({ where, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], skip: (page - 1) * 50, take: 50 }), c.db.adminAuditLog.count({ where })]);
  return { rows: await withPeople(c, rows.map(r => ({ ...r, actorId: r.adminId })), ['actor', 'targetUser']), page, total, pageSize: 50 };
}

export type Operation = 'me' | 'catalog' | 'lookup' | 'members' | 'member' | 'appoint' | 'extend' | 'renew' | 'revoke' |
  'permissions' | 'allowedItems' | 'rewardItems' | 'banHolders' | 'banHolderGrant' | 'banHolderRevoke' |
  'grantable' | 'pool' | 'poolSet' | 'roleRewards' | 'roleRewardsSet' | 'vipGrant' | 'levelGrant' | 'itemGrant' |
  'grants' | 'grantRevoke' | 'agencies' | 'agency' | 'agencyCreate' | 'followerAdd' | 'followerRemove' |
  'ban' | 'unban' | 'bans' | 'audit' | 'parent';

const managerOperations: Operation[] = ['banHolders', 'banHolderGrant', 'banHolderRevoke', 'pool', 'poolSet', 'roleRewards', 'roleRewardsSet', 'parent'];
const managementOperations: Operation[] = ['members', 'member', 'appoint', 'extend', 'renew', 'revoke', 'permissions', 'allowedItems', 'rewardItems', 'followerAdd', 'followerRemove'];
function authorizeRole(c: Context, op: Operation) {
  if (c.dashboard || ['me', 'catalog'].includes(op)) return;
  const banOnlyRoute = ['ban', 'unban', 'bans', 'lookup', 'audit'].includes(op);
  if (!c.access.role && !(banOnlyRoute && c.access.permissions.includes('ban_users'))) denied();
  if (managerOperations.includes(op)) manager(c);
  if (managementOperations.includes(op) && !['MANAGER', 'SUPER_ADMIN'].includes(c.access.role?.role ?? '')) denied();
}
function authorizePermission(c: Context, op: Operation) {
  if (c.dashboard || ['me', 'catalog'].includes(op)) return;
  const banRoute = ['ban', 'unban', 'bans'].includes(op);
  if (banRoute) requirePermission(c, 'ban_users');
  else if (c.access.role) requirePermission(c, 'role_panel');
  if (managementOperations.includes(op)) requirePermission(c, 'manage_admins');
  const needed: Partial<Record<Operation, rules.Permission>> = {
    vipGrant: 'grant_vip', levelGrant: 'grant_level', agencyCreate: 'manage_host_agency',
    agencies: 'follow_agencies', agency: 'follow_agencies', followerAdd: 'manage_host_agency', followerRemove: 'manage_host_agency',
  };
  if (needed[op]) requirePermission(c, needed[op]!);
}

async function scopeGuard(c: Context, op: Operation, body: Body, params: Body) {
  if (params.roleId != null) await managedRole(c, positiveId(params.roleId), op === 'member');
  if (['agency', 'followerAdd', 'followerRemove'].includes(op)) await scopedAgency(c, positiveId(params.id));
  if (['followerAdd', 'followerRemove'].includes(op)) {
    const userId = positiveId(body.staffUserId ?? params.staffUserId);
    const role = c.access.tree.find(r => r.userId === userId && rules.isLive(r, c.now));
    if (!role) fail(404, 'الإداري غير موجود');
    await managedRole(c, role!.id);
  }
  if (op === 'grantRevoke') {
    const grant = await c.db.temporaryEntitlement.findUnique({ where: { id: positiveId(params.id) } });
    if (!grant) fail(404, 'المنحة غير موجودة');
    noSelf(c, grant!.userId);
    if (grant!.source !== 'GRANT' || !grant!.grantedById || !c.access.ids.includes(grant!.grantedById)) denied();
    requirePermission(c, grant!.type === 'VIP' ? 'grant_vip' : grant!.type === 'LEVEL' ? 'grant_level' : rules.itemPermission(grant!.itemType ?? '') ?? 'invalid');
  }
}

async function action(c: Context, op: Operation, body: Body, params: Body, query: Body): Promise<unknown> {
  if (op === 'me') {
    const r = c.access.role;
    const assignedBy = r?.assignedById ? await c.db.user.findUnique({ where: { id: r.assignedById }, select: { id: true, name: true, displayId: true } }) : null;
    const latest = c.access.tree.find(row => row.userId === c.userId);
    const ban = c.access.permissions.includes('ban_users');
    const panel = c.access.permissions.includes('role_panel');
    return { role: r?.role ?? null, roleId: r?.id ?? null, status: r?.status ?? (latest && latest.status === 'ACTIVE' && latest.expiresAt <= c.now ? 'EXPIRED' : latest?.status ?? null),
      startedAt: r?.startedAt ?? null, expiresAt: r?.expiresAt ?? null, assignedBy, permissions: c.access.permissions, banSystem: ban,
      panels: { manager: r?.role === 'MANAGER', superAdmin: r?.role === 'SUPER_ADMIN' && panel, admin: r?.role === 'ADMIN' && panel, ban },
      allowedItemIds: r?.role === 'MANAGER' ? await pool(c.db) : r?.allowedItemIds ?? [], rank: rules.rank(r?.role) };
  }
  if (op === 'catalog') return rules.PERMISSION_CATALOG;
  if (op === 'lookup') {
    const id = positiveId(query.id);
    // The ID people see and type is the displayId; the row id is the fallback.
    const user = await c.db.user.findUnique({ where: { displayId: id }, select: userSelect }) ?? await c.db.user.findUnique({ where: { id }, select: userSelect });
    if (!user) fail(404, 'المستخدم غير موجود');
    return { ...user, isBanned: user.isBanned && (user.banExpiresAt === null || user.banExpiresAt > c.now),
      staffRole: c.access.tree.find(r => r.userId === user.id && rules.isLive(r, c.now)) ?? null };
  }
  if (op === 'members') {
    const status = statusFilter(query.status, ['ACTIVE', 'EXPIRED', 'REVOKED']);
    const role = statusFilter(query.role, rules.ROLES);
    const rows = await c.db.staffRole.findMany({ where: { role, ...(!c.dashboard ? { userId: { in: c.access.ids.filter(id => id !== c.userId) } } : {}) }, orderBy: { id: 'desc' } });
    const ids = [...new Set(rows.flatMap(r => [r.userId, r.parentUserId, r.assignedById]).filter((id): id is number => id != null))];
    const users = await c.db.user.findMany({ where: { id: { in: ids } }, select: userSelect });
    return rows.map(r => ({ ...r, status: r.status === 'ACTIVE' && r.expiresAt <= c.now ? 'EXPIRED' : r.status,
      user: users.find(u => u.id === r.userId), parent: users.find(u => u.id === r.parentUserId) ?? null,
      assignedBy: users.find(u => u.id === r.assignedById) ?? null }))
      .filter(r => !status || r.status === status);
  }
  if (op === 'member') {
    const role = await managedRole(c, positiveId(params.roleId), true);
    return { user: await c.db.user.findUnique({ where: { id: role.userId }, select: userSelect }), role,
      permissions: await c.db.staffPermission.findMany({ where: { staffRoleId: role.id }, orderBy: { id: 'desc' } }),
      allowedItemIds: role.allowedItemIds, rewardItemIds: role.rewardItemIds,
      agencies: (await Promise.all((await agencyIds(c, role.userId)).map(id => agencySummary(c, id)))).filter(Boolean),
      audit: (await auditRows(c, {}, role.userId)).rows };
  }
  if (op === 'appoint') return appoint(c, body);
  if (['extend', 'renew', 'revoke', 'permissions', 'allowedItems', 'rewardItems', 'parent'].includes(op)) {
    const role = await managedRole(c, positiveId(params.roleId));
    if (op === 'revoke') return role.expiresAt <= c.now ? endRole({ ...c, userId: 0 }, role, 'EXPIRED') : endRole(c, role, 'REVOKED');
    if (op === 'renew') {
      if (rules.isLive(role, c.now)) fail(409, 'الإدارة نشطة؛ استخدم التمديد');
      if (role.status === 'ACTIVE') await endRole({ ...c, userId: 0 }, role, 'EXPIRED');
      const endAudit = await c.db.adminAuditLog.findFirst({ where: { targetType: 'staff', targetId: String(role.id),
        action: { in: ['STAFF_REVOKE', 'STAFF_EXPIRED'] } }, orderBy: { id: 'desc' } });
      const snapshot = (endAudit?.before as { permissions?: Array<{ permission: string; expiresAt: string | null; grantedAt: string }> } | null)?.permissions;
      const historical = await c.db.staffPermission.findMany({ where: { staffRoleId: role.id }, orderBy: { id: 'desc' } });
      const latest = new Map<string, typeof historical[number]>();
      for (const p of historical) if (!latest.has(p.permission)) latest.set(p.permission, p);
      const end = role.endedAt ?? c.now;
      const copied = snapshot ? snapshot.map(p => ({ ...p, expiresAt: p.expiresAt ? new Date(p.expiresAt) : null, grantedAt: new Date(p.grantedAt) })) :
        [...latest.values()].filter(p => p.status === 'ACTIVE' || p.endedAt?.getTime() === end.getTime());
      return appoint(c, { userId: role.userId, role: role.role, days: body.days,
        allowedItemIds: role.allowedItemIds, rewardItemIds: role.rewardItemIds,
        permissions: Object.fromEntries(copied.map(p => [p.permission, true])),
        expiresInDays: Object.fromEntries(copied.map(p => [p.permission, p.expiresAt ? Math.max(1, Math.round((p.expiresAt.getTime() - p.grantedAt.getTime()) / rules.DAY)) : null])) }, role);
    }
    if (!rules.isLive(role, c.now)) fail(409, 'انتهت الإدارة؛ استخدم التجديد');
    if (op === 'extend') {
      const days = rules.roleDays(c.dashboard ? 'MANAGER' : c.access.role!.role, body.days);
      if (days === null || body.days == null) fail(400, 'مدة التمديد غير صالحة');
      const updated = await c.db.staffRole.update({ where: { id: role.id }, data: { expiresAt: rules.extendExpiry(role.expiresAt, c.now, days!) } });
      await syncRewards(c, updated);
      await audit(c, 'STAFF_EXTEND', 'staff', role.id, role.userId, { expiresAt: role.expiresAt }, { expiresAt: updated.expiresAt });
      changed(c, role.userId, 'تم تمديد مدة الإدارة الخاصة بك');
      return updated;
    }
    if (op === 'permissions') {
      await setPermissions(c, role, body.permissions, body.expiresInDays);
      changed(c, role.userId);
      return c.db.staffPermission.findMany({ where: { staffRoleId: role.id, ...liveWhere(c.now) } });
    }
    if (op === 'parent') {
      if (!c.dashboard || role.role === 'MANAGER' || !Object.prototype.hasOwnProperty.call(body, 'parentUserId')) denied();
      const parentUserId = body.parentUserId == null ? null : positiveId(body.parentUserId);
      if (parentUserId !== null) {
        const parent = c.access.tree.find(r => r.userId === parentUserId && rules.isLive(r, c.now));
        if (!parent || !rules.mayAppoint(parent.role, role.role) || rules.subtree(c.access.tree, role.userId).includes(parentUserId)) fail(400, 'المدير المحدد غير صالح');
      }
      const updated = await c.db.staffRole.update({ where: { id: role.id }, data: { parentUserId } });
      await audit(c, 'STAFF_REPARENT', 'staff', role.id, role.userId, { parentUserId: role.parentUserId }, { parentUserId });
      for (const id of rules.subtree(c.access.tree, role.userId)) changed(c, id);
      return updated;
    }
    const ids = await validateItems(c, body.itemIds, op === 'rewardItems' ? 'reward' : 'grant');
    const updated = await c.db.staffRole.update({ where: { id: role.id }, data: op === 'allowedItems' ? { allowedItemIds: ids } : { rewardItemIds: ids } });
    if (op === 'rewardItems') await syncRewards(c, updated);
    await audit(c, op === 'allowedItems' ? 'STAFF_ALLOWED_ITEMS_SET' : 'STAFF_REWARD_ITEMS_SET', 'staff', role.id, role.userId, role, updated);
    changed(c, role.userId);
    return updated;
  }
  if (op === 'pool' || op === 'grantable') {
    // `?scope=rewards` (pool only): what may be picked as a staff reward — the
    // pool plus the role-reward list, so Admin Frame / Badge show with a name
    // and a picture in the app's picker.
    const available = op === 'pool' && query.scope === 'rewards'
      ? (c.dashboard ? [...new Set([...(await pool(c.db)), ...Object.values(await rewards(c.db)).flat()])] : await assignableItems(c, 'reward'))
      : await pool(c.db);
    const allowed = c.dashboard || c.access.role?.role === 'MANAGER' || op === 'pool' ? available : available.filter(id => c.access.role?.allowedItemIds.includes(id));
    const type = query.type == null ? undefined : String(query.type);
    if (type && !Object.prototype.hasOwnProperty.call(rules.ITEM_TYPES, type)) fail(400, 'نوع المنتج غير صالح');
    const items = await c.db.item.findMany({ where: { id: { in: allowed }, ...(type ? { type: { in: rules.ITEM_TYPES[type as keyof typeof rules.ITEM_TYPES] } } : {}) }, select: itemSelect });
    return op === 'pool' ? items : items.filter(item => {
      const permission = rules.itemPermission(item.type);
      return permission && c.access.permissions.includes(permission);
    });
  }
  if (op === 'poolSet') {
    if (!c.dashboard) denied();
    const ids = await validateItems(c, body.itemIds);
    const items = await c.db.item.findMany({ where: { id: { in: ids } }, select: itemSelect });
    if (items.some(item => !rules.itemPermission(item.type))) fail(400, 'قائمة المنح تقبل الإطارات والدخوليات وفقاعات الدردشة فقط');
    const before = await pool(c.db);
    await c.db.appSetting.upsert({ where: { key: 'staff_grantable_items' }, create: { key: 'staff_grantable_items', value: JSON.stringify(ids) }, update: { value: JSON.stringify(ids) } });
    // Keep stored allowlists a subset, not merely the effective list returned by reads.
    const roles = await c.db.staffRole.findMany({ where: { status: 'ACTIVE' } });
    for (const role of roles) {
      const allowedItemIds = role.allowedItemIds.filter(id => ids.includes(id));
      if (allowedItemIds.length !== role.allowedItemIds.length) {
        await c.db.staffRole.update({ where: { id: role.id }, data: { allowedItemIds } });
        await audit(c, 'STAFF_ALLOWED_ITEMS_SET', 'staff', role.id, role.userId, role.allowedItemIds, allowedItemIds);
      }
      changed(c, role.userId);
    }
    await audit(c, 'STAFF_GRANTABLE_POOL_SET', 'setting', 'staff_grantable_items', null, before, ids);
    return ids;
  }
  if (op === 'roleRewards') return rewards(c.db);
  if (op === 'roleRewardsSet') {
    const before = await rewards(c.db);
    const after = { ...before };
    for (const key of Object.keys(body)) {
      if (!rules.ROLES.includes(key as rules.StaffRoleName)) fail(400, 'نوع الإدارة غير صالح');
      after[key as rules.StaffRoleName] = await validateItems(c, body[key], 'reward');
    }
    await c.db.appSetting.upsert({ where: { key: 'staff_role_rewards' }, create: { key: 'staff_role_rewards', value: JSON.stringify(after) }, update: { value: JSON.stringify(after) } });
    for (const role of await c.db.staffRole.findMany({ where: { status: 'ACTIVE', expiresAt: { gt: c.now }, role: { in: Object.keys(body) } } })) {
      await syncRewards(c, role); changed(c, role.userId);
    }
    await audit(c, 'STAFF_ROLE_REWARDS_CONFIG', 'setting', 'staff_role_rewards', null, before, after);
    return after;
  }
  if (op === 'banHolders') {
    const holders = await c.db.staffPermission.findMany({ where: { permission: 'ban_users', ...liveWhere(c.now),
      ...(!c.dashboard ? { AND: [{ OR: [{ grantedById: { in: c.access.ids } }, { userId: { in: c.access.ids } }] }] } : {}) } });
    const valid = holders.filter(p => p.staffRoleId === null || c.access.tree.some(r => r.id === p.staffRoleId && rules.isLive(r, c.now)));
    const users = await c.db.user.findMany({ where: { id: { in: valid.map(p => p.userId) } }, select: userSelect });
    return valid.map(p => ({ ...p, user: users.find(u => u.id === p.userId) }));
  }
  if (op === 'banHolderGrant' || op === 'banHolderRevoke') {
    const user = await targetUser(c, op === 'banHolderRevoke' ? { userId: params.userId } : body);
    noSelf(c, user.id);
    const role = c.access.tree.find(r => r.userId === user.id && rules.isLive(r, c.now));
    if (role) await managedRole(c, role.id);
    const before = await c.db.staffPermission.findMany({ where: { userId: user.id, permission: 'ban_users', status: 'ACTIVE' } });
    if (op === 'banHolderGrant') checkTarget(c, user);
    else if (!role && before.some(p => p.grantedById && !c.access.ids.includes(p.grantedById))) denied();
    if (body.days != null && !rules.PERMISSION_DAYS.includes(body.days)) fail(400, 'مدة صلاحية الحظر غير صالحة');
    await c.db.staffPermission.updateMany({ where: { userId: user.id, permission: 'ban_users', status: 'ACTIVE' }, data: { status: 'REVOKED', endedAt: c.now, endedById: c.userId } });
    const after = op === 'banHolderGrant' ? await c.db.staffPermission.create({ data: { userId: user.id, staffRoleId: role?.id ?? null,
      permission: 'ban_users', grantedById: c.userId, expiresAt: body.days == null ? null : new Date(c.now.getTime() + body.days * rules.DAY) } }) : null;
    await audit(c, op === 'banHolderGrant' ? 'STAFF_PERMISSION_GRANT' : 'STAFF_PERMISSION_REVOKE', 'user', user.id, user.id, before, after);
    changed(c, user.id, op === 'banHolderGrant' ? 'تم منحك صلاحية نظام الحظر' : 'نظام الحظر: مسحوب');
    return after;
  }
  if (op === 'vipGrant' || op === 'levelGrant' || op === 'itemGrant') {
    const user = await targetUser(c, body);
    checkTarget(c, user);
    const expiresAt = new Date(c.now.getTime() + rules.GRANT_DAYS * rules.DAY);
    if (op === 'itemGrant') {
      const ids = await validateItems(c, [body.itemId]);
      const item = await c.db.item.findUnique({ where: { id: ids[0]! }, select: itemSelect });
      const permission = rules.itemPermission(item!.type);
      if (!permission) fail(400, 'هذا النوع من المنتجات غير متاح للمنح');
      requirePermission(c, permission!);
      return applyItemGrant(c, user.id, item!.id, expiresAt);
    }
    const type = op === 'vipGrant' ? 'VIP' : 'LEVEL';
    const value = body.level;
    if (!Number.isInteger(value) || value < 1 || value > (type === 'VIP' ? 5 : 20)) fail(400, 'المستوى المطلوب غير صالح');
    // A delayed sweep must not turn an expired temporary column into a new base.
    const expired = await c.db.temporaryEntitlement.findMany({ where: { userId: user.id, type, status: 'ACTIVE', expiresAt: { lte: c.now } }, orderBy: { id: 'asc' } });
    for (const grant of expired) await endGrant({ ...c, userId: 0 }, grant, 'EXPIRED');
    const chain = await c.db.temporaryEntitlement.findMany({ where: { userId: user.id, type, status: 'ACTIVE', expiresAt: { gt: c.now } }, orderBy: [{ startedAt: 'asc' }, { id: 'asc' }] });
    const { current, natural } = await naturalValue(c, user.id, type);
    const decision = rules.applyValue(current, natural, value, chain);
    if (!decision.allowed) fail(400, 'المستخدم لديه مستوى أعلى أو مساوٍ');
    const grant = await c.db.temporaryEntitlement.create({ data: { userId: user.id, type, value, previousValue: decision.previousValue, grantedById: c.userId, expiresAt } });
    await c.db.user.update({ where: { id: user.id }, data: type === 'VIP' ? { vipLevel: decision.value } : { level: decision.value } });
    await audit(c, type === 'VIP' ? 'STAFF_GRANT_VIP' : 'STAFF_GRANT_LEVEL', 'grant', grant.id, user.id, { value: current }, grant);
    notify(c, user.id, `تم منحك ${type === 'VIP' ? 'VIP' : 'المستوى'} ${value} لمدة ٧ أيام`);
    return grant;
  }
  if (op === 'grants') {
    const rows = await c.db.temporaryEntitlement.findMany({ where: {
      status: statusFilter(query.status, ['ACTIVE', 'EXPIRED', 'REVOKED']),
      ...(!c.dashboard ? { grantedById: { in: c.access.ids } } : {}) }, orderBy: { id: 'desc' }, take: 500 });
    const items = await c.db.item.findMany({ where: { id: { in: rows.map(r => r.itemId).filter((id): id is string => !!id) } }, select: itemSelect });
    return withPeople(c, rows.map(r => ({ ...r, item: items.find(i => i.id === r.itemId) ?? null })), ['user', 'grantedBy']);
  }
  if (op === 'grantRevoke') {
    const grant = await c.db.temporaryEntitlement.findUniqueOrThrow({ where: { id: positiveId(params.id) } });
    return grant.expiresAt <= c.now ? endGrant({ ...c, userId: 0 }, grant, 'EXPIRED') : endGrant(c, grant, 'REVOKED');
  }
  if (op === 'agencies') return (await Promise.all((await agencyIds(c)).map(id => agencySummary(c, id)))).filter(Boolean);
  if (op === 'agency') return agencySummary(c, positiveId(params.id), true);
  if (op === 'agencyCreate') {
    const owner = await targetUser(c, { userId: body.ownerUserId, displayId: body.ownerDisplayId });
    checkTarget(c, owner);
    if (typeof body.agencyName !== 'string' || !body.agencyName.trim() || body.agencyName.length > 200) fail(400, 'اسم الوكالة مطلوب');
    if (await c.db.chargingAgency.findFirst({ where: { userId: owner.id, type: 'HOSTING', status: { not: 'rejected' } }, select: { id: true } })) fail(409, 'المستخدم لديه وكالة مضيفين بالفعل');
    const agency = await c.db.chargingAgency.create({ data: { userId: owner.id, agencyName: body.agencyName.trim(),
      phoneNumber: '-', agencyImageUrl: '', idFrontUrl: '', idBackUrl: '', type: 'HOSTING', status: 'approved', assignedByAdminId: null },
      select: { id: true, userId: true, agencyName: true, type: true, status: true, createdAt: true } });
    await c.db.agencyMember.create({ data: { agencyId: agency.id, userId: owner.id, role: 'OWNER' } });
    await c.db.staffAgencyScope.create({ data: { staffUserId: c.userId, agencyId: agency.id, kind: 'CREATED', assignedById: c.userId } });
    await audit(c, 'STAFF_AGENCY_CREATE', 'agency', agency.id, owner.id, null, agency);
    notify(c, owner.id, `تم تعيينك وكيلاً لوكالة المضيفين «${agency.agencyName}»`);
    return agency;
  }
  if (op === 'followerAdd' || op === 'followerRemove') {
    const agencyId = positiveId(params.id);
    const staffUserId = positiveId(body.staffUserId ?? params.staffUserId);
    const before = await c.db.staffAgencyScope.findUnique({ where: { staffUserId_agencyId: { staffUserId, agencyId } } });
    if (before?.kind === 'CREATED') fail(409, 'لا يمكن إزالة نطاق منشئ الوكالة أو استبداله');
    const after = op === 'followerAdd' ? await c.db.staffAgencyScope.upsert({ where: { staffUserId_agencyId: { staffUserId, agencyId } },
      create: { staffUserId, agencyId, kind: 'ASSIGNED', assignedById: c.userId }, update: { assignedById: c.userId } }) : null;
    if (op === 'followerRemove') await c.db.staffAgencyScope.deleteMany({ where: { staffUserId, agencyId, kind: 'ASSIGNED' } });
    await audit(c, op === 'followerAdd' ? 'STAFF_AGENCY_FOLLOWER_ADD' : 'STAFF_AGENCY_FOLLOWER_REMOVE', 'agency', agencyId, staffUserId, before, after);
    changed(c, staffUserId);
    return after;
  }
  if (op === 'ban') {
    const user = await targetUser(c, body);
    const flags = await c.db.user.findUniqueOrThrow({ where: { id: user.id }, select: { isAdmin: true, isSuperAdmin: true } });
    const targetRole = c.access.tree.find(r => r.userId === user.id && rules.isLive(r, c.now));
    if (!rules.mayBan(c.userId, c.access.role?.role ?? null, { id: user.id, ...flags, role: targetRole?.role ?? null })) denied();
    if (user.isBanned && (!user.banExpiresAt || user.banExpiresAt > c.now)) fail(409, 'المستخدم محظور بالفعل');
    if (typeof body.reason !== 'string' || !body.reason.trim()) fail(400, 'سبب الحظر مطلوب');
    if (typeof body.duration !== 'string' || !Object.prototype.hasOwnProperty.call(rules.BAN_DURATIONS, body.duration)) fail(400, 'مدة الحظر غير صالحة');
    const days = rules.BAN_DURATIONS[body.duration as keyof typeof rules.BAN_DURATIONS];
    const expiresAt = days === null ? null : new Date(c.now.getTime() + days * rules.DAY);
    const reason = body.reason.trim();
    await c.db.user.update({ where: { id: user.id }, data: { isBanned: true, bannedAt: c.now, banReason: reason, banExpiresAt: expiresAt, banSource: 'staff' } });
    const record = await c.db.banRecord.create({ data: { userId: user.id, bannedById: c.userId, duration: body.duration, reason, expiresAt } });
    await audit(c, 'STAFF_BAN', 'ban', record.id, user.id, user, record);
    c.effects.push(() => invalidateBanCache(user.id));
    c.effects.push(() => kickBannedUser(user.id, reason, expiresAt));
    return record;
  }
  if (op === 'unban') {
    const userId = positiveId(params.userId);
    noSelf(c, userId);
    const user = await c.db.user.findUnique({ where: { id: userId }, select: { banSource: true, isBanned: true } });
    if (!user) fail(404, 'المستخدم غير موجود');
    if (user!.banSource !== 'staff') fail(403, 'لا يمكن رفع حظر صادر من خارج نظام الإدارة');
    const record = await c.db.banRecord.findFirst({ where: { userId, status: 'ACTIVE' }, orderBy: { id: 'desc' } });
    if (!record) fail(404, 'سجل الحظر غير موجود');
    if (c.access.role?.role !== 'MANAGER' && !c.access.ids.includes(record!.bannedById)) denied();
    await c.db.user.update({ where: { id: userId }, data: { isBanned: false, bannedAt: null, banReason: null, banExpiresAt: null, banSource: null } });
    const updated = await c.db.banRecord.update({ where: { id: record!.id }, data: { status: 'LIFTED', liftedAt: c.now, liftedById: c.userId } });
    await audit(c, 'STAFF_UNBAN', 'ban', record!.id, userId, record, updated);
    c.effects.push(() => invalidateBanCache(userId));
    return updated;
  }
  if (op === 'bans') return withPeople(c, await c.db.banRecord.findMany({ where: { status: statusFilter(query.status, ['ACTIVE', 'LIFTED', 'EXPIRED']),
    ...(!c.dashboard ? { bannedById: { in: await overseenIds(c) } } : {}) }, orderBy: { id: 'desc' }, take: 500 }), ['user', 'bannedBy', 'liftedBy']);
  if (op === 'audit') return auditRows(c, query);
  return fail(404, 'المسار غير موجود');
}

async function transaction<T>(work: (db: Db, effects: Effect[]) => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    const effects: Effect[] = [];
    try {
      const result = await prisma.$transaction(db => work(db, effects), { isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 30_000 });
      // Never publish an access change, notification or kick for a rolled-back action.
      for (const effect of effects) try { await effect(); } catch (error) { console.warn('[staff] notification/reward failed', error); }
      return result;
    } catch (error) {
      if ((error as { code?: string }).code === 'P2034' && attempt < 3) continue;
      if ((error as { code?: string }).code === 'P2002') fail(409, 'يوجد سجل نشط بالفعل؛ قم بالتمديد أو السحب أولاً');
      throw error;
    }
  }
}

export async function runStaffAction(actor: ActorContext, op: Operation, body: Body = {}, params: Body = {}, query: Body = {}) {
  if (!actor.userId) fail(401, 'يرجى تسجيل الدخول');
  return transaction(async (db, effects) => {
    const now = new Date();
    const c: Context = { ...actor, db, effects, now, access: await resolveAccess(db, actor.userId, now) };
    // Authentication is performed by the router. These phases run again inside
    // the serializable action, so simultaneous revocations cannot bypass a guard.
    authorizeRole(c, op);
    authorizePermission(c, op);
    await scopeGuard(c, op, body, params);
    c.now = new Date();
    c.access = await resolveAccess(db, actor.userId, c.now);
    authorizeRole(c, op);
    authorizePermission(c, op);
    return action(c, op, body, params, query);
  });
}

export async function sweepStaffExpiry(now = new Date()): Promise<void> {
  await transaction(async (db, effects) => {
    const c: Context = { userId: 0, dashboard: true, db, effects, now, access: { role: null, permissions: [], tree: await treeRows(db), ids: [] } };
    const roles = await db.staffRole.findMany({ where: { status: 'ACTIVE', expiresAt: { lte: now } }, orderBy: { id: 'asc' } });
    for (const role of roles) {
      const current = await db.staffRole.findUniqueOrThrow({ where: { id: role.id } });
      await endRole(c, current, 'EXPIRED');
    }
    const permissions = await db.staffPermission.findMany({ where: { status: 'ACTIVE', expiresAt: { lte: now } } });
    for (const permission of permissions) {
      await db.staffPermission.update({ where: { id: permission.id }, data: { status: 'EXPIRED', endedAt: now, endedById: 0 } });
      await audit(c, 'STAFF_PERMISSION_EXPIRED', 'user', permission.userId, permission.userId, permission, { status: 'EXPIRED' });
      changed(c, permission.userId, 'انتهت مدة إحدى صلاحيات الإدارة الخاصة بك');
    }
    const grants = await db.temporaryEntitlement.findMany({ where: { status: 'ACTIVE', expiresAt: { lte: now } }, orderBy: { id: 'asc' } });
    for (const grant of grants) await endGrant(c, grant, 'EXPIRED');
    const bans = await db.banRecord.findMany({ where: { status: 'ACTIVE', expiresAt: { lte: now } } });
    for (const ban of bans) {
      await db.banRecord.update({ where: { id: ban.id }, data: { status: 'EXPIRED' } });
      await audit(c, 'STAFF_BAN_EXPIRED', 'ban', ban.id, ban.userId, ban, { status: 'EXPIRED' });
    }
    // A staff ban lifted or replaced elsewhere (dashboard / in-app admin) leaves
    // the record ACTIVE forever otherwise, and the list would show a ban that
    // no longer exists.
    const open = await db.banRecord.findMany({ where: { status: 'ACTIVE' }, select: { id: true, userId: true } });
    if (open.length) {
      const stillStaffBanned = new Set((await db.user.findMany({
        where: { id: { in: open.map(b => b.userId) }, isBanned: true, banSource: 'staff' }, select: { id: true },
      })).map(u => u.id));
      for (const ban of open.filter(b => !stillStaffBanned.has(b.userId))) {
        await db.banRecord.update({ where: { id: ban.id }, data: { status: 'LIFTED', liftedAt: now } });
      }
    }
  });
}
let expiryTimer: NodeJS.Timeout | null = null;
let sweeping = false;
export function startStaffExpiryJob(): void {
  if (expiryTimer) return;
  const run = async () => {
    if (sweeping) return;
    sweeping = true;
    try { await sweepStaffExpiry(); } catch (error) { console.error('[staff] expiry failed', error); }
    finally { sweeping = false; }
  };
  void run();
  expiryTimer = setInterval(() => { void run(); }, 60_000);
  expiryTimer.unref();
}
