import { AsyncLocalStorage } from 'async_hooks';
import type { NextFunction, Request, Response } from 'express';
import prisma from './prisma';

/**
 * تجميد الكوينزات — 2026-10-01, client:
 *
 *   «اجمد كوينزات المستخدمين، محدش يعرف يستخدم الكوينزات في اي شي.
 *    افك التجميد يرجع كما كان. وكمان اجمد مستخدم بالايدي لوحده.»
 *   «التجميد فى لوحة التحكم بس.»
 *
 * Same two layers as the target freeze (targetLock.ts), both driven only from
 * the admin dashboard:
 *   1. a GLOBAL switch that freezes every account's coins at once;
 *   2. a per-user list, for freezing single accounts by id.
 *
 * Unlike the target freeze, a missing row means NOT frozen: this is a new
 * control, and shipping it must not stop a single gift until the owner turns
 * it on.
 *
 * WHAT "FROZEN" MEANS: the balance stays exactly where it is, and nothing can
 * take coins out of it — gifts, games, store, VIP, CP, paid DMs, anything.
 * Unfreezing simply lets spending resume; nothing is moved or recalculated.
 * Coins can still ARRIVE (a gift received, a game round already in play paying
 * out) — the freeze is on using coins, not on owning them.
 *
 * WHERE IT IS ENFORCED: not route by route. There are ~25 places that spend
 * coins and more will come, so the check sits under all of them, on the one
 * operation they share — a `coinsBalance: { decrement }` on a user row — via
 * the Prisma query extension in prisma.ts. A path somebody adds next month is
 * frozen too without anyone remembering this file.
 *
 * Two deliberate exemptions, both declared at their call site with
 * [runWithCoinFreezeBypass]:
 *   - 'all'    — the admin removing coins from an account (removeCoins). An
 *                admin correction is not the user spending.
 *   - 'global' — a charging agent selling coins to a user. The platform-wide
 *                freeze stops USE, not sales; an agent frozen by id is still
 *                stopped.
 */

const GLOBAL_KEY = 'coins_frozen_global';
const USERS_KEY = 'coins_frozen_user_ids';

export const COINS_FROZEN_GLOBAL_MESSAGE =
  'الكوينزات مجمدة حالياً من قِبَل الإدارة — لا يمكن استخدامها لحين فك التجميد';
export const COINS_FROZEN_MESSAGE =
  'تم تجميد الكوينزات في حسابك من قِبَل الإدارة — لا يمكن استخدامها لحين فك التجميد';

export class CoinsFrozenError extends Error {
  readonly code = 'COINS_FROZEN';
  readonly status = 403;
  constructor(message: string) {
    super(message);
    this.name = 'CoinsFrozenError';
  }
}

interface CoinFreezePolicy {
  globallyFrozen: boolean;
  frozenUserIds: Set<number>;
}

function parseIds(raw: unknown): Set<number> {
  const text = String(raw ?? '').trim();
  if (!text) return new Set();
  return new Set(
    text
      .split(',')
      .map((s) => Number(s.trim()))
      .filter((n) => Number.isInteger(n) && n > 0),
  );
}

function parseBool(raw: unknown): boolean {
  return ['1', 'true', 'yes', 'on', 'frozen'].includes(String(raw ?? '').trim().toLowerCase());
}

// Every coin spend reads this, so it is cached briefly. Writes from the
// dashboard clear it, so a freeze takes effect on the next spend on this
// process; the TTL only bounds how stale another process can be.
const CACHE_TTL_MS = 3000;
let cached: { policy: CoinFreezePolicy; at: number } | null = null;

async function readPolicy(): Promise<CoinFreezePolicy> {
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.policy;
  try {
    const rows = await (prisma as any).appSetting.findMany({
      where: { key: { in: [GLOBAL_KEY, USERS_KEY] } },
    });
    const byKey = new Map<string, any>(rows.map((r: any) => [r.key, r.value]));
    const policy = {
      globallyFrozen: parseBool(byKey.get(GLOBAL_KEY)),
      frozenUserIds: parseIds(byKey.get(USERS_KEY)),
    };
    cached = { policy, at: Date.now() };
    return policy;
  } catch (e) {
    // Fail OPEN, as the target freeze does: a settings-table blip must not
    // stop every gift on the platform.
    console.warn('[coinFreeze] lookup failed, allowing:', (e as Error).message);
    return { globallyFrozen: false, frozenUserIds: new Set() };
  }
}

