import prisma from '../utils/prisma';
import type {} from '../middlewares/auth.middleware'; // req.userId typing
import { resolveUserByPublicId } from '../utils/resolveUserByPublicId';
import { perRoomCupSupport } from '../services/roomReward.service';
import { banHandler, banError, positiveId } from './adminNameImageBan.controller';

const db = prisma as any;
function coins(value: unknown, max: bigint): bigint {
  if (!/^\d+$/.test(String(value))) banError(400, 'أدخل عدداً صحيحاً موجباً');
  const n = BigInt(String(value));
  if (n <= 0n || n > max) banError(400, 'قيمة الكوينز غير صالحة');
  return n;
}
const serialize = (row: any) => ({ ...row, targetCoins: String(row.targetCoins), ownerRewardCoins: String(row.ownerRewardCoins) });
export const createRoomCup = banHandler(async req => {
  const ref = positiveId(req.body.roomRef);
  // Several levels (client 10/11 19:02): [{ targetCoins, rewardCoins }], each
  // reward being the owner's TOTAL at that level. Without them, the single
  // target/reward pair is the only level, as before.
  const rawLevels = Array.isArray(req.body.levels) ? req.body.levels : [];
  if (rawLevels.length > 20) banError(400, 'أقصى عدد للمستويات 20');
  const levels = rawLevels.map((l: any) => ({
    targetCoins: coins(l?.targetCoins, 9223372036854775807n),
    // Wallets and transaction amounts are currently PostgreSQL Int columns.
    rewardCoins: coins(l?.rewardCoins, 2147483647n),
  })).sort((a: any, b: any) => (a.targetCoins < b.targetCoins ? -1 : 1));
  for (let i = 1; i < levels.length; i++) {
    if (levels[i].targetCoins === levels[i - 1].targetCoins) banError(400, 'مستويين بنفس الدعم المطلوب');
    if (levels[i].rewardCoins < levels[i - 1].rewardCoins) banError(400, 'مكافأة كل مستوى هي الإجمالي عنده، فلازم تكون أكبر من أو تساوي اللي قبله');
  }
  const top = levels[levels.length - 1];
  const targetCoins = top ? top.targetCoins : coins(req.body.targetCoins, 9223372036854775807n);
  const ownerRewardCoins = top ? top.rewardCoins : coins(req.body.ownerRewardCoins, 2147483647n);
  const hours = Number(req.body.hours);
  const startsAt = req.body.startsAt == null ? new Date() : new Date(req.body.startsAt);
  const endsAt = new Date(startsAt.getTime() + hours * 3600000);
  if (!Number.isFinite(hours) || hours <= 0 || !Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime()) || endsAt <= startsAt) banError(400, 'المدة أو وقت البداية غير صالح');
  let room = await db.room.findUnique({ where: { id: ref } });
  if (!room) {
    const owner = await resolveUserByPublicId(ref);
    if (owner) room = await db.room.findFirst({ where: { ownerId: owner.id }, orderBy: { id: 'asc' } });
  }
  if (!room) banError(404, 'الغرفة غير موجودة');
  return serialize(await db.roomCup.create({ data: { roomId: room.id, targetCoins, ownerRewardCoins, startsAt, endsAt, createdById: req.userId,
    levels: levels.map((l: any) => ({ targetCoins: String(l.targetCoins), rewardCoins: String(l.rewardCoins) })) } }));
});
export const listRoomCups = banHandler(async () => {
  const rows = await db.roomCup.findMany({ orderBy: { id: 'desc' } });
  return Promise.all(rows.map(async (cup: any) => {
    const room = await db.room.findUnique({ where: { id: cup.roomId }, select: { name: true, owner: { select: { name: true } } } });
    const support = await perRoomCupSupport(cup);
    return { ...serialize(cup), support: String(support), roomName: room?.name ?? '', ownerName: room?.owner?.name ?? '',
      levels: Array.isArray(cup.levels) ? cup.levels : [],
      status: cup.paidAt ? 'وصل لآخر مستوى' : cup.endsAt < new Date() && support < BigInt(cup.targetCoins) ? 'انتهى بدون وصول' : 'جاري' };
  }));
});
export const deleteRoomCup = banHandler(async req => {
  const result = await db.roomCup.deleteMany({ where: { id: positiveId(req.params.id), paidAt: null } });
  if (!result.count) banError(409, 'لا يمكن حذف كأس مصروف أو غير موجود');
  return result;
});

/** Room-cup rewards granted: who, how much, and whether he collected it. */
export const listRoomCupClaims = banHandler(async req => {
  const status = String(req.query.status ?? 'all');
  const where = status === 'pending' ? { claimedAt: null } : status === 'claimed' ? { claimedAt: { not: null } } : {};
  const rows = await db.roomCupClaim.findMany({ where, orderBy: { id: 'desc' }, take: 300 });
  const userIds = [...new Set(rows.map((r: any) => r.userId))];
  const roomIds = [...new Set(rows.map((r: any) => r.roomId))];
  const [users, rooms] = await Promise.all([
    db.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true, displayId: true } }),
    db.room.findMany({ where: { id: { in: roomIds } }, select: { id: true, name: true } }),
  ]);
  const u = new Map(users.map((x: any) => [x.id, x]));
  const r = new Map(rooms.map((x: any) => [x.id, x]));
  return rows.map((c: any) => ({
    id: c.id, roomId: c.roomId, roomName: (r.get(c.roomId) as any)?.name ?? '',
    userId: c.userId, userName: (u.get(c.userId) as any)?.name ?? '', displayId: (u.get(c.userId) as any)?.displayId ?? null,
    coins: String(c.coins), source: c.source === 'cup' ? `كأس بالـ ID #${c.refId} — مستوى ${c.level + 1}` : 'كأس الروم',
    createdAt: c.createdAt, claimedAt: c.claimedAt,
  }));
});

