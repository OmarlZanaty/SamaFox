"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.leaveRoom = exports.joinRoom = exports.deleteRoom = exports.updateRoom = exports.getRoomById = exports.getRooms = void 0;
exports.createRoom = createRoom;
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
const getRooms = async (req, res) => {
    try {
        const { page = 1, limit = 20, type } = req.query;
        const skip = (Number(page) - 1) * Number(limit);
        const where = {
            isActive: true,
            ...(type && { type: String(type) })
        };
        const rooms = await prisma_1.default.room.findMany({
            where,
            include: {
                owner: {
                    select: {
                        id: true,
                        name: true,
                        avatarUrl: true,
                        level: true,
                        vipLevel: true
                    }
                },
                members: {
                    take: 3,
                    include: {
                        user: {
                            select: {
                                id: true,
                                name: true,
                                avatarUrl: true,
                                avatarFrameUrl: true,
                            }
                        }
                    }
                },
                _count: {
                    select: {
                        members: true
                    }
                }
            },
            skip,
            take: Number(limit),
            orderBy: {
                createdAt: 'desc'
            }
        });
        const total = await prisma_1.default.room.count({ where });
        res.json({
            rooms: rooms.map(room => ({
                id: room.id,
                name: room.name,
                description: room.description,
                coverImageUrl: room.coverImageUrl,
                backgroundImageUrl: room.backgroundImageUrl,
                type: room.type,
                maxSeats: room.maxSeats,
                owner: room.owner,
                membersCount: room._count.members,
                members: room.members.map(m => ({
                    userId: m.userId,
                    role: m.role,
                    isMuted: m.isMuted,
                    joinedAt: m.joinedAt,
                    user: m.user
                })),
                createdAt: room.createdAt
            })),
            pagination: {
                page: Number(page),
                limit: Number(limit),
                total,
                totalPages: Math.ceil(total / Number(limit))
            }
        });
    }
    catch (error) {
        console.error('Get rooms error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getRooms = getRooms;
const getRoomById = async (req, res) => {
    try {
        const roomIdNum = (0, http_1.intParam)(req.params.roomId);
        if (!roomIdNum)
            return res.status(400).json({ error: 'Invalid roomId' });
        const room = await prisma_1.default.room.findUnique({
            where: { id: roomIdNum },
            include: {
                owner: { select: { id: true, name: true, avatarUrl: true, level: true, vipLevel: true } },
                members: {
                    include: { user: { select: { id: true, name: true, avatarUrl: true, avatarFrameUrl: true, level: true, vipLevel: true } } },
                },
                _count: { select: { members: true } },
            },
        });
        if (!room)
            return res.status(404).json({ error: 'Room not found' });
        return res.json({
            id: room.id,
            name: room.name,
            description: room.description,
            coverImageUrl: room.coverImageUrl,
            backgroundImageUrl: room.backgroundImageUrl,
            type: room.type,
            maxSeats: room.maxSeats,
            owner: room.owner,
            membersCount: room._count.members,
            members: room.members.map(m => ({
                userId: m.userId,
                role: m.role,
                isMuted: m.isMuted,
                joinedAt: m.joinedAt,
                user: m.user,
            })),
            createdAt: room.createdAt,
        });
    }
    catch (error) {
        console.error('Get room error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getRoomById = getRoomById;
async function createRoom(req, res) {
    try {
        const userId = req.userId;
        const { name, roomNumber, description, type, coverImage, coverImageUrl, backgroundImageUrl, password, } = req.body;
        const rawMaxSeats = Number(req.body.maxSeats);
        const safeMaxSeats = Math.max(2, Math.min(30, Number.isFinite(rawMaxSeats) ? rawMaxSeats : 8));
        if (!userId) {
            return res.status(401).json({ error: 'Unauthorized' });
        }
        if (!name) {
            return res.status(400).json({ error: 'Room name is required' });
        }
        const room = await prisma_1.default.room.create({
            data: {
                name,
                description: description || null,
                type: type || 'public',
                maxSeats: safeMaxSeats,
                coverImageUrl: coverImage || coverImageUrl || null,
                backgroundImageUrl: backgroundImageUrl || null,
                passwordHash: password || null,
                ownerId: userId,
                isActive: true,
            },
            include: {
                owner: {
                    select: {
                        id: true,
                        name: true,
                        avatarUrl: true,
                        level: true,
                        vipLevel: true,
                    },
                },
            },
        });
        await prisma_1.default.roomMember.create({
            data: {
                userId,
                roomId: room.id,
                role: 'owner',
                isMuted: false,
            },
        });
        return res.status(201).json({
            id: room.id,
            name: room.name,
            description: room.description,
            type: room.type,
            maxSeats: room.maxSeats,
            coverImageUrl: room.coverImageUrl,
            backgroundImageUrl: room.backgroundImageUrl,
            owner: room.owner,
            createdAt: room.createdAt,
        });
    }
    catch (error) {
        console.error('Create room error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
}
;
const updateRoom = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ error: 'Unauthorized' });
        const roomIdNum = (0, http_1.intParam)(req.params.roomId);
        if (!roomIdNum)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { name, description, type, maxSeats, coverImageUrl, backgroundImageUrl } = req.body;
        const room = await prisma_1.default.room.findUnique({ where: { id: roomIdNum } });
        if (!room)
            return res.status(404).json({ error: 'Room not found' });
        if (room.ownerId !== userId)
            return res.status(403).json({ error: 'Only room owner can update the room' });
        const safeMaxSeats = maxSeats != null ? Math.max(2, Math.min(30, Number(maxSeats))) : undefined;
        const updatedRoom = await prisma_1.default.room.update({
            where: { id: roomIdNum },
            data: {
                ...(name && { name }),
                ...(description !== undefined && { description }),
                ...(type && { type }),
                ...(safeMaxSeats != null && Number.isFinite(safeMaxSeats) && { maxSeats: safeMaxSeats }),
                ...(coverImageUrl && { coverImageUrl }),
                ...(backgroundImageUrl && { backgroundImageUrl }),
            },
        });
        return res.json(updatedRoom);
    }
    catch (error) {
        console.error('Update room error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.updateRoom = updateRoom;
const deleteRoom = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ error: 'Unauthorized' });
        const roomIdNum = (0, http_1.intParam)(req.params.roomId);
        if (!roomIdNum)
            return res.status(400).json({ error: 'Invalid roomId' });
        const room = await prisma_1.default.room.findUnique({ where: { id: roomIdNum } });
        if (!room)
            return res.status(404).json({ error: 'Room not found' });
        if (room.ownerId !== userId)
            return res.status(403).json({ error: 'Only room owner can delete the room' });
        await prisma_1.default.room.update({
            where: { id: roomIdNum },
            data: { isActive: false },
        });
        return res.json({ message: 'Room deleted successfully' });
    }
    catch (error) {
        console.error('Delete room error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.deleteRoom = deleteRoom;
const joinRoom = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ error: 'Unauthorized' });
        const roomIdNum = (0, http_1.intParam)(req.params.roomId);
        if (!roomIdNum)
            return res.status(400).json({ error: 'Invalid roomId' });
        const room = await prisma_1.default.room.findUnique({
            where: { id: roomIdNum },
            include: { _count: { select: { members: true } } },
        });
        if (!room)
            return res.status(404).json({ error: 'Room not found' });
        if (!room.isActive)
            return res.status(400).json({ error: 'Room is not active' });
        const existing = await prisma_1.default.roomMember.findUnique({
            where: { userId_roomId: { userId, roomId: roomIdNum } },
        });
        if (existing)
            return res.status(409).json({ error: 'Already a member of this room' });
        const membership = await prisma_1.default.roomMember.create({
            data: { userId, roomId: roomIdNum, role: 'member', isMuted: false },
        });
        return res.status(201).json(membership);
    }
    catch (error) {
        console.error('Join room error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.joinRoom = joinRoom;
const leaveRoom = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ error: 'Unauthorized' });
        const roomIdNum = (0, http_1.intParam)(req.params.roomId);
        if (!roomIdNum)
            return res.status(400).json({ error: 'Invalid roomId' });
        await prisma_1.default.roomMember.delete({
            where: { userId_roomId: { userId, roomId: roomIdNum } },
        });
        return res.json({ message: 'Left room successfully' });
    }
    catch (error) {
        console.error('Leave room error:', error);
        return res.status(500).json({ error: 'Internal server error' });
    }
};
exports.leaveRoom = leaveRoom;
//# sourceMappingURL=room.controller.js.map