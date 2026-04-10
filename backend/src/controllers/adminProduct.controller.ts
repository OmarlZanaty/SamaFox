import { Request, Response } from "express";
import prisma from "../utils/prisma";
import { getPublicBaseUrl } from "../utils/public-url";

export const createProduct = async (req: Request, res: Response) => {
  try {
    // ✅ STEP 1: get body
    const { name, type, price_coins } = req.body;

    if (!name || !type || !price_coins) {
  return res.status(400).json({
    message: "بيانات ناقصة",
  });
}
    // ✅ STEP 2: get uploaded file (FROM MULTER)
    const file = (req as any).file;

    // 🔥 STEP 3: check file exists
    if (!file) {
      return res.status(400).json({
        message: "يجب رفع ملف",
      });
    }

    // 🔥 STEP 4: detect file type (THIS IS YOUR NEW PART ✔)
    const isVideo = file.mimetype.startsWith("video/");
    const isImage = file.mimetype.startsWith("image/");

    // 🔥 STEP 5: validate based on product type (✔ CORRECT PLACE)
    if (type === "seat_effect" && !isVideo) {
      return res.status(400).json({
        message: "يجب رفع فيديو لهذا النوع",
      });
    }

    if (type === "avatar_frame" && !isImage) {
      return res.status(400).json({
        message: "يجب رفع صورة لهذا النوع",
      });
    }

    // ✅ STEP 6: build file URL
    const assetUrl = `${getPublicBaseUrl(req)}/uploads/${file.filename}`;

    // ✅ STEP 7: map type to DB enum
    const mappedType =
      type === "seat_effect"
        ? "ENTRANCE_EFFECT"
        : type === "avatar_frame"
        ? "PROFILE_FRAME"
        : type;

    // ✅ STEP 8: save to database
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

    // ✅ STEP 9: return response
    res.json({
      id: product.id,
      name: product.name,
      type: product.type,
      price_coins: product.priceCoins,
      file_url: product.assetUrl,
    });

  } catch (error) {
    console.error("createProduct error:", error);
    res.status(500).json({ message: "فشل إنشاء المنتج" });
  }
};

export const deleteProduct = async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id); // ⚠️ IMPORTANT (your item.id is string)

    const item = await prisma.item.findUnique({
      where: { id }
    });

    if (!item) {
      return res.status(404).json({ message: "Product not found" });
    }

    await prisma.item.delete({
      where: { id }
    });

    return res.json({ message: "Product deleted successfully" });

  } catch (error) {
    console.error("deleteProduct error:", error);
    return res.status(500).json({ message: "Failed to delete product" });
  }
};

