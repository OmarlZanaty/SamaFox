import { randomInt } from 'crypto';
import prisma from '../utils/prisma';
import { creditAccount, debitAccount, readBalance, PROGRAM_ACCOUNT } from './economyAccounts.service';
import { recordAdminAuditStrict } from './adminAudit.service';
import { PkMatchQueue } from './pkMatchmaking';
import { emitGlobal, emitToRoomAndUsers, emitToUser, isUserInRoom, getSeatedUserIds } from './socket.service';

const db = prisma as any;
const MAX = 2_000_000_000;
export class RoomEventError extends Error {
  constructor(message: string, public status = 400) { super(message); }
}
export function integer(v: unknown, min = 1, max = MAX): number {
  if (!Number.isSafeInteger(v) || Number(v) < min || Number(v) > max) throw new RoomEventError('قيمة غير صالحة');
  return Number(v);
}
export async function eventTransaction<T>(work: (tx: any) => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await db.$transaction(work, { isolationLevel: 'Serializable', timeout: 15000 });
    } catch (e: any) {
      if ((e.code === 'P2034' || e.code === 'P2002') && attempt < 4) continue;
      throw e;
    }
  }
}
export type Reward = { type: 'coins' | 'item' | 'both'; coins?: number; itemId?: string; weight: number; quantity: number; durationDays?: number | null; name?: string };
export function drawReward(rewards: Reward[], pick = randomInt): Reward {
  const sum = rewards.reduce((n, r) => n + r.weight, 0);
  let roll = pick(sum);
  for (const r of rewards) { roll -= r.weight; if (roll < 0) return r; }
  throw new RoomEventError('الجوائز غير متاحة');
}
async function validateReward(tx: any, raw: any, weighted: boolean): Promise<Reward> {
  if (!raw || typeof raw !== 'object') throw new RoomEventError('الجائزة غير صالحة');
  if (!weighted && raw.itemId && raw.coins > 0) {
    const item = await validateReward(tx, { ...raw, type: 'item', coins: undefined }, false);
    return { ...item, type: 'both', coins: integer(raw.coins, 1, 1_000_000) };
  }
  const quantity = integer(raw.quantity ?? 1, 1, 100);
  const weight = weighted ? integer(raw.weight, 1, 1_000_000) : 1;
  if (raw.type === 'coins' || (!weighted && raw.coins != null)) {
    const coins = integer(raw.coins, 1, 1_000_000);
    integer(coins * quantity);
    return { type: 'coins', coins, quantity, weight };
  }
  if (typeof raw.itemId !== 'string') throw new RoomEventError('اختر المنتج');
  const item = await tx.item.findUnique({ where: { id: raw.itemId } });
  if (!item) throw new RoomEventError('المنتج غير موجود');
  // UserItem represents one entitlement; quantity extends a timed entitlement.
  if (quantity > 1 && !item.durationDays) throw new RoomEventError('المنتج الدائم كميته واحدة');
  return { type: 'item', itemId: item.id, quantity, weight, durationDays: item.durationDays, name: item.name };
}
export async function saveEventConfig(kind: 'rocket' | 'pk', raw: any, adminId: number) {
  return eventTransaction(async tx => {
    let data: any;
    if (kind === 'rocket') {
      if (!Array.isArray(raw.rewards) || raw.rewards.length < 1 || raw.rewards.length > 100) throw new RoomEventError('أضف الجوائز');
      const rewards = await Promise.all(raw.rewards.map((r: any) => validateReward(tx, r, true)));
      data = {
        targetCoins: integer(raw.targetCoins), roomCupPercent: integer(raw.roomCupPercent, 0, 10000),
        durationMinutes: integer(raw.durationMinutes, 1, 1440), winnersCount: integer(raw.winnersCount, 1, 1000),
        maxRewardPerUserCoins: integer(raw.maxRewardPerUserCoins, 0, 1_000_000),
        claimWindowSeconds: integer(raw.claimWindowSeconds ?? 90, 10, 3600), rewards,
        isActive: raw.isActive === true, updatedBy: adminId,
      };
    } else {
      if (!Array.isArray(raw.allowedDurations) || !raw.allowedDurations.length || raw.allowedDurations.length > 20) throw new RoomEventError('حدد المدد');
      if (!Array.isArray(raw.countedGiftIds) || raw.countedGiftIds.length > 500 || raw.countedGiftIds.some((id: any) => typeof id !== 'string')) throw new RoomEventError('قائمة الهدايا غير صالحة');
      if (raw.winCondition !== 'HIGHER_SCORE' || !['TIE', 'FIRST_TO_REACH'].includes(raw.tieRule)) throw new RoomEventError('قاعدة الحسم غير صالحة');
      const rewards: any = {};
      for (const side of ['winner', 'loser']) if (raw.rewards?.[side]) rewards[side] = await validateReward(tx, raw.rewards[side], false);
      const viewerGiftCoins = integer(raw.viewerGiftCoins ?? 0, 0, 1_000_000);
      const viewerGiftItem = raw.viewerGiftItem ? await validateReward(tx,
        typeof raw.viewerGiftItem === 'string' ? { itemId: raw.viewerGiftItem } : { ...raw.viewerGiftItem, type: 'item', coins: undefined }, false) : null;
      data = { minTotalCoins: BigInt(integer(Number(raw.minTotalCoins ?? 0), 0, Number.MAX_SAFE_INTEGER)),
        viewerGiftCoins, viewerGiftItem: viewerGiftItem ?? undefined, allowedDurations: [...new Set(raw.allowedDurations.map((v: any) => integer(v, 30, 3600)))],
        countedGiftIds: raw.countedGiftIds, pointsPerCoin: integer(raw.pointsPerCoin, 1, 1000),
        winCondition: raw.winCondition, tieRule: raw.tieRule, rewards, enabled: raw.enabled === true, updatedBy: adminId };
    }
    const model = kind === 'rocket' ? tx.rocketConfig : tx.pkConfig;
    const before = await model.findFirst({ orderBy: { id: 'desc' } });
    if (kind === 'rocket') await model.updateMany({ where: { isActive: true }, data: { isActive: false } });
    const after = await model.create({ data });
    await recordAdminAuditStrict(tx, { adminId, action: kind === 'rocket' ? 'ROCKET_CONFIG_UPDATE' : 'PK_CONFIG_UPDATE', before, after });
    return kind === 'pk' ? pkConfigSnapshot(after) : after;
  });
}
async function grantReward(tx: any, userId: number, reward: Reward, pool: string, ref: string, cap = MAX): Promise<any> {
  if (reward.type === 'both') {
    const coins = await grantReward(tx, userId, { ...reward, type: 'coins' }, pool, ref, cap);
    const item = await grantReward(tx, userId, { ...reward, type: 'item' }, pool, ref, cap);
    return { type: 'both', coins: coins.coins, itemId: reward.itemId, item, before: coins.before, after: coins.after };
  }
  const before = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { coinsBalance: true } });
  if (reward.type === 'coins') {
    const coins = Math.min(cap, (reward.coins ?? 0) * reward.quantity);
    const balance = await debitAccount(tx, pool, coins, { kind: 'EVENT_REWARD', refType: pool, refId: ref, userId });
    if (balance === null) throw new RoomEventError('رصيد صندوق الجوائز غير كافٍ', 409);
    await tx.user.update({ where: { id: userId }, data: { coinsBalance: { increment: coins } } });
    return { type: 'coins', coins, before: before.coinsBalance, after: before.coinsBalance + coins };
  }
  const old = await tx.userItem.findUnique({ where: { userId_itemId: { userId, itemId: reward.itemId! } } });
  const expiresAt = reward.durationDays
    ? new Date(Math.max(Date.now(), old?.expiresAt?.getTime() ?? 0) + reward.durationDays * reward.quantity * 86400000)
    : null;
  // A permanent entitlement is never shortened by a timed prize.
  const expiry = old && !old.expiresAt ? null : expiresAt;
  await tx.userItem.upsert({
    where: { userId_itemId: { userId, itemId: reward.itemId! } },
    create: { userId, itemId: reward.itemId, expiresAt: expiry },
    update: { expiresAt: expiry },
  });
  await tx.economyLedger.create({ data: { account: pool, delta: 0n, balanceAfter: (await readBalance(tx, pool)) ?? 0n,
    kind: 'EVENT_ITEM_REWARD', refType: 'item', refId: ref, userId } });
  return { type: 'item', itemId: reward.itemId, name: reward.name, quantity: reward.quantity, before: old, expiresAt: expiry };
}
export async function fundEventPool(kind: 'rocket' | 'pk', amount: number, adminId: number) {
  integer(amount);
  const account = kind === 'rocket' ? 'ROCKET_POOL' : 'PK_POOL';
  return eventTransaction(async tx => {
    const before = { pool: (await readBalance(tx, account)) ?? 0n, program: (await readBalance(tx, PROGRAM_ACCOUNT)) ?? 0n };
    if (await debitAccount(tx, PROGRAM_ACCOUNT, amount, { kind: 'POOL_FUNDING', refType: account, userId: adminId }) === null)
      throw new RoomEventError('رصيد البرنامج غير كافٍ', 409);
    const after = await creditAccount(tx, account, amount, { kind: 'POOL_FUNDING', refType: account, userId: adminId });
    await recordAdminAuditStrict(tx, { adminId, action: 'EVENT_POOL_FUND', targetId: account, before,
      after: { pool: after, program: before.program - BigInt(amount) } });
    return { poolBalance: after.toString() };
  });
}

