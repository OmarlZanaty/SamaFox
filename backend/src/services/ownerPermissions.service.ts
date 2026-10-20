import { Request, Response, NextFunction, RequestHandler } from 'express';
import prisma from '../utils/prisma';
import { auditContext, recordAdminAuditStrict } from './adminAudit.service';

/**
 * Owner + explicit financial permissions (SPEC52 item 42, 2026-10-20).
 *
 * Roles (isAdmin / isSuperAdmin / staff MANAGER…ADMIN) say WHO someone is;
 * these keys say WHAT money-touching thing they may do. Only the Owner holds
 * all of them implicitly. Everyone else needs an explicit, owner-issued row in
 * admin_permission_grants — no role inherits them, including the staff
 * MANAGER's "all permissions" rule (that catalog lives in staff/staffRules.ts
 * and deliberately does not contain these keys).
 *
 * Bootstrap: until some account is flagged `isOwner`, super-admins act as the
 * owner, so production keeps working the moment this ships. Set the real
 * owner with `UPDATE users SET "isOwner" = true WHERE id = …;` — from then on
 * a super-admin without a grant is refused.
 */
export const OWNER_PERMISSIONS = {
  'finance.coins': 'إضافة / خصم كوينز وتجميد المحافظ',
  'finance.recharge': 'الشحن وطلبات الشحن',
  'finance.charging_agency': 'الإعدادات المالية لوكالات الشحن وأرصدتها',
  'store.products': 'منتجات المتجر وأسعارها وقوائم المتجر',
  'gifts.prices': 'الهدايا وأسعارها وقوائم الهدايا',
  'economy.settings': 'اقتصاد الألعاب والمحظوظ والصاروخ وPK والمكافآت',
  'vip.config': 'إعدادات VIP وألوان الأسماء والصور المتحركة',
  'admin.permissions': 'منح وسحب هذه الصلاحيات (المالك فقط)',
} as const;

export type OwnerPermission = keyof typeof OWNER_PERMISSIONS;
export const OWNER_PERMISSION_KEYS = Object.keys(OWNER_PERMISSIONS) as OwnerPermission[];

export const isOwnerPermission = (v: unknown): v is OwnerPermission =>
  typeof v === 'string' && (OWNER_PERMISSION_KEYS as string[]).includes(v);

let ownerExistsCache: { value: boolean; at: number } | null = null;
const OWNER_CACHE_MS = 30_000;

/** True once any account carries isOwner — switches the bootstrap rule off. */
export async function ownerExists(): Promise<boolean> {
  if (ownerExistsCache && Date.now() - ownerExistsCache.at < OWNER_CACHE_MS) return ownerExistsCache.value;
  const n = await (prisma as any).user.count({ where: { isOwner: true } });
  ownerExistsCache = { value: n > 0, at: Date.now() };
  return n > 0;
}

export function resetOwnerCache() {
  ownerExistsCache = null;
}

let warnedBootstrap = false;

/** Is this account the Owner (or a super-admin while no owner is set)? */
export async function isOwnerUser(userId: number): Promise<boolean> {
  const u = await (prisma as any).user.findUnique({
    where: { id: userId },
    select: { isOwner: true, isSuperAdmin: true },
  });
  if (!u) return false;
  if (u.isOwner) return true;
  if (u.isSuperAdmin && !(await ownerExists())) {
    if (!warnedBootstrap) {
      console.warn('[owner] no user has isOwner=true — super-admins act as owner until one is set');
      warnedBootstrap = true;
    }
    return true;
  }
  return false;
}

/** Active explicit grants of one user. */
export async function grantedPermissions(userId: number): Promise<OwnerPermission[]> {
  const rows = await (prisma as any).adminPermissionGrant.findMany({
    where: { userId, revokedAt: null },
    select: { permission: true },
  });
  return rows.map((r: any) => r.permission).filter(isOwnerPermission);
}

export async function hasOwnerPermission(userId: number, perm: OwnerPermission): Promise<boolean> {
  if (await isOwnerUser(userId)) return true;
  if (perm === 'admin.permissions') return false; // never delegable
  const row = await (prisma as any).adminPermissionGrant.findFirst({
    where: { userId, permission: perm, revokedAt: null },
    select: { id: true },
  });
  return !!row;
}

