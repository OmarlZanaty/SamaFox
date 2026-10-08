import { Router } from 'express';
import { getYummyState, spinYummy, getYummyHistory, getYummyFairness, setYummyClientSeed, rotateYummySeed, verifyYummySpin,
  getYummyFeed, getYummyLeaderboard, getYummyMissions, claimYummyMission } from '../controllers/yummy.controller';
import { getFruitWheelState, spinFruitWheel, getFruitWheelHistory, getFruitWheelFairness, setFruitWheelClientSeed,
  rotateFruitWheelSeed, verifyFruitWheelSpin, getFruitWheelFeed, getFruitWheelLeaderboard, getFruitWheelToday } from '../controllers/fruitWheel.controller';
import { getRouletteState, placeRouletteBet, undoRouletteBet, clearRouletteBets, repeatRouletteBets, getRouletteHistory,
  getRouletteRanking } from '../controllers/roulette.controller';
import { getCarWheelState, placeCarWheelBet, undoCarWheelBet, clearCarWheelBets, repeatCarWheelBets, getCarWheelHistory,
  getCarWheelRanking } from '../controllers/carWheel.controller';
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
  getAsterionState,
  spinAsterion,
  getAsterionHistory,
  getAsterionFairness,
  setAsterionClientSeed,
  rotateAsterionSeed,
  verifyAsterionSpin,
} from '../controllers/asterion.controller';
import {
  getOlympusState,
  spinOlympus,
  getOlympusHistory,
  getOlympusFairness,
  setOlympusClientSeed,
  rotateOlympusSeed,
  verifyOlympusSpin,
} from '../controllers/olympus.controller';
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
import { gameGuard } from '../services/gameConfig.service';
import { idempotent } from '../middlewares/idempotency.middleware';

// G3(d) — one guard per game in front of the STAKE-TAKING endpoints only.
// Cash-outs, cancels and verifies are deliberately left open: taking a game
// offline must never trap coins a player has already put in.

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

router.post('/dice/play', authenticate, idempotent('game:dice:play'), diceLimiter, gameGuard('dice'), playDice);
router.get('/dice/round', authenticate, getDiceRound);
router.post('/dice/round/join', authenticate, idempotent('game:dice:round:join'), skillDiceLimiter, gameGuard('dice'), joinDiceRound);
router.post('/dice/round/submit', authenticate, skillDiceLimiter, submitDiceRound);
router.get('/wheel/round', authenticate, getWheelRound);
router.post('/wheel/round/join', authenticate, idempotent('game:wheel:round:join'), skillWheelLimiter, gameGuard('wheel'), joinWheelRoundHandler);
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

