import prisma from '../utils/prisma';

/**
 * صلاحيات فتح CP (2026-09-22).
 *
 * "Opening CP" = the right to send a CP invitation and so create a pair.
 * Before this file existed it was implicitly free for everyone. Now every
 * `POST /cp/requests` runs `assertCpUnlocked`, which the server enforces no
 * matter what the app does ("يجب التحقق من الصلاحية من السيرفر").
 *
 * Who pays what is decided by `resolveCpUnlockPolicy`:
 *   1. a per-user grant (cp_unlock_grants) wins — FREE, or FEE with its own
 *      price ("يمكن تحديد الرسوم لكل مستخدم");
 *   2. otherwise the system policy in app_settings — cp_unlock_mode
 *      (free | fee) and cp_unlock_fee_coins ("أو وفق سياسة النظام").
 *
 * The fee is quoted by `getCpUnlockStatus` so the app shows it BEFORE the
 * user confirms, and taken by `confirmCpUnlock` in one transaction with a
 * guarded decrement: either the coins leave, the Transaction row is written
 * and the cp_unlocks row exists — or none of it happens. Insufficient balance
 * is a 402 with the shortfall and nothing is deducted.
 *
 * Every function takes its Prisma client as the last argument so the tests
 * can run against an in-memory fake; production callers omit it.
 */

export class CpError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 400,
    public data?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export type CpUnlockMode = 'free' | 'fee';

/** app_settings keys and the defaults that keep today's behaviour. */
export const CP_UNLOCK_SETTING_DEFAULTS: Record<string, string> = {
  cp_unlock_mode: 'free', // free | fee — free == exactly what existed before
  cp_unlock_fee_coins: '0',
  cp_level_step_coins: '0', // 0 = legacy days-based ladder
  cp_level_max: '5',
  cp_level_names: '', // JSON array or "a,b,c"; empty = built-in Arabic names
};

export interface CpUnlockSettings {
  unlockMode: CpUnlockMode;
  unlockFeeCoins: number;
  levelStepCoins: number;
  levelMax: number;
  levelNames: string[];
}

export const CP_LEVEL_NAMES_DEFAULT = ['بداية حب', 'حب حلو', 'حب كبير', 'حب خالد', 'روح واحدة'];
/** Days needed for each level when cp_level_step_coins is 0 (the app's old ladder). */
export const CP_LEVEL_DAYS_LADDER = [0, 7, 30, 90, 365];

const clampInt = (v: unknown, min: number, max: number, fallback: number): number => {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
};

export function parseLevelNames(raw: string | null | undefined): string[] {
  const s = String(raw ?? '').trim();
  if (!s) return [...CP_LEVEL_NAMES_DEFAULT];
  try {
    const arr = JSON.parse(s);
    if (Array.isArray(arr)) {
      const names = arr.map((x) => String(x).trim()).filter(Boolean);
      if (names.length) return names;
    }
  } catch {
    /* comma list */
  }
  const names = s.split(',').map((x) => x.trim()).filter(Boolean);
  return names.length ? names : [...CP_LEVEL_NAMES_DEFAULT];
}

export async function readCpSettings(db: any = prisma): Promise<CpUnlockSettings> {
  const keys = Object.keys(CP_UNLOCK_SETTING_DEFAULTS);
  const rows: Array<{ key: string; value: string }> = await db.appSetting.findMany({ where: { key: { in: keys } } });
  const merged: Record<string, string> = { ...CP_UNLOCK_SETTING_DEFAULTS };
  for (const r of rows) merged[r.key] = r.value;
  const mode = String(merged.cp_unlock_mode).toLowerCase() === 'fee' ? 'fee' : 'free';
  return {
    unlockMode: mode,
    unlockFeeCoins: clampInt(merged.cp_unlock_fee_coins, 0, 2_000_000_000, 0),
    levelStepCoins: clampInt(merged.cp_level_step_coins, 0, 2_000_000_000, 0),
    levelMax: clampInt(merged.cp_level_max, 1, 999, 5),
    levelNames: parseLevelNames(merged.cp_level_names),
  };
}

// ---------------------------------------------------------------------------
// Level
// ---------------------------------------------------------------------------

export interface CpLevelInput {
  cpValue: number;
  createdAt: Date | string;
  levelOverride?: number | null;
}

