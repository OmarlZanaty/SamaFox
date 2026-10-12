import prisma from '../utils/prisma';
import { awardUserXP, notifyLevelUp } from './xp.service';
import { getGameSettings, naturalMaxMultiplier } from './gameConfig.service';
import {
  PROGRAM_ACCOUNT,
  bpShare,
  creditAccount,
  debitAccount,
  gamePoolAccount,
  normalizeGameKey,
  readBalance,
} from './economyAccounts.service';

const db = prisma as any;

// ============================================================
// اقتصاد الألعاب — GAME ECONOMY (2026-09-26, replaces the platform-funded
// daily prize budget of 2026-09-24)
// ============================================================
// Every game goes through this one module; the engines keep their own maths.
//
//   STAKE  (grantStakeValue, when the stake can no longer be refunded)
//     programShareBp (default 25%) → the PROGRAM account
//     the rest       (default 75%) → that game's prize pool (GAME_POOL:<game>)
//     + the XP the stake buys, as before
//
//   PRIZE  (payPrize)
//     paid ONLY from that game's pool. The program never mints coins to fund a
//     win: a pool that cannot cover a round means the bet is refused up front.
//
// Limits, all server-side and per game (لوحة التحكم ← اقتصاد الألعاب):
//   maxWinPerRound      no single round pays more than this
//   maxPayoutRatio      no round pays more than stake × this (a bug backstop:
//                       an engine that computes a 10,000× win by mistake is cut
//                       to the ratio, and the row is flagged `capped`)
//   dailyMaxWinPerUser  per player, per game, per Cairo day
//   minBet / maxBet / enabled   enforced at the route (gameConfig.gameGuard)
//
// Reservation: before any coin moves the engine asks for the largest prize the
// round could pay. That amount, cut by the caps above, must fit in the pool
// (minus what other rounds in flight have reserved) and in the player's daily
// cap, or the bet is refused with a plain message. So a displayed multiplier is
// paid in full unless a cap applies — and a cap is known before the bet.
// ============================================================

export const HALAL_SETTINGS_KEY = 'halal_games';

export interface HalalSettings {
  /** XP a stake buys per coin — the gift rate unless the owner changes it. */
  xpPerCoin: number;
  /** Legacy fields, still readable by old dashboard pages; no longer enforced. */
  dailyPrizeBudget?: number;
  perUserDailyPrizeCap?: number;
}

const DEFAULTS: HalalSettings = {
  xpPerCoin: Number(process.env.GIFT_XP_PER_COIN ?? 1),
};

const SETTINGS_TTL_MS = 15_000;
let settingsCache: { value: HalalSettings; at: number } | null = null;

export async function getHalalSettings(): Promise<HalalSettings> {
  if (settingsCache && Date.now() - settingsCache.at < SETTINGS_TTL_MS) return settingsCache.value;
  let stored: Partial<HalalSettings> = {};
  try {
    const row = await db.appSetting.findUnique({ where: { key: HALAL_SETTINGS_KEY } });
    if (row?.value) stored = JSON.parse(row.value);
  } catch (e) {
    console.warn('[games] settings read failed, using defaults:', (e as Error).message);
  }
  const value = { ...DEFAULTS, ...stored };
  settingsCache = { value, at: Date.now() };
  return value;
}

export async function setHalalSettings(patch: Partial<HalalSettings>): Promise<HalalSettings> {
  const current = await getHalalSettings();
  const next: HalalSettings = { ...current };
  for (const k of ['dailyPrizeBudget', 'perUserDailyPrizeCap', 'xpPerCoin'] as const) {
    const v = patch[k];
    if (v != null && Number.isFinite(Number(v)) && Number(v) >= 0) (next as any)[k] = Number(v);
  }
  const value = JSON.stringify(next);
  await db.appSetting.upsert({
    where: { key: HALAL_SETTINGS_KEY },
    update: { value },
    create: { key: HALAL_SETTINGS_KEY, value },
  });
  settingsCache = null;
  return next;
}

// ── Day accounting (per player, per game) ───────────────────
const dayFmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' });
export const cairoDay = (d = new Date()) => dayFmt.format(d); // YYYY-MM-DD

interface DayState {
  day: string;
  /** `${game}:${userId}` → prizes already paid today, hydrated from the ledger. */
  paid: Map<string, number>;
}
let dayState: DayState = { day: cairoDay(), paid: new Map() };

function today(): DayState {
  const d = cairoDay();
  if (dayState.day !== d) dayState = { day: d, paid: new Map() };
  return dayState;
}

/** Every ledger spelling of one game ('neon_fortune' and 'neon-fortune'). */
function ledgerGameNames(game: string): string[] {
  const g = normalizeGameKey(game);
  return Array.from(new Set([g, g.replace(/-/g, '_')]));
}

