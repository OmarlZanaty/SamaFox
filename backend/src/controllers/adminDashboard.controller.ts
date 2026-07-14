import { Request, Response } from 'express';

export type AdminReq = Request & { userId?: number };
import prisma from '../utils/prisma';

const db = prisma as any;

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

    // Prisma query (Postgres-safe). The old raw SQL used `?` placeholders and
    // unquoted camelCase columns, which PostgreSQL rejects -> 500.
    const numeric = /^\d+$/.test(search) ? Number(search) : null;
    const where: any = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { email: { contains: search, mode: 'insensitive' } },
            { phone: { contains: search } },
            ...(numeric != null ? [{ displayId: numeric }, { id: numeric }] : []),
          ],
        }
      : {};

    const [total, users] = await Promise.all([
      prisma.user.count({ where }),
      prisma.user.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit,
        select: {
          id: true,
          displayId: true,
          name: true,
          email: true,
          phone: true,
          gender: true,
          avatarUrl: true,
          isAdmin: true,
          isBanned: true,
          bannedAt: true,
          banReason: true,
          coinsBalance: true,
          vipLevel: true,
          createdAt: true,
          updatedAt: true,
        },
      }),
    ]);

    return ok(res, {
      data: users.map((u) => ({ ...u, coinsBalance: String(u.coinsBalance ?? 0) })),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
  } catch (e) {
    console.error('adminDashboardListUsers error:', e);
    return fail(res, 500, 'Server error');
  }
};

export const adminChangeUserDisplayId = async (req: AdminReq, res: Response) => {
  try {
    const userId = Number(req.params.id);
    const newDisplayId = Number(req.body?.newDisplayId);

    if (!userId) return res.status(400).json({ success: false, message: 'Invalid user id' });
    if (!newDisplayId || newDisplayId < 100000 || newDisplayId > 999999) {
      return res.status(400).json({ success: false, message: 'displayId must be a 6-digit number (100000-999999)' });
    }

    const taken = await prisma.user.findFirst({
      where: { displayId: newDisplayId, NOT: { id: userId } },
    });
    if (taken) return res.status(400).json({ success: false, message: 'ID already in use' });

    const updated = await prisma.user.update({
      where: { id: userId },
      data: { displayId: newDisplayId },
      select: { id: true, name: true, displayId: true },
    });

    return res.json({ success: true, data: updated });
  } catch {
    return res.status(500).json({ success: false, message: 'Server error' });
  }
};

export const adminUpdateUserProfile = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid user id');

    const data: any = {};
    if (req.body?.name != null) {
      const name = String(req.body.name).trim();
      if (!name) return fail(res, 400, 'name cannot be empty');
      data.name = name;
    }
    if (req.body?.gender != null) {
      const gender = String(req.body.gender).trim().toLowerCase();
      if (!['male', 'female', 'other'].includes(gender)) return fail(res, 400, 'gender must be male/female/other');
      data.gender = gender;
    }
    if (req.body?.nameLocked != null) {
      data.nameLocked = Boolean(req.body.nameLocked);
    }
    if (Object.keys(data).length === 0) return fail(res, 400, 'nothing to update');

    const updated = await (prisma as any).user.update({
      where: { id },
      data,
      select: { id: true, name: true, gender: true, nameLocked: true },
    });
    return ok(res, { data: updated });
  } catch (e: any) {
    if (e?.code === 'P2025') return fail(res, 404, 'User not found');
    return fail(res, 500, 'Server error');
  }
};

// Duration codes -> milliseconds. 'permanent' => no expiry.
const BAN_DURATIONS: Record<string, number | null> = {
  '1d': 24 * 60 * 60 * 1000,
  '3d': 3 * 24 * 60 * 60 * 1000,
  '1m': 30 * 24 * 60 * 60 * 1000,
  '1y': 365 * 24 * 60 * 60 * 1000,
  permanent: null,
};

