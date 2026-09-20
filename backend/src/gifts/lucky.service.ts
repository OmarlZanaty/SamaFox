import crypto from 'crypto';
import type { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';

// ============================================================
// هدايا الحظ — LUCKY GIFTS
// ============================================================
// The client's rule, verbatim: "الداعم يرمي على المضيف الهدية والهدية يروح 10%
// من قيمتها للمضيف والداعم يحصل على أضعاف القيمة اللي راحت للمضيف … مفيش حد
// يكسب من البرنامج لكن الكل يحس إنه كسبان".
//
// So for a gift worth V:
//   host   ← H = 10% of V            (through the normal gift ledger)
//   pool   ← V − H                   (the other 90%, first)
//   sender ← m × H, m from the tier table, paid FROM THE POOL
//
// Two hard guarantees, both enforced here and nowhere else:
//   1. The pool never goes negative. A multiplier the pool cannot pay is not
//      in the draw at all (not "drawn then capped" — that would skew the odds
//      the admin configured); and the debit is a conditional update.
//   2. The house takes nothing and gives nothing. Every coin a sender wins
//      was put in by a sender who lost. The admin can only ever ADD to the
//      pool (a promotion), never take from it.
//
// Fairness: each roll draws a fresh server seed; the roll is
// SHA-256(seed) → uniform in [0, 10000) → walked over the tier weights that
// were in force. Seed, hash and the tier snapshot are stored on the roll, so
// anyone can recompute it (see `verifyRoll`).

export const LUCKY_MULTIPLIERS = [5, 10, 20, 50, 100, 200, 300, 500] as const;

/** Host share, in basis points. 1000 = 10%. Admin-adjustable via app_settings. */
export const LUCKY_HOST_SHARE_KEY = 'lucky_host_share_bp';
export const LUCKY_HOST_SHARE_DEFAULT_BP = 1000;

/** Wins at or above this multiplier are announced to the whole app. */
export const LUCKY_BROADCAST_MIN_KEY = 'lucky_broadcast_min_multiplier';
export const LUCKY_BROADCAST_MIN_DEFAULT = 10;

const BP = 10_000;

export interface LuckyTierRow {
  multiplier: number;
  weightBp: number;
  minPoolCoins: bigint;
}

export interface LuckyRollResult {
  rollId: number;
  multiplier: number;
  payoutCoins: number;
  hostCoins: number;
  poolAfter: bigint;
  serverSeedHash: string;
}

// ── settings & tiers (cached briefly; a roll must not cost two extra queries) ──

let tiersCache: { at: number; rows: LuckyTierRow[] } | null = null;
let settingsCache: { at: number; hostShareBp: number; broadcastMin: number } | null = null;
const CACHE_MS = 15_000;

export function invalidateLuckyCache() {
  tiersCache = null;
  settingsCache = null;
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

export async function getLuckySettings() {
  if (settingsCache && Date.now() - settingsCache.at < CACHE_MS) return settingsCache;
  const rows = await prisma.appSetting.findMany({
    where: { key: { in: [LUCKY_HOST_SHARE_KEY, LUCKY_BROADCAST_MIN_KEY] } },
  });
  const m = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  const hostShareBp = clampInt(Number(m[LUCKY_HOST_SHARE_KEY]), 100, 5000, LUCKY_HOST_SHARE_DEFAULT_BP);
  const broadcastMin = clampInt(Number(m[LUCKY_BROADCAST_MIN_KEY]), 0, 500, LUCKY_BROADCAST_MIN_DEFAULT);
  settingsCache = { at: Date.now(), hostShareBp, broadcastMin };
  return settingsCache;
}

function clampInt(n: number, lo: number, hi: number, dflt: number) {
  if (!Number.isFinite(n)) return dflt;
  return Math.min(hi, Math.max(lo, Math.floor(n)));
}

/** The host's cut of a lucky gift worth `giftCoins`. */
export function luckyHostCoins(giftCoins: number, hostShareBp: number) {
  return Math.floor((giftCoins * hostShareBp) / BP);
}

// ── the economics check the admin UI and the tier endpoint both run ──────────

/**
 * Expected multiplier of a tier table, and whether the table can ever cost
 * the house money. With host share s and expected multiplier E, the sender
 * gets back E×s of every coin and the host s, so the pool's expected intake
 * per coin is 1 − s − E×s. It must stay ≥ 0 or the pool drains to zero and
 * stays there (nobody is robbed — the pool guard holds — but every roll
 * becomes a loss, which is the opposite of "الكل يحس إنه كسبان").
 */
export function analyzeTiers(tiers: { multiplier: number; weightBp: number }[], hostShareBp: number) {
  const totalWeight = tiers.reduce((a, t) => a + t.weightBp, 0);
  const expectedMultiplier = tiers.reduce((a, t) => a + (t.multiplier * t.weightBp) / BP, 0);
  const s = hostShareBp / BP;
  const senderReturn = expectedMultiplier * s; // fraction of V back to sender
  const poolIntake = 1 - s - senderReturn;     // fraction of V the pool keeps
  return {
    totalWeightBp: totalWeight,
    loseBp: BP - totalWeight,
    winRate: totalWeight / BP,
    expectedMultiplier,
    senderReturn,
    hostShare: s,
    poolIntake,
    valid: totalWeight <= BP && totalWeight >= 0 && poolIntake >= 0,
  };
}

// ── the roll ─────────────────────────────────────────────────────────────────

export function rollHash(serverSeed: string) {
  return crypto.createHash('sha256').update(serverSeed).digest('hex');
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

interface RollInput {
  giftTxId: string;
  senderId: number;
  recipientId: number;
  roomId: number | null;
  giftCoins: number;   // V
  hostCoins: number;   // H
  /** A gift to yourself never wins — there is no host to have paid. */
  isSelfGift: boolean;
}

/**
 * Feed the pool with the 90%, draw, and pay the sender from the pool. Runs
 * INSIDE the gift's own transaction so a failed gift rolls nothing back on its
 * own, and a failed roll rolls the gift back with it.
 */
export async function rollLucky(tx: Prisma.TransactionClient, input: RollInput): Promise<LuckyRollResult> {
  const toPool = BigInt(input.giftCoins - input.hostCoins);
  if (toPool < 0n) throw new Error('lucky: host share exceeds gift');

  // Fund first. The row is the serialisation point for every lucky gift in
  // flight — that is deliberate: the pool balance is the one number every
  // roll's eligibility depends on.
  const funded = await tx.luckyPool.upsert({
    where: { id: 1 },
    update: { balance: { increment: toPool }, totalIn: { increment: toPool } },
    create: { id: 1, balance: toPool, totalIn: toPool },
    select: { balance: true },
  });
  const poolBefore = funded.balance - toPool;
  const poolAfterIn = funded.balance;

  const tiersAll = await tx.luckyTier.findMany({
    where: { isActive: true },
    orderBy: { multiplier: 'asc' },
    select: { multiplier: true, weightBp: true, minPoolCoins: true },
  });

  // Only tiers the pool can pay right now are in the draw. The losing share
  // absorbs the weight of the excluded ones, so a thin pool means more losses,
  // never a payout the pool cannot honour.
  const eligible = input.isSelfGift
    ? []
    : tiersAll.filter(
        (t) =>
          poolAfterIn >= t.minPoolCoins &&
          poolAfterIn >= BigInt(t.multiplier * input.hostCoins),
      );

  const serverSeed = crypto.randomBytes(16).toString('hex');
  const serverSeedHash = rollHash(serverSeed);
  const point = rollPointFromHash(serverSeedHash);
  const multiplier = multiplierAtPoint(point, eligible);
  const payoutCoins = multiplier * input.hostCoins;

  let poolAfter = poolAfterIn;
  if (payoutCoins > 0) {
    // Conditional debit: the eligibility check above already guarantees this,
    // but the invariant "pool ≥ 0" must not depend on that reasoning holding
    // under every future edit.
    const paid = await tx.luckyPool.updateMany({
      where: { id: 1, balance: { gte: BigInt(payoutCoins) } },
      data: { balance: { decrement: BigInt(payoutCoins) }, totalOut: { increment: BigInt(payoutCoins) } },
    });
    if (paid.count !== 1) throw new Error('lucky: pool could not cover payout');
    poolAfter = poolAfterIn - BigInt(payoutCoins);

    await tx.user.update({
      where: { id: input.senderId },
      data: { coinsBalance: { increment: payoutCoins } },
    });
    await tx.transaction.create({
      data: {
        userId: input.senderId,
        type: 'LUCKY_WIN',
        amountCoins: payoutCoins,
        status: 'completed',
        externalId: input.giftTxId,
      },
    });
  }

  const roll = await tx.luckyRoll.create({
    data: {
      giftTxId: input.giftTxId,
      senderId: input.senderId,
      recipientId: input.recipientId,
      roomId: input.roomId,
      giftCoins: input.giftCoins,
      hostCoins: input.hostCoins,
      multiplier,
      payoutCoins,
      poolBefore,
      poolAfter,
      serverSeed,
      serverSeedHash,
      tiersSnapshot: eligible.map((t) => ({ multiplier: t.multiplier, weightBp: t.weightBp })),
    },
    select: { id: true },
  });

  return { rollId: roll.id, multiplier, payoutCoins, hostCoins: input.hostCoins, poolAfter, serverSeedHash };
}

/** Recompute a stored roll from its seed and snapshot. */
export function verifyRoll(roll: { serverSeed: string; serverSeedHash: string; tiersSnapshot: unknown; multiplier: number }) {
  const hash = rollHash(roll.serverSeed);
  const tiers = Array.isArray(roll.tiersSnapshot) ? (roll.tiersSnapshot as { multiplier: number; weightBp: number }[]) : [];
  const point = rollPointFromHash(hash);
  const multiplier = multiplierAtPoint(point, tiers);
  return {
    hashMatches: hash === roll.serverSeedHash,
    point,
    multiplier,
    matches: hash === roll.serverSeedHash && multiplier === roll.multiplier,
  };
}
