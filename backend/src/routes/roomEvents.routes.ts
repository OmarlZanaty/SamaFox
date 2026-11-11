import { Router, Request, Response, NextFunction } from 'express';
import prisma from '../utils/prisma';
import { authenticate } from '../middlewares/auth.middleware';
import { idempotent } from '../middlewares/idempotency.middleware';
import { requireOwnerPermission } from '../services/ownerPermissions.service';
import { acceptPk, cancelRandomPk, joinRandomPk, claimPk, claimRocket, claimRocketTopPrize, pendingRocketTopPrizes, fundEventPool, integer, pkView, rocketView, saveEventConfig, startPk, RoomEventError } from '../services/roomEvents.service';
import { isUserInRoom, getSeatedUserIds } from '../services/socket.service';
import { readBalance } from '../services/economyAccounts.service';

const db = prisma as any;
const wrap = (fn: (req: Request) => Promise<unknown>) => async (req: Request, res: Response, next: NextFunction) => {
  try { res.json({ success: true, data: await fn(req) }); }
  catch (e) {
    if (e instanceof RoomEventError) res.status(e.status).json({ success: false, message: e.message });
    else next(e);
  }
};
export const roomEventsRouter = Router();
roomEventsRouter.use(['/room-events', '/rockets', '/pk'], authenticate);
roomEventsRouter.get('/room-events/:roomId', wrap(async req => {
  const roomId = integer(Number(req.params.roomId));
  if (!isUserInRoom(req.userId!, roomId)) throw new RoomEventError('ادخل الغرفة أولاً', 403);
  const rocket = await db.rocketEvent.findFirst({ where: { roomId }, orderBy: { startedAt: 'desc' } });
  const pk = await db.pkBattle.findFirst({ where: { OR: [{ room1Id: roomId }, { room2Id: roomId }] }, orderBy: { createdAt: 'desc' } });
  const config = await db.pkConfig.findFirst({ orderBy: { id: 'desc' } });
  const rocketConfig = await db.rocketConfig.findFirst({ where: { isActive: true } });
  const seated = await db.user.findMany({ where: { id: { in: getSeatedUserIds(roomId) } }, select: { id: true, name: true, avatarUrl: true } });
  const participants = pk ? await db.user.findMany({ where: { id: { in: [pk.sideAUserId, pk.sideBUserId].filter(Boolean) } }, select: { id: true, name: true, avatarUrl: true } }) : [];
  const myTopPrizes = await pendingRocketTopPrizes(req.userId!);
  return { rocket: rocketView(rocket), rocketConfig, myTopPrizes, pk: pkView(pk), pkConfig: config ? { ...config, minTotalCoins: String(config.minTotalCoins ?? 0) } : null, seated, participants };
}));
// Top-supporter prize held under the user's name (any room).
roomEventsRouter.post('/rockets/top-prizes/:id/claim', idempotent('rocket-top-claim'), wrap(req => claimRocketTopPrize(integer(Number(req.params.id)), req.userId!)));
roomEventsRouter.post('/rockets/:eventId/claim', idempotent('rocket-claim'), wrap(req => claimRocket(String(req.params.eventId), req.userId!)));
roomEventsRouter.post('/pk/:id/claim', wrap(req => claimPk(String(req.params.id), req.userId!)));
roomEventsRouter.post('/pk/start', idempotent('pk-start'), wrap(req => startPk(req.userId!, req.body)));
roomEventsRouter.post('/pk/random', wrap(req => joinRandomPk(req.userId!, req.body)));
roomEventsRouter.post('/pk/random/cancel', wrap(req => cancelRandomPk(req.userId!, req.body)));
roomEventsRouter.post('/pk/:id/accept', idempotent('pk-accept'), wrap(req => acceptPk(String(req.params.id), req.userId!)));

// Mounted inside the authenticated admin dashboard router.
export const adminRoomEventsRouter = Router();
adminRoomEventsRouter.use(['/rocket', '/pk'], requireOwnerPermission('economy.settings'));
for (const kind of ['rocket', 'pk'] as const) {
  adminRoomEventsRouter.get(`/${kind}`, wrap(async () => {
    const config = await (kind === 'rocket' ? db.rocketConfig : db.pkConfig).findFirst({ orderBy: { id: 'desc' } });
    const events = kind === 'rocket'
      ? await db.rocketEvent.findMany({ orderBy: { startedAt: 'desc' }, take: 50, include: { claims: { orderBy: { claimedAt: 'desc' }, take: 100 } } })
      : await db.pkBattle.findMany({ orderBy: { createdAt: 'desc' }, take: 50 });
    const products = await db.item.findMany({ select: { id: true, name: true, durationDays: true, type: true }, orderBy: { name: 'asc' } });
    const gifts = await db.gift.findMany({ select: { id: true, name: true, nameAr: true } });
    return { config: kind === 'pk' && config ? { ...config, minTotalCoins: String(config.minTotalCoins ?? 0) } : config,
      events, products, gifts, poolBalance: String((await readBalance(db, kind === 'rocket' ? 'ROCKET_POOL' : 'PK_POOL')) ?? 0n) };
  }));
  adminRoomEventsRouter.put(`/${kind}/config`, idempotent(`${kind}-config`), wrap(req => saveEventConfig(kind, req.body, req.userId!)));
  adminRoomEventsRouter.post(`/${kind}/fund`, idempotent(`${kind}-fund`), wrap(async req => {
    if (!req.get('Idempotency-Key') && !req.body?.requestId) throw new RoomEventError('مفتاح العملية مطلوب');
    return fundEventPool(kind, req.body?.amount, req.userId!);
  }));
}
