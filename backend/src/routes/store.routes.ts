import { Router } from "express";
import rateLimit from "express-rate-limit";
import prisma from "../utils/prisma";
import { authMiddleware } from "../middlewares/auth.middleware";
import { createNotification } from "../services/notification.service";
import { expiryFromDuration } from "../services/expiry.service";

const router = Router();

router.use(authMiddleware);

// ✅ FIX: rate limit the buy endpoint to prevent purchase spam
const buyLimiter = rateLimit({
  windowMs: 10 * 1000, // 10 seconds
  max: 5,
  message: { success: false, message: 'Too many purchase requests. Slow down.' },
});

router.post("/buy", buyLimiter, async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { productId } = req.body;
    const itemId = String(productId);

    const purchaseResult = await prisma.$transaction(async (tx) => {
      const item = await tx.item.findUnique({ where: { id: itemId } });
      if (!item) return { ok: false as const, status: 404, message: "المنتج غير موجود" };
      if (!item.isPurchasable) return { ok: false as const, status: 403, message: "هذا المنتج غير متاح للشراء" };

      const user = await tx.user.findUnique({
        where: { id: userId },
        select: { coinsBalance: true },
      });

      if (!user) return { ok: false as const, status: 404, message: "المستخدم غير موجود" };

      const itemPrice = BigInt(item.priceCoins);
      const userBalance = BigInt(user.coinsBalance);
      if (userBalance < itemPrice) {
        return { ok: false as const, status: 400, message: "الرصيد غير كافٍ" };
      }

      await tx.user.update({
        where: { id: userId },
        data: { coinsBalance: { decrement: Number(itemPrice) } },
      });

      // Time-limited products: stamp the term at purchase. Re-buying an
      // expired item is allowed, and buying one you already own EXTENDS it
      // rather than failing, which is what a rental is supposed to do.
      const expiresAt = expiryFromDuration((item as any).durationDays);
      try {
        const userItem = await tx.userItem.create({
          data: { userId, itemId, expiresAt } as any,
        });
        return { ok: true as const, userItemId: userItem.id, expiresAt };
      } catch (err: any) {
        if (err?.code === "P2002") {
          const existing = await tx.userItem.findUnique({
            where: { userId_itemId: { userId, itemId } },
            select: { id: true, expiresAt: true },
          });
          // A permanent copy is already owned — nothing to sell them.
          if (!expiresAt || !existing || (existing as any).expiresAt === null) {
            return { ok: false as const, status: 409, message: "تم الشراء مسبقاً" };
          }
          const base = new Date(
            Math.max(Date.now(), new Date((existing as any).expiresAt).getTime()),
          );
          const extended = new Date(
            base.getTime() + Number((item as any).durationDays) * 24 * 60 * 60 * 1000,
          );
          await tx.userItem.update({
            where: { id: existing.id },
            data: { expiresAt: extended } as any,
          });
          return { ok: true as const, userItemId: existing.id, expiresAt: extended };
        }
        throw err;
      }
    });

    if (!purchaseResult.ok) {
      return res.status(purchaseResult.status).json({
        success: false, // ✅ FIX: was `purchaseResult.status === 200` — always false for errors anyway but logically wrong
        message: purchaseResult.message,
      });
    }

    return res.json({
      success: true,
      message: "تم الشراء بنجاح",
      userItemId: purchaseResult.userItemId,
      expiresAt: purchaseResult.expiresAt ?? null,
    });
  } catch (e) {
    console.error("BUY ERROR:", e);
    return res.status(500).json({ message: "خطأ في الشراء" });
  }
});

