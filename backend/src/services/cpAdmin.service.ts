import prisma from '../utils/prisma';
import { AUDIT_ACTIONS, recordAdminAudit } from './adminAudit.service';
import {
  CP_UNLOCK_SETTING_DEFAULTS,
  CpError,
  computeCpLevel,
  readCpSettings,
  resolveCpUnlockPolicy,
} from './cpUnlock.service';

/**
 * إدارة نظام CP والخلفيات — the business logic behind the dashboard panel.
 *
 * Every mutation here:
 *   • runs after the route has already verified `isAdmin` server-side;
 *   • writes an admin_audit_logs row (who, what, target user, before/after);
 *   • for grants also appends to cp_unlock_grant_history, which is never
 *     deleted ("يجب تسجيل تاريخ منح الصلاحية وسحبها");
 *   • touches ONLY the addressed user / pair / item — a background revoke
 *     deletes one (userId, itemId) row and nothing else.
 *
 * Functions take the Prisma client last so tests can inject a fake.
 */

export interface AdminCtx {
  adminId: number;
  ip?: string | null;
}

const PROFILE_BACKGROUND_TYPE = 'PROFILE_BACKGROUND';

const USER_SELECT = { id: true, name: true, displayId: true, avatarUrl: true, coinsBalance: true } as const;

/**
 * The admin types the ID he reads off the profile card — that is `displayId`.
 * The internal row id still resolves so links from other dashboard lists keep
 * working; `by = 'id'` forces that reading.
 */
export async function resolveUser(raw: unknown, by: 'auto' | 'id' | 'displayId' = 'auto', db: any = prisma) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) throw new CpError('INVALID_USER', 'رقم المستخدم غير صالح', 400);
  const byDisplay = by === 'id' ? null : await db.user.findUnique({ where: { displayId: n }, select: USER_SELECT });
  if (byDisplay) return byDisplay;
  if (by === 'displayId') throw new CpError('USER_NOT_FOUND', 'لا يوجد مستخدم بهذا الرقم', 404);
  const byId = await db.user.findUnique({ where: { id: n }, select: USER_SELECT });
  if (!byId) throw new CpError('USER_NOT_FOUND', 'لا يوجد مستخدم بهذا الرقم', 404);
  return byId;
}

// ---------------------------------------------------------------------------
// System policy
// ---------------------------------------------------------------------------

export async function getCpPolicy(db: any = prisma) {
  const s = await readCpSettings(db);
  return {
    unlockMode: s.unlockMode,
    unlockFeeCoins: s.unlockFeeCoins,
    levelStepCoins: s.levelStepCoins,
    levelMax: s.levelMax,
    levelNames: s.levelNames,
  };
}

export interface CpPolicyPatch {
  unlockMode?: 'free' | 'fee';
  unlockFeeCoins?: number;
  levelStepCoins?: number;
  levelMax?: number;
  levelNames?: string[] | string;
}

export async function updateCpPolicy(patch: CpPolicyPatch, ctx: AdminCtx, db: any = prisma) {
  const before = await getCpPolicy(db);
  const writes: Array<{ key: string; value: string }> = [];
  if (patch.unlockMode !== undefined) {
    if (patch.unlockMode !== 'free' && patch.unlockMode !== 'fee') throw new CpError('INVALID_MODE', 'الوضع يجب أن يكون free أو fee');
    writes.push({ key: 'cp_unlock_mode', value: patch.unlockMode });
  }
  const intField = (v: unknown, key: string, min: number, label: string) => {
    if (v === undefined) return;
    const n = Math.floor(Number(v));
    if (!Number.isFinite(n) || n < min) throw new CpError('INVALID_VALUE', `${label} غير صالح`);
    writes.push({ key, value: String(n) });
  };
  intField(patch.unlockFeeCoins, 'cp_unlock_fee_coins', 0, 'رسوم فتح CP');
  intField(patch.levelStepCoins, 'cp_level_step_coins', 0, 'قيمة رفع المستوى');
  intField(patch.levelMax, 'cp_level_max', 1, 'أقصى مستوى');
  if (patch.levelNames !== undefined) {
    const names = Array.isArray(patch.levelNames)
      ? patch.levelNames.map((x) => String(x).trim()).filter(Boolean)
      : String(patch.levelNames).split(',').map((x) => x.trim()).filter(Boolean);
    writes.push({ key: 'cp_level_names', value: names.length ? JSON.stringify(names) : '' });
  }
  if (!writes.length) throw new CpError('NOTHING_TO_UPDATE', 'لا يوجد ما يتم تحديثه');
  for (const w of writes) {
    if (!(w.key in CP_UNLOCK_SETTING_DEFAULTS)) continue;
    await db.appSetting.upsert({ where: { key: w.key }, update: { value: w.value }, create: { key: w.key, value: w.value } });
  }
  const after = await getCpPolicy(db);
  await recordAdminAudit(
    { adminId: ctx.adminId, action: AUDIT_ACTIONS.CP_POLICY_UPDATE, targetType: 'setting', targetId: 'cp_policy', before, after, ip: ctx.ip },
    db,
  );
  return after;
}