export const adminDashboardBanUser = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid user id');

    const isBanned = Boolean(req.body?.isBanned);

    if (!isBanned) {
      // Unban from the dashboard: always allowed (this is the only place a
      // dashboard-sourced ban can be lifted).
      const updated = await (prisma as any).user.update({
        where: { id },
        data: { isBanned: false, bannedAt: null, banReason: null, banExpiresAt: null, banSource: null },
        select: { id: true, isBanned: true },
      });
      return ok(res, { data: updated });
    }

    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
    if (!reason) return fail(res, 400, 'reason is required when banning user');

    const duration = String(req.body?.duration || 'permanent');
    if (!(duration in BAN_DURATIONS)) return fail(res, 400, 'Invalid duration');
    const ms = BAN_DURATIONS[duration];
    const now = new Date();
    const banExpiresAt = ms == null ? null : new Date(now.getTime() + ms);

    const updated = await (prisma as any).user.update({
      where: { id },
      data: {
        isBanned: true,
        bannedAt: now,
        banReason: reason,
        banExpiresAt,
        banSource: 'dashboard',
      },
      select: { id: true, isBanned: true, bannedAt: true, banReason: true, banExpiresAt: true, banSource: true },
    });

    // Kick the user off any live sockets immediately.
    try {
      const { io } = await import('../index');
      io.emit('user_banned', { userId: id, reason, banExpiresAt });
    } catch (e) {
      console.warn('user_banned emit failed:', e);
    }

    return ok(res, { data: serialize(updated) });
  } catch (e: any) {
    if (e?.code === 'P2025') return fail(res, 404, 'User not found');
    console.error('adminDashboardBanUser error:', e);
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

    const result = await db.$transaction(async (tx: any) => {
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
      prisma.giftTransaction.groupBy({
        by: ['senderId'],
        where: { createdAt: { gte: since } },
        _sum: { totalCoins: true },
        orderBy: { _sum: { totalCoins: 'desc' } },
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
      prisma.giftTransaction.aggregate({ where: { createdAt: { gte: startOfToday } }, _sum: { totalCoins: true } }),
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
          coins: ((g._sum?.totalCoins as any) || 0).toString(),
        })),
        topRooms: topRoomsRaw.map((r) => ({
          roomId: r.roomId,
          room: rooms.find((x) => x.id === r.roomId) || null,
          messagesCount: (r._count as any)?.roomId || 0,
        })),
        pendingReports,
        todayGiftCoins: (todayGiftCoins._sum.totalCoins || 0).toString(),
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

export const adminDashboardListRooms = async (req: Request, res: Response) => {
  try {
    const search = String(req.query.search || '').trim();
    const numeric = /^\d+$/.test(search) ? Number(search) : null;
    const where: any = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { owner: { name: { contains: search, mode: 'insensitive' } } },
            ...(numeric != null
              ? [{ id: numeric }, { ownerId: numeric }, { owner: { displayId: numeric } }]
              : []),
          ],
        }
      : {};

    const data = await (prisma as any).room.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        name: true,
        type: true,
        maxSeats: true,
        coverImageUrl: true,
        isActive: true,
        isLocked: true,
        accessCode: true,
        nameLocked: true,
        createdAt: true,
        owner: { select: { id: true, displayId: true, name: true, avatarUrl: true, email: true, nameLocked: true } },
      },
    });

    // Never ship the PIN in the list payload — it is fetched per-room via /rooms/:id/details.
    return ok(res, {
      data: data.map((r: any) => {
        const { accessCode, ...rest } = r;
        return { ...rest, hasAccessCode: Boolean(accessCode) };
      }),
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// PATCH /admin-dashboard/rooms/:id — edit name, lock renaming, close/reopen (group 6)
export const adminDashboardUpdateRoom = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid room id');

    const data: any = {};
    if (req.body?.name != null) {
      const name = String(req.body.name).trim();
      if (!name) return fail(res, 400, 'name cannot be empty');
      data.name = name;
    }
    if (req.body?.nameLocked != null) data.nameLocked = Boolean(req.body.nameLocked);
    if (req.body?.isActive != null) data.isActive = Boolean(req.body.isActive);
    if (Object.keys(data).length === 0) return fail(res, 400, 'nothing to update');

    const updated = await (prisma as any).room.update({
      where: { id },
      data,
      select: { id: true, name: true, nameLocked: true, isActive: true },
    });

    try {
      const { io } = await import('../index');
      if (data.isActive === false) {
        const reason = String(req.body?.reason || 'تم إغلاق الغرفة من الإدارة').trim();
        io.to(`room:${id}`).emit('room_force_closed', { roomId: id, reason });
      }
      if (data.name) {
        io.to(`room:${id}`).emit('room_updated', { roomId: id, name: data.name });
      }
    } catch (e) {
      console.warn('adminDashboardUpdateRoom emit failed:', e);
    }

    return ok(res, { data: updated });
  } catch (e: any) {
    if (e?.code === 'P2025') return fail(res, 404, 'Room not found');
    return fail(res, 500, 'Server error');
  }
};

