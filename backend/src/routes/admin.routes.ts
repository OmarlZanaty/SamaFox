import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import { adminMiddleware } from '../middlewares/admin.middleware';
import * as adminController from '../controllers/admin.controller';

const router = Router();

router.use(authMiddleware);
router.use(adminMiddleware);

router.get('/dashboard', adminController.getDashboardStats);
router.get('/users', adminController.getAllUsers);
router.post('/users/:userId/coins/add', adminController.addCoins);
router.post('/users/:userId/coins/remove', adminController.removeCoins);
router.put('/users/:userId/admin', adminController.toggleAdminStatus);
router.put('/users/:userId/ban', adminController.toggleUserBan);
router.delete('/rooms/:roomId', adminController.deleteRoom);
router.delete('/products/:id', adminController.deleteProduct);
router.get('/transactions', adminController.getAllTransactions);

export default router;