// ---------------------------------------------------------------------------
// Per-user grants: "فتح CP مجانًا" / "فتح CP برسوم"
// ---------------------------------------------------------------------------

export interface GrantInput {
  mode: 'FREE' | 'FEE';
  feeCoins?: number;
  note?: string | null;
}

export async function listCpGrants(db: any = prisma, opts: { userId?: number; limit?: number } = {}) {
  const rows = await db.cpUnlockGrant.findMany({
    where: opts.userId ? { userId: opts.userId } : undefined,
    orderBy: { grantedAt: 'desc' },
    take: Math.min(500, Math.max(1, opts.limit ?? 200)),
    include: { user: { select: { id: true, name: true, displayId: true, avatarUrl: true } } },
  });
  const adminIds = [...new Set(rows.map((r: any) => r.grantedById))];
  const admins = adminIds.length
    ? await db.user.findMany({ where: { id: { in: adminIds } }, select: { id: true, name: true, displayId: true } })
    : [];
  const adminById = new Map(admins.map((a: any) => [a.id, a]));
  return rows.map((r: any) => ({ ...r, grantedBy: adminById.get(r.grantedById) ?? { id: r.grantedById } }));
}

export async function grantCpUnlock(targetUserId: number, input: GrantInput, ctx: AdminCtx, db: any = prisma) {
  const mode = String(input.mode).toUpperCase() === 'FEE' ? 'FEE' : 'FREE';
  const feeCoins = mode === 'FEE' ? Math.floor(Number(input.feeCoins)) : 0;
  if (mode === 'FEE' && (!Number.isFinite(feeCoins) || feeCoins < 0)) {
    throw new CpError('INVALID_FEE', 'عدد الكوينز غير صالح');
  }
  const note = input.note == null ? null : String(input.note).slice(0, 500) || null;

  return db.$transaction(async (tx: any) => {
    const before = await tx.cpUnlockGrant.findUnique({ where: { userId: targetUserId } });
    const grant = await tx.cpUnlockGrant.upsert({
      where: { userId: targetUserId },
      update: { mode, feeCoins, note, grantedById: ctx.adminId },
      create: { userId: targetUserId, mode, feeCoins, note, grantedById: ctx.adminId },
    });
    await tx.cpUnlockGrantHistory.create({
      data: { userId: targetUserId, action: before ? 'UPDATE' : 'GRANT', mode, feeCoins, note, adminId: ctx.adminId },
    });
    await recordAdminAudit(
      {
        adminId: ctx.adminId,
        action: mode === 'FEE' ? AUDIT_ACTIONS.CP_GRANT_FEE : AUDIT_ACTIONS.CP_GRANT_FREE,
        targetUserId,
        targetType: 'user',
        targetId: targetUserId,
        before: before ? { mode: before.mode, feeCoins: before.feeCoins, note: before.note } : null,
        after: { mode, feeCoins, note },
        ip: ctx.ip,
      },
      tx,
    );
    return grant;
  });
}

