import { Prisma } from '@prisma/client';
import crypto from 'crypto';
import prisma from '../utils/prisma';
import * as fair from './fairSeeds';
import { getGameSettings, checkGamePlayable } from './gameConfig.service';
import { cairoDay, getHalalSettings, reservePrize, releasePrize } from './halalGames.service';
import { creditAccount, debitAccount, readBalance, gamePoolAccount, PROGRAM_ACCOUNT, bpShare } from './economyAccounts.service';
import { awardUserXP } from './xp.service';
import { broadcastGameWin, recentGameWins } from './gameBroadcast.service';
import { cairoWeekDays } from './yummy.service';
import { CARDS, CHIPS, MULTIPLIERS, WEIGHTS, TOTAL_WEIGHT, SEGMENTS, ORBS, BONUS_BASE, MIN_BET, MAX_BET, MAX_MULTIPLIER,
  MATH_VERSION, TARGET_RTP, RngStream, computeSpin, maxPrize, parseBets, totalOf } from './fruitWheel.math';

const GAME = 'fruitwheel';
/** Wins of at least this × the stake are announced to every player. */
export const BROADCAST_MIN_X = 3;
export class FruitWheelError extends Error {
  constructor(public code: string, message: string, public status = 400) { super(message); }
}
export const getFairness = (userId:number) => fair.getFairness(userId,GAME);
export const setClientSeed = (userId:number,seed:string) => fair.setClientSeed(userId,GAME,seed);
export const rotateServerSeed = (userId:number) => fair.rotateServerSeed(userId,GAME);

async function betRange() {
  const settings = await getGameSettings(GAME);
  return {settings,minBet:Math.max(MIN_BET,settings.minBet ?? MIN_BET),maxBet:Math.min(MAX_BET,settings.maxBet ?? MAX_BET)};
}
export async function getLayout() {
  const {settings,minBet,maxBet} = await betRange();
  return {chips:CHIPS,cards:CARDS,multipliers:MULTIPLIERS,segments:SEGMENTS,weights:WEIGHTS,totalWeight:TOTAL_WEIGHT,
    orbs:ORBS.map(o => o.multiplier),bonusBase:BONUS_BASE,mathVersion:MATH_VERSION,mathRtp:TARGET_RTP,
    maxMultiplier:MAX_MULTIPLIER,...settings,minBet,maxBet};
}
export async function getHistory(userId:number) {
  const records = await prisma.fruitWheelRound.findMany({where:{userId},orderBy:{createdAt:'desc'},take:50});
  return records.map(r => ({id:r.id,at:r.createdAt.toISOString(),round:r.round,...r.result as object}));
}

// ── Today's coins on each card, all players. A social figure, refreshed every 30 s. ──
let pot: {at:number;day:string;totals:Record<string,number>} | null = null;
export async function getTodayPot() {
  const day = cairoDay();
  if (!pot || pot.day !== day || Date.now()-pot.at > 30_000) {
    const since = new Date(Date.now()-26*3_600_000);
    const rows = await prisma.fruitWheelRound.findMany({where:{createdAt:{gte:since}},select:{createdAt:true,result:true},take:20_000,
      orderBy:{createdAt:'desc'}});
    const totals: Record<string,number> = Object.fromEntries(CARDS.map(c => [c,0]));
    for (const row of rows) {
      if (cairoDay(row.createdAt) !== day) continue;
      const bets = ((row.result ?? {}) as {spin?:{bets?:Record<string,number>}}).spin?.bets ?? {};
      for (const card of CARDS) totals[card]! += Number(bets[card] ?? 0);
    }
    pot = {at:Date.now(),day,totals};
  }
  return {day,totals:pot.totals};
}

export async function getState(userId:number) {
  const [layout,user,history,fairness,today,rounds] = await Promise.all([
    getLayout(),prisma.user.findUnique({where:{id:userId},select:{coinsBalance:true}}),getHistory(userId),getFairness(userId),
    getTodayPot(),prisma.fruitWheelRound.count({where:{userId}}),
  ]);
  return {layout,balance:user?.coinsBalance ?? 0,history,fairness,today,rounds};
}

