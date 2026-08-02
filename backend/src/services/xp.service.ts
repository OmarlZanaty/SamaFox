import prisma from '../utils/prisma';
import type { Prisma } from '@prisma/client';
import { createNotification } from './notification.service';

type DbClient = typeof prisma | Prisma.TransactionClient;

/**
 * Calculate level from XP
 */
export const calculateLevel = (xp: number): number => {
  // Level formula: level = floor(sqrt(xp / 100))
  // This means: Level 1 = 0-99 XP, Level 2 = 100-399 XP, Level 3 = 400-899 XP, etc.
  return Math.floor(Math.sqrt(xp / 100)) + 1;
};

/** Hard ceiling, mirroring the 1-100 range the admin dashboard accepts. */
const MAX_LEVEL = 100;

/**
 * Admin threshold overrides from LevelConfig (level -> cumulative XP).
 * Empty map = nothing configured yet.
 */
export const getLevelThresholdOverrides = async (
  client: DbClient = prisma,
): Promise<Map<number, number>> => {
  try {
    const configs = await (client as any).levelConfig.findMany({
      where: { threshold: { not: null } },
      select: { level: true, threshold: true },
    });
    return new Map<number, number>(
      configs.map((c: any) => [Number(c.level), Number(c.threshold)]),
    );
  } catch (e) {
    // Older database without the table — fall back to the built-in curve
    // rather than failing the surrounding operation (usually a gift).
    console.warn('[xp.service] level config lookup failed, using formula:', (e as Error).message);
    return new Map();
  }
};

/** Cumulative XP required for [level], honoring admin overrides. */
export const levelThresholdWithOverrides = (
  level: number,
  overrides: Map<number, number>,
): number => overrides.get(level) ?? Math.pow(level - 1, 2) * 100;

/**
 * calculateLevel with admin-configured thresholds taking precedence.
 *
 * With no overrides this is exactly the old sqrt curve, which is what keeps
 * every existing user's level unchanged until an admin actually sets tiers.
 */
export const calculateLevelWithOverrides = (
  xp: number,
  overrides: Map<number, number>,
): number => {
  if (overrides.size === 0) return calculateLevel(xp);
  let level = 1;
  while (level < MAX_LEVEL && levelThresholdWithOverrides(level + 1, overrides) <= xp) {
    level++;
  }
  return level;
};

/**
 * Calculate XP needed for next level
 */
export const xpForNextLevel = (currentLevel: number): number => {
  // XP needed for level N = (N-1)^2 * 100
  return Math.pow(currentLevel, 2) * 100;
};

/**
 * Grant every item configured on LevelConfig for [level]. Idempotent — the
 * upsert never double-grants a UserItem, so re-reaching a level is harmless.
 *
 * Runs on the caller's client so the grant commits atomically with the level
 * change (awardUserXP is called inside the gift transaction).
 */
export const grantLevelRewards = async (
  userId: number,
  level: number,
  client: DbClient = prisma,
): Promise<string[]> => {
  try {
    const cfg: any = await (client as any).levelConfig.findUnique({ where: { level } });
    const itemIds = [...new Set<string>((cfg?.rewardItemIds ?? []).filter(Boolean))];
    if (!itemIds.length) return [];

    // Only grant items that still exist — an admin may have deleted one.
    const items = await client.item.findMany({
      where: { id: { in: itemIds } },
      select: { id: true },
    });
    for (const item of items) {
      await client.userItem.upsert({
        where: { userId_itemId: { userId, itemId: item.id } },
        update: {},
        create: { userId, itemId: item.id, isActive: false },
      });
    }
    return items.map((i) => i.id);
  } catch (e) {
    // A missing table or a bad config must never fail the gift that triggered it.
    console.warn('[xp.service] level reward grant failed:', (e as Error).message);
    return [];
  }
};

/**
 * Tell the user they levelled up. Deliberately NOT called inside awardUserXP:
 * that runs in the gift transaction, and a rollback would leave a notification
 * for a level-up that never committed. Callers fire this after the commit.
 */
export const notifyLevelUp = async (
  userId: number,
  level: number,
  grantedItemCount = 0,
): Promise<void> => {
  try {
    await createNotification({
      userId,
      type: 'level_up',
      title: 'ترقية المستوى ⭐',
      body: grantedItemCount > 0
        ? `تهانينا! وصلت إلى المستوى ${level} وحصلت على ${grantedItemCount} هدية`
        : `تهانينا! وصلت إلى المستوى ${level}`,
      data: { level, grantedItemCount },
    });
  } catch (e) {
    console.warn('level-up notification failed:', e);
  }
};