export async function revokeCpGrant(targetUserId: number, ctx: AdminCtx, db: any = prisma) {
  return db.$transaction(async (tx: any) => {
    const before = await tx.cpUnlockGrant.findUnique({ where: { userId: targetUserId } });
    if (!before) throw new CpError('NOT_FOUND', 'لا توجد صلاحية لهذا المستخدم', 404);
    await tx.cpUnlockGrant.delete({ where: { userId: targetUserId } });
    await tx.cpUnlockGrantHistory.create({
      data: { userId: targetUserId, action: 'REVOKE', mode: before.mode, feeCoins: before.feeCoins, note: before.note, adminId: ctx.adminId },
    });
    await recordAdminAudit(
      {
        adminId: ctx.adminId,
        action: AUDIT_ACTIONS.CP_GRANT_REVOKE,
        targetUserId,
        targetType: 'user',
        targetId: targetUserId,
        before: { mode: before.mode, feeCoins: before.feeCoins, note: before.note },
        after: null,
        ip: ctx.ip,
      },
      tx,
    );
    return { revoked: true };
  });
}

// ---------------------------------------------------------------------------
// Unlock state (admin opens / closes CP for one user)
// ---------------------------------------------------------------------------

/** "فتح CP مجانًا لمستخدم معين" — opens it right now, nothing charged. */
export async function adminUnlockCp(targetUserId: number, ctx: AdminCtx, db: any = prisma) {
  return db.$transaction(async (tx: any) => {
    const before = await tx.cpUnlock.findUnique({ where: { userId: targetUserId } });
    if (before) return { alreadyUnlocked: true, unlock: before };
    const unlock = await tx.cpUnlock.create({
      data: { userId: targetUserId, paidCoins: 0, source: 'admin', grantedById: ctx.adminId },
    });
    await recordAdminAudit(
      { adminId: ctx.adminId, action: AUDIT_ACTIONS.CP_UNLOCK_ADMIN, targetUserId, targetType: 'user', targetId: targetUserId, before: null, after: { source: 'admin' }, ip: ctx.ip },
      tx,
    );
    return { alreadyUnlocked: false, unlock };
  });
}

/** Closes CP again. Pairs are kept; the user just cannot send new invitations. No refund. */
export async function adminLockCp(targetUserId: number, ctx: AdminCtx, db: any = prisma) {
  return db.$transaction(async (tx: any) => {
    const before = await tx.cpUnlock.findUnique({ where: { userId: targetUserId } });
    if (!before) throw new CpError('NOT_FOUND', 'الـ CP غير مفتوح لهذا المستخدم', 404);
    await tx.cpUnlock.delete({ where: { userId: targetUserId } });
    await recordAdminAudit(
      {
        adminId: ctx.adminId,
        action: AUDIT_ACTIONS.CP_LOCK_ADMIN,
        targetUserId,
        targetType: 'user',
        targetId: targetUserId,
        before: { source: before.source, paidCoins: before.paidCoins, createdAt: before.createdAt },
        after: null,
        ip: ctx.ip,
      },
      tx,
    );
    return { locked: true };
  });
}

// ---------------------------------------------------------------------------
// One user's CP data ("عرض بيانات CP الحالية")
// ---------------------------------------------------------------------------

