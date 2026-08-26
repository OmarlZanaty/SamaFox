import prisma from './prisma';

/**
 * Controls on selling (بيع) and converting (استبدال) target earnings.
 *
 * Two layers, both driven from the admin dashboard:
 *   1. A GLOBAL switch that stops every account at once. It is ON by default —
 *      the owner asked for بيع/تبديل التارجيت to stay blocked "حتي اقوم بفك
 *      المنع", so a fresh install (or a wiped settings table) is closed, not
 *      open, and only the dashboard can open it.
 *   2. A per-user block list, for singling out individual accounts while the
 *      global switch is off.
 *
 * Both live in the existing AppSetting key-value table rather than User
 * columns, so they ship without a migration against the production database.
 */
const USERS_KEY = 'target_sell_blocked_user_ids';
const GLOBAL_KEY = 'target_sell_blocked_global';

/** Missing row = blocked. Only an explicit "off" from the dashboard opens it. */
const GLOBAL_DEFAULT_BLOCKED = true;

interface TargetSellPolicy {
  globallyBlocked: boolean;
  blockedUserIds: Set<number>;
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

function parseBool(raw: unknown, fallback: boolean): boolean {
  const text = String(raw ?? '').trim().toLowerCase();
  if (!text) return fallback;
  if (['1', 'true', 'yes', 'on', 'blocked'].includes(text)) return true;
  if (['0', 'false', 'no', 'off', 'allowed'].includes(text)) return false;
  return fallback;
}

async function readPolicy(): Promise<TargetSellPolicy> {
  try {
    const rows = await (prisma as any).appSetting.findMany({
      where: { key: { in: [USERS_KEY, GLOBAL_KEY] } },
    });
    const byKey = new Map<string, any>(rows.map((r: any) => [r.key, r.value]));
    return {
      globallyBlocked: parseBool(byKey.get(GLOBAL_KEY), GLOBAL_DEFAULT_BLOCKED),
      blockedUserIds: parseIds(byKey.get(USERS_KEY)),
    };
  } catch (e) {
    // Fail OPEN: a settings-table blip must not freeze every payout. This is
    // deliberately different from the missing-row case above — "the row isn't
    // there yet" is a real answer (blocked), "the query exploded" is not.
    console.warn('[targetLock] lookup failed, allowing:', (e as Error).message);
    return { globallyBlocked: false, blockedUserIds: new Set() };
  }
}

/** True when this user is barred from selling or converting their target. */
export async function isTargetSellBlocked(userId: number): Promise<boolean> {
  if (!userId) return false;
  const policy = await readPolicy();
  return policy.globallyBlocked || policy.blockedUserIds.has(userId);
}

/**
 * Same check, but says WHY — the global freeze and a personal block are
 * different situations and the user deserves the right message.
 */
export async function checkTargetSellLock(
  userId: number,
): Promise<{ blocked: boolean; message: string }> {
  if (!userId) return { blocked: false, message: '' };
  const policy = await readPolicy();
  if (policy.globallyBlocked) {
    return { blocked: true, message: TARGET_LOCK_GLOBAL_MESSAGE };
  }
  if (policy.blockedUserIds.has(userId)) {
    return { blocked: true, message: TARGET_LOCK_MESSAGE };
  }
  return { blocked: false, message: '' };
}

/** Is the platform-wide freeze on? */
export async function isTargetSellGloballyBlocked(): Promise<boolean> {
  return (await readPolicy()).globallyBlocked;
}

/** Flip the platform-wide freeze. Dashboard only. */
export async function setTargetSellGlobalBlock(blocked: boolean): Promise<boolean> {
  const value = blocked ? '1' : '0';
  await (prisma as any).appSetting.upsert({
    where: { key: GLOBAL_KEY },
    update: { value },
    create: { key: GLOBAL_KEY, value },
  });
  return blocked;
}

/** Add or remove a user from the block list. Returns the resulting list. */
export async function setTargetSellBlocked(
  userId: number,
  blocked: boolean,
): Promise<number[]> {
  const { blockedUserIds: ids } = await readPolicy();
  if (blocked) ids.add(userId);
  else ids.delete(userId);

  const value = [...ids].sort((a, b) => a - b).join(',');
  await (prisma as any).appSetting.upsert({
    where: { key: USERS_KEY },
    update: { value },
    create: { key: USERS_KEY, value },
  });
  return [...ids];
}

/** Every currently blocked user id, for the dashboard list. */
export async function listTargetSellBlocked(): Promise<number[]> {
  return [...(await readPolicy()).blockedUserIds].sort((a, b) => a - b);
}

export const TARGET_LOCK_MESSAGE =
  'تم إيقاف بيع واستبدال التارجيت لحسابك من قِبَل الإدارة';

export const TARGET_LOCK_GLOBAL_MESSAGE =
  'بيع واستبدال التارجيت متوقف حالياً من قِبَل الإدارة';
