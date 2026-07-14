import { Router } from 'express';
import { authMiddleware } from '../middlewares/auth.middleware';
import { rateLimitMw } from './rateLimit';
import * as ctrl from './controller';

const router = Router();

router.get('/', ctrl.listCatalog);
router.get('/transactions', authMiddleware, ctrl.transactions);
router.get('/received-summary/:userId', ctrl.receivedSummary);
router.get('/leaderboard/:roomId', ctrl.leaderboard);
router.post(
  '/send',
  authMiddleware,
  rateLimitMw('gift_send', (req) => req.userId ?? null),
  ctrl.send,
);

export default router;