export async function getUserCpOverview(targetUserId: number, db: any = prisma) {
  const [user, unlock, policy, settings, pairs, pending, history] = await Promise.all([
    db.user.findUnique({ where: { id: targetUserId }, select: { ...USER_SELECT, cpFeaturedPartnerId: true } }),
    db.cpUnlock.findUnique({ where: { userId: targetUserId } }),
    resolveCpUnlockPolicy(targetUserId, db),
    readCpSettings(db),
    db.cpPair.findMany({
      where: { OR: [{ userAId: targetUserId }, { userBId: targetUserId }] },
      orderBy: { createdAt: 'desc' },
      include: {
        userA: { select: { id: true, name: true, displayId: true, avatarUrl: true } },
        userB: { select: { id: true, name: true, displayId: true, avatarUrl: true } },
      },
    }),
    db.cpRequest.findMany({
      where: { OR: [{ senderId: targetUserId }, { recipientId: targetUserId }], status: 'pending' },
      orderBy: { createdAt: 'desc' },
      take: 50,
    }),
    db.cpUnlockGrantHistory.findMany({ where: { userId: targetUserId }, orderBy: { createdAt: 'desc' }, take: 50 }),
  ]);
  if (!user) throw new CpError('USER_NOT_FOUND', 'المستخدم غير موجود', 404);
  const pairRows = pairs.map((p: any) => {
    const partner = p.userAId === targetUserId ? p.userB : p.userA;
    const lvl = computeCpLevel({ cpValue: p.cpValue, createdAt: p.createdAt, levelOverride: p.levelOverride }, settings);
    return {
      pairId: p.id,
      partner,
      giftId: p.giftId,
      createdAt: p.createdAt,
      cpValue: p.cpValue,
      levelOverride: p.levelOverride,
      level: lvl.level,
      levelName: lvl.levelName,
      days: lvl.days,
      levelBasis: lvl.basis,
      featured: user.cpFeaturedPartnerId === partner.id,
    };
  });
  return {
    user,
    unlock,
    policy: { mode: policy.mode, feeCoins: policy.feeCoins, policySource: policy.policySource, grant: policy.grant },
    featuredPartnerId: user.cpFeaturedPartnerId ?? null,
    pairs: pairRows,
    pendingRequests: pending,
    grantHistory: history,
  };
}

// ---------------------------------------------------------------------------
// Featured partner / pair edits
// ---------------------------------------------------------------------------

export async function adminSetFeatured(targetUserId: number, partnerId: number | null, ctx: AdminCtx, db: any = prisma) {
  const before = await db.user.findUnique({ where: { id: targetUserId }, select: { cpFeaturedPartnerId: true } });
  if (!before) throw new CpError('USER_NOT_FOUND', 'المستخدم غير موجود', 404);
  if (partnerId != null) {
    const [a, b] = targetUserId < partnerId ? [targetUserId, partnerId] : [partnerId, targetUserId];
    const pair = await db.cpPair.findUnique({ where: { userAId_userBId: { userAId: a, userBId: b } } });
    if (!pair) throw new CpError('NOT_FOUND', 'لا يوجد ارتباط CP بين المستخدمين', 404);
  }
  await db.user.update({ where: { id: targetUserId }, data: { cpFeaturedPartnerId: partnerId } });
  await recordAdminAudit(
    {
      adminId: ctx.adminId,
      action: AUDIT_ACTIONS.CP_FEATURED_SET,
      targetUserId,
      targetType: 'user',
      targetId: targetUserId,
      before: { cpFeaturedPartnerId: before.cpFeaturedPartnerId },
      after: { cpFeaturedPartnerId: partnerId },
      ip: ctx.ip,
    },
    db,
  );
  return { featuredPartnerId: partnerId };
}

export interface PairPatch {
  cpValue?: number;
  levelOverride?: number | null;
}

export async function adminUpdatePair(pairId: number, patch: PairPatch, ctx: AdminCtx, db: any = prisma) {
  const before = await db.cpPair.findUnique({ where: { id: pairId } });
  if (!before) throw new CpError('NOT_FOUND', 'الارتباط غير موجود', 404);
  const data: any = {};
  if (patch.cpValue !== undefined) {
    const v = Math.floor(Number(patch.cpValue));
    if (!Number.isFinite(v) || v < 0) throw new CpError('INVALID_VALUE', 'قيمة CP غير صالحة');
    data.cpValue = v;
  }
  if (patch.levelOverride !== undefined) {
    if (patch.levelOverride === null) data.levelOverride = null;
    else {
      const l = Math.floor(Number(patch.levelOverride));
      if (!Number.isFinite(l) || l < 1) throw new CpError('INVALID_VALUE', 'المستوى غير صالح');
      data.levelOverride = l;
    }
  }
  if (!Object.keys(data).length) throw new CpError('NOTHING_TO_UPDATE', 'لا يوجد ما يتم تحديثه');
  const after = await db.cpPair.update({ where: { id: pairId }, data });
  await recordAdminAudit(
    {
      adminId: ctx.adminId,
      action: AUDIT_ACTIONS.CP_PAIR_UPDATE,
      targetUserId: before.userAId,
      targetType: 'cp_pair',
      targetId: pairId,
      before: { cpValue: before.cpValue, levelOverride: before.levelOverride, userBId: before.userBId },
      after: { cpValue: after.cpValue, levelOverride: after.levelOverride, userBId: after.userBId },
      ip: ctx.ip,
    },
    db,
  );
  return after;
}

