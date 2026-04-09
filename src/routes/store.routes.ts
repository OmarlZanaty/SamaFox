import { Router, Request, Response } from "express";
import prisma from "../utils/prisma";

const router = Router();

router.post("/buy", async (req: any, res) => {
  try {
    const userId = req.userId || 1;
    const { productId } = req.body;

    const itemId = String(productId);

    console.log("BUY:", userId, itemId);

    const item = await prisma.item.findUnique({
      where: { id: itemId },
    });

    if (!item) {
      return res.status(404).json({ message: "المنتج غير موجود" });
    }

    try {
      await prisma.userItem.create({
        data: {
          userId,
          itemId,
        },
      });

      return res.json({
        success: true,
        message: "تم الشراء بنجاح",
      });

    } catch (err: any) {
      console.log("PRISMA ERROR:", err.code);

      if (err.code === "P2002") {
        return res.status(200).json({
          success: true,
          message: "تم الشراء مسبقاً",
        });
      }

      throw err;
    }

  } catch (e) {
    console.error("BUY ERROR:", e);
    return res.status(500).json({ message: "خطأ في الشراء" });
  }
});

router.get("/inventory", async (req: any, res) => {
  try {
    const userId = req.userId || 1;

    const items = await prisma.userItem.findMany({
      where: { userId },
      include: { item: true },
    });

    res.json({
      data: items.map(i => ({
        id: i.id, // ✅ FIXED (inventoryId)
        product_id: i.item.id,

        name: i.item.name,
        type: i.item.type,

        file_url: i.item.assetUrl,
        preview_url: i.item.assetUrl,

        is_active: i.isActive,
      }))
    });

  } catch (e) {
    console.error(e);
    res.status(500).json({ message: "خطأ في الحقيبة" });
  }
});

router.post("/activate", async (req: any, res) => {
  try {
    const userId = req.userId || 1;
    const { inventoryId } = req.body;

    const userItem = await prisma.userItem.findUnique({
      where: { id: inventoryId },
      include: { item: true },
    });

    if (!userItem || userItem.userId !== userId) {
      return res.status(400).json({ message: "غير مملوك" });
    }

    // ✅ ADD HERE — toggle off if already active
    const isTogglingOff = userItem.isActive;
    if (
      isTogglingOff &&
      (userItem.item.type === 'AVATAR_FRAME' || userItem.item.type === 'avatar_frame')
    ) {
      await prisma.user.update({
        where: { id: userId },
        data: { avatarFrameUrl: null },
      });
      await prisma.userItem.update({
        where: { id: inventoryId },
        data: { isActive: false },
      });
      return res.json({ success: true, deactivated: true });
    }

    // ✅ deactivate same TYPE only
    await prisma.userItem.updateMany({
      where: {
        userId,
        item: { type: userItem.item.type },
      },
      data: { isActive: false },
    });

    // ✅ activate selected
    await prisma.userItem.update({
      where: { id: inventoryId },
      data: { isActive: true },
    });

    // ✅ sync avatarFrameUrl on user record
    if (
      userItem.item.type === 'AVATAR_FRAME' ||
      userItem.item.type === 'avatar_frame'
    ) {
      await prisma.user.update({
        where: { id: userId },
        data: { avatarFrameUrl: userItem.item.assetUrl },
      });
    }

    res.json({ success: true });

  } catch (e) {
    console.error(e);
    res.status(500).json({ message: "خطأ في التفعيل" });
  }
});

router.get("/products", async (req, res) => {
  try {
    const items = await prisma.item.findMany();

    res.json({
      data: items.map(i => ({
        id: i.id,
        name: i.name,
        type: i.type,
        price_coins: i.priceCoins,
        file_url: i.assetUrl,
        preview_url: i.assetUrl,
      }))
    });

  } catch (e) {
    console.error(e);
    res.status(500).json({ message: "خطأ في المنتجات" });
  }
});

export default router;