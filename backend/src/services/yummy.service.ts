import { Prisma } from '@prisma/client';
import crypto from 'crypto';
import prisma from '../utils/prisma';
import * as fair from './fairSeeds';
import { getGameSettings, checkGamePlayable } from './gameConfig.service';
import { cairoDay, getHalalSettings, reservePrize, releasePrize } from './halalGames.service';
import { creditAccount, debitAccount, readBalance, gamePoolAccount, PROGRAM_ACCOUNT, bpShare } from './economyAccounts.service';
import { awardUserXP } from './xp.service';
import { broadcastGameWin, recentGameWins } from './gameBroadcast.service';
import { BET_STEPS, PAYLINES, PAYTABLE, JACKPOT_MULTIPLIER, MAX_MULTIPLIER, MATH_VERSION, TARGET_RTP, TUMBLE_MULTIPLIERS,
  FREE_SPIN_AWARDS, EXPANDING_REELS, RngStream, computeSpin, validBet } from './yummy.math';

const GAME = 'yummy';
/** Default for gameConfig.broadcastMinX: wins of 50× the stake are announced. */
export const BROADCAST_MIN_X = 50;
export class YummyError extends Error {
  constructor(public code: string, message: string, public status = 400) { super(message); }
}
export const getFairness = (userId:number) => fair.getFairness(userId,GAME);
export const setClientSeed = (userId:number,seed:string) => fair.setClientSeed(userId,GAME,seed);
export const rotateServerSeed = (userId:number) => fair.rotateServerSeed(userId,GAME);
export async function getLayout() {
  const settings = await getGameSettings(GAME);
  return { betSteps:BET_STEPS, minLines:1, maxLines:9, paylines:PAYLINES, paytable:PAYTABLE,
    jackpotMultiplier:JACKPOT_MULTIPLIER, mathVersion:MATH_VERSION, mathRtp:TARGET_RTP,
    tumbleMultipliers:TUMBLE_MULTIPLIERS, freeSpinAwards:FREE_SPIN_AWARDS, expandingReels:EXPANDING_REELS,
    maxMultiplier:MAX_MULTIPLIER, broadcastMinX:BROADCAST_MIN_X, missions:MISSIONS, ...settings, minBet:Math.max(10,settings.minBet ?? 10), maxBet:Math.min(9000,settings.maxBet ?? 9000) };
}
export async function getHistory(userId:number) {
  const records = await prisma.yummyRound.findMany({where:{userId},orderBy:{createdAt:'desc'},take:50});
  return records.map(r => ({id:r.id,at:r.createdAt.toISOString(),...r.result as object}));
}
export async function getState(userId:number) {
  const [layout,user,history,fairness] = await Promise.all([
    getLayout(),prisma.user.findUnique({where:{id:userId},select:{coinsBalance:true}}),getHistory(userId),getFairness(userId),
  ]);
  return {layout,balance:user?.coinsBalance ?? 0,history,fairness};
}

/** Charge, split, pay, award XP and save the round in ONE transaction.
 * A failed round rolls everything back; no compensating refund can race a win.
 * Reservations use the shared economy; DB locks also enforce solvency and
 * daily caps across processes, where the shared in-memory reservations cannot.
 */
