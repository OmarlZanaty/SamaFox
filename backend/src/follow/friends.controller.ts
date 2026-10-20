import { Request, Response, Router } from 'express';
import prisma from '../utils/prisma';
import { authMiddleware as auth } from '../middlewares/auth.middleware';
import { createNotification } from '../services/notification.service';
import { emitToUser } from '../services/socket.service';
import { withNameStyles } from '../services/vipStyle.service';

/**
 * SPEC52 #12 — الأصدقاء: a real request → accept relation (pending /
 * accepted / rejected / blocked), separate from one-way follows. Someone is
 * a friend only after accepting. One row per pair.
 */
const db = prisma as any;
type R = Request & { userId?: number };
const pair = (a: number, b: number) => ({ userLowId: Math.min(a, b), userHighId: Math.max(a, b) });
const PUBLIC = { id: true, name: true, avatarUrl: true, avatarFrameUrl: true, displayId: true, level: true, vipLevel: true } as const;
const err = (res: Response, s: number, m: string) => res.status(s).json({ success: false, message: m });

export const friendsRouter = Router();

/** Friendship state between me and :userId — none | pending_out | pending_in | friends | blocked */
export async function friendState(me: number, other: number) {
  const f = await db.friendship.findUnique({ where: { userLowId_userHighId: pair(me, other) } });
  if (!f || f.status === 'rejected') return { state: 'none', id: f?.id ?? null };
  if (f.status === 'accepted') return { state: 'friends', id: f.id };
  if (f.status === 'blocked') return { state: 'blocked', id: f.id };
  return { state: f.requesterId === me ? 'pending_out' : 'pending_in', id: f.id };
}

friendsRouter.get('/status/:userId', auth, async (req: R, res) => {
  res.json({ success: true, data: await friendState(req.userId!, Number(req.params.userId)) });
});

friendsRouter.post('/requests', auth, async (req: R, res) => {
  try {
    const me = req.userId!;
    const other = Number(req.body?.userId);
    if (!other || other === me) return err(res, 400, 'مستخدم غير صالح');
    const target = await db.user.findUnique({ where: { id: other }, select: { id: true } });
    if (!target) return err(res, 404, 'المستخدم غير موجود');
    const blocked = await db.userBlock?.findFirst?.({ where: { OR: [{ blockerId: me, blockedId: other }, { blockerId: other, blockedId: me }] } }).catch(() => null);
    if (blocked) return err(res, 403, 'لا يمكن إرسال طلب صداقة لهذا المستخدم');
    const key = pair(me, other);
    const f = await db.friendship.findUnique({ where: { userLowId_userHighId: key } });
    if (f?.status === 'accepted') return res.json({ success: true, data: { state: 'friends', id: f.id } });
    if (f?.status === 'blocked') return err(res, 403, 'لا يمكن إرسال طلب صداقة لهذا المستخدم');
    if (f?.status === 'pending' && f.requesterId !== me) {
      // They already asked me: sending back = accepting.
      const acc = await db.friendship.update({ where: { id: f.id }, data: { status: 'accepted', acceptedAt: new Date() } });
      emitToUser(other, 'friend_accepted', { userId: me, friendshipId: acc.id });
      return res.json({ success: true, data: { state: 'friends', id: acc.id } });
    }
    if (f?.status === 'pending') return res.json({ success: true, data: { state: 'pending_out', id: f.id } });
    const row = f
      ? await db.friendship.update({ where: { id: f.id }, data: { status: 'pending', requesterId: me, receiverId: other, acceptedAt: null, blockedAt: null, createdAt: new Date() } })
      : await db.friendship.create({ data: { ...key, requesterId: me, receiverId: other, status: 'pending' } });
    const meUser = await db.user.findUnique({ where: { id: me }, select: { name: true } });
    await createNotification({ userId: other, actorId: me, type: 'friend_request', title: 'طلب صداقة', body: `${meUser?.name ?? 'مستخدم'} أرسل لك طلب صداقة`, data: { friendshipId: row.id } }).catch(() => {});
    emitToUser(other, 'friend_request', { userId: me, friendshipId: row.id });
    return res.status(201).json({ success: true, data: { state: 'pending_out', id: row.id } });
  } catch (e: any) {
    if (e?.code === 'P2002') return err(res, 409, 'الطلب موجود بالفعل');
    console.error('[friends.request]', e);
    return err(res, 500, 'Server error');
  }
});