// الألعاب الحلال — what every stake buys, in words the rules screens can show.
router.get('/halal-terms', authenticate, async (_req: any, res: any) => {
  try {
    const { describeHalalTerms } = await import('../services/halalGames.service');
    res.json({ success: true, data: await describeHalalTerms() });
  } catch (e) {
    console.error('halal-terms error:', e);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

router.get('/crash/state', authenticate, getCrashState);
router.post('/crash/bet', authenticate, idempotent('game:crash:bet'), crashLimiter, gameGuard('crash'), placeCrashBetHandler);
router.post('/crash/cancel', authenticate, idempotent('game:crash:cancel'), crashLimiter, cancelCrashBetHandler);
router.post('/crash/cashout', authenticate, idempotent('game:crash:cashout'), crashCashOutLimiter, cashOutCrashHandler);
router.get('/crash/history', authenticate, getCrashHistoryHandler);
router.get('/crash/fair/:roundId', authenticate, getCrashFairnessHandler);
router.post('/crash/seed', authenticate, crashLimiter, setCrashClientSeedHandler);
router.get('/crash/stats', authenticate, getCrashStatsHandler);
router.get('/crash/chat', authenticate, getCrashChatHandler);
router.post('/crash/chat', authenticate, crashChatLimiter, postCrashChatHandler);
router.post('/crash/rain/claim', authenticate, idempotent('game:crash:rain:claim'), crashLimiter, claimCrashRainHandler);

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
router.post('/crazy/bet', authenticate, idempotent('game:crazy:bet'), crazyWheelLimiter, gameGuard('crazy-wheel'), placeCrazyBet);
router.post('/crazy/clear', authenticate, idempotent('game:crazy:clear'), crazyWheelLimiter, clearCrazyBets);
router.post('/crazy/repeat', authenticate, idempotent('game:crazy:repeat'), crazyWheelLimiter, gameGuard('crazy-wheel'), repeatCrazyBets);
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
router.post('/greedy/bet', authenticate, idempotent('game:greedy:bet'), greedyCatLimiter, gameGuard('greedy-cat'), placeGreedyBet);
router.post('/greedy/reduce', authenticate, idempotent('game:greedy:reduce'), greedyCatLimiter, reduceGreedyBet);
router.post('/greedy/clear', authenticate, idempotent('game:greedy:clear'), greedyCatLimiter, clearGreedyBets);
router.post('/greedy/repeat', authenticate, idempotent('game:greedy:repeat'), greedyCatLimiter, gameGuard('greedy-cat'), repeatGreedyBets);
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
router.post('/plinko/drop', authenticate, idempotent('game:plinko:drop'), plinkoLimiter, gameGuard('plinko'), dropPlinkoBall);
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
router.post('/aetherfall/spin', authenticate, idempotent('game:aetherfall:spin'), aetherfallLimiter, gameGuard('aetherfall'), spinAetherfall);
router.get('/aetherfall/history', authenticate, getAetherfallHistory);
router.get('/aetherfall/fair', authenticate, getAetherfallFairness);
router.post('/aetherfall/seed', authenticate, aetherfallLimiter, setAetherfallClientSeed);
router.post('/aetherfall/seed/rotate', authenticate, aetherfallLimiter, rotateAetherfallSeed);
router.post('/aetherfall/verify', authenticate, verifyAetherfallSpin);

// أستيريون (Citadel of Asterion): one tap is one request — the deal, every
// tumble and the whole Skyfall Trials feature resolve in a single call — so it
// gets the same generous allowance as أثيرفول.
const asterionLimiter = rateLimit({
  windowMs: 60_000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `asterion:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/asterion/state', authenticate, getAsterionState);
router.post('/asterion/spin', authenticate, idempotent('game:asterion:spin'), asterionLimiter, gameGuard('asterion'), spinAsterion);
router.get('/asterion/history', authenticate, getAsterionHistory);
router.get('/asterion/fair', authenticate, getAsterionFairness);
router.post('/asterion/seed', authenticate, asterionLimiter, setAsterionClientSeed);
router.post('/asterion/seed/rotate', authenticate, asterionLimiter, rotateAsterionSeed);
router.post('/asterion/verify', authenticate, verifyAsterionSpin);

// بوابات أوليمبوس (Gates of Olympus): one tap is one request — the deal, every
// tumble and the whole 15-spin free-spins feature resolve in a single call — so
// it gets the same generous allowance as أثيرفول and أستيريون.
const olympusLimiter = rateLimit({
  windowMs: 60_000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: any) => `olympus:${req.userId ?? req.ip}`,
  message: { success: false, message: 'Too many requests, slow down' },
});

router.get('/olympus/state', authenticate, getOlympusState);
router.post('/olympus/spin', authenticate, idempotent('game:olympus:spin'), olympusLimiter, gameGuard('olympus'), spinOlympus);
router.get('/olympus/history', authenticate, getOlympusHistory);
router.get('/olympus/fair', authenticate, getOlympusFairness);
router.post('/olympus/seed', authenticate, olympusLimiter, setOlympusClientSeed);
router.post('/olympus/seed/rotate', authenticate, olympusLimiter, rotateOlympusSeed);
router.post('/olympus/verify', authenticate, verifyOlympusSpin);

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
router.post('/neon/spin', authenticate, idempotent('game:neon:spin'), neonFortuneLimiter, gameGuard('neon-fortune'), spinNeonFortune);
router.get('/neon/jackpots', authenticate, getNeonFortuneJackpots);
router.get('/neon/lucky', authenticate, getNeonFortuneLucky);
router.post('/neon/lucky/claim', authenticate, idempotent('game:neon:lucky:claim'), neonFortuneLimiter, claimNeonFortuneLucky);
router.get('/neon/history', authenticate, getNeonFortuneHistory);
router.get('/neon/fair', authenticate, getNeonFortuneFairness);
router.post('/neon/seed', authenticate, neonFortuneLimiter, setNeonFortuneClientSeed);
router.post('/neon/seed/rotate', authenticate, neonFortuneLimiter, rotateNeonFortuneSeed);
router.post('/neon/verify', authenticate, verifyNeonFortuneSpin);

router.get('/boxing/round', authenticate, getBoxingRound);
router.post('/boxing/round/join', authenticate, idempotent('game:boxing:round:join'), boxingLimiter, gameGuard('boxing'), joinBoxingRound);
router.post('/boxing/round/submit', authenticate, boxingLimiter, submitBoxingRound);
router.get('/leaderboard', getLeaderboard);
router.get('/stats/:userId', getUserGameStats);
router.post('/fish/shoot', authenticate, idempotent('game:fish:shoot'), fishShotLimiter, fireFishShot);
router.post('/fish/capture', authenticate, idempotent('game:fish:capture'), fishCaptureLimiter, captureFish);

const yummyLimiter = rateLimit({ windowMs:60_000, max:120, standardHeaders:true, legacyHeaders:false,
  keyGenerator:(req:any)=>`yummy:${req.userId ?? req.ip}` });
router.get('/yummy/state', authenticate, getYummyState);
router.post('/yummy/spin', authenticate, yummyLimiter, idempotent('game:yummy:spin'), gameGuard('yummy'), spinYummy);
router.get('/yummy/history', authenticate, getYummyHistory);
router.get('/yummy/fair', authenticate, getYummyFairness);
router.post('/yummy/seed', authenticate, yummyLimiter, setYummyClientSeed);
router.post('/yummy/seed/rotate', authenticate, yummyLimiter, rotateYummySeed);
router.post('/yummy/verify', authenticate, yummyLimiter, verifyYummySpin);
router.get('/yummy/feed', authenticate, getYummyFeed);
router.get('/yummy/leaderboard', authenticate, getYummyLeaderboard);
router.get('/yummy/missions', authenticate, getYummyMissions);
router.post('/yummy/missions/:key/claim', authenticate, yummyLimiter, claimYummyMission);

const fruitWheelLimiter = rateLimit({ windowMs:60_000, max:120, standardHeaders:true, legacyHeaders:false,
  keyGenerator:(req:any)=>`fruitwheel:${req.userId ?? req.ip}` });
router.get('/fruitwheel/state', authenticate, getFruitWheelState);
router.post('/fruitwheel/spin', authenticate, fruitWheelLimiter, idempotent('game:fruitwheel:spin'), gameGuard('fruitwheel'), spinFruitWheel);
router.get('/fruitwheel/history', authenticate, getFruitWheelHistory);
router.get('/fruitwheel/fair', authenticate, getFruitWheelFairness);
router.post('/fruitwheel/seed', authenticate, fruitWheelLimiter, setFruitWheelClientSeed);
router.post('/fruitwheel/seed/rotate', authenticate, fruitWheelLimiter, rotateFruitWheelSeed);
router.post('/fruitwheel/verify', authenticate, fruitWheelLimiter, verifyFruitWheelSpin);
router.get('/fruitwheel/feed', authenticate, getFruitWheelFeed);
router.get('/fruitwheel/leaderboard', authenticate, getFruitWheelLeaderboard);
router.get('/fruitwheel/today', authenticate, getFruitWheelToday);

// A chip per tap, so the limit is generous; every bet still settles one at a time per player.
const rouletteLimiter = rateLimit({ windowMs:60_000, max:300, standardHeaders:true, legacyHeaders:false,
  keyGenerator:(req:any)=>`roulette:${req.userId ?? req.ip}` });
router.get('/roulette/state', authenticate, getRouletteState);
router.post('/roulette/bet', authenticate, rouletteLimiter, idempotent('game:roulette:bet'), placeRouletteBet);
router.post('/roulette/undo', authenticate, rouletteLimiter, idempotent('game:roulette:undo'), undoRouletteBet);
router.post('/roulette/clear', authenticate, rouletteLimiter, idempotent('game:roulette:clear'), clearRouletteBets);
router.post('/roulette/repeat', authenticate, rouletteLimiter, idempotent('game:roulette:repeat'), gameGuard('roulette'), repeatRouletteBets);
router.get('/roulette/history', authenticate, getRouletteHistory);
router.get('/roulette/ranking', authenticate, getRouletteRanking);

// A chip per tap, so the limit is generous; every bet still settles one at a time per player.
const carWheelLimiter = rateLimit({ windowMs:60_000, max:300, standardHeaders:true, legacyHeaders:false,
  keyGenerator:(req:any)=>`carwheel:${req.userId ?? req.ip}` });
router.get('/carwheel/state', authenticate, getCarWheelState);
router.post('/carwheel/bet', authenticate, carWheelLimiter, idempotent('game:carwheel:bet'), placeCarWheelBet);
router.post('/carwheel/undo', authenticate, carWheelLimiter, idempotent('game:carwheel:undo'), undoCarWheelBet);
router.post('/carwheel/clear', authenticate, carWheelLimiter, idempotent('game:carwheel:clear'), clearCarWheelBets);
router.post('/carwheel/repeat', authenticate, carWheelLimiter, idempotent('game:carwheel:repeat'), gameGuard('carwheel'), repeatCarWheelBets);
router.get('/carwheel/history', authenticate, getCarWheelHistory);
router.get('/carwheel/ranking', authenticate, getCarWheelRanking);

export default router;
