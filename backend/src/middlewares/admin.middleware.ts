import { Request, Response, NextFunction, RequestHandler } from 'express';
import prisma from '../utils/prisma';

/**
 * Admin authorization. Must be chained AFTER authMiddleware.
 * Looks up the authenticated user and rejects unless `isAdmin` is true.
 */
export const adminMiddleware: RequestHandler = async (req: Request, res: Response, next: NextFunction) => {
  try {
    const userId = req.userId ?? req.authUser?.id;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    // A super admin outranks a plain admin, so he must pass every gate a plain
    // admin passes. Selecting `isAdmin` alone locked out any account with
    // isSuperAdmin=true / isAdmin=false — which is the owner's own test account,
    // and why "زر الحظر ظاهر للسوبر أدمن لكنه غير فعال".
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, isAdmin: true, isSuperAdmin: true },
    });
    if (!user || (!user.isAdmin && !user.isSuperAdmin)) {
      return res.status(403).json({ success: false, message: 'Admin access required' });
    }
    return next();
  } catch (err) {
    console.error('[adminMiddleware] error:', (err as Error).message);
    return res.status(500).json({ success: false, message: 'Admin check failed' });
  }
};

export const requireAdmin = adminMiddleware;