export async function resolveSpin(userId:number,betPerLine:unknown,activeLines:unknown,requestId:string) {
  if (!validBet(betPerLine,activeLines)) throw new YummyError('BAD_BET','قيمة الرهان أو الخطوط غير صالحة');
  if (!requestId || requestId.length > 128) throw new YummyError('BAD_REQUEST_ID','مفتاح الطلب مطلوب');
  const bet = betPerLine as number;
  const lines = activeLines as number;
  const totalBet = bet * lines;
  const previous = await prisma.yummyRound.findUnique({where:{userId_requestId:{userId,requestId}}});
  if (previous) {
    const result = previous.result as Prisma.JsonObject;
    const oldSpin = result.spin as Prisma.JsonObject;
    if (oldSpin.betPerLine !== bet || oldSpin.activeLines !== lines) throw new YummyError('IDEMPOTENCY_KEY_REUSED','مفتاح الطلب مستخدم');
    return {id:previous.id,at:previous.createdAt.toISOString(),...result};
  }
  const playable = await checkGamePlayable(GAME,totalBet);
  if (!playable.ok) throw new YummyError(playable.code,playable.message,playable.status);
  const [settings,halal] = await Promise.all([getGameSettings(GAME),getHalalSettings()]);
  const reserved = await reservePrize(userId,GAME,totalBet*MAX_MULTIPLIER,totalBet);
  if (!reserved.ok) throw new YummyError(reserved.code,reserved.message);
  try {
    const seed = await fair.reserveNonce(userId,GAME);
    const spin = computeSpin(new RngStream(seed.serverSeed,seed.clientSeed,seed.nonce),bet,lines);
    const day = cairoDay();
    const pool = gamePoolAccount(GAME);
    const settled = await prisma.$transaction(async tx => {
      // Conditional debit takes the user row lock before any per-user limits.
      const charged = await tx.user.updateMany({where:{id:userId,coinsBalance:{gte:totalBet}},data:{coinsBalance:{decrement:totalBet}}});
      if (charged.count !== 1) throw new YummyError('INSUFFICIENT','رصيدك لا يكفي');
      const duplicate = await tx.yummyRound.findUnique({where:{userId_requestId:{userId,requestId}}});
      if (duplicate) throw new YummyError('REQUEST_IN_PROGRESS','الطلب موجود بالفعل',409);
      const daily = await tx.gameLedger.aggregate({where:{userId,game:GAME,kind:'prize',day},_sum:{amount:true}});
      if (settings.dailyMaxWinPerUser != null && Number(daily._sum.amount ?? 0) + reserved.cap > settings.dailyMaxWinPerUser) {
        throw new YummyError('DAILY_WIN_CAP','وصلت للحد اليومي لمكاسبك في هذه اللعبة');
      }
      // Lock the prize pool before checking the maximum liability, even for a
      // losing round. An underfunded game refuses the wager before settling.
      await tx.economyAccount.updateMany({where:{key:pool},data:{balance:{increment:0}}});
      if (Number(await readBalance(tx,pool) ?? 0n) < reserved.cap) throw new YummyError('PRIZE_POOL_LOW','صندوق الجوائز لا يغطي الرهان');
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
        throw new YummyError('PRIZE_POOL_LOW','صندوق الجوائز لا يغطي الرهان');
      }
      const user = await tx.user.update({where:{id:userId},data:{coinsBalance:{increment:paid}},select:{coinsBalance:true}});
      const capped = paid < spin.totalPrize;
      await tx.gameLedger.create({data:{userId,game:GAME,kind:'prize',amount:paid,xp:0,ref,day,requested:spin.totalPrize,capped}});
      if (xp > 0) {
        const awarded = await awardUserXP(userId,xp,tx);
        if (!awarded.success) throw new Error('YUMMY XP settlement failed');
      }
      const result = {spin:{...spin,requestedPrize:spin.totalPrize,totalPrize:paid,capped},balance:user.coinsBalance,
        serverSeedHash:seed.serverSeedHash,clientSeed:seed.clientSeed,nonce:seed.nonce};
      const record = await tx.yummyRound.create({data:{userId,requestId,result:result as unknown as Prisma.InputJsonValue}});
      return {id:record.id,at:record.createdAt.toISOString(),...result};
    },{timeout:15000});
    await announce(userId,settled.spin.totalPrize,totalBet,spin.jackpotTriggered,settings.broadcastMinX);
    return settled;
  } finally { releasePrize(reserved.token); }
}

export function verifySpin(serverSeed:unknown,clientSeed:unknown,nonce:unknown,bet:unknown,lines:unknown) {
  if (typeof serverSeed !== 'string' || !/^[a-f0-9]{64}$/i.test(serverSeed) ||
      typeof clientSeed !== 'string' || clientSeed.length < 1 || clientSeed.length > 64 ||
      typeof nonce !== 'number' || !Number.isSafeInteger(nonce) || nonce < 0 || !validBet(bet,lines)) {
    throw new YummyError('BAD_VERIFY','بيانات التحقق غير صالحة');
  }
  return {...computeSpin(new RngStream(serverSeed,clientSeed,nonce),bet as number,lines as number),
    serverSeedHash:crypto.createHash('sha256').update(serverSeed).digest('hex')};
}

/** Tells every player about a big win, after it committed. Never throws. */
async function announce(userId:number,prize:number,totalBet:number,jackpot:boolean,minX:number|null|undefined) {
  const x = prize/totalBet;
  if (prize <= 0 || (!jackpot && x < (minX ?? BROADCAST_MIN_X))) return;
  try {
    const user = await prisma.user.findUnique({where:{id:userId},select:{name:true,avatarUrl:true}});
    broadcastGameWin({game:GAME,userId,name:user?.name ?? '',avatar:user?.avatarUrl ?? null,prize,
      x:Math.round(x*10)/10,tier:jackpot ? 'jackpot' : x >= 100 ? 'mega' : 'big',at:new Date().toISOString()});
  } catch (e) { console.warn('[yummy] announce failed:',(e as Error).message); }
}
export const getWinFeed = () => ({wins:recentGameWins(GAME)});

