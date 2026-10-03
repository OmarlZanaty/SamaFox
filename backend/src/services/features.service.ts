import prisma from '../utils/prisma';
import { AUDIT_ACTIONS, recordAdminAudit, type AdminAuditInput } from './adminAudit.service';

const db = prisma as any;

/**
 * «منح المميزات» — features and permissions granted per user (2026-09-26).
 *
 * One table (`user_features`) for every grant, instead of a boolean column per
 * feature: the list below is the whole catalogue, and adding a feature is a new
 * key here, not a migration.
 *
 * `enabled` is the admin's grant. `userOn` is the user's own switch, for the
 * features that have one. A grant can expire (`expiresAt`); an expired grant
 * is treated exactly like no grant — every check below is server-side.
 */
export const FEATURES = {
  /** الدخول المخفي: enter rooms without any entrance notice to other users. */
  HIDDEN_MODE: 'HIDDEN_MODE',
  /** Enter a locked room without its password (an admin permission — NOT
   *  automatic for super admins any more). */
  ROOM_LOCK_BYPASS: 'ROOM_LOCK_BYPASS',
  /** Close / reopen / delete an OFFICIAL_ROOM outside the dashboard. */
  OFFICIAL_ROOM_MANAGE: 'OFFICIAL_ROOM_MANAGE',
} as const;

export type FeatureKey = (typeof FEATURES)[keyof typeof FEATURES];

export const FEATURE_CATALOG: { key: FeatureKey; nameAr: string; description: string; userToggle: boolean; kind: 'feature' | 'permission' }[] = [
  {
    key: 'HIDDEN_MODE',
    nameAr: 'الدخول المخفي',
    description:
      'يظهر في إعدادات المستخدم مفتاح «الدخول المخفي». عند تشغيله لا يظهر للمستخدمين إشعار ولا أنيميشن ولا رسالة بدخوله، ويستطيع دخول الغرفة المغلقة بدون كلمة مرور بعد التأكيد (إن سمحت الغرفة). السيرفر يسجل كل دخول وتراه الإدارة.',
    userToggle: true,
    kind: 'feature',
  },
  {
    key: 'ROOM_LOCK_BYPASS',
    nameAr: 'دخول الغرف المغلقة بدون كلمة مرور',
    description: 'صلاحية إدارية مستقلة: دخول أي غرفة مغلقة بدون كلمة مرور. لا تُمنح تلقائياً للسوبر أدمن. كل دخول يُسجَّل.',
    userToggle: false,
    kind: 'permission',
  },
  {
    key: 'OFFICIAL_ROOM_MANAGE',
    nameAr: 'إدارة الغرف الرسمية',
    description: 'إغلاق/فتح/حذف الغرف الرسمية (OFFICIAL_ROOM) من التطبيق. بدونها لا تُغلق الغرفة الرسمية إلا من لوحة التحكم.',
    userToggle: false,
    kind: 'permission',
  },
];

export const isFeatureKey = (k: unknown): k is FeatureKey =>
  typeof k === 'string' && (Object.values(FEATURES) as string[]).includes(k);

function active(row: any, now = new Date()): boolean {
  return Boolean(row?.enabled) && (!row.expiresAt || new Date(row.expiresAt) > now);
}

/** Is the grant live (admin-enabled, not expired)? */
export async function hasFeature(userId: number, key: FeatureKey): Promise<boolean> {
  const row = await db.userFeature.findUnique({ where: { userId_featureKey: { userId, featureKey: key } } });
  return active(row);
}

/** Granted AND switched on by the user (for features with a user toggle). */
export async function isFeatureOn(userId: number, key: FeatureKey): Promise<boolean> {
  const row = await db.userFeature.findUnique({ where: { userId_featureKey: { userId, featureKey: key } } });
  return active(row) && Boolean(row.userOn);
}

