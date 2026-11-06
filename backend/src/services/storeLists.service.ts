import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { MIN_DISPLAY_ID } from '../utils/displayId';
import { recordAdminAuditStrict, auditContext } from './adminAudit.service';

/** Store purchases, special-ID rentals and gifts commit the guarded debit,
 * ledger, holding, ID history and notification in one serializable transaction.
 * Original IDs remain reserved until their holding is revoked or expires.
 */
const db = prisma as any;
export class StoreError extends Error {
  constructor(public status: number, message: string, public code = 'STORE') {
    super(message);
  }
}

export async function publicCategories() {
  const cats = await db.storeCategory.findMany({
    where: { isActive: true },
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    include: {
      products: {
        where: { isAvailable: true, OR: [{ stock: null }, { stock: { gt: 0 } }] },
        orderBy: [{ sortOrder: 'asc' }, { priceCoins: 'asc' }],
        take: 300,
      },
    },
  });
  return cats.map((c: any) => ({
    id: c.id,
    name: c.name,
    imageUrl: c.imageUrl,
    products: c.products.map((p: any) => ({
      id: p.id,
      kind: p.kind,
      name: p.name,
      imageUrl: p.imageUrl,
      priceCoins: p.priceCoins,
      currency: p.currency,
      durationDays: p.durationDays,
      stock: p.stock,
      specialDisplayId: p.specialDisplayId,
    })),
  }));
}

const DAY_MS = 86_400_000;
const positiveId = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2_147_483_647;
function validateSpecialId(userId: number, displayId?: number, days?: number | null) {
  if (!positiveId(userId) || (displayId !== undefined && !positiveId(displayId)) ||
      (days != null && (!Number.isSafeInteger(days) || days <= 0 || days > 36500))) {
    throw new StoreError(400, 'المستخدم أو الرقم أو المدة غير صالحة', 'INVALID_INPUT');
  }
}

async function specialTransaction<T>(work: (tx: any) => Promise<T>): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await prisma.$transaction(work, { isolationLevel: 'Serializable', timeout: 15000 });
    } catch (e: any) {
      const conflict = e?.code === 'P2034' || String(e?.message ?? '').includes('40001');
      // A simultaneous request may win the order's unique key. A fresh
      // transaction then returns that receipt instead of charging twice.
      if ((conflict || e?.code === 'P2002') && attempt < 3) continue;
      if (conflict) throw new StoreError(409, 'حاول مرة أخرى', 'RETRY');
      if (e?.code === 'P2002') throw new StoreError(409, 'الرقم مستخدم بالفعل', 'ID_TAKEN');
      throw e;
    }
  }
}

async function assignSpecialId(tx: any, userId: number, displayId: number, durationDays: number | null,
    source: 'store' | 'gift' | 'admin', grantedBy: number | null, orderId?: number) {
  validateSpecialId(userId, displayId, durationDays);
  await tx.$queryRaw(Prisma.sql`SELECT "id" FROM "users" WHERE "id" = ${userId} FOR UPDATE`);
  const user = await tx.user.findUnique({ where: { id: userId } });
  if (!user) throw new StoreError(404, 'المستخدم غير موجود', 'USER_NOT_FOUND');
  const active = await tx.userSpecialId.findFirst({ where: { userId, status: 'active' } });
  if (active) {
    if (source !== 'store' || active.displayId !== displayId) {
      throw new StoreError(409, 'المستلم لديه آيدي مميز فعال بالفعل', 'ACTIVE_SPECIAL_ID');
    }
    if (!active.expiresAt) throw new StoreError(409, 'هذا الرقم ملكك بشكل دائم', 'ALREADY_YOURS');
    const expiresAt = durationDays == null ? null : new Date(Math.max(Date.now(), +new Date(active.expiresAt)) + durationDays * DAY_MS);
    return tx.userSpecialId.update({ where: { id: active.id }, data: { expiresAt } });
  }
  const holder = await tx.user.findFirst({ where: { displayId } });
  const reserved = await tx.userSpecialId.findFirst({ where: { status: 'active', OR: [{ displayId }, { originalDisplayId: displayId }] } });
  if (holder || reserved) throw new StoreError(409, 'الرقم مستخدم أو محجوز بالفعل', 'ID_TAKEN');
  const holding = await tx.userSpecialId.create({ data: {
    userId, displayId, originalDisplayId: user.displayId, source, grantedBy,
    expiresAt: durationDays == null ? null : new Date(Date.now() + durationDays * DAY_MS),
  } });
  await tx.user.update({ where: { id: userId }, data: { displayId } });
  await tx.displayIdHistory.create({ data: { userId, oldId: user.displayId, newId: displayId, orderId } });
  return holding;
}

