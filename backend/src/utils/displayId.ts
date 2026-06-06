import { Prisma } from '@prisma/client';

/** First valid 6-digit public ID. */
export const MIN_DISPLAY_ID = 100000;

/**
 * Allocate the next unique 6-digit public display ID inside a transaction.
 * The shared UserIdSequence row is floored to the 6-digit range, so even
 * accounts created before the 6-digit switch hand out 100000+ from now on.
 */
export async function nextDisplayId(tx: Prisma.TransactionClient): Promise<number> {
  // Ensure the sequence exists, starting in the 6-digit range.
  await tx.userIdSequence.upsert({
    where: { id: 1 },
    update: {},
    create: { id: 1, nextId: MIN_DISPLAY_ID },
  });

  // Floor a legacy 5-digit cursor up to 6 digits.
  const current = await tx.userIdSequence.findUnique({ where: { id: 1 } });
  if (current && current.nextId < MIN_DISPLAY_ID) {
    await tx.userIdSequence.update({
      where: { id: 1 },
      data: { nextId: MIN_DISPLAY_ID },
    });
  }

  // Atomically reserve the current value, advancing the cursor for the next caller.
  const updated = await tx.userIdSequence.update({
    where: { id: 1 },
    data: { nextId: { increment: 1 } },
  });

  let candidate = Math.max(updated.nextId - 1, MIN_DISPLAY_ID);
  // Defensive: skip any already-taken id (e.g. after a manual admin change).
  for (let i = 0; i < 1000; i++) {
    const taken = await tx.user.findUnique({ where: { displayId: candidate } });
    if (!taken) break;
    candidate++;
  }
  return candidate;
}
