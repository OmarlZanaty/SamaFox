import { Response } from 'express';
import { prisma } from '../lib/prisma';
import { AuthReq } from '../types';
import { io } from '../index';
import { createNotification } from '../services/notification.service';
import { getUserCurrentRoomIds } from '../services/socket.service';

export const sendFollowRequest = async (req: AuthReq, res: Response) => {
  const followerId = req.userId!;
  const followingId = Number(req.params.userId);
  if (!Number.isInteger(followingId) || followingId <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid user id' });
  }
  if (followerId === followingId) return res.status(400).json({ success: false, message: 'Cannot follow yourself' });

  const targetUser = await prisma.user.findUnique({
    where: { id: followingId },
    select: { id: true },
  });
  if (!targetUser) return res.status(404).json({ success: false, message: 'User not found' });

  const block = await prisma.follow.findFirst({ where: { followerId: followingId, followingId: followerId, status: 'BLOCKED' } });
  if (block) return res.status(403).json({ success: false, message: 'Cannot follow this user' });

  const existing = await prisma.follow.findFirst({ where: { followerId, followingId } });
  let followId = existing?.id ?? null;
  if (existing) {
    if (existing.status === 'PENDING') return res.status(400).json({ success: false, message: 'Request already sent' });
    if (existing.status === 'ACCEPTED') return res.status(400).json({ success: false, message: 'Already following' });
    const updated = await prisma.follow.update({ where: { id: existing.id }, data: { status: 'PENDING', createdAt: new Date() } });
    followId = updated.id;
  } else {
    const created = await prisma.follow.create({ data: { followerId, followingId, status: 'PENDING' } });
    followId = created.id;
  }

  const follower = await prisma.user.findUnique({ where: { id: followerId }, select: { id: true, name: true, avatarUrl: true, displayId: true } });
  io.to(`user:${followingId}`).emit('follow_request', { fromUser: follower });
  if (follower) {
    await createNotification({
      userId: followingId,
      actorId: followerId,
      type: 'follow_request',
      title: 'New follow request',
      body: `${follower.name} sent you a follow request`,
      data: { followerId, followId },
    });
  }
  return res.status(201).json({ success: true, message: 'Follow request sent' });
};

export const respondToFollow = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;
  const followId = Number(req.params.followId);
  const action = String(req.body?.action ?? '').toLowerCase();
  const normalizedAction = action === 'refuse' ? 'reject' : action;
  if (!Number.isInteger(followId) || followId <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid follow id' });
  }
  if (!['accept', 'reject', 'block'].includes(normalizedAction)) {
    return res.status(400).json({ success: false, message: 'Invalid action' });
  }

  const follow = await prisma.follow.findUnique({ where: { id: followId } });
  if (!follow || follow.followingId !== userId) return res.status(403).json({ success: false, message: 'Not your request' });
  if (follow.status !== 'PENDING') {
    return res.status(400).json({ success: false, message: `Request already ${follow.status.toLowerCase()}` });
  }

  const statusMap = { accept: 'ACCEPTED', reject: 'REJECTED', block: 'BLOCKED' } as const;
  await prisma.follow.update({ where: { id: followId }, data: { status: statusMap[normalizedAction as keyof typeof statusMap] } });

  if (normalizedAction === 'accept') {
    const acceptor = await prisma.user.findUnique({ where: { id: userId }, select: { id: true, name: true, avatarUrl: true, displayId: true } });
    io.to(`user:${follow.followerId}`).emit('follow_accepted', { byUser: acceptor });
    if (acceptor) {
      await createNotification({
        userId: follow.followerId,
        actorId: userId,
        type: 'follow_accepted',
        title: 'Follow request accepted',
        body: `${acceptor.name} accepted your follow request`,
        data: { followId },
      });
    }
  } else if (normalizedAction === 'reject') {
    const rejector = await prisma.user.findUnique({ where: { id: userId }, select: { name: true } });
    io.to(`user:${follow.followerId}`).emit('follow_rejected', { followId, byUserId: userId });
    if (rejector) {
      await createNotification({
        userId: follow.followerId,
        actorId: userId,
        type: 'follow_rejected',
        title: 'Follow request rejected',
        body: `${rejector.name} rejected your follow request`,
        data: { followId },
      });
    }
  } else if (normalizedAction === 'block') {
    io.to(`user:${follow.followerId}`).emit('follow_blocked', { followId, byUserId: userId });
  }
  return res.json({ success: true, data: { followId, status: statusMap[normalizedAction as keyof typeof statusMap] } });
};

