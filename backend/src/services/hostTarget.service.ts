import prisma from '../utils/prisma';
import { AUDIT_ACTIONS, recordAdminAudit, type AdminAuditInput } from './adminAudit.service';

const db = prisma as any;

/**
 * Target المضيف — ONE source of truth (2026-09-26, item 14).
 *
 * `host_targets` holds every target a host has had: coins, USD, the period it
 * covers, who set it and when. The active one is the ACTIVE row whose period
 * contains now; an ADMIN target outranks an AGENCY one. The app and the
 * dashboard both read it through [getHostTargetView], so they can no longer
 * show different numbers, and `version`/`updatedAt` travel with it so any cache
 * can tell it is stale.
 *
 * Progress is computed here too, from the gifts the host received inside the
 * period (self-gifts excluded) — never from a number the app sends.
 */

export class TargetError extends Error {
  constructor(public code: string, message: string, public status = 400) {
    super(message);
  }
}

export async function getActiveHostTarget(hostId: number, at = new Date()) {
  const rows = await db.hostTarget.findMany({
    where: { hostId, status: 'ACTIVE', periodStart: { lte: at }, periodEnd: { gte: at } },
    orderBy: [{ updatedAt: 'desc' }],
  });
  if (!rows.length) return null;
  return rows.find((r: any) => r.source === 'ADMIN') ?? rows[0];
}

/** Coins the host received inside [from, to], self-gifts excluded. */
export async function earnedInPeriod(hostId: number, from: Date, to: Date): Promise<number> {
  const agg = await db.giftTransaction.aggregate({
    where: { recipientId: hostId, senderId: { not: hostId }, createdAt: { gte: from, lte: to } },
    _sum: { totalCoins: true },
  });
  return Number(agg?._sum?.totalCoins ?? 0);
}

export interface HostTargetView {
  id: number;
  hostId: number;
  targetCoins: number;
  targetUsd: number;
  periodStart: Date;
  periodEnd: Date;
  status: string;
  source: string;
  earnedCoins: number;
  remainingCoins: number;
  progress: number;
  version: number;
  updatedAt: Date;
}

export async function getHostTargetView(hostId: number): Promise<HostTargetView | null> {
  const t = await getActiveHostTarget(hostId);
  if (!t) return null;
  const now = new Date();
  const earned = await earnedInPeriod(hostId, t.periodStart, t.periodEnd < now ? t.periodEnd : now);
  const target = Number(t.targetCoins);
  return {
    id: t.id,
    hostId,
    targetCoins: target,
    targetUsd: Number(t.targetUsd),
    periodStart: t.periodStart,
    periodEnd: t.periodEnd,
    status: t.status,
    source: t.source,
    earnedCoins: earned,
    remainingCoins: Math.max(0, target - earned),
    progress: target > 0 ? Math.min(1, earned / target) : 0,
    version: t.version,
    updatedAt: t.updatedAt,
  };
}

type AuditCtx = Pick<AdminAuditInput, 'ip' | 'reason' | 'sessionId' | 'userAgent'>;

export interface SetTargetInput {
  hostId: number;
  targetCoins: number;
  targetUsd?: number;
  periodStart: Date;
  periodEnd: Date;
  note?: string | null;
  source: 'ADMIN' | 'AGENCY';
  agencyId?: number | null;
  actorId: number;
}

/**
 * Set a host's target. Any ACTIVE target of the same source whose period
 * overlaps is cancelled in the same transaction, so there is never more than
 * one live number per source.
 */
export async function setHostTarget(input: SetTargetInput, audit?: AuditCtx) {
  const coins = Math.floor(Number(input.targetCoins));
  const usd = Number(input.targetUsd ?? 0);
  if (!Number.isFinite(coins) || coins < 0) throw new TargetError('BAD_COINS', 'قيمة التارجت بالكوينز غير صحيحة');
  if (!Number.isFinite(usd) || usd < 0) throw new TargetError('BAD_USD', 'قيمة التارجت بالدولار غير صحيحة');
  const start = new Date(input.periodStart);
  const end = new Date(input.periodEnd);
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())) throw new TargetError('BAD_PERIOD', 'تاريخ البداية/النهاية غير صحيح');
  if (end <= start) throw new TargetError('BAD_PERIOD', 'تاريخ النهاية يجب أن يكون بعد البداية');
  const host = await db.user.findUnique({ where: { id: input.hostId }, select: { id: true } });
  if (!host) throw new TargetError('NOT_FOUND', 'المستخدم غير موجود', 404);

  return db.$transaction(async (tx: any) => {
    const overlapping = await tx.hostTarget.findMany({
      where: {
        hostId: input.hostId,
        source: input.source,
        status: 'ACTIVE',
        periodStart: { lte: end },
        periodEnd: { gte: start },
      },
    });
    if (overlapping.length) {
      await tx.hostTarget.updateMany({
        where: { id: { in: overlapping.map((o: any) => o.id) } },
        data: { status: 'CANCELLED', updatedBy: input.actorId },
      });
    }
    const last = await tx.hostTarget.findFirst({ where: { hostId: input.hostId }, orderBy: { version: 'desc' }, select: { version: true } });
    const row = await tx.hostTarget.create({
      data: {
        hostId: input.hostId,
        agencyId: input.agencyId ?? null,
        targetCoins: BigInt(coins),
        targetUsd: usd,
        periodStart: start,
        periodEnd: end,
        status: 'ACTIVE',
        source: input.source,
        note: input.note ?? null,
        version: (last?.version ?? 0) + 1,
        updatedBy: input.actorId,
      },
    });
    if (input.source === 'ADMIN') {
      await recordAdminAudit(
        {
          adminId: input.actorId,
          action: AUDIT_ACTIONS.TARGET_SET,
          targetUserId: input.hostId,
          targetType: 'host_target',
          targetId: row.id,
          before: overlapping.map((o: any) => ({
            id: o.id,
            targetCoins: String(o.targetCoins),
            targetUsd: String(o.targetUsd),
            periodStart: o.periodStart,
            periodEnd: o.periodEnd,
          })),
          after: { id: row.id, targetCoins: coins, targetUsd: usd, periodStart: start, periodEnd: end, version: row.version },
          ...(audit ?? {}),
        },
        tx,
      );
    }
    return row;
  });
}

export async function cancelHostTarget(id: number, adminId: number, audit?: AuditCtx) {
  const before = await db.hostTarget.findUnique({ where: { id } });
  if (!before) throw new TargetError('NOT_FOUND', 'التارجت غير موجود', 404);
  return db.$transaction(async (tx: any) => {
    const row = await tx.hostTarget.update({
      where: { id },
      data: { status: 'CANCELLED', updatedBy: adminId, version: { increment: 1 } },
    });
    await recordAdminAudit(
      {
        adminId,
        action: AUDIT_ACTIONS.TARGET_CANCEL,
        targetUserId: before.hostId,
        targetType: 'host_target',
        targetId: id,
        before: { status: before.status, targetCoins: String(before.targetCoins) },
        after: { status: 'CANCELLED' },
        ...(audit ?? {}),
      },
      tx,
    );
    return row;
  });
}

export async function listHostTargets(hostId: number) {
  const rows = await db.hostTarget.findMany({ where: { hostId }, orderBy: { createdAt: 'desc' }, take: 50 });
  return rows.map((r: any) => ({ ...r, targetCoins: Number(r.targetCoins), targetUsd: Number(r.targetUsd) }));
}
