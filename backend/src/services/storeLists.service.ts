import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { MIN_DISPLAY_ID } from '../utils/displayId';
import { recordAdminAuditStrict, auditContext } from './adminAudit.service';
import { createNotification } from './notification.service';

/**
 * SPEC52 #41 — owner-created store lists (e.g. «ID مميز») and purchases.
 *
 * Buying a special ID never changes anything on the tap itself:
 *   create order (PENDING, unique idempotency key)
 *   → ONE serializable transaction: lock the product row (FOR UPDATE),
 *     check available + stock, check no account holds that ID, guarded coin
 *     debit, ledger row, assign users.displayId, history row, stock/sold-out,
 *     order COMPLETED
 *   → any failure rolls the whole transaction back, the order is FAILED
 *     with the reason, and no coins move.
 * A retry with the same key returns the same order. The old ID is released
 * (anyone may get it again later through the normal allocator).
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

export async function buyStoreProduct(userId: number, productId: number, idempotencyKey: string) {
  const key = String(idempotencyKey || '').slice(0, 120);
  if (!key) throw new StoreError(400, 'مفتاح العملية مطلوب', 'NO_KEY');
  const prior = await db.storeOrder.findUnique({ where: { idempotencyKey: key } });
  if (prior) {
    if (prior.userId !== userId || prior.productId !== productId) throw new StoreError(409, 'مفتاح عملية مستخدم لطلب آخر', 'KEY_REUSED');
    return prior;
  }
  const product = await db.storeProduct.findUnique({ where: { id: productId } });
  if (!product) throw new StoreError(404, 'المنتج غير موجود', 'NOT_FOUND');
  const me = await db.user.findUnique({ where: { id: userId }, select: { displayId: true } });
  const order = await db.storeOrder.create({
    data: { userId, productId, priceCoins: product.priceCoins, idempotencyKey: key, oldDisplayId: me?.displayId ?? null },
  });

  const isConflict = (e: any) => e?.code === 'P2034' || String(e?.message ?? '').includes('40001');
  try {
    const run = () => prisma.$transaction(
      async (tx: any) => {
        // Lock the product so two buyers cannot both pass the checks.
        const locked: any[] = await tx.$queryRaw(Prisma.sql`SELECT * FROM "store_products" WHERE "id" = ${productId} FOR UPDATE`);
        const p = locked[0];
        if (!p || !p.isAvailable) throw new StoreError(409, 'المنتج لم يعد متاحاً', 'UNAVAILABLE');
        if (p.stock != null && p.stock <= 0) throw new StoreError(409, 'نفد المنتج', 'SOLD_OUT');

        let newDisplayId: number | null = null;
        if (p.kind === 'special_id') {
          newDisplayId = Number(p.specialDisplayId);
          if (!newDisplayId) throw new StoreError(409, 'المنتج غير صالح', 'BAD_PRODUCT');
          const holder = await tx.user.findFirst({ where: { displayId: newDisplayId }, select: { id: true } });
          if (holder && holder.id !== userId) throw new StoreError(409, 'الرقم لم يعد متاحاً', 'ID_TAKEN');
          if (holder?.id === userId) throw new StoreError(409, 'هذا الرقم هو رقمك بالفعل', 'ALREADY_YOURS');
        }

        const debit = await tx.user.updateMany({
          where: { id: userId, coinsBalance: { gte: p.priceCoins } },
          data: { coinsBalance: { decrement: p.priceCoins } },
        });
        if (debit.count === 0) throw new StoreError(402, 'رصيد غير كافٍ', 'INSUFFICIENT');

        const ledger = await tx.transaction.create({
          data: { userId, type: 'STORE_PURCHASE', amountCoins: p.priceCoins, status: 'completed', externalId: `store_order:${order.id}` },
        });

        if (p.kind === 'special_id') {
          await tx.user.update({ where: { id: userId }, data: { displayId: newDisplayId } });
          await tx.displayIdHistory.create({ data: { userId, oldId: order.oldDisplayId, newId: newDisplayId!, orderId: order.id } });
        } else if (p.itemId) {
          const expiresAt = p.durationDays ? new Date(Date.now() + p.durationDays * 86_400_000) : null;
          await tx.userItem.upsert({
            where: { userId_itemId: { userId, itemId: p.itemId } },
            create: { userId, itemId: p.itemId, expiresAt },
            update: { expiresAt },
          });
        }

        // One special ID = one sale. Other products: stock counts down.
        const soldOut = p.kind === 'special_id' || (p.stock != null && p.stock - 1 <= 0);
        await tx.storeProduct.update({
          where: { id: productId },
          data: { ...(p.stock != null ? { stock: { decrement: 1 } } : {}), ...(soldOut ? { isAvailable: false } : {}) },
        });
        return tx.storeOrder.update({
          where: { id: order.id },
          data: { status: 'COMPLETED', completedAt: new Date(), newDisplayId, transactionId: ledger.id },
        });
      },
      { isolationLevel: 'Serializable', timeout: 15000 },
    );
    // A concurrent buyer makes Postgres abort one transaction (40001): run it
    // again — it then sees the product sold and fails cleanly.
    let done: any;
    for (let attempt = 0; ; attempt++) {
      try {
        done = await run();
        break;
      } catch (e) {
        if (isConflict(e) && attempt < 3) continue;
        throw e;
      }
    }
    await createNotification({
      userId,
      type: 'store_purchase',
      title: 'تم الشراء ✅',
      body: done.newDisplayId ? `أصبح رقمك المميز ${done.newDisplayId}` : `تم شراء ${product.name}`,
      data: { orderId: done.id, productId },
    }).catch(() => {});
    return done;
  } catch (e: any) {
    const reason = e instanceof StoreError ? e.message : e?.code === 'P2002' ? 'الرقم لم يعد متاحاً' : 'تعذر إتمام الشراء';
    await db.storeOrder.update({ where: { id: order.id }, data: { status: 'FAILED', failureReason: reason } }).catch(() => {});
    if (e instanceof StoreError) throw e;
    if (e?.code === 'P2002') throw new StoreError(409, 'الرقم لم يعد متاحاً', 'ID_TAKEN');
    if (isConflict(e)) throw new StoreError(409, 'حاول مرة أخرى', 'RETRY');
    throw e;
  }
}

/** Numbers listed for sale must never be handed out by the normal allocator. */
export async function isReservedDisplayId(tx: any, id: number): Promise<boolean> {
  const p = await tx.storeProduct?.findFirst?.({ where: { specialDisplayId: id, isAvailable: true }, select: { id: true } });
  return !!p;
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
