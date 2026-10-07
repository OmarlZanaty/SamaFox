import { Request, Response } from 'express';
import * as game from '../services/yummy.service';

function handler(action:(req:Request,userId:number)=>Promise<object>|object) {
  return async (req:Request,res:Response) => {
    const userId = (req as Request & {userId?:number}).userId;
    if (!userId) { res.status(401).json({success:false,code:'UNAUTHORIZED'}); return; }
    try { res.json({success:true,...await action(req,userId)}); }
    catch(error) {
      if (error instanceof game.YummyError) res.status(error.status).json({success:false,code:error.code,message:error.message});
      else { console.error('[yummy]',error); res.status(500).json({success:false,code:'SPIN_FAILED',message:'تعذر تنفيذ الطلب'}); }
    }
  };
}
export const getYummyState = handler((_req,id)=>game.getState(id));
export const spinYummy = handler((req,id)=>game.resolveSpin(id,req.body?.betPerLine,req.body?.activeLines,String(req.headers['idempotency-key'] ?? req.body?.requestId ?? '')));
export const getYummyHistory = handler(async (_req,id)=>({history:await game.getHistory(id)}));
export const getYummyFairness = handler(async (_req,id)=>({fairness:await game.getFairness(id)}));
export const setYummyClientSeed = handler(async (req,id)=> {
  const r = await game.setClientSeed(id,req.body?.clientSeed);
  if (!r.ok) throw new game.YummyError(r.code,r.message);
  return {fairness:await game.getFairness(id)};
});
export const rotateYummySeed = handler((_req,id)=>game.rotateServerSeed(id));
export const verifyYummySpin = handler(req=>({spin:game.verifySpin(req.body?.serverSeed,req.body?.clientSeed,req.body?.nonce,req.body?.betPerLine,req.body?.activeLines)}));