// GET /admin-dashboard/rooms/:id/details — who is inside right now + the PIN
// for locked rooms (group 6). "Inside" = sockets currently joined to room:<id>.
export const adminDashboardRoomDetails = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid room id');

    const room = await (prisma as any).room.findUnique({
      where: { id },
      select: {
        id: true,
        name: true,
        type: true,
        isActive: true,
        isLocked: true,
        accessCode: true,
        nameLocked: true,
        createdAt: true,
        owner: { select: { id: true, displayId: true, name: true, nameLocked: true } },
      },
    });
    if (!room) return fail(res, 404, 'Room not found');

    const userIds = new Set<number>();
    try {
      const { io } = await import('../index');
      const socketIds = io.sockets.adapter.rooms.get(`room:${id}`) ?? new Set<string>();
      for (const sid of socketIds) {
        const s: any = io.sockets.sockets.get(sid);
        if (s?.userId) userIds.add(Number(s.userId));
      }
    } catch (e) {
      console.warn('adminDashboardRoomDetails presence lookup failed:', e);
    }

    const members = userIds.size
      ? await prisma.user.findMany({
          where: { id: { in: [...userIds] } },
          select: { id: true, displayId: true, name: true, avatarUrl: true },
        })
      : [];

    return ok(res, {
      data: {
        ...room,
        accessCode: room.isLocked ? room.accessCode : null,
        membersInside: members,
        membersCount: members.length,
      },
    });
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
  } catch (error: any) {
    if (error?.code === 'P2025') {
      return fail(res, 404, 'Room not found');
    }
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
      const data = await prisma.$queryRawUnsafe<Array<{ id: number; name: string; avatarUrl: string | null; coinsBalance: string }>>(
        `SELECT id, name, avatarUrl, CAST(coinsBalance AS TEXT) as coinsBalance
         FROM users
         ORDER BY coinsBalance DESC
         LIMIT 20`,
      );
      return ok(res, { data });
    }

    if (type === 'gifts') {
      const rows = await prisma.giftTransaction.groupBy({
        by: ['senderId'],
        _sum: { totalCoins: true },
        orderBy: { _sum: { totalCoins: 'desc' } },
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
          coinsSpent: (r._sum.totalCoins || 0).toString(),
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
    const type = req.query.type ? String(req.query.type) : undefined; // CHARGING | HOSTING
    const search = String(req.query.search || '').trim();
    const numeric = /^\d+$/.test(search) ? Number(search) : null;

    const where: any = {
      ...(status ? { status } : {}),
      ...(type ? { type } : {}),
      ...(search
        ? {
            OR: [
              { agencyName: { contains: search, mode: 'insensitive' } },
              { phoneNumber: { contains: search } },
              { user: { name: { contains: search, mode: 'insensitive' } } },
              ...(numeric != null
                ? [{ id: numeric }, { userId: numeric }, { user: { displayId: numeric } }]
                : []),
            ],
          }
        : {}),
    };

    const agencies = await prisma.chargingAgency.findMany({
      where,
      include: { user: true },
      orderBy: { createdAt: 'desc' },
    });
    const withDollars = await Promise.all(
      agencies.map(async (a: any) => ({
        ...serialize(a),
        dollars: await computeDollarsFromCoins(a.earnedCoins ?? 0n),
      })),
    );
    return ok(res, { data: withDollars });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// PATCH /admin-dashboard/agencies/:id — edit agency name + lock renaming (group 7)
export const adminDashboardUpdateAgency = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid agency id');

    const data: any = {};
    if (req.body?.agencyName != null) {
      const agencyName = String(req.body.agencyName).trim();
      if (!agencyName) return fail(res, 400, 'agencyName cannot be empty');
      data.agencyName = agencyName;
    }
    if (req.body?.nameLocked != null) data.nameLocked = Boolean(req.body.nameLocked);
    if (Object.keys(data).length === 0) return fail(res, 400, 'nothing to update');

    const updated = await (prisma as any).chargingAgency.update({
      where: { id },
      data,
      select: { id: true, agencyName: true, nameLocked: true },
    });
    return ok(res, { data: updated });
  } catch (e: any) {
    if (e?.code === 'P2025') return fail(res, 404, 'Agency not found');
    return fail(res, 500, 'Server error');
  }
};

// GET /admin-dashboard/agencies/:id/charges — every top-up this agency sent:
// who was charged, how many coins, by which member, when (group 7 complaints).
export const adminDashboardAgencyCharges = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid agency id');
    const page = parsePage(req.query.page, 1);
    const limit = parseLimit(req.query.limit, 50);

    const where = { type: 'AGENCY_TOPUP', agencyId: id } as any;
    const [total, rows] = await Promise.all([
      (prisma as any).transaction.count({ where }),
      (prisma as any).transaction.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: { user: { select: { id: true, displayId: true, name: true } } },
      }),
    ]);

    // Resolve sender names in one query (senderId is a plain column, no relation).
    const senderIds = [...new Set(rows.map((r: any) => r.senderId).filter(Boolean))] as number[];
    const senders = senderIds.length
      ? await prisma.user.findMany({
          where: { id: { in: senderIds } },
          select: { id: true, displayId: true, name: true },
        })
      : [];
    const senderById = new Map(senders.map((s) => [s.id, s]));

    return ok(res, {
      data: rows.map((r: any) => ({
        id: r.id,
        amountCoins: r.amountCoins,
        createdAt: r.createdAt,
        recipient: r.user,
        sender: r.senderId ? (senderById.get(r.senderId) ?? { id: r.senderId }) : null,
      })),
      pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
    });
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


