import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import {
  clearBets,
  getHistory,
  getLayout,
  getPublicState,
  getRanking,
  placeBet,
  reduceBet,
  repeatBets,
} from '../services/greedyCat.service';

/**
 * REST surface for القط الجشع (Greedy Cat). Everything that moves coins goes
 * through here so it stays authenticated and rate-limited; the socket only
 * pushes shared round state.
 */

function userIdOf(req: Request): number | null {
  return (req as any).userId ?? (req as any).user?.id ?? null;
}

export const getGreedyState = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    const state = getPublicState(userId ?? undefined);
    let balance = 0;
    let countryCode: string | null = null;
    if (userId) {
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { coinsBalance: true, countryCode: true },
      });
      balance = user?.coinsBalance ?? 0;
      countryCode = user?.countryCode ?? null;
    }
    res.json({
      success: true,
      state,
      balance,
      countryCode,
      layout: getLayout(),
    });
  } catch (error) {
    console.error('[greedyCat] state error', error);
    res.status(500).json({ success: false, message: 'تعذر تحميل الجولة' });
  }
};

export const placeGreedyBet = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { target, amount } = req.body ?? {};
    const result = await placeBet(userId, String(target), Number(amount));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[greedyCat] bet error', error);
    res.status(500).json({ success: false, message: 'تعذر وضع الرهان' });
  }
};

export const reduceGreedyBet = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { target, amount } = req.body ?? {};
    const result = await reduceBet(userId, String(target), Number(amount));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[greedyCat] reduce error', error);
    res.status(500).json({ success: false, message: 'تعذر تقليل الرهان' });
  }
};

export const clearGreedyBets = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await clearBets(userId);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[greedyCat] clear error', error);
    res.status(500).json({ success: false, message: 'تعذر مسح الرهانات' });
  }
};

export const repeatGreedyBets = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await repeatBets(userId);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[greedyCat] repeat error', error);
    res.status(500).json({ success: false, message: 'تعذر تكرار الرهان' });
  }
};

export const getGreedyHistory = async (_req: Request, res: Response) => {
  res.json({ success: true, history: getHistory() });
};

/**
 * `scope=region` ranks only players sharing the caller's country; anything else
 * is the global board. A caller with no country on file falls back to global
 * rather than returning an empty region.
 */
export const getGreedyRanking = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    const scope = String(req.query.scope ?? 'global');
    let country: string | null = null;
    if (scope === 'region' && userId) {
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { countryCode: true },
      });
      country = user?.countryCode ?? null;
    }
    res.json({ success: true, scope, country, ranking: await getRanking(country) });
  } catch (error) {
    console.error('[greedyCat] ranking error', error);
    res.status(500).json({ success: false, message: 'تعذر تحميل الترتيب' });
  }
};
