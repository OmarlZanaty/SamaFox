import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import * as adminController from '../controllers/admin.controller';
import {
  adminChangeUserDisplayId,
  adminCreateGift,
  adminDeleteGift,
  adminListGifts,
  adminUpdateGift,
} from '../controllers/adminDashboard.controller';

const router = Router();

// Admin middleware to check if user is admin
const adminMiddleware = async (req: any, res: any, next: any) => {
  try {
    const prisma = require('../utils/prisma').default;
    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: { id: true, isAdmin: true },
    });

    if (!user || !user.isAdmin) {
      return res.status(403).json({ message: 'Access denied. Admin only.' });
    }

    next();
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

// All admin routes require authentication and admin status
router.use(authMiddleware);
router.use(adminMiddleware);

// Dashboard
router.get('/dashboard', adminController.getDashboardStats);

// User management
router.get('/users', adminController.getAllUsers);
router.post('/users/:userId/coins/add', adminController.addCoins);
router.post('/users/:userId/coins/remove', adminController.removeCoins);
router.put('/users/:userId/admin', adminController.toggleAdminStatus);
// 2026-08-23: the app issues PATCH here. Only PUT was registered, so every
// in-app ban 404'd — the client's "السوبر ادمن يظهر له حظر المستخدم لكن الحظر
// غير فعال". Both verbs are accepted now so older builds keep working.
router.put('/users/:userId/ban', adminController.toggleUserBan);
router.patch('/users/:userId/ban', adminController.toggleUserBan);
router.patch('/users/:id/display-id', adminChangeUserDisplayId);

// CP / target settings (professional defaults, admin-editable)
router.patch('/settings', require('../controllers/settings.controller').updateSettings);

// Room management (super admin only — enforced in the controller, group 11)
router.delete('/rooms/:roomId', adminController.deleteRoom);
router.patch('/rooms/:roomId/active', adminController.setRoomActive);

// ✅ ADD THIS BELOW
router.delete('/products/:id', adminController.deleteProduct);

// Transactions
router.get('/transactions', adminController.getAllTransactions);

// Legacy-compatible gift management under /api/v1/admin/*
router.get('/gifts', adminListGifts);
router.post('/gifts', adminCreateGift);
router.patch('/gifts/:id', adminUpdateGift);
router.delete('/gifts/:id', adminDeleteGift);

export default router;
