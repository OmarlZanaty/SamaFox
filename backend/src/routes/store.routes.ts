import { Router } from "express";
import rateLimit from "express-rate-limit";
import prisma from "../utils/prisma";
import { authMiddleware } from "../middlewares/auth.middleware";

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

      try {
        const userItem = await tx.userItem.create({
          data: { userId, itemId },
        });
        return { ok: true as const, userItemId: userItem.id };
      } catch (err: any) {
        if (err?.code === "P2002") {
          return { ok: false as const, status: 409, message: "تم الشراء مسبقاً" };
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
    });
  } catch (e) {
    console.error("BUY ERROR:", e);
    return res.status(500).json({ message: "خطأ في الشراء" });
  }
});

router.get("/inventory", async (req: any, res) => {
  try {
    const userId = req.userId!;

    const items = await prisma.userItem.findMany({
      where: { userId },
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
    // where two concurrent requests deactivate each other's item
    try {
      await prisma.$transaction(async (tx) => {
        await tx.userItem.updateMany({ where: { userId }, data: { isActive: false } });
        const updated = await tx.userItem.updateMany({
          where: { id: String(inventoryId), userId },
          data: { isActive: true },
        });
        if (updated.count === 0) throw new Error('NOT_FOUND');
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

router.post('/deactivate-frame', async (req: any, res) => {
  try {
    const userId = req.userId!;
    await prisma.user.update({
      where: { id: userId },
      data: { activeFrameId: null, avatarFrameUrl: null },
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
    const items = await prisma.item.findMany();

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