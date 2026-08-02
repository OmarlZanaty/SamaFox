import { Request, Response } from "express";
import prisma from "../utils/prisma";

export const createProduct = async (req: Request, res: Response) => {
  try {
    const { name, type, price_coins } = req.body;

    if (!name || !type || price_coins == null) {
      return res.status(400).json({ message: "بيانات ناقصة" });
    }

    const file = (req as any).file;
    if (!file) return res.status(400).json({ message: "يجب رفع ملف" });

    const isVideo = file.mimetype.startsWith("video/");
    const isImage = file.mimetype.startsWith("image/");

    if (type === "seat_effect" && !isVideo) {
      return res.status(400).json({ message: "يجب رفع فيديو لهذا النوع" });
    }

    if ((type === "avatar_frame" || type === "frame" || type === "background" || type === "badge" || type === "chat_bubble" || type === "entrance" || type === "chat_top_banner") && !isImage) {
      return res.status(400).json({ message: "يجب رفع صورة لهذا النوع" });
    }

    const configuredBaseUrl = String(process.env.BASE_URL || "").trim().replace(/\/+$/, "");
    const forwardedProto = (String(req.headers["x-forwarded-proto"] || "").split(",")[0] || "").trim();
    const protocol = forwardedProto || req.protocol || "http";
    const host = req.get("host") || "";
    const requestBaseUrl = host ? `${protocol}://${host}` : "";
    const baseUrl = configuredBaseUrl || requestBaseUrl || `http://localhost:${process.env.PORT || 3000}`;
    const assetUrl = `${baseUrl}/uploads/${file.filename}`;

    const mappedType =
      type === "seat_effect"
        ? "ENTRANCE_EFFECT"
        : type === "avatar_frame" || type === "frame"
          ? "FRAME"
          : type === "entrance"
            ? "ENTRANCE_BANNER"
            : type === "badge"
              ? "BADGE"
              : type === "chat_bubble"
                ? "CHAT_BUBBLE"
                : type === "chat_top_banner"
                  ? "CHAT_TOP_BANNER"
                  : type;

    // Group 9: is_private=true puts the item in the Private Store — hidden
    // from the in-app store, only grantable by ID from the dashboard.
    const isPrivate = req.body?.is_private === "true" || req.body?.is_private === true;

    // Owner request: every product gets a term. `duration_days` empty, 0 or
    // "permanent"/"أبدي" means it never expires — the dashboard sends either a
    // day count or the permanent flag.
    const rawDuration = req.body?.duration_days;
    const isPermanent =
      rawDuration === undefined ||
      rawDuration === null ||
      String(rawDuration).trim() === "" ||
      String(rawDuration).trim() === "0" ||
      req.body?.is_permanent === "true" ||
      req.body?.is_permanent === true;
    const durationDays = isPermanent ? null : Math.max(1, Math.floor(Number(rawDuration) || 0)) || null;

    const product = await prisma.item.create({
      data: {
        name,
        description: "",
        type: mappedType,
        assetUrl,
        priceCoins: Number(price_coins),
        isPurchasable: !isPrivate,
        durationDays,
      } as any,
    });

    return res.json({
      id: product.id,
      name: product.name,
      type: product.type,
      price_coins: product.priceCoins,
      file_url: product.assetUrl,
      is_private: !product.isPurchasable,
      duration_days: (product as any).durationDays ?? null,
    });
  } catch (error) {
    console.error("createProduct error:", error);
    return res.status(500).json({ message: "فشل إنشاء المنتج" });
  }
};

// GET /admin-products/products — dashboard list of ALL items (app + private)
export const listProductsAdmin = async (_req: Request, res: Response) => {
  try {
    const items = await prisma.item.findMany({ orderBy: { createdAt: "desc" } });
    return res.json({
      data: items.map((i) => ({
        id: i.id,
        name: i.name,
        type: i.type,
        price_coins: i.priceCoins,
        file_url: i.assetUrl,
        is_private: !i.isPurchasable,
        created_at: i.createdAt,
      })),
    });
  } catch (error) {
    console.error("listProductsAdmin error:", error);
    return res.status(500).json({ message: "فشل تحميل المنتجات" });
  }
};

// PATCH /admin-products/products/:id — move an item between App Store and Private Store
export const setProductVisibility = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const isPrivate = req.body?.is_private === true || req.body?.is_private === "true";
    const item = await prisma.item.update({
      where: { id },
      data: { isPurchasable: !isPrivate },
    });
    return res.json({ id: item.id, is_private: !item.isPurchasable });
  } catch (error: any) {
    if (error?.code === "P2025") return res.status(404).json({ message: "Product not found" });
    console.error("setProductVisibility error:", error);
    return res.status(500).json({ message: "فشل تحديث المنتج" });
  }
};

// POST /admin-products/grant — manually grant an item to a user by display ID (group 9)
export const grantProduct = async (req: Request, res: Response) => {
  try {
    const itemId = String(req.body?.itemId || "");
    const displayId = Number(req.body?.displayId);
    if (!itemId || !displayId) {
      return res.status(400).json({ message: "itemId و displayId مطلوبان" });
    }

    const item = await prisma.item.findUnique({ where: { id: itemId } });
    if (!item) return res.status(404).json({ message: "المنتج غير موجود" });

    const user = await prisma.user.findUnique({
      where: { displayId },
      select: { id: true, name: true, displayId: true },
    });
    if (!user) return res.status(404).json({ message: "لا يوجد مستخدم بهذا الرقم" });

    try {
      await prisma.userItem.create({ data: { userId: user.id, itemId } });
    } catch (err: any) {
      if (err?.code === "P2002") {
        return res.status(409).json({ message: "المستخدم يملك هذا المنتج بالفعل" });
      }
      throw err;
    }

    try {
      const { createNotification } = await import("../services/notification.service");
      await createNotification({
        userId: user.id,
        type: "ITEM_GRANTED",
        title: "🎁 تم منحك منتجاً",
        body: `منحتك إدارة التطبيق: ${item.name}`,
        data: { itemId },
      });
    } catch (e) {
      console.warn("grantProduct notification failed:", e);
    }

    return res.json({
      message: "تم منح المنتج بنجاح",
      user: { id: user.id, displayId: user.displayId, name: user.name },
      item: { id: item.id, name: item.name },
    });
  } catch (error) {
    console.error("grantProduct error:", error);
    return res.status(500).json({ message: "فشل منح المنتج" });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const item = await prisma.item.findUnique({ where: { id } });
    if (!item) return res.status(404).json({ message: "Product not found" });

    await prisma.$transaction(async (tx) => {
      await tx.user.updateMany({
        where: { activeFrameId: id },
        data: { activeFrameId: null, avatarFrameUrl: null },
      });

      await tx.room.updateMany({
        where: { activeThemeId: id },
        data: { activeThemeId: null },
      });

      await tx.userItem.deleteMany({
        where: { itemId: id },
      });

      await tx.item.delete({ where: { id } });
    });

    return res.json({ message: "Product deleted successfully" });
  } catch (error) {
    console.error("deleteProduct error:", error);
    return res.status(500).json({ message: "Failed to delete product" });
  }
};
