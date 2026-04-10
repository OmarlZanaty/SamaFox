"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.deleteProduct = exports.createProduct = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const createProduct = async (req, res) => {
    try {
        const { name, type, price_coins } = req.body;
        if (!name || !type || !price_coins) {
            return res.status(400).json({
                message: "بيانات ناقصة",
            });
        }
        const file = req.file;
        if (!file) {
            return res.status(400).json({
                message: "يجب رفع ملف",
            });
        }
        const isVideo = file.mimetype.startsWith("video/");
        const isImage = file.mimetype.startsWith("image/");
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
        const assetUrl = `http://54.254.79.239:3000/uploads/${file.filename}`;
        const mappedType = type === "seat_effect"
            ? "ENTRANCE_EFFECT"
            : type === "avatar_frame"
                ? "PROFILE_FRAME"
                : type;
        const product = await prisma_1.default.item.create({
            data: {
                name,
                description: "",
                type: mappedType,
                assetUrl,
                priceCoins: Number(price_coins),
                isPurchasable: true,
            },
        });
        res.json({
            id: product.id,
            name: product.name,
            type: product.type,
            price_coins: product.priceCoins,
            file_url: product.assetUrl,
        });
    }
    catch (error) {
        console.error("createProduct error:", error);
        res.status(500).json({ message: "فشل إنشاء المنتج" });
    }
};
exports.createProduct = createProduct;
const deleteProduct = async (req, res) => {
    try {
        const id = String(req.params.id);
        const item = await prisma_1.default.item.findUnique({
            where: { id }
        });
        if (!item) {
            return res.status(404).json({ message: "Product not found" });
        }
        await prisma_1.default.item.delete({
            where: { id }
        });
        return res.json({ message: "Product deleted successfully" });
    }
    catch (error) {
        console.error("deleteProduct error:", error);
        return res.status(500).json({ message: "Failed to delete product" });
    }
};
exports.deleteProduct = deleteProduct;
//# sourceMappingURL=adminProduct.controller.js.map