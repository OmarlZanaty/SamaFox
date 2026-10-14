import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import * as game from '../services/fruitWheelRound.service';

/** REST for عجلة الفواكه. Coins only move through here; the socket pushes the shared table. */
type Result = { ok: true } | { ok: false; code: string; message: string };
function handler(action: (req: Request, userId: number) => Promise<object>) {
  return async (req: Request, res: Response) => {
    const userId = (req as Request & { userId?: number }).userId;
    if (!userId) { res.status(401).json({ success: false, code: 'UNAUTHORIZED' }); return; }
    try {
      const out = await action(req, userId) as Result & Record<string, unknown>;
      if (out.ok === false) { res.status(400).json({ success: false, code: out.code, message: out.message }); return; }
      const { ok: _ok, ...body } = out as Record<string, unknown>;
      res.json({ success: true, ...body });
    } catch (error) {
      console.error('[fruitwheel]', error);
      res.status(500).json({ success: false, code: 'FAILED', message: 'تعذر تنفيذ الطلب' });
    }
  };
}
export const getFruitWheelRoundState = handler(async (_req, id) => {
  const user = await prisma.user.findUnique({ where: { id }, select: { coinsBalance: true } });
  return { ok: true, state: game.getPublicState(id), layout: await game.getLayout(), balance: user?.coinsBalance ?? 0 };
});
export const placeFruitWheelRoundBet = handler((req, id) => game.placeBet(id, req.body?.key, req.body?.amount));
export const undoFruitWheelRoundBet = handler((_req, id) => game.undoBet(id));
export const clearFruitWheelRoundBets = handler((_req, id) => game.clearBets(id));
export const repeatFruitWheelRoundBets = handler((_req, id) => game.repeatBets(id));
export const getFruitWheelRoundHistory = handler(async (_req, id) => ({ ok: true, history: await game.getHistory(id) }));
export const getFruitWheelRoundRanking = handler(async (_req, id) => ({ ok: true, ...await game.getRanking(id) }));