export interface CpLevelResult {
  level: number;
  levelName: string;
  cpValue: number;
  days: number;
  /** cpValue needed for the next level; null when maxed or days-based. */
  nextLevelAt: number | null;
  /** 'override' | 'coins' | 'days' */
  basis: 'override' | 'coins' | 'days';
}

export function daysSince(d: Date | string, now = Date.now()): number {
  const t = new Date(d).getTime();
  if (!Number.isFinite(t)) return 0;
  return Math.max(0, Math.floor((now - t) / 86_400_000));
}

/**
 * The level of a pair.
 *   levelOverride set    → that level (admin pinned it)
 *   cp_level_step_coins  → 1 + floor(cpValue / step), capped at cp_level_max
 *   otherwise            → the days ladder the app has always used
 */
export function computeCpLevel(pair: CpLevelInput, cfg: CpUnlockSettings, now = Date.now()): CpLevelResult {
  const days = daysSince(pair.createdAt, now);
  const cpValue = Math.max(0, Math.floor(Number(pair.cpValue) || 0));
  const max = Math.max(1, cfg.levelMax);
  const nameFor = (lvl: number) => cfg.levelNames[Math.min(cfg.levelNames.length, lvl) - 1] ?? `LV.${lvl}`;

  if (pair.levelOverride != null && Number.isFinite(Number(pair.levelOverride))) {
    const level = clampInt(pair.levelOverride, 1, max, 1);
    return { level, levelName: nameFor(level), cpValue, days, nextLevelAt: null, basis: 'override' };
  }
  if (cfg.levelStepCoins > 0) {
    const level = Math.min(max, 1 + Math.floor(cpValue / cfg.levelStepCoins));
    const nextLevelAt = level >= max ? null : level * cfg.levelStepCoins;
    return { level, levelName: nameFor(level), cpValue, days, nextLevelAt, basis: 'coins' };
  }
  let level = 1;
  for (let i = 0; i < CP_LEVEL_DAYS_LADDER.length; i++) {
    if (days >= (CP_LEVEL_DAYS_LADDER[i] ?? 0)) level = i + 1;
  }
  level = Math.min(max, level);
  return { level, levelName: nameFor(level), cpValue, days, nextLevelAt: null, basis: 'days' };
}

// ---------------------------------------------------------------------------
// Policy
// ---------------------------------------------------------------------------

export interface CpUnlockPolicy {
  mode: CpUnlockMode;
  feeCoins: number;
  /** 'grant' when a per-user row decided, 'system' otherwise. */
  policySource: 'grant' | 'system';
  grant: { id: number; mode: string; feeCoins: number; note: string | null; grantedById: number; grantedAt: Date } | null;
}

export async function resolveCpUnlockPolicy(userId: number, db: any = prisma): Promise<CpUnlockPolicy> {
  const grant = await db.cpUnlockGrant.findUnique({ where: { userId } });
  if (grant) {
    const mode: CpUnlockMode = String(grant.mode).toUpperCase() === 'FEE' ? 'fee' : 'free';
    return {
      mode,
      feeCoins: mode === 'fee' ? Math.max(0, Math.floor(Number(grant.feeCoins) || 0)) : 0,
      policySource: 'grant',
      grant,
    };
  }
  const s = await readCpSettings(db);
  return {
    mode: s.unlockMode,
    feeCoins: s.unlockMode === 'fee' ? s.unlockFeeCoins : 0,
    policySource: 'system',
    grant: null,
  };
}

export interface CpUnlockStatus {
  unlocked: boolean;
  unlockedAt: Date | null;
  paidCoins: number;
  unlockSource: string | null;
  mode: CpUnlockMode;
  feeCoins: number;
  policySource: 'grant' | 'system';
  balance: number;
  /** coins missing to pay the fee; 0 when affordable or free. */
  shortfall: number;
}

