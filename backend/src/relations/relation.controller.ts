import { Response } from 'express';
import { prisma } from '../lib/prisma';
import { AuthReq } from '../types';
import { io } from '../index';
import { createNotification } from '../services/notification.service';

export const sendRelationRequest = async (req: AuthReq, res: Response) => {
  const user1Id = req.userId!;
  const user2Id = Number(req.params.userId);

  if (!Number.isFinite(user2Id) || user2Id <= 0) {
    return res.status(400).json({ success: false, message: 'Invalid user id' });
  }

  if (user1Id === user2Id) {
    return res.status(400).json({ success: false, message: 'Cannot request yourself' });
  }

  const [u1, u2] = await Promise.all([
    prisma.user.findUnique({ where: { id: user1Id }, select: { relationId: true } }),
    prisma.user.findUnique({ where: { id: user2Id }, select: { relationId: true } }),
  ]);

  if (!u2) return res.status(404).json({ success: false, message: 'User not found' });
  if (u1?.relationId) return res.status(400).json({ success: false, message: 'You are already in a relation' });
  if (u2.relationId) return res.status(400).json({ success: false, message: 'This user is already in a relation' });

  const existing = await prisma.relation.findFirst({
    where: {
      OR: [{ user1Id, user2Id }, { user1Id: user2Id, user2Id: user1Id }],
      status: { in: ['PENDING', 'ACTIVE'] },
    },
  });

  if (existing) {
    return res.status(400).json({ success: false, message: 'Request already exists' });
  }

  const relation = await prisma.relation.create({ data: { user1Id, user2Id, status: 'PENDING' } });

  const sender = await prisma.user.findUnique({
    where: { id: user1Id },
    select: { id: true, name: true, avatarUrl: true, displayId: true },
  });

  io.to(`user:${user2Id}`).emit('relation_request', { relationId: relation.id, fromUser: sender });
  if (sender) {
    await createNotification({
      userId: user2Id,
      actorId: user1Id,
      type: 'relation_request',
      title: 'New relation request',
      body: `${sender.name} sent you a relation request`,
      data: { relationId: relation.id, fromUserId: user1Id },
    });
  }

  return res.status(201).json({ success: true, data: relation });
};

export const respondToRelation = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;
  const relationId = Number(req.params.id);
  const { action } = req.body as { action?: string };

  if (!['accept', 'reject'].includes(String(action))) {
    return res.status(400).json({ success: false, message: 'Invalid action' });
  }

  const relation = await prisma.relation.findUnique({ where: { id: relationId } });
  if (!relation) return res.status(404).json({ success: false, message: 'Not found' });
  if (relation.user2Id !== userId) return res.status(403).json({ success: false, message: 'Not your request' });
  if (relation.status !== 'PENDING') return res.status(400).json({ success: false, message: 'Already processed' });

  if (action === 'accept') {
    await prisma.$transaction([
      prisma.relation.update({
        where: { id: relationId },
        data: { status: 'ACTIVE', acceptedAt: new Date() },
      }),
      prisma.user.update({ where: { id: relation.user1Id }, data: { relationId } }),
      prisma.user.update({ where: { id: relation.user2Id }, data: { relationId } }),
    ]);

    const acceptor = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, name: true, avatarUrl: true },
    });

    io.to(`user:${relation.user1Id}`).emit('relation_accepted', { byUser: acceptor, relationId });
    if (acceptor) {
      await createNotification({
        userId: relation.user1Id,
        actorId: userId,
        type: 'relation_accepted',
        title: 'Relation request accepted',
        body: `${acceptor.name} accepted your relation request`,
        data: { relationId },
      });
    }
    io.emit('relation_formed', { user1Id: relation.user1Id, user2Id: relation.user2Id, relationId });
  } else {
    await prisma.relation.update({ where: { id: relationId }, data: { status: 'ENDED' } });
  }

  return res.json({ success: true });
};

export const endRelation = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;
  const relationId = Number(req.params.id);
  const relation = await prisma.relation.findUnique({ where: { id: relationId } });

  if (!relation) return res.status(404).json({ success: false, message: 'Not found' });
  if (relation.user1Id !== userId && relation.user2Id !== userId) {
    return res.status(403).json({ success: false, message: 'Not your relation' });
  }
  if (relation.status !== 'ACTIVE') return res.status(400).json({ success: false, message: 'Not active' });

  await prisma.$transaction([
    prisma.relation.update({ where: { id: relationId }, data: { status: 'ENDED' } }),
    prisma.user.update({ where: { id: relation.user1Id }, data: { relationId: null } }),
    prisma.user.update({ where: { id: relation.user2Id }, data: { relationId: null } }),
  ]);

  const partnerId = relation.user1Id === userId ? relation.user2Id : relation.user1Id;
  io.to(`user:${partnerId}`).emit('relation_ended', { byUserId: userId });

  return res.json({ success: true });
};

export const getMyRelation = async (req: AuthReq, res: Response) => {
  const user = await prisma.user.findUnique({
    where: { id: req.userId! },
    select: { relationId: true },
  });

  if (!user?.relationId) return res.json({ success: true, data: null });

  const relation = await prisma.relation.findUnique({
    where: { id: user.relationId },
    include: {
      user1: { select: { id: true, name: true, avatarUrl: true, displayId: true } },
      user2: { select: { id: true, name: true, avatarUrl: true, displayId: true } },
    },
  });

  const partner = relation?.user1Id === req.userId ? relation?.user2 : relation?.user1;
  return res.json({ success: true, data: { relation, partner } });
};

export const getPendingRelationRequests = async (req: AuthReq, res: Response) => {
  const requests = await prisma.relation.findMany({
    where: { user2Id: req.userId!, status: 'PENDING' },
    orderBy: { requestedAt: 'desc' },
    include: {
      user1: { select: { id: true, name: true, avatarUrl: true, displayId: true } },
    },
  });

  return res.json({ success: true, data: requests });
};