/** What the app needs: every live grant and its switch. */
export async function listMyFeatures(userId: number) {
  const rows = await db.userFeature.findMany({ where: { userId } });
  const now = new Date();
  return rows
    .filter((r: any) => active(r, now))
    .map((r: any) => {
      const meta = FEATURE_CATALOG.find((c) => c.key === r.featureKey);
      return {
        key: r.featureKey,
        nameAr: meta?.nameAr ?? r.featureKey,
        userToggle: meta?.userToggle ?? false,
        on: meta?.userToggle ? Boolean(r.userOn) : true,
        expiresAt: r.expiresAt,
      };
    });
}

export class FeatureError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}

/** The user flips their own switch. Refused unless the grant is live. */
export async function setMyFeatureSwitch(userId: number, key: FeatureKey, on: boolean) {
  const meta = FEATURE_CATALOG.find((c) => c.key === key);
  if (!meta?.userToggle) throw new FeatureError('NOT_TOGGLEABLE', 'هذه الميزة ليس لها مفتاح');
  const row = await db.userFeature.findUnique({ where: { userId_featureKey: { userId, featureKey: key } } });
  if (!active(row)) throw new FeatureError('NOT_GRANTED', 'هذه الميزة غير ممنوحة لحسابك', 403);
  const updated = await db.userFeature.update({ where: { id: row.id }, data: { userOn: Boolean(on) } });
  return { key, on: Boolean(updated.userOn) };
}

type AuditCtx = Pick<AdminAuditInput, 'ip' | 'reason' | 'sessionId' | 'userAgent'>;

export async function grantFeature(
  adminId: number,
  userId: number,
  key: FeatureKey,
  opts: { expiresAt?: Date | null; note?: string | null } & { audit?: AuditCtx } = {},
) {
  const before = await db.userFeature.findUnique({ where: { userId_featureKey: { userId, featureKey: key } } });
  const row = await db.$transaction(async (tx: any) => {
    const r = await tx.userFeature.upsert({
      where: { userId_featureKey: { userId, featureKey: key } },
      update: { enabled: true, grantedBy: adminId, grantedAt: new Date(), expiresAt: opts.expiresAt ?? null, note: opts.note ?? null },
      create: { userId, featureKey: key, enabled: true, grantedBy: adminId, expiresAt: opts.expiresAt ?? null, note: opts.note ?? null },
    });
    await recordAdminAudit(
      {
        adminId,
        action: AUDIT_ACTIONS.FEATURE_GRANT,
        targetUserId: userId,
        targetType: 'feature',
        targetId: key,
        before: before ? { enabled: before.enabled, expiresAt: before.expiresAt } : null,
        after: { enabled: true, expiresAt: r.expiresAt, note: r.note },
        ...(opts.audit ?? {}),
      },
      tx,
    );
    return r;
  });
  return row;
}

export async function revokeFeature(adminId: number, userId: number, key: FeatureKey, audit: AuditCtx = {}) {
  const before = await db.userFeature.findUnique({ where: { userId_featureKey: { userId, featureKey: key } } });
  if (!before) throw new FeatureError('NOT_FOUND', 'الميزة غير ممنوحة لهذا المستخدم', 404);
  return db.$transaction(async (tx: any) => {
    const r = await tx.userFeature.update({ where: { id: before.id }, data: { enabled: false, userOn: false } });
    await recordAdminAudit(
      {
        adminId,
        action: AUDIT_ACTIONS.FEATURE_REVOKE,
        targetUserId: userId,
        targetType: 'feature',
        targetId: key,
        before: { enabled: before.enabled, userOn: before.userOn, expiresAt: before.expiresAt },
        after: { enabled: false, userOn: false },
        ...audit,
      },
      tx,
    );
    return r;
  });
}

export async function listUserFeaturesAdmin(userId: number) {
  const rows = await db.userFeature.findMany({ where: { userId } });
  const byKey = new Map(rows.map((r: any) => [r.featureKey, r]));
  const now = new Date();
  return FEATURE_CATALOG.map((c) => {
    const r: any = byKey.get(c.key);
    return {
      ...c,
      granted: active(r, now),
      enabled: Boolean(r?.enabled),
      userOn: Boolean(r?.userOn),
      grantedBy: r?.grantedBy ?? null,
      grantedAt: r?.grantedAt ?? null,
      expiresAt: r?.expiresAt ?? null,
      note: r?.note ?? null,
    };
  });
}