export async function buyStoreProduct(userId: number, productId: number, idempotencyKey: string) {
  return purchaseStoreProduct(userId, productId, idempotencyKey);
}

async function purchaseStoreProduct(userId: number, productId: number, idempotencyKey: string, recipientUserId: number | null = null) {
  validateSpecialId(userId);
  if (!positiveId(productId)) throw new StoreError(400, 'المنتج غير صالح', 'BAD_PRODUCT');
  const key = String(idempotencyKey || '').slice(0, 120);
  if (!key) throw new StoreError(400, 'مفتاح العملية مطلوب', 'NO_KEY');
  const targetId = recipientUserId ?? userId;
  const done = await specialTransaction(async (tx: any) => {
    const prior = await tx.storeOrder.findUnique({ where: { idempotencyKey: key } });
    if (prior) {
      if (prior.userId !== userId || prior.productId !== productId || (prior.recipientUserId ?? null) !== recipientUserId) {
        throw new StoreError(409, 'مفتاح عملية مستخدم لطلب آخر', 'KEY_REUSED');
      }
      return prior;
    }
    const locked: any[] = await tx.$queryRaw(Prisma.sql`SELECT * FROM "store_products" WHERE "id" = ${productId} FOR UPDATE`);
    const p = locked[0];
    if (!p) throw new StoreError(404, 'المنتج غير موجود', 'NOT_FOUND');
    if (recipientUserId !== null && p.kind !== 'special_id') throw new StoreError(400, 'المنتج ليس آيدي مميز', 'BAD_PRODUCT');
    const active = p.kind === 'special_id' && recipientUserId === null
      ? await tx.userSpecialId.findFirst({ where: { userId, displayId: p.specialDisplayId, status: 'active' } }) : null;
    // A sold special ID remains renewable by its current rental holder.
    if (!active && !p.isAvailable) throw new StoreError(409, 'المنتج لم يعد متاحاً', 'UNAVAILABLE');
    if (!active && p.stock != null && p.stock <= 0) throw new StoreError(409, 'نفد المنتج', 'SOLD_OUT');
    const recipient = await tx.user.findUnique({ where: { id: targetId }, select: { displayId: true } });
    if (!recipient) throw new StoreError(404, 'المستخدم غير موجود', 'USER_NOT_FOUND');
    const order = await tx.storeOrder.create({ data: {
      userId, productId, recipientUserId, priceCoins: p.priceCoins, idempotencyKey: key, oldDisplayId: recipient.displayId,
    } });
    let newDisplayId: number | null = null;
    if (p.kind === 'special_id') {
      newDisplayId = Number(p.specialDisplayId);
      await assignSpecialId(tx, targetId, newDisplayId, p.durationDays, recipientUserId === null ? 'store' : 'gift',
        recipientUserId === null ? null : userId, order.id);
    }
    const debit = await tx.user.updateMany({
      where: { id: userId, coinsBalance: { gte: p.priceCoins } },
      data: { coinsBalance: { decrement: p.priceCoins } },
    });
    if (debit.count !== 1) throw new StoreError(402, 'رصيد غير كافٍ', 'INSUFFICIENT');
    const ledger = await tx.transaction.create({ data: {
      userId, type: 'STORE_PURCHASE', amountCoins: p.priceCoins, status: 'completed', externalId: `store_order:${order.id}`,
    } });
    if (p.kind !== 'special_id' && p.itemId) {
      const expiresAt = p.durationDays ? new Date(Date.now() + p.durationDays * DAY_MS) : null;
      await tx.userItem.upsert({ where: { userId_itemId: { userId, itemId: p.itemId } },
        create: { userId, itemId: p.itemId, expiresAt }, update: { expiresAt } });
    }
    if (!active) {
      const soldOut = p.kind === 'special_id' || (p.stock != null && p.stock - 1 <= 0);
      await tx.storeProduct.update({ where: { id: productId }, data: {
        ...(p.stock != null ? { stock: { decrement: 1 } } : {}), ...(soldOut ? { isAvailable: false } : {}),
      } });
    }
    // Persist the notification in the same transaction: retries cannot duplicate it.
    await tx.notification.create({ data: { userId: targetId, type: 'store_purchase',
      title: recipientUserId === null ? 'تم الشراء' : 'وصلتك هدية',
      body: newDisplayId ? `أصبح رقمك المميز ${newDisplayId}` : `تم شراء ${p.name}`,
      data: { orderId: order.id, productId, senderId: userId },
    } });
    return tx.storeOrder.update({ where: { id: order.id }, data: {
      status: 'COMPLETED', completedAt: new Date(), newDisplayId, transactionId: ledger.id,
    } });
  });
  return done;
}

