import { Router } from "express";
import prisma from "../utils/prisma";
import { authMiddleware } from "../middlewares/auth.middleware";

const router = Router();

router.use(authMiddleware);

router.post("/buy", async (req: any, res) => {
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
          data: {
            userId,
            itemId,
          },
        });

        return { ok: true as const, userItemId: userItem.id };
      } catch (err: any) {
        if (err?.code === "P2002") {
          return { ok: false as const, status: 200, message: "تم الشراء مسبقاً" };
        }
        throw err;
      }
    });

    if (!purchaseResult.ok) {
      return res.status(purchaseResult.status).json({
        success: purchaseResult.status === 200,
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

router.post("/activate", async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { inventoryId } = req.body;

    const userItem = await prisma.userItem.findUnique({
      where: { id: inventoryId },
      include: { item: true },
    });

    if (!userItem || userItem.userId !== userId) {
      return res.status(400).json({ message: "غير مملوك" });
    }

    const isTogglingOff = userItem.isActive;
    if (
      isTogglingOff &&
      (userItem.item.type === "AVATAR_FRAME" ||
        userItem.item.type === "avatar_frame" ||
        userItem.item.type === "FRAME")
    ) {
      await prisma.user.update({
        where: { id: userId },
        data: { avatarFrameUrl: null, activeFrameId: null },
      });
      await prisma.userItem.update({
        where: { id: inventoryId },
        data: { isActive: false },
      });
      return res.json({ success: true, deactivated: true });
    }

    await prisma.userItem.updateMany({
      where: {
        userId,
        item: { type: userItem.item.type },
      },
      data: { isActive: false },
    });

    await prisma.userItem.update({
      where: { id: inventoryId },
      data: { isActive: true },
    });

    if (
      userItem.item.type === "AVATAR_FRAME" ||
      userItem.item.type === "avatar_frame" ||
      userItem.item.type === "FRAME"
    ) {
      await prisma.user.update({
        where: { id: userId },
        data: {
          avatarFrameUrl: userItem.item.assetUrl,
          activeFrameId: userItem.item.id,
        },
      });
    }

    res.json({ success: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ message: "خطأ في التفعيل" });
  }
});

router.post("/activate-frame", async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { inventoryId, itemId } = req.body;

    const targetInventoryId = String(inventoryId || "");
    const targetItemId = String(itemId || "");

    const userItem = await prisma.userItem.findFirst({
      where: {
        userId,
        ...(targetInventoryId
          ? { id: targetInventoryId }
          : targetItemId
            ? { itemId: targetItemId }
            : {}),
      },
      include: { item: true },
    });

    if (!userItem) return res.status(404).json({ message: "الإطار غير مملوك" });
    if (!["AVATAR_FRAME", "avatar_frame", "FRAME"].includes(userItem.item.type)) {
      return res.status(400).json({ message: "العنصر ليس إطاراً" });
    }

    await prisma.$transaction([
      prisma.userItem.updateMany({
        where: {
          userId,
          item: { type: { in: ["AVATAR_FRAME", "avatar_frame", "FRAME"] } },
        },
        data: { isActive: false },
      }),
      prisma.userItem.update({ where: { id: userItem.id }, data: { isActive: true } }),
      prisma.user.update({
        where: { id: userId },
        data: { activeFrameId: userItem.item.id, avatarFrameUrl: userItem.item.assetUrl },
      }),
    ]);

    return res.json({
      success: true,
      activeFrameId: userItem.item.id,
      frameImageUrl: userItem.item.assetUrl,
    });
  } catch (e) {
    console.error("ACTIVATE FRAME ERROR:", e);
    return res.status(500).json({ message: "خطأ في تفعيل الإطار" });
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
