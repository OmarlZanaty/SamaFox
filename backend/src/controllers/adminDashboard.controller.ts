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
    const where: any = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { email: { contains: search, mode: 'insensitive' } },
            { phone: { contains: search } },
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
          avatarUrl: true,
          isAdmin: true,
          isBanned: true,
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

export const adminDashboardBanUser = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    if (!id) return fail(res, 400, 'Invalid user id');

    const isBanned = Boolean(req.body?.isBanned);
    const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : null;

    if (isBanned && !reason) return fail(res, 400, 'reason is required when banning user');

    const bannedAt = isBanned ? new Date().toISOString() : null;

    // NOTE: Prisma client in production may lag behind schema generation; use SQL to avoid TS type breakage.
    try {
      await prisma.$executeRawUnsafe(
        'UPDATE users SET isBanned = ?, bannedAt = ?, banReason = ? WHERE id = ?',
        isBanned ? 1 : 0,
        bannedAt,
        isBanned ? reason : null,
        id,
      );
    } catch (banError: any) {
      const message = String(banError?.message || '');
      const missingBanColumns =
        message.includes('no such column') ||
        message.includes('Unknown column') ||
        message.includes('isBanned') ||
        message.includes('bannedAt') ||
        message.includes('banReason');
      if (missingBanColumns) {
        return fail(res, 409, 'User ban fields are missing in DB. Run latest migrations.');
      }
      throw banError;
    }

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
  const { nameAr, iconUrl, animationUrl, coinCost, sortOrder, isActive, name } = req.body;

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
