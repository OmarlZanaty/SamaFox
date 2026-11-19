export type CategoryLock = { minVipLevel: number | null; allowedUserIds: number[] };
export function isCategoryLocked(category: CategoryLock | null): boolean {
  return !!category && (category.minVipLevel != null || category.allowedUserIds.length > 0);
}
export function canOpenCategory(category: CategoryLock | null, user: { vipLevel: number; displayId: number | null } | null): boolean {
  if (!isCategoryLocked(category)) return true;
  return !!user && ((category!.minVipLevel != null && user.vipLevel >= category!.minVipLevel) ||
    (user.displayId != null && category!.allowedUserIds.includes(user.displayId)));
}
export function parseCategoryLock(body: Record<string, unknown>): Partial<CategoryLock> {
  const data: Partial<CategoryLock> = {};
  if (body.minVipLevel !== undefined) {
    const value = body.minVipLevel === null || body.minVipLevel === '' ? null : Number(body.minVipLevel);
    if (value !== null && (!Number.isInteger(value) || value < 0 || value > 100)) throw new Error('أقل مستوى VIP لازم يكون من 0 لـ 100');
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
