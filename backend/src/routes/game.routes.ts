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
  getWheelRound,
  joinWheelRoundHandler,
  submitWheelRoundHandler,
  getBoxingRound,
  joinBoxingRound,
  submitBoxingRound,
} from '../controllers/game.controller';
import {
  getCrashState,
  placeCrashBetHandler,
  cancelCrashBetHandler,
  cashOutCrashHandler,
  getCrashHistoryHandler,
  getCrashFairnessHandler,
  setCrashClientSeedHandler,
  getCrashStatsHandler,
  getCrashChatHandler,
  postCrashChatHandler,
  claimCrashRainHandler,
} from '../controllers/crash.controller';

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

// Skill wheel: same shape as skill dice — one join + one submit per ~33s round
// cycle, so the same allowance covers it with room for retries.
const skillWheelLimiter = rateLimit({
  windowMs: 60_000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `skill-wheel:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

// Lion & tiger arena: same shape as skill dice — one join + one submit per
// ~33s round cycle, so the same allowance is plenty.
const boxingLimiter = rateLimit({
  windowMs: 60_000,
  max: 40,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `boxing:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.post('/dice/play', authenticate, diceLimiter, playDice);
router.get('/dice/round', authenticate, getDiceRound);
router.post('/dice/round/join', authenticate, skillDiceLimiter, joinDiceRound);
router.post('/dice/round/submit', authenticate, skillDiceLimiter, submitDiceRound);
router.get('/wheel/round', authenticate, getWheelRound);
router.post('/wheel/round/join', authenticate, skillWheelLimiter, joinWheelRoundHandler);
router.post('/wheel/round/submit', authenticate, skillWheelLimiter, submitWheelRoundHandler);
// Crash (طيّار): rounds cycle every ~10s and a player may bet on two panels and
// cash both out, so this needs a much higher allowance than the skill games.
const crashLimiter = rateLimit({
  windowMs: 60_000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `crash:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

// Cashing out is time-critical — never let the limiter cost a player a payout,
// but still cap a client that is hammering the endpoint.
const crashCashOutLimiter = rateLimit({
  windowMs: 60_000,
  max: 240,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `crash-cashout:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

const crashChatLimiter = rateLimit({
  windowMs: 60_000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `crash-chat:${req.userId ?? req.ip}`,
  message: { success: false, message: 'مهلاً، رسائل كثيرة' },
});

router.get('/crash/state', authenticate, getCrashState);
router.post('/crash/bet', authenticate, crashLimiter, placeCrashBetHandler);
router.post('/crash/cancel', authenticate, crashLimiter, cancelCrashBetHandler);
router.post('/crash/cashout', authenticate, crashCashOutLimiter, cashOutCrashHandler);
router.get('/crash/history', authenticate, getCrashHistoryHandler);
router.get('/crash/fair/:roundId', authenticate, getCrashFairnessHandler);
router.post('/crash/seed', authenticate, crashLimiter, setCrashClientSeedHandler);
router.get('/crash/stats', authenticate, getCrashStatsHandler);
router.get('/crash/chat', authenticate, getCrashChatHandler);
router.post('/crash/chat', authenticate, crashChatLimiter, postCrashChatHandler);
router.post('/crash/rain/claim', authenticate, crashLimiter, claimCrashRainHandler);

router.get('/boxing/round', authenticate, getBoxingRound);
router.post('/boxing/round/join', authenticate, boxingLimiter, joinBoxingRound);
router.post('/boxing/round/submit', authenticate, boxingLimiter, submitBoxingRound);
router.get('/leaderboard', getLeaderboard);
router.get('/stats/:userId', getUserGameStats);
router.post('/fish/shoot', authenticate, fishShotLimiter, fireFishShot);
router.post('/fish/capture', authenticate, fishCaptureLimiter, captureFish);

export default router;