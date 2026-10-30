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
