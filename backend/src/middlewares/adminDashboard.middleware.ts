import { Request, Response, NextFunction } from 'express';
import prisma from '../utils/prisma';

export const requireAdminDashboard = async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: { isAdmin: true },
    });

    if (!user?.isAdmin) return res.status(403).json({ success: false, message: 'Not admin' });

    return next();
  } catch {
    return res.status(500).json({ success: false, message: 'Server error' });
  }
};

// Only super-admins may manage the admin roster (#23).
export const requireSuperAdmin = async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: { isSuperAdmin: true },
    });

    if (!user?.isSuperAdmin) return res.status(403).json({ success: false, message: 'Super-admin only' });

    return next();
  } catch {
    return res.status(500).json({ success: false, message: 'Server error' });
  }
};
