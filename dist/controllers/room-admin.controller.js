"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.addRoomAdmin = addRoomAdmin;
exports.removeRoomAdmin = removeRoomAdmin;
exports.muteUser = muteUser;
exports.banUser = banUser;
exports.unbanUser = unbanUser;
exports.getBanList = getBanList;
exports.toggleRoomLock = toggleRoomLock;
exports.updateMaxSeats = updateMaxSeats;
exports.setBackgroundMusic = setBackgroundMusic;
exports.updateRoomBackground = updateRoomBackground;
exports.toggleSoundSettings = toggleSoundSettings;
exports.clearChat = clearChat;
exports.getRoomAdmins = getRoomAdmins;
const prisma_1 = __importDefault(require("../utils/prisma"));
const toInt = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : null;
};
async function isRoomAdminOrOwner(userId, roomId) {
    const room = await prisma_1.default.room.findUnique({
        where: { id: roomId },
        include: { members: { where: { userId } } },
    });
    if (!room)
        return { isAdmin: false, role: null };
    if (room.ownerId === userId)
        return { isAdmin: true, role: 'owner' };
    const member = room.members[0];
    if (member?.role === 'admin')
        return { isAdmin: true, role: 'admin' };
    return { isAdmin: false, role: member?.role || null };
}
async function addRoomAdmin(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const userId = toInt(req.body.userId);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId || !userId)
            return res.status(400).json({ error: 'roomId and userId required' });
        const room = await prisma_1.default.room.findUnique({ where: { id: roomId } });
        if (!room)
            return res.status(404).json({ error: 'Room not found' });
        if (room.ownerId !== requesterId)
            return res.status(403).json({ error: 'Only room owner can add admins' });
        const member = await prisma_1.default.roomMember.upsert({
            where: { userId_roomId: { userId, roomId } },
            update: { role: 'admin' },
            create: { userId, roomId, role: 'admin' },
        });
        return res.json({ success: true, message: 'Admin added', member });
    }
    catch (e) {
        console.error('addRoomAdmin error:', e);
        return res.status(500).json({ error: 'Failed to add admin' });
    }
}
async function removeRoomAdmin(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const userId = toInt(req.body.userId);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId || !userId)
            return res.status(400).json({ error: 'roomId and userId required' });
        const room = await prisma_1.default.room.findUnique({ where: { id: roomId } });
        if (!room)
            return res.status(404).json({ error: 'Room not found' });
        if (room.ownerId !== requesterId)
            return res.status(403).json({ error: 'Only room owner can remove admins' });
        const member = await prisma_1.default.roomMember.update({
            where: { userId_roomId: { userId, roomId } },
            data: { role: 'member' },
        });
        return res.json({ success: true, message: 'Admin removed', member });
    }
    catch (e) {
        console.error('removeRoomAdmin error:', e);
        return res.status(500).json({ error: 'Failed to remove admin' });
    }
}
async function muteUser(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const userId = toInt(req.body.userId);
        const isMuted = !!req.body.isMuted;
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId || !userId)
            return res.status(400).json({ error: 'roomId and userId required' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can mute users' });
        const member = await prisma_1.default.roomMember.update({
            where: { userId_roomId: { userId, roomId } },
            data: { isMuted },
        });
        return res.json({ success: true, message: isMuted ? 'User muted' : 'User unmuted', member });
    }
    catch (e) {
        console.error('muteUser error:', e);
        return res.status(500).json({ error: 'Failed to mute user' });
    }
}
async function banUser(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const userId = toInt(req.body.userId);
        const reason = req.body.reason?.toString();
        const expiresAtRaw = req.body.expiresAt;
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId || !userId)
            return res.status(400).json({ error: 'roomId and userId required' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can ban users' });
        const ban = await prisma_1.default.roomBan.create({
            data: {
                roomId,
                userId,
                bannedBy: requesterId,
                reason: reason || null,
                expiresAt: expiresAtRaw ? new Date(expiresAtRaw) : null,
            },
        });
        await prisma_1.default.roomMember.deleteMany({ where: { roomId, userId } });
        return res.json({ success: true, message: 'User banned', ban });
    }
    catch (e) {
        console.error('banUser error:', e);
        return res.status(500).json({ error: 'Failed to ban user' });
    }
}
async function unbanUser(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const userId = toInt(req.body.userId);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId || !userId)
            return res.status(400).json({ error: 'roomId and userId required' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can unban users' });
        await prisma_1.default.roomBan.delete({ where: { roomId_userId: { roomId, userId } } });
        return res.json({ success: true, message: 'User unbanned' });
    }
    catch (e) {
        console.error('unbanUser error:', e);
        return res.status(500).json({ error: 'Failed to unban user' });
    }
}
async function getBanList(req, res) {
    try {
        const roomId = toInt(req.params.roomId);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can view ban list' });
        const bans = await prisma_1.default.roomBan.findMany({
            where: { roomId },
            include: {
                user: { select: { id: true, name: true, avatarUrl: true } },
                banner: { select: { id: true, name: true } },
            },
            orderBy: { bannedAt: 'desc' },
        });
        return res.json({ bans });
    }
    catch (e) {
        console.error('getBanList error:', e);
        return res.status(500).json({ error: 'Failed to fetch ban list' });
    }
}
async function toggleRoomLock(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const isLocked = !!req.body.isLocked;
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can lock/unlock room' });
        const room = await prisma_1.default.room.update({ where: { id: roomId }, data: { isLocked } });
        return res.json({ success: true, message: isLocked ? 'Room locked' : 'Room unlocked', room });
    }
    catch (e) {
        console.error('toggleRoomLock error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
async function updateMaxSeats(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const maxSeats = toInt(req.body.maxSeats);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId || !maxSeats)
            return res.status(400).json({ error: 'roomId and maxSeats required' });
        if (maxSeats < 2 || maxSeats > 20)
            return res.status(400).json({ error: 'Max seats must be 2..20' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can change seat count' });
        const room = await prisma_1.default.room.update({ where: { id: roomId }, data: { maxSeats } });
        return res.json({ success: true, message: 'Max seats updated', room });
    }
    catch (e) {
        console.error('updateMaxSeats error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
async function setBackgroundMusic(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const musicUrl = req.body.musicUrl?.toString() || null;
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can set background music' });
        const room = await prisma_1.default.room.update({ where: { id: roomId }, data: { backgroundMusicUrl: musicUrl } });
        return res.json({ success: true, message: 'Background music updated', room });
    }
    catch (e) {
        console.error('setBackgroundMusic error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
async function updateRoomBackground(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const backgroundImageUrl = req.body.backgroundImageUrl?.toString() || null;
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can change room background' });
        const room = await prisma_1.default.room.update({ where: { id: roomId }, data: { backgroundImageUrl } });
        return res.json({ success: true, message: 'Room background updated', room });
    }
    catch (e) {
        console.error('updateRoomBackground error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
async function toggleSoundSettings(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can change sound settings' });
        const updateData = {};
        if (req.body.muteGiftSounds !== undefined)
            updateData.muteGiftSounds = !!req.body.muteGiftSounds;
        if (req.body.muteEntranceSounds !== undefined)
            updateData.muteEntranceSounds = !!req.body.muteEntranceSounds;
        const room = await prisma_1.default.room.update({ where: { id: roomId }, data: updateData });
        return res.json({ success: true, message: 'Sound settings updated', room });
    }
    catch (e) {
        console.error('toggleSoundSettings error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
async function clearChat(req, res) {
    try {
        const roomId = toInt(req.body.roomId);
        const requesterId = req.userId;
        if (!requesterId)
            return res.status(401).json({ error: 'Unauthorized' });
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
        if (!isAdmin)
            return res.status(403).json({ error: 'Only admins can clear chat' });
        await prisma_1.default.roomMessage.deleteMany({ where: { roomId } });
        return res.json({ success: true, message: 'Chat cleared' });
    }
    catch (e) {
        console.error('clearChat error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
async function getRoomAdmins(req, res) {
    try {
        const roomId = toInt(req.params.roomId);
        if (!roomId)
            return res.status(400).json({ error: 'Invalid roomId' });
        const admins = await prisma_1.default.roomMember.findMany({
            where: { roomId, role: { in: ['owner', 'admin'] } },
            include: { user: { select: { id: true, name: true, avatarUrl: true, level: true } } },
        });
        return res.json({ admins });
    }
    catch (e) {
        console.error('getRoomAdmins error:', e);
        return res.status(500).json({ error: 'Failed' });
    }
}
//# sourceMappingURL=room-admin.controller.js.map