export const unfollow = async (req: AuthReq, res: Response) => {
  await prisma.follow.deleteMany({
    where: {
      followerId: req.userId!,
      followingId: Number(req.params.userId),
      status: { not: 'BLOCKED' }, // ✅ preserve blocks
    },
  });
  return res.json({ success: true });
};

export const removeFollower = async (req: AuthReq, res: Response) => {
  await prisma.follow.deleteMany({ where: { followerId: Number(req.params.userId), followingId: req.userId! } });
  return res.json({ success: true });
};

export const getFollowers = async (req: AuthReq, res: Response) => {
const p = Math.max(1, Number.isFinite(Number(req.query.page)) ? Number(req.query.page) : 1);
const l = Math.min(100, Math.max(1, Number.isFinite(Number(req.query.limit)) ? Number(req.query.limit) : 30));
  const [total, follows] = await Promise.all([
    prisma.follow.count({ where: { followingId: req.userId!, status: 'ACCEPTED' } }),
    prisma.follow.findMany({
      where: { followingId: req.userId!, status: 'ACCEPTED' }, orderBy: { createdAt: 'desc' },
      skip: (p - 1) * l, take: l,
      include: { follower: { select: { id: true, name: true, avatarUrl: true, displayId: true, level: true } } },
    }),
  ]);
  return res.json({ success: true, data: follows.map((f) => f.follower), pagination: { page: p, limit: l, total, totalPages: Math.ceil(total / l) } });
};

export const getFollowing = async (req: AuthReq, res: Response) => {
const p = Math.max(1, Number.isFinite(Number(req.query.page)) ? Number(req.query.page) : 1);
const l = Math.min(100, Math.max(1, Number.isFinite(Number(req.query.limit)) ? Number(req.query.limit) : 30));
  const [total, follows] = await Promise.all([
    prisma.follow.count({ where: { followerId: req.userId!, status: 'ACCEPTED' } }),
    prisma.follow.findMany({
      where: { followerId: req.userId!, status: 'ACCEPTED' }, orderBy: { createdAt: 'desc' },
      skip: (p - 1) * l, take: l,
      include: { following: { select: { id: true, name: true, avatarUrl: true, displayId: true, level: true } } },
    }),
  ]);
  // #25: attach the room each followed user is ACTUALLY in right now — as a
  // guest in someone else's room, or hosting their own — so the "live" badge
  // jumps to where they really are, not just a room they happen to own.
  const followedIds = follows.map((f) => f.following.id);
  const currentRooms = getUserCurrentRoomIds(followedIds);
  const liveRoomIds = Array.from(currentRooms.values());
  const liveRoomsInfo = liveRoomIds.length
    ? await prisma.room.findMany({ where: { id: { in: liveRoomIds } }, select: { id: true, name: true } })
    : [];
  const roomInfoById = new Map(liveRoomsInfo.map((r) => [r.id, r]));
  const data = follows.map((f) => {
    const rid = currentRooms.get(f.following.id) ?? null;
    const info = rid ? roomInfoById.get(rid) : null;
    return {
      ...f.following,
      liveRoomId: rid,
      liveRoomName: info?.name ?? null,
    };
  });
  return res.json({ success: true, data, pagination: { page: p, limit: l, total, totalPages: Math.ceil(total / l) } });
};

export const getPendingRequests = async (req: AuthReq, res: Response) => {
  const requests = await prisma.follow.findMany({
    where: { followingId: req.userId!, status: 'PENDING' }, orderBy: { createdAt: 'desc' },
    include: { follower: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
  });
  return res.json({ success: true, data: requests });
};

export const getFollowStatus = async (req: AuthReq, res: Response) => {
  const myId = req.userId!;
  const otherId = Number(req.params.userId);
  const [iFollow, theyFollow] = await Promise.all([
    prisma.follow.findFirst({ where: { followerId: myId, followingId: otherId } }),
    prisma.follow.findFirst({ where: { followerId: otherId, followingId: myId } }),
  ]);
  let status = 'none';
  if (iFollow?.status === 'ACCEPTED' && theyFollow?.status === 'ACCEPTED') status = 'mutual';
  else if (iFollow?.status === 'ACCEPTED') status = 'following';
  else if (iFollow?.status === 'PENDING') status = 'pending_sent';
  else if (theyFollow?.status === 'ACCEPTED') status = 'followed_by';
  else if (theyFollow?.status === 'PENDING') status = 'pending_received';
  else if (iFollow?.status === 'BLOCKED' || theyFollow?.status === 'BLOCKED') status = 'blocked';
  return res.json({ success: true, data: { status, followId: iFollow?.id ?? null } });
};
