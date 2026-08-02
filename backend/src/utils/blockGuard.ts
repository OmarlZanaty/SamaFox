import prisma from './prisma';

/**
 * Personal blacklist (القائمة السوداء) enforcement.
 *
 * `UserBlock` rows were only ever written — nothing read them — so blocking
 * someone changed nothing at all. Every path that lets one user reach another
 * should go through here.
 */

/**
 * True when either user has blocked the other.
 *
 * Deliberately symmetric: if A blocks B, B must not be able to message A
 * either, otherwise blocking only hides the harasser's inbox from the victim.
 * Fails open on a database error so an outage can't silently drop messages.
 */
export async function isBlockedBetween(a: number, b: number): Promise<boolean> {
  if (!a || !b || a === b) return false;
  try {
    const row = await (prisma as any).userBlock.findFirst({
      where: {
        OR: [
          { blockerId: a, blockedId: b },
          { blockerId: b, blockedId: a },
        ],
      },
      select: { id: true },
    });
    return !!row;
  } catch (e) {
    console.warn('[blockGuard] lookup failed, allowing:', e);
    return false;
  }
}

/**
 * Every user id that [userId] has blocked or been blocked by — used to keep
 * those conversations out of the inbox list.
 */
export async function blockedUserIds(userId: number): Promise<Set<number>> {
  if (!userId) return new Set();
  try {
    const rows = await (prisma as any).userBlock.findMany({
      where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
      select: { blockerId: true, blockedId: true },
    });
    const out = new Set<number>();
    for (const r of rows) {
      out.add(r.blockerId === userId ? r.blockedId : r.blockerId);
    }
    return out;
  } catch (e) {
    console.warn('[blockGuard] list failed:', e);
    return new Set();
  }
}
