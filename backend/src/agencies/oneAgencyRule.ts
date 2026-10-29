import type { AgencyMember, ChargingAgency } from '@prisma/client';

export const ALREADY_IN_AGENCY_MESSAGE = 'عذراً، هذا المستخدم موجود في وكالة بالفعل';

/** Only seats in other live (approved) agencies block; OWNER + OWNER remains allowed.
 * Seats in rejected or pending agencies are inert and must not block.
 */
export async function findBlockingMembership(
  tx: any,
  userId: number,
  targetAgencyId: number,
  newRole: 'OWNER' | 'BRANCH' | 'MEMBER',
): Promise<(AgencyMember & { agency: Pick<ChargingAgency, 'id' | 'agencyName' | 'type'> }) | null> {
  return tx.agencyMember.findFirst({
    where: {
      userId,
      agencyId: { not: targetAgencyId },
      agency: { status: 'approved' },
      role: { in: newRole === 'OWNER' ? ['MEMBER', 'BRANCH'] : ['OWNER', 'BRANCH', 'MEMBER'] },
    },
    include: { agency: { select: { id: true, agencyName: true, type: true } } },
  });
}
