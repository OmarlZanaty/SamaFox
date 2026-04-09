import { Request, Response } from 'express';
import prisma from '../utils/prisma';

/**
 * Get all achievements
 */
export const getAllAchievements = async (req: Request, res: Response) => {
  try {
    const achievements = await prisma.achievement.findMany({
      orderBy: {
        target: 'asc'
      }
    });

    res.json(achievements);
  } catch (error) {
    console.error('Error fetching achievements:', error);
    res.status(500).json({ error: 'Failed to fetch achievements' });
  }
};

/**
 * Get user achievements
 */
export const getUserAchievements = async (req: Request, res: Response) => {
  try {
    const userId = parseInt(req.params.userId as string);

    if (isNaN(userId)) {
      return res.status(400).json({ error: 'Invalid user ID' });
    }

    const userAchievements = await prisma.userAchievement.findMany({
      where: {
        userId
      },
      include: {
        achievement: true
      },
      orderBy: {
        unlockedAt: 'desc'
      }
    });

    res.json(userAchievements);
  } catch (error) {
    console.error('Error fetching user achievements:', error);
    res.status(500).json({ error: 'Failed to fetch user achievements' });
  }
};

/**
 * Check and award achievements for a user
 * This is called internally when user performs actions
 */
export const checkAchievements = async (userId: number, metric: string, currentValue: number) => {
  try {
    // Find all achievements for this metric that haven't been unlocked yet
    const achievements = await prisma.achievement.findMany({
      where: {
        metric
      }
    });

    // Get already unlocked achievements
    const unlockedAchievements = await prisma.userAchievement.findMany({
      where: {
        userId
      },
      select: {
        achievementId: true
      }
    });

    const unlockedIds = new Set(unlockedAchievements.map(ua => ua.achievementId));

    // Check which achievements should be unlocked
    const toUnlock = achievements.filter(
      achievement => !unlockedIds.has(achievement.id) && currentValue >= achievement.target
    );

    // Unlock achievements
    if (toUnlock.length > 0) {
      await prisma.userAchievement.createMany({
        data: toUnlock.map(achievement => ({
          userId,
          achievementId: achievement.id
        }))
      });

      return toUnlock;
    }

    return [];
  } catch (error) {
    console.error('Error checking achievements:', error);
    return [];
  }
};

/**
 * Create a new achievement (admin only)
 */
export const createAchievement = async (req: Request, res: Response) => {
  try {
    const { name, description, iconUrl, target, metric } = req.body;

    // Validate input
    if (!name || !description || !iconUrl || !target || !metric) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (target <= 0) {
      return res.status(400).json({ error: 'Target must be greater than 0' });
    }

    const achievement = await prisma.achievement.create({
      data: {
        name,
        description,
        iconUrl,
        target,
        metric
      }
    });

    res.status(201).json(achievement);
  } catch (error) {
    console.error('Error creating achievement:', error);
    res.status(500).json({ error: 'Failed to create achievement' });
  }
};
