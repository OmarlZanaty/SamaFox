import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { intParam } from '../utils/http';
import { isValidPositiveAmount, MAX_COINS_BALANCE } from '../utils/coins';
import { evaluateVip } from '../services/vip.service';
import { invalidateBanCache } from '../utils/banGuard';
import { kickBannedUser } from '../services/socket.service';

const toBigInt = (v: unknown) => BigInt(v as number | string | bigint);

const serializeUserWithCoins = (user: any) => ({
  ...user,
  coinsBalance: user.coinsBalance?.toString?.() ?? '0',
});

const serializeTx = (tx: any) => ({
  ...tx,
  amountCoins: tx.amountCoins?.toString?.() ?? '0',
  user: tx.user ? serializeUserWithCoins(tx.user) : tx.user,
});

export const getAllUsers = async (_req: Request, res: Response) => {
  try {
    const users = await prisma.user.findMany({
      select: {
        id: true,
        name: true,
        email: true,
        phone: true,
        avatarUrl: true,
        level: true,
        xp: true,
        coinsBalance: true,
        vipLevel: true,
        isAdmin: true,
        createdAt: true,
        _count: { select: { followers: true, following: true, ownedRooms: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    return res.json({ users: users.map(serializeUserWithCoins) });
  } catch {
    return res.status(500).json({ message: 'Failed to fetch users' });
  }
};

export const addCoins = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });

    const amt = Number(req.body.amount);
    if (!isValidPositiveAmount(amt)) return res.status(400).json({ message: 'Invalid amount' });
    const amtBig = BigInt(amt);

    const currentUser = await prisma.user.findUnique({ where: { id: userIdNum }, select: { coinsBalance: true } });
    if (!currentUser) return res.status(404).json({ message: 'User not found' });

    if (toBigInt(currentUser.coinsBalance) + amtBig > BigInt(MAX_COINS_BALANCE)) {
      return res.status(400).json({ message: `Max coins limit is ${MAX_COINS_BALANCE}` });
    }

    const user = await prisma.user.update({
      where: { id: userIdNum },
      // Count admin top-ups toward VIP progress (totalRecharge).
      data: {
        coinsBalance: { increment: Number(amtBig) },
        totalRecharge: { increment: Number(amtBig) },
      },
    });

    try {
      await prisma.transaction.create({
        data: { userId: userIdNum, type: 'admin_add', amountCoins: Number(amtBig), status: 'completed' },
      });
    } catch (txErr) {
      console.warn('addCoins transaction log skipped:', txErr);
    }

    // Auto-evaluate VIP level (grants frame/badge + notifies on level-up).
    try { await evaluateVip(userIdNum); } catch (e) { console.warn('evaluateVip failed:', e); }

    return res.json({
      message: 'Coins added successfully',
      user: { id: user.id, name: user.name, coinsBalance: user.coinsBalance.toString() },
    });
  } catch (error) {
    console.error('addCoins error:', error);
    return res.status(500).json({ message: 'Failed to add coins' });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const item = await prisma.item.findUnique({ where: { id } });
    if (!item) return res.status(404).json({ message: 'Product not found' });
    await prisma.item.delete({ where: { id } });
    return res.json({ message: 'Product deleted successfully' });
  } catch (error) {
    console.error('deleteProduct error:', error);
    return res.status(500).json({ message: 'Failed to delete product' });
  }
};

export const removeCoins = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });

    const amt = Number(req.body.amount);
    if (!isValidPositiveAmount(amt)) return res.status(400).json({ message: 'Invalid amount' });
    const amtBig = BigInt(amt);

    const user = await prisma.user.findUnique({ where: { id: userIdNum } });
    if (!user) return res.status(404).json({ message: 'User not found' });

    if (toBigInt(user.coinsBalance) < amtBig) return res.status(400).json({ message: 'Insufficient coins' });

    const updatedUser = await prisma.user.update({
      where: { id: userIdNum },
      data: { coinsBalance: { decrement: Number(amtBig) } },
    });

    try {
      await prisma.transaction.create({
        data: { userId: userIdNum, type: 'admin_remove', amountCoins: -Number(amtBig), status: 'completed' },
      });
    } catch (txErr) {
      console.warn('removeCoins transaction log skipped:', txErr);
    }

    return res.json({
      message: 'Coins removed successfully',
      user: { id: updatedUser.id, name: updatedUser.name, coinsBalance: updatedUser.coinsBalance.toString() },
    });
  } catch (error) {
    console.error('removeCoins error:', error);
    return res.status(500).json({ message: 'Failed to remove coins' });
  }
};

