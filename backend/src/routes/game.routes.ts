import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authenticate } from '../middlewares/auth.middleware';
import { playDice, getLeaderboard, getUserGameStats } from '../controllers/game.controller';

const router = Router();

const diceLimiter = rateLimit({
  windowMs: 60_000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `dice:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many dice rolls, slow down' },
});

router.post('/dice/play', authenticate, diceLimiter, playDice);
router.get('/leaderboard', getLeaderboard);
router.get('/stats/:userId', getUserGameStats);

export default router;