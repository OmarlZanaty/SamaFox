import { Router } from 'express';
import { authMiddleware, optionalAuth } from '../middlewares/auth.middleware';
import { rateLimitMw } from './rateLimit';
import * as ctrl from './controller';

const router = Router();

router.get('/', ctrl.listCatalog);
router.get('/transactions', authMiddleware, ctrl.transactions);
router.get('/received-summary/:userId', ctrl.receivedSummary);
// كأس الدعم: app-wide board, and the same board scoped to one room.
router.get('/supporters', ctrl.topSupporters);
// optionalAuth: the board is public, but knowing WHO is asking is what lets it
// carry that viewer's claimable مكافأة لك rungs (A15b).
router.get('/leaderboard/:roomId', optionalAuth, ctrl.leaderboard);
// A15b — claim a supporter reward rung.
router.post('/supporter-rewards/:id/claim', authMiddleware, ctrl.claimSupporterRewardHandler);
router.post(
  '/send',
  authMiddleware,
  rateLimitMw('gift_send', (req) => req.userId ?? null),
  ctrl.send,
);
// A27 - "المايك الكامل" / "جميع الغرفة": one request fans the gift out to every
// selected user, each receiving the full value. See ctrl.sendBatch for why this
// is not the app looping over /send.
router.post(
  '/send-batch',
  authMiddleware,
  rateLimitMw('gift_send', (req) => req.userId ?? null),
  ctrl.sendBatch,
);

export default router;
