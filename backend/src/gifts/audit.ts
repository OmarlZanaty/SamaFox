import prisma from '../utils/prisma';
import type { GiftAuditAction } from '@prisma/client';

export interface AuditLogInput {
  adminId: number;
  giftId?: string | null;
  action: GiftAuditAction;
  before?: unknown;
  after?: unknown;
}

export async function recordGiftAudit({ adminId, giftId, action, before, after }: AuditLogInput): Promise<void> {
  try {
    await prisma.giftAdminAudit.create({
      data: {
        adminId,
        giftId: giftId ?? null,
        action,
        diff: before === undefined && after === undefined ? undefined : { before: before ?? null, after: after ?? null },
      },
    });
  } catch (err) {
    // Audit failures must not break the admin action.
    console.error('[giftAudit] failed:', (err as Error).message);
  }
}