async function respond(req: R, res: Response, accept: boolean) {
  const me = req.userId!;
  const f = await db.friendship.findUnique({ where: { id: Number(req.params.id) } });
  if (!f || f.receiverId !== me || f.status !== 'pending') return err(res, 404, 'الطلب غير موجود');
  const row = await db.friendship.update({
    where: { id: f.id },
    data: accept ? { status: 'accepted', acceptedAt: new Date() } : { status: 'rejected' },
  });
  if (accept) emitToUser(f.requesterId, 'friend_accepted', { userId: me, friendshipId: f.id });
  return res.json({ success: true, data: row });
}
friendsRouter.post('/requests/:id/accept', auth, (req: R, res) => respond(req, res, true));
friendsRouter.post('/requests/:id/reject', auth, (req: R, res) => respond(req, res, false));

friendsRouter.get('/requests', auth, async (req: R, res) => {
  const me = req.userId!;
  const incoming = req.query.direction !== 'out';
  const rows = await db.friendship.findMany({
    where: incoming ? { receiverId: me, status: 'pending' } : { requesterId: me, status: 'pending' },
    orderBy: { createdAt: 'desc' },
    take: 200,
  });
  const ids = rows.map((r: any) => (incoming ? r.requesterId : r.receiverId));
  const users = ids.length ? await db.user.findMany({ where: { id: { in: ids } }, select: PUBLIC }) : [];
  const byId = new Map<number, any>(withNameStyles(users).map((u: any) => [u.id, u]));
  res.json({ success: true, data: rows.map((r: any) => ({ id: r.id, createdAt: r.createdAt, user: byId.get(incoming ? r.requesterId : r.receiverId) ?? null })) });
});

friendsRouter.delete('/:userId', auth, async (req: R, res) => {
  const me = req.userId!;
  const other = Number(req.params.userId);
  await db.friendship.deleteMany({ where: { ...pair(me, other), status: { in: ['accepted', 'pending', 'rejected'] } } });
  res.json({ success: true });
});

friendsRouter.post('/:userId/block', auth, async (req: R, res) => {
  const me = req.userId!;
  const other = Number(req.params.userId);
  if (!other || other === me) return err(res, 400, 'مستخدم غير صالح');
  const key = pair(me, other);
  const row = await db.friendship.upsert({
    where: { userLowId_userHighId: key },
    create: { ...key, requesterId: me, receiverId: other, status: 'blocked', blockedAt: new Date() },
    update: { status: 'blocked', requesterId: me, receiverId: other, blockedAt: new Date() },
  });
  res.json({ success: true, data: row });
});

/** Accepted friends of the caller. */
friendsRouter.get('/', auth, async (req: R, res) => {
  const me = req.userId!;
  const rows = await db.friendship.findMany({ where: { status: 'accepted', OR: [{ userLowId: me }, { userHighId: me }] }, take: 1000 });
  const ids = rows.map((r: any) => (r.userLowId === me ? r.userHighId : r.userLowId));
  const users = ids.length ? await db.user.findMany({ where: { id: { in: ids } }, select: PUBLIC }) : [];
  res.json({ success: true, data: withNameStyles(users) });
});

/** Real counts from the database — no fixed numbers anywhere. */
export async function socialCounts(userId: number) {
  const [friends, followers, following, visitors] = await Promise.all([
    db.friendship.count({ where: { status: 'accepted', OR: [{ userLowId: userId }, { userHighId: userId }] } }),
    db.follow.count({ where: { followingId: userId, status: 'ACCEPTED' } }),
    db.follow.count({ where: { followerId: userId, status: 'ACCEPTED' } }),
    db.profileVisit.groupBy({ by: ['viewerId'], where: { profileId: userId } }).then((g: any[]) => g.length),
  ]);
  return { friends, followers, following, visitors };
}