export async function adminDeletePair(pairId: number, ctx: AdminCtx, db: any = prisma) {
  const before = await db.cpPair.findUnique({ where: { id: pairId } });
  if (!before) throw new CpError('NOT_FOUND', 'الارتباط غير موجود', 404);
  await db.cpPair.delete({ where: { id: pairId } });
  await recordAdminAudit(
    {
      adminId: ctx.adminId,
      action: AUDIT_ACTIONS.CP_PAIR_DELETE,
      targetUserId: before.userAId,
      targetType: 'cp_pair',
      targetId: pairId,
      before: { userAId: before.userAId, userBId: before.userBId, cpValue: before.cpValue, giftId: before.giftId },
      after: null,
      ip: ctx.ip,
    },
    db,
  );
  return { deleted: true };
}

// ---------------------------------------------------------------------------
// CP gifts ("إدارة هدايا CP") — the gifts in the `cp` list
// ---------------------------------------------------------------------------

export async function listCpGifts(db: any = prisma) {
  return db.gift.findMany({
    where: { category: 'cp' },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    select: { id: true, name: true, nameAr: true, iconUrl: true, coinCost: true, isActive: true, sortOrder: true, tier: true, category: true },
  });
}

export interface CpGiftPatch {
  coinCost?: number;
  isActive?: boolean;
  sortOrder?: number;
  nameAr?: string;
}

export async function updateCpGift(giftId: string, patch: CpGiftPatch, ctx: AdminCtx, db: any = prisma) {
  const before = await db.gift.findUnique({ where: { id: giftId } });
  if (!before) throw new CpError('NOT_FOUND', 'الهدية غير موجودة', 404);
  const data: any = {};
  if (patch.coinCost !== undefined) {
    const c = Math.floor(Number(patch.coinCost));
    if (!Number.isFinite(c) || c <= 0) throw new CpError('INVALID_VALUE', 'قيمة الهدية غير صالحة');
    data.coinCost = c;
  }
  if (patch.isActive !== undefined) data.isActive = Boolean(patch.isActive);
  if (patch.sortOrder !== undefined) {
    const o = Math.floor(Number(patch.sortOrder));
    if (Number.isFinite(o)) data.sortOrder = o;
  }
  if (patch.nameAr !== undefined && String(patch.nameAr).trim()) data.nameAr = String(patch.nameAr).trim();
  if (!Object.keys(data).length) throw new CpError('NOTHING_TO_UPDATE', 'لا يوجد ما يتم تحديثه');
  const after = await db.gift.update({ where: { id: giftId }, data });
  await recordAdminAudit(
    {
      adminId: ctx.adminId,
      action: AUDIT_ACTIONS.CP_GIFT_UPDATE,
      targetType: 'gift',
      targetId: giftId,
      before: { coinCost: before.coinCost, isActive: before.isActive, sortOrder: before.sortOrder, nameAr: before.nameAr },
      after: { coinCost: after.coinCost, isActive: after.isActive, sortOrder: after.sortOrder, nameAr: after.nameAr },
      ip: ctx.ip,
    },
    db,
  );
  return after;
}

// ---------------------------------------------------------------------------
// Audit log ("عرض سجل العمليات والتعديلات")
// ---------------------------------------------------------------------------