// ── Weekly leaderboard: coins won this Cairo week (Saturday → Friday) ──────────
/** Cairo days from the last Saturday through today, oldest first. */
export function cairoWeekDays(now = new Date()): string[] {
  const today = cairoDay(now);
  const [y,m,d] = today.split('-').map(Number) as [number,number,number];
  const base = Date.UTC(y,m-1,d);
  const sinceSaturday = (new Date(base).getUTCDay()+1) % 7;
  return Array.from({length:sinceSaturday+1},(_,i) => new Date(base-(sinceSaturday-i)*86_400_000).toISOString().slice(0,10));
}
let board: {at:number;week:string;rows:{userId:number;won:number}[]} | null = null;
export async function getLeaderboard(userId:number) {
  const days = cairoWeekDays();
  if (!board || board.week !== days[0] || Date.now()-board.at > 60_000) {
    const grouped = await prisma.gameLedger.groupBy({by:['userId'],where:{game:GAME,kind:'prize',day:{in:days}},
      _sum:{amount:true},orderBy:{_sum:{amount:'desc'}},take:20});
    board = {at:Date.now(),week:days[0]!,rows:grouped.map(g => ({userId:g.userId,won:Number(g._sum.amount ?? 0)})).filter(r => r.won > 0)};
  }
  const rows = board.rows;
  const users = await prisma.user.findMany({where:{id:{in:rows.map(r => r.userId)}},select:{id:true,name:true,avatarUrl:true}});
  const byId = new Map(users.map(u => [u.id,u]));
  const mine = await prisma.gameLedger.aggregate({where:{userId,game:GAME,kind:'prize',day:{in:days}},_sum:{amount:true}});
  const rank = rows.findIndex(r => r.userId === userId);
  return {weekStart:days[0],entries:rows.map((r,i) => ({rank:i+1,userId:r.userId,name:byId.get(r.userId)?.name ?? '',
    avatar:byId.get(r.userId)?.avatarUrl ?? null,won:r.won})),
    me:{rank:rank < 0 ? null : rank+1,won:Number(mine._sum.amount ?? 0)}};
}
export function __resetLeaderboardForTests() { board = null; }

// ── Daily missions: progress comes from today's rounds; claims pay XP once ─────
export const MISSIONS = [
  {key:'spin20',target:20,xp:50},
  {key:'win5',target:5,xp:60},
  {key:'chain3',target:1,xp:80},
  {key:'freeSpins',target:1,xp:120},
] as const;
type MissionKey = typeof MISSIONS[number]['key'];

async function missionProgress(userId:number,day:string): Promise<Record<MissionKey,number>> {
  const since = new Date(Date.now()-26*3_600_000);
  const rounds = await prisma.yummyRound.findMany({where:{userId,createdAt:{gte:since}},orderBy:{createdAt:'desc'},
    take:500,select:{createdAt:true,result:true}});
  const progress: Record<MissionKey,number> = {spin20:0,win5:0,chain3:0,freeSpins:0};
  for (const round of rounds) {
    if (cairoDay(round.createdAt) !== day) continue;
    const spin = ((round.result ?? {}) as {spin?:{totalPrize?:number;tumbles?:{prize:number}[];bonusTriggered?:boolean}}).spin ?? {};
    progress.spin20++;
    if ((spin.totalPrize ?? 0) > 0) progress.win5++;
    if ((spin.tumbles ?? []).filter(t => t.prize > 0).length >= 3) progress.chain3++;
    if (spin.bonusTriggered) progress.freeSpins++;
  }
  return progress;
}
export async function getMissions(userId:number) {
  const day = cairoDay();
  const [progress,claims] = await Promise.all([missionProgress(userId,day),
    prisma.yummyMissionClaim.findMany({where:{userId,day},select:{key:true}})]);
  const claimed = new Set(claims.map(c => c.key));
  return {day,missions:MISSIONS.map(m => ({...m,progress:Math.min(progress[m.key],m.target),claimed:claimed.has(m.key)}))};
}
export async function claimMission(userId:number,key:unknown) {
  const mission = MISSIONS.find(m => m.key === key);
  if (!mission) throw new YummyError('BAD_MISSION','مهمة غير معروفة');
  const day = cairoDay();
  const progress = await missionProgress(userId,day);
  if (progress[mission.key] < mission.target) throw new YummyError('MISSION_INCOMPLETE','المهمة لم تكتمل بعد');
  try {
    await prisma.$transaction(async tx => {
      await tx.yummyMissionClaim.create({data:{userId,day,key:mission.key,xp:mission.xp}});
      const awarded = await awardUserXP(userId,mission.xp,tx);
      if (!awarded.success) throw new Error('YUMMY mission XP failed');
    });
  } catch (e) {
    if ((e as {code?:string}).code === 'P2002') throw new YummyError('MISSION_CLAIMED','تم استلام هذه المكافأة');
    throw e;
  }
  return {claimed:mission.key,xp:mission.xp,...await getMissions(userId)};
}