export const adminListAgencyRequests = async (req: AdminReq, res: Response) => {
  try {
    const { type, status = 'pending' } = req.query;
    const requests = await db.agencyRequest.findMany({
      where: {
        ...(type ? { type: String(type) } : {}),
        status: String(status),
      },
      include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
      orderBy: { createdAt: 'desc' },
    });

    return ok(res, { data: requests });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminReviewAgencyRequest = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    const { status } = req.body as { status?: string };
    if (!['approved', 'rejected'].includes(String(status))) return fail(res, 400, 'Invalid status');
    if (!req.userId) return fail(res, 401, 'Unauthorized');

    const result = await db.$transaction(async (tx: any) => {
      const request = await tx.agencyRequest.findUnique({ where: { id } });
      if (!request || request.status !== 'pending') {
        return { ok: false as const, status: 404, message: 'Not found or already processed' };
      }

      await tx.agencyRequest.update({
        where: { id },
        data: { status, reviewedBy: req.userId, reviewedAt: new Date() },
      });

      if (status === 'approved') {
        const agency = await tx.chargingAgency.create({
          data: {
            userId: request.userId,
            agencyName: request.agencyName,
            phoneNumber: request.contactInfo || '-',
            agencyImageUrl: request.imageUrl || '',
            idFrontUrl: request.imageUrl || '',
            idBackUrl: request.imageUrl || '',
            type: request.type,
            logoUrl: request.imageUrl,
            contactInfo: request.contactInfo,
            status: 'approved',
          },
        });

        await tx.agencyMember.create({
          data: { agencyId: agency.id, userId: request.userId, role: 'OWNER' },
        });

        return { ok: true as const, data: serialize(agency) };
      }

      return { ok: true as const, data: null };
    });

    if (!result.ok) return fail(res, result.status, result.message);
    return ok(res, { data: result.data });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

export const adminTopupAgency = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    const { amount } = req.body as { amount?: number | string };
    const numericAmount = Number(amount);

    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      return fail(res, 400, 'Positive amount required');
    }

    const agency = await db.chargingAgency.update({
      where: { id },
      data: {
        balanceCoins: { increment: numericAmount },
        totalTopupCoins: { increment: numericAmount },
      },
    });

    return ok(res, { data: { balanceCoins: String(agency.balanceCoins) } });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// ── Target tiers (coins earned -> dollar payout). Admin-managed. ──
// Dollars for a given earned-coins amount = coins * (dollars/coins) of the
// highest tier whose coins threshold <= earned. If no tier qualifies, $0.
export const computeDollarsFromCoins = async (earnedCoins: bigint | number): Promise<number> => {
  const earned = typeof earnedCoins === 'bigint' ? earnedCoins : BigInt(Math.floor(Number(earnedCoins) || 0));
  const tiers = await (prisma as any).targetTier.findMany({ orderBy: { coins: 'asc' } });
  let ratio = 0; // dollars per coin
  for (const t of tiers) {
    const tc = BigInt(t.coins);
    if (tc > 0n && earned >= tc) {
      ratio = Number(t.dollars) / Number(tc);
    }
  }
  return Math.round(Number(earned) * ratio * 100) / 100;
};

export const adminListTargetTiers = async (_req: AdminReq, res: Response) => {
  try {
    const tiers = await (prisma as any).targetTier.findMany({ orderBy: { coins: 'asc' } });
    return ok(res, { data: serialize(tiers) });
  } catch (e) {
    console.error('adminListTargetTiers error:', e);
    return fail(res, 500, 'Server error');
  }
};

export const adminCreateTargetTier = async (req: AdminReq, res: Response) => {
  try {
    const coins = Number(req.body?.coins);
    const dollars = Number(req.body?.dollars);
    if (!Number.isFinite(coins) || coins <= 0) return fail(res, 400, 'coins must be > 0');
    if (!Number.isFinite(dollars) || dollars < 0) return fail(res, 400, 'dollars must be >= 0');
    const tier = await (prisma as any).targetTier.create({
      data: { coins: BigInt(Math.floor(coins)), dollars },
    });
    return ok(res, { data: serialize(tier) });
  } catch (e) {
    console.error('adminCreateTargetTier error:', e);
    return fail(res, 500, 'Server error');
  }
};

export const adminUpdateTargetTier = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid id');
    const data: any = {};
    if (req.body?.coins != null) {
      const coins = Number(req.body.coins);
      if (!Number.isFinite(coins) || coins <= 0) return fail(res, 400, 'coins must be > 0');
      data.coins = BigInt(Math.floor(coins));
    }
    if (req.body?.dollars != null) {
      const dollars = Number(req.body.dollars);
      if (!Number.isFinite(dollars) || dollars < 0) return fail(res, 400, 'dollars must be >= 0');
      data.dollars = dollars;
    }
    if (Object.keys(data).length === 0) return fail(res, 400, 'nothing to update');
    const tier = await (prisma as any).targetTier.update({ where: { id }, data });
    return ok(res, { data: serialize(tier) });
  } catch (e: any) {
    if (e?.code === 'P2025') return fail(res, 404, 'Tier not found');
    return fail(res, 500, 'Server error');
  }
};

