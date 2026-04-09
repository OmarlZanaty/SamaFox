import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { firstStr } from '../utils/http';
/**
 * Get daily quests for the current user
 */
export const getDailyQuests = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user?.userId;

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Get all daily quests
    const dailyQuests = await prisma.dailyQuest.findMany();

    // Get user's progress for today
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const userQuests = await prisma.userQuest.findMany({
      where: {
        userId,
        date: {
          gte: today
        }
      },
      include: {
        quest: true
      }
    });

    // Map quests with user progress
    const questsWithProgress = dailyQuests.map(quest => {
      const userQuest = userQuests.find(uq => uq.questId === quest.id);
      return {
        ...quest,
        progress: userQuest?.progress || 0,
        isComplete: userQuest?.isComplete || false,
        userQuestId: userQuest?.id
      };
    });

    res.json(questsWithProgress);
  } catch (error) {
    console.error('Error fetching daily quests:', error);
    res.status(500).json({ error: 'Failed to fetch daily quests' });
  }
};

/**
 * Update quest progress
 * This is called internally when user performs actions
 */
export const updateQuestProgress = async (
  userId: number,
  metric: string,
  incrementBy: number = 1
) => {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Find quests matching this metric
    const quests = await prisma.dailyQuest.findMany({
      where: {
        metric
      }
    });

    for (const quest of quests) {
      // Find or create user quest for today
      let userQuest = await prisma.userQuest.findFirst({
        where: {
          userId,
          questId: quest.id,
          date: {
            gte: today
          }
        }
      });

      if (!userQuest) {
        userQuest = await prisma.userQuest.create({
          data: {
            userId,
            questId: quest.id,
            progress: 0,
            date: new Date()
          }
        });
      }

      // Update progress if not complete
      if (!userQuest.isComplete) {
        const newProgress = Math.min(userQuest.progress + incrementBy, quest.target);
        const isComplete = newProgress >= quest.target;

        await prisma.userQuest.update({
          where: {
            id: userQuest.id
          },
          data: {
            progress: newProgress,
            isComplete
          }
        });

        // If quest completed, award coins
        if (isComplete && !userQuest.isComplete) {
          await prisma.user.update({
            where: {
              id: userId
            },
            data: {
              coinsBalance: {
                increment: quest.rewardCoins
              }
            }
          });

          return { questCompleted: true, quest, reward: quest.rewardCoins };
        }
      }
    }

    return { questCompleted: false };
  } catch (error) {
    console.error('Error updating quest progress:', error);
    return { questCompleted: false };
  }
};

/**
 * Complete a quest and claim reward
 */


export const completeQuest = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user?.userId;
    const questIdStr = firstStr(req.params.questId);

    if (!userId) return res.status(401).json({ error: 'Unauthorized' });
    if (!questIdStr) return res.status(400).json({ error: 'Invalid questId' });

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const userQuest = await prisma.userQuest.findFirst({
      where: {
        userId,
        questId: questIdStr,
        date: { gte: today },
      },
      include: { quest: true },
    });

    if (!userQuest) return res.status(404).json({ error: 'Quest not found' });
    if (userQuest.isComplete) return res.status(400).json({ error: 'Quest already completed' });

    if (userQuest.progress < userQuest.quest.target) {
      return res.status(400).json({ error: 'Quest not completed yet' });
    }

    await prisma.userQuest.update({
      where: { id: userQuest.id },
      data: { isComplete: true },
    });

    await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: userQuest.quest.rewardCoins } },
    });

    return res.json({ message: 'Quest completed', reward: userQuest.quest.rewardCoins });
  } catch (error) {
    console.error('Error completing quest:', error);
    return res.status(500).json({ error: 'Failed to complete quest' });
  }
};


/**
 * Create a new daily quest (admin only)
 */
export const createDailyQuest = async (req: Request, res: Response) => {
  try {
    const { name, description, metric, target, rewardCoins } = req.body;

    // Validate input
    if (!name || !description || !metric || !target || !rewardCoins) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    if (target <= 0 || rewardCoins <= 0) {
      return res.status(400).json({ error: 'Target and reward must be greater than 0' });
    }

    const quest = await prisma.dailyQuest.create({
      data: {
        name,
        description,
        metric,
        target,
        rewardCoins
      }
    });

    res.status(201).json(quest);
  } catch (error) {
    console.error('Error creating daily quest:', error);
    res.status(500).json({ error: 'Failed to create daily quest' });
  }
};
