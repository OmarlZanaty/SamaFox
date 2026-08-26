import prisma from '../utils/prisma';

/**
 * Broadcast time (وقت البث) per host, for agency targets.
 *
 * A "stint" is one continuous spell on a mic seat. Stints are recorded rather
 * than a running total so the owner's requested view — a row per calendar day
 * with the hours on it — can be produced for any date range.
 *
 * Deliberately fire-and-forget: mic traffic is hot, and a failure to record
 * time must never break someone taking or leaving a seat.
 */

/** Open a stint when a user takes a mic seat. No-op if one is already open. */
export async function startBroadcast(userId: number, roomId: number): Promise<void> {
  if (!userId || !roomId) return;
  try {
    const open = await (prisma as any).broadcastSession.findFirst({
      where: { userId, endedAt: null },
      select: { id: true, roomId: true },
    });
    // Already on a mic somewhere: close the old stint first so time can never
    // be double-counted across two rooms.
    if (open) {
      if (open.roomId === roomId) return;
      await endBroadcast(userId);
    }
    await (prisma as any).broadcastSession.create({ data: { userId, roomId } });
  } catch (e) {
    console.warn('[broadcast] start failed:', (e as Error).message);
  }
}

/** Close the open stint, if any, and store its length in seconds. */
export async function endBroadcast(userId: number): Promise<void> {
  if (!userId) return;
  try {
    const open = await (prisma as any).broadcastSession.findFirst({
      where: { userId, endedAt: null },
      orderBy: { startedAt: 'desc' },
      select: { id: true, startedAt: true },
    });
    if (!open) return;
    const endedAt = new Date();
    const seconds = Math.max(
      0,
      Math.floor((endedAt.getTime() - new Date(open.startedAt).getTime()) / 1000),
    );
    await (prisma as any).broadcastSession.update({
      where: { id: open.id },
      data: { endedAt, seconds },
    });
  } catch (e) {
    console.warn('[broadcast] end failed:', (e as Error).message);
  }
}

export type BroadcastDay = { date: string; hours: number; seconds: number };

/**
 * Per-day totals for one user, newest first. Days with no airtime are omitted,
 * which is what the owner's example table shows.
 */
export async function getDailyBroadcast(
  userId: number,
  fromDate?: Date,
  toDate?: Date,
): Promise<BroadcastDay[]> {
  const where: any = { userId, endedAt: { not: null } };
  if (fromDate || toDate) {
    where.startedAt = {};
    if (fromDate) where.startedAt.gte = fromDate;
    if (toDate) where.startedAt.lte = toDate;
  }

  const rows = await (prisma as any).broadcastSession.findMany({
    where,
    select: { startedAt: true, seconds: true },
    orderBy: { startedAt: 'desc' },
  });

  const perDay = new Map<string, number>();
  for (const r of rows) {
    const key = new Date(r.startedAt).toISOString().slice(0, 10);
    perDay.set(key, (perDay.get(key) ?? 0) + Number(r.seconds ?? 0));
  }

  return [...perDay.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([date, seconds]) => ({
      date,
      seconds,
      // One decimal is enough for "2 hours / 1 hour" style reporting.
      hours: Math.round((seconds / 3600) * 10) / 10,
    }));
}

/** Total airtime in seconds for a user over a range — used by target views. */
export async function getBroadcastSeconds(
  userId: number,
  fromDate?: Date,
  toDate?: Date,
): Promise<number> {
  const days = await getDailyBroadcast(userId, fromDate, toDate);
  return days.reduce((sum, d) => sum + d.seconds, 0);
}
