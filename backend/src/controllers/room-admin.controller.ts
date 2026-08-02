// File: src/controllers/room-admin.controller.ts

import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { io } from '../index';
import { invalidateAdminCacheAndRefresh } from '../services/socket.service';

const toInt = (v: any): number | null => {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
};

/** Platform-wide super admin (group 11): outranks room owners in every room. */
async function isPlatformSuperAdmin(userId: number): Promise<boolean> {
  const u = await (prisma as any).user.findUnique({
    where: { id: userId },
    select: { isSuperAdmin: true },
  });
  return Boolean(u?.isSuperAdmin);
}

/**
 * Platform staff tier for a user, independent of any room membership:
 *   'super'    — super admin: moderates anyone and controls room settings
 *   'platform' — admin: moderates anyone and is immune to moderation, but
 *                deliberately gets NO room-settings powers
 *   null       — ordinary user, ranked by their room role alone
 */
async function getPlatformTier(userId: number): Promise<'super' | 'platform' | null> {
  const u = await (prisma as any).user.findUnique({
    where: { id: userId },
    select: { isSuperAdmin: true, isAdmin: true },
  });
  if (u?.isSuperAdmin) return 'super';
  if (u?.isAdmin) return 'platform';
  return null;
}

async function isRoomAdminOrOwner(userId: number, roomId: number): Promise<{ isAdmin: boolean; role: string | null }> {
  // Group 11: platform super admins hold admin powers in every room.
  if (await isPlatformSuperAdmin(userId)) return { isAdmin: true, role: 'super' };

  const room = await prisma.room.findUnique({
    where: { id: roomId },
    include: { members: { where: { userId } } },
  });

  if (!room) return { isAdmin: false, role: null };
  if (room.ownerId === userId) return { isAdmin: true, role: 'owner' };

  const member = room.members[0];
  // Supervisors have admin-level powers (gated separately from real admins).
  if (member?.role === 'admin' || member?.role === 'supervisor') {
    return { isAdmin: true, role: member.role };
  }

  return { isAdmin: false, role: member?.role || null };
}

// Platform staff sit above every room role, so a room owner can never kick,
// mute or pull an admin off the mic — the immunity the owner asked for. Note
// this ranking governs MODERATION only; room settings stay gated by
// isRoomAdminOrOwner, which platform admins deliberately do not satisfy.
const ROLE_RANK: Record<string, number> = {
  super: 5,
  platform: 4,
  owner: 3,
  admin: 2,
  supervisor: 1,
  member: 0,
};

/** Effective role: super | platform | owner | admin | supervisor | member. */
async function getRoomRole(userId: number, roomId: number): Promise<string> {
  // Group 11: super admins outrank the owner (owner can't mute/kick them,
  // they can moderate anyone including the owner). Platform admins rank just
  // below them: same immunity and moderation reach, no settings control.
  const tier = await getPlatformTier(userId);
  if (tier) return tier;

  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { ownerId: true, members: { where: { userId }, select: { role: true } } },
  });
  if (!room) return 'member';
  if (room.ownerId === userId) return 'owner';
  const r = room.members[0]?.role;
  return r === 'admin' || r === 'supervisor' ? r : 'member';
}

/**
 * Moderation guard. Confirms the requester may act on the target:
 * - requester must be admin-level (owner/admin/supervisor)
 * - you can only act on someone strictly lower in rank
 *   (so supervisors act on members only; admins act on supervisors+members;
 *    nobody can act on the owner).
 */
