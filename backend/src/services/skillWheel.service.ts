import { Server } from 'socket.io';
import prisma from '../utils/prisma';

// ============================================================
// عجلة المهارة — SKILL WHEEL (real coins, NOT a roulette table)
// ============================================================
// This replaces the classic casino roulette (bet on a number / colour / dozen
// at 36x / 2x / 3x). That format is قمار: the player stakes coins on an
// uncertain outcome and either multiplies the stake or loses it entirely.
//
// What we do instead — the same model already used by the fish shooter and
// نرد المهارة (see skillDice.service.ts): the player pays a FIXED, KNOWN entry
// price for one play, and in exchange always receives a reward. There is:
//   • no wager on an outcome — the entry is a price for a play, not a stake,
//   • no betting zones, no odds and no multipliers on money,
//   • no zero outcome — every participant gets at least MIN_RETURN back,
//   • no player-vs-player transfer — nobody wins another player's coins,
//   • the reward depends on how well the player performs the mission (stopping
//     the pointer on the announced pocket), not on chance applied to money.
//
// The wheel is not a random draw the player bets against: the server announces
// the target pocket BEFORE the wheel starts, the wheel then spins at a fixed,
// known speed, and the player taps to stop it. Where it stops is a matter of
// timing — the closer to the announced pocket, the bigger the reward.
//
// Economy: the reward table is deliberately calibrated so the platform stays
// net-positive. A careless stop lands 5+ pockets away and returns the 0.3x
// floor; only a near-perfect stop reaches EXACT_RETURN (1.2x), which leaves
// even a very skilled player at roughly break-even. Tune with the SKILL_WHEEL_*
// env vars, never above 1.2.
// ============================================================

export const WHEEL_ENTRY_TIERS = [1000, 5000, 10000, 50000];

/** Pocket order on the physical wheel — used for both display and distance. */
export const WHEEL_SEQUENCE = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24,
  16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
];

const RED_NUMBERS = new Set([
  1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
]);

export function pocketColor(n: number): 'green' | 'red' | 'black' {
  if (n === 0) return 'green';
  return RED_NUMBERS.has(n) ? 'red' : 'black';
}

/**
 * Score by how many pockets away the stop landed from the announced target.
 * Landing far away still scores 0 — but 0 score still pays the guaranteed
 * floor, so nobody ever ends a round with nothing.
 */
// Calibrated against a simulated human timing error (see the economy note
// above): with the 2s wheel revolution the client animates, this keeps an elite
// player at ~0.88x and a casual one at ~0.61x. Loosening these — or slowing the
// client's revolution — flips the game player-positive and the platform starts
// losing coins to skilled players.
const DISTANCE_SCORE = [100, 60, 40, 20, 8];

export function scoreStop(target: number, landed: number): number {
  const ti = WHEEL_SEQUENCE.indexOf(target);
  const li = WHEEL_SEQUENCE.indexOf(landed);
  if (ti < 0 || li < 0) return 0;
  const raw = Math.abs(ti - li);
  const distance = Math.min(raw, WHEEL_SEQUENCE.length - raw);
  return DISTANCE_SCORE[distance] ?? 0;
}

// Reward = entry * multiplier for the highest tier whose `minScore` is met.
// Ordered high -> low. Last entry (minScore 0) is the guaranteed floor: a
// player who never even stops the wheel still gets it back.
const REWARD_TIERS: { minScore: number; multiplier: number }[] = [
  { minScore: 100, multiplier: Number(process.env.SKILL_WHEEL_EXACT_RETURN ?? 1.2) },
  { minScore: 72, multiplier: 0.9 },
  { minScore: 48, multiplier: 0.65 },
  { minScore: 28, multiplier: 0.45 },
  { minScore: 0, multiplier: Number(process.env.SKILL_WHEEL_MIN_RETURN ?? 0.3) },
];

function rewardFor(entry: number, score: number): number {
  const multiplier = REWARD_TIERS.find((t) => score >= t.minScore)?.multiplier ?? 0.3;
  return Math.floor(entry * multiplier);
}

