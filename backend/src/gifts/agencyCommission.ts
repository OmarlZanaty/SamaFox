import prisma from '../utils/prisma';
import { retryTxConflicts } from './giftRetry';

/**
 * The ONE account that may collect the 20% agent share of a hosting agency: the
 * registered agent (`ChargingAgency.userId`) holding the OWNER seat. A فرع, a
 * member, or a stray second OWNER row never qualifies. Null = nobody gets it.
 */
export async function findAgencyCommissionOwner(
  tx: any,
  agencyId: number,
): Promise<{ id: number; userId: number } | null> {
  const agency = await tx.chargingAgency.findUnique({
    where: { id: agencyId },
    select: { type: true, userId: true },
  });
  if (!agency || agency.type !== 'HOSTING') return null;
  return tx.agencyMember.findFirst({
    where: { agencyId, userId: agency.userId, role: 'OWNER' },
    select: { id: true, userId: true },
  });
}

/**
 * Agency commission accrual, applied outside the gift transaction. Plain atomic
 * increments (never read-modify-write), consistent lock order (by member id), each
 * in its own tiny transaction and retried on any conflict.
 */
export async function applyCommissionAccrual(
  accrual: { ownerMemberId: number; hostMemberId: number; amount: number },
  db: any = prisma,
): Promise<void> {
  const inc = BigInt(accrual.amount);
  await retryTxConflicts(async () => {
    if (accrual.ownerMemberId === accrual.hostMemberId) {
      await db.agencyMember.update({
        where: { id: accrual.ownerMemberId },
        data: { commissionTargetCoins: { increment: inc }, commissionGeneratedCoins: { increment: inc } },
      });
      return;
    }
    await db.$transaction(async (t: any) => {
      const ops = [
        { id: accrual.ownerMemberId, data: { commissionTargetCoins: { increment: inc } } },
        { id: accrual.hostMemberId, data: { commissionGeneratedCoins: { increment: inc } } },
      ].sort((x, y) => x.id - y.id);
      for (const op of ops) await t.agencyMember.update({ where: { id: op.id }, data: op.data });
    });
  }, 12);
}
