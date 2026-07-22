import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { intParam } from '../utils/http';
import {
  DICE_ENTRY_TIERS,
  getCurrentRoundPublic,
  joinRound,
  submitRound,
} from '../services/skillDice.service';
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

// ============================================
// FISH SHOOTER (real coins, fixed payouts)
// ============================================
// No randomness in the cost or the reward: bet tiers and per-species values
// are fixed and known to the player up front (client shows the same table).
// The only variance is player aim/skill, not chance on the stake — kept
// server-owned here so the client can't spoof a reward amount.
const FISH_BET_TIERS = [1000, 5000, 10000, 50000];

const FISH_SPECIES_VALUES: Record<string, number> = {
  tropical: 2000,
  puffer: 3000,
  squid: 4000,
  octopus: 6000,
  turtle: 12000,
  dolphin: 30000,
  shark: 50000,
  lobster: 100000,
  golden: 500000,
  whale: 5000000,
  megashark: 10000000,
  dragon: 1000000, // boss — fixed value, no jackpot/random multiplier
};

export const fireFishShot = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const bet = Number((req.body ?? {}).bet);
    if (!FISH_BET_TIERS.includes(bet)) {
      return res.status(400).json({ success: false, message: 'Invalid bet tier' });
    }

    const decremented = await prisma.user.updateMany({
      where: { id: userId, coinsBalance: { gte: bet } },
      data: { coinsBalance: { decrement: bet } },
    });
    if (decremented.count === 0) {
      return res.status(402).json({ success: false, message: 'Insufficient balance', code: 'INSUFFICIENT_COINS' });
    }

    const user = await prisma.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } });
    res.json({ success: true, balance: user?.coinsBalance ?? 0 });
  } catch (error) {
    console.error('Fish shoot error:', error);
    res.status(500).json({ success: false, message: 'Failed to fire shot' });
  }
};

export const captureFish = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const speciesKey = String((req.body ?? {}).speciesKey ?? '');
    const reward = FISH_SPECIES_VALUES[speciesKey];
    if (!reward) {
      return res.status(400).json({ success: false, message: 'Invalid species' });
    }

    const user = await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: reward } },
      select: { coinsBalance: true },
    });
    res.json({ success: true, balance: user.coinsBalance, reward });
  } catch (error) {
    console.error('Fish capture error:', error);
    res.status(500).json({ success: false, message: 'Failed to capture fish' });
  }
};

// ============================================
// SKILL DICE (نرد المهارة) — fixed entry price, guaranteed reward
// ============================================
// Not a betting game: see the design note at the top of
// services/skillDice.service.ts. The round engine owns the mission, the
// scoring and the reward table; these endpoints only move coins.
export const getDiceRound = async (_req: Request, res: Response) => {
  res.json({ success: true, round: getCurrentRoundPublic(), entryTiers: DICE_ENTRY_TIERS });
};

export const joinDiceRound = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const entry = Number((req.body ?? {}).entry);
    const result = await joinRound(userId, entry);
    if (!result.ok) {
      const status = result.code === 'INSUFFICIENT_COINS' ? 402 : 400;
      return res.status(status).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Dice join error:', error);
    res.status(500).json({ success: false, message: 'Failed to join round' });
  }
};

export const submitDiceRound = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const body = req.body ?? {};
    const result = submitRound(userId, Number(body.roundId), body.dice);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, score: result.score, reward: result.reward });
  } catch (error) {
    console.error('Dice submit error:', error);
    res.status(500).json({ success: false, message: 'Failed to submit round' });
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
