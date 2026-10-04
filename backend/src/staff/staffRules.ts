// Keep policy independent of storage so clients cannot change authority through input.
export type StaffRoleName = 'MANAGER' | 'SUPER_ADMIN' | 'ADMIN';
export const ROLES: StaffRoleName[] = ['MANAGER', 'SUPER_ADMIN', 'ADMIN'];
export const RANK = { MANAGER: 3, SUPER_ADMIN: 2, ADMIN: 1 } as const;
export const rank = (role: string | null | undefined): number => ROLES.includes(role as StaffRoleName) ? RANK[role as StaffRoleName] : 0;
export const DAY = 86_400_000;
export const GRANT_DAYS = 7;
export const BAN_DURATIONS = { '1d': 1, '7d': 7, '30d': 30, '365d': 365, permanent: null } as const;
export const PERMISSION_DAYS = [1, 7, 30, 365];
const staffRoles: StaffRoleName[] = ['SUPER_ADMIN', 'ADMIN'];
export const PERMISSION_CATALOG = [
  { key: 'role_panel', label: 'نظام {role}', roles: staffRoles },
  { key: 'manage_admins', label: 'تعيين Admin', roles: ['SUPER_ADMIN'] as StaffRoleName[] },
  { key: 'grant_vip', label: 'منح VIP', roles: staffRoles },
  { key: 'grant_level', label: 'منح Level', roles: staffRoles },
  { key: 'grant_frame', label: 'منح إطار', roles: staffRoles },
  { key: 'grant_entry', label: 'منح دخولية', roles: staffRoles },
  { key: 'grant_bubble', label: 'منح فقاعة دردشة', roles: staffRoles },
  { key: 'manage_host_agency', label: 'تعيين وكالة مضيفين', roles: staffRoles },
  { key: 'follow_agencies', label: 'متابعة الوكالات', roles: staffRoles },
  { key: 'ban_users', label: 'نظام الحظر', roles: [...ROLES, null] },
] as const;
export type Permission = typeof PERMISSION_CATALOG[number]['key'];
export const permissionKeys = PERMISSION_CATALOG.map(p => p.key);
export function mayHold(role: string | null, key: string): boolean {
  const entry = PERMISSION_CATALOG.find(p => p.key === key);
  return !!entry && (role === 'MANAGER' || (entry.roles as readonly (string | null)[]).includes(role));
}
export function defaultPermissions(role: StaffRoleName): Permission[] {
  if (role === 'MANAGER') return [...permissionKeys];
  return permissionKeys.filter(key => key !== 'ban_users' && mayHold(role, key) &&
    (role === 'SUPER_ADMIN' || ['role_panel', 'manage_host_agency', 'follow_agencies'].includes(key)));
}
export function mayAppoint(actor: string | null, target: string, self = false): boolean {
  return !self && ((actor === 'MANAGER' && ['SUPER_ADMIN', 'ADMIN'].includes(target)) ||
    (actor === 'SUPER_ADMIN' && target === 'ADMIN'));
}
export interface TreeRole { userId: number; parentUserId: number | null; role: string }
export function subtree(rows: readonly TreeRole[], userId: number): number[] {
  const seen = new Set<number>([userId]);
  const queue = [userId];
  for (let i = 0; i < queue.length; i++) {
    for (const row of rows) if (row.parentUserId === queue[i] && !seen.has(row.userId)) {
      seen.add(row.userId); queue.push(row.userId);
    }
  }
  return [...seen];
}
export function mayManage(actor: TreeRole, target: TreeRole, rows: readonly TreeRole[]): boolean {
  return actor.userId !== target.userId && rank(actor.role) > rank(target.role) &&
    (actor.role === 'MANAGER' ? subtree(rows, actor.userId).includes(target.userId) :
      actor.role === 'SUPER_ADMIN' && target.role === 'ADMIN' && target.parentUserId === actor.userId);
}
export function scopeAgencies(rows: readonly TreeRole[], scopes: readonly { staffUserId: number; agencyId: number }[], userId: number): number[] {
  const ids = new Set(subtree(rows, userId));
  return [...new Set(scopes.filter(s => ids.has(s.staffUserId)).map(s => s.agencyId))];
}
export function roleDays(actorRole: string, days: unknown = 30): number | null {
  return typeof days === 'number' && Number.isInteger(days) && days >= 1 &&
    days <= (actorRole === 'SUPER_ADMIN' ? 30 : actorRole === 'MANAGER' ? 365 : 0) ? days : null;
}
export const extendExpiry = (current: Date, now: Date, days: number): Date =>
  new Date(Math.max(current.getTime(), now.getTime()) + days * DAY);
export function isLive(row: { status: string; expiresAt: Date | null }, now: Date): boolean {
  return row.status === 'ACTIVE' && (row.expiresAt === null || row.expiresAt.getTime() > now.getTime());
}
export function mayBan(actorId: number, actorRole: string | null, target: {
  id: number; isAdmin: boolean; isSuperAdmin: boolean; role: string | null;
}): boolean {
  return actorId !== target.id && !target.isAdmin && !target.isSuperAdmin &&
    (!target.role || rank(actorRole) > rank(target.role));
}
export interface ValueGrant { value: number | null; previousValue: string | null }
export function baseValue(current: number, natural: number, chain: readonly ValueGrant[]): number {
  return Math.max(natural, chain.length ? Number(chain[0]!.previousValue ?? 0) : current);
}
export function applyValue(current: number, natural: number, value: number, chain: readonly ValueGrant[]) {
  return { allowed: value > baseValue(current, natural, chain),
    previousValue: String(chain.length ? Number(chain[0]!.previousValue ?? 0) : current),
    value: Math.max(current, value) };
}
export function restoreValue(previous: string | null, natural: number, remaining: readonly ValueGrant[]): number {
  return Math.max(Number(previous ?? 0), natural, ...remaining.map(g => g.value ?? 0));
}
export type ItemDecision = { action: 'create' | 'update' | 'keep'; previousValue: string; expiresAt: Date };
export function applyItem(existing: { expiresAt: Date | null } | null, now: Date, expiry = new Date(now.getTime() + GRANT_DAYS * DAY)): ItemDecision {
  if (!existing) return { action: 'create', previousValue: 'none', expiresAt: expiry };
  if (existing.expiresAt === null) return { action: 'keep', previousValue: 'permanent', expiresAt: expiry };
  if (existing.expiresAt >= expiry) return { action: 'keep', previousValue: `later:${existing.expiresAt.toISOString()}`, expiresAt: expiry };
  return { action: 'update', previousValue: `until:${existing.expiresAt.toISOString()}`, expiresAt: expiry };
}
export function revokeItem(existing: { expiresAt: Date | null } | null, grantExpiry: Date, previous: string | null):
  { action: 'keep' | 'delete' | 'restore'; expiresAt?: Date } {
  if (!existing?.expiresAt || existing.expiresAt.getTime() !== grantExpiry.getTime()) return { action: 'keep' };
  if (previous === 'none') return { action: 'delete' };
  if (previous?.startsWith('until:')) return { action: 'restore', expiresAt: new Date(previous.slice(6)) };
  return { action: 'keep' };
}
export const ITEM_TYPES = { frame: ['FRAME'], entry: ['ENTRANCE_BANNER', 'ENTRANCE_EFFECT'], bubble: ['CHAT_BUBBLE'] };
export function itemPermission(type: string): Permission | null {
  return type === 'FRAME' ? 'grant_frame' : ITEM_TYPES.entry.includes(type) ? 'grant_entry' : type === 'CHAT_BUBBLE' ? 'grant_bubble' : null;
}
