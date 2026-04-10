import prisma from '../utils/prisma';
import { Request, Response } from 'express';
import { firstStr } from '../utils/http';
import { io } from '../index';

type AdminReq = Request;

function toCoinsString(v: unknown) {
  if (typeof v === 'bigint') return v.toString();
  if (typeof v === 'number') return String(v);
  return '0';
}

function serializeUser(user: any) {
  return {
    ...user,
    coinsBalance: toCoinsString(user.coinsBalance),
  };
}

function ok(res: Response, data: any) {
  return res.json({ success: true, ...data });
}

function fail(res: Response, status: number, message: string) {
  return res.status(status).json({ success: false, message });
}

function parseIntOr(v: any, def: number) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : def;
}

export const adminDashboardOverview = async (_req: AdminReq, res: Response) => {
  try {
    const [usersCount, roomsCount, agenciesCount, pendingAgencies] = await Promise.all([
      prisma.user.count(),
      prisma.room.count(),
      prisma.chargingAgency.count(),
      prisma.chargingAgency.count({ where: { status: 'pending' } }),
    ]);

    return ok(res, { data: { usersCount, roomsCount, agenciesCount, pendingAgencies } });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListUsers = async (req: AdminReq, res: Response) => {
  try {
    const page = parseIntOr(req.query.page, 1);
    const limit = parseIntOr(req.query.limit, 30);
    const skip = (page - 1) * limit;
    const search = firstStr(req.query.search)?.trim();

    const where: any = search
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
      prisma.user.findMany({ where, orderBy: { createdAt: 'desc' }, skip, take: limit }),
    ]);

    return ok(res, {
      data: users.map(serializeUser),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardBanUser = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid user id');

    const isBanned = !!req.body?.isBanned;
    const reason = typeof req.body?.reason === 'string' ? req.body.reason : null;

    const user = await prisma.user.update({
      where: { id },
      data: {
        isBanned: isBanned as any,
        bannedAt: isBanned ? new Date() : null,
        banReason: isBanned ? reason : null,
      } as any,
      select: { id: true, name: true, isBanned: true, bannedAt: true, banReason: true },
    });

    return ok(res, { data: user });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListRooms = async (_req: AdminReq, res: Response) => {
  try {
    const rooms = await prisma.room.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        owner: { select: { id: true, name: true, avatarUrl: true, email: true } },
      },
    });

    return ok(res, { data: rooms });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListChargingAgencies = async (req: AdminReq, res: Response) => {
  try {
    const status = firstStr(req.query.status as any);

    const agencies = await prisma.chargingAgency.findMany({
      where: status ? { status } : undefined,
      include: { user: { select: { id: true, name: true, avatarUrl: true, email: true } } },
      orderBy: { createdAt: 'desc' },
    });

    return ok(res, { data: agencies });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardUpdateAgencyStatus = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    const status = req.body?.status;

    if (!id || !['approved', 'rejected', 'pending'].includes(status)) {
      return fail(res, 400, 'Invalid id/status');
    }

    const updated = await prisma.chargingAgency.update({ where: { id }, data: { status } });
    return ok(res, { data: updated });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListTransactions = async (req: AdminReq, res: Response) => {
  try {
    const page = parseIntOr(req.query.page, 1);
    const limit = parseIntOr(req.query.limit, 50);
    const userId = req.query.userId ? Number(req.query.userId) : undefined;
    const type = firstStr(req.query.type);
    const where: any = { ...(userId ? { userId } : {}), ...(type ? { type } : {}) };

    const [total, txns] = await Promise.all([
      prisma.transaction.count({ where }),
      prisma.transaction.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: { user: { select: { id: true, name: true } } },
      }),
    ]);

    return ok(res, {
      data: txns.map((t) => ({ ...t, amountCoins: toCoinsString(t.amountCoins) })),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardBroadcast = async (req: AdminReq, res: Response) => {
  try {
    const { title, message } = req.body ?? {};
    if (!title || !message) return fail(res, 400, 'title and message required');

    io.emit('admin_broadcast', { title, message, sentAt: new Date().toISOString() });
    return ok(res, { sent: true });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListTopups = async (req: AdminReq, res: Response) => {
  try {
    const status = firstStr(req.query.status) ?? 'pending';
    const items = await prisma.agencyTopupRequest.findMany({
      where: { status },
      orderBy: { createdAt: 'desc' },
      include: { agency: { select: { id: true, agencyName: true, balanceCoins: true, userId: true } } },
    });

    return ok(res, {
      data: items.map((i) => ({
        ...i,
        amount: toCoinsString((i as any).amount),
        agency: i.agency ? { ...i.agency, balanceCoins: toCoinsString((i.agency as any).balanceCoins) } : null,
      })),
    });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardReviewTopup = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    const status = req.body?.status;
    if (!id || !['approved', 'rejected'].includes(status)) return fail(res, 400, 'Invalid id/status');

    const result = await prisma.$transaction(async (tx) => {
      const request = await tx.agencyTopupRequest.findUnique({ where: { id } });
      if (!request) throw new Error('Topup request not found');
      if (request.status !== 'pending') throw new Error('Already processed');

      if (status === 'approved') {
        await tx.chargingAgency.update({
          where: { id: request.agencyId },
          data: {
            balanceCoins: { increment: request.amount as any },
            totalTopupCoins: { increment: request.amount as any },
          },
        });
      }

      return tx.agencyTopupRequest.update({
        where: { id },
        data: { status, reviewedBy: req.userId, reviewedAt: new Date() },
      });
    });

    return ok(res, { data: { ...result, amount: toCoinsString((result as any).amount) } });
  } catch (e: any) {
    return fail(res, 400, e?.message ?? 'Server error');
  }
};

export const adminDashboardAnalytics = async (_req: AdminReq, res: Response) => {
  try {
    const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const [topGifters, topRooms, pendingReports, giftTotal] = await Promise.all([
      prisma.giftLog.groupBy({
        by: ['senderId'],
        _sum: { coinsSpent: true },
        orderBy: { _sum: { coinsSpent: 'desc' } },
        take: 5,
        where: { createdAt: { gte: weekAgo } },
      }),
      prisma.roomMessage.groupBy({ by: ['roomId'], _count: { id: true }, orderBy: { _count: { id: 'desc' } }, take: 5 }),
      prisma.report.count({ where: { status: 'pending' } }),
      prisma.giftLog.aggregate({ _sum: { coinsSpent: true }, where: { createdAt: { gte: today } } }),
    ]);

    return ok(res, {
      data: {
        topGifters,
        topRooms,
        pendingReports,
        dailyGiftCoins: toCoinsString(giftTotal._sum.coinsSpent ?? 0),
      },
    });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListReports = async (req: AdminReq, res: Response) => {
  try {
    const status = firstStr(req.query.status) ?? 'pending';
    const reports = await prisma.report.findMany({
      where: { status },
      orderBy: { createdAt: 'desc' },
      include: {
        reporter: { select: { id: true, name: true } },
        reportedUser: { select: { id: true, name: true } },
        room: { select: { id: true, name: true } },
      },
    });

    return ok(res, { data: reports });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardResolveReport = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    const status = req.body?.status;
    if (!id || !['resolved', 'dismissed'].includes(status)) return fail(res, 400, 'Invalid id/status');

    const updated = await prisma.report.update({ where: { id }, data: { status } });
    return ok(res, { data: updated });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardForceCloseRoom = async (req: AdminReq, res: Response) => {
  try {
    const roomId = Number(req.params.id);
    if (!roomId) return fail(res, 400, 'Invalid room id');

    io.to(`room:${roomId}`).emit('room_force_closed', {
      roomId,
      reason: req.body?.reason ?? 'Closed by admin',
    });

    await prisma.room.update({ where: { id: roomId }, data: { isActive: false } });

    return ok(res, { closed: true, roomId });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardListQuests = async (_req: AdminReq, res: Response) => {
  try {
    const quests = await prisma.dailyQuest.findMany({ orderBy: { createdAt: 'desc' } });
    return ok(res, { data: quests });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardCreateQuest = async (req: AdminReq, res: Response) => {
  try {
    const { name, description, metric, target, rewardCoins } = req.body ?? {};
    if (!name || !metric || !target || !rewardCoins) return fail(res, 400, 'Missing fields');

    const quest = await prisma.dailyQuest.create({
      data: {
        name: String(name),
        description: String(description ?? ''),
        metric: String(metric),
        target: Number(target),
        rewardCoins: Number(rewardCoins),
      },
    });

    return ok(res, { data: quest });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardUpdateQuest = async (req: AdminReq, res: Response) => {
  try {
    const id = String(req.params.id);
    const { name, description, metric, target, rewardCoins } = req.body ?? {};

    const quest = await prisma.dailyQuest.update({
      where: { id },
      data: {
        ...(name != null ? { name: String(name) } : {}),
        ...(description != null ? { description: String(description) } : {}),
        ...(metric != null ? { metric: String(metric) } : {}),
        ...(target != null ? { target: Number(target) } : {}),
        ...(rewardCoins != null ? { rewardCoins: Number(rewardCoins) } : {}),
      },
    });

    return ok(res, { data: quest });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardDeleteQuest = async (req: AdminReq, res: Response) => {
  try {
    await prisma.dailyQuest.delete({ where: { id: String(req.params.id) } });
    return ok(res, { deleted: true });
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};

export const adminDashboardLeaderboard = async (req: AdminReq, res: Response) => {
  try {
    const type = firstStr(req.query.type) ?? 'coins';

    if (type === 'coins') {
      const users = await prisma.user.findMany({
        orderBy: { coinsBalance: 'desc' },
        take: 20,
        select: { id: true, name: true, avatarUrl: true, coinsBalance: true, level: true },
      });
      return ok(res, { data: users.map((u) => ({ ...u, coinsBalance: toCoinsString(u.coinsBalance) })) });
    }

    if (type === 'gifts') {
      const senders = await prisma.giftLog.groupBy({
        by: ['senderId'],
        _sum: { coinsSpent: true },
        orderBy: { _sum: { coinsSpent: 'desc' } },
        take: 20,
      });
      return ok(res, { data: senders.map((s) => ({ ...s, _sum: { coinsSpent: toCoinsString(s._sum.coinsSpent ?? 0) } })) });
    }

    if (type === 'rooms') {
      const rooms = await prisma.room.findMany({
        orderBy: { xp: 'desc' },
        take: 20,
        select: { id: true, name: true, xp: true, level: true, owner: { select: { name: true } } },
      });
      return ok(res, { data: rooms });
    }

    return fail(res, 400, 'Invalid type');
  } catch (e: any) {
    return fail(res, 500, e?.message ?? 'Server error');
  }
};