const pendingStates = new Map<string, { roomIds: number[]; event: string; payload: any }>();
function queueState(key: string, roomIds: number[], event: string, payload: any) {
  pendingStates.set(key, { roomIds: [...new Set(roomIds)], event, payload });
}
export function rocketView(e: any) {
  return e ? { ...e, eventId: e.id, current: e.currentCoins, target: e.targetCoins, rewards: e.configSnapshot.rewards,
    claimWindowSeconds: e.configSnapshot.claimWindowSeconds } : null;
}
function pkConfigSnapshot(cfg: any) {
  return { ...cfg, minTotalCoins: String(cfg.minTotalCoins ?? 0) };
}
export function pkView(p: any) {
  return p ? { ...p, pkId: p.id, roomId: p.room1Id, opponentRoomId: p.room2Id,
    scoreA: p.room1Score, scoreB: p.room2Score,
    prizeEligible: p.status === 'FINISHED' && ['A', 'B'].includes(p.winner) &&
      BigInt(p.room1Score + p.room2Score) >= BigInt(p.configSnapshot.minTotalCoins ?? 0) } : null;
}
export async function processRoomGift(giftTransactionId: string) {
  const out: any = await eventTransaction(async tx => {
    const job = await tx.roomGiftJob.findUnique({ where: { giftTransactionId } });
    if (!job || job.processedAt) return null;
    const gift = await tx.giftTransaction.findUnique({ where: { id: giftTransactionId } });
    if (!gift?.roomId) return null;
    // Serialize each room's lazy creation. SERIALIZABLE retries protect a global PK's two rooms.
    await tx.$executeRawUnsafe('SELECT pg_advisory_xact_lock($1::bigint)', 5200000000 + gift.roomId);
    const now = new Date();
    await tx.rocketEvent.updateMany({ where: { roomId: gift.roomId, status: 'ACTIVE', endsAt: { lte: gift.createdAt } }, data: { status: 'EXPIRED' } });
    let rocket = await tx.rocketEvent.findFirst({ where: { roomId: gift.roomId, status: 'ACTIVE' } });
    if (!rocket) {
      const cfg = await tx.rocketConfig.findFirst({ where: { createdAt: { lte: gift.createdAt } }, orderBy: { id: 'desc' } });
      if (cfg?.isActive) rocket = await tx.rocketEvent.create({ data: { roomId: gift.roomId, configSnapshot: cfg,
        targetCoins: cfg.targetCoins, startedAt: gift.createdAt, endsAt: new Date(gift.createdAt.getTime() + cfg.durationMinutes * 60000) } });
    }
    let launched = false;
    if (rocket && !await tx.rocketContribution.findUnique({ where: { giftTransactionId } })) {
      const coins = Math.floor(gift.paidCoins * rocket.configSnapshot.roomCupPercent / 10000);
      await tx.rocketContribution.create({ data: { eventId: rocket.id, giftTransactionId, userId: gift.senderId, coins } });
      rocket = await tx.rocketEvent.update({ where: { id: rocket.id }, data: { currentCoins: Math.min(MAX, rocket.currentCoins + coins) } });
      if (rocket.currentCoins >= rocket.targetCoins) {
        const flip = await tx.rocketEvent.updateMany({ where: { id: rocket.id, status: 'ACTIVE' }, data: { status: 'LAUNCHED', launchedAt: now } });
        launched = flip.count === 1;
        rocket = { ...rocket, status: 'LAUNCHED', launchedAt: now };
      }
    }
    const lock = await tx.pkRoomLock.findUnique({ where: { roomId: gift.roomId }, include: { pk: true } });
    let pk = lock?.pk;
    if (pk?.status === 'ACTIVE' && gift.createdAt >= pk.startedAt && gift.createdAt < pk.endsAt) {
      const cfg = pk.configSnapshot;
      // Room-vs-room: a gift counts for the room it was sent in. Inside one
      // room (both sides share the room) it counts for the side whose player
      // RECEIVED it — never for whoever opened the PK by default.
      const side = pk.room1Id === pk.room2Id
        ? (gift.recipientId === pk.sideAUserId ? 'A' : gift.recipientId === pk.sideBUserId ? 'B' : null)
        : gift.roomId === pk.room1Id ? 'A' : gift.roomId === pk.room2Id ? 'B' : null;
      if (side && (!cfg.countedGiftIds.length || cfg.countedGiftIds.includes(gift.giftId)) &&
        !await tx.pkContribution.findUnique({ where: { giftTransactionId } })) {
        const points = Math.min(MAX, gift.paidCoins * cfg.pointsPerCoin);
        await tx.pkContribution.create({ data: { pkId: pk.id, giftTransactionId, side, points, createdAt: gift.createdAt } });
        const field = side === 'A' ? 'room1Score' : 'room2Score';
        pk = await tx.pkBattle.update({ where: { id: pk.id }, data: { [field]: Math.min(MAX, pk[field] + points),
          [side === 'A' ? 'scoreReachedA' : 'scoreReachedB']: gift.createdAt } });
      }
    }
    await tx.roomGiftJob.update({ where: { giftTransactionId }, data: { processedAt: now } });
    return { rocket, launched, pk };
  });
  if (!out) return;
  if (out.rocket) queueState(`r:${out.rocket.id}`, [out.rocket.roomId], 'rocket_state', rocketView(out.rocket));
  if (out.launched) {
    const room = await db.room.findUnique({ where: { id: out.rocket.roomId }, select: { name: true } });
    // A single global emit already includes every socket in the source room.
    emitGlobal('rocket_launched', { ...rocketView(out.rocket), roomName: room?.name ?? '' });
  }
  if (out.pk) queueState(`p:${out.pk.id}`, [out.pk.room1Id, out.pk.room2Id], 'pk_state', pkView(out.pk));
}
export async function claimRocket(eventId: string, userId: number) {
  return eventTransaction(async tx => {
    const event = await tx.rocketEvent.findUnique({ where: { id: eventId } });
    if (!event) throw new RoomEventError('الصاروخ غير موجود', 404);
    if (!isUserInRoom(userId, event.roomId)) throw new RoomEventError('ادخل الغرفة أولاً', 403);
    const existing = await tx.rocketClaim.findUnique({ where: { rocketEventId_userId: { rocketEventId: eventId, userId } } });
    if (existing) return existing.rewardJson;
    const cfg = event.configSnapshot;
    if (event.status !== 'LAUNCHED' || Date.now() >= event.launchedAt.getTime() + cfg.claimWindowSeconds * 1000)
      throw new RoomEventError('انتهت فترة الاستلام', 409);
    if (await tx.rocketClaim.count({ where: { rocketEventId: eventId } }) >= cfg.winnersCount)
      throw new RoomEventError('اكتمل عدد الفائزين', 409);
    const reward = await grantReward(tx, userId, drawReward(cfg.rewards), 'ROCKET_POOL', `${eventId}:${userId}`, cfg.maxRewardPerUserCoins);
    await tx.rocketClaim.create({ data: { rocketEventId: eventId, userId, rewardJson: JSON.parse(JSON.stringify(reward)) } });
    await recordAdminAuditStrict(tx, { adminId: 0, action: 'ROCKET_REWARD', targetUserId: userId, targetId: eventId,
      before: reward.before, after: reward });
    return reward;
  });
}
export async function requireRoomManager(tx: any, roomId: number, userId: number, ownerOnly = false) {
  if (!isUserInRoom(userId, roomId)) throw new RoomEventError('ادخل الغرفة أولاً', 403);
  const room = await tx.room.findUnique({ where: { id: roomId } });
  const member = await tx.roomMember.findUnique({ where: { userId_roomId: { userId, roomId } } });
  if (!room?.isActive || (room.ownerId !== userId && (ownerOnly || !['admin', 'owner'].includes(member?.role))))
    throw new RoomEventError('ليست لديك صلاحية', 403);
  return room;
}
/** Custom length (client @199: «مربع كمان احط فيه المده»): 1–60 minutes. */
export function pkDurationSec(raw: unknown, cfg: any): number {
  const fallback = Array.isArray(cfg?.allowedDurations) && cfg.allowedDurations.length ? cfg.allowedDurations[0] : 300;
  return integer(raw ?? fallback, 60, 3600);
}
async function reservePk(tx: any, pk: any, cfg: any, userId: number) {
  const reserve = Object.values(cfg.rewards as Record<string, Reward>).reduce((sum, reward) =>
    sum + (reward.type === 'coins' || reward.type === 'both' ? (reward.coins ?? 0) * reward.quantity : 0), 0);
  if (reserve) {
    const movement = { kind: 'PK_RESERVE', refType: 'pk', refId: pk.id, userId };
    if (await debitAccount(tx, 'PK_POOL', reserve, movement) === null) throw new RoomEventError('رصيد صندوق PK غير كافٍ', 409);
    await creditAccount(tx, `PK_ESCROW:${pk.id}`, reserve, movement);
  }
  for (const id of new Set<number>([pk.room1Id, pk.room2Id])) await tx.pkRoomLock.create({ data: { roomId: id, pkId: pk.id } });
}
export async function startPk(userId: number, raw: any) {
  const roomId = integer(raw.roomId);
  const p: any = await eventTransaction(async tx => {
    const room = await requireRoomManager(tx, roomId, userId);
    const cfg = await tx.pkConfig.findFirst({ orderBy: { id: 'desc' } });
    if (!cfg?.enabled) throw new RoomEventError('PK غير متاح');
    const durationSec = pkDurationSec(raw.durationSec, cfg);
    if (!['ROOM', 'GLOBAL'].includes(raw.type)) throw new RoomEventError('نوع PK غير صالح');
    const global = raw.type === 'GLOBAL';
    const room2Id = global ? integer(raw.opponentRoomId) : roomId;
    const opponent = await tx.room.findUnique({ where: { id: room2Id } });
    if (global && room2Id === roomId) throw new RoomEventError('لا يمكن تحدي نفس الغرفة');
    if (!opponent) throw new RoomEventError('رقم الغرفة غير صحيح', 404);
    if (!opponent.isActive) throw new RoomEventError('الغرفة المنافسة مغلقة');
    const chosen = raw.sideUserId != null ? integer(raw.sideUserId) : null;
    if (chosen != null && global && !getSeatedUserIds(roomId).includes(chosen)) throw new RoomEventError('اللاعب المختار ليس على المايك');
    const a = global ? (chosen ?? room.ownerId) : integer(raw.sideAUserId);
    const b = global ? opponent.ownerId : integer(raw.sideBUserId);
    if (!global && (a === b || !getSeatedUserIds(roomId).includes(a) || !getSeatedUserIds(roomId).includes(b)))
      throw new RoomEventError('اختر مستخدمين مختلفين على المايك');
    const ids = [...new Set([roomId, room2Id])];
    if (await tx.pkRoomLock.count({ where: { roomId: { in: ids } } })) throw new RoomEventError('يوجد PK أو دعوة قائمة', 409);
    const now = new Date();
    const pk = await tx.pkBattle.create({ data: { room1Id: roomId, room2Id, type: raw.type,
      sideAUserId: a, sideBUserId: b, durationSec, configSnapshot: pkConfigSnapshot(cfg), createdBy: userId,
      status: global ? 'PENDING' : 'ACTIVE', startedAt: global ? null : now,
      endsAt: new Date(now.getTime() + (global ? 90 : durationSec) * 1000) } });
    await reservePk(tx, pk, cfg, userId);
    return pk;
  });
  if (p.status === 'PENDING') emitToUser(p.sideBUserId, 'pk_invite', pkView(p));
  for (const id of new Set<number>([p.room1Id, p.room2Id])) emitToRoomAndUsers(id, [], 'pk_state', pkView(p));
  return pkView(p);
}