/**
 * Award XP to a room
 */
export const awardRoomXP = async (roomId: number, xpAmount: number) => {
  try {
    const room = await prisma.room.findUnique({
      where: { id: roomId }
    });

    if (!room) {
      return { success: false, error: 'Room not found' };
    }

    const newXP = room.xp + xpAmount;
    const newLevel = calculateLevel(newXP);
    const leveledUp = newLevel > room.level;

    await prisma.room.update({
      where: { id: roomId },
      data: {
        xp: newXP,
        level: newLevel
      }
    });

    return {
      success: true,
      xp: newXP,
      level: newLevel,
      leveledUp,
      xpGained: xpAmount
    };
  } catch (error) {
    console.error('Error awarding room XP:', error);
    return { success: false, error: 'Failed to award XP' };
  }
};

/**
 * Award XP to a user. Pass a transaction client (`tx`) when called from
 * inside another `$transaction` (e.g. gift receipt) so the XP/level update
 * commits atomically with the rest of that operation.
 */
export const awardUserXP = async (userId: number, xpAmount: number, client: DbClient = prisma) => {
  try {
    const user = await client.user.findUnique({
      where: { id: userId }
    });

    if (!user) {
      return { success: false, error: 'User not found' };
    }

    const newXP = user.xp + xpAmount;
    const overrides = await getLevelThresholdOverrides(client);
    const newLevel = calculateLevelWithOverrides(newXP, overrides);
    // Never demote on an XP gain: if an admin raises a threshold later, a user
    // who already reached a level keeps it instead of silently dropping.
    const leveledUp = newLevel > user.level;

    const effectiveLevel = Math.max(newLevel, user.level);

    await client.user.update({
      where: { id: userId },
      data: {
        xp: newXP,
        level: effectiveLevel
      }
    });

    // Grant the configured items for EVERY level crossed, not just the final
    // one — a large gift can jump several levels at once.
    const grantedItemIds: string[] = [];
    if (leveledUp) {
      for (let lvl = user.level + 1; lvl <= effectiveLevel; lvl++) {
        grantedItemIds.push(...(await grantLevelRewards(userId, lvl, client)));
      }
    }

    return {
      success: true,
      xp: newXP,
      level: effectiveLevel,
      previousLevel: user.level,
      leveledUp,
      grantedItemIds,
      xpGained: xpAmount
    };
  } catch (error) {
    console.error('Error awarding user XP:', error);
    return { success: false, error: 'Failed to award XP' };
  }
};

/**
 * Get room level info
 */
export const getRoomLevelInfo = async (roomId: number) => {
  try {
    const room = await prisma.room.findUnique({
      where: { id: roomId },
      select: {
        xp: true,
        level: true
      }
    });

    if (!room) {
      return { success: false, error: 'Room not found' };
    }

    const currentLevelXP = Math.pow(room.level - 1, 2) * 100;
    const nextLevelXP = xpForNextLevel(room.level);
    const xpInCurrentLevel = room.xp - currentLevelXP;
    const xpNeededForNextLevel = nextLevelXP - room.xp;

    return {
      success: true,
      level: room.level,
      xp: room.xp,
      currentLevelXP,
      nextLevelXP,
      xpInCurrentLevel,
      xpNeededForNextLevel,
      progress: (xpInCurrentLevel / (nextLevelXP - currentLevelXP)) * 100
    };
  } catch (error) {
    console.error('Error getting room level info:', error);
    return { success: false, error: 'Failed to get level info' };
  }
};

/**
 * Get user level info
 */
export const getUserLevelInfo = async (userId: number) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        xp: true,
        level: true
      }
    });

    if (!user) {
      return { success: false, error: 'User not found' };
    }

    const currentLevelXP = Math.pow(user.level - 1, 2) * 100;
    const nextLevelXP = xpForNextLevel(user.level);
    const xpInCurrentLevel = user.xp - currentLevelXP;
    const xpNeededForNextLevel = nextLevelXP - user.xp;

    return {
      success: true,
      level: user.level,
      xp: user.xp,
      currentLevelXP,
      nextLevelXP,
      xpInCurrentLevel,
      xpNeededForNextLevel,
      progress: (xpInCurrentLevel / (nextLevelXP - currentLevelXP)) * 100
    };
  } catch (error) {
    console.error('Error getting user level info:', error);
    return { success: false, error: 'Failed to get level info' };
  }
};
