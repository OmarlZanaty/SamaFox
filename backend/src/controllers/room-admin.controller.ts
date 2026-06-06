// File: src/controllers/room-admin.controller.ts

import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { io } from '../index';

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

    // Admin mute is a FORCE mute: the user cannot unmute themselves until an
    // admin unmutes them (which also clears the force flag).
    const member = await prisma.roomMember.update({
      where: { userId_roomId: { userId, roomId } },
      data: { isMuted, forceMuted: isMuted },
    });

    // Live update so the target's mic flips immediately.
    io.to(`room:${roomId}`).emit('seat_mute_changed', {
      roomId, userId, isMuted, forced: isMuted,
    });
    io.to(`user:${userId}`).emit('force_mute', { roomId, isMuted });

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
    // Accept both `isLocked` and legacy `locked`; default to locking.
    const isLocked = req.body.isLocked !== undefined ? !!req.body.isLocked : !!req.body.locked;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can lock/unlock room' });

    let accessCode: string | null = null;
    if (isLocked) {
      // A 5-digit numeric PIN is required when locking.
      const raw = (req.body.accessCode ?? req.body.code ?? '').toString().trim();
      if (!/^\d{5}$/.test(raw)) {
        return res.status(400).json({ error: 'accessCode must be exactly 5 digits' });
      }
      accessCode = raw;
    }

    const room = await prisma.room.update({
      where: { id: roomId },
      // Lock → store PIN; unlock → clear PIN so the room is open again.
      data: { isLocked, accessCode },
    });

    return res.json({
      success: true,
      message: isLocked ? 'Room locked' : 'Room unlocked',
      isLocked: room.isLocked,
      accessCode: room.accessCode, // returned so the admin can see/share the PIN
      room,
    });
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

// Block/unblock a user from taking any seat in the room. When blocking we also
// remove them from their current seat live.
export async function setSeatBlock(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const blocked = !!req.body.blocked;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can block seats' });

    await prisma.roomMember.upsert({
      where: { userId_roomId: { userId, roomId } },
      update: { seatBlocked: blocked },
      create: { userId, roomId, seatBlocked: blocked, role: 'member' },
    });

    // Tell the room (and the target) so the client kicks them off the mic now.
    io.to(`room:${roomId}`).emit('seat_block_changed', { roomId, userId, blocked });
    if (blocked) io.to(`user:${userId}`).emit('removed_from_seat', { roomId });

    return res.json({
      success: true,
      message: blocked ? 'User blocked from seats' : 'Seat block cleared',
    });
  } catch (e) {
    console.error('setSeatBlock error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}

// Kick a user from the room for a duration (minutes). 0/absent => permanent.
// Creates a RoomBan (enforced on join_room) and removes them live.
export async function kickUser(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const userId = toInt(req.body.userId);
    const minutes = toInt(req.body.minutes) ?? 0;
    const reason = req.body.reason?.toString() || null;
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId || !userId) return res.status(400).json({ error: 'roomId and userId required' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can kick users' });

    // Never let a kick target the room owner.
    const room = await prisma.room.findUnique({ where: { id: roomId }, select: { ownerId: true } });
    if (room?.ownerId === userId) return res.status(403).json({ error: 'Cannot kick the room owner' });

    const expiresAt = minutes > 0 ? new Date(Date.now() + minutes * 60_000) : null;

    await prisma.roomBan.upsert({
      where: { roomId_userId: { roomId, userId } },
      update: { bannedBy: requesterId, reason, expiresAt },
      create: { roomId, userId, bannedBy: requesterId, reason, expiresAt },
    });
    await prisma.roomMember.deleteMany({ where: { roomId, userId } });

    // Live removal: tell the target to leave the room now.
    io.to(`user:${userId}`).emit('kicked_from_room', {
      roomId,
      until: expiresAt,
      message: reason || 'تم طردك من الغرفة',
    });

    return res.json({
      success: true,
      message: expiresAt ? `User kicked until ${expiresAt.toISOString()}` : 'User kicked',
      expiresAt,
    });
  } catch (e) {
    console.error('kickUser error:', e);
    return res.status(500).json({ error: 'Failed' });
  }
}
