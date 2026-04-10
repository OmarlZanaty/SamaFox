"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getUserLevelInfo = exports.getRoomLevelInfo = exports.awardUserXP = exports.awardRoomXP = exports.xpForNextLevel = exports.calculateLevel = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const calculateLevel = (xp) => {
    return Math.floor(Math.sqrt(xp / 100)) + 1;
};
exports.calculateLevel = calculateLevel;
const xpForNextLevel = (currentLevel) => {
    return Math.pow(currentLevel, 2) * 100;
};
exports.xpForNextLevel = xpForNextLevel;
const awardRoomXP = async (roomId, xpAmount) => {
    try {
        const room = await prisma_1.default.room.findUnique({
            where: { id: roomId }
        });
        if (!room) {
            return { success: false, error: 'Room not found' };
        }
        const newXP = room.xp + xpAmount;
        const newLevel = (0, exports.calculateLevel)(newXP);
        const leveledUp = newLevel > room.level;
        await prisma_1.default.room.update({
            where: { id: roomId },
            data: {
                xp: newXP,
                level: newLevel
            }
        });
        return {
            success: true,
            xp: newXP,
            level: newLevel,
            leveledUp,
            xpGained: xpAmount
        };
    }
    catch (error) {
        console.error('Error awarding room XP:', error);
        return { success: false, error: 'Failed to award XP' };
    }
};
exports.awardRoomXP = awardRoomXP;
const awardUserXP = async (userId, xpAmount) => {
    try {
        const user = await prisma_1.default.user.findUnique({
            where: { id: userId }
        });
        if (!user) {
            return { success: false, error: 'User not found' };
        }
        const newXP = user.xp + xpAmount;
        const newLevel = (0, exports.calculateLevel)(newXP);
        const leveledUp = newLevel > user.level;
        await prisma_1.default.user.update({
            where: { id: userId },
            data: {
                xp: newXP,
                level: newLevel
            }
        });
        return {
            success: true,
            xp: newXP,
            level: newLevel,
            leveledUp,
            xpGained: xpAmount
        };
    }
    catch (error) {
        console.error('Error awarding user XP:', error);
        return { success: false, error: 'Failed to award XP' };
    }
};
exports.awardUserXP = awardUserXP;
const getRoomLevelInfo = async (roomId) => {
    try {
        const room = await prisma_1.default.room.findUnique({
            where: { id: roomId },
            select: {
                xp: true,
                level: true
            }
        });
        if (!room) {
            return { success: false, error: 'Room not found' };
        }
        const currentLevelXP = Math.pow(room.level - 1, 2) * 100;
        const nextLevelXP = (0, exports.xpForNextLevel)(room.level);
        const xpInCurrentLevel = room.xp - currentLevelXP;
        const xpNeededForNextLevel = nextLevelXP - room.xp;
        return {
            success: true,
            level: room.level,
            xp: room.xp,
            currentLevelXP,
            nextLevelXP,
            xpInCurrentLevel,
            xpNeededForNextLevel,
            progress: (xpInCurrentLevel / (nextLevelXP - currentLevelXP)) * 100
        };
    }
    catch (error) {
        console.error('Error getting room level info:', error);
        return { success: false, error: 'Failed to get level info' };
    }
};
exports.getRoomLevelInfo = getRoomLevelInfo;
const getUserLevelInfo = async (userId) => {
    try {
        const user = await prisma_1.default.user.findUnique({
            where: { id: userId },
            select: {
                xp: true,
                level: true
            }
        });
        if (!user) {
            return { success: false, error: 'User not found' };
        }
        const currentLevelXP = Math.pow(user.level - 1, 2) * 100;
        const nextLevelXP = (0, exports.xpForNextLevel)(user.level);
        const xpInCurrentLevel = user.xp - currentLevelXP;
        const xpNeededForNextLevel = nextLevelXP - user.xp;
        return {
            success: true,
            level: user.level,
            xp: user.xp,
            currentLevelXP,
            nextLevelXP,
            xpInCurrentLevel,
            xpNeededForNextLevel,
            progress: (xpInCurrentLevel / (nextLevelXP - currentLevelXP)) * 100
        };
    }
    catch (error) {
        console.error('Error getting user level info:', error);
        return { success: false, error: 'Failed to get level info' };
    }
};
exports.getUserLevelInfo = getUserLevelInfo;
//# sourceMappingURL=xp.service.js.map