export async function listAuditLog(opts: { userId?: number; action?: string; limit?: number; before?: number }, db: any = prisma) {
  const where: any = {};
  if (opts.userId) where.targetUserId = opts.userId;
  if (opts.action) where.action = opts.action.startsWith('*') ? undefined : opts.action;
  if (opts.action === 'CP') where.action = { startsWith: 'CP_' };
  if (opts.action === 'BG') where.action = { startsWith: 'BG_' };
  if (opts.before) where.id = { lt: opts.before };
  const rows = await db.adminAuditLog.findMany({
    where,
    orderBy: { id: 'desc' },
    take: Math.min(500, Math.max(1, opts.limit ?? 100)),
  });
  const ids = [...new Set(rows.flatMap((r: any) => [r.adminId, r.targetUserId]).filter((x: any) => x != null))];
  const users = ids.length ? await db.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true, displayId: true } }) : [];
  const byId = new Map(users.map((u: any) => [u.id, u]));
  return rows.map((r: any) => ({
    ...r,
    admin: byId.get(r.adminId) ?? { id: r.adminId },
    targetUser: r.targetUserId != null ? byId.get(r.targetUserId) ?? { id: r.targetUserId } : null,
  }));
}

// ---------------------------------------------------------------------------
// Backgrounds (خلفية الصفحة الشخصية) — Item.type = PROFILE_BACKGROUND
// ---------------------------------------------------------------------------

const bgView = (i: any, ownerCount?: number) => ({
  id: i.id,
  name: i.name,
  type: i.type,
  assetUrl: i.assetUrl,
  previewUrl: i.previewUrl ?? null,
  priceCoins: i.priceCoins,
  isFree: Number(i.priceCoins) === 0,
  isPurchasable: i.isPurchasable,
  durationDays: i.durationDays ?? null,
  grantToAll: i.grantToAll ?? false,
  createdAt: i.createdAt,
  ...(ownerCount !== undefined ? { ownerCount } : {}),
});

export async function listBackgrounds(db: any = prisma) {
  const items = await db.item.findMany({ where: { type: PROFILE_BACKGROUND_TYPE }, orderBy: { createdAt: 'desc' } });
  const counts = items.length
    ? await db.userItem.groupBy({ by: ['itemId'], where: { itemId: { in: items.map((i: any) => i.id) } }, _count: { _all: true } })
    : [];
  const countById = new Map<string, number>(counts.map((c: any) => [String(c.itemId), Number(c._count?._all ?? 0)]));
  return items.map((i: any) => bgView(i, countById.get(i.id) ?? 0));
}

export interface BackgroundCreate {
  name: string;
  assetUrl: string;
  previewUrl?: string | null;
  priceCoins?: number;
  isFree?: boolean;
  isPurchasable?: boolean;
  durationDays?: number | null;
}

export async function createBackground(input: BackgroundCreate, ctx: AdminCtx, db: any = prisma) {
  const name = String(input.name ?? '').trim();
  if (!name) throw new CpError('INVALID_VALUE', 'اسم الخلفية مطلوب');
  if (!input.assetUrl) throw new CpError('INVALID_VALUE', 'ملف الخلفية مطلوب');
  const price = input.isFree ? 0 : Math.max(0, Math.floor(Number(input.priceCoins ?? 0)) || 0);
  const item = await db.item.create({
    data: {
      name,
      description: '',
      type: PROFILE_BACKGROUND_TYPE,
      itemType: 'PROFILE_BACKGROUND',
      assetUrl: input.assetUrl,
      previewUrl: input.previewUrl ?? null,
      priceCoins: price,
      isPurchasable: input.isPurchasable ?? true,
      durationDays: input.durationDays ?? null,
    },
  });
  await recordAdminAudit(
    { adminId: ctx.adminId, action: AUDIT_ACTIONS.BG_CREATE, targetType: 'item', targetId: item.id, before: null, after: bgView(item), ip: ctx.ip },
    db,
  );
  return bgView(item, 0);
}

export interface BackgroundPatch {
  name?: string;
  priceCoins?: number;
  isFree?: boolean;
  isPurchasable?: boolean;
  durationDays?: number | null;
  assetUrl?: string;
  previewUrl?: string | null;
}

