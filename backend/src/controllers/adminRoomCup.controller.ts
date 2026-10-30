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
  const targetCoins = coins(req.body.targetCoins, 9223372036854775807n);
  // Wallets and transaction amounts are currently PostgreSQL Int columns.
  const ownerRewardCoins = coins(req.body.ownerRewardCoins, 2147483647n);
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
  return serialize(await db.roomCup.create({ data: { roomId: room.id, targetCoins, ownerRewardCoins, startsAt, endsAt, createdById: req.userId } }));
});
export const listRoomCups = banHandler(async () => {
  const rows = await db.roomCup.findMany({ orderBy: { id: 'desc' } });
  return Promise.all(rows.map(async (cup: any) => {
    const room = await db.room.findUnique({ where: { id: cup.roomId }, select: { name: true, owner: { select: { name: true } } } });
    const support = await perRoomCupSupport(cup);
    return { ...serialize(cup), support: String(support), roomName: room?.name ?? '', ownerName: room?.owner?.name ?? '',
      status: cup.paidAt ? 'تم الصرف' : cup.endsAt < new Date() && support < BigInt(cup.targetCoins) ? 'انتهى بدون وصول' : 'جاري' };
  }));
});
export const deleteRoomCup = banHandler(async req => {
  const result = await db.roomCup.deleteMany({ where: { id: positiveId(req.params.id), paidAt: null } });
  if (!result.count) banError(409, 'لا يمكن حذف كأس مصروف أو غير موجود');
  return result;
});
