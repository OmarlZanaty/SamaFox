"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createDailyQuest = exports.completeQuest = exports.updateQuestProgress = exports.getDailyQuests = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
const getDailyQuests = async (req, res) => {
    try {
        const userId = req.user?.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        const dailyQuests = await prisma_1.default.dailyQuest.findMany();
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const userQuests = await prisma_1.default.userQuest.findMany({
            where: {
                userId,
                date: {
                    gte: today
                }
            },
            include: {
                quest: true
            }
        });
        const questsWithProgress = dailyQuests.map(quest => {
            const userQuest = userQuests.find(uq => uq.questId === quest.id);
            return {
                ...quest,
                progress: userQuest?.progress || 0,
                isComplete: userQuest?.isComplete || false,
                userQuestId: userQuest?.id
            };
        });
        res.json(questsWithProgress);
    }
    catch (error) {
        console.error('Error fetching daily quests:', error);
        res.status(500).json({ error: 'Failed to fetch daily quests' });
    }
};
exports.getDailyQuests = getDailyQuests;
const updateQuestProgress = async (userId, metric, incrementBy = 1) => {
    try {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const quests = await prisma_1.default.dailyQuest.findMany({
            where: {
                metric
            }
        });
        for (const quest of quests) {
            let userQuest = await prisma_1.default.userQuest.findFirst({
                where: {
                    userId,
                    questId: quest.id,
                    date: {
                        gte: today
                    }
                }
            });
            if (!userQuest) {
                userQuest = await prisma_1.default.userQuest.create({
                    data: {
                        userId,
                        questId: quest.id,
                        progress: 0,
                        date: new Date()
                    }
                });
            }
            if (!userQuest.isComplete) {
                const newProgress = Math.min(userQuest.progress + incrementBy, quest.target);
                const isComplete = newProgress >= quest.target;
                await prisma_1.default.userQuest.update({
                    where: {
                        id: userQuest.id
                    },
                    data: {
                        progress: newProgress,
                        isComplete
                    }
                });
                if (isComplete && !userQuest.isComplete) {
                    await prisma_1.default.user.update({
                        where: {
                            id: userId
                        },
                        data: {
                            coinsBalance: {
                                increment: quest.rewardCoins
                            }
                        }
                    });
                    return { questCompleted: true, quest, reward: quest.rewardCoins };
                }
            }
        }
        return { questCompleted: false };
    }
    catch (error) {
        console.error('Error updating quest progress:', error);
        return { questCompleted: false };
    }
};
exports.updateQuestProgress = updateQuestProgress;
const completeQuest = async (req, res) => {
    try {
        const userId = req.user?.userId;
        const questIdStr = (0, http_1.firstStr)(req.params.questId);
        if (!userId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!questIdStr)
            return res.status(400).json({ error: 'Invalid questId' });
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const userQuest = await prisma_1.default.userQuest.findFirst({
            where: {
                userId,
                questId: questIdStr,
                date: { gte: today },
            },
            include: { quest: true },
        });
        if (!userQuest)
            return res.status(404).json({ error: 'Quest not found' });
        if (userQuest.isComplete)
            return res.status(400).json({ error: 'Quest already completed' });
        if (userQuest.progress < userQuest.quest.target) {
            return res.status(400).json({ error: 'Quest not completed yet' });
        }
        await prisma_1.default.userQuest.update({
            where: { id: userQuest.id },
            data: { isComplete: true },
        });
        await prisma_1.default.user.update({
            where: { id: userId },
            data: { coinsBalance: { increment: userQuest.quest.rewardCoins } },
        });
        return res.json({ message: 'Quest completed', reward: userQuest.quest.rewardCoins });
    }
    catch (error) {
        console.error('Error completing quest:', error);
        return res.status(500).json({ error: 'Failed to complete quest' });
    }
};
exports.completeQuest = completeQuest;
const createDailyQuest = async (req, res) => {
    try {
        const { name, description, metric, target, rewardCoins } = req.body;
        if (!name || !description || !metric || !target || !rewardCoins) {
            return res.status(400).json({ error: 'Missing required fields' });
        }
        if (target <= 0 || rewardCoins <= 0) {
            return res.status(400).json({ error: 'Target and reward must be greater than 0' });
        }
        const quest = await prisma_1.default.dailyQuest.create({
            data: {
                name,
                description,
                metric,
                target,
                rewardCoins
            }
        });
        res.status(201).json(quest);
    }
    catch (error) {
        console.error('Error creating daily quest:', error);
        res.status(500).json({ error: 'Failed to create daily quest' });
    }
};
exports.createDailyQuest = createDailyQuest;
//# sourceMappingURL=quest.controller.js.map