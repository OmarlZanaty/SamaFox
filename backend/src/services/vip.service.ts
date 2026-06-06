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

/**
 * Grant the badge + seat frame configured for [level] (VipLevelConfig).
 * Idempotent: never double-grants a UserItem.
 */
async function grantLevelRewards(userId: number, level: number): Promise<void> {
  const cfg = await prisma.vipLevelConfig.findUnique({ where: { level } });
  if (!cfg?.frameItemId) return;
  const item = await prisma.item.findUnique({ where: { id: cfg.frameItemId } });
  if (!item) return;
  await prisma.userItem.upsert({
    where: { userId_itemId: { userId, itemId: cfg.frameItemId } },
    update: {},
    create: { userId, itemId: cfg.frameItemId, isActive: false },
  });
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

  const newLevel = computeVipLevel(user.totalRecharge);
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

  return { leveledUp: true, vipLevel: newLevel };
}
