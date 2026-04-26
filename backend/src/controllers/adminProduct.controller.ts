import { Request, Response } from "express";
import prisma from "../utils/prisma";

export const createProduct = async (req: Request, res: Response) => {
  try {
    const { name, type, price_coins } = req.body;

    if (!name || !type || !price_coins) {
      return res.status(400).json({ message: "بيانات ناقصة" });
    }

    const file = (req as any).file;
    if (!file) return res.status(400).json({ message: "يجب رفع ملف" });

    const isVideo = file.mimetype.startsWith("video/");
    const isImage = file.mimetype.startsWith("image/");

    if (type === "seat_effect" && !isVideo) {
      return res.status(400).json({ message: "يجب رفع فيديو لهذا النوع" });
    }

    if ((type === "avatar_frame" || type === "frame") && !isImage) {
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
          : type;

    const product = await prisma.item.create({
      data: {
        name,
        description: "",
        type: mappedType,
        assetUrl,
        priceCoins: Number(price_coins),
        isPurchasable: true,
      },
    });

    return res.json({
      id: product.id,
      name: product.name,
      type: product.type,
      price_coins: product.priceCoins,
      file_url: product.assetUrl,
    });
  } catch (error) {
    console.error("createProduct error:", error);
    return res.status(500).json({ message: "فشل إنشاء المنتج" });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const item = await prisma.item.findUnique({ where: { id } });
    if (!item) return res.status(404).json({ message: "Product not found" });

    await prisma.item.delete({ where: { id } });
    return res.json({ message: "Product deleted successfully" });
  } catch (error) {
    console.error("deleteProduct error:", error);
    return res.status(500).json({ message: "Failed to delete product" });
  }
};
