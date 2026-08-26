import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import {
  clearBets,
  getHistory,
  getPublicState,
  getWheelLayout,
  placeBet,
  repeatBets,
  submitPick,
} from '../services/crazyWheel.service';

/**
 * REST surface for عجلة الحظ (Crazy Wheel). Everything that moves coins goes
 * through here so it stays authenticated and rate-limited; the socket only
 * pushes shared round state.
 */

function userIdOf(req: Request): number | null {
  return (req as any).userId ?? (req as any).user?.id ?? null;
}

export const getCrazyState = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    const state = getPublicState(userId ?? undefined);
    let balance = 0;
    if (userId) {
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { coinsBalance: true },
      });
      balance = user?.coinsBalance ?? 0;
    }
    res.json({ success: true, state, balance, layout: getWheelLayout() });
  } catch (error) {
    console.error('[crazyWheel] state error', error);
    res.status(500).json({ success: false, message: 'تعذر تحميل الجولة' });
  }
};

export const placeCrazyBet = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { segment, amount } = req.body ?? {};
    const result = await placeBet(userId, String(segment), Number(amount));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[crazyWheel] bet error', error);
    res.status(500).json({ success: false, message: 'تعذر وضع الرهان' });
  }
};

export const clearCrazyBets = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await clearBets(userId);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[crazyWheel] clear error', error);
    res.status(500).json({ success: false, message: 'تعذر مسح الرهانات' });
  }
};

export const repeatCrazyBets = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await repeatBets(userId);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[crazyWheel] repeat error', error);
    res.status(500).json({ success: false, message: 'تعذر تكرار الرهان' });
  }
};

export const submitCrazyPick = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const pick = req.body?.pick;
    const result = submitPick(userId, typeof pick === 'number' ? pick : String(pick));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, pick: result.pick });
  } catch (error) {
    console.error('[crazyWheel] pick error', error);
    res.status(500).json({ success: false, message: 'تعذر تسجيل الاختيار' });
  }
};

export const getCrazyHistory = async (_req: Request, res: Response) => {
  res.json({ success: true, history: getHistory() });
};