export async function updateBackground(itemId: string, patch: BackgroundPatch, ctx: AdminCtx, db: any = prisma) {
  const before = await db.item.findUnique({ where: { id: itemId } });
  if (!before || before.type !== PROFILE_BACKGROUND_TYPE) throw new CpError('NOT_FOUND', 'الخلفية غير موجودة', 404);
  const data: any = {};
  if (patch.name !== undefined && String(patch.name).trim()) data.name = String(patch.name).trim();
  if (patch.isFree === true) data.priceCoins = 0;
  else if (patch.priceCoins !== undefined) {
    const p = Math.floor(Number(patch.priceCoins));
    if (!Number.isFinite(p) || p < 0) throw new CpError('INVALID_VALUE', 'السعر غير صالح');
    data.priceCoins = p;
  }
  if (patch.isPurchasable !== undefined) data.isPurchasable = Boolean(patch.isPurchasable);
  if (patch.durationDays !== undefined) {
    const d = patch.durationDays == null ? null : Math.floor(Number(patch.durationDays));
    data.durationDays = d && d > 0 ? d : null;
  }
  if (patch.assetUrl) data.assetUrl = patch.assetUrl;
  if (patch.previewUrl !== undefined) data.previewUrl = patch.previewUrl;
  if (!Object.keys(data).length) throw new CpError('NOTHING_TO_UPDATE', 'لا يوجد ما يتم تحديثه');
  const after = await db.item.update({ where: { id: itemId }, data });
  await recordAdminAudit(
    { adminId: ctx.adminId, action: AUDIT_ACTIONS.BG_UPDATE, targetType: 'item', targetId: itemId, before: bgView(before), after: bgView(after), ip: ctx.ip },
    db,
  );
  return bgView(after);
}

/**
 * Delete a background. Same cascade the store's deleteProduct does: owners
 * lose the row (the product no longer exists), and any profile still painting
 * this exact asset is cleared. Audited with the owner count so it can be
 * explained afterwards.
 */
export async function deleteBackground(itemId: string, ctx: AdminCtx, db: any = prisma) {
  const before = await db.item.findUnique({ where: { id: itemId } });
  if (!before || before.type !== PROFILE_BACKGROUND_TYPE) throw new CpError('NOT_FOUND', 'الخلفية غير موجودة', 404);
  return db.$transaction(async (tx: any) => {
    const owners = await tx.userItem.count({ where: { itemId } });
    if (before.assetUrl) {
      await tx.user.updateMany({ where: { profileBgUrl: before.assetUrl }, data: { profileBgUrl: null, profileBgType: 'image' } });
    }
    await tx.userItem.deleteMany({ where: { itemId } });
    await tx.item.delete({ where: { id: itemId } });
    await recordAdminAudit(
      { adminId: ctx.adminId, action: AUDIT_ACTIONS.BG_DELETE, targetType: 'item', targetId: itemId, before: { ...bgView(before), ownerCount: owners }, after: null, ip: ctx.ip },
      tx,
    );
    return { deleted: true, ownersAffected: owners };
  });
}

/** "منح الخلفية لمستخدم محدد" — one (userId, itemId) row; nobody else is touched. */
export async function grantBackground(itemId: string, targetUserId: number, ctx: AdminCtx, db: any = prisma) {
  const item = await db.item.findUnique({ where: { id: itemId } });
  if (!item || item.type !== PROFILE_BACKGROUND_TYPE) throw new CpError('NOT_FOUND', 'الخلفية غير موجودة', 404);
  const days = Number(item.durationDays ?? 0);
  const expiresAt = Number.isFinite(days) && days > 0 ? new Date(Date.now() + days * 86_400_000) : null;
  return db.$transaction(async (tx: any) => {
    const before = await tx.userItem.findUnique({ where: { userId_itemId: { userId: targetUserId, itemId } } });
    let row;
    if (before) {
      // Re-granting a rental extends it; a permanent copy is already owned.
      if (!expiresAt) throw new CpError('ALREADY_OWNED', 'المستخدم يملك هذه الخلفية بالفعل', 409);
      const base = Math.max(Date.now(), before.expiresAt ? new Date(before.expiresAt).getTime() : 0);
      row = await tx.userItem.update({ where: { id: before.id }, data: { expiresAt: new Date(base + days * 86_400_000) } });
    } else {
      row = await tx.userItem.create({ data: { userId: targetUserId, itemId, expiresAt } });
    }
    await recordAdminAudit(
      {
        adminId: ctx.adminId,
        action: AUDIT_ACTIONS.BG_GRANT,
        targetUserId,
        targetType: 'item',
        targetId: itemId,
        before: before ? { expiresAt: before.expiresAt } : null,
        after: { expiresAt: row.expiresAt, itemName: item.name },
        ip: ctx.ip,
      },
      tx,
    );
    return row;
  });
}

