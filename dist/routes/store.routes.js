"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const prisma_1 = __importDefault(require("../utils/prisma"));
const router = (0, express_1.Router)();
router.post("/buy", async (req, res) => {
    try {
        const userId = req.userId || 1;
        const { productId } = req.body;
        const itemId = String(productId);
        console.log("BUY:", userId, itemId);
        const item = await prisma_1.default.item.findUnique({
            where: { id: itemId },
        });
        if (!item) {
            return res.status(404).json({ message: "المنتج غير موجود" });
        }
        try {
            await prisma_1.default.userItem.create({
                data: {
                    userId,
                    itemId,
                },
            });
            return res.json({
                success: true,
                message: "تم الشراء بنجاح",
            });
        }
        catch (err) {
            console.log("PRISMA ERROR:", err.code);
            if (err.code === "P2002") {
                return res.status(200).json({
                    success: true,
                    message: "تم الشراء مسبقاً",
                });
            }
            throw err;
        }
    }
    catch (e) {
        console.error("BUY ERROR:", e);
        return res.status(500).json({ message: "خطأ في الشراء" });
    }
});
router.get("/inventory", async (req, res) => {
    try {
        const userId = req.userId || 1;
        const items = await prisma_1.default.userItem.findMany({
            where: { userId },
            include: { item: true },
        });
        res.json({
            data: items.map(i => ({
                id: i.id,
                product_id: i.item.id,
                name: i.item.name,
                type: i.item.type,
                file_url: i.item.assetUrl,
                preview_url: i.item.assetUrl,
                is_active: i.isActive,
            }))
        });
    }
    catch (e) {
        console.error(e);
        res.status(500).json({ message: "خطأ في الحقيبة" });
    }
});
router.post("/activate", async (req, res) => {
    try {
        const userId = req.userId || 1;
        const { inventoryId } = req.body;
        const userItem = await prisma_1.default.userItem.findUnique({
            where: { id: inventoryId },
            include: { item: true },
        });
        if (!userItem || userItem.userId !== userId) {
            return res.status(400).json({ message: "غير مملوك" });
        }
        const isTogglingOff = userItem.isActive;
        if (isTogglingOff &&
            (userItem.item.type === 'AVATAR_FRAME' || userItem.item.type === 'avatar_frame')) {
            await prisma_1.default.user.update({
                where: { id: userId },
                data: { avatarFrameUrl: null },
            });
            await prisma_1.default.userItem.update({
                where: { id: inventoryId },
                data: { isActive: false },
            });
            return res.json({ success: true, deactivated: true });
        }
        await prisma_1.default.userItem.updateMany({
            where: {
                userId,
                item: { type: userItem.item.type },
            },
            data: { isActive: false },
        });
        await prisma_1.default.userItem.update({
            where: { id: inventoryId },
            data: { isActive: true },
        });
        if (userItem.item.type === 'AVATAR_FRAME' ||
            userItem.item.type === 'avatar_frame') {
            await prisma_1.default.user.update({
                where: { id: userId },
                data: { avatarFrameUrl: userItem.item.assetUrl },
            });
        }
        res.json({ success: true });
    }
    catch (e) {
        console.error(e);
        res.status(500).json({ message: "خطأ في التفعيل" });
    }
});
router.get("/products", async (req, res) => {
    try {
        const items = await prisma_1.default.item.findMany();
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
    }
    catch (e) {
        console.error(e);
        res.status(500).json({ message: "خطأ في المنتجات" });
    }
});
exports.default = router;
//# sourceMappingURL=store.routes.js.map