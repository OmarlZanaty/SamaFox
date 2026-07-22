import prisma from '../utils/prisma';
import { createNotification } from './notification.service';

// VIP thresholds: 500k per level up to VIP5 (2.5M), then each further level
// needs 30% more cumulative recharge than the previous one.
const BASE_STEP = 500000;
const FLAT_MAX_LEVEL = 5;
const GROWTH = 1.3;
const HARD_CAP_LEVEL = 100;

/** Cumulative recharge required to reach a given VIP level. */
export function vipThreshold(level: number): number {
  if (level <= 0) return 0;
  if (level <= FLAT_MAX_LEVEL) return level * BASE_STEP;
  let t = FLAT_MAX_LEVEL * BASE_STEP; // threshold at VIP5
  for (let l = FLAT_MAX_LEVEL + 1; l <= level; l++) t = Math.round(t * GROWTH);
  return t;
}

/** Highest VIP level fully covered by a cumulative recharge total. */
export function computeVipLevel(totalRecharge: number): number {
  let level = 0;
  while (level < HARD_CAP_LEVEL && vipThreshold(level + 1) <= totalRecharge) {
    level++;
  }
  return level;
}

/** Admin threshold overrides from VipLevelConfig (level -> cumulative coins). */
export async function getVipThresholdOverrides(): Promise<Map<number, number>> {
  const configs = await prisma.vipLevelConfig.findMany({
    where: { threshold: { not: null } },
    select: { level: true, threshold: true },
  });
  return new Map(configs.map((c) => [c.level, c.threshold!]));
}

/** Cumulative coins required for [level], honoring admin overrides (group 10). */
export function vipThresholdWithOverrides(level: number, overrides: Map<number, number>): number {
  return overrides.get(level) ?? vipThreshold(level);
}

/** computeVipLevel but with admin-configured thresholds taking precedence. */
export function computeVipLevelWithOverrides(
  totalRecharge: number,
  overrides: Map<number, number>,
): number {
  let level = 0;
  while (
    level < HARD_CAP_LEVEL &&
    vipThresholdWithOverrides(level + 1, overrides) <= totalRecharge
  ) {
    level++;
  }
  return level;
}

/**
 * Grant everything configured for [level] (VipLevelConfig): the legacy seat
 * frame plus every item in rewardItemIds — badges/frames/entrances from the
 * app OR private store (group 10). Idempotent: never double-grants a UserItem.
 */
async function grantLevelRewards(userId: number, level: number): Promise<void> {
  const cfg: any = await prisma.vipLevelConfig.findUnique({ where: { level } });
  if (!cfg) return;

  const itemIds = new Set<string>(
    [cfg.frameItemId, ...(cfg.rewardItemIds ?? [])].filter(Boolean) as string[],
  );
  if (!itemIds.size) return;

  // Only grant items that still exist (an admin may have deleted one).
  const items = await prisma.item.findMany({
    where: { id: { in: [...itemIds] } },
    select: { id: true },
  });
  for (const item of items) {
    await prisma.userItem.upsert({
      where: { userId_itemId: { userId, itemId: item.id } },
      update: {},
      create: { userId, itemId: item.id, isActive: false },
    });
  }
}

/**
 * Re-evaluate a user's VIP level from their cumulative recharge. Call after any
 * coin top-up (the totalRecharge increment should already be applied). On a
 * level-up it bumps vipLevel, grants every newly-reached level's frame/badge,
 * and notifies the user. Safe to call on every credit (no-op when unchanged).
 */
export async function evaluateVip(
  userId: number,
): Promise<{ leveledUp: boolean; vipLevel: number }> {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { vipLevel: true, totalRecharge: true },
  });
  if (!user) return { leveledUp: false, vipLevel: 0 };

  const overrides = await getVipThresholdOverrides();
  const newLevel = computeVipLevelWithOverrides(user.totalRecharge, overrides);
  if (newLevel <= user.vipLevel) {
    return { leveledUp: false, vipLevel: user.vipLevel };
  }

  await prisma.user.update({ where: { id: userId }, data: { vipLevel: newLevel } });
  for (let lvl = user.vipLevel + 1; lvl <= newLevel; lvl++) {
    await grantLevelRewards(userId, lvl);
  }

  try {
    await createNotification({
      userId,
      type: 'vip_level_up',
      title: 'ترقية VIP 👑',
      body: `تهانينا! وصلت إلى مستوى VIP ${newLevel}`,
      data: { vipLevel: newLevel },
    });
  } catch (e) {
    console.warn('VIP level-up notification failed:', e);
  }

  // Medals: unlock any vip_level achievements this promotion earned.
  try {
    const { checkAchievements } = await import('../controllers/achievement.controller');
    await checkAchievements(userId, 'vip_level', newLevel);
  } catch (e) {
    console.warn('VIP achievement check failed:', e);
  }

  return { leveledUp: true, vipLevel: newLevel };
}
