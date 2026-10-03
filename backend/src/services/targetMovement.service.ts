import prisma from '../utils/prisma';

/**
 * سجل تعديلات التارجت — one row per movement of a membership's target balance.
 *
 * On 2026-10-03 an agent's target read 0 because of a 50M deduction made weeks
 * earlier from the dashboard, and the only trace was a generic audit line. Every
 * writer of `targetAdjustmentCoins` now leaves a row here naming who moved how
 * much, so the dashboard can answer "why is my target what it is".
 *
 * Callers inside a transaction pass `tx`, so the row lands with the movement or
 * not at all. Outside one, a failed write is logged and swallowed: the action
 * itself must never fail because the log could not be written.
 */
export type TargetMovementKind = 'admin_add' | 'admin_deduct' | 'sale_out' | 'sale_in' | 'convert' | 'charge';

export interface TargetMovementInput {
  memberId: number;
  userId: number;
  agencyId: number;
  kind: TargetMovementKind;
  /** Signed: negative takes target away. */
  amountCoins: number | bigint;
  actorId?: number | null;
  counterpartId?: number | null;
  note?: string | null;
}

export async function recordTargetMovement(input: TargetMovementInput, db: any = prisma): Promise<void> {
  const write = db.targetMovement.create({
    data: {
      memberId: input.memberId,
      userId: input.userId,
      agencyId: input.agencyId,
      kind: input.kind,
      amountCoins: BigInt(input.amountCoins),
      actorId: input.actorId ?? null,
      counterpartId: input.counterpartId ?? null,
      note: input.note ?? null,
    },
  });
  if (db !== prisma) {
    await write; // inside the caller's transaction: fail together
    return;
  }
  try {
    await write;
  } catch (e) {
    console.warn('[targetMovement] record failed:', (e as Error).message);
  }
}