export async function getDashboardStats(_req: Request, res: Response) {
  try {
    const [totalUsers, totalRooms, activeRooms, totalCoins, totalTransactions] = await Promise.all([
      prisma.user.count(),
      prisma.room.count(),
      prisma.room.count({ where: { isActive: true } }),
      prisma.user.aggregate({ _sum: { coinsBalance: true } }),
      prisma.transaction.count(),
    ]);

    const recentUsers = await prisma.user.findMany({
      take: 5,
      orderBy: { createdAt: 'desc' },
      select: { id: true, name: true, avatarUrl: true, createdAt: true },
    });

    const topRooms = await prisma.room.findMany({
      take: 5,
      orderBy: { createdAt: 'desc' },
      select: { id: true, name: true, _count: { select: { members: true } }, owner: { select: { name: true } } },
    });

    return res.json({
      stats: {
        totalUsers,
        totalRooms,
        activeRooms,
        totalCoins: totalCoins._sum.coinsBalance?.toString() ?? '0',
        totalTransactions,
      },
      recentUsers,
      topRooms,
    });
  } catch {
    return res.status(500).json({ message: 'Failed to fetch dashboard stats' });
  }
}

export const getAllTransactions = async (req: Request, res: Response) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const skip = (Number(page) - 1) * Number(limit);

    const [transactions, total] = await Promise.all([
      prisma.transaction.findMany({
        take: Number(limit),
        skip,
        orderBy: { createdAt: 'desc' },
        include: { user: { select: { id: true, name: true, avatarUrl: true, coinsBalance: true } } },
      }),
      prisma.transaction.count(),
    ]);

    return res.json({
      transactions: transactions.map(serializeTx),
      pagination: { page: Number(page), limit: Number(limit), total, totalPages: Math.ceil(total / Number(limit)) },
    });
  } catch {
    return res.status(500).json({ message: 'Failed to fetch transactions' });
  }
};

// Group 11: only super admins control rooms — regular admins cannot close/delete them.
const requireSuper = async (req: Request): Promise<boolean> => {
  const requesterId = (req as any).userId as number | undefined;
  if (!requesterId) return false;
  const u = await (prisma as any).user.findUnique({
    where: { id: requesterId },
    select: { isSuperAdmin: true },
  });
  return Boolean(u?.isSuperAdmin);
};

export const deleteRoom = async (req: Request, res: Response) => {
  try {
    if (!(await requireSuper(req))) {
      return res.status(403).json({ message: 'إغلاق/حذف الغرف متاح للسوبر أدمن فقط' });
    }
    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ message: 'Invalid roomId' });
    await prisma.room.delete({ where: { id: roomIdNum } });
    return res.json({ message: 'Room deleted successfully' });
  } catch (error) {
    console.error('deleteRoom error:', error);
    return res.status(500).json({ message: 'Failed to delete room' });
  }
};

// PATCH /admin/rooms/:roomId/active — super admin closes/reopens a room from
// inside the app (group 11). Closing kicks everyone live.
export const setRoomActive = async (req: Request, res: Response) => {
  try {
    if (!(await requireSuper(req))) {
      return res.status(403).json({ message: 'إغلاق/فتح الغرف متاح للسوبر أدمن فقط' });
    }
    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ message: 'Invalid roomId' });
    const isActive = Boolean(req.body?.isActive);

    const room = await prisma.room.update({ where: { id: roomIdNum }, data: { isActive } });

    if (!isActive) {
      try {
        const { io } = await import('../index');
        const reason = String(req.body?.reason || 'تم إغلاق الغرفة من الإدارة').trim();
        io.to(`room:${roomIdNum}`).emit('room_force_closed', { roomId: roomIdNum, reason });
      } catch (e) {
        console.warn('room_force_closed emit failed:', e);
      }
    }

    return res.json({ message: isActive ? 'Room opened' : 'Room closed', room: { id: room.id, isActive: room.isActive } });
  } catch (error: any) {
    if (error?.code === 'P2025') return res.status(404).json({ message: 'Room not found' });
    console.error('setRoomActive error:', error);
    return res.status(500).json({ message: 'Failed to update room' });
  }
};

