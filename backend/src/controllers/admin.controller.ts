import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { intParam } from '../utils/http';

const toCoinsString = (v: unknown) => (typeof v === 'bigint' ? v.toString() : String(v ?? 0));

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
        isBanned: true as any,
        bannedAt: true as any,
        banReason: true as any,
        _count: { select: { followers: true, following: true, ownedRooms: true } },
      } as any,
      orderBy: { createdAt: 'desc' },
    });

    return res.json({ success: true, users: users.map((u) => ({ ...u, coinsBalance: toCoinsString(u.coinsBalance) })) });
  } catch {
    return res.status(500).json({ success: false, message: 'Failed to fetch users' });
  }
};

export const addCoins = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const amt = Number(req.body.amount);
    if (!Number.isFinite(amt) || amt <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });

    const amountBig = BigInt(Math.trunc(amt));

    const user = await prisma.user.update({
      where: { id: userIdNum },
      data: { coinsBalance: { increment: Number(amountBig) } as any },
    });

    await prisma.transaction.create({
      data: {
        userId: userIdNum,
        type: 'admin_add',
        amountCoins: Number(amountBig) as any,
        status: 'completed',
      },
    });

    return res.json({
      success: true,
      message: 'Coins added successfully',
      user: { id: user.id, name: user.name, coinsBalance: toCoinsString(user.coinsBalance) },
    });
  } catch (error) {
    console.error('addCoins error:', error);
    return res.status(500).json({ success: false, message: 'Failed to add coins' });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const item = await prisma.item.findUnique({ where: { id } });
    if (!item) return res.status(404).json({ success: false, message: 'Product not found' });

    await prisma.item.delete({ where: { id } });
    return res.json({ success: true, message: 'Product deleted successfully' });
  } catch (error) {
    console.error('deleteProduct error:', error);
    return res.status(500).json({ success: false, message: 'Failed to delete product' });
  }
};

export const removeCoins = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const amt = Number(req.body.amount);
    if (!Number.isFinite(amt) || amt <= 0) return res.status(400).json({ success: false, message: 'Invalid amount' });

    const amountBig = BigInt(Math.trunc(amt));

    const user = await prisma.user.findUnique({ where: { id: userIdNum }, select: { id: true, name: true, coinsBalance: true } });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    if (BigInt(user.coinsBalance as any) < amountBig) {
      return res.status(400).json({ success: false, message: 'Insufficient coins' });
    }

    const updatedUser = await prisma.user.update({
      where: { id: userIdNum },
      data: { coinsBalance: { decrement: Number(amountBig) } as any },
    });

    await prisma.transaction.create({
      data: {
        userId: userIdNum,
        type: 'admin_remove',
        amountCoins: Number(-amountBig) as any,
        status: 'completed',
      },
    });

    return res.json({
      success: true,
      message: 'Coins removed successfully',
      user: { id: updatedUser.id, name: updatedUser.name, coinsBalance: toCoinsString(updatedUser.coinsBalance) },
    });
  } catch (error) {
    console.error('removeCoins error:', error);
    return res.status(500).json({ success: false, message: 'Failed to remove coins' });
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
      success: true,
      stats: {
        totalUsers,
        totalRooms,
        activeRooms,
        totalCoins: toCoinsString(totalCoins._sum.coinsBalance ?? 0),
        totalTransactions,
      },
      recentUsers,
      topRooms,
    });
  } catch {
    return res.status(500).json({ success: false, message: 'Failed to fetch dashboard stats' });
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
        include: { user: { select: { id: true, name: true, avatarUrl: true } } },
      }),
      prisma.transaction.count(),
    ]);

    return res.json({
      success: true,
      transactions: transactions.map((t) => ({ ...t, amountCoins: toCoinsString(t.amountCoins) })),
      pagination: { page: Number(page), limit: Number(limit), total, totalPages: Math.ceil(total / Number(limit)) },
    });
  } catch {
    return res.status(500).json({ success: false, message: 'Failed to fetch transactions' });
  }
};

export const deleteRoom = async (req: Request, res: Response) => {
  try {
    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ success: false, message: 'Invalid roomId' });

    await prisma.room.delete({ where: { id: roomIdNum } });
    return res.json({ success: true, message: 'Room deleted successfully' });
  } catch (error) {
    console.error('deleteRoom error:', error);
    return res.status(500).json({ success: false, message: 'Failed to delete room' });
  }
};

export const toggleUserBan = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const isBanned = !!req.body.isBanned;
    const reason = typeof req.body.reason === 'string' ? req.body.reason : null;

    const user = await prisma.user.update({
      where: { id: userIdNum },
      data: {
        isBanned: isBanned as any,
        bannedAt: isBanned ? new Date() : null,
        banReason: isBanned ? reason : null,
      } as any,
      select: { id: true, name: true, isBanned: true, bannedAt: true, banReason: true } as any,
    });

    return res.json({
      success: true,
      message: isBanned ? 'User banned successfully' : 'User unbanned successfully',
      user,
    });
  } catch (error) {
    console.error('toggleUserBan error:', error);
    return res.status(500).json({ success: false, message: 'Failed to update user ban status' });
  }
};

export const toggleAdminStatus = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const isAdmin = !!req.body.isAdmin;

    const user = await prisma.user.update({ where: { id: userIdNum }, data: { isAdmin } });

    return res.json({
      success: true,
      message: isAdmin ? 'User promoted to admin' : 'Admin privileges removed',
      user: { id: user.id, name: user.name, isAdmin: user.isAdmin },
    });
  } catch (error) {
    console.error('toggleAdminStatus error:', error);
    return res.status(500).json({ success: false, message: 'Failed to update admin status' });
  }
};
