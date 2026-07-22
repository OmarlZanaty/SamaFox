import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { authenticate } from '../middlewares/auth.middleware';
import {
  playDice,
  getLeaderboard,
  getUserGameStats,
  fireFishShot,
  captureFish,
  getDiceRound,
  joinDiceRound,
  submitDiceRound,
} from '../controllers/game.controller';

const router = Router();

const diceLimiter = rateLimit({
  windowMs: 60_000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `dice:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many dice rolls, slow down' },
});

const fishShotLimiter = rateLimit({
  windowMs: 10_000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `fish-shot:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many shots, slow down' },
});

const fishCaptureLimiter = rateLimit({
  windowMs: 10_000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `fish-capture:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many captures, slow down' },
});

// Skill dice: one join + one submit per round, so the limits only need to be
// generous enough for the ~33s round cycle plus retries.
const skillDiceLimiter = rateLimit({
  windowMs: 60_000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `skill-dice:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.post('/dice/play', authenticate, diceLimiter, playDice);
router.get('/dice/round', authenticate, getDiceRound);
router.post('/dice/round/join', authenticate, skillDiceLimiter, joinDiceRound);
router.post('/dice/round/submit', authenticate, skillDiceLimiter, submitDiceRound);
router.get('/leaderboard', getLeaderboard);
router.get('/stats/:userId', getUserGameStats);
router.post('/fish/shoot', authenticate, fishShotLimiter, fireFishShot);
router.post('/fish/capture', authenticate, fishCaptureLimiter, captureFish);

export default router;