import { Router } from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import { playDice, getLeaderboard, getUserGameStats } from '../controllers/game.controller';

const router = Router();

// Game endpoints
router.post('/dice/play', authenticate, playDice);
router.get('/leaderboard', getLeaderboard);
router.get('/stats/:userId', getUserGameStats);

export default router;