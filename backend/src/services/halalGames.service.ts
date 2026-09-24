import prisma from '../utils/prisma';
import { awardUserXP, notifyLevelUp } from './xp.service';

const db = prisma as any;

// ============================================================
// الألعاب الحلال — العِوَض + الجائزة
// ============================================================
// Every game used to be a wager: the stake went into a pot and the winner was
// paid out of what the losers put in. That is قمار. This service is the one
// place every engine goes through to make each round two separate, honest
// transactions instead:
//
//   1. العِوَض — the stake is a PURCHASE. It buys XP at exactly the rate a
//      gift of the same coins buys (GIFT_XP_PER_COIN), and that XP is delivered
//      the moment the stake becomes final — before the result is known. The
//      player always receives full value for what they paid, win or lose.
//
//   2. الجائزة — a win is a PRIZE from the platform's own prize fund: a daily
//      budget the owner sets, not money collected from other players. Nobody's
//      coins ever go to another player.
//
// A prize is only promised when the fund can honour it: before a stake is
// taken the engine reserves the largest prize the round could pay. If the
// fund or the player's daily cap cannot cover it, the bet is refused up front
// with a plain message — never accepted and then shorted. Every multiplier a
// player sees is paid in full.
//
// The ledger (game_ledger) records every stake and every prize, so the whole
// arrangement can be audited line by line.
// ============================================================

export const HALAL_SETTINGS_KEY = 'halal_games';

export interface HalalSettings {
  /** Total prizes the platform funds across all games per day (Cairo time). */
  dailyPrizeBudget: number;
  /** Prizes a single player can receive per day. */
  perUserDailyPrizeCap: number;
  /** XP a stake buys per coin — the gift rate unless the owner changes it. */
  xpPerCoin: number;
}

