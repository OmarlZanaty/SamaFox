import { Request, Response } from 'express';
import prisma from '../utils/prisma';

const parsePage = (v: unknown, d = 1) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : d;
};

const parseLimit = (v: unknown, d = 20) => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? Math.min(100, Math.floor(n)) : d;
};

const fail = (res: Response, status: number, message: string) => res.status(status).json({ success: false, message });
const ok = (res: Response, data: any) => res.json({ success: true, ...data });

const serialize = (obj: any): any => {
  if (typeof obj === 'bigint') return obj.toString();
  if (Array.isArray(obj)) return obj.map(serialize);
  if (obj && typeof obj === 'object') {
    return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, serialize(v)]));
  }
  return obj;
};

const serializeUser = (user: any) => ({
  ...user,
  coinsBalance: user?.coinsBalance != null ? String(user.coinsBalance) : '0',
});

export const adminDashboardOverview = async (_req: Request, res: Response) => {
  try {
    const [usersCount, roomsCount, agenciesCount, pendingAgencies] = await Promise.all([
      prisma.user.count(),
      prisma.room.count(),
      prisma.chargingAgency.count(),
      prisma.chargingAgency.count({ where: { status: 'pending' } }),
    ]);
    return ok(res, { data: { usersCount, roomsCount, agenciesCount, pendingAgencies } });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardListUsers = async (req: Request, res: Response) => {
  try {
    const page = parsePage(req.query.page, 1);
    const limit = parseLimit(req.query.limit, 30);
    const skip = (page - 1) * limit;
    const search = String(req.query.search || '').trim();

    const where = search
      ? {
          OR: [
            { name: { contains: search } },
            { email: { contains: search } },
            { phone: { contains: search } },
          ],
        }
      : undefined;

    const [total, users] = await Promise.all([
      prisma.user.count({ where }),
      prisma.user.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        select: {
          id: true,
          name: true,
          email: true,
          phone: true,
          avatarUrl: true,
          isAdmin: true,
          coinsBalance: true,
          isBanned: true,
          bannedAt: true,
          banReason: true,
          createdAt: true,
          updatedAt: true,
        },
      }),
    ]);

    return ok(res, {
      data: users.map(serializeUser),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardBanUser = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid user id');

    const isBanned = Boolean(req.body?.isBanned);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : null;

    if (isBanned && !reason) return fail(res, 400, 'reason is required when banning user');

    const bannedAt = isBanned ? new Date().toISOString() : null;

    // NOTE: Prisma client in production may lag behind schema generation; use SQL to avoid TS type breakage.
    await prisma.$executeRawUnsafe(
      'UPDATE users SET isBanned = ?, bannedAt = ?, banReason = ? WHERE id = ?',
      isBanned ? 1 : 0,
      bannedAt,
      isBanned ? reason : null,
      id,
    );

    return ok(res, { data: { id, isBanned, bannedAt, banReason: isBanned ? reason : null } });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardTransactions = async (req: Request, res: Response) => {
  try {
    const page = parsePage(req.query.page, 1);
    const limit = parseLimit(req.query.limit, 20);
    const skip = (page - 1) * limit;
    const userId = req.query.userId ? Number(req.query.userId) : undefined;
    const type = req.query.type ? String(req.query.type) : undefined;

    const where: any = {};
    if (userId) where.userId = userId;
    if (type) where.type = type;

    const [total, data] = await Promise.all([
      prisma.transaction.count({ where }),
      prisma.transaction.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
        include: { user: { select: { id: true, name: true, email: true, avatarUrl: true } } },
      }),
    ]);

    return ok(res, {
      data: data.map((tx) => ({ ...tx, amountCoins: tx.amountCoins.toString() })),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardBroadcast = async (req: Request, res: Response) => {
  try {
    const title = String(req.body?.title || '').trim();
    const message = String(req.body?.message || '').trim();
    if (!title || !message) return fail(res, 400, 'title and message are required');

    const sentAt = new Date().toISOString();
    const payload = { title, message, sentAt };
    const { io } = await import('../index');
    io.emit('admin_broadcast', payload);

    return ok(res, { data: payload });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardTopupRequests = async (req: Request, res: Response) => {
  try {
    const status = req.query.status ? String(req.query.status) : undefined;
    const data = await prisma.agencyTopupRequest.findMany({
      where: status ? { status } : undefined,
      orderBy: { createdAt: 'desc' },
      include: { agency: { select: { id: true, agencyName: true, userId: true, balanceCoins: true } } },
    });
    return ok(res, { data: serialize(data) });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardReviewTopupRequest = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const status = String(req.body?.status || '');
    if (!id || !['approved', 'rejected'].includes(status)) return fail(res, 400, 'Invalid payload');
    const adminId = req.userId!;

    const result = await prisma.$transaction(async (tx) => {
      const topup = await tx.agencyTopupRequest.findUnique({ where: { id } });
      if (!topup) return { ok: false as const, status: 404, message: 'Topup request not found' };
      if (topup.status !== 'pending') return { ok: false as const, status: 409, message: 'Already reviewed' };

      if (status === 'approved') {
        await tx.chargingAgency.update({
          where: { id: topup.agencyId },
          data: {
            balanceCoins: { increment: topup.amount },
            totalTopupCoins: { increment: topup.amount },
          },
        });
      }

      const updated = await tx.agencyTopupRequest.update({
        where: { id },
        data: { status, reviewedAt: new Date(), reviewedBy: adminId },
      });

      return { ok: true as const, data: updated };
    });

    if (!result.ok) return fail(res, result.status, result.message);
    return ok(res, { data: serialize(result.data) });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardAnalytics = async (_req: Request, res: Response) => {
  try {
    const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    const [topGifters, topRoomsRaw, pendingReports, todayGiftCoins] = await Promise.all([
      prisma.giftLog.groupBy({
        by: ['senderId'],
        where: { createdAt: { gte: since } },
        _sum: { coinsSpent: true },
        orderBy: { _sum: { coinsSpent: 'desc' } },
        take: 5,
      }),
      prisma.roomMessage.groupBy({
        by: ['roomId'],
        where: { timestamp: { gte: since } },
        _count: { roomId: true },
        orderBy: { _count: { roomId: 'desc' } },
        take: 5,
      }),
      prisma.report.count({ where: { status: 'pending' } }),
      prisma.giftLog.aggregate({ where: { createdAt: { gte: startOfToday } }, _sum: { coinsSpent: true } }),
    ]);

    const senderIds = topGifters.map((r) => r.senderId);
    const roomIds = topRoomsRaw.map((r) => r.roomId);

    const [users, rooms] = await Promise.all([
      senderIds.length
        ? prisma.user.findMany({ where: { id: { in: senderIds } }, select: { id: true, name: true, avatarUrl: true } })
        : [],
      roomIds.length ? prisma.room.findMany({ where: { id: { in: roomIds } }, select: { id: true, name: true } }) : [],
    ]);

    return ok(res, {
      data: {
        topGifters: topGifters.map((g) => ({
          senderId: g.senderId,
          user: users.find((u) => u.id === g.senderId) || null,
          coins: ((g._sum?.coinsSpent as any) || 0).toString(),
        })),
        topRooms: topRoomsRaw.map((r) => ({
          roomId: r.roomId,
          room: rooms.find((x) => x.id === r.roomId) || null,
          messagesCount: (r._count as any)?.roomId || 0,
        })),
        pendingReports,
        todayGiftCoins: (todayGiftCoins._sum.coinsSpent || 0).toString(),
      },
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardReports = async (req: Request, res: Response) => {
  try {
    const status = req.query.status ? String(req.query.status) : undefined;
    const data = await prisma.report.findMany({
      where: status ? { status } : undefined,
      orderBy: { createdAt: 'desc' },
      include: {
        reporter: { select: { id: true, name: true, email: true, avatarUrl: true } },
        reportedUser: { select: { id: true, name: true, email: true, avatarUrl: true } },
        room: { select: { id: true, name: true } },
      },
    });
    return ok(res, { data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardUpdateReport = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const status = String(req.body?.status || '');
    if (!id || !['resolved', 'dismissed'].includes(status)) return fail(res, 400, 'Invalid payload');

    const data = await prisma.report.update({ where: { id }, data: { status } });
    return ok(res, { data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardListRooms = async (_req: Request, res: Response) => {
  try {
    const data = await prisma.room.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        owner: { select: { id: true, name: true, avatarUrl: true, email: true } },
      },
    });
    return ok(res, { data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardForceCloseRoom = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const reason = String(req.body?.reason || '').trim();
    if (!id || !reason) return fail(res, 400, 'Invalid payload');

    const room = await prisma.room.update({ where: { id }, data: { isActive: false } });
    const { io } = await import('../index');
    io.to(`room:${id}`).emit('room_force_closed', { roomId: id, reason });

    return ok(res, { data: room });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardGetQuests = async (_req: Request, res: Response) => {
  try {
    const data = await prisma.dailyQuest.findMany({ orderBy: { createdAt: 'desc' } });
    return ok(res, { data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardCreateQuest = async (req: Request, res: Response) => {
  try {
    const { name, description, metric, target, rewardCoins } = req.body;
    if (!name || !description || !metric || !target || !rewardCoins) return fail(res, 400, 'Missing required fields');

    const data = await prisma.dailyQuest.create({
      data: {
        name: String(name),
        description: String(description),
        metric: String(metric),
        target: Number(target),
        rewardCoins: Number(rewardCoins),
      },
    });
    return ok(res, { data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardDeleteQuest = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    await prisma.dailyQuest.delete({ where: { id } });
    return ok(res, { message: 'Quest deleted' });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardLeaderboard = async (req: Request, res: Response) => {
  try {
    const type = String(req.query.type || 'coins');
    if (!['coins', 'gifts', 'rooms'].includes(type)) return fail(res, 400, 'Invalid leaderboard type');

    if (type === 'coins') {
      const data = await prisma.user.findMany({
        take: 20,
        orderBy: { coinsBalance: 'desc' },
        select: { id: true, name: true, avatarUrl: true, coinsBalance: true },
      });
      return ok(res, { data: data.map(serializeUser) });
    }

    if (type === 'gifts') {
      const rows = await prisma.giftLog.groupBy({
        by: ['senderId'],
        _sum: { coinsSpent: true },
        orderBy: { _sum: { coinsSpent: 'desc' } },
        take: 20,
      });
      const users = await prisma.user.findMany({
        where: { id: { in: rows.map((r) => r.senderId) } },
        select: { id: true, name: true, avatarUrl: true },
      });

      return ok(res, {
        data: rows.map((r) => ({
          senderId: r.senderId,
          user: users.find((u) => u.id === r.senderId) || null,
          coinsSpent: (r._sum.coinsSpent || 0).toString(),
        })),
      });
    }

    const data = await prisma.room.findMany({
      take: 20,
      orderBy: { xp: 'desc' },
      select: {
        id: true,
        name: true,
        xp: true,
        owner: { select: { name: true } },
      },
    });
    return ok(res, { data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardListChargingAgencies = async (req: Request, res: Response) => {
  try {
    const status = req.query.status ? String(req.query.status) : undefined;
    const agencies = await prisma.chargingAgency.findMany({
      where: status ? { status } : undefined,
      include: { user: true },
      orderBy: { createdAt: 'desc' },
    });
    return ok(res, { data: serialize(agencies) });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminDashboardUpdateAgencyStatus = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const status = req.body?.status;
    if (!['approved', 'rejected', 'pending'].includes(status)) return fail(res, 400, 'Invalid status');

    const updated = await prisma.chargingAgency.update({ where: { id }, data: { status } });
    return ok(res, { data: serialize(updated) });
  } catch {
    return fail(res, 500, 'Server error');
  }
};
