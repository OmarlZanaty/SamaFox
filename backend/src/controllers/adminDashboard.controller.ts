import prisma from '../utils/prisma';
import { Request, Response } from 'express';
import { firstStr } from '../utils/http';

type AdminReq = Request;

/* =============================
   Helpers
============================= */

function serializeUser(user: any) {
  return {
    ...user,
    coinsBalance: user.coinsBalance?.toString() ?? "0",
  };
}

async function requireAdminDashboard(req: AdminReq) {
  const userId = req.userId;
  if (!userId) throw { status: 401, message: 'Unauthorized' };

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, isAdmin: true }
  });

  if (!user || !user.isAdmin)
    throw { status: 403, message: 'Admin only (Dashboard)' };
}

function ok(res: Response, data: any) {
  return res.json({ success: true, ...data });
}

function fail(res: Response, status: number, message: string) {
  return res.status(status).json({ success: false, message });
}

function parseIntOr(v: any, def: number) {
  const n = Number(v);
  return Number.isFinite(n) ? n : def;
}

/* =============================
   Admin Dashboard Controllers
============================= */

/** GET /api/v1/admin-dashboard/overview */
export const adminDashboardOverview = async (req: AdminReq, res: Response) => {
  try {
    await requireAdminDashboard(req);

    const [
      usersCount,
      roomsCount,
      agenciesCount,
      pendingAgencies
    ] = await Promise.all([
      prisma.user.count(),
      prisma.room.count(),
      prisma.chargingAgency.count(),
      prisma.chargingAgency.count({ where: { status: 'pending' } })
    ]);

    return ok(res, {
      data: {
        usersCount,
        roomsCount,
        agenciesCount,
        pendingAgencies
      }
    });

  } catch (e: any) {
    return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
  }
};

/** GET /api/v1/admin-dashboard/users */
export const adminDashboardListUsers = async (req: AdminReq, res: Response) => {
  try {
    await requireAdminDashboard(req);

    const page  = parseIntOr(req.query.page, 1);
    const limit = parseIntOr(req.query.limit, 30);
    const skip  = (page - 1) * limit;

    const [total, users] = await Promise.all([
      prisma.user.count(),
      prisma.user.findMany({
        select: {
          id: true,
          email: true,
          phone: true,
          name: true,
          avatarUrl: true,
          isAdmin: true,
          createdAt: true,
          updatedAt: true
        },
        orderBy: { createdAt: 'desc' },
        skip,
        take: limit
      })
    ]);

    return ok(res, {
      data: users.map(serializeUser),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit)
      }
    });

  } catch (e: any) {
    return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
  }
};

/** GET /api/v1/admin-dashboard/rooms */
export const adminDashboardListRooms = async (req: AdminReq, res: Response) => {
  try {
    await requireAdminDashboard(req);

    const rooms = await prisma.room.findMany({
      orderBy: { createdAt: 'desc' },
      include: { owner: true }
    });

    return ok(res, { data: rooms });

  } catch (e: any) {
    return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
  }
};

/** GET /api/v1/admin-dashboard/charging-agencies */
export const adminDashboardListChargingAgencies = async (req: AdminReq, res: Response) => {
  try {
    await requireAdminDashboard(req);

    const status = firstStr(req.query.status as any);

    const agencies = await prisma.chargingAgency.findMany({
      where: status ? { status } : undefined,
      include: { user: true },
      orderBy: { createdAt: 'desc' }
    });

    return ok(res, { data: agencies });

  } catch (e: any) {
    return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
  }
};

/** PATCH /api/v1/admin-dashboard/charging-agencies/:id/status */
export const adminDashboardUpdateAgencyStatus = async (req: AdminReq, res: Response) => {
  try {
    await requireAdminDashboard(req);

    const id     = Number(req.params.id);
    const status = req.body?.status;

    if (!['approved', 'rejected', 'pending'].includes(status))
      return fail(res, 400, 'Invalid status');

    const updated = await prisma.chargingAgency.update({
      where: { id },
      data: { status }
    });

    return ok(res, { data: updated });

  } catch (e: any) {
    return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
  }
};
