import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { intParam } from '../utils/http';
export const playDice = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const user = await prisma.user.findUnique({
      where: { id: userId }
    });

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Roll dice (1-6)
    const diceResult = Math.floor(Math.random() * 6) + 1;
    const xpReward = 50 * diceResult;

    // Update user XP
    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: {
        xp: { increment: xpReward }
      }
    });

    res.json({
      success: true,
      diceResult,
      xpEarned: xpReward,
      userXp: updatedUser.xp
    });
  } catch (error) {
    console.error('Dice game error:', error);
    res.status(500).json({ error: 'Failed to play dice game' });
  }
};

export const getLeaderboard = async (req: Request, res: Response) => {
  try {
    const leaderboard = await prisma.user.findMany({
      take: 10,
      orderBy: { xp: 'desc' },
      select: {
        id: true,
        name: true,
        avatarUrl: true,
        level: true,
        xp: true
      }
    });

    res.json({ leaderboard });
  } catch (error) {
    console.error('Leaderboard error:', error);
    res.status(500).json({ error: 'Failed to fetch leaderboard' });
  }
};

export const getUserGameStats = async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
const userIdNum = intParam(req.params.userId);
if (!userIdNum) return res.status(400).json({ error: 'Invalid userId' });

const user = await prisma.user.findUnique({
  where: { id: userIdNum },
  select: { id:true, name:true, avatarUrl:true, level:true, xp:true }
});

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(user);
  } catch (error) {
    console.error('User stats error:', error);
    res.status(500).json({ error: 'Failed to fetch user stats' });
  }
};
