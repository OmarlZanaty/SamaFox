import prisma from '../utils/prisma';

/**
 * Generic admin audit log (2026-09-22, "حفظ جميع العمليات في سجل مراجعة").
 *
 * Every admin action on the CP / backgrounds panel records who did it, what,
 * to whom, and the values before and after. `GiftAdminAudit` predates this and
 * is left alone; new code writes here.
 *
 * Same rule as `recordGiftAudit`: a failed audit write is logged and swallowed.
 * The action itself must never fail because the log could not be written —
 * but the reverse is also enforced by callers that write the audit row INSIDE
 * the same transaction when they can (see cpAdmin.service).
 */
export const AUDIT_ACTIONS = {
  STAFF_APPOINT: 'STAFF_APPOINT',
  STAFF_EXTEND: 'STAFF_EXTEND',
  STAFF_RENEW: 'STAFF_RENEW',
  STAFF_REVOKE: 'STAFF_REVOKE',
  STAFF_EXPIRED: 'STAFF_EXPIRED',
  STAFF_PERMISSION_GRANT: 'STAFF_PERMISSION_GRANT',
  STAFF_PERMISSION_REVOKE: 'STAFF_PERMISSION_REVOKE',
  STAFF_PERMISSION_EXPIRED: 'STAFF_PERMISSION_EXPIRED',
  STAFF_ALLOWED_ITEMS_SET: 'STAFF_ALLOWED_ITEMS_SET',
  STAFF_REWARD_ITEMS_SET: 'STAFF_REWARD_ITEMS_SET',
  STAFF_ROLE_REWARDS_CONFIG: 'STAFF_ROLE_REWARDS_CONFIG',
  STAFF_GRANTABLE_POOL_SET: 'STAFF_GRANTABLE_POOL_SET',
  STAFF_REPARENT: 'STAFF_REPARENT',
  STAFF_GRANT_VIP: 'STAFF_GRANT_VIP',
  STAFF_GRANT_LEVEL: 'STAFF_GRANT_LEVEL',
  STAFF_GRANT_ITEM: 'STAFF_GRANT_ITEM',
  STAFF_GRANT_REVOKE: 'STAFF_GRANT_REVOKE',
  STAFF_GRANT_EXPIRED: 'STAFF_GRANT_EXPIRED',
  STAFF_AGENCY_CREATE: 'STAFF_AGENCY_CREATE',
  STAFF_AGENCY_FOLLOWER_ADD: 'STAFF_AGENCY_FOLLOWER_ADD',
  STAFF_AGENCY_FOLLOWER_REMOVE: 'STAFF_AGENCY_FOLLOWER_REMOVE',
  STAFF_BAN: 'STAFF_BAN',
  STAFF_UNBAN: 'STAFF_UNBAN',
  STAFF_BAN_EXPIRED: 'STAFF_BAN_EXPIRED',
  CP_POLICY_UPDATE: 'CP_POLICY_UPDATE',
  CP_GRANT_FREE: 'CP_GRANT_FREE',
  CP_GRANT_FEE: 'CP_GRANT_FEE',
  CP_GRANT_REVOKE: 'CP_GRANT_REVOKE',
  CP_UNLOCK_ADMIN: 'CP_UNLOCK_ADMIN',
  CP_LOCK_ADMIN: 'CP_LOCK_ADMIN',
  CP_FEATURED_SET: 'CP_FEATURED_SET',
  CP_PAIR_UPDATE: 'CP_PAIR_UPDATE',
  CP_PAIR_DELETE: 'CP_PAIR_DELETE',
  CP_GIFT_UPDATE: 'CP_GIFT_UPDATE',
  BG_CREATE: 'BG_CREATE',
  BG_UPDATE: 'BG_UPDATE',
  BG_DELETE: 'BG_DELETE',
  BG_GRANT: 'BG_GRANT',
  BG_REVOKE: 'BG_REVOKE',
  // 2026-09-26
  FEATURE_GRANT: 'FEATURE_GRANT',
  FEATURE_REVOKE: 'FEATURE_REVOKE',
  TARGET_SET: 'TARGET_SET',
  TARGET_CANCEL: 'TARGET_CANCEL',
  CP_BREAK_FEE_UPDATE: 'CP_BREAK_FEE_UPDATE',
  CP_BREAK_CUSTOM_FEE: 'CP_BREAK_CUSTOM_FEE',
  CP_LEVEL_UPDATE: 'CP_LEVEL_UPDATE',
  CP_LEVEL_DELETE: 'CP_LEVEL_DELETE',
  CP_EFFECT_UPDATE: 'CP_EFFECT_UPDATE',
  GAME_ECONOMY_UPDATE: 'GAME_ECONOMY_UPDATE',
  GAME_PROBABILITY_UPDATE: 'GAME_PROBABILITY_UPDATE',
  GAME_POOL_FUND: 'GAME_POOL_FUND',
  LUCKY_SETTINGS_UPDATE: 'LUCKY_SETTINGS_UPDATE',
  LUCKY_TIERS_UPDATE: 'LUCKY_TIERS_UPDATE',
  LUCKY_POOL_FUND: 'LUCKY_POOL_FUND',
  ROOM_PERMISSION_UPDATE: 'ROOM_PERMISSION_UPDATE',
  ROOM_CLOSE: 'ROOM_CLOSE',
  ROOM_ORDER_UPDATE: 'ROOM_ORDER_UPDATE',
  AGENCY_ACTION: 'AGENCY_ACTION',
  // 2026-10-20 (SPEC52)
  OWNER_PERMISSION_GRANT: 'OWNER_PERMISSION_GRANT',
  OWNER_PERMISSION_REVOKE: 'OWNER_PERMISSION_REVOKE',
  VIP_LEVEL_UPDATE: 'VIP_LEVEL_UPDATE',
  VIP_NAME_COLOR_UPDATE: 'VIP_NAME_COLOR_UPDATE',
  USER_VIP_CHANGE: 'USER_VIP_CHANGE',
  USER_PROGRESSION_UPDATE: 'USER_PROGRESSION_UPDATE',
  GATES_UPDATE: 'GATES_UPDATE',
  ITEM_GRANT: 'ITEM_GRANT',
  PRODUCT_CREATE: 'PRODUCT_CREATE',
  PRODUCT_UPDATE: 'PRODUCT_UPDATE',
  PRODUCT_DELETE: 'PRODUCT_DELETE',
  GIFT_CREATE: 'GIFT_CREATE',
  GIFT_UPDATE: 'GIFT_UPDATE',
  GIFT_DELETE: 'GIFT_DELETE',
  GIFT_CATEGORY_CREATE: 'GIFT_CATEGORY_CREATE',
  GIFT_CATEGORY_UPDATE: 'GIFT_CATEGORY_UPDATE',
  GIFT_CATEGORY_DELETE: 'GIFT_CATEGORY_DELETE',
  GIFT_MOVE: 'GIFT_MOVE',
  AGENCY_PROFILE_UPDATE: 'AGENCY_PROFILE_UPDATE',
  STORE_CATEGORY_CREATE: 'STORE_CATEGORY_CREATE',
  STORE_CATEGORY_UPDATE: 'STORE_CATEGORY_UPDATE',
  STORE_CATEGORY_DELETE: 'STORE_CATEGORY_DELETE',
  ROCKET_CONFIG_UPDATE: 'ROCKET_CONFIG_UPDATE',
  ROCKET_REWARD: 'ROCKET_REWARD',
  PK_CONFIG_UPDATE: 'PK_CONFIG_UPDATE',
  PK_RESULT: 'PK_RESULT',
} as const;