async function userPaidToday(s: DayState, game: string, userId: number): Promise<number> {
  const k = `${normalizeGameKey(game)}:${userId}`;
  if (!s.paid.has(k)) {
    const agg = await db.gameLedger.aggregate({
      where: { day: s.day, kind: 'prize', userId, game: { in: ledgerGameNames(game) } },
      _sum: { amount: true },
    });
    if (!s.paid.has(k)) s.paid.set(k, Number(agg?._sum?.amount ?? 0));
  }
  return s.paid.get(k)!;
}

// ── Reservations ────────────────────────────────────────────
// In memory: the API runs as a single pm2 fork (ecosystem.config.js), and a
// restart drops every round in flight anyway. A reservation that is never
// settled (an engine bug, a crash mid-round) expires instead of pinning the
// pool forever.
interface Reservation {
  userId: number;
  game: string;
  /** The most this round may pay: the engine's max prize cut by every cap. */
  amount: number;
  stake: number | null;
  at: number;
}
const RESERVATION_TTL_MS = 30 * 60_000;
const reservations = new Map<string, Reservation>();
let nextToken = 1;

function sweep() {
  const cutoff = Date.now() - RESERVATION_TTL_MS;
  for (const [k, r] of reservations) if (r.at < cutoff) reservations.delete(k);
}

function reservedTotals(game: string, userId: number) {
  const g = normalizeGameKey(game);
  let pool = 0;
  let mine = 0;
  for (const r of reservations.values()) {
    if (normalizeGameKey(r.game) !== g) continue;
    pool += r.amount;
    if (r.userId === userId) mine += r.amount;
  }
  return { pool, mine };
}

export type ReserveCode = 'PRIZE_POOL_LOW' | 'PRIZE_FUND_EMPTY' | 'PRIZE_CAP_REACHED' | 'DAILY_WIN_CAP';
export type ReserveResult =
  | { ok: true; token: string; cap: number }
  | { ok: false; code: ReserveCode; message: string };

/**
 * The most a round may pay, given what the engine says it could pay and the
 * admin's caps. `stake` enables the payout-ratio cap.
 */
export async function prizeCapFor(game: string, maxPrize: number, stake?: number | null): Promise<number> {
  const s = await getGameSettings(normalizeGameKey(game));
  let cap = Math.max(0, Math.ceil(maxPrize));
  if (s.maxWinPerRound != null && s.maxWinPerRound >= 0) cap = Math.min(cap, s.maxWinPerRound);
  if (stake != null && stake > 0) {
    const ratio = s.maxPayoutRatio ?? naturalMaxMultiplier(normalizeGameKey(game));
    if (ratio != null && ratio > 0) cap = Math.min(cap, Math.floor(stake * ratio));
  }
  return cap;
}

// Reservations are checked and taken synchronously after the awaits, so two
// bets racing through the reads cannot both claim the last of the pool.
export async function reservePrize(
  userId: number,
  game: string,
  maxPrize: number,
  stake?: number | null,
): Promise<ReserveResult> {
  const settings = await getGameSettings(normalizeGameKey(game));
  const cap = await prizeCapFor(game, maxPrize, stake);
  const s = today();
  const paidMine = await userPaidToday(s, game, userId);
  const pool = Number((await readBalance(prisma, gamePoolAccount(game))) ?? 0n);

  sweep();
  const held = reservedTotals(game, userId);
  if (settings.dailyMaxWinPerUser != null && paidMine + held.mine + cap > settings.dailyMaxWinPerUser) {
    return {
      ok: false,
      code: 'DAILY_WIN_CAP',
      message: 'وصلت للحد اليومي لمكاسبك في هذه اللعبة — قلّل المبلغ أو ارجع بكرة',
    };
  }
  if (held.pool + cap > pool) {
    return {
      ok: false,
      code: 'PRIZE_POOL_LOW',
      message: 'صندوق جوائز اللعبة لا يغطي هذا الرهان حالياً — قلّل المبلغ أو حاول لاحقاً',
    };
  }

  const token = `${normalizeGameKey(game)}:${userId}:${nextToken++}`;
  reservations.set(token, { userId, game, amount: cap, stake: stake ?? null, at: Date.now() });
  return { ok: true, token, cap };
}

/** The round ended without a prize (a loss, a refund, a cancelled bet). */
export function releasePrize(token: string | null | undefined): void {
  if (token) reservations.delete(token);
}

export interface PayResult {
  /** What actually reached the player's balance. */
  paid: number;
  /** What the engine computed. */
  requested: number;
  /** A cap (round max, payout ratio, pool) cut the prize. */
  capped: boolean;
  /** The player's balance after the credit, when a credit happened. */
  balance: number | null;
}

