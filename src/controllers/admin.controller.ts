import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { intParam, firstStr } from '../utils/http';

// Get all users (admin only)
export const getAllUsers = async (req: Request, res: Response) => {
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
        _count: {
          select: {
            followers: true,
            following: true,
            ownedRooms: true
          }
        }
      },
      orderBy: {
        createdAt: 'desc'
      }
    });

    res.json({ users });
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch users' });
  }
};

// Add coins to user
export const addCoins = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });

    const amt = Number(req.body.amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      return res.status(400).json({ message: 'Invalid amount' });
    }

    const user = await prisma.user.update({
      where: { id: userIdNum },
      data: { coinsBalance: { increment: amt } },
    });

    await prisma.transaction.create({
      data: {
        userId: userIdNum,
        type: 'admin_add',
        amountCoins: amt,
        status: 'completed',
      },
    });

    return res.json({
      message: 'Coins added successfully',
      user: { id: user.id, name: user.name, coinsBalance: user.coinsBalance },
    });
  } catch (error) {
    console.error('addCoins error:', error);
    return res.status(500).json({ message: 'Failed to add coins' });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id); // ⚠️ your ID is string

    const item = await prisma.item.findUnique({
      where: { id }
    });

    if (!item) {
      return res.status(404).json({ message: 'Product not found' });
    }

    await prisma.item.delete({
      where: { id }
    });

    return res.json({ message: 'Product deleted successfully' });

  } catch (error) {
    console.error('deleteProduct error:', error);
    return res.status(500).json({ message: 'Failed to delete product' });
  }
};


// Remove coins from user
export const removeCoins = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });

    const amt = Number(req.body.amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      return res.status(400).json({ message: 'Invalid amount' });
    }

    const user = await prisma.user.findUnique({ where: { id: userIdNum } });
    if (!user) return res.status(404).json({ message: 'User not found' });

    if (user.coinsBalance < amt) {
      return res.status(400).json({ message: 'Insufficient coins' });
    }

    const updatedUser = await prisma.user.update({
      where: { id: userIdNum },
      data: { coinsBalance: { decrement: amt } },
    });

    await prisma.transaction.create({
      data: {
        userId: userIdNum,
        type: 'admin_remove',
        amountCoins: -amt,
        status: 'completed',
      },
    });

    return res.json({
      message: 'Coins removed successfully',
      user: { id: updatedUser.id, name: updatedUser.name, coinsBalance: updatedUser.coinsBalance },
    });
  } catch (error) {
    console.error('removeCoins error:', error);
    return res.status(500).json({ message: 'Failed to remove coins' });
  }
};

// Get dashboard statistics
export async function getDashboardStats(req: Request, res: Response) {
    try {
    const [
      totalUsers,
      totalRooms,
      activeRooms,
      totalCoins,
      totalTransactions
    ] = await Promise.all([
      prisma.user.count(),
      prisma.room.count(),
      prisma.room.count({ where: { isActive: true } }),
      prisma.user.aggregate({ _sum: { coinsBalance: true } }),
      prisma.transaction.count()
    ]);

    // Get recent users
    const recentUsers = await prisma.user.findMany({
      take: 5,
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        name: true,
        avatarUrl: true,
        createdAt: true
      }
    });

    // Get top rooms
    const topRooms = await prisma.room.findMany({
      take: 5,
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        name: true,
        _count: { select: { members: true } },
        owner: {
          select: {
            name: true
          }
        }
      }
    });

    res.json({
      stats: {
        totalUsers,
        totalRooms,
        activeRooms,
        totalCoins: totalCoins._sum.coinsBalance || 0,
        totalTransactions
      },
      recentUsers,
      topRooms
    });
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch dashboard stats' });
  }
};

// Get all transactions
export const getAllTransactions = async (req: Request, res: Response) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const skip = (Number(page) - 1) * Number(limit);

    const [transactions, total] = await Promise.all([
      prisma.transaction.findMany({
        take: Number(limit),
        skip,
        orderBy: { createdAt: 'desc' },
        include: {
          user: {
            select: {
              id: true,
              name: true,
              avatarUrl: true
            }
          }
        }
      }),
      prisma.transaction.count()
    ]);

    res.json({
      transactions,
      pagination: {
        page: Number(page),
        limit: Number(limit),
        total,
        totalPages: Math.ceil(total / Number(limit))
      }
    });
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch transactions' });
  }
};

// Delete room (admin only)
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

// Ban/Unban user
export const toggleUserBan = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });

    const isBanned = !!req.body.isBanned;
    const reason = typeof req.body.reason === 'string' ? req.body.reason : null;

    // If your schema DOES NOT have isBanned yet, return a clear message:
    // Remove this block only after adding `isBanned Boolean @default(false)` to User model.
    return res.status(501).json({
      message: 'Ban system not enabled in schema yet. Add `isBanned` to Prisma User model first.',
      userId: userIdNum,
      requestedIsBanned: isBanned,
      reason,
    });

    // ✅ After you add isBanned in schema, use this instead:
    // const user = await prisma.user.update({
    //   where: { id: userIdNum },
    //   data: { isBanned },
    // });
    // return res.json({
    //   message: isBanned ? 'User banned successfully' : 'User unbanned successfully',
    //   user: { id: user.id, name: user.name, isBanned: (user as any).isBanned },
    // });
  } catch (error) {
    console.error('toggleUserBan error:', error);
    return res.status(500).json({ message: 'Failed to update user ban status' });
  }
};


// Make user admin
export const toggleAdminStatus = async (req: Request, res: Response) => {
  try {
    const userIdNum = intParam(req.params.userId);
    if (!userIdNum) return res.status(400).json({ message: 'Invalid userId' });

    const isAdmin = !!req.body.isAdmin;

    const user = await prisma.user.update({
      where: { id: userIdNum },
      data: { isAdmin },
    });

    return res.json({
      message: isAdmin ? 'User promoted to admin' : 'Admin privileges removed',
      user: { id: user.id, name: user.name, isAdmin: user.isAdmin },
    });
  } catch (error) {
    console.error('toggleAdminStatus error:', error);
    return res.status(500).json({ message: 'Failed to update admin status' });
  }
};