async function assertCanModerate(
  requesterId: number,
  targetId: number,
  roomId: number,
): Promise<{ ok: true } | { ok: false; status: number; error: string }> {
  const [requesterRole, targetRole] = await Promise.all([
    getRoomRole(requesterId, roomId),
    getRoomRole(targetId, roomId),
  ]);
  if ((ROLE_RANK[requesterRole] ?? 0) < 1) {
    // requester is not at least a supervisor
    return { ok: false, status: 403, error: 'Not allowed' };
  }
  if ((ROLE_RANK[targetRole] ?? 0) >= (ROLE_RANK[requesterRole] ?? 0)) {
    return { ok: false, status: 403, error: 'لا يمكنك تنفيذ هذا الإجراء على هذا المستخدم' };
  }
  return { ok: true };
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

    const role = req.body.role === 'supervisor' ? 'supervisor' : 'admin';
    const requesterRole = await getRoomRole(requesterId, roomId);

    // Only the owner may appoint full admins; owner OR admins may appoint supervisors.
    if (role === 'admin' && requesterRole !== 'owner') {
      return res.status(403).json({ error: 'Only room owner can add admins' });
    }
    if (role === 'supervisor' && requesterRole !== 'owner' && requesterRole !== 'admin') {
      return res.status(403).json({ error: 'Only owner or admins can add supervisors' });
    }

    const member = await prisma.roomMember.upsert({
      where: { userId_roomId: { userId, roomId } },
      update: { role },
      create: { userId, roomId, role },
    });

    invalidateAdminCacheAndRefresh(roomId);
    return res.json({ success: true, message: `${role} added`, member, role });
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

    invalidateAdminCacheAndRefresh(roomId);
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

    const guard = await assertCanModerate(requesterId, userId, roomId);
    if (!guard.ok) return res.status(guard.status).json({ error: guard.error });

    // Admin mute is a FORCE mute: the user cannot unmute themselves until an
    // admin unmutes them (which also clears the force flag).
    const member = await prisma.roomMember.upsert({
      where: { userId_roomId: { userId, roomId } },
      update: { isMuted, forceMuted: isMuted },
      create: { userId, roomId, isMuted, forceMuted: isMuted, role: 'member' },
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

    const guard = await assertCanModerate(requesterId, userId, roomId);
    if (!guard.ok) return res.status(guard.status).json({ error: guard.error });

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

// Combined moderation list: everyone in the room with an active sanction
// (force-muted, seat-blocked, or banned). Admin can lift any of them.
export async function getModeratedUsers(req: Request, res: Response) {
  try {
    const roomId = toInt(req.params.roomId);
    const requesterId = (req as any).userId as number | undefined;

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can view this list' });

    const [members, bans] = await Promise.all([
      prisma.roomMember.findMany({
        where: { roomId, OR: [{ forceMuted: true }, { seatBlocked: true }] },
        include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
      }),
      prisma.roomBan.findMany({
        where: { roomId },
        include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
      }),
    ]);

    const map = new Map<number, any>();
    const ensure = (u: any) => {
      if (!map.has(u.id)) {
        map.set(u.id, {
          userId: u.id, name: u.name, avatarUrl: u.avatarUrl, displayId: u.displayId,
          forceMuted: false, seatBlocked: false, banned: false, banExpiresAt: null,
        });
      }
      return map.get(u.id);
    };

    for (const m of members) {
      const row = ensure(m.user);
      row.forceMuted = !!m.forceMuted;
      row.seatBlocked = !!m.seatBlocked;
    }
    const now = Date.now();
    for (const b of bans) {
      // Skip expired temporary bans.
      if (b.expiresAt && new Date(b.expiresAt).getTime() <= now) continue;
      const row = ensure(b.user);
      row.banned = true;
      row.banExpiresAt = b.expiresAt;
    }

    return res.json({ success: true, data: Array.from(map.values()) });
  } catch (e) {
    console.error('getModeratedUsers error:', e);
    return res.status(500).json({ error: 'Failed to fetch moderated users' });
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

// #4: admin resets the per-user coin counters shown under each seat in this room.
export async function resetSeatEarnings(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const requesterId = (req as any).userId as number | undefined;
    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'Invalid roomId' });

    const { isAdmin } = await isRoomAdminOrOwner(requesterId, roomId);
    if (!isAdmin) return res.status(403).json({ error: 'Only admins can reset counters' });

    await prisma.room.update({ where: { id: roomId }, data: { contributionResetAt: new Date() } });
    return res.json({ success: true, message: 'Counters reset' });
  } catch (e) {
    console.error('resetSeatEarnings error:', e);
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

    // A background uploaded from the device is rented, not bought: the owner
    // set 1,000 coins for 20 days. Both are AppSettings so the price and the
    // term can be retuned from the dashboard without a deploy.
    const chargeUpload = req.body.chargeUpload === true || req.body.chargeUpload === 'true';
    let backgroundExpiresAt: Date | null = null;
    if (chargeUpload) {
      const [priceRow, daysRow] = await Promise.all([
        (prisma as any).appSetting.findUnique({ where: { key: 'room_background_price_coins' } }),
        (prisma as any).appSetting.findUnique({ where: { key: 'room_background_days' } }),
      ]);
      const cost = Math.max(0, Math.floor(Number(priceRow?.value ?? 1000)) || 1000);
      const days = Math.max(1, Math.floor(Number(daysRow?.value ?? 20)) || 20);

      const u = await prisma.user.findUnique({ where: { id: requesterId }, select: { coinsBalance: true } });
      if (!u || u.coinsBalance < cost) {
        return res.status(400).json({
          error: 'INSUFFICIENT_COINS',
          message: `رصيد الكوينز غير كافٍ (تكلفة الخلفية ${cost.toLocaleString('en-US')})`,
        });
      }
      await prisma.user.update({ where: { id: requesterId }, data: { coinsBalance: { decrement: cost } } });
      await prisma.transaction.create({
        data: { userId: requesterId, type: 'ROOM_BACKGROUND', amountCoins: -cost, status: 'completed' },
      });
      backgroundExpiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
    }

    const room = await prisma.room.update({
      where: { id: roomId },
      // Clearing or setting a free background also clears any running term.
      data: { backgroundImageUrl, backgroundExpiresAt } as any,
    });

    // Live update for everyone currently in the room.
    io.to(`room:${roomId}`).emit('room_background_changed', { roomId, backgroundImageUrl });

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

    // Tell every client in the room to clear their chat immediately.
    io.to(`room:${roomId}`).emit('chat_cleared', { roomId });

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

    const guard = await assertCanModerate(requesterId, userId, roomId);
    if (!guard.ok) return res.status(guard.status).json({ error: guard.error });

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

/**
 * Close a room from inside the app. Super admins only — platform admins get
 * moderation powers but deliberately no control over the room itself.
 *
 * Closing is the same operation the dashboard performs: isActive:false, which
 * `join_room` rejects with `join_denied` ('closed'), plus a broadcast that
 * empties the room immediately. So everyone inside leaves and nobody can get
 * back in, which is what the owner asked for.
 */
export async function closeRoomAsSuperAdmin(req: Request, res: Response) {
  try {
    const roomId = toInt(req.body.roomId);
    const requesterId = (req as any).userId as number | undefined;
    const reason = req.body.reason?.toString()?.trim() || 'تم إغلاق الغرفة من الإدارة';

    if (!requesterId) return res.status(401).json({ error: 'Unauthorized' });
    if (!roomId) return res.status(400).json({ error: 'roomId required' });

    if (!(await isPlatformSuperAdmin(requesterId))) {
      return res.status(403).json({ error: 'سوبر أدمن فقط يمكنه إغلاق الغرفة' });
    }

    const room = await prisma.room.findUnique({ where: { id: roomId }, select: { id: true } });
    if (!room) return res.status(404).json({ error: 'Room not found' });

    await prisma.room.update({ where: { id: roomId }, data: { isActive: false } });
    io.to(`room:${roomId}`).emit('room_force_closed', { roomId, reason });

    return res.json({ success: true, message: 'Room closed' });
  } catch (e) {
    console.error('closeRoomAsSuperAdmin error:', e);
    return res.status(500).json({ error: 'Failed to close room' });
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

    const guard = await assertCanModerate(requesterId, userId, roomId);
    if (!guard.ok) return res.status(guard.status).json({ error: guard.error });

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
