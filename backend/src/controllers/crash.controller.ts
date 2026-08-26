import { Request, Response } from 'express';
import { intParam } from '../utils/http';
import {
  CRASH_GROWTH,
  CRASH_MAX_BET,
  CRASH_MIN_BET,
  CRASH_SLOTS,
  cancelCrashBet,
  cashOutCrashBet,
  claimCrashRain,
  getCrashChat,
  getCrashHistory,
  getCrashPlayerBets,
  getCrashPlayerStats,
  getCrashRoundFairness,
  getCrashStatePublic,
  getClientSeed,
  placeCrashBet,
  postCrashChat,
  setClientSeed,
  verifyCrashPoint,
} from '../services/crash.service';

// ============================================
// طيّار — CRASH (Aviator-style)
// ============================================
// These endpoints only move coins and read state; the round engine in
// services/crash.service.ts owns the crash point, the clock and the payouts.

const uid = (req: Request) => (req as any).userId ?? (req as any).user?.id;

export const getCrashState = async (req: Request, res: Response) => {
  const userId = uid(req);
  res.json({
    success: true,
    state: getCrashStatePublic(),
    minBet: CRASH_MIN_BET,
    maxBet: CRASH_MAX_BET,
    slots: CRASH_SLOTS,
    growth: CRASH_GROWTH,
    clientSeed: userId ? getClientSeed(userId) : null,
  });
};

export const placeCrashBetHandler = async (req: Request, res: Response) => {
  try {
    const userId = uid(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const body = req.body ?? {};
    const autoRaw = body.autoCashOut;
    const autoCashOut =
      autoRaw == null || autoRaw === '' ? null : Math.round(Number(autoRaw) * 100) / 100;

    const result = await placeCrashBet(
      userId,
      Number(body.slot ?? 0),
      Math.floor(Number(body.amount)),
      autoCashOut,
    );
    if (!result.ok) {
      const status = result.code === 'INSUFFICIENT_COINS' ? 402 : 400;
      return res.status(status).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Crash bet error:', error);
    res.status(500).json({ success: false, message: 'Failed to place bet' });
  }
};

export const cancelCrashBetHandler = async (req: Request, res: Response) => {
  try {
    const userId = uid(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await cancelCrashBet(userId, Number((req.body ?? {}).slot ?? 0));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Crash cancel error:', error);
    res.status(500).json({ success: false, message: 'Failed to cancel bet' });
  }
};

export const cashOutCrashHandler = async (req: Request, res: Response) => {
  try {
    const userId = uid(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await cashOutCrashBet(userId, Number((req.body ?? {}).slot ?? 0));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Crash cashout error:', error);
    res.status(500).json({ success: false, message: 'Failed to cash out' });
  }
};

export const getCrashHistoryHandler = async (_req: Request, res: Response) => {
  res.json({ success: true, history: getCrashHistory(50) });
};

/**
 * Provably-fair detail for one past round: the revealed server seed, the client
 * seeds, the nonce, and the crash point recomputed live from them so the caller
 * can see the formula agree with what was played.
 */
export const getCrashFairnessHandler = async (req: Request, res: Response) => {
  const roundId = intParam(req.params.roundId);
  if (!roundId) return res.status(400).json({ success: false, message: 'Invalid roundId' });

  const entry = getCrashRoundFairness(roundId);
  if (!entry) return res.status(404).json({ success: false, message: 'الجولة غير متاحة' });

  const recomputed = verifyCrashPoint(entry.serverSeed, entry.clientSeeds, entry.nonce);
  res.json({
    success: true,
    round: entry,
    recomputed,
    verified: Math.abs(recomputed.crashPoint - entry.crashPoint) < 1e-9,
  });
};

export const setCrashClientSeedHandler = async (req: Request, res: Response) => {
  const userId = uid(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

  const result = setClientSeed(userId, String((req.body ?? {}).clientSeed ?? ''));
  if (!result.ok) return res.status(400).json({ success: false, message: result.message });
  res.json({ success: true, clientSeed: result.clientSeed });
};

export const getCrashStatsHandler = async (req: Request, res: Response) => {
  const userId = uid(req);
  if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
  res.json({
    success: true,
    stats: getCrashPlayerStats(userId),
    bets: getCrashPlayerBets(userId, 50),
  });
};

export const getCrashChatHandler = async (_req: Request, res: Response) => {
  res.json({ success: true, messages: getCrashChat(50) });
};

export const postCrashChatHandler = async (req: Request, res: Response) => {
  try {
    const userId = uid(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await postCrashChat(userId, String((req.body ?? {}).text ?? ''));
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, message: result.message });
  } catch (error) {
    console.error('Crash chat error:', error);
    res.status(500).json({ success: false, message: 'Failed to send message' });
  }
};

export const claimCrashRainHandler = async (req: Request, res: Response) => {
  try {
    const userId = uid(req);
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const result = await claimCrashRain(userId);
    if (!result.ok) {
      return res.status(400).json({ success: false, code: result.code, message: result.message });
    }
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Crash rain claim error:', error);
    res.status(500).json({ success: false, message: 'Failed to claim rain' });
  }
};