// orderId selects a product from the sender's own order; this is a new paid
// purchase, never a transfer that would change the sender's current ID.
export async function sendSpecialId(userId: number, input: { orderId?: number; productId?: number; toUserId: number }, idempotencyKey: string) {
  validateSpecialId(userId);
  validateSpecialId(input.toUserId);
  if (input.toUserId === userId) throw new StoreError(400, 'اختر مستلماً آخر', 'SELF_GIFT');
  if ((input.orderId == null) === (input.productId == null)) throw new StoreError(400, 'حدد الطلب أو المنتج فقط', 'INVALID_INPUT');
  let productId = input.productId;
  if (input.orderId != null) {
    if (!positiveId(input.orderId)) throw new StoreError(400, 'الطلب غير صالح', 'INVALID_INPUT');
    const order = await db.storeOrder.findUnique({ where: { id: input.orderId } });
    if (!order || order.userId !== userId) throw new StoreError(404, 'الطلب غير موجود', 'NOT_FOUND');
    productId = order.productId;
  }
  return purchaseStoreProduct(userId, productId!, idempotencyKey, input.toUserId);
}

export async function grantSpecialId(adminId: number, userId: number, displayId: number, durationDays: number | null) {
  validateSpecialId(adminId);
  return specialTransaction(async (tx: any) => {
    const holding = await assignSpecialId(tx, userId, displayId, durationDays, 'admin', adminId);
    await recordAdminAuditStrict(tx, { adminId, action: 'SPECIAL_ID_GRANT', targetType: 'user', targetId: userId, before: null, after: holding });
    return holding;
  });
}

async function restoreSpecialId(tx: any, userId: number, status: 'revoked' | 'expired', adminId?: number, now = new Date()) {
  await tx.$queryRaw(Prisma.sql`SELECT "id" FROM "users" WHERE "id" = ${userId} FOR UPDATE`);
  const holding = await tx.userSpecialId.findFirst({ where: { userId, status: 'active' } });
  if (!holding || (status === 'expired' && (!holding.expiresAt || +new Date(holding.expiresAt) >= +now))) return null;
  await tx.user.update({ where: { id: userId }, data: { displayId: holding.originalDisplayId } });
  const after = await tx.userSpecialId.update({ where: { id: holding.id }, data: { status } });
  await tx.displayIdHistory.create({ data: { userId, oldId: holding.displayId, newId: holding.originalDisplayId } });
  if (adminId != null) await recordAdminAuditStrict(tx, {
    adminId, action: 'SPECIAL_ID_REVOKE', targetType: 'user', targetId: userId, before: holding, after,
  });
  if (status === 'expired') await tx.notification.create({ data: {
    userId, type: 'store_purchase', title: 'انتهت مدة الآيدي المميز',
    body: 'انتهت مدة الآيدي المميز وتمت استعادة رقمك الأصلي', data: { specialId: holding.id, displayId: holding.originalDisplayId },
  } });
  return after;
}

export async function revokeSpecialId(adminId: number, userId: number) {
  validateSpecialId(adminId);
  validateSpecialId(userId);
  return specialTransaction((tx) => restoreSpecialId(tx, userId, 'revoked', adminId));
}

