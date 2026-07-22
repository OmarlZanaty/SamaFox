import { Server } from 'socket.io';
import prisma from '../utils/prisma';

// ============================================================
// نرد المهارة — SKILL DICE (real coins, NOT a betting game)
// ============================================================
// This replaces the classic "Greedy Dice" casino table (Small/Big/Tiger with
// 2x/35x odds). That format is قمار: the player stakes coins on an uncertain
// outcome and either multiplies the stake or loses it entirely.
//
// What we do instead — the same model already used by the fish shooter
// (see game.controller.ts): the player pays a FIXED, KNOWN entry price for one
// play, and in exchange always receives a reward. There is:
//   • no wager on an outcome — the entry is a price for a play, not a stake,
//   • no odds and no multipliers on money,
//   • no zero outcome — every participant gets at least MIN_RETURN back,
//   • no player-vs-player transfer — nobody wins another player's coins,
//   • the reward depends on how well the player performs the mission
//     (stopping the spinning dice on the right faces + one re-roll decision),
//     not on chance applied to their money.
//
// Economy: the reward table below is deliberately calibrated so that the
// platform stays net-positive. An average player recovers roughly 40-55% of the
// entry price; only near-perfect play reaches EXACT_RETURN (>1.0), and that is
// hard enough that the expected payout for even a very skilled player sits at
// about break-even. Tune with the SKILL_DICE_* env vars, never above 1.2.
// ============================================================

export const DICE_ENTRY_TIERS = [1000, 5000, 10000, 50000];

// Reward = entry * multiplier for the highest tier whose `minScore` is met.
// Ordered high -> low. Last entry (minScore 0) is the guaranteed floor: a
// player who does nothing at all still gets it back.
const REWARD_TIERS: { minScore: number; multiplier: number }[] = [
  { minScore: 100, multiplier: Number(process.env.SKILL_DICE_EXACT_RETURN ?? 1.2) },
  { minScore: 80, multiplier: 0.9 },
  { minScore: 55, multiplier: 0.65 },
  { minScore: 30, multiplier: 0.45 },
  { minScore: 0, multiplier: Number(process.env.SKILL_DICE_MIN_RETURN ?? 0.3) },
];

const JOIN_MS = 12_000;
const PLAY_MS = 15_000;
const RESULT_MS = 6_000;

export const DICE_TABLE_ROOM = 'dice:main';

// ── Missions ────────────────────────────────────────────────
// The round's goal, announced to everyone when the play phase opens. Score is
// 0-100 by how close the submitted dice are to the goal — a partial match still
// scores, so effort is always rewarded.
type Mission =
  | { key: 'sum'; target: number; label: string }
  | { key: 'triple'; label: string }
  | { key: 'straight'; label: string }
  | { key: 'high'; label: string }
  | { key: 'low'; label: string };

function rollMission(): Mission {
  // 'triple' and 'straight' are the hardest, so they appear less often.
  const pool = ['sum', 'sum', 'sum', 'high', 'low', 'straight', 'triple'] as const;
  const key = pool[Math.floor(Math.random() * pool.length)];
  switch (key) {
    case 'sum': {
      // Centre-weighted targets (9-12) keep a blind guess from scoring well.
      const target = 9 + Math.floor(Math.random() * 4);
      return { key: 'sum', target, label: `اجمع ${target} بالضبط` };
    }
    case 'triple':
      return { key: 'triple', label: 'ثلاثة أرقام متطابقة' };
    case 'straight':
      return { key: 'straight', label: 'ثلاثة أرقام متتالية' };
    case 'high':
      return { key: 'high', label: 'كل النرد ٤ أو أكثر' };
    case 'low':
    default:
      return { key: 'low', label: 'كل النرد ٣ أو أقل' };
  }
}

// How many dice match the "all high"/"all low" goal -> score.
const MATCH_COUNT_SCORE = [0, 25, 55, 100];

