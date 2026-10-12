import { Prisma } from '@prisma/client';
import crypto from 'crypto';
import prisma from '../utils/prisma';
import * as fair from './fairSeeds';
import { getGameSettings, checkGamePlayable } from './gameConfig.service';
import { cairoDay, getHalalSettings, reservePrize, releasePrize } from './halalGames.service';
import { creditAccount, debitAccount, readBalance, gamePoolAccount, PROGRAM_ACCOUNT, bpShare } from './economyAccounts.service';
import { awardUserXP } from './xp.service';
import { BET_STEPS, PAYLINES, PAYTABLE, JACKPOT_MULTIPLIER, MAX_MULTIPLIER, MATH_VERSION, TARGET_RTP, RngStream, computeSpin, validBet } from './fruitJackpot.math';

// The checked-in schema adds this delegate; shared worktree clients may predate generation.
const rounds = (db: typeof prisma | Prisma.TransactionClient) => (db as unknown as {fruitJackpotRound: typeof prisma.yummyRound}).fruitJackpotRound;
const GAME = 'fruit-jackpot';
export class FruitJackpotError extends Error {
  constructor(public code: string, message: string, public status = 400) { super(message); }
}
export const getFairness = (userId:number) => fair.getFairness(userId,GAME);
export const setClientSeed = (userId:number,seed:string) => fair.setClientSeed(userId,GAME,seed);
export const rotateServerSeed = (userId:number) => fair.rotateServerSeed(userId,GAME);
export async function getLayout() {
  const settings = await getGameSettings(GAME);
  return { betSteps:BET_STEPS, minLines:8, maxLines:8, paylines:PAYLINES, paytable:PAYTABLE,
    jackpotMultiplier:JACKPOT_MULTIPLIER, mathVersion:MATH_VERSION, mathRtp:TARGET_RTP,
    maxMultiplier:MAX_MULTIPLIER, ...settings, minBet:Math.max(100,settings.minBet ?? 100), maxBet:Math.min(100000,settings.maxBet ?? 100000) };
}
export async function getHistory(userId:number) {
  const records = await rounds(prisma).findMany({where:{userId},orderBy:{createdAt:'desc'},take:50});
  return records.map(r => ({id:r.id,at:r.createdAt.toISOString(),...r.result as object}));
}
export async function getState(userId:number) {
  const [layout,user,history,fairness,stats] = await Promise.all([
    getLayout(),prisma.user.findUnique({where:{id:userId},select:{coinsBalance:true}}),getHistory(userId),getFairness(userId),getRank(userId),
  ]);
  return {layout,balance:user?.coinsBalance ?? 0,history,fairness,...stats};
}

/** Charge, split, pay, award XP and save the round in ONE transaction.
 * A failed round rolls everything back; no compensating refund can race a win.
 * Reservations use the shared economy; DB locks also enforce solvency and
 * daily caps across processes, where the shared in-memory reservations cannot.
 */
