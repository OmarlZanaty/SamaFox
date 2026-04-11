import { Router } from 'express';
import { authMiddleware as auth } from '../middlewares/auth.middleware';
import * as N from '../controllers/notification.controller';

const router = Router();

router.get('/', auth, N.listNotifications);
router.patch('/read-all', auth, N.markAllNotificationsRead);
router.patch('/:id/read', auth, N.markNotificationRead);

export default router;