// Step 8: send (gift) a store product to another user. Deducts the price from
// the sender, grants the item to the recipient, and notifies both.
router.post("/send", buyLimiter, async (req: any, res) => {
  try {
    const senderId = req.userId!;
    const itemId = String(req.body?.productId ?? req.body?.itemId ?? "");
    let toUserId = Number(req.body?.toUserId);

    // Accept a 6-digit public display ID (what users actually share) and resolve it.
    const toDisplayId = Number(req.body?.toDisplayId);
    if (!toUserId && toDisplayId) {
      const target = await prisma.user.findUnique({
        where: { displayId: toDisplayId },
        select: { id: true },
      });
      if (!target) {
        return res.status(404).json({ success: false, message: "لا يوجد مستخدم بهذا الرقم" });
      }
      toUserId = target.id;
    }

    if (!itemId || !toUserId) {
      return res.status(400).json({ success: false, message: "productId والمستلم مطلوبان" });
    }
    if (toUserId === senderId) {
      return res.status(400).json({ success: false, message: "لا يمكنك إرسال المنتج لنفسك" });
    }

    const result = await prisma.$transaction(async (tx) => {
      const item = await tx.item.findUnique({ where: { id: itemId } });
      if (!item) return { ok: false as const, status: 404, message: "المنتج غير موجود" };
      if (!item.isPurchasable) return { ok: false as const, status: 403, message: "هذا المنتج غير متاح للشراء" };

      const recipient = await tx.user.findUnique({ where: { id: toUserId }, select: { id: true, name: true } });
      if (!recipient) return { ok: false as const, status: 404, message: "المستلم غير موجود" };

      const sender = await tx.user.findUnique({ where: { id: senderId }, select: { coinsBalance: true, name: true } });
      if (!sender) return { ok: false as const, status: 404, message: "المرسل غير موجود" };

      if (BigInt(sender.coinsBalance) < BigInt(item.priceCoins)) {
        return { ok: false as const, status: 400, message: "الرصيد غير كافٍ" };
      }

      await tx.user.update({
        where: { id: senderId },
        data: { coinsBalance: { decrement: item.priceCoins } },
      });

      // Grant to recipient; tolerate them already owning it.
      await tx.userItem.upsert({
        where: { userId_itemId: { userId: toUserId, itemId } },
        update: {},
        create: { userId: toUserId, itemId },
      });

      return {
        ok: true as const,
        itemName: item.name,
        senderName: sender.name,
        recipientName: recipient.name,
      };
    });

    if (!result.ok) {
      return res.status(result.status).json({ success: false, message: result.message });
    }

    // Notify both sides (best-effort).
    try {
      await createNotification({
        userId: toUserId,
        actorId: senderId,
        type: "product_received",
        title: "هدية من المتجر 🎁",
        body: `${result.senderName ?? "مستخدم"} أرسل لك ${result.itemName}`,
        data: { itemId, fromUserId: senderId },
      });
      await createNotification({
        userId: senderId,
        actorId: toUserId,
        type: "product_sent",
        title: "تم الإرسال ✅",
        body: `أرسلت ${result.itemName} إلى ${result.recipientName ?? "مستخدم"}`,
        data: { itemId, toUserId },
      });
    } catch (e) {
      console.warn("store send notification failed:", e);
    }

    return res.json({ success: true, message: "تم إرسال المنتج بنجاح" });
  } catch (e) {
    console.error("STORE SEND ERROR:", e);
    return res.status(500).json({ success: false, message: "خطأ في إرسال المنتج" });
  }
});

router.get("/inventory", async (req: any, res) => {
  try {
    const userId = req.userId!;

    // Expired rentals stop counting as owned the moment they lapse, without
    // waiting for the 15-minute sweep to delete the row.
    const items = await prisma.userItem.findMany({
      where: {
        userId,
        OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
      } as any,
      include: { item: true },
    });

    res.json({
      data: items.map((i) => ({
        id: i.id,
        product_id: i.item.id,
        name: i.item.name,
        type: i.item.type,
        file_url: i.item.assetUrl,
        preview_url: i.item.assetUrl,
        is_active: i.isActive,
        // null = أبدي. The app shows the remaining term from this.
        expires_at: (i as any).expiresAt ?? null,
        duration_days: (i.item as any).durationDays ?? null,
      })),
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: "خطأ في الحقيبة" });
  }
});

router.post('/activate', async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { inventoryId } = req.body;
    if (!inventoryId) return res.status(400).json({ message: 'inventoryId required' });

    // ✅ FIX: wrap both writes in a single transaction to prevent race condition
    // where two concurrent requests deactivate each other's item.
    // Group 12: deactivate only items of the SAME type, so a vehicle, an
    // entrance banner and a chat bubble can all be active at once.
    try {
      await prisma.$transaction(async (tx) => {
        const target = await tx.userItem.findFirst({
          where: { id: String(inventoryId), userId },
          include: { item: { select: { type: true } } },
        });
        if (!target) throw new Error('NOT_FOUND');
        await tx.userItem.updateMany({
          where: { userId, item: { type: target.item.type } },
          data: { isActive: false },
        });
        await tx.userItem.update({
          where: { id: target.id },
          data: { isActive: true },
        });
      });
    } catch (e: any) {
      if (e?.message === 'NOT_FOUND') {
        return res.status(404).json({ success: false, message: 'Inventory item not found for user' });
      }
      throw e;
    }

    return res.json({ success: true });
  } catch (e) {
    console.error("ACTIVATE ERROR:", e);
    return res.status(500).json({ success: false, message: "Failed to activate item" });
  }
});

