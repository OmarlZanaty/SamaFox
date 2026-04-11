import { Response } from 'express';
import { prisma } from '../lib/prisma';
import { AuthReq } from '../types';
import { io } from '../index';

export const sendFollowRequest = async (req: AuthReq, res: Response) => {
  const followerId = req.userId!;
  const followingId = Number(req.params.userId);
  if (followerId === followingId) return res.status(400).json({ success: false, message: 'Cannot follow yourself' });

  const block = await prisma.follow.findFirst({ where: { followerId: followingId, followingId: followerId, status: 'BLOCKED' } });
  if (block) return res.status(403).json({ success: false, message: 'Cannot follow this user' });

  const existing = await prisma.follow.findFirst({ where: { followerId, followingId } });
  if (existing) {
    if (existing.status === 'PENDING') return res.status(400).json({ success: false, message: 'Request already sent' });
    if (existing.status === 'ACCEPTED') return res.status(400).json({ success: false, message: 'Already following' });
    await prisma.follow.update({ where: { id: existing.id }, data: { status: 'PENDING', createdAt: new Date() } });
  } else {
    await prisma.follow.create({ data: { followerId, followingId, status: 'PENDING' } });
  }

  const follower = await prisma.user.findUnique({ where: { id: followerId }, select: { id: true, name: true, avatarUrl: true, displayId: true } });
  io.to(`user:${followingId}`).emit('follow_request', { fromUser: follower });
  return res.status(201).json({ success: true, message: 'Follow request sent' });
};

export const respondToFollow = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;
  const followId = Number(req.params.followId);
  const { action } = req.body;
  if (!['accept', 'reject', 'block'].includes(action)) return res.status(400).json({ success: false, message: 'Invalid action' });

  const follow = await prisma.follow.findUnique({ where: { id: followId } });
  if (!follow || follow.followingId !== userId) return res.status(403).json({ success: false, message: 'Not your request' });

  const statusMap = { accept: 'ACCEPTED', reject: 'REJECTED', block: 'BLOCKED' } as const;
  await prisma.follow.update({ where: { id: followId }, data: { status: statusMap[action as keyof typeof statusMap] } });

  if (action === 'accept') {
    const acceptor = await prisma.user.findUnique({ where: { id: userId }, select: { id: true, name: true, avatarUrl: true, displayId: true } });
    io.to(`user:${follow.followerId}`).emit('follow_accepted', { byUser: acceptor });
  }
  return res.json({ success: true });
};

export const unfollow = async (req: AuthReq, res: Response) => {
  await prisma.follow.deleteMany({ where: { followerId: req.userId!, followingId: Number(req.params.userId) } });
  return res.json({ success: true });
};

export const removeFollower = async (req: AuthReq, res: Response) => {
  await prisma.follow.deleteMany({ where: { followerId: Number(req.params.userId), followingId: req.userId! } });
  return res.json({ success: true });
};

export const getFollowers = async (req: AuthReq, res: Response) => {
  const { page = 1, limit = 30 } = req.query;
  const p = Number(page), l = Number(limit);
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
  const { page = 1, limit = 30 } = req.query;
  const p = Number(page), l = Number(limit);
  const [total, follows] = await Promise.all([
    prisma.follow.count({ where: { followerId: req.userId!, status: 'ACCEPTED' } }),
    prisma.follow.findMany({
      where: { followerId: req.userId!, status: 'ACCEPTED' }, orderBy: { createdAt: 'desc' },
      skip: (p - 1) * l, take: l,
      include: { following: { select: { id: true, name: true, avatarUrl: true, displayId: true, level: true } } },
    }),
  ]);
  return res.json({ success: true, data: follows.map((f) => f.following), pagination: { page: p, limit: l, total, totalPages: Math.ceil(total / l) } });
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
