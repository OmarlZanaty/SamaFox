import { Request, Response } from 'express';
import {
  claimLuckyDrop,
  getFairness,
  getFeed,
  getHistory,
  getLayout,
  getLuckyDrop,
  getState,
  poolValues,
  resolveSpin,
  rotateServerSeed,
  setClientSeed,
  verifySpin,
} from '../services/neonFortune.service';

/**
 * REST surface for نيون فورتشن (Neon Fortune: Tiger City). Every spin is settled
 * server-side — the client never decides a symbol, a payline, a free spin or a
 * jackpot, it only replays the result this endpoint hands back.
 */

function userIdOf(req: Request): number | null {
  return (req as any).userId ?? (req as any).user?.id ?? null;
}

export const getNeonFortuneState = async (req: Request, res: Response) => {
  try {
    const userId = userIdOf(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    res.json({ success: true, ...(await getState(userId)) });
  } catch (error) {
    console.error('[neon-fortune] state error', error);
    res.status(500).json({ success: false, message: 'تعذر تحميل اللعبة' });
  }
};

export const spinNeonFortune = async (req: Request, res: Response) => {
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
    console.error('[neon-fortune] spin error', error);
    res.status(500).json({ success: false, message: 'تعذر تنفيذ الجولة' });
  }
};

/** Lucky Drop status: the free coin chest and its cooldown. */
export const getNeonFortuneLucky = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  try {
    res.json({ success: true, lucky: await getLuckyDrop(userId) });
  } catch (error) {
    console.error('[neon-fortune] lucky status error', error);
    res.status(500).json({ success: false, message: 'تعذر قراءة الصندوق' });
  }
};

export const claimNeonFortuneLucky = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  try {
    const result = await claimLuckyDrop(userId);
    if (!result.ok) {
      return res
        .status(400)
        .json({ success: false, code: result.code, message: result.message, lucky: result.lucky });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('[neon-fortune] lucky claim error', error);
    res.status(500).json({ success: false, message: 'تعذر فتح الصندوق' });
  }
};

/** Live pool values, polled by the meters between spins. */
export const getNeonFortuneJackpots = async (_req: Request, res: Response) => {
  res.json({ success: true, jackpots: poolValues(), feed: getFeed() });
};

export const getNeonFortuneHistory = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, history: getHistory(userId) });
};

export const getNeonFortuneFairness = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, fairness: getFairness(userId), layout: getLayout() });
};

export const setNeonFortuneClientSeed = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const result = setClientSeed(userId, req.body?.clientSeed);
  if (!result.ok) {
    return res.status(400).json({ success: false, code: result.code, message: result.message });
  }
  res.json({ success: true, fairness: getFairness(userId) });
};

/** Reveals the current server seed and starts a new one. */
export const rotateNeonFortuneSeed = async (req: Request, res: Response) => {
  const userId = userIdOf(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({ success: true, ...rotateServerSeed(userId) });
};

/**
 * Recomputes a past spin from revealed seeds. The reels, the features and the
 * vault layout reproduce exactly; the jackpot coin amount cannot, because it
 * depended on the pool at that instant — the verifier returns the tier instead.
 */
export const verifyNeonFortuneSpin = async (req: Request, res: Response) => {
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
    console.error('[neon-fortune] verify error', error);
    res.status(500).json({ success: false, message: 'تعذر التحقق' });
  }
};