export async function listSpecialIds(userId?: number) {
  if (userId !== undefined) validateSpecialId(userId);
  return db.userSpecialId.findMany({ where: { status: 'active', ...(userId === undefined ? {} : { userId }) }, orderBy: { id: 'desc' } });
}

export async function sweepExpiredSpecialIds(now = new Date()) {
  const expired = await db.userSpecialId.findMany({ where: { status: 'active', expiresAt: { lt: now } }, select: { userId: true } });
  for (const row of expired) {
    try {
      await specialTransaction((tx) => restoreSpecialId(tx, row.userId, 'expired', undefined, now));
    } catch (e) {
      console.error('[special-id.expiry]', row.userId, e);
    }
  }
}

/** Numbers listed for sale must never be handed out by the normal allocator. */
export async function isReservedDisplayId(tx: any, id: number): Promise<boolean> {
  const p = await tx.storeProduct?.findFirst?.({ where: { specialDisplayId: id, isAvailable: true }, select: { id: true } });
  const holding = await tx.userSpecialId?.findFirst?.({ where: { status: 'active', OR: [{ displayId: id }, { originalDisplayId: id }] }, select: { id: true } });
  return !!p || !!holding;
}

// ── admin (requires store.products) ────────────────────────────────────────
const audit = (tx: any, req: any, action: string, targetId: any, before: unknown, after: unknown) =>
  recordAdminAuditStrict(tx, { adminId: Number(req.userId), action, targetType: 'store', targetId, before, after, ...auditContext(req) });

export async function adminList() {
  return db.storeCategory.findMany({
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    include: { products: { orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] } },
  });
}

export async function saveCategory(req: any) {
  const b = req.body ?? {};
  return prisma.$transaction(async (tx: any) => {
    const id = Number(req.params.id) || null;
    const before = id ? await tx.storeCategory.findUnique({ where: { id } }) : null;
    const data: any = {};
    if (b.name !== undefined) data.name = String(b.name).trim().slice(0, 80);
    if (b.imageUrl !== undefined) data.imageUrl = b.imageUrl ? String(b.imageUrl) : null;
    if (b.sortOrder !== undefined) data.sortOrder = Math.floor(Number(b.sortOrder) || 0);
    if (b.isActive !== undefined) data.isActive = !!b.isActive;
    if (!id && !data.name) throw new StoreError(400, 'اسم القائمة مطلوب');
    const after = id ? await tx.storeCategory.update({ where: { id }, data }) : await tx.storeCategory.create({ data });
    await audit(tx, req, id ? 'STORE_CATEGORY_UPDATE' : 'STORE_CATEGORY_CREATE', after.id, before, after);
    return after;
  });
}

export async function deleteCategory(req: any) {
  const id = Number(req.params.id);
  return prisma.$transaction(async (tx: any) => {
    const before = await tx.storeCategory.findUnique({ where: { id }, include: { products: true } });
    if (!before) throw new StoreError(404, 'القائمة غير موجودة');
    // Products are hidden with their list, never deleted with it (orders keep pointing at them).
    await tx.storeProduct.updateMany({ where: { categoryId: id }, data: { isAvailable: false } });
    await tx.storeCategory.update({ where: { id }, data: { isActive: false } });
    await audit(tx, req, 'STORE_CATEGORY_DELETE', id, before, { isActive: false });
    return { ok: true };
  });
}

