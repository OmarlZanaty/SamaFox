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
import {
  getCrazyState,
  placeCrazyBet,
  clearCrazyBets,
  repeatCrazyBets,
  submitCrazyPick,
  getCrazyHistory,
} from '../controllers/crazyWheel.controller';
import {
  getPlinkoState,
  dropPlinkoBall,
  getPlinkoHistory,
  getPlinkoFairness,
  setPlinkoClientSeed,
  rotatePlinkoSeed,
  verifyPlinkoDrop,
} from '../controllers/plinko.controller';
import {
  getGreedyState,
  placeGreedyBet,
  reduceGreedyBet,
  clearGreedyBets,
  repeatGreedyBets,
  getGreedyHistory,
  getGreedyRanking,
} from '../controllers/greedyCat.controller';
import {
  getAetherfallState,
  spinAetherfall,
  getAetherfallHistory,
  getAetherfallFairness,
  setAetherfallClientSeed,
  rotateAetherfallSeed,
  verifyAetherfallSpin,
} from '../controllers/aetherfall.controller';
import {
  getNeonFortuneState,
  spinNeonFortune,
  getNeonFortuneJackpots,
  getNeonFortuneLucky,
  claimNeonFortuneLucky,
  getNeonFortuneHistory,
  getNeonFortuneFairness,
  setNeonFortuneClientSeed,
  rotateNeonFortuneSeed,
  verifyNeonFortuneSpin,
} from '../controllers/neonFortune.controller';

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

// عجلة الحظ (Crazy Wheel): a player can stack chips on all 8 spots inside a
// 20s betting window and still repeat/clear, so this needs crash-level headroom.
const crazyWheelLimiter = rateLimit({
  windowMs: 60_000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `crazy-wheel:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/crazy/state', authenticate, getCrazyState);
router.post('/crazy/bet', authenticate, crazyWheelLimiter, placeCrazyBet);
router.post('/crazy/clear', authenticate, crazyWheelLimiter, clearCrazyBets);
router.post('/crazy/repeat', authenticate, crazyWheelLimiter, repeatCrazyBets);
router.post('/crazy/pick', authenticate, crazyWheelLimiter, submitCrazyPick);
router.get('/crazy/history', authenticate, getCrazyHistory);

// القط الجشع (Greedy Cat): eight food cards plus two category buttons, tapped
// repeatedly inside a 30s window, so it needs the same headroom as عجلة الحظ.
const greedyCatLimiter = rateLimit({
  windowMs: 60_000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `greedy-cat:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/greedy/state', authenticate, getGreedyState);
router.post('/greedy/bet', authenticate, greedyCatLimiter, placeGreedyBet);
router.post('/greedy/reduce', authenticate, greedyCatLimiter, reduceGreedyBet);
router.post('/greedy/clear', authenticate, greedyCatLimiter, clearGreedyBets);
router.post('/greedy/repeat', authenticate, greedyCatLimiter, repeatGreedyBets);
router.get('/greedy/history', authenticate, getGreedyHistory);
router.get('/greedy/ranking', authenticate, getGreedyRanking);

// بلينكو: every drop is its own request and auto-bet fires them back to back, so
// this needs the highest allowance of any game.
const plinkoLimiter = rateLimit({
  windowMs: 60_000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `plinko:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/plinko/state', authenticate, getPlinkoState);
router.post('/plinko/drop', authenticate, plinkoLimiter, dropPlinkoBall);
router.get('/plinko/history', authenticate, getPlinkoHistory);
router.get('/plinko/fair', authenticate, getPlinkoFairness);
router.post('/plinko/seed', authenticate, plinkoLimiter, setPlinkoClientSeed);
router.post('/plinko/seed/rotate', authenticate, plinkoLimiter, rotatePlinkoSeed);
router.post('/plinko/verify', authenticate, verifyPlinkoDrop);

// أثيرفول (Aetherfall): each spin can chain a long cascade sequence plus a
// Skyfire Vault bonus server-side, but it is still one request per spin like
// بلينكو's one-request-per-drop, so it gets the same generous allowance.
const aetherfallLimiter = rateLimit({
  windowMs: 60_000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `aetherfall:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/aetherfall/state', authenticate, getAetherfallState);
router.post('/aetherfall/spin', authenticate, aetherfallLimiter, spinAetherfall);
router.get('/aetherfall/history', authenticate, getAetherfallHistory);
router.get('/aetherfall/fair', authenticate, getAetherfallFairness);
router.post('/aetherfall/seed', authenticate, aetherfallLimiter, setAetherfallClientSeed);
router.post('/aetherfall/seed/rotate', authenticate, aetherfallLimiter, rotateAetherfallSeed);
router.post('/aetherfall/verify', authenticate, verifyAetherfallSpin);

// نيون فورتشن (Neon Fortune): one request per spin, and a spin can carry a whole
// free-spin round and a vault bonus with it, so the allowance matches أثيرفول.
const neonFortuneLimiter = rateLimit({
  windowMs: 60_000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `neon-fortune:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/neon/state', authenticate, getNeonFortuneState);
router.post('/neon/spin', authenticate, neonFortuneLimiter, spinNeonFortune);
router.get('/neon/jackpots', authenticate, getNeonFortuneJackpots);
router.get('/neon/lucky', authenticate, getNeonFortuneLucky);
router.post('/neon/lucky/claim', authenticate, neonFortuneLimiter, claimNeonFortuneLucky);
router.get('/neon/history', authenticate, getNeonFortuneHistory);
router.get('/neon/fair', authenticate, getNeonFortuneFairness);
router.post('/neon/seed', authenticate, neonFortuneLimiter, setNeonFortuneClientSeed);
router.post('/neon/seed/rotate', authenticate, neonFortuneLimiter, rotateNeonFortuneSeed);
router.post('/neon/verify', authenticate, verifyNeonFortuneSpin);

router.get('/boxing/round', authenticate, getBoxingRound);
router.post('/boxing/round/join', authenticate, boxingLimiter, joinBoxingRound);
router.post('/boxing/round/submit', authenticate, boxingLimiter, submitBoxingRound);
router.get('/leaderboard', getLeaderboard);
router.get('/stats/:userId', getUserGameStats);
router.post('/fish/shoot', authenticate, fishShotLimiter, fireFishShot);
router.post('/fish/capture', authenticate, fishCaptureLimiter, captureFish);

export default router;