export function scoreMission(mission: Mission, dice: number[]): number {
  const [a, b, c] = [...dice].sort((x, y) => x - y) as [number, number, number];
  switch (mission.key) {
    case 'sum': {
      const diff = Math.abs(dice.reduce((x, y) => x + y, 0) - mission.target);
      return Math.max(0, 100 - diff * 25);
    }
    case 'triple': {
      if (a === c) return 100;
      if (a === b || b === c) return 45;
      return 0;
    }
    case 'straight': {
      if (b === a + 1 && c === b + 1) return 100;
      return b === a + 1 || c === b + 1 ? 45 : 0;
    }
    case 'high':
      return MATCH_COUNT_SCORE[dice.filter((d) => d >= 4).length] ?? 0;
    case 'low':
    default:
      return MATCH_COUNT_SCORE[dice.filter((d) => d <= 3).length] ?? 0;
  }
}

function rewardFor(entry: number, score: number): number {
  const multiplier = REWARD_TIERS.find((t) => score >= t.minScore)?.multiplier ?? 0.3;
  return Math.floor(entry * multiplier);
}

// ── Round state ─────────────────────────────────────────────
type Phase = 'join' | 'play' | 'result';

interface Entrant {
  userId: number;
  name: string;
  avatarUrl: string | null;
  entry: number;
  dice: number[] | null; // null until they submit
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

export function getCurrentRoundPublic() {
  if (!round) return null;
  return {
    roundId: round.id,
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    mission: round.mission,
    entryTiers: DICE_ENTRY_TIERS,
    players: Array.from(round.entrants.values()).map((e) => ({
      userId: e.userId,
      name: e.name,
      avatarUrl: e.avatarUrl,
      entry: e.entry,
      submitted: e.dice != null,
    })),
  };
}

function broadcastState() {
  io?.to(DICE_TABLE_ROOM).emit('dice_round_state', getCurrentRoundPublic());
}

/** Charge the entry price and seat the player in the current round. */
export async function joinRound(userId: number, entry: number) {
  if (!round || round.phase !== 'join') {
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهى وقت الدخول للجولة' };
  }
  if (!DICE_ENTRY_TIERS.includes(entry)) {
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
    await prisma.user.update({ where: { id: userId }, data: { coinsBalance: { increment: entry } } });
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهى وقت الدخول للجولة' };
  }

  round.entrants.set(userId, {
    userId,
    name: user?.name ?? 'لاعب',
    avatarUrl: user?.avatarUrl ?? null,
    entry,
    dice: null,
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
 * Record the player's final dice. The client runs the spin/stop animation and
 * reports the faces it landed on — the same trust model as the fish shooter's
 * capture call. The server owns the mission, the scoring and the reward table,
 * so a tampered client can at best claim a perfect play; it can never invent a
 * payout amount, replay a round, or submit without having paid.
 */
export function submitRound(userId: number, roundId: number, dice: number[]) {
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
  if (entrant.dice) {
    return { ok: false as const, code: 'ALREADY_SUBMITTED', message: 'سجلت نتيجتك بالفعل' };
  }
  const clean = Array.isArray(dice) ? dice.map((d) => Number(d)) : [];
  if (clean.length !== 3 || clean.some((d) => !Number.isInteger(d) || d < 1 || d > 6)) {
    return { ok: false as const, code: 'BAD_DICE', message: 'نتيجة غير صحيحة' };
  }

  entrant.dice = clean;
  entrant.score = scoreMission(round.mission!, clean);
  entrant.reward = rewardFor(entrant.entry, entrant.score);
  broadcastState();

  return { ok: true as const, score: entrant.score, reward: entrant.reward };
}

/** Pay every entrant their earned reward and publish the podium. */
async function settleRound(r: Round) {
  const entrants = Array.from(r.entrants.values());

  // Players who never submitted still get the guaranteed floor — they paid a
  // price for a play, so they are never left with nothing.
  for (const e of entrants) {
    if (!e.dice) {
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
      console.error('[skillDice] payout failed', { userId: e.userId, reward: e.reward, err });
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

  io?.to(DICE_TABLE_ROOM).emit('dice_round_result', {
    roundId: r.id,
    mission: r.mission,
    podium,
    results: entrants.map((e) => ({
      userId: e.userId,
      dice: e.dice,
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
    settleRound(r).catch((err) => console.error('[skillDice] settle error', err));
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

export function startSkillDiceEngine(server: Server) {
  if (io) return; // already running
  io = server;
  startNewRound();
  console.log('[skillDice] round engine started');
}

export function stopSkillDiceEngine() {
  if (timer) clearTimeout(timer);
  timer = null;
  round = null;
  io = null;
}
