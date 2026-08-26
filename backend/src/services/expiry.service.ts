import prisma from '../utils/prisma';

/**
 * Time-limited products (owner request): a frame, vehicle, badge, bubble or
 * VIP tier can be sold for 7/15/20/30 days or أبدي.
 *
 * Two rules only:
 *   - `UserItem.expiresAt` is stamped at acquisition from `Item.durationDays`.
 *     null means permanent, which is every row that existed before this.
 *   - Once past, the item is unequipped and stops being returned as owned.
 *
 * Expiry is applied by a sweep rather than checked at every read, so a lapsed
 * frame disappears for OTHER users too, not just when the owner opens the app.
 */

/** Expiry stamp for a newly acquired item. null when the product is permanent. */
export function expiryFromDuration(durationDays?: number | null): Date | null {
  if (!durationDays || durationDays <= 0) return null;
  return new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000);
}

/**
 * Retire everything whose term has run out.
 *
 * Items are unequipped and deleted from the inventory; a lapsed VIP tier drops
 * the user back to the level their recharge actually earns, so buying VIP 5 for
 * a month can never permanently overwrite an earned VIP 2.
 */
export async function sweepExpired(now: Date = new Date()): Promise<{
  items: number;
  vips: number;
  backgrounds: number;
}> {
  let items = 0;
  let vips = 0;
  let backgrounds = 0;

  try {
    // Clear the equipped-frame pointer first: it lives on User, so deleting the
    // UserItem alone would leave the avatar wearing a frame it no longer owns.
    const lapsed = await (prisma as any).userItem.findMany({
      where: { expiresAt: { not: null, lte: now } },
      select: { id: true, userId: true, itemId: true },
    });
    for (const row of lapsed) {
      await (prisma as any).user.updateMany({
        where: { id: row.userId, activeFrameId: row.itemId },
        data: { activeFrameId: null, avatarFrameUrl: null },
      });
    }
    const del = await (prisma as any).userItem.deleteMany({
      where: { expiresAt: { not: null, lte: now } },
    });
    items = del.count;
  } catch (e) {
    console.warn('[expiry] item sweep failed:', (e as Error).message);
  }

  try {
    const { computeVipLevelWithOverrides, getVipThresholdOverrides } = await import('./vip.service');
    const overrides = await getVipThresholdOverrides();
    const lapsedVips = await (prisma as any).user.findMany({
      where: { vipExpiresAt: { not: null, lte: now } },
      select: { id: true, totalRecharge: true },
    });
    for (const u of lapsedVips) {
      const earned = computeVipLevelWithOverrides(u.totalRecharge, overrides);
      await (prisma as any).user.update({
        where: { id: u.id },
        data: { vipLevel: earned, vipExpiresAt: null },
      });
    }
    vips = lapsedVips.length;
  } catch (e) {
    console.warn('[expiry] vip sweep failed:', (e as Error).message);
  }

  try {
    const bg = await (prisma as any).room.updateMany({
      where: { backgroundExpiresAt: { not: null, lte: now } },
      data: { backgroundImageUrl: null, backgroundExpiresAt: null },
    });
    backgrounds = bg.count;
  } catch (e) {
    console.warn('[expiry] background sweep failed:', (e as Error).message);
  }

  if (items || vips || backgrounds) {
    console.log('[expiry] retired', { items, vips, backgrounds });
  }
  return { items, vips, backgrounds };
}

let timer: NodeJS.Timeout | null = null;

/** Run the sweep on boot and every 15 minutes after. */
export function startExpirySweep(intervalMs = 15 * 60 * 1000): void {
  if (timer) return;
  sweepExpired().catch(() => {});
  timer = setInterval(() => {
    sweepExpired().catch(() => {});
  }, intervalMs);
  // Never hold the process open for the sake of a cleanup timer.
  timer.unref?.();
}
