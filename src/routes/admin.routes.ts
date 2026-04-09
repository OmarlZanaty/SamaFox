import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import * as adminController from '../controllers/admin.controller';

const router = Router();

// Admin middleware to check if user is admin
const adminMiddleware = async (req: any, res: any, next: any) => {
  try {
    const prisma = require('../utils/prisma').default;
    const user = await prisma.user.findUnique({
    where: { id: req.userId }
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
router.put('/users/:userId/ban', adminController.toggleUserBan);

// Room management
router.delete('/rooms/:roomId', adminController.deleteRoom);

// ✅ ADD THIS BELOW
router.delete('/products/:id', adminController.deleteProduct);

// Transactions
router.get('/transactions', adminController.getAllTransactions);

export default router;