export const adminDeleteTargetTier = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid id');
    await (prisma as any).targetTier.delete({ where: { id } });
    return ok(res, { message: 'Tier deleted' });
  } catch (e: any) {
    if (e?.code === 'P2025') return fail(res, 404, 'Tier not found');
    return fail(res, 500, 'Server error');
  }
};

export const adminSetAgencyTarget = async (req: AdminReq, res: Response) => {
  try {
    const id = Number(req.params.id);
    const { targetCoins } = req.body as { targetCoins?: number | string };
    const numericTarget = Number(targetCoins);
    if (!Number.isFinite(numericTarget) || numericTarget < 0) return fail(res, 400, 'targetCoins must be >= 0');

    const agency = await db.chargingAgency.update({ where: { id }, data: { targetCoins: BigInt(Math.floor(numericTarget)) } });
    return ok(res, { data: { targetCoins: agency.targetCoins.toString() } });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// Gift CRUD on this dashboard controller is superseded by the canonical
// /api/v1/admin/gifts module. These thin wrappers remain only for the
// existing admin dashboard UI; new clients should target the dedicated
// admin gift routes which support format/tier/animation metadata.

export const adminListGifts = async (_req: AdminReq, res: Response) => {
  const gifts = await prisma.gift.findMany({ orderBy: [{ sortOrder: 'asc' }, { createdAt: 'desc' }] });
  return res.json({ success: true, data: gifts });
};

export const adminCreateGift = async (req: AdminReq, res: Response) => {
  const { nameAr, iconUrl, animationUrl, coinCost, sortOrder, format, tier, name } = req.body;
  if (!nameAr || !iconUrl || coinCost == null) {
    return res.status(400).json({ success: false, message: 'nameAr, iconUrl, coinCost required' });
  }

  const gift = await prisma.gift.create({
    data: {
      name: String(name ?? nameAr),
      nameAr: String(nameAr),
      iconUrl: String(iconUrl),
      animationUrl: animationUrl ?? null,
      coinCost: Number(coinCost),
      sortOrder: Number(sortOrder ?? 0),
      format: (format ?? 'SVG_CSS') as any,
      tier: (tier ?? 'SMALL') as any,
      category: 'admin',
    },
  });

  return res.status(201).json({ success: true, data: gift });
};

export const adminUpdateGift = async (req: AdminReq, res: Response) => {
  const id = String(req.params.id);
  const { nameAr, iconUrl, animationUrl, coinCost, sortOrder, isActive, name, tier, format } = req.body;

  const gift = await prisma.gift.update({
    where: { id },
    data: {
      ...(nameAr !== undefined && { nameAr: String(nameAr) }),
      ...(name !== undefined && { name: String(name) }),
      ...(iconUrl !== undefined && { iconUrl: String(iconUrl) }),
      ...(animationUrl !== undefined && { animationUrl }),
      ...(coinCost !== undefined && { coinCost: Number(coinCost) }),
      ...(sortOrder !== undefined && { sortOrder: Number(sortOrder) }),
      ...(isActive !== undefined && { isActive: Boolean(isActive) }),
      ...(tier !== undefined && { tier: tier as any }),
      ...(format !== undefined && { format: format as any }),
    },
  });

  return res.json({ success: true, data: gift });
};

export const adminDeleteGift = async (req: AdminReq, res: Response) => {
  const id = String(req.params.id);
  try {
    await prisma.gift.delete({ where: { id } });
    return res.json({ success: true, message: 'Gift deleted' });
  } catch {
    await prisma.gift.update({
      where: { id },
      data: { isActive: false },
    });
    return res.json({ success: true, message: 'Gift deactivated (used in history)' });
  }
};

export const adminDashboardListGifts = adminListGifts;
export const adminDashboardCreateGift = adminCreateGift;
export const adminDashboardUpdateGift = adminUpdateGift;
export const adminDashboardDeleteGift = adminDeleteGift;

// ── Agency members (app owner can inspect and remove anyone from any agency) ──
export const adminListAgencyMembers = async (req: AdminReq, res: Response) => {
  try {
    const agencyId = Number(req.params.id);
    if (!agencyId) return fail(res, 400, 'Invalid agency id');

    const members = await db.agencyMember.findMany({
      where: { agencyId },
      include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
      orderBy: { joinedAt: 'asc' },
    });

    // #24: surface each member's target (earned since joining, excl self-gifts)
    // + goal + remaining so the admin can hold people accountable from the panel.
    const withTargets = await Promise.all(
      members.map(async (m: any) => {
        const earned = await db.giftTransaction.aggregate({
          where: { recipientId: m.userId, senderId: { not: m.userId }, createdAt: { gte: m.joinedAt } },
          _sum: { totalCoins: true },
        });
        const earnedCoins = Number(earned._sum.totalCoins ?? 0);
        const goal = Number(m.targetGoalCoins ?? 0n);
        return {
          ...m,
          targetGoalCoins: goal,
          earnedCoins,
          remainingCoins: goal > 0 ? Math.max(0, goal - earnedCoins) : 0,
        };
      }),
    );

    return ok(res, { data: serialize(withTargets) });
  } catch (e) {
    console.error('adminListAgencyMembers error:', e);
    return fail(res, 500, 'Server error');
  }
};

export const adminRemoveAgencyMember = async (req: AdminReq, res: Response) => {
  try {
    const memberId = Number(req.params.memberId);
    if (!memberId) return fail(res, 400, 'Invalid member id');

    const member = await db.agencyMember.findUnique({
      where: { id: memberId },
      include: { agency: { select: { agencyName: true } } },
    });
    if (!member) return fail(res, 404, 'Member not found');
    if (member.role === 'OWNER') return fail(res, 400, 'Cannot remove the agency owner');

    await db.agencyMember.delete({ where: { id: memberId } });

    try {
      const { createNotification } = await import('../services/notification.service');
      await createNotification({
        userId: member.userId,
        type: 'AGENCY_REMOVED',
        title: 'تمت إزالتك من الوكالة',
        body: `قامت إدارة التطبيق بإزالتك من وكالة ${member.agency?.agencyName ?? ''}`,
        data: { agencyId: member.agencyId },
      });
    } catch (e) {
      console.warn('admin agency removal notification failed:', e);
    }

    return ok(res, { message: 'Member removed' });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// ── VIP level configuration (badge image + seat frame per level) ──
export const adminListVipLevels = async (_req: AdminReq, res: Response) => {
  try {
    const levels = await prisma.vipLevelConfig.findMany({ orderBy: { level: 'asc' } });
    return res.json({ success: true, data: levels });
  } catch (e) {
    console.error('adminListVipLevels error:', e);
    return res.status(500).json({ success: false, message: 'Failed to list VIP levels' });
  }
};

export const adminUpsertVipLevel = async (req: AdminReq, res: Response) => {
  try {
    const level = Number(req.body?.level);
    if (!level || level < 1 || level > 100) {
      return res.status(400).json({ success: false, message: 'level must be 1-100' });
    }
    const data = {
      name: req.body?.name != null ? String(req.body.name) : undefined,
      threshold: req.body?.threshold != null ? Number(req.body.threshold) : undefined,
      badgeUrl: req.body?.badgeUrl != null ? String(req.body.badgeUrl) : undefined,
      frameItemId: req.body?.frameItemId != null ? String(req.body.frameItemId) : undefined,
    };
    const saved = await prisma.vipLevelConfig.upsert({
      where: { level },
      update: data,
      create: { level, ...data },
    });
    return res.json({ success: true, data: saved });
  } catch (e) {
    console.error('adminUpsertVipLevel error:', e);
    return res.status(500).json({ success: false, message: 'Failed to save VIP level' });
  }
};

// ============================================================
// ADMIN ROLE MANAGEMENT (#22, #23)
// Only super-admins may appoint/revoke admins & super-admins.
// ============================================================

// GET /admin-dashboard/me — the current dashboard user's own role, so the UI
// can show/hide the super-admin-only controls.
export const adminDashboardMe = async (req: AdminReq, res: Response) => {
  try {
    if (!req.userId) return fail(res, 401, 'Unauthorized');
    const me = await db.user.findUnique({
      where: { id: req.userId },
      select: { id: true, name: true, displayId: true, isAdmin: true, isSuperAdmin: true },
    });
    if (!me) return fail(res, 401, 'Unauthorized');
    return ok(res, { data: me });
  } catch (e) {
    console.error('adminDashboardMe error:', e);
    return fail(res, 500, 'Server error');
  }
};

// GET /admin-dashboard/admins — list every admin / super-admin.
export const adminListAdmins = async (_req: AdminReq, res: Response) => {
  try {
    const admins = await db.user.findMany({
      where: { OR: [{ isAdmin: true }, { isSuperAdmin: true }] },
      select: { id: true, name: true, displayId: true, avatarUrl: true, isAdmin: true, isSuperAdmin: true, createdAt: true },
      orderBy: [{ isSuperAdmin: 'desc' }, { id: 'asc' }],
    });
    return ok(res, { data: admins });
  } catch (e) {
    console.error('adminListAdmins error:', e);
    return fail(res, 500, 'Server error');
  }
};

// Resolve a target user from a param that may be an internal id or a public displayId.
const resolveTargetUser = async (raw: string) => {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  // Prefer displayId (what the owner types), fall back to internal id.
  return (
    (await db.user.findFirst({ where: { displayId: n }, select: { id: true, name: true, isAdmin: true, isSuperAdmin: true } })) ||
    (await db.user.findUnique({ where: { id: n }, select: { id: true, name: true, isAdmin: true, isSuperAdmin: true } }))
  );
};

// POST /admin-dashboard/admins/:userId/grant — make a user an admin (super-admin only).
export const adminGrantAdmin = async (req: AdminReq, res: Response) => {
  try {
    const target = await resolveTargetUser(String(req.params.userId));
    if (!target) return fail(res, 404, 'User not found');
    await db.user.update({ where: { id: target.id }, data: { isAdmin: true } });
    return ok(res, { data: { id: target.id, isAdmin: true } });
  } catch (e) {
    console.error('adminGrantAdmin error:', e);
    return fail(res, 500, 'Server error');
  }
};

// POST /admin-dashboard/admins/:userId/revoke — remove admin (and super) rights.
export const adminRevokeAdmin = async (req: AdminReq, res: Response) => {
  try {
    const target = await resolveTargetUser(String(req.params.userId));
    if (!target) return fail(res, 404, 'User not found');
    if (target.id === req.userId) return fail(res, 400, 'You cannot revoke your own admin access');
    // Never allow removing the last super-admin (lockout guard).
    if (target.isSuperAdmin) {
      const superCount = await db.user.count({ where: { isSuperAdmin: true } });
      if (superCount <= 1) return fail(res, 400, 'Cannot revoke the last super-admin');
    }
    await db.user.update({ where: { id: target.id }, data: { isAdmin: false, isSuperAdmin: false } });
    return ok(res, { data: { id: target.id, isAdmin: false, isSuperAdmin: false } });
  } catch (e) {
    console.error('adminRevokeAdmin error:', e);
    return fail(res, 500, 'Server error');
  }
};

// PATCH /admin-dashboard/admins/:userId/super  { value: boolean } — promote/demote super-admin.
export const adminSetSuperAdmin = async (req: AdminReq, res: Response) => {
  try {
    const value = Boolean((req.body as any)?.value);
    const target = await resolveTargetUser(String(req.params.userId));
    if (!target) return fail(res, 404, 'User not found');
    if (!value) {
      // Demoting a super-admin: block self-demotion and last-super-admin lockout.
      if (target.id === req.userId) return fail(res, 400, 'You cannot demote yourself');
      const superCount = await db.user.count({ where: { isSuperAdmin: true } });
      if (target.isSuperAdmin && superCount <= 1) return fail(res, 400, 'Cannot demote the last super-admin');
    }
    // A super-admin is always also an admin.
    await db.user.update({
      where: { id: target.id },
      data: value ? { isSuperAdmin: true, isAdmin: true } : { isSuperAdmin: false },
    });
    return ok(res, { data: { id: target.id, isSuperAdmin: value } });
  } catch (e) {
    console.error('adminSetSuperAdmin error:', e);
    return fail(res, 500, 'Server error');
  }
};