router.post('/activate-frame', async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { itemId } = req.body;
    if (!itemId) return res.status(400).json({ message: 'itemId required' });

    const userItem = await prisma.userItem.findFirst({
      where: { userId, itemId: String(itemId) },
      include: { item: true },
    });
    if (!userItem) return res.status(404).json({ message: 'Item not in inventory' });

    await prisma.user.update({
      where: { id: userId },
      data: { activeFrameId: String(itemId), avatarFrameUrl: userItem.item.assetUrl },
    });
    return res.json({ success: true });
  } catch (e) {
    console.error("ACTIVATE FRAME ERROR:", e);
    return res.status(500).json({ success: false, message: "Failed to activate frame" });
  }
});

// Unequip a single item. deactivate-all clears EVERY category at once, which
// unequipped the user's vehicle whenever they took off an entrance banner or a
// chat bubble — now that more than one type can be active at a time, the client
// deactivates by inventory id instead.
router.post('/deactivate', async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { inventoryId } = req.body;
    if (!inventoryId) return res.status(400).json({ message: 'inventoryId required' });

    const updated = await prisma.userItem.updateMany({
      where: { id: String(inventoryId), userId },
      data: { isActive: false },
    });
    if (updated.count === 0) {
      return res.status(404).json({ success: false, message: 'Inventory item not found for user' });
    }
    return res.json({ success: true });
  } catch (e) {
    console.error("DEACTIVATE ERROR:", e);
    return res.status(500).json({ success: false, message: "Failed to deactivate item" });
  }
});

router.post('/deactivate-all', async (req: any, res) => {
  try {
    const userId = req.userId!;
    await prisma.userItem.updateMany({ where: { userId }, data: { isActive: false } });
    return res.json({ success: true });
  } catch (e) {
    console.error("DEACTIVATE ALL ERROR:", e);
    return res.status(500).json({ success: false, message: "Failed to deactivate items" });
  }
});

router.post('/deactivate-frame', async (req: any, res) => {
  try {
    const userId = req.userId!;
    await prisma.user.update({
      where: { id: userId },
      data: { activeFrameId: null, avatarFrameUrl: null },
    });
    // Also clear the inventory "in use" flag on frame items — the profile reads
    // UserItem.isActive, so without this the frame kept showing as equipped
    // ("إلغاء الاستخدام not working").
    await prisma.userItem.updateMany({
      where: { userId, item: { type: { in: ['FRAME', 'avatar_frame'] } } },
      data: { isActive: false },
    });
    return res.json({ success: true });
  } catch (e) {
    console.error("DEACTIVATE FRAME ERROR:", e);
    return res.status(500).json({ success: false, message: "Failed to deactivate frame" });
  }
});

router.get("/my-frames", async (req: any, res) => {
  try {
    const userId = req.userId!;
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { activeFrameId: true },
    });

    const items = await prisma.userItem.findMany({
      where: {
        userId,
        item: { itemType: "FRAME" },
      },
      include: { item: true },
    });

    return res.json({
      success: true,
      data: items.map((i) => ({
        id: i.item.id,
        name: i.item.name,
        imageUrl: i.item.assetUrl,
        priceCoins: i.item.priceCoins,
        isActive: i.item.id === user?.activeFrameId,
      })),
    });
  } catch (e) {
    console.error("MY FRAMES ERROR:", e);
    return res.status(500).json({ success: false, message: "Failed to load frames" });
  }
});

router.get("/products", async (_req, res) => {
  try {
    // Private-store items (isPurchasable=false) are hidden from the app —
    // they can only be granted manually from the dashboard (group 9).
    const items = await prisma.item.findMany({ where: { isPurchasable: true } });

    res.json({
      data: items.map((i) => ({
        id: i.id,
        name: i.name,
        type: i.type,
        price_coins: i.priceCoins,
        file_url: i.assetUrl,
        preview_url: i.assetUrl,
      })),
    });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: "خطأ في المنتجات" });
  }
});

export default router;