/** What the dashboard shows/hides; the server still checks every call. */
export async function capabilitiesFor(userId: number) {
  const owner = await isOwnerUser(userId);
  return {
    isOwner: owner,
    permissions: owner ? OWNER_PERMISSION_KEYS : await grantedPermissions(userId),
  };
}

export const OWNER_PERMISSION_DENIED = 'هذه العملية تحتاج صلاحية من المالك';

/** Gate for a money/price/product endpoint. Chain after authentication. */
export function requireOwnerPermission(perm: OwnerPermission): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const userId = Number((req as any).userId ?? (req as any).authUser?.id);
      if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
      if (await hasOwnerPermission(userId, perm)) return next();
      return res.status(403).json({ success: false, code: 'OWNER_PERMISSION_REQUIRED', permission: perm, message: OWNER_PERMISSION_DENIED });
    } catch (err) {
      console.error('[ownerPermission] check failed:', (err as Error).message);
      return res.status(500).json({ success: false, message: 'Permission check failed' });
    }
  };
}

export const requireOwner: RequestHandler = requireOwnerPermission('admin.permissions');

// ── Grant management (owner only) ──────────────────────────────────────────

export async function listGrants() {
  const rows = await (prisma as any).adminPermissionGrant.findMany({
    orderBy: [{ revokedAt: 'asc' }, { createdAt: 'desc' }],
    take: 500,
  });
  const ids = [...new Set(rows.flatMap((r: any) => [r.userId, r.grantedBy, r.revokedBy].filter(Boolean)))] as number[];
  const users = ids.length
    ? await (prisma as any).user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true, displayId: true, isAdmin: true, isSuperAdmin: true } })
    : [];
  const byId = new Map(users.map((u: any) => [u.id, u]));
  return rows.map((r: any) => ({ ...r, user: byId.get(r.userId) ?? null, grantedByUser: byId.get(r.grantedBy) ?? null }));
}

export async function grantPermission(req: Request, userId: number, perm: OwnerPermission) {
  const adminId = Number((req as any).userId);
  return prisma.$transaction(async (tx: any) => {
    const target = await tx.user.findUnique({ where: { id: userId }, select: { id: true, isAdmin: true, isSuperAdmin: true } });
    if (!target) throw Object.assign(new Error('المستخدم غير موجود'), { status: 404 });
    if (!target.isAdmin && !target.isSuperAdmin) throw Object.assign(new Error('الصلاحيات تُمنح للمشرفين فقط'), { status: 400 });
    const existing = await tx.adminPermissionGrant.findFirst({ where: { userId, permission: perm, revokedAt: null } });
    if (existing) return existing;
    const row = await tx.adminPermissionGrant.create({ data: { userId, permission: perm, grantedBy: adminId } });
    await recordAdminAuditStrict(tx, {
      adminId,
      action: 'OWNER_PERMISSION_GRANT',
      targetUserId: userId,
      targetType: 'admin_permission',
      targetId: row.id,
      before: null,
      after: { userId, permission: perm },
      ...auditContext(req),
    });
    return row;
  });
}

export async function revokePermission(req: Request, grantId: number) {
  const adminId = Number((req as any).userId);
  return prisma.$transaction(async (tx: any) => {
    const row = await tx.adminPermissionGrant.findUnique({ where: { id: grantId } });
    if (!row) throw Object.assign(new Error('الصلاحية غير موجودة'), { status: 404 });
    if (row.revokedAt) return row;
    const updated = await tx.adminPermissionGrant.update({
      where: { id: grantId },
      data: { revokedAt: new Date(), revokedBy: adminId },
    });
    await recordAdminAuditStrict(tx, {
      adminId,
      action: 'OWNER_PERMISSION_REVOKE',
      targetUserId: row.userId,
      targetType: 'admin_permission',
      targetId: row.id,
      before: { userId: row.userId, permission: row.permission, active: true },
      after: { active: false },
      ...auditContext(req),
    });
    return updated;
  });
}