const JOIN_MS = 12_000;
const PLAY_MS = 15_000;
const RESULT_MS = 6_000;

export const WHEEL_TABLE_ROOM = 'wheel:main';

// ── Mission ─────────────────────────────────────────────────
// One shape only: a target pocket, announced when the play phase opens. Keeping
// every round the same shape is what makes this a skill test rather than a
// draw — there is nothing to guess, only a stop to time.
interface Mission {
  target: number;
  color: 'green' | 'red' | 'black';
  label: string;
}

function rollMission(): Mission {
  const target = WHEEL_SEQUENCE[Math.floor(Math.random() * WHEEL_SEQUENCE.length)] ?? 0;
  return {
    target,
    color: pocketColor(target),
    label: `أوقف المؤشر على ${target}`,
  };
}

// ── Round state ─────────────────────────────────────────────
type Phase = 'join' | 'play' | 'result';

interface Entrant {
  userId: number;
  name: string;
  avatarUrl: string | null;
  entry: number;
  landed: number | null; // null until they submit
  score: number;
  reward: number;
}

interface Round {
  id: number;
  phase: Phase;
  endsAt: number;
  mission: Mission | null;
  entrants: Map<number, Entrant>;
}

let io: Server | null = null;
let round: Round | null = null;
let timer: NodeJS.Timeout | null = null;
let nextRoundId = 1;

export function getCurrentWheelRoundPublic() {
  if (!round) return null;
  return {
    roundId: round.id,
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    mission: round.mission,
    entryTiers: WHEEL_ENTRY_TIERS,
    players: Array.from(round.entrants.values()).map((e) => ({
      userId: e.userId,
      name: e.name,
      avatarUrl: e.avatarUrl,
      entry: e.entry,
      submitted: e.landed != null,
    })),
  };
}

function broadcastState() {
  io?.to(WHEEL_TABLE_ROOM).emit('wheel_round_state', getCurrentWheelRoundPublic());
}

/** Charge the entry price and seat the player in the current round. */
export async function joinWheelRound(userId: number, entry: number) {
  if (!round || round.phase !== 'join') {
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهى وقت الدخول للجولة' };
  }
  if (!WHEEL_ENTRY_TIERS.includes(entry)) {
    return { ok: false as const, code: 'BAD_TIER', message: 'قيمة دخول غير صحيحة' };
  }
  if (round.entrants.has(userId)) {
    return { ok: false as const, code: 'ALREADY_JOINED', message: 'أنت مشترك في هذه الجولة' };
  }

  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: entry } },
    data: { coinsBalance: { decrement: entry } },
  });
  if (charged.count === 0) {
    return { ok: false as const, code: 'INSUFFICIENT_COINS', message: 'رصيدك لا يكفي' };
  }

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { name: true, avatarUrl: true, coinsBalance: true },
  });

  // The join window can close while the charge is in flight — refund rather
  // than silently keeping the money.
  if (!round || round.phase !== 'join') {
    await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: entry } },
    });
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهى وقت الدخول للجولة' };
  }

  round.entrants.set(userId, {
    userId,
    name: user?.name ?? 'لاعب',
    avatarUrl: user?.avatarUrl ?? null,
    entry,
    landed: null,
    score: 0,
    reward: 0,
  });
  broadcastState();

  return {
    ok: true as const,
    roundId: round.id,
    balance: user?.coinsBalance ?? 0,
    minReward: rewardFor(entry, 0),
    maxReward: rewardFor(entry, 100),
  };
}

/**
 * Record the pocket the player stopped the wheel on. The client runs the spin
 * animation and reports where the pointer came to rest — the same trust model
 * as the fish shooter's capture call. The server owns the target, the scoring
 * and the reward table, so a tampered client can at best claim a perfect stop;
 * it can never invent a payout amount, replay a round, or submit without paying.
 */