/**
 * Pay a prize from the game's pool — debit the pool, credit the player, and
 * book the ledger row — in ONE transaction. Replaces "credit the user, then
 * settlePrize()" in every engine.
 */
export async function payPrize(
  token: string | null | undefined | Array<string | null | undefined>,
  userId: number,
  game: string,
  prize: number,
  ref?: string,
  stake?: number | null,
): Promise<PayResult> {
  // A round where the player bet several times holds one reservation per bet;
  // together they cover the round, so they are pooled here.
  const tokens = (Array.isArray(token) ? token : [token]).filter((t): t is string => !!t);
  let reservedAmount: number | null = null;
  let reservedStake: number | null = null;
  for (const t of tokens) {
    const r = reservations.get(t);
    reservations.delete(t);
    if (!r) continue;
    reservedAmount = (reservedAmount ?? 0) + r.amount;
    if (r.stake != null) reservedStake = (reservedStake ?? 0) + r.stake;
  }

  const requested = Math.max(0, Math.floor(prize));
  if (requested <= 0) return { paid: 0, requested: 0, capped: false, balance: null };

  const effStake = stake ?? reservedStake;
  const ruleCap = await prizeCapFor(game, requested, effStake);
  const cap = reservedAmount != null ? Math.min(reservedAmount, ruleCap) : ruleCap;
  let amount = Math.min(requested, cap);
  let capped = amount < requested;
  const account = gamePoolAccount(game);
  const s = today();

  const out = await prisma.$transaction(async (tx) => {
    let debited = amount > 0 ? await debitAccount(tx, account, amount, { kind: 'GAME_PRIZE', refType: game, refId: ref ?? null, userId }) : 0n;
    if (debited === null) {
      // The reservation should have made this impossible. Pay what the pool
      // holds rather than mint the rest, and flag it.
      const bal = Number((await readBalance(tx, account)) ?? 0n);
      amount = Math.max(0, Math.min(amount, bal));
      capped = true;
      debited = amount > 0 ? await debitAccount(tx, account, amount, { kind: 'GAME_PRIZE', refType: game, refId: ref ?? null, userId }) : 0n;
      if (debited === null) amount = 0;
    }
    let balance: number | null = null;
    if (amount > 0) {
      const u = await (tx as any).user.update({
        where: { id: userId },
        data: { coinsBalance: { increment: amount } },
        select: { coinsBalance: true },
      });
      balance = u?.coinsBalance ?? null;
    }
    await (tx as any).gameLedger.create({
      data: { userId, game, kind: 'prize', amount, xp: 0, ref: ref ?? null, day: s.day, requested, capped },
    });
    return { balance };
  });

  if (capped) console.warn('[games] prize capped', { userId, game, requested, paid: amount, ref });
  const k = `${normalizeGameKey(game)}:${userId}`;
  if (s.paid.has(k)) s.paid.set(k, s.paid.get(k)! + amount);
  return { paid: amount, requested, capped, balance: out.balance };
}

/**
 * Legacy seam: book a prize some other code already credited. Every engine now
 * pays through [payPrize]; this stays only so an out-of-tree caller cannot
 * leave a reservation pinned.
 */
export function settlePrize(token: string | null | undefined, _userId: number, _game: string, _prize: number, _ref?: string): void {
  if (token) reservations.delete(token);
}

// ── The stake ───────────────────────────────────────────────
/**
 * The stake is final: split it between the PROGRAM and the game's pool (one
 * transaction with its ledger row), then deliver the XP it bought. Called once
 * per stake, when it can no longer be refunded (takeoff, round close, or the
 * instant a one-shot game charges). Never throws — the coins have already
 * moved; a failure is logged for follow-up.
 */
export async function grantStakeValue(userId: number, game: string, stake: number, ref?: string): Promise<number> {
  const amount = Math.max(0, Math.floor(stake));
  if (amount <= 0) return 0;
  const [settings, gs] = await Promise.all([getHalalSettings(), getGameSettings(normalizeGameKey(game))]);
  const xp = Math.floor(amount * settings.xpPerCoin);
  const programShare = bpShare(amount, gs.programShareBp);
  const poolShare = amount - programShare;

  try {
    await prisma.$transaction(async (tx) => {
      await (tx as any).gameLedger.create({
        data: { userId, game, kind: 'stake', amount, xp, ref: ref ?? null, day: today().day, programShare, poolShare },
      });
      await creditAccount(tx, PROGRAM_ACCOUNT, programShare, { kind: 'GAME_STAKE_PROGRAM', refType: game, refId: ref ?? null, userId });
      await creditAccount(tx, gamePoolAccount(game), poolShare, { kind: 'GAME_STAKE_POOL', refType: game, refId: ref ?? null, userId });
    });
  } catch (e) {
    console.error('[games] stake split failed', { userId, game, amount, e: (e as Error).message });
  }

  if (xp > 0) {
    const r: any = await awardUserXP(userId, xp);
    if (r?.success && r.leveledUp) {
      await notifyLevelUp(userId, r.level, r.grantedItemIds?.length ?? 0);
    } else if (!r?.success) {
      console.error('[games] stake XP not delivered', { userId, game, amount, xp, error: r?.error });
    }
  }
  return xp;
}