// Group 11: role-tiered in-app ban durations (ms).
// Regular admins may only issue short bans; supers go up to permanent.
const ADMIN_BAN_DURATIONS: Record<string, number | null> = {
  '1d': 24 * 60 * 60 * 1000,
  '2d': 2 * 24 * 60 * 60 * 1000,
  '3d': 3 * 24 * 60 * 60 * 1000,
};
const SUPER_BAN_DURATIONS: Record<string, number | null> = {
  // يوم / شهر / أبدي is the set the owner asked a super admin for; 2d/3d/1y
  // stay available so nothing that already worked breaks.
  '1d': 24 * 60 * 60 * 1000,
  '2d': 2 * 24 * 60 * 60 * 1000,
  '3d': 3 * 24 * 60 * 60 * 1000,
  '1m': 30 * 24 * 60 * 60 * 1000,
  '1y': 365 * 24 * 60 * 60 * 1000,
  permanent: null,
};

export const toggleUserBan = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });
    const isBanned = !!req.body.isBanned;
    const reason = typeof req.body.reason === 'string' ? req.body.reason : null;

    const requesterId = (req as any).userId as number | undefined;
    const requester = requesterId
      ? await (prisma as any).user.findUnique({
          where: { id: requesterId },
          select: { isAdmin: true, isSuperAdmin: true },
        })
      : null;
    const isSuper = Boolean(requester?.isSuperAdmin);

    const target = await (prisma as any).user.findUnique({
      where: { id: userIdNum },
      select: { banSource: true, isAdmin: true, isSuperAdmin: true },
    });
    if (!target) return res.status(404).json({ message: 'User not found' });

    // Staff immunity ("ولا احد ياخد اجراء ضده"): platform staff are not a
    // moderation target from inside the app at all. A super admin outranks a
    // plain admin, so he may still act on one; nobody bans a super admin here.
    if (isBanned && target.isSuperAdmin) {
      return res.status(403).json({ message: 'لا يمكن حظر سوبر أدمن من داخل التطبيق' });
    }
    if (isBanned && target.isAdmin && !isSuper) {
      return res.status(403).json({ message: 'لا يمكن اتخاذ إجراء ضد أدمن' });
    }

    // A ban issued from the control panel can only be lifted from the control panel.
    if (!isBanned && target.banSource === 'dashboard') {
      return res.status(403).json({ message: 'This user was banned from the control panel and can only be unbanned there.' });
    }

    let banExpiresAt: Date | null = null;
    if (isBanned) {
      // Group 11: regular admin → 1/2/3 days only; super admin → 3d/1m/1y/permanent.
      const allowed = isSuper ? SUPER_BAN_DURATIONS : ADMIN_BAN_DURATIONS;
      const duration = String(req.body?.duration || (isSuper ? 'permanent' : '1d'));
      if (!(duration in allowed)) {
        return res.status(403).json({
          message: isSuper
            ? 'المدد المتاحة: 3d / 1m / 1y / permanent'
            : 'الأدمن العادي يحظر 1d / 2d / 3d فقط',
        });
      }
      const ms = allowed[duration];
      banExpiresAt = ms == null ? null : new Date(Date.now() + ms);
    }

    await (prisma as any).user.update({
      where: { id: userIdNum },
      data: isBanned
        ? { isBanned: true, bannedAt: new Date(), banReason: reason, banExpiresAt, banSource: 'admin' }
        : { isBanned: false, bannedAt: null, banReason: null, banExpiresAt: null, banSource: null },
    });

    // Take effect now rather than up to a cache TTL later — this covers the
    // unban direction too, so a lifted ban lets them straight back in.
    invalidateBanCache(userIdNum);

    // Kick the user off any live sockets immediately (same as dashboard bans).
    if (isBanned) {
      try {
        await kickBannedUser(userIdNum, reason, banExpiresAt);
      } catch (e) {
        console.warn('user_banned emit failed:', e);
      }
    }

    return res.json({ message: isBanned ? 'User banned successfully' : 'User unbanned successfully' });
  } catch (error) {
    console.error('toggleUserBan error:', error);
    return res.status(500).json({ message: 'Failed to update user ban status' });
  }
};

export const toggleAdminStatus = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });
    const isAdmin = !!req.body.isAdmin;

    const user = await prisma.user.update({ where: { id: userIdNum }, data: { isAdmin } });

    return res.json({
      message: isAdmin ? 'User promoted to admin' : 'Admin privileges removed',
      user: { id: user.id, name: user.name, isAdmin: user.isAdmin },
    });
  } catch (error) {
    console.error('toggleAdminStatus error:', error);
    return res.status(500).json({ message: 'Failed to update admin status' });
  }
};