const randomQueue = new PkMatchQueue();
const lockedRooms = new Set<number>();

/**
 * Random PK: the room waits for another room that also opted in; both opted
 * in, so the battle starts at once (no invitation). The longer-waiting room is
 * side A and its chosen length is used.
 */
export async function joinRandomPk(userId: number, raw: any) {
  const roomId = integer(raw.roomId);
  const sideUserId = raw.sideUserId != null ? integer(raw.sideUserId) : null;
  if (sideUserId != null && !getSeatedUserIds(roomId).includes(sideUserId)) throw new RoomEventError('اللاعب المختار ليس على المايك');
  const durationSec = await eventTransaction(async tx => {
    await requireRoomManager(tx, roomId, userId);
    const cfg = await tx.pkConfig.findFirst({ orderBy: { id: 'desc' } });
    if (!cfg?.enabled) throw new RoomEventError('PK غير متاح');
    if (await tx.pkRoomLock.count({ where: { roomId } })) throw new RoomEventError('يوجد PK أو دعوة قائمة', 409);
    const busy = await tx.pkRoomLock.findMany({ select: { roomId: true } });
    lockedRooms.clear();
    for (const l of busy) lockedRooms.add(l.roomId);
    return pkDurationSec(raw.durationSec, cfg);
  });
  const partner = randomQueue.take({ roomId, userId, durationSec, sideUserId }, id => lockedRooms.has(id));
  if (!partner) return { status: 'WAITING', roomId, durationSec };
  let p: any;
  try {
    p = await eventTransaction(async tx => {
      const cfg = await tx.pkConfig.findFirst({ orderBy: { id: 'desc' } });
      if (!cfg?.enabled) throw new RoomEventError('PK غير متاح');
      const [room1, room2] = await Promise.all([
        tx.room.findUnique({ where: { id: partner.roomId } }), tx.room.findUnique({ where: { id: roomId } })]);
      if (!room1?.isActive || !room2?.isActive) throw new RoomEventError('إحدى الغرفتين مغلقة');
      if (await tx.pkRoomLock.count({ where: { roomId: { in: [partner.roomId, roomId] } } }))
        throw new RoomEventError('يوجد PK أو دعوة قائمة', 409);
      const now = new Date();
      const pk = await tx.pkBattle.create({ data: { room1Id: partner.roomId, room2Id: roomId, type: 'GLOBAL',
        sideAUserId: partner.sideUserId ?? room1.ownerId, sideBUserId: sideUserId ?? room2.ownerId, durationSec: partner.durationSec,
        configSnapshot: { ...pkConfigSnapshot(cfg), random: true }, createdBy: partner.userId, status: 'ACTIVE', startedAt: now,
        endsAt: new Date(now.getTime() + partner.durationSec * 1000) } });
      await reservePk(tx, pk, cfg, partner.userId);
      return pk;
    });
  } catch (e) {
    // The partner did nothing wrong: it keeps its place.
    randomQueue.restore(partner);
    throw e;
  }
  for (const id of [p.room1Id, p.room2Id]) emitToRoomAndUsers(id, [], 'pk_state', pkView(p));
  for (const uid of new Set<number>([partner.userId, userId])) emitToUser(uid, 'pk_matched', pkView(p));
  return { status: 'MATCHED', pk: pkView(p) };
}
export async function cancelRandomPk(userId: number, raw: any) {
  const roomId = integer(raw.roomId);
  await eventTransaction(tx => requireRoomManager(tx, roomId, userId));
  return { cancelled: randomQueue.cancel(roomId) };
}
export async function acceptPk(id: string, userId: number) {
  const p: any = await eventTransaction(async tx => {
    const pk = await tx.pkBattle.findUnique({ where: { id } });
    if (!pk) throw new RoomEventError('PK غير موجود', 404);
    await requireRoomManager(tx, pk.room2Id, userId, true);
    if (pk.status === 'ACTIVE') return pk;
    if (pk.status !== 'PENDING' || pk.endsAt <= new Date()) throw new RoomEventError('انتهت الدعوة');
    const now = new Date();
    return tx.pkBattle.update({ where: { id }, data: { status: 'ACTIVE', startedAt: now, endsAt: new Date(now.getTime() + pk.durationSec * 1000) } });
  });
  for (const rid of new Set<number>([p.room1Id, p.room2Id])) emitToRoomAndUsers(rid, [], 'pk_state', pkView(p));
  return pkView(p);
}
export function pkWinner(p: any): 'A' | 'B' | 'TIE' {
  if (p.room1Score !== p.room2Score) return p.room1Score > p.room2Score ? 'A' : 'B';
  if (p.configSnapshot.tieRule === 'FIRST_TO_REACH' && p.room1Score > 0 && p.scoreReachedA && p.scoreReachedB) {
    const a = new Date(p.scoreReachedA).getTime(), b = new Date(p.scoreReachedB).getTime();
    if (a !== b) return a < b ? 'A' : 'B';
  }
  return 'TIE';
}
export async function finishPk(id: string) {
  const result: any = await eventTransaction(async tx => {
    const p = await tx.pkBattle.findUnique({ where: { id } });
    if (!p || !['PENDING', 'ACTIVE'].includes(p.status) || p.endsAt > new Date()) return null;
    const winner = p.status === 'PENDING' ? null : pkWinner(p);
    const status = p.status === 'PENDING' ? 'CANCELLED' : 'FINISHED';
    const flip = await tx.pkBattle.updateMany({ where: { id, status: p.status }, data: { status, winner, isActive: false } });
    if (!flip.count) return null;
    const rewards: any[] = [];
    const prizeEligible = !!winner && winner !== 'TIE' &&
      BigInt(p.room1Score + p.room2Score) >= BigInt(p.configSnapshot.minTotalCoins ?? 0);
    let prizeBox: any = null;
    if (prizeEligible) {
      for (const side of ['A', 'B']) {
        const reward = p.configSnapshot.rewards[side === winner ? 'winner' : 'loser'];
        if (reward) rewards.push(await grantReward(tx, side === 'A' ? p.sideAUserId : p.sideBUserId, reward, `PK_ESCROW:${id}`, `${id}:${side}`));
      }
    }
    if (prizeEligible) {
      const winnerUserId = winner === 'A' ? p.sideAUserId : p.sideBUserId;
      const user = await tx.user.findUniqueOrThrow({ where: { id: winnerUserId }, select: { name: true, avatarUrl: true } });
      prizeBox = await tx.pkPrizeBox.create({ data: { pkId: id, winnerUserId,
        winnerName: user.name ?? '', winnerAvatar: user.avatarUrl, room1Id: p.room1Id, room2Id: p.room2Id,
        expiresAt: new Date(Date.now() + 10 * 60000), configSnapshot: p.configSnapshot } });
    }
    const unused = (await readBalance(tx, `PK_ESCROW:${id}`)) ?? 0n;
    if (unused > 0n) {
      const movement = { kind: 'PK_RESERVE_RETURN', refType: 'pk', refId: id };
      if (await debitAccount(tx, `PK_ESCROW:${id}`, unused, movement) === null) throw new RoomEventError('رصيد حجز جوائز PK غير كافٍ، حاول مجدداً', 409);
      await creditAccount(tx, 'PK_POOL', unused, movement);
    }
    await tx.pkRoomLock.deleteMany({ where: { pkId: id } });
    const after = { ...pkView(p), status, isActive: false, winner, rewards, prizeEligible, prizeBox };
    await recordAdminAuditStrict(tx, { adminId: 0, action: 'PK_RESULT', targetId: id, before: pkView(p), after });
    return after;
  });
  if (result) {
    if (result.prizeBox) {
      const box = result.prizeBox;
      emitGlobal('pk_prize', { pkId: id, winnerName: box.winnerName, winnerAvatar: box.winnerAvatar,
        roomIds: [...new Set([box.room1Id, box.room2Id])], expiresAt: box.expiresAt });
    }
    pendingStates.delete(`p:${id}`);
    for (const rid of new Set<number>([result.room1Id, result.room2Id])) emitToRoomAndUsers(rid, [], 'pk_result', result);
  }
  return result;
}
export async function claimPk(pkId: string, userId: number) {
  return eventTransaction(async tx => {
    const box = await tx.pkPrizeBox.findUnique({ where: { pkId } });
    if (!box) throw new RoomEventError('صندوق جوائز PK غير متاح', 409);
    if (box.expiresAt <= new Date()) throw new RoomEventError('انتهت مهلة استلام جائزة PK', 409);
    if (box.winnerUserId === userId) throw new RoomEventError('الفائز استلم جائزته بالفعل', 409);
    if (await tx.pkClaim.findUnique({ where: { pkId_userId: { pkId, userId } } }))
      throw new RoomEventError('استلمت جائزة PK بالفعل', 409);
    const cfg = box.configSnapshot;
    const rewards: any[] = [];
    if (cfg.viewerGiftCoins > 0) rewards.push(await grantReward(tx, userId,
      { type: 'coins', coins: cfg.viewerGiftCoins, quantity: 1, weight: 1 }, 'PK_POOL', `${pkId}:${userId}`));
    if (cfg.viewerGiftItem) rewards.push(await grantReward(tx, userId, cfg.viewerGiftItem, 'PK_POOL', `${pkId}:${userId}`));
    if (!rewards.length) throw new RoomEventError('لا توجد هدية للمشاهدين في هذا الصندوق', 409);
    const reward = { rewards };
    await tx.pkClaim.create({ data: { pkId, userId, rewardJson: JSON.parse(JSON.stringify(reward)) } });
    await recordAdminAuditStrict(tx, { adminId: 0, action: 'PK_VIEWER_REWARD', targetUserId: userId, targetId: pkId, after: reward });
    return reward;
  });
}
let running = false;
export async function recoverRoomEvents() {
  if (running) return;
  running = true;
  try {
    const jobs = await db.roomGiftJob.findMany({ where: { processedAt: null }, orderBy: [{ createdAt: 'asc' }, { giftTransactionId: 'asc' }], take: 200 });
    for (const job of jobs) await processRoomGift(job.giftTransactionId);
    // Drain pending committed gifts before settling; a backlog cannot silently drop points.
    if (!await db.roomGiftJob.count({ where: { processedAt: null } })) {
      const expired = await db.pkBattle.findMany({ where: { status: { in: ['ACTIVE', 'PENDING'] }, endsAt: { lte: new Date() } }, take: 100 });
      for (const p of expired) {
        try { await finishPk(p.id); } catch (e) { console.warn('[pk settlement retry]', p.id, e); }
      }
    }
    await db.rocketEvent.updateMany({ where: { status: 'ACTIVE', endsAt: { lte: new Date() } }, data: { status: 'EXPIRED' } });
  } finally { running = false; }
}
export function startRoomEvents() {
  const run = () => recoverRoomEvents().catch(e => console.warn('[room events recovery]', e));
  void run();
  setInterval(run, 1000).unref();
  setInterval(() => {
    for (const { roomIds, event, payload } of pendingStates.values())
      for (const id of roomIds) emitToRoomAndUsers(id, [], event, payload);
    pendingStates.clear();
  }, 1000).unref();
}
