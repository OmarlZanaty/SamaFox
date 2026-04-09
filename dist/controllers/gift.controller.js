"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendGift = exports.getGiftHistory = exports.getGifts = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const index_1 = require("../index");
const getGifts = async (req, res) => {
    try {
        const { category } = req.query;
        const where = {
            isActive: true,
            ...(category && { category: String(category) })
        };
        const [gifts, total] = await prisma_1.default.$transaction([
            prisma_1.default.gift.findMany({
                where,
                orderBy: { priceCoins: 'asc' }
            }),
            prisma_1.default.gift.count({ where })
        ]);
        res.json({ gifts, total });
    }
    catch (error) {
        console.error('Get gifts error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getGifts = getGifts;
const getGiftHistory = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ error: 'Unauthorized' });
        const pageNum = Number(req.query.page ?? 1);
        const limitNum = Number(req.query.limit ?? 20);
        const page = Number.isFinite(pageNum) && pageNum > 0 ? pageNum : 1;
        const limit = Number.isFinite(limitNum) && limitNum > 0 ? limitNum : 20;
        const skip = (page - 1) * limit;
        const where = {
            OR: [{ senderId: userId }, { receiverId: userId }],
        };
        const [logs, total] = await Promise.all([
            prisma_1.default.giftLog.findMany({
                where,
                orderBy: { createdAt: 'desc' },
                skip,
                take: limit,
                include: {
                    gift: true,
                    sender: { select: { id: true, name: true, avatarUrl: true } },
                    receiver: { select: { id: true, name: true, avatarUrl: true } },
                },
            }),
            prisma_1.default.giftLog.count({ where }),
        ]);
        return res.json({
            logs,
            pagination: { page, limit, total, totalPages: Math.ceil(total / limit) },
        });
    }
    catch (e) {
        console.error('getGiftHistory error:', e);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getGiftHistory = getGiftHistory;
const sendGift = async (req, res) => {
    try {
        const senderId = req.userId;
        if (!senderId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        const { receiverId, giftId, roomId, quantity = 1, message } = req.body;
        const gid = Number(giftId);
        const qty = Math.max(1, Number(quantity) || 1);
        const rid = roomId != null ? Number(roomId) : 0;
        const receiverNum = receiverId != null ? Number(receiverId) : undefined;
        if (!gid) {
            return res.status(400).json({ error: 'Invalid giftId' });
        }
        const gift = await prisma_1.default.gift.findUnique({ where: { id: gid } });
        if (!gift || !gift.isActive) {
            return res.status(404).json({ error: 'Gift not found' });
        }
        const sender = await prisma_1.default.user.findUnique({
            where: { id: senderId },
            select: { id: true, name: true, avatarUrl: true, coinsBalance: true },
        });
        if (!sender) {
            return res.status(404).json({ error: 'Sender not found' });
        }
        let receiver = null;
        if (receiverNum != null) {
            const r = await prisma_1.default.user.findUnique({
                where: { id: receiverNum },
                select: { id: true, name: true, avatarUrl: true, coinsBalance: true },
            });
            if (!r)
                return res.status(404).json({ error: 'Receiver not found' });
            receiver = { id: r.id, name: r.name, avatarUrl: r.avatarUrl };
        }
        const price = Number(gift.priceCoins ?? 0);
        const totalCost = price * qty;
        if (!Number.isFinite(totalCost) || totalCost <= 0) {
            return res.status(400).json({ error: 'Invalid gift price' });
        }
        const receiverCoins = receiverNum != null ? Math.floor(totalCost * 0.5) : 0;
        const result = await prisma_1.default.$transaction(async (tx) => {
            const updated = await tx.user.updateMany({
                where: {
                    id: senderId,
                    coinsBalance: { gte: totalCost },
                },
                data: {
                    coinsBalance: { decrement: totalCost },
                },
            });
            if (updated.count === 0) {
                throw new Error('INSUFFICIENT_COINS');
            }
            let receiverNewBalance = null;
            if (receiverNum != null) {
                const ur = await tx.user.update({
                    where: { id: receiverNum },
                    data: { coinsBalance: { increment: receiverCoins } },
                    select: { coinsBalance: true },
                });
                receiverNewBalance = ur.coinsBalance;
            }
            const us = await tx.user.findUnique({
                where: { id: senderId },
                select: { coinsBalance: true },
            });
            const createdLog = await tx.giftLog.create({
                data: {
                    senderId,
                    receiverId: receiverNum ?? senderId,
                    giftId: gid,
                    roomId: rid || null,
                    coinsSpent: totalCost,
                    quantity: qty,
                    message: message ?? null,
                },
                include: {
                    gift: true,
                    sender: { select: { id: true, name: true, avatarUrl: true } },
                    receiver: { select: { id: true, name: true, avatarUrl: true } },
                },
            });
            await tx.transaction.create({
                data: {
                    userId: senderId,
                    type: 'gift_send',
                    amountCoins: -totalCost,
                    status: 'completed',
                },
            });
            if (receiverNum != null) {
                await tx.transaction.create({
                    data: {
                        userId: receiverNum,
                        type: 'gift_receive',
                        amountCoins: receiverCoins,
                        status: 'completed',
                    },
                });
            }
            return {
                createdLog,
                senderNewBalance: us?.coinsBalance ?? 0,
                receiverNewBalance,
            };
        });
        const createdLog = result.createdLog;
        if (rid && index_1.io) {
            index_1.io.to(`room:${rid}`).emit('gift', {
                roomId: rid,
                type: 'sent',
                giftEvent: {
                    id: createdLog.id,
                    giftId: createdLog.giftId,
                    giftName: createdLog.gift.name,
                    giftImageUrl: createdLog.gift.imageUrl,
                    coinsSpent: totalCost,
                    quantity: qty,
                    message: message ?? null,
                    sender: createdLog.sender,
                    receiver: createdLog.receiver,
                    senderId,
                    senderNewBalance: result.senderNewBalance,
                    receiverId: receiverNum ?? senderId,
                    receiverCoins,
                    receiverNewBalance: result.receiverNewBalance,
                    createdAt: createdLog.createdAt,
                }
            });
        }
        return res.status(201).json({
            message: 'Gift sent successfully',
            gift: {
                id: gift.id,
                name: gift.name,
                imageUrl: gift.imageUrl,
                unitPriceCoins: gift.priceCoins,
                quantity: qty,
                message: message ?? null,
                coinsSpent: totalCost,
            },
            balances: {
                senderId,
                senderNewBalance: result.senderNewBalance,
                receiverId: receiverNum ?? senderId,
                receiverNewBalance: result.receiverNewBalance,
            },
        });
    }
    catch (error) {
        if (error?.message === 'INSUFFICIENT_COINS') {
            return res.status(400).json({ error: 'Insufficient coins balance' });
        }
        console.error('sendGift error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.sendGift = sendGift;
//# sourceMappingURL=gift.controller.js.map