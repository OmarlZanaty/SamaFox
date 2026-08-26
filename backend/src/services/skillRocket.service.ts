import { Server } from 'socket.io';
import prisma from '../utils/prisma';

// ============================================================
// صاروخ المهارة — SKILL ROCKET (real coins, NOT a crash game)
// ============================================================
// This replaces the classic "Crash" game. The original is قمار twice over: you
// stake coins on a round, a hidden random multiplier decides when it blows up,
// and you either multiply the stake by cashing out in time or lose it entirely.
//
// What we do instead — the same model as the fish shooter, نرد المهارة and
// عجلة المهارة (see skillWheel.service.ts): the player pays a FIXED, KNOWN
// entry price for one play, and in exchange always receives a reward. There is:
//   • no wager on an outcome — the entry is a price for a play, not a stake,
//   • no multiplier applied to money and no cash-out race,
//   • nothing hidden and nothing random deciding the payout — the target
//     altitude is announced BEFORE the rocket launches and the climb rate is
//     fixed and known, so where you stop is pure timing,
//   • no zero outcome — every participant gets at least MIN_RETURN back,
//   • no explosion, no "you lost it all" — the rocket simply stops,
//   • no player-vs-player transfer — nobody wins another player's coins.
//
// Economy: same calibration as the other skill games. A careless stop lands far
// from the target and returns the 0.3x floor; only a near-perfect stop reaches
// EXACT_RETURN (1.2x), leaving even a very skilled player at roughly break-even.
// Tune with the SKILL_ROCKET_* env vars, never above 1.2.
// ============================================================

export const ROCKET_ENTRY_TIERS = [1000, 5000, 10000, 50000];

/** Altitude units per second while climbing — the client animates at this exact
 * rate, so the whole game is "when do you tap". Also the difficulty dial: the
 * faster it climbs, the harder an exact stop is, so payouts drop with it. */
export const ROCKET_CLIMB_RATE = 100;

export const ROCKET_MAX_ALTITUDE = 2000;

/** Score by how far the stop landed from the announced altitude. */
const DISTANCE_TIERS: { maxDiff: number; score: number }[] = [
  { maxDiff: 0, score: 100 },
  { maxDiff: 5, score: 72 },
  { maxDiff: 12, score: 48 },
  { maxDiff: 25, score: 28 },
  { maxDiff: 45, score: 12 },
];

export function scoreAltitude(target: number, landed: number): number {
  const diff = Math.abs(target - landed);
  return DISTANCE_TIERS.find((t) => diff <= t.maxDiff)?.score ?? 0;
}

// Reward = entry * multiplier for the highest tier whose `minScore` is met.
// The last entry (minScore 0) is the guaranteed floor: a player who never even
// stops the rocket still gets it back.
const REWARD_TIERS: { minScore: number; multiplier: number }[] = [
  { minScore: 100, multiplier: Number(process.env.SKILL_ROCKET_EXACT_RETURN ?? 1.2) },
  { minScore: 72, multiplier: 0.9 },
  { minScore: 48, multiplier: 0.65 },
  { minScore: 28, multiplier: 0.45 },
  { minScore: 0, multiplier: Number(process.env.SKILL_ROCKET_MIN_RETURN ?? 0.3) },
];

function rewardFor(entry: number, score: number): number {
  const multiplier = REWARD_TIERS.find((t) => score >= t.minScore)?.multiplier ?? 0.3;
  return Math.floor(entry * multiplier);
}

const JOIN_MS = 12_000;
const PLAY_MS = 15_000;
const RESULT_MS = 6_000;

export const ROCKET_PAD_ROOM = 'rocket:main';

// ── Mission ─────────────────────────────────────────────────
// One shape only: a target altitude, announced when the play phase opens. There
// is nothing to guess — only a stop to time.
interface Mission {
  target: number;
  climbRate: number;
  label: string;
}

function rollMission(): Mission {
  // 150–850 → between 1.5s and 8.5s of climb, comfortably inside PLAY_MS.
  const target = 150 + Math.floor(Math.random() * 15) * 50;
  return {
    target,
    climbRate: ROCKET_CLIMB_RATE,
    label: `أوقف الصاروخ عند ارتفاع ${target}`,
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

export function getCurrentRocketRoundPublic() {
  if (!round) return null;
  return {
    roundId: round.id,
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    mission: round.mission,
    entryTiers: ROCKET_ENTRY_TIERS,
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
  io?.to(ROCKET_PAD_ROOM).emit('rocket_round_state', getCurrentRocketRoundPublic());
}

/** Charge the entry price and seat the player in the current round. */
export async function joinRocketRound(userId: number, entry: number) {
  if (!round || round.phase !== 'join') {
    return { ok: false as const, code: 'ROUND_CLOSED', message: 'انتهى وقت الدخول للجولة' };
  }
  if (!ROCKET_ENTRY_TIERS.includes(entry)) {
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
 * Record the altitude the player stopped the rocket at. The client animates the
 * climb at the published rate and reports where it stopped — the same trust
 * model as the fish shooter's capture call. The server owns the target, the
 * scoring and the reward table, so a tampered client can at best claim a
 * perfect stop; it can never invent a payout, replay a round, or submit without
 * having paid.
 */
export function submitRocketRound(userId: number, roundId: number, landed: number) {
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
  const altitude = Number(landed);
  if (!Number.isInteger(altitude) || altitude < 0 || altitude > ROCKET_MAX_ALTITUDE) {
    return { ok: false as const, code: 'BAD_ALTITUDE', message: 'نتيجة غير صحيحة' };
  }

  entrant.landed = altitude;
  entrant.score = scoreAltitude(round.mission!.target, altitude);
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

  // Players who never stopped the rocket still get the guaranteed floor — they
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
      console.error('[skillRocket] payout failed', { userId: e.userId, reward: e.reward, err });
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

  io?.to(ROCKET_PAD_ROOM).emit('rocket_round_result', {
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
    settleRound(r).catch((err) => console.error('[skillRocket] settle error', err));
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

export function startSkillRocketEngine(server: Server) {
  if (io) return; // already running
  io = server;
  startNewRound();
  console.log('[skillRocket] round engine started');
}

export function stopSkillRocketEngine() {
  if (timer) clearTimeout(timer);
  timer = null;
  round = null;
  io = null;
}
