"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.toggleAdminStatus = exports.toggleUserBan = exports.deleteRoom = exports.getAllTransactions = exports.removeCoins = exports.deleteProduct = exports.addCoins = exports.getAllUsers = void 0;
exports.getDashboardStats = getDashboardStats;
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
const getAllUsers = async (req, res) => {
    try {
        const users = await prisma_1.default.user.findMany({
            select: {
                id: true,
                name: true,
                email: true,
                phone: true,
                avatarUrl: true,
                level: true,
                xp: true,
                coinsBalance: true,
                vipLevel: true,
                isAdmin: true,
                createdAt: true,
                _count: {
                    select: {
                        followers: true,
                        following: true,
                        ownedRooms: true
                    }
                }
            },
            orderBy: {
                createdAt: 'desc'
            }
        });
        res.json({ users });
    }
    catch (error) {
        res.status(500).json({ message: 'Failed to fetch users' });
    }
};
exports.getAllUsers = getAllUsers;
const addCoins = async (req, res) => {
    try {
        const userIdNum = (0, http_1.intParam)(req.params.userId);
        if (!userIdNum)
            return res.status(400).json({ message: 'Invalid userId' });
        const amt = Number(req.body.amount);
        if (!Number.isFinite(amt) || amt <= 0) {
            return res.status(400).json({ message: 'Invalid amount' });
        }
        const user = await prisma_1.default.user.update({
            where: { id: userIdNum },
            data: { coinsBalance: { increment: amt } },
        });
        await prisma_1.default.transaction.create({
            data: {
                userId: userIdNum,
                type: 'admin_add',
                amountCoins: amt,
                status: 'completed',
            },
        });
        return res.json({
            message: 'Coins added successfully',
            user: { id: user.id, name: user.name, coinsBalance: user.coinsBalance },
        });
    }
    catch (error) {
        console.error('addCoins error:', error);
        return res.status(500).json({ message: 'Failed to add coins' });
    }
};
exports.addCoins = addCoins;
const deleteProduct = async (req, res) => {
    try {
        const id = String(req.params.id);
        const item = await prisma_1.default.item.findUnique({
            where: { id }
        });
        if (!item) {
            return res.status(404).json({ message: 'Product not found' });
        }
        await prisma_1.default.item.delete({
            where: { id }
        });
        return res.json({ message: 'Product deleted successfully' });
    }
    catch (error) {
        console.error('deleteProduct error:', error);
        return res.status(500).json({ message: 'Failed to delete product' });
    }
};
exports.deleteProduct = deleteProduct;
const removeCoins = async (req, res) => {
    try {
        const userIdNum = (0, http_1.intParam)(req.params.userId);
        if (!userIdNum)
            return res.status(400).json({ message: 'Invalid userId' });
        const amt = Number(req.body.amount);
        if (!Number.isFinite(amt) || amt <= 0) {
            return res.status(400).json({ message: 'Invalid amount' });
        }
        const user = await prisma_1.default.user.findUnique({ where: { id: userIdNum } });
        if (!user)
            return res.status(404).json({ message: 'User not found' });
        if (user.coinsBalance < amt) {
            return res.status(400).json({ message: 'Insufficient coins' });
        }
        const updatedUser = await prisma_1.default.user.update({
            where: { id: userIdNum },
            data: { coinsBalance: { decrement: amt } },
        });
        await prisma_1.default.transaction.create({
            data: {
                userId: userIdNum,
                type: 'admin_remove',
                amountCoins: -amt,
                status: 'completed',
            },
        });
        return res.json({
            message: 'Coins removed successfully',
            user: { id: updatedUser.id, name: updatedUser.name, coinsBalance: updatedUser.coinsBalance },
        });
    }
    catch (error) {
        console.error('removeCoins error:', error);
        return res.status(500).json({ message: 'Failed to remove coins' });
    }
};
exports.removeCoins = removeCoins;
async function getDashboardStats(req, res) {
    try {
        const [totalUsers, totalRooms, activeRooms, totalCoins, totalTransactions] = await Promise.all([
            prisma_1.default.user.count(),
            prisma_1.default.room.count(),
            prisma_1.default.room.count({ where: { isActive: true } }),
            prisma_1.default.user.aggregate({ _sum: { coinsBalance: true } }),
            prisma_1.default.transaction.count()
        ]);
        const recentUsers = await prisma_1.default.user.findMany({
            take: 5,
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                name: true,
                avatarUrl: true,
                createdAt: true
            }
        });
        const topRooms = await prisma_1.default.room.findMany({
            take: 5,
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                name: true,
                _count: { select: { members: true } },
                owner: {
                    select: {
                        name: true
                    }
                }
            }
        });
        res.json({
            stats: {
                totalUsers,
                totalRooms,
                activeRooms,
                totalCoins: totalCoins._sum.coinsBalance || 0,
                totalTransactions
            },
            recentUsers,
            topRooms
        });
    }
    catch (error) {
        res.status(500).json({ message: 'Failed to fetch dashboard stats' });
    }
}
;
const getAllTransactions = async (req, res) => {
    try {
        const { page = 1, limit = 20 } = req.query;
        const skip = (Number(page) - 1) * Number(limit);
        const [transactions, total] = await Promise.all([
            prisma_1.default.transaction.findMany({
                take: Number(limit),
                skip,
                orderBy: { createdAt: 'desc' },
                include: {
                    user: {
                        select: {
                            id: true,
                            name: true,
                            avatarUrl: true
                        }
                    }
                }
            }),
            prisma_1.default.transaction.count()
        ]);
        res.json({
            transactions,
            pagination: {
                page: Number(page),
                limit: Number(limit),
                total,
                totalPages: Math.ceil(total / Number(limit))
            }
        });
    }
    catch (error) {
        res.status(500).json({ message: 'Failed to fetch transactions' });
    }
};
exports.getAllTransactions = getAllTransactions;
const deleteRoom = async (req, res) => {
    try {
        const roomIdNum = (0, http_1.intParam)(req.params.roomId);
        if (!roomIdNum)
            return res.status(400).json({ message: 'Invalid roomId' });
        await prisma_1.default.room.delete({ where: { id: roomIdNum } });
        return res.json({ message: 'Room deleted successfully' });
    }
    catch (error) {
        console.error('deleteRoom error:', error);
        return res.status(500).json({ message: 'Failed to delete room' });
    }
};
exports.deleteRoom = deleteRoom;
const toggleUserBan = async (req, res) => {
    try {
        const userIdNum = (0, http_1.intParam)(req.params.userId);
        if (!userIdNum)
            return res.status(400).json({ message: 'Invalid userId' });
        const isBanned = !!req.body.isBanned;
        const reason = typeof req.body.reason === 'string' ? req.body.reason : null;
        return res.status(501).json({
            message: 'Ban system not enabled in schema yet. Add `isBanned` to Prisma User model first.',
            userId: userIdNum,
            requestedIsBanned: isBanned,
            reason,
        });
    }
    catch (error) {
        console.error('toggleUserBan error:', error);
        return res.status(500).json({ message: 'Failed to update user ban status' });
    }
};
exports.toggleUserBan = toggleUserBan;
const toggleAdminStatus = async (req, res) => {
    try {
        const userIdNum = (0, http_1.intParam)(req.params.userId);
        if (!userIdNum)
            return res.status(400).json({ message: 'Invalid userId' });
        const isAdmin = !!req.body.isAdmin;
        const user = await prisma_1.default.user.update({
            where: { id: userIdNum },
            data: { isAdmin },
        });
        return res.json({
            message: isAdmin ? 'User promoted to admin' : 'Admin privileges removed',
            user: { id: user.id, name: user.name, isAdmin: user.isAdmin },
        });
    }
    catch (error) {
        console.error('toggleAdminStatus error:', error);
        return res.status(500).json({ message: 'Failed to update admin status' });
    }
};
exports.toggleAdminStatus = toggleAdminStatus;
//# sourceMappingURL=admin.controller.js.map