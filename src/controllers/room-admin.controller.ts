// File: src/controllers/room-admin.controller.ts

import { Request, Response } from 'express';
import prisma from '../utils/prisma';

const toInt = (v: any): number | null => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
};

async function isRoomAdminOrOwner(userId: number, roomId: number): Promise<{ isAdmin: boolean; role: string | null }> {
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    include: { members: { where: { userId } } },
  });

  if (!room) return { isAdmin: false, role: null };
  if (room.ownerId === userId) return { isAdmin: true, role: 'owner' };

  const member = room.members[0];
  if (member?.role === 'admin') return { isAdmin: true, role: 'admin' };

  return { isAdmin: false, role: member?.role || null };
}

export async function addRoomAdmin(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const room = await prisma.room.findUnique({ where: { id: roomId } });
    if (!room) return res.status(404).json({ error: 'Room not found' });
    if (room.ownerId !== requesterId) return res.status(403).json({ error: 'Only room owner can add admins' });

    const member = await prisma.roomMember.upsert({
      where: { userId_roomId: { userId, roomId } },
      update: { role: 'admin' },
      create: { userId, roomId, role: 'admin' },
    });

    return res.json({ success: true, message: 'Admin added', member });
  } catch (e) {
    console.error('addRoomAdmin error:', e);
    return res.status(500).json({ error: 'Failed to add admin' });
  }
}

export async function removeRoomAdmin(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const room = await prisma.room.findUnique({ where: { id: roomId } });
    if (!room) return res.status(404).json({ error: 'Room not found' });
    if (room.ownerId !== requesterId) return res.status(403).json({ error: 'Only room owner can remove admins' });

    const member = await prisma.roomMember.update({
      where: { userId_roomId: { userId, roomId } },
      data: { role: 'member' },
    });

    return res.json({ success: true, message: 'Admin removed', member });
  } catch (e) {
    console.error('removeRoomAdmin error:', e);
    return res.status(500).json({ error: 'Failed to remove admin' });
  }
}

export async function muteUser(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const isMuted = !!req.body.isMuted;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can mute users' });

    const member = await prisma.roomMember.update({
      where: { userId_roomId: { userId, roomId } },
      data: { isMuted },
    });

    return res.json({ success: true, message: isMuted ? 'User muted' : 'User unmuted', member });
  } catch (e) {
    console.error('muteUser error:', e);
    return res.status(500).json({ error: 'Failed to mute user' });
  }
}

export async function banUser(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const reason = req.body.reason?.toString();
    const expiresAtRaw = req.body.expiresAt;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can ban users' });

    const ban = await prisma.roomBan.create({
      data: {
        roomId,
        userId,
        bannedBy: requesterId,
        reason: reason || null,
        expiresAt: expiresAtRaw ? new Date(expiresAtRaw) : null,
      },
    });

    await prisma.roomMember.deleteMany({ where: { roomId, userId } });

    return res.json({ success: true, message: 'User banned', ban });
  } catch (e) {
    console.error('banUser error:', e);
    return res.status(500).json({ error: 'Failed to ban user' });
  }
}

export async function unbanUser(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can unban users' });

    await prisma.roomBan.delete({ where: { roomId_userId: { roomId, userId } } });

    return res.json({ success: true, message: 'User unbanned' });
  } catch (e) {
    console.error('unbanUser error:', e);
    return res.status(500).json({ error: 'Failed to unban user' });
  }
}

export async function getBanList(req: Request, res: Response) {
  try {
    const roomId = toInt(req.params.roomId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can view ban list' });

    const bans = await prisma.roomBan.findMany({
      where: { roomId },
      include: {
        user: { select: { id: true, name: true, avatarUrl: true } },
        banner: { select: { id: true, name: true } },
      },
      orderBy: { bannedAt: 'desc' },
    });

    return res.json({ bans });
  } catch (e) {
    console.error('getBanList error:', e);
    return res.status(500).json({ error: 'Failed to fetch ban list' });
  }
}

export async function toggleRoomLock(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const isLocked = !!req.body.isLocked;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can lock/unlock room' });

    const room = await prisma.room.update({ where: { id: roomId }, data: { isLocked } });

    return res.json({ success: true, message: isLocked ? 'Room locked' : 'Room unlocked', room });
  } catch (e) {
    console.error('toggleRoomLock error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

export async function updateMaxSeats(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const maxSeats = toInt(req.body.maxSeats);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !maxSeats) return res.status(400).json({ error: 'roomId and maxSeats required' });
    if (maxSeats < 2 || maxSeats > 20) return res.status(400).json({ error: 'Max seats must be 2..20' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can change seat count' });

    const room = await prisma.room.update({ where: { id: roomId }, data: { maxSeats } });

    return res.json({ success: true, message: 'Max seats updated', room });
  } catch (e) {
    console.error('updateMaxSeats error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

export async function setBackgroundMusic(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const musicUrl = req.body.musicUrl?.toString() || null;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can set background music' });

    const room = await prisma.room.update({ where: { id: roomId }, data: { backgroundMusicUrl: musicUrl } });

    return res.json({ success: true, message: 'Background music updated', room });
  } catch (e) {
    console.error('setBackgroundMusic error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

export async function updateRoomBackground(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const backgroundImageUrl = req.body.backgroundImageUrl?.toString() || null;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can change room background' });

    const room = await prisma.room.update({ where: { id: roomId }, data: { backgroundImageUrl } });

    return res.json({ success: true, message: 'Room background updated', room });
  } catch (e) {
    console.error('updateRoomBackground error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

export async function toggleSoundSettings(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can change sound settings' });

    const updateData: any = {};
    if (req.body.muteGiftSounds !== undefined) updateData.muteGiftSounds = !!req.body.muteGiftSounds;
    if (req.body.muteEntranceSounds !== undefined) updateData.muteEntranceSounds = !!req.body.muteEntranceSounds;

    const room = await prisma.room.update({ where: { id: roomId }, data: updateData });

    return res.json({ success: true, message: 'Sound settings updated', room });
  } catch (e) {
    console.error('toggleSoundSettings error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

export async function clearChat(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can clear chat' });

    await prisma.roomMessage.deleteMany({ where: { roomId } });

    return res.json({ success: true, message: 'Chat cleared' });
  } catch (e) {
    console.error('clearChat error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

export async function getRoomAdmins(req: Request, res: Response) {
  try {
    const roomId = toInt(req.params.roomId);
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const admins = await prisma.roomMember.findMany({
      where: { roomId, role: { in: ['owner', 'admin'] } },
      include: { user: { select: { id: true, name: true, avatarUrl: true, level: true } } },
    });

    return res.json({ admins });
  } catch (e) {
    console.error('getRoomAdmins error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}