export type AuditAction = (typeof AUDIT_ACTIONS)[keyof typeof AUDIT_ACTIONS];

export interface AdminAuditInput {
  adminId: number;
  action: AuditAction | string;
  targetUserId?: number | null;
  targetType?: string | null;
  targetId?: string | number | null;
  before?: unknown;
  after?: unknown;
  ip?: string | null;
  reason?: string | null;
  sessionId?: string | null;
  userAgent?: string | null;
  device?: string | null;
}

/** Minimal shape of the client the writer needs — the real prisma or a tx. */
export interface AuditWriter {
  adminAuditLog: { create: (args: { data: any }) => Promise<unknown> };
}

const json = (v: unknown) =>
  v === undefined ? undefined : JSON.parse(JSON.stringify(v ?? null, (_k, x) => (typeof x === 'bigint' ? x.toString() : x)));

/** Short device label from the User-Agent / X-Device header ("Android 14 · SM-A266B", "Chrome · Windows"). */
export function deviceFrom(userAgent?: string | null, explicit?: string | null): string | null {
  if (explicit) return String(explicit).slice(0, 120);
  const ua = String(userAgent ?? '');
  if (!ua) return null;
  const android = /Android\s+([\d.]+);\s*([^;)]+)/.exec(ua);
  if (android) return `Android ${android[1]} · ${(android[2] ?? '').trim()}`.slice(0, 120);
  if (/Dart\//.test(ua)) return 'SamaFox app';
  const browser = /(Edg|Chrome|Firefox|Safari)\//.exec(ua)?.[1] ?? 'Browser';
  const os = /Windows|Mac OS X|Linux|iPhone|iPad/.exec(ua)?.[0] ?? '';
  return `${browser === 'Edg' ? 'Edge' : browser}${os ? ' · ' + os : ''}`;
}

