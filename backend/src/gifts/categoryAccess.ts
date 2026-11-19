export type CategoryLock = { minVipLevel: number | null; allowedUserIds: number[] };
// minVipLevel 0 means "everyone" (every user is VIP >= 0), so it is NOT a lock.
const hasVipLock = (c: { minVipLevel?: number | null }) => c.minVipLevel != null && c.minVipLevel > 0;
export function isCategoryLocked(category: { minVipLevel: number | null; allowedUserIds?: number[] | null } | null): boolean {
  return !!category && (hasVipLock(category) || (category.allowedUserIds ?? []).length > 0);
}
export function canOpenCategory(category: { minVipLevel: number | null; allowedUserIds?: number[] | null } | null, user: { vipLevel: number; displayId: number | null } | null): boolean {
  if (!isCategoryLocked(category)) return true;
  return !!user && ((hasVipLock(category!) && user.vipLevel >= category!.minVipLevel!) ||
    (user.displayId != null && (category!.allowedUserIds ?? []).includes(user.displayId)));
}

let lockColumnsPresent: boolean | undefined;
let lockColumnsCheck: Promise<boolean> | null = null;
/**
 * One-time (cached) check, with the GLOBAL client and OUTSIDE any transaction,
 * that the category lock columns are migrated. Never call inside a tx.
 * On a failed check (DB error) nothing is cached, so it is retried later and
 * the lock stays enforced (fail closed).
 */
export function ensureCategoryLockColumns(
  client: { $queryRaw: (...args: any[]) => Promise<any> },
): Promise<boolean> {
  if (lockColumnsPresent !== undefined) return Promise.resolve(lockColumnsPresent);
  if (!lockColumnsCheck) {
    lockColumnsCheck = (async () => {
      try {
        const rows: unknown[] = await client.$queryRaw`SELECT 1 FROM information_schema.columns WHERE table_name = 'gift_categories' AND column_name = 'minVipLevel' LIMIT 1`;
        lockColumnsPresent = Array.isArray(rows) && rows.length > 0;
        if (!lockColumnsPresent) console.error('[gifts] category lock columns missing (migration pending); treating categories as unlocked');
        return lockColumnsPresent;
      } catch (error) {
        console.error('[gifts] category lock column check failed', error);
        return true;
      } finally {
        lockColumnsCheck = null;
      }
    })();
  }
  return lockColumnsCheck;
}
export function categoryLockColumnsKnownMissing(): boolean { return lockColumnsPresent === false; }
export function __resetCategoryLockColumnsForTest() { lockColumnsPresent = undefined; lockColumnsCheck = null; }

/**
 * Reads a category's lock through the caller's client (the gift transaction),
 * selecting only the lock columns. Call ensureCategoryLockColumns() first.
 */
export async function loadCategoryLock(
  client: { giftCategory: { findUnique: (args: any) => Promise<any> } },
  key: string,
): Promise<CategoryLock | null> {
  if (categoryLockColumnsKnownMissing()) return null;
  const row = await client.giftCategory.findUnique({ where: { key }, select: { minVipLevel: true, allowedUserIds: true } });
  return row ? { minVipLevel: row.minVipLevel ?? null, allowedUserIds: row.allowedUserIds ?? [] } : null;
}
export function parseCategoryLock(body: Record<string, unknown>): Partial<CategoryLock> {
  const data: Partial<CategoryLock> = {};
  if (body.minVipLevel !== undefined) {
    let value = body.minVipLevel === null || body.minVipLevel === '' ? null : Number(body.minVipLevel);
    if (value !== null && (!Number.isInteger(value) || value < 0 || value > 100)) throw new Error('أقل مستوى VIP لازم يكون من 0 لـ 100');
    if (value === 0) value = null; // 0 = no restriction
    data.minVipLevel = value;
  }
  if (body.allowedUserIds !== undefined) {
    const raw = body.allowedUserIds;
    if (!Array.isArray(raw) && typeof raw !== 'string') throw new Error('أرقام ID غير صالحة');
    const values = (Array.isArray(raw) ? raw : raw.trim().split(/[,،\s]+/).filter(Boolean)).map(Number);
    if (values.some(value => !Number.isInteger(value) || value <= 0 || value > 2147483647)) throw new Error('أرقام ID لازم تكون أرقام صحيحة موجبة');
    data.allowedUserIds = [...new Set(values)];
  }
  return data;
}
