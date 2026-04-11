import { io } from '../index';
import { prisma } from '../lib/prisma';

type CreateNotificationInput = {
  userId: number;
  actorId?: number | null;
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
};

export const createNotification = async (input: CreateNotificationInput) => {
  const notification = await prisma.notification.create({
    data: {
      userId: input.userId,
      actorId: input.actorId ?? null,
      type: input.type,
      title: input.title,
      body: input.body,
      data: (input.data ?? undefined) as any,
    },
    include: {
      actor: { select: { id: true, name: true, avatarUrl: true, displayId: true } },
    },
  });

  io.to(`user:${input.userId}`).emit('notification:new', notification);
  io.to(`user:${input.userId}`).emit('notification:unread_count', { delta: 1 });
  return notification;
};
