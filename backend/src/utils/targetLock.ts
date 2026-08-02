import prisma from './prisma';

/**
 * Per-user block on selling (بيع) and converting (استبدال) target earnings.
 *
 * Stored as a comma-separated id list in the existing AppSetting key-value
 * table rather than a User column, so the lock ships without a migration
 * against the production database. It moves to a real column when the product
 * -duration migration lands.
 */
const SETTING_KEY = 'target_sell_blocked_user_ids';

async function readBlockedIds(): Promise<Set<number>> {
  try {
    const row = await (prisma as any).appSetting.findUnique({ where: { key: SETTING_KEY } });
    const raw = String(row?.value ?? '').trim();
    if (!raw) return new Set();
    return new Set(
      raw
        .split(',')
        .map((s) => Number(s.trim()))
        .filter((n) => Number.isInteger(n) && n > 0),
    );
  } catch (e) {
    // Fail OPEN: a settings-table blip must not freeze every payout.
    console.warn('[targetLock] lookup failed, allowing:', (e as Error).message);
    return new Set();
  }
}

/** True when this user is barred from selling or converting their target. */
export async function isTargetSellBlocked(userId: number): Promise<boolean> {
  if (!userId) return false;
  return (await readBlockedIds()).has(userId);
}

/** Add or remove a user from the block list. Returns the resulting list. */
export async function setTargetSellBlocked(
  userId: number,
  blocked: boolean,
): Promise<number[]> {
  const ids = await readBlockedIds();
  if (blocked) ids.add(userId);
  else ids.delete(userId);

  const value = [...ids].sort((a, b) => a - b).join(',');
  await (prisma as any).appSetting.upsert({
    where: { key: SETTING_KEY },
    update: { value },
    create: { key: SETTING_KEY, value },
  });
  return [...ids];
}

/** Every currently blocked user id, for the dashboard list. */
export async function listTargetSellBlocked(): Promise<number[]> {
  return [...(await readBlockedIds())].sort((a, b) => a - b);
}

export const TARGET_LOCK_MESSAGE =
  'تم إيقاف بيع واستبدال التارجيت لحسابك من قِبَل الإدارة';