export async function resolveSpin(userId:number,betPerLine:unknown,activeLines:unknown,requestId:string) {
  if (!validBet(betPerLine,activeLines)) throw new FruitJackpotError('BAD_BET','قيمة الرهان أو الخطوط غير صالحة');
  if (!requestId || requestId.length > 128) throw new FruitJackpotError('BAD_REQUEST_ID','مفتاح الطلب مطلوب');
  const bet = betPerLine as number;
  const lines = activeLines as number;
  const totalBet = bet;
  const previous = await rounds(prisma).findUnique({where:{userId_requestId:{userId,requestId}}});
  if (previous) {
    const result = previous.result as Prisma.JsonObject;
    const oldSpin = result.spin as Prisma.JsonObject;
    if (oldSpin.betPerLine !== bet || oldSpin.activeLines !== lines) throw new FruitJackpotError('IDEMPOTENCY_KEY_REUSED','مفتاح الطلب مستخدم');
    return {id:previous.id,at:previous.createdAt.toISOString(),...result};
  }
  const playable = await checkGamePlayable(GAME,totalBet);
  if (!playable.ok) throw new FruitJackpotError(playable.code,playable.message,playable.status);
  const [settings,halal] = await Promise.all([getGameSettings(GAME),getHalalSettings()]);
  const reserved = await reservePrize(userId,GAME,totalBet*MAX_MULTIPLIER,totalBet);
  if (!reserved.ok) throw new FruitJackpotError(reserved.code,reserved.message);
  try {
    const seed = await fair.reserveNonce(userId,GAME);
    const spin = computeSpin(new RngStream(seed.serverSeed,seed.clientSeed,seed.nonce),bet,lines);
    const day = cairoDay();
    const pool = gamePoolAccount(GAME);
    return await prisma.$transaction(async tx => {
      // Conditional debit takes the user row lock before any per-user limits.
      const charged = await tx.user.updateMany({where:{id:userId,coinsBalance:{gte:totalBet}},data:{coinsBalance:{decrement:totalBet}}});
      if (charged.count !== 1) throw new FruitJackpotError('INSUFFICIENT','رصيدك لا يكفي');
      const duplicate = await rounds(tx).findUnique({where:{userId_requestId:{userId,requestId}}});
      if (duplicate) throw new FruitJackpotError('REQUEST_IN_PROGRESS','الطلب موجود بالفعل',409);
      const daily = await tx.gameLedger.aggregate({where:{userId,game:GAME,kind:'prize',day},_sum:{amount:true}});
      if (settings.dailyMaxWinPerUser != null && Number(daily._sum.amount ?? 0) + reserved.cap > settings.dailyMaxWinPerUser) {
        throw new FruitJackpotError('DAILY_WIN_CAP','وصلت للحد اليومي لمكاسبك في هذه اللعبة');
      }
      // Lock the prize pool before checking the maximum liability, even for a
      // losing round. An underfunded game refuses the wager before settling.
      await tx.economyAccount.updateMany({where:{key:pool},data:{balance:{increment:0}}});
      if (Number(await readBalance(tx,pool) ?? 0n) < reserved.cap) throw new FruitJackpotError('PRIZE_POOL_LOW','صندوق الجوائز لا يغطي الرهان');
      const ref = `${userId}:${seed.serverSeedHash}:${seed.nonce}`;
      const movement = {refType:GAME,refId:ref,userId};
      const programShare = bpShare(totalBet,settings.programShareBp);
      const poolShare = totalBet-programShare;
      const xp = Math.floor(totalBet*halal.xpPerCoin);
      await creditAccount(tx,PROGRAM_ACCOUNT,programShare,{...movement,kind:'GAME_STAKE_PROGRAM'});
      await creditAccount(tx,pool,poolShare,{...movement,kind:'GAME_STAKE_POOL'});
      await tx.gameLedger.create({data:{userId,game:GAME,kind:'stake',amount:totalBet,xp,ref,day,programShare,poolShare}});
      const paid = Math.min(spin.totalPrize,reserved.cap);
      if (paid > 0 && await debitAccount(tx,pool,paid,{...movement,kind:'GAME_PRIZE'}) === null) {
        throw new FruitJackpotError('PRIZE_POOL_LOW','صندوق الجوائز لا يغطي الرهان');
      }
      const user = await tx.user.update({where:{id:userId},data:{coinsBalance:{increment:paid}},select:{coinsBalance:true}});
      const capped = paid < spin.totalPrize;
      await tx.gameLedger.create({data:{userId,game:GAME,kind:'prize',amount:paid,xp:0,ref,day,requested:spin.totalPrize,capped}});
      if (xp > 0) {
        const awarded = await awardUserXP(userId,xp,tx);
        if (!awarded.success) throw new Error('FRUIT JACKPOT XP settlement failed');
      }
      const roundNumber = await rounds(tx).count({where:{userId}}) + 1;
      const result = {roundNumber,spin:{...spin,requestedPrize:spin.totalPrize,totalPrize:paid,capped},balance:user.coinsBalance,
        serverSeedHash:seed.serverSeedHash,clientSeed:seed.clientSeed,nonce:seed.nonce};
      const record = await rounds(tx).create({data:{userId,requestId,result:result as unknown as Prisma.InputJsonValue}});
      return {id:record.id,at:record.createdAt.toISOString(),...result};
    },{timeout:15000});
  } finally { releasePrize(reserved.token); }
}

export function verifySpin(serverSeed:unknown,clientSeed:unknown,nonce:unknown,bet:unknown,lines:unknown) {
  if (typeof serverSeed !== 'string' || !/^[a-f0-9]{64}$/i.test(serverSeed) ||
      typeof clientSeed !== 'string' || clientSeed.length < 1 || clientSeed.length > 64 ||
      typeof nonce !== 'number' || !Number.isSafeInteger(nonce) || nonce < 0 || !validBet(bet,lines)) {
    throw new FruitJackpotError('BAD_VERIFY','بيانات التحقق غير صالحة');
  }
  return {...computeSpin(new RngStream(serverSeed,clientSeed,nonce),bet as number,lines as number),
    serverSeedHash:crypto.createHash('sha256').update(serverSeed).digest('hex')};
}

/** Find the next Cairo calendar day boundary, including DST transitions. */
export function nextCairoReset(now = new Date()) {
  const day=cairoDay(now); let lo=now.getTime(), hi=lo+27*3600000;
  while(hi-lo>1) { const mid=Math.floor((lo+hi)/2); if(cairoDay(new Date(mid))===day) lo=mid; else hi=mid; }
  return new Date(hi).toISOString();
}
export async function getRank(userId:number) {
  const now=new Date();
  const [totals,roundCount]=await Promise.all([
    prisma.gameLedger.groupBy({by:['userId'],where:{game:GAME,kind:'prize',day:cairoDay(now)},_sum:{amount:true}}),
    rounds(prisma).count({where:{userId}}),
  ]);
  const won=Number(totals.find(r=>r.userId===userId)?._sum.amount??0);
  return {rank:won>0?1+totals.filter(r=>Number(r._sum.amount??0)>won).length:null,totalWonToday:won,roundCount,
    serverTime:now.toISOString(),resetAt:nextCairoReset(now)};
}
