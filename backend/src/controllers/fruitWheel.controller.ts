import { Request, Response } from 'express';
import * as game from '../services/fruitWheel.service';

function handler(action:(req:Request,userId:number)=>Promise<object>|object) {
  return async (req:Request,res:Response) => {
    const userId = (req as Request & {userId?:number}).userId;
    if (!userId) { res.status(401).json({success:false,code:'UNAUTHORIZED'}); return; }
    try { res.json({success:true,...await action(req,userId)}); }
    catch(error) {
      if (error instanceof game.FruitWheelError) res.status(error.status).json({success:false,code:error.code,message:error.message});
      else { console.error('[fruitwheel]',error); res.status(500).json({success:false,code:'SPIN_FAILED',message:'تعذر تنفيذ الطلب'}); }
    }
  };
}
export const getFruitWheelState = handler((_req,id)=>game.getState(id));
export const spinFruitWheel = handler((req,id)=>game.resolveSpin(id,req.body?.bets,String(req.headers['idempotency-key'] ?? req.body?.requestId ?? '')));
export const getFruitWheelHistory = handler(async (_req,id)=>({history:await game.getHistory(id)}));
export const getFruitWheelFairness = handler(async (_req,id)=>({fairness:await game.getFairness(id)}));
export const setFruitWheelClientSeed = handler(async (req,id)=> {
  const r = await game.setClientSeed(id,req.body?.clientSeed);
  if (!r.ok) throw new game.FruitWheelError(r.code,r.message);
  return {fairness:await game.getFairness(id)};
});
export const rotateFruitWheelSeed = handler((_req,id)=>game.rotateServerSeed(id));
export const verifyFruitWheelSpin = handler(req=>({spin:game.verifySpin(req.body?.serverSeed,req.body?.clientSeed,req.body?.nonce,req.body?.bets)}));
export const getFruitWheelFeed = handler(()=>game.getWinFeed());
export const getFruitWheelLeaderboard = handler((_req,id)=>game.getLeaderboard(id));
export const getFruitWheelToday = handler(()=>game.getTodayPot());
