import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { io } from '../index';

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
          createdAt: true,
          updatedAt: true,
        },
      }),
    ]);

    return ok(res, {
      data: serialize(users),
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

    const isBanned = Boolean(req.body.isBanned);
    const banReason = typeof req.body.banReason === 'string' ? req.body.banReason.trim() : null;
    const bannedAt = isBanned ? new Date().toISOString() : null;

    await prisma.$executeRawUnsafe(
      'UPDATE users SET isBanned = ?, bannedAt = ?, banReason = ? WHERE id = ?',
      isBanned ? 1 : 0,
      bannedAt,
      isBanned ? banReason : null,
      id,
    );

    return ok(res, { data: { id, isBanned, bannedAt, banReason: isBanned ? banReason : null } });
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
  const title = String(req.body?.title || '').trim();
  const message = String(req.body?.message || '').trim();
  if (!title || !message) return fail(res, 400, 'title and message are required');

  const payload = { title, message, createdAt: new Date().toISOString() };
  io.emit('admin_broadcast', payload);
  return ok(res, { data: payload });
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
            balanceCoins: { increment: Number(BigInt(topup.amount)) },
            totalTopupCoins: { increment: Number(BigInt(topup.amount)) },
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

    const [topGifters, topRoomsRaw, pendingReports, dailyGiftCoinsRaw] = await Promise.all([
      prisma.giftLog.groupBy({ by: ['senderId'], where: { createdAt: { gte: since } }, _sum: { coinsSpent: true }, orderBy: { _sum: { coinsSpent: 'desc' } }, take: 10 }),
      prisma.giftLog.groupBy({ by: ['roomId'], where: { roomId: { not: null }, createdAt: { gte: since } }, _sum: { coinsSpent: true }, orderBy: { _sum: { coinsSpent: 'desc' } }, take: 10 }),
      prisma.report.count({ where: { status: 'pending' } }),
      prisma.$queryRaw<Array<{ day: string; total: number | bigint }>>`
        SELECT date(createdAt) as day, SUM(coinsSpent) as total
        FROM gift_logs
        WHERE createdAt >= ${since.toISOString()}
        GROUP BY date(createdAt)
        ORDER BY day ASC
      `,
    ]);

    const senderIds = topGifters.map((r) => r.senderId);
    const roomIds = topRoomsRaw.map((r) => r.roomId).filter(Boolean) as number[];
    const [users, rooms] = await Promise.all([
      senderIds.length ? prisma.user.findMany({ where: { id: { in: senderIds } }, select: { id: true, name: true, avatarUrl: true } }) : [],
      roomIds.length ? prisma.room.findMany({ where: { id: { in: roomIds } }, select: { id: true, name: true } }) : [],
    ]);

    return ok(res, {
      data: {
        topGifters: topGifters.map((g) => ({ ...g, user: users.find((u) => u.id === g.senderId) || null, coins: (g._sum.coinsSpent || 0).toString() })),
        topRooms: topRoomsRaw.map((r) => ({ ...r, room: rooms.find((x) => x.id === r.roomId) || null, coins: (r._sum.coinsSpent || 0).toString() })),
        pendingReports,
        dailyGiftCoins: dailyGiftCoinsRaw.map((d) => ({ day: d.day, total: BigInt(d.total || 0).toString() })),
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
        room: { select: { id: true, name: true, isActive: true } },
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
    if (!id || !status) return fail(res, 400, 'Invalid payload');

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
    io.to(`room:${id}`).emit('admin_force_close', { roomId: id, reason, closedAt: new Date().toISOString() });
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
      data: { name: String(name), description: String(description), metric: String(metric), target: Number(target), rewardCoins: Number(rewardCoins) },
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
      return ok(res, { data: serialize(data) });
    }

    if (type === 'gifts') {
      const rows = await prisma.giftLog.groupBy({ by: ['senderId'], _sum: { coinsSpent: true }, orderBy: { _sum: { coinsSpent: 'desc' } }, take: 20 });
      const users = await prisma.user.findMany({ where: { id: { in: rows.map((r) => r.senderId) } }, select: { id: true, name: true, avatarUrl: true } });
      return ok(res, { data: rows.map((r) => ({ user: users.find((u) => u.id === r.senderId) || null, total: (r._sum.coinsSpent || 0).toString() })) });
    }

    const data = await prisma.room.findMany({
      take: 20,
      orderBy: { members: { _count: 'desc' } },
      select: { id: true, name: true, isActive: true, _count: { select: { members: true } } },
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