const DEFAULTS: HalalSettings = {
  dailyPrizeBudget: Number(process.env.HALAL_DAILY_PRIZE_BUDGET ?? 2_000_000_000),
  perUserDailyPrizeCap: Number(process.env.HALAL_USER_DAILY_PRIZE_CAP ?? 200_000_000),
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
    console.warn('[halal] settings read failed, using defaults:', (e as Error).message);
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
    if (v != null && Number.isFinite(Number(v)) && Number(v) >= 0) next[k] = Number(v);
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

// ── Day accounting ──────────────────────────────────────────
const dayFmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' });
export const cairoDay = (d = new Date()) => dayFmt.format(d); // YYYY-MM-DD

interface DayState {
  day: string;
  /** Prizes already paid today, hydrated from the ledger once per day. */
  paid: number | null;
  paidByUser: Map<number, number>;
}
let dayState: DayState = { day: cairoDay(), paid: null, paidByUser: new Map() };

function today(): DayState {
  const d = cairoDay();
  if (dayState.day !== d) dayState = { day: d, paid: null, paidByUser: new Map() };
  return dayState;
}

async function paidToday(s: DayState): Promise<number> {
  if (s.paid == null) {
    const agg = await db.gameLedger.aggregate({
      where: { day: s.day, kind: 'prize' },
      _sum: { amount: true },
    });
    // Another call may have hydrated while this one awaited.
    if (s.paid == null) s.paid = Number(agg?._sum?.amount ?? 0);
  }
  return s.paid!;
}

async function userPaidToday(s: DayState, userId: number): Promise<number> {
  if (!s.paidByUser.has(userId)) {
    const agg = await db.gameLedger.aggregate({
      where: { day: s.day, kind: 'prize', userId },
      _sum: { amount: true },
    });
    if (!s.paidByUser.has(userId)) s.paidByUser.set(userId, Number(agg?._sum?.amount ?? 0));
  }
  return s.paidByUser.get(userId)!;
}

// ── Reservations ────────────────────────────────────────────
// In memory: the API runs as a single pm2 fork (ecosystem.config.js), and a
// restart drops every round in flight anyway. A reservation that is never
// settled (an engine bug, a crash mid-round) expires instead of pinning the
// fund forever.
interface Reservation {
  userId: number;
  game: string;
  amount: number;
  at: number;
}
const RESERVATION_TTL_MS = 30 * 60_000;
const reservations = new Map<string, Reservation>();
let nextToken = 1;

function sweep() {
  const cutoff = Date.now() - RESERVATION_TTL_MS;
  for (const [k, r] of reservations) if (r.at < cutoff) reservations.delete(k);
}

function reservedTotals(userId: number) {
  let all = 0;
  let mine = 0;
  for (const r of reservations.values()) {
    all += r.amount;
    if (r.userId === userId) mine += r.amount;
  }
  return { all, mine };
}

export type ReserveResult =
  | { ok: true; token: string }
  | { ok: false; code: 'PRIZE_FUND_EMPTY' | 'PRIZE_CAP_REACHED'; message: string };

// Reservations are checked and taken synchronously after the awaits, so two
// bets racing through the hydration queries cannot both claim the last room.
export async function reservePrize(userId: number, game: string, maxPrize: number): Promise<ReserveResult> {
  const amount = Math.max(0, Math.ceil(maxPrize));
  const settings = await getHalalSettings();
  const s = today();
  const paid = await paidToday(s);
  const mine = await userPaidToday(s, userId);

  sweep();
  const held = reservedTotals(userId);
  if (paid + held.all + amount > settings.dailyPrizeBudget) {
    return {
      ok: false,
      code: 'PRIZE_FUND_EMPTY',
      message: 'جوائز الألعاب لليوم خلصت — ارجع بكرة، أو قلّل المبلغ',
    };
  }
  if (mine + held.mine + amount > settings.perUserDailyPrizeCap) {
    return {
      ok: false,
      code: 'PRIZE_CAP_REACHED',
      message: 'وصلت للحد اليومي لجوائزك في الألعاب — قلّل المبلغ أو ارجع بكرة',
    };
  }

  const token = `${game}:${userId}:${nextToken++}`;
  reservations.set(token, { userId, game, amount, at: Date.now() });
  return { ok: true, token };
}

/** The round ended without a prize (a loss, a refund, a cancelled bet). */
export function releasePrize(token: string | null | undefined): void {
  if (token) reservations.delete(token);
}

/**
 * The round paid `prize`. The engine credits the coins itself (inside its own
 * write); this closes the reservation and books the prize to the ledger.
 */
export function settlePrize(token: string | null | undefined, userId: number, game: string, prize: number, ref?: string): void {
  if (token) reservations.delete(token);
  const amount = Math.max(0, Math.floor(prize));
  if (amount <= 0) return;

  const s = today();
  if (s.paid != null) s.paid += amount;
  if (s.paidByUser.has(userId)) s.paidByUser.set(userId, s.paidByUser.get(userId)! + amount);

  db.gameLedger
    .create({ data: { userId, game, kind: 'prize', amount, xp: 0, ref: ref ?? null, day: s.day } })
    .catch((e: Error) => console.error('[halal] prize ledger write failed', { userId, game, amount, e: e.message }));
}

// ── العِوَض ──────────────────────────────────────────────────
/**
 * The stake is final: deliver what it bought. Called once per stake, when it
 * can no longer be refunded (takeoff, round close, or the instant a one-shot
 * game charges). Never throws — a failed XP write must not void a bet whose
 * coins have already moved; it is logged for follow-up instead.
 */
export async function grantStakeValue(userId: number, game: string, stake: number, ref?: string): Promise<number> {
  const amount = Math.max(0, Math.floor(stake));
  if (amount <= 0) return 0;
  const settings = await getHalalSettings();
  const xp = Math.floor(amount * settings.xpPerCoin);

  try {
    await db.gameLedger.create({
      data: { userId, game, kind: 'stake', amount, xp, ref: ref ?? null, day: today().day },
    });
  } catch (e) {
    console.error('[halal] stake ledger write failed', { userId, game, amount, e: (e as Error).message });
  }

  if (xp > 0) {
    const r: any = await awardUserXP(userId, xp);
    if (r?.success && r.leveledUp) {
      await notifyLevelUp(userId, r.level, r.grantedItemIds?.length ?? 0);
    } else if (!r?.success) {
      console.error('[halal] stake XP not delivered', { userId, game, amount, xp, error: r?.error });
    }
  }
  return xp;
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

/** Today's totals for لوحة التحكم: what stakes bought, what the fund paid. */
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

/** The player-facing summary of what the stake buys, for rules screens. */
export async function describeHalalTerms() {
  const s = await getHalalSettings();
  return {
    xpPerCoin: s.xpPerCoin,
    perUserDailyPrizeCap: s.perUserDailyPrizeCap,
    text:
      `كل عملة تدفعها في اللعبة تشتري ${s.xpPerCoin} XP لمستواك فورًا، بنفس سعر الهدايا — ` +
      'ده مقابل كامل لفلوسك سواء كسبت أو لا. والفوز جائزة من صندوق جوائز المنصة، ' +
      'مش من فلوس لاعبين تانيين.',
  };
}

/** Test hook: forget all in-memory state. */
export function __resetHalalForTests() {
  reservations.clear();
  settingsCache = null;
  dayState = { day: cairoDay(), paid: null, paidByUser: new Map() };
}
