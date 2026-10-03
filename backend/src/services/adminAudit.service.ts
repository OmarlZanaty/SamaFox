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
}

/** Minimal shape of the client the writer needs — the real prisma or a tx. */
export interface AuditWriter {
  adminAuditLog: { create: (args: { data: any }) => Promise<unknown> };
}

const json = (v: unknown) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v ?? null)));

export async function recordAdminAudit(input: AdminAuditInput, db: AuditWriter = prisma as any): Promise<void> {
  try {
    await db.adminAuditLog.create({
      data: {
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
      },
    });
  } catch (err) {
    console.error('[adminAudit] failed:', (err as Error).message);
  }
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
export function auditContext(req: any): Pick<AdminAuditInput, 'ip' | 'reason' | 'sessionId' | 'userAgent'> {
  const reason = req?.body?.reason ?? req?.headers?.['x-admin-reason'] ?? null;
  return {
    ip: requestIp(req),
    reason: reason == null || reason === '' ? null : String(reason),
    sessionId: (req?.headers?.['x-session-id'] as string) ?? req?.tokenJti ?? null,
    userAgent: (req?.headers?.['user-agent'] as string) ?? null,
  };
}