/**
 * An engine refunded a stake it had already split (a failure after the
 * charge). Put the split back so the pool and the program never keep money a
 * player got back.
 */
export async function revokeStakeValue(userId: number, game: string, stake: number, ref?: string): Promise<void> {
  const amount = Math.max(0, Math.floor(stake));
  if (amount <= 0) return;
  const gs = await getGameSettings(normalizeGameKey(game));
  const programShare = bpShare(amount, gs.programShareBp);
  const poolShare = amount - programShare;
  try {
    await prisma.$transaction(async (tx) => {
      await (tx as any).gameLedger.create({
        data: { userId, game, kind: 'refund', amount: -amount, xp: 0, ref: ref ?? null, day: today().day, programShare: -programShare, poolShare: -poolShare },
      });
      await debitAccount(tx, PROGRAM_ACCOUNT, programShare, { kind: 'GAME_STAKE_REFUND', refType: game, refId: ref ?? null, userId }, { allowNegative: true });
      await debitAccount(tx, gamePoolAccount(game), poolShare, { kind: 'GAME_STAKE_REFUND', refType: game, refId: ref ?? null, userId }, { allowNegative: true });
    });
  } catch (e) {
    console.error('[games] stake revoke failed', { userId, game, amount, e: (e as Error).message });
  }
}

// ── الصعوبة ─────────────────────────────────────────────────
/**
 * Scale a slot paytable by one factor, rounding every entry DOWN to what the
 * app's paytable screens print (two decimals under 10×, whole numbers from
 * 10×). The table sent to the client is this scaled one, so the paytable a
 * player reads is exactly the paytable that pays.
 */
export function scalePaytable<K extends string>(
  table: Record<K, [number, number, number]>,
  factor: number,
): Record<K, [number, number, number]> {
  const f = Math.min(1, Math.max(0, factor));
  const round = (v: number) => (v >= 10 ? Math.floor(v + 1e-9) : Math.floor(v * 100 + 1e-9) / 100);
  const out = {} as Record<K, [number, number, number]>;
  for (const k of Object.keys(table) as K[]) {
    out[k] = table[k].map((v) => round(v * f)) as [number, number, number];
  }
  return out;
}

/** Today's totals for لوحة التحكم. */
export async function getHalalToday() {
  const s = today();
  const [stakes, prizes] = await Promise.all([
    db.gameLedger.aggregate({ where: { day: s.day, kind: 'stake' }, _sum: { amount: true, xp: true }, _count: true }),
    db.gameLedger.aggregate({ where: { day: s.day, kind: 'prize' }, _sum: { amount: true }, _count: true }),
  ]);
  sweep();
  let reserved = 0;
  for (const r of reservations.values()) reserved += r.amount;
  return {
    day: s.day,
    stakes: Number(stakes?._sum?.amount ?? 0),
    xpDelivered: Number(stakes?._sum?.xp ?? 0),
    stakeCount: Number(stakes?._count ?? 0),
    prizesPaid: Number(prizes?._sum?.amount ?? 0),
    prizeCount: Number(prizes?._count ?? 0),
    reservedNow: reserved,
  };
}

/** Held right now against one game's pool, for the dashboard. */
export function reservedForGame(game: string): number {
  sweep();
  return reservedTotals(game, -1).pool;
}

/** The player-facing summary of the rules, for rules screens. */
export async function describeHalalTerms() {
  const s = await getHalalSettings();
  return {
    xpPerCoin: s.xpPerCoin,
    text:
      `كل عملة تدفعها في اللعبة تضيف ${s.xpPerCoin} XP لمستواك فورًا. ` +
      'الجوائز تُدفع من صندوق جوائز اللعبة الممول من مشاركات اللاعبين، ' +
      'ولكل لعبة حد أقصى للمكسب في الجولة وفي اليوم.',
  };
}

/** Test hook: forget all in-memory state. */
export function __resetHalalForTests() {
  reservations.clear();
  settingsCache = null;
  dayState = { day: cairoDay(), paid: new Map() };
}