function invalidate(): void {
  cached = null;
}

type BypassMode = 'all' | 'global';

interface CoinFreezeContext {
  bypass?: BypassMode;
  /** Set when a spend in this request was refused — see coinFreezeResponses. */
  refused?: string;
}

const context = new AsyncLocalStorage<CoinFreezeContext>();

/** Run [fn] with the freeze relaxed. See the class comment for who may. */
export function runWithCoinFreezeBypass<T>(mode: BypassMode, fn: () => Promise<T>): Promise<T> {
  const outer = context.getStore();
  return context.run({ ...outer, bypass: mode }, fn);
}

/** Why [userId] may not spend coins right now, or null when he may. */
export async function coinFreezeReason(userId: number, bypass?: BypassMode): Promise<string | null> {
  if (!userId || bypass === 'all') return null;
  const policy = await readPolicy();
  if (policy.frozenUserIds.has(userId)) return COINS_FROZEN_MESSAGE;
  if (policy.globallyFrozen && bypass !== 'global') return COINS_FROZEN_GLOBAL_MESSAGE;
  return null;
}

/** Throws [CoinsFrozenError] when [userId]'s coins are frozen. */
export async function assertCoinsNotFrozen(userId: number): Promise<void> {
  const reason = await coinFreezeReason(userId, context.getStore()?.bypass);
  if (reason) throw new CoinsFrozenError(reason);
}

function positive(v: unknown): boolean {
  if (typeof v === 'bigint') return v > BigInt(0);
  const n = Number(v);
  return Number.isFinite(n) && n > 0;
}

/**
 * The guard the Prisma extension runs before every user update. Only a real
 * spend is checked: a positive `coinsBalance.decrement` on a row named by id.
 * (A negative decrement is an increment and is let through.)
 */
export async function guardCoinDecrement(args: any): Promise<void> {
  const dec = args?.data?.coinsBalance?.decrement;
  if (dec === undefined || !positive(dec)) return;
  const raw = args?.where?.id;
  const userId = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isInteger(userId) || userId <= 0) return;
  const store = context.getStore();
  const reason = await coinFreezeReason(userId, store?.bypass);
  if (!reason) return;
  if (store) store.refused = reason;
  throw new CoinsFrozenError(reason);
}

/**
 * Express middleware, mounted before the routes. Every handler maps errors its
 * own way — most turn an unknown one into «Internal error» or «فشل» — so a
 * frozen user would be told something broke. When a spend in this request was
 * refused by the freeze and the handler answers with an error, the answer is
 * replaced with the freeze message and 403, whichever handler it was.
 */
export function coinFreezeResponses(_req: Request, res: Response, next: NextFunction): void {
  const store: CoinFreezeContext = {};
  const json = res.json.bind(res);
  res.json = ((body: unknown) => {
    if (store.refused && res.statusCode >= 400) {
      res.status(403);
      return json({ success: false, ok: false, code: 'COINS_FROZEN', message: store.refused });
    }
    return json(body);
  }) as Response['json'];
  context.run(store, () => next());
}

// --------------------------------------------------------------- dashboard

export async function getCoinFreezePolicy(): Promise<{ globallyFrozen: boolean; frozenUserIds: number[] }> {
  invalidate();
  const p = await readPolicy();
  return { globallyFrozen: p.globallyFrozen, frozenUserIds: [...p.frozenUserIds].sort((a, b) => a - b) };
}

export async function setCoinsGloballyFrozen(frozen: boolean): Promise<boolean> {
  const value = frozen ? '1' : '0';
  await (prisma as any).appSetting.upsert({
    where: { key: GLOBAL_KEY },
    update: { value },
    create: { key: GLOBAL_KEY, value },
  });
  invalidate();
  return frozen;
}

export async function setUserCoinsFrozen(userId: number, frozen: boolean): Promise<number[]> {
  invalidate();
  const { frozenUserIds: ids } = await readPolicy();
  if (frozen) ids.add(userId);
  else ids.delete(userId);
  const value = [...ids].sort((a, b) => a - b).join(',');
  await (prisma as any).appSetting.upsert({
    where: { key: USERS_KEY },
    update: { value },
    create: { key: USERS_KEY, value },
  });
  invalidate();
  return [...ids].sort((a, b) => a - b);
}
