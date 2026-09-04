import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import {
  dropBall,
  getFairness,
  getHistory,
  getLayout,
  rotateServerSeed,
  setClientSeed,
  verifyDrop,
  RiskLevel,
} from '../services/plinko.service';

/**
 * REST surface for بلينكو (Plinko). Every drop is settled server-side here —
 * the client never decides a path, a slot or a payout.
 */

function userIdOf(req: Request): number | null {
  return (req as any).userId ?? (req as any).user?.id ?? null;
}

export const getPlinkoState = async (req: Request, res: Response) => {
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
      fairness: await getFairness(userId),
    });
  } catch (error) {
    console.error('[plinko] state error', error);
    res.status(500).json({ success: false, message: 'تعذر تحميل اللعبة' });
  }
};

export const dropPlinkoBall = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { risk, rows, amount } = req.body ?? {};
    const result = await dropBall(userId, risk, rows, amount);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[plinko] drop error', error);
    res.status(500).json({ success: false, message: 'تعذر إسقاط الكرة' });
  }
};

export const getPlinkoHistory = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, history: getHistory(userId) });
};

export const getPlinkoFairness = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, fairness: await getFairness(userId) });
};

export const setPlinkoClientSeed = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const result = await setClientSeed(userId, req.body?.clientSeed);
  if (!result.ok) {
    return res.status(400).json({ success: false, code: result.code, message: result.message });
  }
  res.json({ success: true, fairness: await getFairness(userId) });
};

/** Reveals the current server seed and starts a new one. */
export const rotatePlinkoSeed = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, ...(await rotateServerSeed(userId)) });
};

/** Recomputes a past drop from revealed seeds so the player can check it. */
export const verifyPlinkoDrop = async (req: Request, res: Response) => {
  try {
    const { serverSeed, clientSeed, nonce, rows, risk } = req.body ?? {};
    if (!serverSeed || !clientSeed) {
      return res.status(400).json({ success: false, message: 'البذور مطلوبة' });
    }
    const result = verifyDrop(
      String(serverSeed),
      String(clientSeed),
      Math.trunc(Number(nonce)) || 0,
      Math.trunc(Number(rows)) || 16,
      (risk === 'low' || risk === 'medium' || risk === 'high' ? risk : 'medium') as RiskLevel,
    );
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[plinko] verify error', error);
    res.status(500).json({ success: false, message: 'تعذر التحقق' });
  }
};
