"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const room_controller_1 = require("../controllers/room.controller");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const prisma_1 = __importDefault(require("../utils/prisma"));
const router = (0, express_1.Router)();
router.get('/', auth_middleware_1.optionalAuth, room_controller_1.getRooms);
router.get('/:roomId', auth_middleware_1.optionalAuth, room_controller_1.getRoomById);
router.post('/', auth_middleware_1.authMiddleware, room_controller_1.createRoom);
router.patch('/:roomId', auth_middleware_1.authMiddleware, room_controller_1.updateRoom);
router.delete('/:roomId', auth_middleware_1.authMiddleware, room_controller_1.deleteRoom);
router.post('/:roomId/join', auth_middleware_1.authMiddleware, room_controller_1.joinRoom);
router.post('/:roomId/leave', auth_middleware_1.authMiddleware, room_controller_1.leaveRoom);
router.get('/:roomId/messages', auth_middleware_1.authMiddleware, async (req, res) => {
    try {
        const roomId = Number(req.params.roomId);
        const limit = Number(req.query.limit ?? 50);
        const offset = Number(req.query.offset ?? 0);
        if (isNaN(roomId)) {
            return res.status(400).json({ error: 'Invalid roomId' });
        }
        console.log(`📜 Fetching messages for room ${roomId}, limit=${limit}, offset=${offset}`);
        const messages = await prisma_1.default.roomMessage.findMany({
            where: { roomId },
            orderBy: { timestamp: 'asc' },
            take: limit,
            skip: offset,
            include: {
                user: {
                    select: {
                        id: true,
                        name: true,
                        avatarUrl: true
                    }
                }
            }
        });
        const formattedMessages = messages.map((msg) => ({
            id: msg.id,
            roomId: msg.roomId,
            userId: msg.userId,
            username: msg.user?.name ?? 'Unknown',
            content: msg.content,
            timestamp: msg.timestamp.getTime(),
            avatar: msg.user?.avatarUrl ?? null
        }));
        res.json({
            success: true,
            data: formattedMessages
        });
    }
    catch (error) {
        console.error('❌ Error fetching room messages:', error);
        res.status(500).json({ error: 'Failed to fetch messages' });
    }
});
exports.default = router;
//# sourceMappingURL=room.routes.js.map