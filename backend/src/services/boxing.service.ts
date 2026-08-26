import { Server } from 'socket.io';
import prisma from '../utils/prisma';

// ============================================================
// حلبة الأسد والنمر — LION & TIGER ARENA (real coins, NOT a betting game)
// ============================================================
// This replaces the classic "Lion or Tiger" casino table (bet on Lion / Tie /
// Tiger at 2x/30x). That format is قمار: the player stakes coins on an
// uncertain outcome that they cannot influence, and either multiplies the
// stake or loses it entirely.
//
// What we do instead — the same model as the fish shooter and skill dice
// (see skillDice.service.ts): the player pays a FIXED, KNOWN entry price for
// one play and in exchange always receives a reward. There is:
//   • no wager on an outcome — the entry is a ticket price, not a stake,
//   • no odds and no multipliers on money,
//   • no zero outcome — every participant gets at least MIN_RETURN back,
//   • no player-vs-player transfer — nobody wins another player's coins,
//   • the player is IN the ring, not betting on it: the reward depends on how
//     well they land their own punches, not on chance applied to their money.
//
// Picking الأسد or النمر is choosing which fighter you play as — purely
// cosmetic. It carries no odds and never changes a payout.
//
// Economy: the reward table is calibrated so the platform stays net-positive.
// An average player recovers roughly 40-55% of the entry price; only near
// perfect play reaches TOP_RETURN (>1.0), which leaves even a very skilled
// player at about break-even. Tune with BOXING_* env vars, never above 1.2.
// ============================================================

export const BOXING_ENTRY_TIERS = [1000, 5000, 10000, 50000];

/** Punches thrown per play. The client sends one accuracy value (0-100) each. */
export const PUNCHES_PER_ROUND = 6;

export const BOXING_CORNERS = ['lion', 'tiger'] as const;
export type BoxingCorner = (typeof BOXING_CORNERS)[number];

// Reward = entry * multiplier for the highest tier whose `minScore` is met.
// Ordered high -> low. The last entry (minScore 0) is the guaranteed floor: a
// player who never throws a punch still gets it back.
const REWARD_TIERS: { minScore: number; multiplier: number }[] = [
  { minScore: 100, multiplier: Number(process.env.BOXING_TOP_RETURN ?? 1.2) },
  { minScore: 80, multiplier: 0.9 },
  { minScore: 55, multiplier: 0.65 },
  { minScore: 30, multiplier: 0.45 },
  { minScore: 0, multiplier: Number(process.env.BOXING_MIN_RETURN ?? 0.3) },
];

const JOIN_MS = 12_000;
const PLAY_MS = 15_000;
const RESULT_MS = 6_000;

export const BOXING_RING_ROOM = 'boxing:main';

// ── Missions ────────────────────────────────────────────────
// The corner instruction for the round, announced to everyone when the play
// phase opens. Score is 0-100 by how close the player got — a partial result
// still scores, so effort is always rewarded and nobody is wiped out.
type Mission =
  | { key: 'power'; target: number; label: string }
  | { key: 'knockout'; need: number; label: string }
  | { key: 'combo'; need: number; label: string };

/** A punch this clean counts as a knockout blow. */
const KO_ACCURACY = 88;
/** A punch this clean keeps a combo alive. */
const COMBO_ACCURACY = 70;

function rollMission(): Mission {
  // 'knockout' is the hardest, so it comes up least often.
  const pool = ['power', 'power', 'combo', 'combo', 'knockout'] as const;
  const key = pool[Math.floor(Math.random() * pool.length)];
  switch (key) {
    case 'power': {
      // 72-84 average accuracy: reachable with good timing, not by mashing.
      const target = 72 + Math.floor(Math.random() * 13);
      return { key: 'power', target, label: `متوسط دقة ${target}% أو أعلى` };
    }
    case 'knockout': {
      const need = 2 + Math.floor(Math.random() * 2); // 2-3
      return { key: 'knockout', need, label: `سدّد ${need} لكمات قاضية` };
    }
    case 'combo':
    default: {
      const need = 3 + Math.floor(Math.random() * 2); // 3-4
      return { key: 'combo', need, label: `كومبو ${need} لكمات متتالية` };
    }
  }
}

/**
 * Score a play out of 100. `punches` is the accuracy (0-100) of each punch the
 * player landed, in order; a missed/never-thrown punch is 0.
 */
export function scoreMission(mission: Mission, punches: number[]): number {
  switch (mission.key) {
    case 'power': {
      const avg = punches.reduce((a, b) => a + b, 0) / PUNCHES_PER_ROUND;
      return Math.max(0, Math.min(100, Math.round((avg / mission.target) * 100)));
    }
    case 'knockout': {
      const kos = punches.filter((p) => p >= KO_ACCURACY).length;
      return Math.max(0, Math.min(100, Math.round((kos / mission.need) * 100)));
    }
    case 'combo':
    default: {
      let best = 0;
      let run = 0;
      for (const p of punches) {
        run = p >= COMBO_ACCURACY ? run + 1 : 0;
        if (run > best) best = run;
      }
      return Math.max(0, Math.min(100, Math.round((best / mission.need) * 100)));
    }
  }
}

function rewardFor(entry: number, score: number): number {
  const multiplier = REWARD_TIERS.find((t) => score >= t.minScore)?.multiplier ?? 0.3;
  return Math.floor(entry * multiplier);
}

// ── Round state ─────────────────────────────────────────────
type Phase = 'join' | 'play' | 'result';