/** What the app shows before the user confirms — the fee and whether he can pay it. */
export async function getCpUnlockStatus(userId: number, db: any = prisma): Promise<CpUnlockStatus> {
  const [unlock, policy, user] = await Promise.all([
    db.cpUnlock.findUnique({ where: { userId } }),
    resolveCpUnlockPolicy(userId, db),
    db.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } }),
  ]);
  const balance = Number(user?.coinsBalance ?? 0);
  const feeCoins = unlock ? 0 : policy.feeCoins;
  return {
    unlocked: !!unlock,
    unlockedAt: unlock?.createdAt ?? null,
    paidCoins: Number(unlock?.paidCoins ?? 0),
    unlockSource: unlock?.source ?? null,
    mode: policy.mode,
    feeCoins,
    policySource: policy.policySource,
    balance,
    shortfall: Math.max(0, feeCoins - balance),
  };
}

export interface CpUnlockResult {
  unlocked: true;
  alreadyUnlocked: boolean;
  paidCoins: number;
  balance: number;
  source: string;
  transactionId: number | null;
}

/**
 * The user confirmed. Free → record the unlock. Fee → guarded decrement,
 * Transaction(CP_UNLOCK_FEE) and the unlock row in ONE transaction. A second
 * call is a no-op that reports `alreadyUnlocked` (a double tap must not pay
 * twice). Insufficient balance → CpError 402 with `shortfall`, nothing moved.
 */
export async function confirmCpUnlock(userId: number, db: any = prisma): Promise<CpUnlockResult> {
  return db.$transaction(async (tx: any) => {
    const existing = await tx.cpUnlock.findUnique({ where: { userId } });
    const balRow = await tx.user.findUnique({ where: { id: userId }, select: { id: true, coinsBalance: true } });
    if (!balRow) throw new CpError('UNAUTHORIZED', 'غير مصرح', 401);
    if (existing) {
      return {
        unlocked: true as const,
        alreadyUnlocked: true,
        paidCoins: Number(existing.paidCoins ?? 0),
        balance: Number(balRow.coinsBalance),
        source: existing.source,
        transactionId: existing.transactionId ?? null,
      };
    }

    const policy = await resolveCpUnlockPolicy(userId, tx);
    const fee = policy.feeCoins;
    const source =
      policy.policySource === 'grant'
        ? policy.mode === 'fee'
          ? 'grant_fee'
          : 'grant_free'
        : policy.mode === 'fee'
          ? 'fee_policy'
          : 'free_policy';

    let transactionId: number | null = null;
    let balance = Number(balRow.coinsBalance);
    if (fee > 0) {
      const dec = await tx.user.updateMany({
        where: { id: userId, coinsBalance: { gte: fee } },
        data: { coinsBalance: { decrement: fee } },
      });
      if (!dec.count) {
        throw new CpError('INSUFFICIENT_COINS', 'رصيدك لا يكفي لفتح الـ CP', 402, {
          feeCoins: fee,
          balance,
          shortfall: Math.max(0, fee - balance),
        });
      }
      balance -= fee;
      const trx = await tx.transaction.create({
        data: { userId, type: 'CP_UNLOCK_FEE', amountCoins: -fee, status: 'completed' },
      });
      transactionId = trx.id;
    }

    await tx.cpUnlock.create({
      data: { userId, paidCoins: fee, source, transactionId, grantedById: policy.grant?.grantedById ?? null },
    });

    return { unlocked: true as const, alreadyUnlocked: false, paidCoins: fee, balance, source, transactionId };
  });
}

/**
 * The gate on `POST /cp/requests`.
 *
 * Free (system policy `free`, or a FREE grant): the unlock is recorded on the
 * spot and the request goes through — nothing to confirm, nothing to pay, so
 * an app build that predates this feature keeps working under the default
 * policy exactly as before.
 *
 * Fee: throws 403 CP_LOCKED carrying the quoted fee so the app can open the
 * confirmation sheet straight away; only `confirmCpUnlock` takes the coins.
 */
export async function assertCpUnlocked(userId: number, db: any = prisma): Promise<void> {
  const unlock = await db.cpUnlock.findUnique({ where: { userId }, select: { id: true } });
  if (unlock) return;
  const status = await getCpUnlockStatus(userId, db);
  if (status.feeCoins <= 0) {
    await confirmCpUnlock(userId, db);
    return;
  }
  throw new CpError('CP_LOCKED', `فتح الـ CP يتطلب ${status.feeCoins} كوينز`, 403, {
    mode: status.mode,
    feeCoins: status.feeCoins,
    balance: status.balance,
    shortfall: status.shortfall,
    policySource: status.policySource,
  });
}
