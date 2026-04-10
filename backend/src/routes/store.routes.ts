import { Router } from "express";
import prisma from "../utils/prisma";
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

router.use(authMiddleware);

router.post("/buy", async (req: any, res) => {
  try {
    const userId = req.userId!;
    const { productId } = req.body;
    const itemId = String(productId);

    const item = await prisma.item.findUnique({ where: { id: itemId } });
    if (!item) {
      return res.status(404).json({ success: false, message: "المنتج غير موجود" });
    }

    const priceCoins = BigInt(item.priceCoins);

    try {
      await prisma.$transaction(async (tx) => {
        const user = await tx.user.findUnique({
          where: { id: userId },
          select: { coinsBalance: true },
        });

        if (!user) throw new Error('USER_NOT_FOUND');
        if (BigInt(user.coinsBalance as any) < priceCoins) throw new Error('INSUFFICIENT_COINS');

        await tx.user.update({
          where: { id: userId },
          data: { coinsBalance: { decrement: Number(priceCoins) } as any },
        });

        await tx.userItem.create({
          data: { userId, itemId },
        });
      });

      return res.json({ success: true, message: "تم الشراء بنجاح" });
    } catch (err: any) {
      if (err?.message === 'INSUFFICIENT_COINS') {
        return res.status(400).json({ success: false, message: 'رصيد الكوينز غير كافٍ' });
      }
      if (err?.code === "P2002") {
        return res.status(200).json({ success: true, message: "تم الشراء مسبقاً" });
      }
      throw err;
    }
  } catch (e) {
    console.error("BUY ERROR:", e);
    return res.status(500).json({ success: false, message: "خطأ في الشراء" });
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
      success: true,
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
    res.status(500).json({ success: false, message: "خطأ في الحقيبة" });
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
      return res.status(400).json({ success: false, message: "غير مملوك" });
    }

    const isTogglingOff = userItem.isActive;
    if (isTogglingOff && (userItem.item.type === 'AVATAR_FRAME' || userItem.item.type === 'avatar_frame')) {
      await prisma.user.update({ where: { id: userId }, data: { avatarFrameUrl: null } });
      await prisma.userItem.update({ where: { id: inventoryId }, data: { isActive: false } });
      return res.json({ success: true, deactivated: true });
    }

    await prisma.userItem.updateMany({
      where: { userId, item: { type: userItem.item.type } },
      data: { isActive: false },
    });

    await prisma.userItem.update({ where: { id: inventoryId }, data: { isActive: true } });

    if (userItem.item.type === 'AVATAR_FRAME' || userItem.item.type === 'avatar_frame') {
      await prisma.user.update({ where: { id: userId }, data: { avatarFrameUrl: userItem.item.assetUrl } });
    }

    res.json({ success: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ success: false, message: "خطأ في التفعيل" });
  }
});

router.get("/products", async (_req, res) => {
  try {
    const items = await prisma.item.findMany();
    res.json({
      success: true,
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
    res.status(500).json({ success: false, message: "خطأ في المنتجات" });
  }
});

export default router;
