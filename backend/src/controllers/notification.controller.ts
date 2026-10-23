import { Response } from 'express';
import { AuthReq } from '../types';
import { prisma } from '../lib/prisma';

export const AGENCY_NOTIFICATION_TYPES = [
  'AGENCY_COMMISSION', 'AGENCY_ASSIGNED', 'AGENCY_BRANCH_ADDED', 'AGENCY_EXIT_FEE', 'AGENCY_INVITE',
  'AGENCY_INVITE_RESPONSE', 'AGENCY_MEMBER_LEFT', 'AGENCY_OWNERSHIP', 'AGENCY_REMOVED', 'AGENCY_TARGET_SET',
  'AGENCY_TOPUP', 'TARGET_ADJUSTED', 'TARGET_SOLD', 'agency_charge_reward',
];

const pendingInviteIds = async (userId: number, now: Date) => new Set(
  (await prisma.agencyInvite.findMany({
    where: { inviteeId: userId, status: 'pending', OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
    select: { id: true },
  })).map(invite => invite.id),
);

const notificationInviteId = (data: unknown): number | undefined => {
  if (!data || typeof data !== 'object' || !('inviteId' in data)) return undefined;
  return typeof data.inviteId === 'number' ? data.inviteId : undefined;
};

export const listNotifications = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId!;
    const page = Math.max(1, Number(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 30));
    // SPEC52 #31 — ?category=agency: the room bell's list (commission,
    // agency and target notices). Always scoped to the caller's own rows, so
    // nobody sees another account's financial notices.
    const where: any = { userId };
    if (String(req.query.category ?? '') === 'agency') where.type = { in: AGENCY_NOTIFICATION_TYPES };

    const [total, unreadCount, notifications] = await Promise.all([
      prisma.notification.count({ where }),
      prisma.notification.count({ where: { ...where, isRead: false } }),
      prisma.notification.findMany({
        where,
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
  } catch (err) {
    console.error('[notification.listNotifications]', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
};

export const markNotificationRead = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId!;
    const id = Number(req.params.id);

    // 2026-10-23 — unread keeps the invite's accept/reject buttons available.
    const now = new Date();
    const pendingIds = await pendingInviteIds(userId, now);
    if (pendingIds.size) {
      const notification = await prisma.notification.findFirst({
        where: { id, userId, isRead: false, type: 'AGENCY_INVITE' },
        select: { data: true },
      });
      const inviteId = notificationInviteId(notification?.data);
      if (inviteId !== undefined && pendingIds.has(inviteId)) return res.json({ success: true });
    }

    await prisma.notification.updateMany({
      where: { id, userId, isRead: false },
      data: { isRead: true, readAt: now },
    });

    return res.json({ success: true });
  } catch (err) {
    console.error('[notification.markNotificationRead]', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
};

export const markAllNotificationsRead = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId!;
    const where: any = { userId, isRead: false };
    if (String(req.query.category ?? '') === 'agency') where.type = { in: AGENCY_NOTIFICATION_TYPES };

    // 2026-10-23 — read-all must also preserve actionable invite buttons.
    const now = new Date();
    const pendingIds = await pendingInviteIds(userId, now);
    if (pendingIds.size) {
      const notifications = await prisma.notification.findMany({
        where: { userId, isRead: false, type: 'AGENCY_INVITE' },
        select: { id: true, data: true },
      });
      where.id = { notIn: notifications.filter(notification => {
        const inviteId = notificationInviteId(notification.data);
        return inviteId !== undefined && pendingIds.has(inviteId);
      }).map(notification => notification.id) };
    }

    await prisma.notification.updateMany({
      where,
      data: { isRead: true, readAt: now },
    });

    return res.json({ success: true });
  } catch (err) {
    console.error('[notification.markAllNotificationsRead]', err);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
};
