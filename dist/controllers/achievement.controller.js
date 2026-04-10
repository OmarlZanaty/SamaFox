"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createAchievement = exports.checkAchievements = exports.getUserAchievements = exports.getAllAchievements = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const getAllAchievements = async (req, res) => {
    try {
        const achievements = await prisma_1.default.achievement.findMany({
            orderBy: {
                target: 'asc'
            }
        });
        res.json(achievements);
    }
    catch (error) {
        console.error('Error fetching achievements:', error);
        res.status(500).json({ error: 'Failed to fetch achievements' });
    }
};
exports.getAllAchievements = getAllAchievements;
const getUserAchievements = async (req, res) => {
    try {
        const userId = parseInt(req.params.userId);
        if (isNaN(userId)) {
            return res.status(400).json({ error: 'Invalid user ID' });
        }
        const userAchievements = await prisma_1.default.userAchievement.findMany({
            where: {
                userId
            },
            include: {
                achievement: true
            },
            orderBy: {
                unlockedAt: 'desc'
            }
        });
        res.json(userAchievements);
    }
    catch (error) {
        console.error('Error fetching user achievements:', error);
        res.status(500).json({ error: 'Failed to fetch user achievements' });
    }
};
exports.getUserAchievements = getUserAchievements;
const checkAchievements = async (userId, metric, currentValue) => {
    try {
        const achievements = await prisma_1.default.achievement.findMany({
            where: {
                metric
            }
        });
        const unlockedAchievements = await prisma_1.default.userAchievement.findMany({
            where: {
                userId
            },
            select: {
                achievementId: true
            }
        });
        const unlockedIds = new Set(unlockedAchievements.map(ua => ua.achievementId));
        const toUnlock = achievements.filter(achievement => !unlockedIds.has(achievement.id) && currentValue >= achievement.target);
        if (toUnlock.length > 0) {
            await prisma_1.default.userAchievement.createMany({
                data: toUnlock.map(achievement => ({
                    userId,
                    achievementId: achievement.id
                }))
            });
            return toUnlock;
        }
        return [];
    }
    catch (error) {
        console.error('Error checking achievements:', error);
        return [];
    }
};
exports.checkAchievements = checkAchievements;
const createAchievement = async (req, res) => {
    try {
        const { name, description, iconUrl, target, metric } = req.body;
        if (!name || !description || !iconUrl || !target || !metric) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        if (target <= 0) {
            return res.status(400).json({ error: 'Target must be greater than 0' });
        }
        const achievement = await prisma_1.default.achievement.create({
            data: {
                name,
                description,
                iconUrl,
                target,
                metric
            }
        });
        res.status(201).json(achievement);
    }
    catch (error) {
        console.error('Error creating achievement:', error);
        res.status(500).json({ error: 'Failed to create achievement' });
    }
};
exports.createAchievement = createAchievement;
//# sourceMappingURL=achievement.controller.js.map