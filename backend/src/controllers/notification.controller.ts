import { Response } from 'express';
import { AuthReq } from '../types';
import { prisma } from '../lib/prisma';

export const listNotifications = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;
  const page = Math.max(1, Number(req.query.page) || 1);
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 30));

  const [total, unreadCount, notifications] = await Promise.all([
    prisma.notification.count({ where: { userId } }),
    prisma.notification.count({ where: { userId, isRead: false } }),
    prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      include: {
        actor: { select: { id: true, name: true, avatarUrl: true, displayId: true } },
      },
    }),
  ]);

  return res.json({
    success: true,
    data: notifications,
    unreadCount,
    pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
  });
};

export const markNotificationRead = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;
  const id = Number(req.params.id);

  await prisma.notification.updateMany({
    where: { id, userId, isRead: false },
    data: { isRead: true, readAt: new Date() },
  });

  return res.json({ success: true });
};

export const markAllNotificationsRead = async (req: AuthReq, res: Response) => {
  const userId = req.userId!;

  await prisma.notification.updateMany({
    where: { userId, isRead: false },
    data: { isRead: true, readAt: new Date() },
  });

  return res.json({ success: true });
};
