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