/** Charge, split, pay, award XP and save the round in ONE transaction (see yummy.service). */
export async function resolveSpin(userId:number,rawBets:unknown,requestId:string) {
  const {settings,minBet,maxBet} = await betRange();
  const bets = parseBets(rawBets,minBet,maxBet);
  if (!bets) throw new FruitWheelError('BAD_BET','قيمة الرهان غير صالحة');
  if (!requestId || requestId.length > 128) throw new FruitWheelError('BAD_REQUEST_ID','مفتاح الطلب مطلوب');
  const totalBet = totalOf(bets);
  const previous = await prisma.fruitWheelRound.findUnique({where:{userId_requestId:{userId,requestId}}});
  if (previous) {
    const result = previous.result as Prisma.JsonObject;
    const old = (result.spin as Prisma.JsonObject).bets as Record<string,number>;
    if (CARDS.some(c => old[c] !== bets[c])) throw new FruitWheelError('IDEMPOTENCY_KEY_REUSED','مفتاح الطلب مستخدم');
    return {id:previous.id,at:previous.createdAt.toISOString(),round:previous.round,...result};
  }
  const playable = await checkGamePlayable(GAME,totalBet);
  if (!playable.ok) throw new FruitWheelError(playable.code,playable.message,playable.status);
  const halal = await getHalalSettings();
  const reserved = await reservePrize(userId,GAME,maxPrize(bets),totalBet);
  if (!reserved.ok) throw new FruitWheelError(reserved.code,reserved.message);
  try {
    const seed = await fair.reserveNonce(userId,GAME);
    const spin = computeSpin(new RngStream(seed.serverSeed,seed.clientSeed,seed.nonce),bets);
    const day = cairoDay();
    const pool = gamePoolAccount(GAME);
    const settled = await prisma.$transaction(async tx => {
      const charged = await tx.user.updateMany({where:{id:userId,coinsBalance:{gte:totalBet}},data:{coinsBalance:{decrement:totalBet}}});
      if (charged.count !== 1) throw new FruitWheelError('INSUFFICIENT','رصيدك لا يكفي');
      const duplicate = await tx.fruitWheelRound.findUnique({where:{userId_requestId:{userId,requestId}}});
      if (duplicate) throw new FruitWheelError('REQUEST_IN_PROGRESS','الطلب موجود بالفعل',409);
      const daily = await tx.gameLedger.aggregate({where:{userId,game:GAME,kind:'prize',day},_sum:{amount:true}});
      if (settings.dailyMaxWinPerUser != null && Number(daily._sum.amount ?? 0) + reserved.cap > settings.dailyMaxWinPerUser) {
        throw new FruitWheelError('DAILY_WIN_CAP','وصلت للحد اليومي لمكاسبك في هذه اللعبة');
      }
      await tx.economyAccount.updateMany({where:{key:pool},data:{balance:{increment:0}}});
      if (Number(await readBalance(tx,pool) ?? 0n) < reserved.cap) throw new FruitWheelError('PRIZE_POOL_LOW','صندوق الجوائز لا يغطي الرهان');
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
        throw new FruitWheelError('PRIZE_POOL_LOW','صندوق الجوائز لا يغطي الرهان');
      }
      const user = await tx.user.update({where:{id:userId},data:{coinsBalance:{increment:paid}},select:{coinsBalance:true}});
      const capped = paid < spin.totalPrize;
      await tx.gameLedger.create({data:{userId,game:GAME,kind:'prize',amount:paid,xp:0,ref,day,requested:spin.totalPrize,capped}});
      if (xp > 0) {
        const awarded = await awardUserXP(userId,xp,tx);
        if (!awarded.success) throw new Error('FRUIT WHEEL XP settlement failed');
      }
      const round = await tx.fruitWheelRound.count({where:{userId}}) + 1;
      const result = {spin:{...spin,requestedPrize:spin.totalPrize,totalPrize:paid,capped},balance:user.coinsBalance,
        serverSeedHash:seed.serverSeedHash,clientSeed:seed.clientSeed,nonce:seed.nonce};
      const record = await tx.fruitWheelRound.create({data:{userId,requestId,round,result:result as unknown as Prisma.InputJsonValue}});
      return {id:record.id,at:record.createdAt.toISOString(),round,...result};
    },{timeout:15000});
    if (pot && pot.day === day) for (const card of CARDS) pot.totals[card]! += bets[card];
    await announce(userId,settled.spin.totalPrize,totalBet,settings.broadcastMinX);
    return settled;
  } finally { releasePrize(reserved.token); }
}

export function verifySpin(serverSeed:unknown,clientSeed:unknown,nonce:unknown,bets:unknown) {
  const parsed = parseBets(bets,1,Number.MAX_SAFE_INTEGER);
  if (typeof serverSeed !== 'string' || !/^[a-f0-9]{64}$/i.test(serverSeed) ||
      typeof clientSeed !== 'string' || clientSeed.length < 1 || clientSeed.length > 64 ||
      typeof nonce !== 'number' || !Number.isSafeInteger(nonce) || nonce < 0 || !parsed) {
    throw new FruitWheelError('BAD_VERIFY','بيانات التحقق غير صالحة');
  }
  return {...computeSpin(new RngStream(serverSeed,clientSeed,nonce),parsed),
    serverSeedHash:crypto.createHash('sha256').update(serverSeed).digest('hex')};
}

/** Tells every player about a big win, after it committed. Never throws. */
async function announce(userId:number,prize:number,totalBet:number,minX:number|null|undefined) {
  const x = prize/totalBet;
  if (prize <= 0 || x < (minX ?? BROADCAST_MIN_X)) return;
  try {
    const user = await prisma.user.findUnique({where:{id:userId},select:{name:true,avatarUrl:true}});
    broadcastGameWin({game:GAME,userId,name:user?.name ?? '',avatar:user?.avatarUrl ?? null,prize,
      x:Math.round(x*10)/10,tier:'big',at:new Date().toISOString()});
  } catch (e) { console.warn('[fruitwheel] announce failed:',(e as Error).message); }
}
export const getWinFeed = () => ({wins:recentGameWins(GAME)});

// ── Weekly leaderboard: coins won this Cairo week (Saturday → Friday) ──────────
/** Milliseconds until the board resets (Saturday 00:00 Cairo). */
export function weekEndsIn(now = new Date()): number {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Africa/Cairo',hour12:false,
    hour:'2-digit',minute:'2-digit',second:'2-digit'}).formatToParts(now).map(p => [p.type,Number(p.value)]));
  const intoDay = ((parts.hour! % 24)*3600 + parts.minute!*60 + parts.second!)*1000;
  return (7-cairoWeekDays(now).length)*86_400_000 + 86_400_000 - intoDay;
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
  return {weekStart:days[0],endsIn:weekEndsIn(),entries:rows.map((r,i) => ({rank:i+1,userId:r.userId,name:byId.get(r.userId)?.name ?? '',
    avatar:byId.get(r.userId)?.avatarUrl ?? null,won:r.won})),
    me:{rank:rank < 0 ? null : rank+1,won:Number(mine._sum.amount ?? 0)}};
}
export function __resetForTests() { board = null; pot = null; }