/**
 * "سحب ملكية الخلفية عند الحاجة وفق قواعد الإدارة" — removes ONE user's
 * ownership of ONE background and un-equips it if it is the one on his page.
 * Every other user's rows are untouched.
 */
export async function revokeBackground(itemId: string, targetUserId: number, ctx: AdminCtx, db: any = prisma, reason?: string | null) {
  const item = await db.item.findUnique({ where: { id: itemId } });
  if (!item || item.type !== PROFILE_BACKGROUND_TYPE) throw new CpError('NOT_FOUND', 'الخلفية غير موجودة', 404);
  return db.$transaction(async (tx: any) => {
    const before = await tx.userItem.findUnique({ where: { userId_itemId: { userId: targetUserId, itemId } } });
    if (!before) throw new CpError('NOT_FOUND', 'المستخدم لا يملك هذه الخلفية', 404);
    await tx.userItem.delete({ where: { id: before.id } });
    // Only THIS user's page, only if it is painting THIS asset.
    await tx.user.updateMany({
      where: { id: targetUserId, profileBgUrl: item.assetUrl },
      data: { profileBgUrl: null, profileBgType: 'image' },
    });
    await recordAdminAudit(
      {
        adminId: ctx.adminId,
        action: AUDIT_ACTIONS.BG_REVOKE,
        targetUserId,
        targetType: 'item',
        targetId: itemId,
        before: { acquiredAt: before.acquiredAt, expiresAt: before.expiresAt, isActive: before.isActive, itemName: item.name },
        after: reason ? { reason: String(reason).slice(0, 500) } : null,
        ip: ctx.ip,
      },
      tx,
    );
    return { revoked: true };
  });
}

/**
 * "منع تعديل ملكية الخلفيات من التطبيق" — may this user paint `url` on his
 * page via PUT /users/me? A picture he uploaded himself (not a store asset)
 * is always fine; a store background needs an unexpired user_items row.
 */
export async function canUseProfileBackground(userId: number, url: string, db: any = prisma): Promise<boolean> {
  if (!url) return true;
  const storeItem = await db.item.findFirst({
    where: { assetUrl: url, type: PROFILE_BACKGROUND_TYPE },
    select: { id: true },
  });
  if (!storeItem) return true;
  const owned = await db.userItem.findFirst({
    where: {
      userId,
      itemId: storeItem.id,
      OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
    },
    select: { id: true },
  });
  return !!owned;
}

/** "عرض قائمة الخلفيات المملوكة لكل مستخدم". */
export async function listUserBackgrounds(targetUserId: number, db: any = prisma) {
  const [user, rows] = await Promise.all([
    db.user.findUnique({ where: { id: targetUserId }, select: { id: true, name: true, displayId: true, profileBgUrl: true, profileBgType: true } }),
    db.userItem.findMany({
      where: { userId: targetUserId, item: { type: PROFILE_BACKGROUND_TYPE } },
      orderBy: { acquiredAt: 'desc' },
      include: { item: true },
    }),
  ]);
  if (!user) throw new CpError('USER_NOT_FOUND', 'المستخدم غير موجود', 404);
  return {
    user,
    backgrounds: rows.map((r: any) => ({
      userItemId: r.id,
      acquiredAt: r.acquiredAt,
      expiresAt: r.expiresAt,
      isActive: r.isActive,
      equipped: !!user.profileBgUrl && user.profileBgUrl === r.item.assetUrl,
      item: bgView(r.item),
    })),
  };
}