interface Fighter {
  userId: number;
  name: string;
  avatarUrl: string | null;
  entry: number;
  corner: BoxingCorner;
  punches: number[] | null; // null until they submit
  score: number;
  reward: number;
}

interface Round {
  id: number;
  phase: Phase;
  endsAt: number;
  mission: Mission | null;
  fighters: Map<number, Fighter>;
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
    entryTiers: BOXING_ENTRY_TIERS,
    punches: PUNCHES_PER_ROUND,
    players: Array.from(round.fighters.values()).map((f) => ({
      userId: f.userId,
      name: f.name,
      avatarUrl: f.avatarUrl,
      entry: f.entry,
      corner: f.corner,
      submitted: f.punches != null,
    })),
  };
}

function broadcastState() {
  io?.to(BOXING_RING_ROOM).emit('boxing_round_state', getCurrentRoundPublic());
}

/** Charge the entry price and put the player in the ring for this round. */
export async function joinRound(userId: number, entry: number, corner: string) {
  if (!round || round.phase !== 'join') {
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهى وقت الدخول للجولة' };
  }
  if (!BOXING_ENTRY_TIERS.includes(entry)) {
    return { ok: false as const, code: 'BAD_TIER', message: 'قيمة دخول غير صحيحة' };
  }
  if (!BOXING_CORNERS.includes(corner as BoxingCorner)) {
    return { ok: false as const, code: 'BAD_CORNER', message: 'اختر الأسد أو النمر' };
  }
  if (round.fighters.has(userId)) {
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

  round.fighters.set(userId, {
    userId,
    name: user?.name ?? 'لاعب',
    avatarUrl: user?.avatarUrl ?? null,
    entry,
    corner: corner as BoxingCorner,
    punches: null,
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
 * Record the accuracy of the punches the player threw. The client runs the
 * timing bar and reports what it landed — the same trust model as the fish
 * shooter's capture call. The server owns the mission, the scoring and the
 * reward table, so a tampered client can at best claim a perfect play; it can
 * never invent a payout amount, replay a round, or submit without having paid.
 */
export function submitRound(userId: number, roundId: number, punches: number[]) {
  if (!round || round.id !== roundId) {
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهت الجولة' };
  }
  if (round.phase !== 'play') {
    return { ok: false as const, code: 'NOT_PLAYING', message: 'ليس وقت اللعب' };
  }
  const fighter = round.fighters.get(userId);
  if (!fighter) {
    return { ok: false as const, code: 'NOT_JOINED', message: 'لم تدخل هذه الجولة' };
  }
  if (fighter.punches) {
    return { ok: false as const, code: 'ALREADY_SUBMITTED', message: 'سجلت نتيجتك بالفعل' };
  }
  const clean = Array.isArray(punches) ? punches.map((p) => Math.round(Number(p))) : [];
  if (
    clean.length !== PUNCHES_PER_ROUND ||
    clean.some((p) => !Number.isFinite(p) || p < 0 || p > 100)
  ) {
    return { ok: false as const, code: 'BAD_PUNCHES', message: 'نتيجة غير صحيحة' };
  }

  fighter.punches = clean;
  fighter.score = scoreMission(round.mission!, clean);
  fighter.reward = rewardFor(fighter.entry, fighter.score);
  broadcastState();

  return { ok: true as const, score: fighter.score, reward: fighter.reward };
}

/** Pay every fighter their earned reward and publish the podium. */
async function settleRound(r: Round) {
  const fighters = Array.from(r.fighters.values());

  // Players who never submitted still get the guaranteed floor — they paid a
  // ticket price for a play, so they are never left with nothing.
  for (const f of fighters) {
    if (!f.punches) {
      f.score = 0;
      f.reward = rewardFor(f.entry, 0);
    }
  }

  for (const f of fighters) {
    if (f.reward <= 0) continue;
    try {
      await prisma.user.update({
        where: { id: f.userId },
        data: { coinsBalance: { increment: f.reward } },
      });
    } catch (err) {
      console.error('[boxing] payout failed', { userId: f.userId, reward: f.reward, err });
    }
  }

  const podium = [...fighters]
    .sort((a, b) => b.score - a.score || b.reward - a.reward)
    .slice(0, 3)
    .map((f, i) => ({
      rank: i + 1,
      userId: f.userId,
      name: f.name,
      avatarUrl: f.avatarUrl,
      corner: f.corner,
      score: f.score,
      reward: f.reward,
    }));

  io?.to(BOXING_RING_ROOM).emit('boxing_round_result', {
    roundId: r.id,
    mission: r.mission,
    podium,
    results: fighters.map((f) => ({
      userId: f.userId,
      corner: f.corner,
      punches: f.punches,
      score: f.score,
      reward: f.reward,
      entry: f.entry,
    })),
  });
}

function advance() {
  if (!round) return;
  const r = round;

  if (r.phase === 'join') {
    // Nobody paid in — skip straight to a fresh join window.
    if (r.fighters.size === 0) {
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
    settleRound(r).catch((err) => console.error('[boxing] settle error', err));
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
    fighters: new Map(),
  };
  broadcastState();
  timer = setTimeout(advance, JOIN_MS);
}

export function startBoxingEngine(server: Server) {
  if (io) return; // already running
  io = server;
  startNewRound();
  console.log('[boxing] round engine started');
}

export function stopBoxingEngine() {
  if (timer) clearTimeout(timer);
  timer = null;
  round = null;
  io = null;
}
