"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getUserGameStats = exports.getLeaderboard = exports.playDice = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
const playDice = async (req, res) => {
    try {
        const userId = req.user?.id;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        const user = await prisma_1.default.user.findUnique({
            where: { id: userId }
        });
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }
        const diceResult = Math.floor(Math.random() * 6) + 1;
        const xpReward = 50 * diceResult;
        const updatedUser = await prisma_1.default.user.update({
            where: { id: userId },
            data: {
                xp: { increment: xpReward }
            }
        });
        res.json({
            success: true,
            diceResult,
            xpEarned: xpReward,
            userXp: updatedUser.xp
        });
    }
    catch (error) {
        console.error('Dice game error:', error);
        res.status(500).json({ error: 'Failed to play dice game' });
    }
};
exports.playDice = playDice;
const getLeaderboard = async (req, res) => {
    try {
        const leaderboard = await prisma_1.default.user.findMany({
            take: 10,
            orderBy: { xp: 'desc' },
            select: {
                id: true,
                name: true,
                avatarUrl: true,
                level: true,
                xp: true
            }
        });
        res.json({ leaderboard });
    }
    catch (error) {
        console.error('Leaderboard error:', error);
        res.status(500).json({ error: 'Failed to fetch leaderboard' });
    }
};
exports.getLeaderboard = getLeaderboard;
const getUserGameStats = async (req, res) => {
    try {
        const { userId } = req.params;
        const userIdNum = (0, http_1.intParam)(req.params.userId);
        if (!userIdNum)
            return res.status(400).json({ error: 'Invalid userId' });
        const user = await prisma_1.default.user.findUnique({
            where: { id: userIdNum },
            select: { id: true, name: true, avatarUrl: true, level: true, xp: true }
        });
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }
        res.json(user);
    }
    catch (error) {
        console.error('User stats error:', error);
        res.status(500).json({ error: 'Failed to fetch user stats' });
    }
};
exports.getUserGameStats = getUserGameStats;
//# sourceMappingURL=game.controller.js.map