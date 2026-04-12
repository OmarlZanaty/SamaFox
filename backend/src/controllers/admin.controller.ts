import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { intParam } from '../utils/http';
import { isValidPositiveAmount, MAX_COINS_BALANCE } from '../utils/coins';

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
      data: { coinsBalance: { increment: Number(amtBig) } },
    });

    try {
      await prisma.transaction.create({
        data: { userId: userIdNum, type: 'admin_add', amountCoins: Number(amtBig), status: 'completed' },
      });
    } catch (txErr) {
      console.warn('addCoins transaction log skipped:', txErr);
    }

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

export const deleteRoom = async (req: Request, res: Response) => {
  try {
    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ message: 'Invalid roomId' });
    await prisma.room.delete({ where: { id: roomIdNum } });
    return res.json({ message: 'Room deleted successfully' });
  } catch (error) {
    console.error('deleteRoom error:', error);
    return res.status(500).json({ message: 'Failed to delete room' });
  }
};

export const toggleUserBan = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });
    const isBanned = !!req.body.isBanned;
    const reason = typeof req.body.reason === 'string' ? req.body.reason : null;

    await prisma.$executeRawUnsafe(
      `UPDATE users SET isBanned = ?, bannedAt = ?, banReason = ? WHERE id = ?`,
      isBanned ? 1 : 0,
      isBanned ? new Date().toISOString() : null,
      isBanned ? reason : null,
      userIdNum,
    );

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
