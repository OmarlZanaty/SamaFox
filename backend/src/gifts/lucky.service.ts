import crypto from 'crypto';
import type { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { PROGRAM_ACCOUNT, bpShare, creditAccount } from '../services/economyAccounts.service';

// ============================================================
// هدايا الحظ — LUCKY GIFTS (rules of 2026-09-26)
// ============================================================
// A lucky gift worth V is an ENTRY in its room's current round:
//
//   program ← programShareBp of V   (default 30%) — the host's H (10% of V)
//                                     is paid out of this share, the rest is
//                                     the program's (PROGRAM account)
//   pool    ← prizePoolBp of V      (default 70%) — the players' prize pool
//
// Competition: a round is a time window per room. An entry is only DRAWN once
// its round has `minPlayers` distinct players (a lone player is never paid a
// competitive win, and no coin is ever created for him). Entries made before
// that wait as PENDING; the moment the round becomes competitive every pending
// entry is drawn. A round that closes still short of players settles its
// pending entries as NO_COMPETITION: no win, and their V stays split exactly
// as above.
//
// Draw: the multiplier set is x5 … x500, each with an admin-set probability
// (basis points; the remainder is "no win"). A win pays m × V — the full gift
// value (client, 2026-10-05: "خلي المكسب من قيمة الهديه") — to the sender,
// FROM THE POOL ONLY, and never from its locked floor (`poolFloor`: the
// program's seed money — "مفيش مكسب من البرنامج نهائي"). A multiplier the
// pool — or the admin's max win — cannot cover is not in the draw at all, so
// every shown multiplier is paid in full and the pool can never go below its
// floor. The expected return, E[m] (the RTP), is validated against the
// admin's RTP target, which cannot exceed the prize-pool share.
//
// A player alone in his round (fewer than 2 players) "wins from his own
// losses": his win is also capped by what he has put into the pool and not yet
// won back, so a lone player can never take coins other players lost.
//
// Fairness: every entry commits to a fresh server seed at entry time (its hash
// is stored and returned immediately); the draw at settlement is
// SHA-256(seed) → uniform in [0, 10000) → walked over the eligible tier weights,
// which are stored with the roll so it can be recomputed (`verifyRoll`).
// ============================================================

export const LUCKY_MULTIPLIERS = [5, 10, 20, 30, 50, 100, 200, 300, 500] as const;

/** Legacy keys still honoured (the old dashboard card writes them). */
export const LUCKY_HOST_SHARE_KEY = 'lucky_host_share_bp';
export const LUCKY_HOST_SHARE_DEFAULT_BP = 1000;
export const LUCKY_BROADCAST_MIN_KEY = 'lucky_broadcast_min_multiplier';
export const LUCKY_BROADCAST_MIN_DEFAULT = 10;
export const LUCKY_CONFIG_KEY = 'lucky_config';

/** The dashboard list the app shows as the "محظوظ" tab. */
export const LUCKY_CATEGORY_KEY = 'lucky';

/**
 * A gift is lucky when its flag is set OR it sits in the "lucky" list. The app
 * has always shown both in the محظوظ tab; the server used to honour only the
 * flag, so a gift filed under the list without ticking the box was shown as
 * lucky and sent as an ordinary gift — no round, no draw.
 */
export function isLuckyGift(g: { isLucky: boolean; category?: string | null }) {
  return g.isLucky || (g.category ?? '').trim() === LUCKY_CATEGORY_KEY;
}

const BP = 10_000;

export interface LuckyConfig {
  enabled: boolean;
  programShareBp: number;
  prizePoolBp: number;
  hostShareBp: number;
  minPlayers: number;
  maxPlayers: number;
  minEntry: number;
  maxEntry: number;
  rtpTargetBp: number;
  maxWin: number;
  roundSeconds: number;
  broadcastMin: number;
  /** Coins at the bottom of the pool that no win may touch (the seed). */
  poolFloor: number;
}

export const LUCKY_DEFAULTS: LuckyConfig = {
  enabled: true,
  programShareBp: 3000,
  prizePoolBp: 7000,
  hostShareBp: LUCKY_HOST_SHARE_DEFAULT_BP,
  minPlayers: 2,
  maxPlayers: 100,
  minEntry: 1,
  maxEntry: 1_000_000,
  rtpTargetBp: 6500,
  maxWin: 1_000_000,
  roundSeconds: 60,
  broadcastMin: LUCKY_BROADCAST_MIN_DEFAULT,
  poolFloor: 0,
};

export interface LuckyTierRow {
  multiplier: number;
  weightBp: number;
  minPoolCoins: bigint;
}

export type LuckyStatus = 'PENDING' | 'SETTLED' | 'NO_COMPETITION';

export interface LuckyRollResult {
  rollId: number;
  status: LuckyStatus;
  roundCode: string | null;
  multiplier: number;
  payoutCoins: number;
  hostCoins: number;
  poolAfter: bigint;
  serverSeedHash: string;
}

/** An entry drawn during this call — the sender's own, or someone else's
 *  pending entry that this gift made competitive. */
export interface SettledEntry {
  rollId: number;
  giftTxId: string;
  senderId: number;
  recipientId: number;
  roomId: number | null;
  giftCoins: number;
  hostCoins: number;
  multiplier: number;
  payoutCoins: number;
  roundCode: string | null;
}

// ── settings & tiers ─────────────────────────────────────────

let tiersCache: { at: number; rows: LuckyTierRow[] } | null = null;
let configCache: { at: number; cfg: LuckyConfig } | null = null;
const CACHE_MS = 15_000;

export function invalidateLuckyCache() {
  tiersCache = null;
  configCache = null;
}

export async function getLuckyTiers(): Promise<LuckyTierRow[]> {
  if (tiersCache && Date.now() - tiersCache.at < CACHE_MS) return tiersCache.rows;
  const rows = await prisma.luckyTier.findMany({
    where: { isActive: true },
    orderBy: { multiplier: 'asc' },
    select: { multiplier: true, weightBp: true, minPoolCoins: true },
  });
  tiersCache = { at: Date.now(), rows };
  return rows;
}

export async function getLuckyConfig(): Promise<LuckyConfig> {
  if (configCache && Date.now() - configCache.at < CACHE_MS) return configCache.cfg;
  const rows = await prisma.appSetting.findMany({
    where: { key: { in: [LUCKY_CONFIG_KEY, LUCKY_HOST_SHARE_KEY, LUCKY_BROADCAST_MIN_KEY] } },
  });
  const m = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  let stored: Partial<LuckyConfig> = {};
  try {
    if (m[LUCKY_CONFIG_KEY]) stored = JSON.parse(m[LUCKY_CONFIG_KEY]!);
  } catch {
    stored = {};
  }
  const cfg: LuckyConfig = { ...LUCKY_DEFAULTS, ...stored };
  // The legacy single-value keys win only when lucky_config never set them.
  if (stored.hostShareBp == null && m[LUCKY_HOST_SHARE_KEY] != null) {
    cfg.hostShareBp = clampInt(Number(m[LUCKY_HOST_SHARE_KEY]), 100, 5000, LUCKY_HOST_SHARE_DEFAULT_BP);
  }
  if (stored.broadcastMin == null && m[LUCKY_BROADCAST_MIN_KEY] != null) {
    cfg.broadcastMin = clampInt(Number(m[LUCKY_BROADCAST_MIN_KEY]), 0, 500, LUCKY_BROADCAST_MIN_DEFAULT);
  }
  configCache = { at: Date.now(), cfg };
  return cfg;
}

/** Old call sites read `hostShareBp` / `broadcastMin` from here. */
export async function getLuckySettings() {
  const cfg = await getLuckyConfig();
  return { at: Date.now(), ...cfg };
}

function clampInt(n: number, lo: number, hi: number, dflt: number) {
  if (!Number.isFinite(n)) return dflt;
  return Math.min(hi, Math.max(lo, Math.floor(n)));
}

/** The host's cut of a lucky gift worth `giftCoins`. */
export function luckyHostCoins(giftCoins: number, hostShareBp: number) {
  return Math.floor((giftCoins * hostShareBp) / BP);
}

// ── validation (the dashboard and the save endpoint both run these) ─────────

export function validateLuckyConfig(c: LuckyConfig): string | null {
  const int = (v: unknown) => Number.isInteger(v);
  if (![c.programShareBp, c.prizePoolBp, c.hostShareBp, c.minPlayers, c.maxPlayers, c.minEntry, c.maxEntry, c.rtpTargetBp, c.maxWin, c.roundSeconds, c.broadcastMin, c.poolFloor].every(int)) {
    return 'كل القيم يجب أن تكون أرقاماً صحيحة';
  }
  if (c.programShareBp < 0 || c.prizePoolBp < 0) return 'النسب لا تكون سالبة';
  if (c.programShareBp + c.prizePoolBp !== BP) return 'حصة البرنامج + صندوق الجوائز يجب أن تساوي 100%';
  if (c.hostShareBp <= 0) return 'حصة المضيف يجب أن تكون أكبر من صفر';
  if (c.hostShareBp > c.programShareBp) return 'حصة المضيف تُدفع من حصة البرنامج، فلا تتجاوزها';
  if (c.minPlayers < 1 || c.maxPlayers < c.minPlayers || c.maxPlayers > 10_000) return 'عدد اللاعبين غير منطقي (الأدنى ≥ 1 والأقصى ≥ الأدنى)';
  if (c.minEntry < 1 || c.maxEntry < c.minEntry) return 'حدود المشاركة غير منطقية (الأدنى ≥ 1 والأقصى ≥ الأدنى)';
  if (c.rtpTargetBp < 0 || c.rtpTargetBp > c.prizePoolBp) return 'RTP المستهدف لا يتجاوز نسبة صندوق الجوائز';
  if (c.maxWin < 1) return 'أقصى مكسب يجب أن يكون 1 أو أكثر';
  if (c.roundSeconds < 10 || c.roundSeconds > 3600) return 'مدة الجولة بين 10 ثوانٍ وساعة';
  if (c.broadcastMin < 0) return 'حد الإعلان لا يكون سالباً';
  if (c.poolFloor < 0) return 'الحد المحجوز في الصندوق لا يكون سالباً';
  return null;
}

/**
 * Expected multiplier of a tier table, and what it returns per coin of V.
 * RTP = E[m] (the win is m × V). `hostShareBp` is only reported back.
 */
export function analyzeTiers(tiers: { multiplier: number; weightBp: number }[], hostShareBp: number, cfg?: Partial<LuckyConfig>) {
  const totalWeight = tiers.reduce((a, t) => a + t.weightBp, 0);
  const expectedMultiplier = tiers.reduce((a, t) => a + (t.multiplier * t.weightBp) / BP, 0);
  const s = hostShareBp / BP;
  const rtp = expectedMultiplier;
  const prizePool = (cfg?.prizePoolBp ?? LUCKY_DEFAULTS.prizePoolBp) / BP;
  const rtpTarget = (cfg?.rtpTargetBp ?? LUCKY_DEFAULTS.rtpTargetBp) / BP;
  return {
    totalWeightBp: totalWeight,
    loseBp: BP - totalWeight,
    winRate: totalWeight / BP,
    expectedMultiplier,
    /** Kept under its old name for the old dashboard card. */
    senderReturn: rtp,
    rtp,
    rtpTarget,
    hostShare: s,
    prizePoolShare: prizePool,
    /** What the pool keeps per coin of V on average. */
    poolIntake: prizePool - rtp,
    valid: totalWeight <= BP && totalWeight >= 0 && rtp <= rtpTarget + 1e-9 && rtp <= prizePool + 1e-9,
  };
}

export function validateTiers(tiers: { multiplier: number; weightBp: number }[], cfg: LuckyConfig): string | null {
  const seen = new Set<number>();
  for (const t of tiers) {
    if (!(LUCKY_MULTIPLIERS as readonly number[]).includes(t.multiplier)) return `مضاعف غير مسموح: x${t.multiplier}`;
    if (seen.has(t.multiplier)) return `المضاعف x${t.multiplier} مكرر`;
    seen.add(t.multiplier);
    if (!Number.isInteger(t.weightBp) || t.weightBp < 0) return 'الاحتمال يجب أن يكون رقماً صحيحاً موجباً (بالنقطة الأساسية)';
  }
  const a = analyzeTiers(tiers, cfg.hostShareBp, cfg);
  if (a.totalWeightBp > BP) return `مجموع الاحتمالات ${a.totalWeightBp / 100}% أكبر من 100%`;
  if (a.rtp > a.rtpTarget + 1e-9) {
    return `العائد المحسوب ${(a.rtp * 100).toFixed(2)}% أعلى من RTP المستهدف ${(a.rtpTarget * 100).toFixed(2)}%`;
  }
  return null;
}

// ── the draw ─────────────────────────────────────────────────

export function rollHash(serverSeed: string) {
  return crypto.createHash('sha256').update(serverSeed).digest('hex');
}

/**
 * The draw point of a round entry. NOT the published hash: an entry can wait
 * PENDING with its commitment public, and a point readable from the commitment
 * would let a player complete only the rounds he already knows he wins. The
 * point comes from the secret seed, which is revealed only after the draw.
 */
export function drawPointFromSeed(serverSeed: string, giftTxId: string) {
  return rollPointFromHash(crypto.createHash('sha256').update(`${serverSeed}:${giftTxId}:draw`).digest('hex'));
}

/** hash → integer in [0, 10000). 52 bits of the hash is plenty. */
export function rollPointFromHash(hash: string) {
  const h = parseInt(hash.slice(0, 13), 16);
  return h % BP;
}

/** Walk the (eligible) tiers; anything past the last weight is a loss. */
export function multiplierAtPoint(point: number, tiers: { multiplier: number; weightBp: number }[]) {
  let acc = 0;
  for (const t of tiers) {
    acc += t.weightBp;
    if (point < acc) return t.multiplier;
  }
  return 0;
}

interface EntryInput {
  giftTxId: string;
  senderId: number;
  recipientId: number;
  roomId: number | null;
  giftCoins: number; // V
  hostCoins: number; // H
  // A gift to yourself enters the round like any other (owner's call,
  // 2026-10-05: the client tested by gifting himself and never saw a draw).
  cfg: LuckyConfig;
}

export interface EntryResult {
  own: LuckyRollResult;
  /** Everyone drawn in this call, the sender's own entry included when drawn. */
  settled: SettledEntry[];
}

function newRoundCode(roomId: number | null) {
  return `LR${roomId ?? 0}-${Date.now().toString(36)}-${crypto.randomBytes(3).toString('hex')}`.toUpperCase();
}

/**
 * Close every OPEN round of this room whose window has passed: pending entries
 * become NO_COMPETITION. Returns what was closed, for the room notice.
 */
export async function closeExpiredRounds(tx: Prisma.TransactionClient, roomId: number | null | 'ALL', cfg: LuckyConfig) {
  const now = new Date();
  const where: any = { status: 'OPEN', endsAt: { lte: now } };
  if (roomId !== 'ALL') where.roomId = roomId;
  const expired = await tx.luckyRound.findMany({ where, select: { id: true, code: true, roomId: true, playerCount: true } });
  const closed: { roundId: number; code: string; roomId: number | null; status: string; pending: { rollId: number; senderId: number; giftTxId: string }[] }[] = [];
  for (const r of expired) {
    const pending = await tx.luckyRoll.findMany({
      where: { roundId: r.id, status: 'PENDING' },
      select: { id: true, senderId: true, giftTxId: true },
    });
    if (pending.length) {
      await tx.luckyRoll.updateMany({
        where: { roundId: r.id, status: 'PENDING' },
        data: { status: 'NO_COMPETITION', settledAt: now },
      });
    }
    const status = r.playerCount >= cfg.minPlayers ? 'SETTLED' : 'NOT_COMPETITIVE';
    await tx.luckyRound.update({ where: { id: r.id }, data: { status, closedAt: now } });
    closed.push({
      roundId: r.id,
      code: r.code,
      roomId: r.roomId,
      status,
      pending: pending.map((p) => ({ rollId: p.id, senderId: p.senderId, giftTxId: p.giftTxId })),
    });
  }
  return closed;
}

async function openRoundFor(tx: Prisma.TransactionClient, roomId: number | null, senderId: number, cfg: LuckyConfig) {
  await closeExpiredRounds(tx, roomId, cfg);
  const now = new Date();
  let round = await tx.luckyRound.findFirst({
    where: { roomId, status: 'OPEN', endsAt: { gt: now } },
    orderBy: { id: 'desc' },
  });
  if (round && round.playerCount >= cfg.maxPlayers) {
    const already = await tx.luckyRoll.findFirst({ where: { roundId: round.id, senderId }, select: { id: true } });
    if (!already) {
      // Full: close it early (it is competitive — it has maxPlayers ≥ minPlayers)
      // and start the next one.
      await tx.luckyRound.update({ where: { id: round.id }, data: { status: 'SETTLED', closedAt: now } });
      round = null;
    }
  }
  if (!round) {
    round = await tx.luckyRound.create({
      data: {
        code: newRoundCode(roomId),
        roomId,
        endsAt: new Date(now.getTime() + cfg.roundSeconds * 1000),
      },
    });
  }
  return round;
}

/**
 * Enter a lucky gift into its round, INSIDE the gift's own transaction (a
 * failed gift enters nothing; a failed entry rolls the gift back).
 */
export async function rollLucky(tx: Prisma.TransactionClient, input: EntryInput): Promise<EntryResult> {
  const { cfg } = input;
  const V = input.giftCoins;
  const H = input.hostCoins;
  const programGross = bpShare(V, cfg.programShareBp);
  const poolCoins = V - programGross;
  const programCoins = programGross - H;
  if (programCoins < 0 || poolCoins < 0) throw new Error('lucky: shares do not add up');

  // Fund first. The pool row is the serialisation point for every lucky gift
  // in flight — deliberate: every draw's eligibility depends on it.
  const funded = await tx.luckyPool.upsert({
    where: { id: 1 },
    update: { balance: { increment: BigInt(poolCoins) }, totalIn: { increment: BigInt(poolCoins) } },
    create: { id: 1, balance: BigInt(poolCoins), totalIn: BigInt(poolCoins) },
    select: { balance: true },
  });
  if (programCoins > 0) {
    await creditAccount(tx, PROGRAM_ACCOUNT, programCoins, {
      kind: 'LUCKY_PROGRAM',
      refType: 'lucky',
      refId: input.giftTxId,
      userId: input.senderId,
    });
  }

  const serverSeed = crypto.randomBytes(16).toString('hex');
  const serverSeedHash = rollHash(serverSeed);

  const round = await openRoundFor(tx, input.roomId, input.senderId, cfg);
  const isNewPlayer = !(await tx.luckyRoll.findFirst({
    where: { roundId: round.id, senderId: input.senderId },
    select: { id: true },
  }));
  const updatedRound = await tx.luckyRound.update({
    where: { id: round.id },
    data: {
      playerCount: { increment: isNewPlayer ? 1 : 0 },
      entryCount: { increment: 1 },
      totalEntry: { increment: BigInt(V) },
      hostShare: { increment: BigInt(H) },
      programShare: { increment: BigInt(programGross) },
      prizePool: { increment: BigInt(poolCoins) },
    },
  });

  const own = await tx.luckyRoll.create({
    data: {
      giftTxId: input.giftTxId,
      senderId: input.senderId,
      recipientId: input.recipientId,
      roomId: input.roomId,
      giftCoins: V,
      hostCoins: H,
      multiplier: 0,
      payoutCoins: 0,
      poolBefore: funded.balance - BigInt(poolCoins),
      poolAfter: funded.balance,
      serverSeed,
      serverSeedHash,
      tiersSnapshot: [],
      roundId: round.id,
      programCoins,
      poolCoins,
      status: 'PENDING',
    },
    select: { id: true },
  });

  let settled: SettledEntry[] = [];
  if (updatedRound.playerCount >= cfg.minPlayers) {
    settled = await drawPending(tx, round.id, round.code, cfg, updatedRound.playerCount < 2);
  }

  const mine = settled.find((s) => s.rollId === own.id);
  const poolNow = (await tx.luckyPool.findUnique({ where: { id: 1 }, select: { balance: true } }))?.balance ?? funded.balance;
  return {
    own: mine
      ? { rollId: own.id, status: 'SETTLED', roundCode: round.code, multiplier: mine.multiplier, payoutCoins: mine.payoutCoins, hostCoins: H, poolAfter: poolNow, serverSeedHash }
      : { rollId: own.id, status: 'PENDING', roundCode: round.code, multiplier: 0, payoutCoins: 0, hostCoins: H, poolAfter: poolNow, serverSeedHash },
    settled,
  };
}

/** What a player has put into the pool and not yet won back (never < 0). */
async function netPoolContribution(tx: Prisma.TransactionClient, senderId: number) {
  const agg = await tx.luckyRoll.aggregate({
    where: { senderId },
    _sum: { poolCoins: true, payoutCoins: true },
  });
  const net = (agg._sum.poolCoins ?? 0) - (agg._sum.payoutCoins ?? 0);
  return Math.max(0, net);
}

/** Draw every pending entry of a drawable round, oldest first. `solo`: the
 *  round has a single player, whose wins are capped by his own losses. */
async function drawPending(tx: Prisma.TransactionClient, roundId: number, roundCode: string, cfg: LuckyConfig, solo: boolean): Promise<SettledEntry[]> {
  const pending = await tx.luckyRoll.findMany({
    where: { roundId, status: 'PENDING' },
    orderBy: { id: 'asc' },
  });
  if (!pending.length) return [];
  const tiersAll = await tx.luckyTier.findMany({
    where: { isActive: true },
    orderBy: { multiplier: 'asc' },
    select: { multiplier: true, weightBp: true, minPoolCoins: true },
  });

  const out: SettledEntry[] = [];
  let totalWin = 0n;
  for (const p of pending) {
    const pool = (await tx.luckyPool.findUnique({ where: { id: 1 }, select: { balance: true } }))?.balance ?? 0n;
    // Players' money only: the locked floor is never paid out.
    const floor = BigInt(cfg.poolFloor);
    const available = pool > floor ? pool - floor : 0n;
    const soloCap = solo ? BigInt(await netPoolContribution(tx, p.senderId)) : null;
    // Only multipliers the pool, the max-win cap AND (alone) the player's own
    // losses can pay are in the draw. The losing share absorbs the weight of
    // the excluded ones.
    const eligible = tiersAll.filter((t) => {
      const win = BigInt(t.multiplier) * BigInt(p.giftCoins);
      return (
        available >= t.minPoolCoins &&
        available >= win &&
        win <= BigInt(cfg.maxWin) &&
        (soloCap == null || win <= soloCap)
      );
    });
    const point = drawPointFromSeed(p.serverSeed, p.giftTxId);
    const multiplier = multiplierAtPoint(point, eligible);
    const payoutCoins = multiplier * p.giftCoins;

    let poolAfter = pool;
    if (payoutCoins > 0) {
      const paid = await tx.luckyPool.updateMany({
        where: { id: 1, balance: { gte: BigInt(payoutCoins) } },
        data: { balance: { decrement: BigInt(payoutCoins) }, totalOut: { increment: BigInt(payoutCoins) } },
      });
      if (paid.count !== 1) throw new Error('lucky: pool could not cover payout');
      poolAfter = pool - BigInt(payoutCoins);
      await tx.user.update({ where: { id: p.senderId }, data: { coinsBalance: { increment: payoutCoins } } });
      await tx.transaction.create({
        data: { userId: p.senderId, type: 'LUCKY_WIN', amountCoins: payoutCoins, status: 'completed', externalId: p.giftTxId },
      });
      totalWin += BigInt(payoutCoins);
    }
    await tx.luckyRoll.update({
      where: { id: p.id },
      data: {
        multiplier,
        payoutCoins,
        poolBefore: pool,
        poolAfter,
        tiersSnapshot: eligible.map((t) => ({ multiplier: t.multiplier, weightBp: t.weightBp })),
        status: 'SETTLED',
        settledAt: new Date(),
      },
    });
    out.push({
      rollId: p.id,
      giftTxId: p.giftTxId,
      senderId: p.senderId,
      recipientId: p.recipientId,
      roomId: p.roomId,
      giftCoins: p.giftCoins,
      hostCoins: p.hostCoins,
      multiplier,
      payoutCoins,
      roundCode,
    });
  }
  if (totalWin > 0n) await tx.luckyRound.update({ where: { id: roundId }, data: { totalWin: { increment: totalWin } } });
  return out;
}

/** Recompute a stored roll from its seed and snapshot. */
export function verifyRoll(roll: {
  serverSeed: string;
  serverSeedHash: string;
  tiersSnapshot: unknown;
  multiplier: number;
  roundId?: number | null;
  giftTxId?: string;
}) {
  const hash = rollHash(roll.serverSeed);
  const tiers = Array.isArray(roll.tiersSnapshot) ? (roll.tiersSnapshot as { multiplier: number; weightBp: number }[]) : [];
  // Round entries (2026-09-26 on) draw from the seed; the older instant rolls
  // drew from the hash itself.
  const point = roll.roundId != null && roll.giftTxId ? drawPointFromSeed(roll.serverSeed, roll.giftTxId) : rollPointFromHash(hash);
  const multiplier = multiplierAtPoint(point, tiers);
  return {
    hashMatches: hash === roll.serverSeedHash,
    point,
    multiplier,
    matches: hash === roll.serverSeedHash && multiplier === roll.multiplier,
  };
}

// ── round expiry sweeper ─────────────────────────────────────

export type RoundClosedListener = (closed: Awaited<ReturnType<typeof closeExpiredRounds>>) => void;
let sweeper: NodeJS.Timeout | null = null;

export function startLuckyRoundSweeper(onClosed: RoundClosedListener, everyMs = 15_000) {
  if (sweeper) return;
  sweeper = setInterval(async () => {
    try {
      const cfg = await getLuckyConfig();
      const closed = await prisma.$transaction((tx) => closeExpiredRounds(tx, 'ALL', cfg));
      if (closed.length) onClosed(closed);
    } catch (e) {
      console.warn('[lucky] round sweep failed:', (e as Error).message);
    }
  }, everyMs);
  sweeper.unref?.();
}

export function stopLuckyRoundSweeper() {
  if (sweeper) clearInterval(sweeper);
  sweeper = null;
}