function auditData(input: AdminAuditInput) {
  return {
        adminId: input.adminId,
        action: String(input.action),
        targetUserId: input.targetUserId ?? null,
        targetType: input.targetType ?? null,
        targetId: input.targetId == null ? null : String(input.targetId),
        before: json(input.before),
        after: json(input.after),
        ip: input.ip ?? null,
        reason: input.reason ? String(input.reason).slice(0, 500) : null,
        sessionId: input.sessionId ? String(input.sessionId).slice(0, 200) : null,
        userAgent: input.userAgent ? String(input.userAgent).slice(0, 300) : null,
        device: deviceFrom(input.userAgent, input.device),
  };
}

export async function recordAdminAudit(input: AdminAuditInput, db: AuditWriter = prisma as any): Promise<void> {
  try {
    await db.adminAuditLog.create({ data: auditData(input) });
  } catch (err) {
    console.error('[adminAudit] failed:', (err as Error).message);
  }
}

/**
 * Mandatory audit (SPEC52 item 43): written with the caller's transaction and
 * NOT swallowed — if the row cannot be written the whole change rolls back.
 * Use for permissions, VIP config, prices and anything money-related.
 */
export async function recordAdminAuditStrict(db: AuditWriter, input: AdminAuditInput): Promise<void> {
  await db.adminAuditLog.create({ data: auditData(input) });
}

/** Best-effort client IP for the audit row. */
export function requestIp(req: any): string | null {
  const fwd = String(req?.headers?.['x-forwarded-for'] ?? '').split(',')[0]?.trim();
  return fwd || req?.ip || req?.socket?.remoteAddress || null;
}

/**
 * Who, from where, and why — everything an audit row wants from the request.
 * `reason` is read from the body (`reason`) or the `X-Admin-Reason` header so
 * any dashboard call can carry one; the session/device come from the headers
 * the dashboard sends (`X-Session-Id`) or, failing that, the JWT's jti.
 */
export function auditContext(req: any): Pick<AdminAuditInput, 'ip' | 'reason' | 'sessionId' | 'userAgent' | 'device'> {
  const reason = req?.body?.reason ?? req?.headers?.['x-admin-reason'] ?? null;
  return {
    ip: requestIp(req),
    reason: reason == null || reason === '' ? null : String(reason),
    sessionId: (req?.headers?.['x-session-id'] as string) ?? req?.tokenJti ?? null,
    userAgent: (req?.headers?.['user-agent'] as string) ?? null,
    device: (req?.headers?.['x-device'] as string) ?? null,
  };
}
