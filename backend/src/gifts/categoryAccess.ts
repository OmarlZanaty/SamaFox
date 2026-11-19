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

let warnedMissingColumns = false;
/**
 * Reads a category's lock. If the lock columns are not migrated yet (Prisma
 * P2022) the category is treated as unlocked (logged once) so sending gifts
 * never breaks while a migration lags. Pass the GLOBAL prisma client, not a
 * transaction: a failed statement would poison a Postgres transaction.
 */
export async function loadCategoryLock(
  client: { giftCategory: { findUnique: (args: any) => Promise<any> } },
  key: string,
): Promise<CategoryLock | null> {
  try {
    const row = await client.giftCategory.findUnique({ where: { key } });
    return row ? { minVipLevel: row.minVipLevel ?? null, allowedUserIds: row.allowedUserIds ?? [] } : null;
  } catch (error) {
    if ((error as { code?: string })?.code === 'P2022') {
      if (!warnedMissingColumns) {
        warnedMissingColumns = true;
        console.error('[gifts] category lock columns missing (migration pending); treating categories as unlocked');
      }
      return null;
    }
    throw error;
  }
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
