import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import {
  getFairness,
  getHistory,
  getLayout,
  resolveSpin,
  rotateServerSeed,
  setClientSeed,
  verifySpin,
} from '../services/aetherfall.service';

/**
 * REST surface for أثيرفول (Aetherfall: Vaults of the Skyfire). Every spin is
 * settled server-side here — the client never decides a symbol, a tumble or a
 * payout, only replays the sequence this endpoint hands back.
 */

function userIdOf(req: Request): number | null {
  return (req as any).userId ?? (req as any).user?.id ?? null;
}

export const getAetherfallState = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { coinsBalance: true },
    });

    res.json({
      success: true,
      layout: getLayout(),
      balance: user?.coinsBalance ?? 0,
      history: getHistory(userId),
      fairness: getFairness(userId),
    });
  } catch (error) {
    console.error('[aetherfall] state error', error);
    res.status(500).json({ success: false, message: 'تعذر تحميل اللعبة' });
  }
};

export const spinAetherfall = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { amount } = req.body ?? {};
    const result = await resolveSpin(userId, amount);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[aetherfall] spin error', error);
    res.status(500).json({ success: false, message: 'تعذر تنفيذ الجولة' });
  }
};

export const getAetherfallHistory = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, history: getHistory(userId) });
};

export const getAetherfallFairness = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, fairness: getFairness(userId) });
};

export const setAetherfallClientSeed = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const result = setClientSeed(userId, req.body?.clientSeed);
  if (!result.ok) {
    return res.status(400).json({ success: false, code: result.code, message: result.message });
  }
  res.json({ success: true, fairness: getFairness(userId) });
};

/** Reveals the current server seed and starts a new one. */
export const rotateAetherfallSeed = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, ...rotateServerSeed(userId) });
};

/** Recomputes a past spin from revealed seeds so the player can check it. */
export const verifyAetherfallSpin = async (req: Request, res: Response) => {
  try {
    const { serverSeed, clientSeed, nonce, bet } = req.body ?? {};
    if (!serverSeed || !clientSeed) {
      return res.status(400).json({ success: false, message: 'البذور مطلوبة' });
    }
    const spin = verifySpin(
      String(serverSeed),
      String(clientSeed),
      Math.trunc(Number(nonce)) || 0,
      Math.trunc(Number(bet)) || 100,
    );
    res.json({ success: true, spin });
  } catch (error) {
    console.error('[aetherfall] verify error', error);
    res.status(500).json({ success: false, message: 'تعذر التحقق' });
  }
};