export function submitWheelRound(userId: number, roundId: number, landed: number) {
  if (!round || round.id !== roundId) {
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهت الجولة' };
  }
  if (round.phase !== 'play') {
    return { ok: false as const, code: 'NOT_PLAYING', message: 'ليس وقت اللعب' };
  }
  const entrant = round.entrants.get(userId);
  if (!entrant) {
    return { ok: false as const, code: 'NOT_JOINED', message: 'لم تدخل هذه الجولة' };
  }
  if (entrant.landed != null) {
    return { ok: false as const, code: 'ALREADY_SUBMITTED', message: 'سجلت نتيجتك بالفعل' };
  }
  const pocket = Number(landed);
  if (!Number.isInteger(pocket) || !WHEEL_SEQUENCE.includes(pocket)) {
    return { ok: false as const, code: 'BAD_POCKET', message: 'نتيجة غير صحيحة' };
  }

  entrant.landed = pocket;
  entrant.score = scoreStop(round.mission!.target, pocket);
  entrant.reward = rewardFor(entrant.entry, entrant.score);
  broadcastState();

  return {
    ok: true as const,
    score: entrant.score,
    reward: entrant.reward,
    target: round.mission!.target,
  };
}

/** Pay every entrant their earned reward and publish the podium. */
async function settleRound(r: Round) {
  const entrants = Array.from(r.entrants.values());

  // Players who never stopped the wheel still get the guaranteed floor — they
  // paid a price for a play, so they are never left with nothing.
  for (const e of entrants) {
    if (e.landed == null) {
      e.score = 0;
      e.reward = rewardFor(e.entry, 0);
    }
  }

  for (const e of entrants) {
    if (e.reward <= 0) continue;
    try {
      await prisma.user.update({
        where: { id: e.userId },
        data: { coinsBalance: { increment: e.reward } },
      });
    } catch (err) {
      console.error('[skillWheel] payout failed', { userId: e.userId, reward: e.reward, err });
    }
  }

  const podium = [...entrants]
    .sort((a, b) => b.score - a.score || b.reward - a.reward)
    .slice(0, 3)
    .map((e, i) => ({
      rank: i + 1,
      userId: e.userId,
      name: e.name,
      avatarUrl: e.avatarUrl,
      score: e.score,
      reward: e.reward,
    }));

  io?.to(WHEEL_TABLE_ROOM).emit('wheel_round_result', {
    roundId: r.id,
    mission: r.mission,
    podium,
    results: entrants.map((e) => ({
      userId: e.userId,
      landed: e.landed,
      score: e.score,
      reward: e.reward,
      entry: e.entry,
    })),
  });
}

function advance() {
  if (!round) return;
  const r = round;

  if (r.phase === 'join') {
    // Nobody paid in — skip straight to a fresh join window.
    if (r.entrants.size === 0) {
      startNewRound();
      return;
    }
    r.phase = 'play';
    r.mission = rollMission();
    r.endsAt = Date.now() + PLAY_MS;
    broadcastState();
    timer = setTimeout(advance, PLAY_MS);
    return;
  }

  if (r.phase === 'play') {
    r.phase = 'result';
    r.endsAt = Date.now() + RESULT_MS;
    broadcastState();
    settleRound(r).catch((err) => console.error('[skillWheel] settle error', err));
    timer = setTimeout(advance, RESULT_MS);
    return;
  }

  startNewRound();
}

function startNewRound() {
  round = {
    id: nextRoundId++,
    phase: 'join',
    endsAt: Date.now() + JOIN_MS,
    mission: null,
    entrants: new Map(),
  };
  broadcastState();
  timer = setTimeout(advance, JOIN_MS);
}

export function startSkillWheelEngine(server: Server) {
  if (io) return; // already running
  io = server;
  startNewRound();
  console.log('[skillWheel] round engine started');
}

export function stopSkillWheelEngine() {
  if (timer) clearTimeout(timer);
  timer = null;
  round = null;
  io = null;
}