export async function saveProduct(req: any) {
  const b = req.body ?? {};
  return prisma.$transaction(async (tx: any) => {
    const id = Number(req.params.productId) || null;
    const before = id ? await tx.storeProduct.findUnique({ where: { id } }) : null;
    const data: any = {};
    if (b.categoryId !== undefined) data.categoryId = Number(b.categoryId);
    if (b.kind !== undefined) data.kind = b.kind === 'item' ? 'item' : 'special_id';
    if (b.name !== undefined) data.name = String(b.name).trim().slice(0, 80);
    if (b.imageUrl !== undefined) data.imageUrl = b.imageUrl ? String(b.imageUrl) : null;
    if (b.priceCoins !== undefined) {
      const p = Math.floor(Number(b.priceCoins));
      if (!Number.isFinite(p) || p < 0) throw new StoreError(400, 'السعر غير صالح');
      data.priceCoins = p;
    }
    if (b.currency !== undefined) data.currency = 'coins';
    if (b.durationDays !== undefined) data.durationDays = Number(b.durationDays) > 0 ? Math.floor(Number(b.durationDays)) : null;
    if (b.stock !== undefined) data.stock = b.stock === '' || b.stock == null ? null : Math.max(0, Math.floor(Number(b.stock)));
    if (b.isAvailable !== undefined) data.isAvailable = !!b.isAvailable;
    if (b.itemId !== undefined) data.itemId = b.itemId ? String(b.itemId) : null;
    if (b.sortOrder !== undefined) data.sortOrder = Math.floor(Number(b.sortOrder) || 0);
    if (b.specialDisplayId !== undefined) {
      const n = Math.floor(Number(b.specialDisplayId));
      if (!Number.isFinite(n) || n < 1000) throw new StoreError(400, 'رقم الـ ID غير صالح');
      const holder = await tx.user.findFirst({ where: { displayId: n }, select: { id: true } });
      if (holder) throw new StoreError(409, `الرقم ${n} مستخدم بالفعل`);
      data.specialDisplayId = n;
    }
    if (!id && (data.categoryId == null || data.priceCoins == null || !data.name)) throw new StoreError(400, 'القائمة والاسم والسعر مطلوبة');
    const after = id ? await tx.storeProduct.update({ where: { id }, data }) : await tx.storeProduct.create({ data });
    const priceChanged = before && before.priceCoins !== after.priceCoins;
    await audit(tx, req, id ? (priceChanged ? 'PRODUCT_PRICE_UPDATE' : 'PRODUCT_UPDATE') : 'PRODUCT_CREATE', after.id, before, after);
    return after;
  });
}

export async function bulkAddIds(req: any) {
  const b = req.body ?? {};
  const ids: number[] = [...new Set<number>((Array.isArray(b.ids) ? b.ids : String(b.ids ?? '').split(/[\s,]+/)).map((x: any) => Math.floor(Number(x))).filter((n: number) => Number.isFinite(n) && n >= 1000))];
  const price = Math.floor(Number(b.priceCoins));
  const categoryId = Number(b.categoryId);
  if (!ids.length || ids.length > 500 || !(price >= 0) || !categoryId) throw new StoreError(400, 'أدخل الأرقام والسعر والقائمة');
  return prisma.$transaction(async (tx: any) => {
    const taken = await tx.user.findMany({ where: { displayId: { in: ids } }, select: { displayId: true } });
    const listed = await tx.storeProduct.findMany({ where: { specialDisplayId: { in: ids } }, select: { specialDisplayId: true } });
    const skip = new Set<number>([...taken.map((t: any) => t.displayId), ...listed.map((t: any) => t.specialDisplayId)]);
    const fresh = ids.filter((n) => !skip.has(n));
    for (const n of fresh) {
      await tx.storeProduct.create({ data: { categoryId, kind: 'special_id', name: `ID ${n}`, priceCoins: price, specialDisplayId: n, stock: 1 } });
    }
    await audit(tx, req, 'PRODUCT_CREATE', `bulk:${categoryId}`, null, { added: fresh, skipped: [...skip], priceCoins: price });
    return { added: fresh.length, skipped: [...skip] };
  });
}

export async function deleteProduct(req: any) {
  const id = Number(req.params.productId);
  return prisma.$transaction(async (tx: any) => {
    const before = await tx.storeProduct.findUnique({ where: { id } });
    if (!before) throw new StoreError(404, 'المنتج غير موجود');
    const orders = await tx.storeOrder.count({ where: { productId: id } });
    if (orders) await tx.storeProduct.update({ where: { id }, data: { isAvailable: false } });
    else await tx.storeProduct.delete({ where: { id } });
    await audit(tx, req, 'PRODUCT_DELETE', id, before, orders ? { isAvailable: false } : null);
    return { ok: true };
  });
}

export const _MIN = MIN_DISPLAY_ID;
