import prisma from '../utils/prisma';
import type { Prisma } from '@prisma/client';

type DbClient = typeof prisma | Prisma.TransactionClient;

/**
 * Calculate level from XP
 */
export const calculateLevel = (xp: number): number => {
  // Level formula: level = floor(sqrt(xp / 100))
  // This means: Level 1 = 0-99 XP, Level 2 = 100-399 XP, Level 3 = 400-899 XP, etc.
  return Math.floor(Math.sqrt(xp / 100)) + 1;
};

/**
 * Calculate XP needed for next level
 */
export const xpForNextLevel = (currentLevel: number): number => {
  // XP needed for level N = (N-1)^2 * 100
  return Math.pow(currentLevel, 2) * 100;
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
    const newLevel = calculateLevel(newXP);
    const leveledUp = newLevel > user.level;

    await client.user.update({
      where: { id: userId },
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
