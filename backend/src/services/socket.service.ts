import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from '../utils/jwt';
import prisma from '../utils/prisma';
import { getBanState } from '../utils/banGuard';
import { startBroadcast, endBroadcast } from './broadcast.service';
import { isBlockedBetween } from '../utils/blockGuard';
import { createNotification } from './notification.service';
import { DICE_TABLE_ROOM, getCurrentRoundPublic } from './skillDice.service';
import { WHEEL_TABLE_ROOM, getCurrentWheelRoundPublic } from './skillWheel.service';
import { CRAZY_ROOM, getPublicState as getCrazyWheelState } from './crazyWheel.service';
import { CRASH_ROOM, getCrashStatePublic, getCrashChat } from './crash.service';
import {
  BOXING_RING_ROOM,
  getCurrentRoundPublic as getCurrentBoxingRoundPublic,
} from './boxing.service';
// Gift sending is handled via the REST endpoint POST /api/v1/gifts/send
// which emits 'gift_sent' / 'gift_legendary_incoming' / 'gift_broadcast'
// socket events directly. The legacy 'send_gift' socket handler was
// removed when the gift system was unified.


interface AuthenticatedSocket extends Socket {
  userId?: number;
}

const roomSeats = new Map<number, Map<number, number>>();
const roomMuted = new Map<number, Map<number, boolean>>();
const roomMicQueue = new Map<number, number[]>();
const roomAdmins = new Map<number, Set<number>>();
const MEGA_GIFT_THRESHOLD = Number(process.env.MEGA_GIFT_THRESHOLD ?? 5000);
// Group 12: debounce entrance announcements per room+user (reconnects shouldn't spam).
// Only a dropped connection is debounced — an explicit leave_room clears the key
// below, so leaving and walking back in always replays the entrance.
const recentRoomEntries = new Map<string, number>();
const ENTRANCE_DEBOUNCE_MS = 15_000;

/**
 * Pending mic invitations, keyed by inviteId. An admin inviting a user no longer
 * seats them outright — the invitee gets a قبول / رفض prompt and is only seated
 * if they accept before the invite expires.
 */
interface PendingSeatInvite {
  roomId: number;
  seatNumber: number;
  targetUserId: number;
  fromUserId: number;
  fromUsername: string;
  expiresAt: number;
}
const pendingSeatInvites = new Map<string, PendingSeatInvite>();
const SEAT_INVITE_TTL_MS = 60_000;

function purgeExpiredSeatInvites() {
  const now = Date.now();
  for (const [id, inv] of pendingSeatInvites.entries()) {
    if (inv.expiresAt <= now) pendingSeatInvites.delete(id);
  }
}

function toInt(v: any): number | null {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}


const roomLockedSeats = new Map<number, Set<number>>();

function getLockedSeats(roomId: number): Set<number> {
  if (!roomLockedSeats.has(roomId)) roomLockedSeats.set(roomId, new Set<number>());
  return roomLockedSeats.get(roomId)!;
}

const roomAdminMutedSeats = new Map<number, Set<number>>();

function getAdminMutedSeats(roomId: number): Set<number> {
  if (!roomAdminMutedSeats.has(roomId)) roomAdminMutedSeats.set(roomId, new Set<number>());
  return roomAdminMutedSeats.get(roomId)!;
}

// ✅ Track voice participants per room (GLOBAL ONLY)
const voiceUsers = new Map<number, Set<number>>();
const getVoiceSet = (roomId: number) => {
  if (!voiceUsers.has(roomId)) voiceUsers.set(roomId, new Set<number>());
  return voiceUsers.get(roomId)!;
};

// #25/#31: which room a user is ACTUALLY connected to right now (as host or
// guest) — distinct from Room.ownerId, which only tells you rooms they own.
// The "live" badge on follow lists / other-user profiles must jump here, not
// to a room they own but aren't currently in.
const userCurrentRoom = new Map<number, number>();
export function getUserCurrentRoomId(userId: number): number | null {
  return userCurrentRoom.get(userId) ?? null;
}
export function getUserCurrentRoomIds(userIds: number[]): Map<number, number> {
  const out = new Map<number, number>();
  for (const id of userIds) {
    const rid = userCurrentRoom.get(id);
    if (rid) out.set(id, rid);
  }
  return out;
}

/**
 * Tell a just-banned user and drop their live connections.
 *
 * The ban controllers used to `io.emit('user_banned', …)` — a broadcast to
 * every connected client, which told the whole app who had been banned and
 * why, and which no client listened to anyway. This targets the banned user's
 * own room and then disconnects them so they can't keep using the socket they
 * already hold.
 */
export async function kickBannedUser(
  userId: number,
  reason: string | null,
  banExpiresAt: Date | null,
): Promise<void> {
  if (!_io || !userId) return;
  try {
    _io.to(`user:${userId}`).emit('user_banned', { userId, reason, banExpiresAt });
    const sockets = await _io.in(`user:${userId}`).fetchSockets();
    for (const s of sockets) s.disconnect(true);
  } catch (e) {
    console.warn('[kickBannedUser] failed:', e);
  }
}

// ── Online presence: userId -> set of live socket ids. A user is "online"
// while they have >=1 connected socket. Returns true when the online state
// actually flipped, so callers only broadcast on real transitions. ──
const onlineSockets = new Map<number, Set<string>>();
function markOnline(uid: number, sid: string): boolean {
  let set = onlineSockets.get(uid);
  if (!set) { set = new Set(); onlineSockets.set(uid, set); }
  const wasOffline = set.size === 0;
  set.add(sid);
  return wasOffline;
}
function markOffline(uid: number, sid: string): boolean {
  const set = onlineSockets.get(uid);
  if (!set) return false;
  set.delete(sid);
  if (set.size === 0) { onlineSockets.delete(uid); return true; }
  return false;
}
function getOnlineUserIds(): number[] {
  return Array.from(onlineSockets.keys());
}
function isUserOnline(uid: number): boolean {
  return onlineSockets.has(uid);
}

function getSeats(roomId: number): Map<number, number> {
  if (!roomSeats.has(roomId)) roomSeats.set(roomId, new Map());
  return roomSeats.get(roomId)!;
}

function getMuted(roomId: number): Map<number, boolean> {
  if (!roomMuted.has(roomId)) roomMuted.set(roomId, new Map());
  return roomMuted.get(roomId)!;
}

function getQueue(roomId: number): number[] {
  if (!roomMicQueue.has(roomId)) roomMicQueue.set(roomId, []);
  return roomMicQueue.get(roomId)!;
}

function getAdmins(roomId: number): Set<number> {
  if (!roomAdmins.has(roomId)) roomAdmins.set(roomId, new Set());
  return roomAdmins.get(roomId)!;
}

function cleanupRoomStateIfEmpty(roomId: number) {
  const seats = roomSeats.get(roomId);
  const queue = roomMicQueue.get(roomId);
  const voice = voiceUsers.get(roomId);
  const hasSeats = (seats?.size ?? 0) > 0;
  const hasQueue = (queue?.length ?? 0) > 0;
  const hasVoice = (voice?.size ?? 0) > 0;
  if (hasSeats || hasQueue || hasVoice) return;

  roomSeats.delete(roomId);
  roomMuted.delete(roomId);
  roomMicQueue.delete(roomId);
  roomAdmins.delete(roomId);
  roomLockedSeats.delete(roomId);
  roomAdminMutedSeats.delete(roomId);
  voiceUsers.delete(roomId);
  adminCacheTTL.delete(roomId);
}

const adminCacheTTL = new Map<number, number>(); // rid -> timestamp
const ADMIN_CACHE_DURATION_MS = 0; // always fresh

async function populateAdmins(roomId: number) {
  const now = Date.now();
  const lastPopulated = adminCacheTTL.get(roomId) ?? 0;
  if (now - lastPopulated < ADMIN_CACHE_DURATION_MS && getAdmins(roomId).size > 0) return;
  
  const admins = new Set<number>();

  // ✅ include real room owner always
  const room = await prisma.room.findUnique({
    where: { id: roomId },
    select: { ownerId: true },
  });
  if (room?.ownerId) admins.add(room.ownerId);

  // include admins from roomMember table
  const members = await prisma.roomMember.findMany({
    where: { roomId },
    select: { userId: true, role: true },
  });
  for (const m of members) {
    // Supervisors get admin-level powers in the room (server still blocks them
    // from acting on real admins/owner).
    if (m.role === 'owner' || m.role === 'admin' || m.role === 'supervisor') {
      admins.add(m.userId);
    }
  }

  // Group 11: platform super admins have admin powers in EVERY room
  // (HTTP moderation endpoints still rank them above the owner).
  try {
    const supers = await (prisma as any).user.findMany({
      where: { isSuperAdmin: true },
      select: { id: true },
    });
    for (const s of supers) admins.add(s.id);
  } catch (e) {
    console.warn('populateAdmins super-admin lookup failed:', e);
  }

  roomAdmins.set(roomId, admins);
}

async function emitRoomState(io: Server, rid: number) {
  // make sure admins are populated
  let adminsSet = getAdmins(rid);
  if (adminsSet.size === 0) {
    await populateAdmins(rid);
    adminsSet = getAdmins(rid);
  }
const locked = getLockedSeats(rid);

  const seatsMap = getSeats(rid);
  const mutedMap = getMuted(rid);

    // Build FULL seat list (1..maxSeats), not only occupied seats
  const room = await prisma.room.findUnique({
    where: { id: rid },
    select: { ownerId: true, maxSeats: true },
  });

  const maxSeats = room?.maxSeats ?? 8;

  // fetch all users who are seated (to avoid N queries)
  const seatedUserIds = Array.from(new Set(Array.from(seatsMap.values())));
  const seatedUsers = seatedUserIds.length
    ? await prisma.user.findMany({
        where: { id: { in: seatedUserIds } },
        select: {
  id: true,
  name: true,
  avatarUrl: true,        // 🔥 ADD THIS
  displayId: true,
  vipLevel: true,
  relationId: true,
  avatarFrameUrl: true,
  activeFrameId: true,
  activeFrame: { select: { assetUrl: true } },
  level: true,
}
      })
    : [];

  const usersById = new Map(seatedUsers.map(u => [u.id, u]));
  const relationIds = Array.from(new Set(seatedUsers.map((u: any) => u.relationId).filter((id: any) => !!id)));
  const relations = relationIds.length
    ? await prisma.relation.findMany({
      where: { id: { in: relationIds } },
      include: {
        user1: { select: { id: true, name: true, avatarUrl: true } },
        user2: { select: { id: true, name: true, avatarUrl: true } },
      },
    })
    : [];
  const relationsById = new Map(relations.map((rel) => [rel.id, rel]));

  const frameMap = new Map<number, string | null>();

await Promise.all(
  seatedUsers.map(async (u) => {
    const frame = u.activeFrame?.assetUrl ?? u.avatarFrameUrl ?? null;
    frameMap.set(u.id, frame);
  })
);

  const seatDetails = Array.from({ length: maxSeats }, (_, i) => {
    const seatNumber = i + 1;
    const occupant = seatsMap.get(seatNumber) ?? null;
    const u = occupant ? usersById.get(occupant) : null;
    const rel = u?.relationId ? relationsById.get(u.relationId) : null;
    const relationPartner = rel
      ? (rel.user1Id === u?.id ? rel.user2 : rel.user1)
      : null;

    return {
      seatNumber,
      userId: occupant,
      username: u?.name ?? null,
      displayId: u?.displayId ?? null,
      vipLevel: u?.vipLevel ?? 0,
      avatarUrl: u?.avatarUrl ?? null,
  avatarFrameUrl: occupant ? frameMap.get(occupant) ?? null : null, // ✅ ADD
      frameImageUrl: occupant ? frameMap.get(occupant) ?? null : null,
      activeFrameId: u?.activeFrameId ?? null,
      relationPartner,
      level: u?.level ?? 1,
      isMuted: occupant ? (mutedMap.get(occupant) ?? true) : true,
      isLocked: locked.has(seatNumber),
    };
  });

  const adminList = Array.from(adminsSet);

  io.to(`room:${rid}`).emit('room_seats_state', {
    roomId: rid,
    ownerId: room?.ownerId ?? 0,
    admins: adminList,
    adminIds: adminList,
    maxSeats,
    lockedSeats: Array.from(locked.values()),
    mutedSeats: Array.from(getAdminMutedSeats(rid).values()),
    seats: seatDetails,
  });

}

async function emitVoiceUsers(io: Server, rid: number) {
  const users = Array.from(getVoiceSet(rid).values());
  io.to(`room:${rid}`).emit('voice_users', { roomId: rid, users });
}

/**
 * Everyone currently connected to a room, derived from socket.io's own room
 * membership. Clients had no way to learn who was already present — they only
 * saw `user_joined` for people arriving after them — so lists like the
 * "دعوة إلى المقعد" picker showed nothing but the viewer themselves.
 */
async function buildRoomUsers(io: Server, rid: number) {
  const sockets = await io.in(`room:${rid}`).fetchSockets();
  const ids = Array.from(
    new Set(
      sockets
        .map((s) => Number((s.data as any)?.userId))
        .filter((n) => Number.isFinite(n) && n > 0),
    ),
  );
  if (ids.length === 0) return [];

  const users = await prisma.user.findMany({
    where: { id: { in: ids } },
    select: { id: true, name: true, avatarUrl: true, displayId: true, level: true, vipLevel: true },
  });
  return users.map((u) => ({
    userId: u.id,
    username: u.name ?? (u.displayId ? `#${u.displayId}` : 'مستخدم'),
    avatarUrl: u.avatarUrl ?? null,
    displayId: u.displayId ?? null,
    level: u.level ?? 1,
    vipLevel: u.vipLevel ?? 0,
  }));
}

let _io: Server | null = null;

export function invalidateAdminCacheAndRefresh(roomId: number) {
  adminCacheTTL.delete(roomId);
  if (_io) emitRoomState(_io, roomId).catch(console.error);
}

export function broadcastRoomClosed(roomId: number) {
  if (!_io) return;
  _io.to(`room:${roomId}`).emit('room_closed', { roomId });
}

export const initializeSocketHandlers = (io: Server) => {
  _io = io;
  io.use(async (socket: AuthenticatedSocket, next) => {
  let payload: { userId: number };
  try {
    let token = socket.handshake.auth?.token
      || socket.handshake.headers?.authorization?.replace('Bearer ', '');

    if (!token) return next(new Error('no token'));

    // ✅ Strip surrounding quotes if stored badly
    token = token.trim().replace(/^["']|["']$/g, '');

    if (!token) return next(new Error('no token'));

    payload = verifyAccessToken(token);
  } catch (err) {
    console.error('[socket auth error]', err);
    return next(new Error('invalid token'));
  }

  // A banned account must not hold a socket either — otherwise they stay in
  // rooms, chat and send gifts for as long as the connection lives.
  const ban = await getBanState(payload.userId);
  if (ban.banned) return next(new Error('banned'));

  socket.userId = payload.userId;
  // Mirrored onto `data` because fetchSockets() hands back RemoteSockets,
  // which carry `data` but not custom properties — buildRoomUsers needs it.
  socket.data.userId = payload.userId;
  return next();
});

  io.on('connection', (socket: AuthenticatedSocket) => {

 const uid = socket.userId;

if (uid) {
  socket.join(uid.toString());        // keep (used by WebRTC & approveMic in your code)
  socket.join(`user:${uid}`);         // ✅ ADD THIS (for dm_* events)
  console.log('[socket connected]', { uid, sid: socket.id });

  // Presence: announce only on the offline -> online transition.
  if (markOnline(uid, socket.id)) {
    io.emit('presence:update', { userId: uid, online: true });
  }
  // Send the current online roster to the freshly-connected client.
  socket.emit('presence:snapshot', { online: getOnlineUserIds() });
}

// Client can request the online roster at any time (e.g. opening a list).
socket.on('get_online_users', () => {
  socket.emit('presence:snapshot', { online: getOnlineUserIds() });
});

// Same idea, scoped to one room: who is in here right now. Lets a client
// refresh its member list on demand (opening the invite sheet, reconnecting)
// without waiting for the next join.
socket.on('get_room_users', async ({ roomId }: any) => {
  const rid = toInt(roomId);
  if (!rid) return;
  try {
    socket.emit('room_users', { roomId: rid, users: await buildRoomUsers(io, rid) });
  } catch (e) {
    console.warn('[get_room_users] failed:', e);
  }
});

// ── Skill dice table: joining only subscribes you to the live round state.
// Entering a round (and paying the entry price) goes through the REST
// endpoints so the coin movement stays atomic. ──
socket.on('dice_join_table', () => {
  socket.join(DICE_TABLE_ROOM);
  socket.emit('dice_round_state', getCurrentRoundPublic());
});

socket.on('dice_leave_table', () => {
  socket.leave(DICE_TABLE_ROOM);
});

// ── Skill wheel table: joining only subscribes you to the live round state;
// entering a round (and paying the entry price) goes through REST. ──
socket.on('wheel_join_table', () => {
  socket.join(WHEEL_TABLE_ROOM);
  socket.emit('wheel_round_state', getCurrentWheelRoundPublic());
});

socket.on('wheel_leave_table', () => {
  socket.leave(WHEEL_TABLE_ROOM);
});

// ── Crazy wheel (عجلة الحظ): subscribing is free — betting, clearing and bonus
// picks all go through REST so they stay authenticated and rate-limited.
socket.on('crazy_join_table', () => {
  socket.join(CRAZY_ROOM);
  socket.emit('crazy_state', getCrazyWheelState());
});

socket.on('crazy_leave_table', () => {
  socket.leave(CRAZY_ROOM);
});

// ── Crash (طيّار): subscribing to the table is free — betting, cashing out and
// chatting all go through the REST endpoints so they stay authenticated and
// rate-limited. The socket only pushes state.
socket.on('crash_join_table', () => {
  socket.join(CRASH_ROOM);
  socket.emit('crash_state', getCrashStatePublic());
  socket.emit('crash_chat_history', getCrashChat(50));
});

socket.on('crash_leave_table', () => {
  socket.leave(CRASH_ROOM);
});

// ── Lion & tiger arena: same deal — subscribing to the ring is free, entering
// a round (and paying the ticket price) goes through the REST endpoints. ──
socket.on('boxing_join_table', () => {
  socket.join(BOXING_RING_ROOM);
  socket.emit('boxing_round_state', getCurrentBoxingRoundPublic());
});

socket.on('boxing_leave_table', () => {
  socket.leave(BOXING_RING_ROOM);
});

// Step 5: voice quality check. A speaker reports their mic self-test result
// (live audio track + echo/noise/gain processing on). Broadcast so every
// client can show a "perfect mic" badge on that seat.
socket.on('mic_status', ({ roomId, ok }: any) => {
  const rid = toInt(roomId);
  const uid = socket.userId;
  if (!uid || !rid) return;
  io.to(`room:${rid}`).emit('mic_verified', { userId: uid, ok: !!ok });
});

socket.on('send_dm', async ({ toUserId, text }: any) => {
  try {
  const senderId = socket.userId;
  const receiverId = Number(toUserId);
  const clean = (text ?? '').toString().trim();
  if (!senderId || !receiverId || !clean) return;

  // القائمة السوداء — a block in either direction stops the DM.
  if (await isBlockedBetween(senderId, receiverId)) {
    socket.emit('dm_blocked', {
      toUserId: receiverId,
      message: 'لا يمكن إرسال رسالة — يوجد حظر بينكما',
    });
    return;
  }

  const userAId = Math.min(senderId, receiverId);
  const userBId = Math.max(senderId, receiverId);

  const conv = await prisma.conversation.upsert({
    where: { userAId_userBId: { userAId, userBId } },
    create: {
      userAId,
      userBId,
      participants: { create: [{ userId: senderId }, { userId: receiverId }] },
    },
    update: {},
  });

  const msg = await prisma.$transaction(async (tx) => {
  const m = await tx.directMessage.create({
    data: { conversationId: conv.id, senderId, text: clean, type: 'text' },
    include: { sender: { select: {
  id: true,
  name: true,
  avatarUrl: true,        // 🔥 ADD THIS
  avatarFrameUrl: true,
  level: true,
} } },
  });

  await tx.conversation.update({
    where: { id: conv.id },
    data: { lastMessageId: m.id, lastMessageAt: m.createdAt },
  });

  return m;
});

  const dmPayload = {
    id: msg.id,
    conversationId: msg.conversationId,
    senderId: msg.senderId,
    text: msg.text,
    imageUrl: msg.imageUrl,
    type: msg.type,
    createdAt: msg.createdAt.toISOString(),
    sender: msg.sender,
  };

  // ✅ emit to both users
  io.to(`user:${senderId}`).emit('dm_new_message', dmPayload);
  io.to(`user:${receiverId}`).emit('dm_new_message', dmPayload);

  // optional: update conversation list live (simple payload)
  io.to(`user:${senderId}`).emit('dm_conversation_updated', {
    conversationId: conv.id,
    partnerId: receiverId,
    lastMessage: clean,
    lastMessageTime: msg.createdAt.toISOString(),
  });

  io.to(`user:${receiverId}`).emit('dm_conversation_updated', {
    conversationId: conv.id,
    partnerId: senderId,
    lastMessage: clean,
    lastMessageTime: msg.createdAt.toISOString(),
  });
  } catch (err) {
    console.error('[socket.send_dm] handler error:', err);
    socket.emit('error', { event: 'send_dm', message: 'Internal error' });
  }
});

socket.on('set_seat_count', async ({ roomId, seatCount }: any) => {
  try {
  const rid = toInt(roomId);
  const count = toInt(seatCount);
  const uid = socket.userId;
  if (rid === null || count === null || !uid) return; // ✅ correct

  await populateAdmins(rid);
  if (!getAdmins(rid).has(uid)) return;

  const safe = Math.max(1, Math.min(24, count)); // ✅ no ! needed
  await prisma.room.update({ where: { id: rid }, data: { maxSeats: safe } });
  await emitRoomState(io, rid);
  } catch (err) {
    console.error('[socket.set_seat_count] handler error:', err);
    socket.emit('error', { event: 'set_seat_count', message: 'Internal error' });
  }
});

socket.on('moveSeat', async ({ roomId, fromSeat, toSeat }: any) => {
  const rid = toInt(roomId);
  const from = toInt(fromSeat);
  const to = toInt(toSeat);
  const uid = socket.userId;
  if (!rid || !from || !to || !uid) return;

  const seats = getSeats(rid);
  const lockedSet = getLockedSeats(rid);

  // Verify the user is in fromSeat
  if (seats.get(from) !== uid) {
    socket.emit('seat_error', { message: 'Not your seat' });
    return;
  }

  // Target seat must be free and not locked
  if (seats.has(to) || lockedSet.has(to)) {
    socket.emit('seat_error', { message: 'Target seat unavailable' });
    return;
  }

  const room = await prisma.room.findUnique({ where: { id: rid }, select: { maxSeats: true } });
  const maxSeats = room?.maxSeats ?? 8;
  if (to < 1 || to > maxSeats) return;

  seats.delete(from);
  seats.set(to, uid);

  await emitRoomState(io, rid);
});



socket.on('seat_lock', async ({ roomId, seatNumber, locked }: any) => {
  const rid = toInt(roomId);
  const sn = toInt(seatNumber);
  const uid = socket.userId;
  if (!rid || !sn || !uid) return;

  await populateAdmins(rid);
  const admins = getAdmins(rid);
  if (!admins.has(uid)) return; // ✅ only admin/owner

  const room = await prisma.room.findUnique({
    where: { id: rid },
    select: { maxSeats: true },
  });
  const maxSeats = room?.maxSeats ?? 8;
  if (sn < 1 || sn > maxSeats) return;

  const set = getLockedSeats(rid);
  const willLock = locked === true || locked?.toString() === 'true';

  if (willLock) set.add(sn);
  else set.delete(sn);

  // ✅ broadcast to everyone
  io.to(`room:${rid}`).emit('seat_lock', {
    roomId: rid,
    seatNumber: sn,
    locked: willLock,
  });

  // ✅ strong sync: snapshot refresh
  await emitRoomState(io, rid);
});

// Admin mutes/unmutes a seat position — broadcast so all clients reflect it.
socket.on('seat_mute_lock', async ({ roomId, seatNumber, muted }: any) => {
  const rid = toInt(roomId);
  const sn = toInt(seatNumber);
  const uid = socket.userId;
  if (!rid || !sn || !uid) return;
  await populateAdmins(rid);
  if (!getAdmins(rid).has(uid)) return; // only admin/owner
  const willMute = muted === true || muted?.toString() === 'true';
  const mutedSet = getAdminMutedSeats(rid);
  if (willMute) mutedSet.add(sn); else mutedSet.delete(sn);
  io.to(`room:${rid}`).emit('seat_mute_lock', {
    roomId: rid,
    seatNumber: sn,
    muted: willMute,
  });
});

socket.on('take_seat', async ({ roomId, seatNumber }: any) => {
  try {
  const rid = toInt(roomId);
  const sn = toInt(seatNumber);
  const uid = socket.userId;
  if (!rid || !sn || !uid) return;

  // make sure socket is in the room so it receives updates too
  socket.join(`room:${rid}`);

  const lockedSet = getLockedSeats(rid);
if (lockedSet.has(sn)) {
  socket.emit('seat_error', {
    roomId: rid,
    seatNumber: sn,
    message: 'Seat is locked',
  });
  return;
}

  // Per-user seat block (admin moderation): cannot take any seat until cleared.
  const seatBlock = await prisma.roomMember
    .findUnique({
      where: { userId_roomId: { userId: uid, roomId: rid } },
      select: { seatBlocked: true },
    })
    .catch(() => null);
  if (seatBlock?.seatBlocked) {
    socket.emit('seat_error', {
      roomId: rid,
      seatNumber: sn,
      message: 'تم منعك من الجلوس على المايك بواسطة الإدارة',
    });
    return;
  }

  const seats = getSeats(rid);
const room = await prisma.room.findUnique({
  where: { id: rid },
  select: { maxSeats: true },
});
const maxSeats = room?.maxSeats ?? 8;

if (sn < 1 || sn > maxSeats) {
  socket.emit('seat_error', { roomId: rid, seatNumber: sn, message: 'Invalid seat number' });
  return;
}

  // seat occupied?
  if (seats.has(sn)) {
socket.emit('seat_error', {
  roomId: rid,
  seatNumber: sn,
  message: 'Seat already occupied',
});
    return;
  }

  // user already seated somewhere?
  for (const [num, occupant] of seats.entries()) {
    if (occupant === uid) {
socket.emit('seat_error', {
  roomId: rid,
  seatNumber: sn,
  message: 'You are already seated',
});
      return;
    }
  }

  seats.set(sn, uid);

// Persist seat to DB — composite PK @@id([userId, roomId])
try {
  await prisma.roomMember.upsert({
    where: { userId_roomId: { userId: uid, roomId: rid } },
    create: { roomId: rid, userId: uid, role: 'member' },
    update: { joinedAt: new Date() },
  });
} catch (err) {
  console.error('[socket.take_seat] roomMember upsert failed:', err);
  seats.delete(sn); // roll back in-memory seat
  socket.emit('seat_error', { roomId: rid, seatNumber: sn, message: 'Failed to claim seat, please try again' });
  return;
}

  getMuted(rid).set(uid, true); // start muted

  // Airtime starts the moment the seat is held (owner request: أيام وساعات
  // البث). Fire-and-forget — never let bookkeeping fail a seat claim.
  startBroadcast(uid, rid).catch(() => {});

  const u = await prisma.user.findUnique({
    where: { id: uid },
    select: {
  id: true,
  name: true,
  avatarUrl: true,        // 🔥 ADD THIS
  avatarFrameUrl: true,
  activeFrame: { select: { assetUrl: true } },
  level: true,
  displayId: true,
  vipLevel: true,
}
  });
      const avatarFrameUrl = u?.activeFrame?.assetUrl ?? u?.avatarFrameUrl ?? null;

      console.log("🧪 BACKEND seat_occupied:", {
  seatNumber: sn,
  userId: uid,
  username: u?.name,
  avatarFrameUrl,
});

  // ✅ broadcast to everyone (this is what other devices need)
  io.to(`room:${rid}`).emit('seat_occupied', {
    seatNumber: sn,
    userId: uid,
    username: u?.name ?? null,
    avatarUrl: u?.avatarUrl ?? null,
    avatarFrameUrl, // ✅ ADD THIS
    frameImageUrl: avatarFrameUrl,
    level: u?.level ?? 1,
    displayId: u?.displayId ?? null,
    vipLevel: u?.vipLevel ?? 0,
    isMuted: true,
  });

  console.log("DEBUG USER:", u);
  // optional: if you use voice list as “on mic”, don’t add here until unmuted
  // getVoiceSet(rid).add(uid);
  // await emitVoiceUsers(io, rid);

  // optional full snapshot (strongest sync)
  await emitRoomState(io, rid);
  } catch (err) {
    console.error('[socket.take_seat] handler error:', err);
    socket.emit('error', { event: 'take_seat', message: 'Internal error' });
  }
});

// ----------------------------
// Snapshot request (Flutter calls this)
// ----------------------------
socket.on('init_room_seats', async ({ roomId }: any) => {
  const rid = toInt(roomId);
  if (!rid) return;

  // make sure socket is in the room so it receives updates
  socket.join(`room:${rid}`);

  // send FULL snapshot to requester (and also refresh room to be safe)
  await emitRoomState(io, rid);
});

    // ----------------------------
    // Join room (chat/seats)
    // ----------------------------
    socket.on('join_room', async ({ roomId, code }) => {
      try {
      const uid = socket.userId;
      const rid = toInt(roomId);
      if (!uid || !rid) return;

      // ── Locked-room gate: a 5-digit PIN is required to enter when the room
      // is locked *and* a PIN is set. The owner and room admins always bypass.
      // (Rooms with isLocked=true but no accessCode are legacy boolean locks —
      // treat them as open so nobody is permanently locked out.) ──
      const roomRow = await prisma.room.findUnique({
        where: { id: rid },
        select: { isLocked: true, accessCode: true, ownerId: true, isActive: true },
      });
      if (!roomRow?.isActive) {
        socket.emit('join_denied', { roomId: rid, reason: 'closed' });
        return;
      }
      if (roomRow?.isLocked && roomRow.accessCode) {
        await populateAdmins(rid);
        const privileged = roomRow.ownerId === uid || getAdmins(rid).has(uid);
        const provided = code != null ? String(code).trim() : '';
        if (!privileged && provided !== roomRow.accessCode) {
          socket.emit('join_denied', { roomId: rid, reason: 'locked' });
          socket.leave(`room:${rid}`);
          return;
        }
      }

      // ── Ban/kick gate: an active (non-expired) RoomBan blocks entry. ──
      const ban = await prisma.roomBan
        .findUnique({
          where: { roomId_userId: { roomId: rid, userId: uid } },
          select: { expiresAt: true, reason: true },
        })
        .catch(() => null);
      if (ban && (!ban.expiresAt || ban.expiresAt > new Date())) {
        console.log('[join_denied]', { uid, rid, reason: 'banned', until: ban.expiresAt });
        socket.emit('join_denied', {
          roomId: rid,
          reason: 'banned',
          until: ban.expiresAt ?? null,
          message: ban.reason ?? 'تم طردك من هذه الغرفة',
        });
        socket.leave(`room:${rid}`);
        return;
      }

      const locked = getLockedSeats(rid);

      socket.join(`room:${rid}`);
      userCurrentRoom.set(uid, rid); // #25/#31: track actual current room
      await populateAdmins(rid);

      const admins = getAdmins(rid);
      const seatsMap = getSeats(rid);
      const mutedMap = getMuted(rid);
      const queue = getQueue(rid);

      console.log('[join_room]', {
        uid,
        rid,
        admins: Array.from(admins),
        seats: Array.from(seatsMap.entries()),
        queue,
      });

      // ── Group 12: entrance announcement for EVERY user (user_joined below
      // only fires for auto-seated admins). Carries the user's active entrance
      // banner design (bought in store or granted via VIP) + level/VIP for the
      // animated banner and the "[Name] دخل الغرفة" chat line. Debounced so
      // reconnects don't spam the room. ──
      const entryKey = `${rid}:${uid}`;
      const lastEntry = recentRoomEntries.get(entryKey) ?? 0;
      if (Date.now() - lastEntry > ENTRANCE_DEBOUNCE_MS) {
        recentRoomEntries.set(entryKey, Date.now());
        try {
          const [entrant, activeBanner, activeEffect] = await Promise.all([
            prisma.user.findUnique({
              where: { id: uid },
              select: { name: true, avatarUrl: true, displayId: true, level: true, vipLevel: true },
            }),
            (prisma as any).userItem.findFirst({
              where: { userId: uid, isActive: true, item: { type: 'ENTRANCE_BANNER' } },
              include: { item: { select: { assetUrl: true } } },
            }),
            (prisma as any).userItem.findFirst({
              where: { userId: uid, isActive: true, item: { type: 'ENTRANCE_EFFECT' } },
              include: { item: { select: { assetUrl: true } } },
            }),
          ]);
          io.to(`room:${rid}`).emit('user_entered', {
            roomId: rid,
            userId: uid,
            username: entrant?.name ?? (entrant?.displayId ? `#${entrant.displayId}` : 'مستخدم'),
            avatarUrl: entrant?.avatarUrl ?? null,
            displayId: entrant?.displayId ?? null,
            level: entrant?.level ?? 1,
            vipLevel: entrant?.vipLevel ?? 0,
            bannerUrl: activeBanner?.item?.assetUrl ?? null,
          });

          // The entrance video/sound used to be played locally by the entrant
          // only, so nobody else in the room ever saw or heard it. Broadcast it
          // to the whole room (entrant included) from this single event so every
          // client starts it at the same moment.
          const effectUrl = activeEffect?.item?.assetUrl ?? null;
          console.log('[entrance]', {
            uid,
            rid,
            effect: effectUrl ? 'yes' : 'none',
            // How many sockets actually receive it — if this is 1 while two
            // devices are in the room, the problem is room membership, not the
            // effect itself.
            recipients: io.sockets.adapter.rooms.get(`room:${rid}`)?.size ?? 0,
          });
          if (effectUrl) {
            io.to(`room:${rid}`).emit('seat_effect', {
              roomId: rid,
              userId: uid,
              video: effectUrl,
              kind: 'entrance',
            });
          }
        } catch (e) {
          console.warn('[join_room] user_entered emit failed:', e);
        }
      }

      // ✅ Auto-seat admins
      if (admins.has(uid)) {
        let seatNum: number | null = null;

        // already seated?
        for (const [num, occupant] of seatsMap.entries()) {
          if (occupant === uid) {
            seatNum = num;
            break;
          }
        }

        // find first available seat
        if (seatNum == null) {
          const room = await prisma.room.findUnique({
            where: { id: rid },
            select: { maxSeats: true },
          });
          const maxSeats = room?.maxSeats ?? 8;

          for (let i = 1; i <= maxSeats; i++) {
            if (!seatsMap.has(i) && !locked.has(i)) {
              seatNum = i;
              break;
            }
          }
        }

        if (seatNum != null) {
          seatsMap.set(seatNum, uid);
          mutedMap.set(uid, false);

          const user = await prisma.user.findUnique({
            where: { id: uid },
             select: {
  id: true,
  name: true,
  avatarUrl: true,        // 🔥 ADD THIS
  avatarFrameUrl: true,
  activeFrame: { select: { assetUrl: true } },
  level: true,
  displayId: true,
  vipLevel: true,
}
          });
            const avatarFrameUrl = user?.activeFrame?.assetUrl ?? user?.avatarFrameUrl ?? null;
          console.log('[auto-seat assigned]', { uid, rid, seatNum });

          io.to(`room:${rid}`).emit('seat_occupied', {
  seatNumber: seatNum,
  userId: uid,
  username: user?.name ?? null,
  avatarUrl: user?.avatarUrl ?? null,
  avatarFrameUrl, // ✅ ADD
  frameImageUrl: avatarFrameUrl,
  level: user?.level ?? 1,
  displayId: user?.displayId ?? null,
  vipLevel: user?.vipLevel ?? 0,
  isMuted: false,
});

// (user_joined is emitted once for every entrant below, not just here.)

getVoiceSet(rid).add(uid);
await emitVoiceUsers(io, rid);
//await emitRoomState(io, rid);


        } else {
          console.log('[auto-seat failed] no seat available', { uid, rid });
        }
      }

      // Unified snapshot (full seats 1..maxSeats) to avoid payload mismatches.
      await emitRoomState(io, rid);

      // Roster, both directions:
      //  • `user_joined` for EVERY entrant — it used to fire only inside the
      //    auto-seat-admin branch, so an ordinary user entering never appeared
      //    in anyone else's member list.
      //  • `room_users` back to the joiner, who otherwise has no way to learn
      //    about the people already in the room.
      // Together these are what makes "دعوة إلى المقعد" list the whole room
      // instead of just the viewer.
      try {
        const joiner = await prisma.user.findUnique({
          where: { id: uid },
          select: { id: true, name: true, avatarUrl: true, displayId: true, level: true, vipLevel: true },
        });
        io.to(`room:${rid}`).emit('user_joined', {
          userId: uid,
          roomId: rid,
          username: joiner?.name ?? (joiner?.displayId ? `#${joiner.displayId}` : 'مستخدم'),
          avatarUrl: joiner?.avatarUrl ?? null,
          displayId: joiner?.displayId ?? null,
          level: joiner?.level ?? 1,
          vipLevel: joiner?.vipLevel ?? 0,
        });
        socket.emit('room_users', { roomId: rid, users: await buildRoomUsers(io, rid) });
      } catch (e) {
        console.warn('[join_room] roster emit failed:', e);
      }

      io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue });
      } catch (err) {
        console.error('[socket.join_room] handler error:', err);
        socket.emit('error', { event: 'join_room', message: 'Internal error' });
      }
    });

    // ----------------------------
    // Leave room
    // ----------------------------
socket.on('leave_room', async ({ roomId }: any) => {
  const rid = toInt(roomId);
  const uid = socket.userId;
  if (!uid || !rid) return;

  socket.leave(`room:${rid}`);
  if (userCurrentRoom.get(uid) === rid) userCurrentRoom.delete(uid); // #25/#31
  // A deliberate exit ends the debounce window: coming back in is a real
  // entrance and must play for the whole room, however fast they return.
  // Reconnects never send leave_room, so they stay debounced.
  recentRoomEntries.delete(`${rid}:${uid}`);
  console.log('[leave_room]', { uid, rid });

  // cleanup: remove from queue
  const q = getQueue(rid).filter((id) => id !== uid);
  roomMicQueue.set(rid, q);

  // cleanup: remove from seats
  const seats = getSeats(rid);
  for (const [num, occupant] of seats.entries()) {
    if (occupant === uid) {
      seats.delete(num);
      getMuted(rid).delete(uid);
      endBroadcast(uid).catch(() => {}); // left the room while on the mic

      io.to(`room:${rid}`).emit('seat_released', { seatNumber: num, userId: uid });

      getVoiceSet(rid).delete(uid);
      emitVoiceUsers(io, rid);
    }
  }

  // ✅ ONE strong snapshot after all cleanup
  await emitRoomState(io, rid);
  cleanupRoomStateIfEmpty(rid);

  io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });

  io.to(`room:${rid}`).emit('user_left', {
  userId: uid,
  roomId: rid
});

});


    // ----------------------------
    // Chat
    // ----------------------------
    socket.on('send_message', async ({ roomId, message }: any) => {
      try {
      const uid = socket.userId;
      const rid = toInt(roomId);
      // ✅ FIX: limit message length to prevent DB/client abuse
      const MAX_MSG = 500;
      const clean = message?.toString().trim().slice(0, MAX_MSG);
      if (!uid || !rid || !clean) return;

      // ✅ FIX: fetch username from DB — never trust client-provided username (was spoofable)
      const user = await prisma.user.findUnique({
        where: { id: uid },
        select: { name: true, avatarUrl: true, level: true, vipLevel: true },
      });
      const username = user?.name ?? 'Unknown';

      // Group 12: the sender's active chat-bubble design (store/dashboard-managed).
      let bubbleUrl: string | null = null;
      try {
        const activeBubble = await (prisma as any).userItem.findFirst({
          where: { userId: uid, isActive: true, item: { type: 'CHAT_BUBBLE' } },
          include: { item: { select: { assetUrl: true } } },
        });
        bubbleUrl = activeBubble?.item?.assetUrl ?? null;
      } catch (e) {
        console.warn('[send_message] bubble lookup failed:', e);
      }

      const msg = await prisma.roomMessage.create({
        data: {
          roomId: rid,
          userId: uid,
          username,
          content: clean,
          timestamp: new Date(),
        },
      });

      io.to(`room:${rid}`).emit('new_message', {
        id: msg.id,
        roomId: rid,
        userId: uid,
        username,
        message: clean,
        timestamp: Date.now(),
        avatar: user?.avatarUrl ?? null,
        // Group 12: level-tiered + custom chat bubbles.
        level: user?.level ?? 1,
        vipLevel: user?.vipLevel ?? 0,
        bubbleUrl,
      });
      } catch (err) {
        console.error('[socket.send_message] handler error:', err);
        socket.emit('error', { event: 'send_message', message: 'Internal error' });
      }
    });

    socket.on('typing', ({ roomId, username, isTyping }: any) => {
      const rid = toInt(roomId);
      if (!rid) return;
      io.to(`room:${rid}`).emit('typing', {
        userId: socket.userId,
        username,
        isTyping,
      });
    });

    // ----------------------------
    // Mic queue
    // ----------------------------
    socket.on('request_mic', ({ roomId }: any) => {
      const rid = toInt(roomId);
      const uid = socket.userId;
      if (!uid || !rid) return;

      console.log('[request_mic]', { uid, rid });

      const q = getQueue(rid);
      if (!q.includes(uid)) q.push(uid);
      io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });
    });

    socket.on('cancel_mic_request', ({ roomId }: any) => {
      const rid = toInt(roomId);
      const uid = socket.userId;
      if (!uid || !rid) return;

      console.log('[cancel_mic_request]', { uid, rid });

      const q = getQueue(rid).filter((id) => id !== uid);
      roomMicQueue.set(rid, q);
      io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });
    });

    socket.on('approve_mic', async ({ roomId, targetUserId, userId }: any) => {
  try {
  const adminId = socket.userId;
  const rid = toInt(roomId);
  const targetId = toInt(targetUserId ?? userId);

  if (!adminId || !rid || !targetId) return;

  let adminsSet = getAdmins(rid);
  if (adminsSet.size === 0) {
    await populateAdmins(rid);
    adminsSet = getAdmins(rid);
  }

  if (!adminsSet.has(adminId)) {
    console.log('❌ approve_mic rejected: not admin', { adminId, rid });
    return;
  }

  // remove from queue
  const q = getQueue(rid).filter((id) => id !== targetId);
  roomMicQueue.set(rid, q);

  const room = await prisma.room.findUnique({
    where: { id: rid },
    select: { maxSeats: true },
  });
  const maxSeatsRaw = room?.maxSeats ?? 8;
  const maxSeats = maxSeatsRaw > 0 ? maxSeatsRaw : 8;

  const seats = getSeats(rid);
  const lockedSet = getLockedSeats(rid);

  let seatNum: number | null = null;

  // already seated?
  for (const [num, occupant] of seats.entries()) {
    if (occupant === targetId) {
      seatNum = num;
      break;
    }
  }

  // find free + NOT locked
  if (seatNum == null) {
    for (let i = 1; i <= maxSeats; i++) {
      if (!seats.has(i) && !lockedSet.has(i)) {
        seatNum = i;
        break;
      }
    }
  }

  if (seatNum == null) {
    console.log('[approve_mic] no seat available', { rid, targetId });
    io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });
    return;
  }

  seats.set(seatNum, targetId);
  getMuted(rid).set(targetId, false);

  const u = await prisma.user.findUnique({
    where: { id: targetId },
    // ✅ FIX: also join activeFrame — was missing so approved users showed no frame
    // unlike take_seat and join_room which both do this correctly
    select: {
      id: true,
      name: true,
      avatarUrl: true,
      avatarFrameUrl: true,
      activeFrame: { select: { assetUrl: true } },
      level: true,
    },
  });

  // ✅ FIX: prefer activeFrame.assetUrl (same priority as take_seat)
  const avatarFrameUrl = u?.activeFrame?.assetUrl ?? u?.avatarFrameUrl ?? null;

  io.to(`room:${rid}`).emit('seat_occupied', {
  seatNumber: seatNum,
  userId: targetId,
  username: u?.name ?? null,
  avatarUrl: u?.avatarUrl ?? null,
  avatarFrameUrl, // ✅ ADD THIS
  level: u?.level ?? 1,
  isMuted: false,
});

  io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });

  // voice list
  getVoiceSet(rid).add(targetId);
  await emitVoiceUsers(io, rid);

  // notify user directly
  io.to(targetId.toString()).emit('approve_mic', { roomId: rid, userId: targetId });

  // strong sync snapshot
  await emitRoomState(io, rid);
  } catch (err) {
    console.error('[socket.approve_mic] handler error:', err);
    socket.emit('error', { event: 'approve_mic', message: 'Internal error' });
  }
});

// #12: admin/supervisor invites a specific audience user onto a SPECIFIC seat
// (unlike approve_mic which auto-picks). Works even if the seat is closed/muted.
socket.on('invite_to_seat', async ({ roomId, targetUserId, seatNumber }: any) => {
  try {
    const adminId = socket.userId;
    const rid = toInt(roomId);
    const targetId = toInt(targetUserId);
    const seatNum = toInt(seatNumber);
    if (!adminId || !rid || !targetId || !seatNum) return;

    let adminsSet = getAdmins(rid);
    if (adminsSet.size === 0) { await populateAdmins(rid); adminsSet = getAdmins(rid); }
    if (!adminsSet.has(adminId)) return; // owner + supervisor/admins only

    const room = await prisma.room.findUnique({ where: { id: rid }, select: { maxSeats: true } });
    const maxSeats = (room?.maxSeats ?? 8) > 0 ? (room?.maxSeats ?? 8) : 8;
    if (seatNum < 1 || seatNum > maxSeats) return;

    const seats = getSeats(rid);
    if (seats.has(seatNum) && seats.get(seatNum) !== targetId) {
      socket.emit('seat_error', { message: 'Seat occupied' });
      return;
    }

    // Do NOT seat the user here. Send an invitation they can accept or refuse;
    // `seat_invite_response` below does the actual seating on acceptance.
    purgeExpiredSeatInvites();
    const inviter = await prisma.user.findUnique({
      where: { id: adminId },
      select: { name: true, displayId: true },
    });
    const fromUsername = inviter?.name ?? (inviter?.displayId ? `#${inviter.displayId}` : 'مشرف');

    const inviteId = `${rid}:${seatNum}:${targetId}:${Date.now()}`;
    pendingSeatInvites.set(inviteId, {
      roomId: rid,
      seatNumber: seatNum,
      targetUserId: targetId,
      fromUserId: adminId,
      fromUsername,
      expiresAt: Date.now() + SEAT_INVITE_TTL_MS,
    });

    io.to(targetId.toString()).emit('seat_invite', {
      inviteId,
      roomId: rid,
      seatNumber: seatNum,
      fromUserId: adminId,
      fromUsername,
      expiresInMs: SEAT_INVITE_TTL_MS,
    });
    socket.emit('seat_invite_sent', { inviteId, targetUserId: targetId, seatNumber: seatNum });
  } catch (err) {
    console.error('[socket.invite_to_seat] handler error:', err);
    socket.emit('error', { event: 'invite_to_seat', message: 'Internal error' });
  }
});

/** The invitee answers a mic invitation. Seats them only on `accept: true`. */
socket.on('seat_invite_response', async ({ inviteId, accept }: any) => {
  try {
    const uid = socket.userId;
    if (!uid || !inviteId) return;

    purgeExpiredSeatInvites();
    const invite = pendingSeatInvites.get(String(inviteId));
    if (!invite) {
      socket.emit('seat_error', { message: 'انتهت صلاحية الدعوة' });
      return;
    }
    // Only the person who was invited may answer it.
    if (invite.targetUserId !== uid) return;
    pendingSeatInvites.delete(String(inviteId));

    const rid = invite.roomId;
    const seatNum = invite.seatNumber;

    if (!accept) {
      io.to(invite.fromUserId.toString()).emit('seat_invite_result', {
        roomId: rid, seatNumber: seatNum, userId: uid, accepted: false,
      });
      return;
    }

    const seats = getSeats(rid);
    if (seats.has(seatNum) && seats.get(seatNum) !== uid) {
      socket.emit('seat_error', { message: 'المقعد مشغول الآن' });
      io.to(invite.fromUserId.toString()).emit('seat_invite_result', {
        roomId: rid, seatNumber: seatNum, userId: uid, accepted: false, reason: 'occupied',
      });
      return;
    }

    // remove the invitee from any current seat + the mic queue
    for (const [num, occ] of seats.entries()) if (occ === uid) seats.delete(num);
    roomMicQueue.set(rid, getQueue(rid).filter((id) => id !== uid));

    seats.set(seatNum, uid);
    getMuted(rid).set(uid, false);

    const u = await prisma.user.findUnique({
      where: { id: uid },
      select: { id: true, name: true, avatarUrl: true, avatarFrameUrl: true, activeFrame: { select: { assetUrl: true } }, level: true },
    });
    const avatarFrameUrl = u?.activeFrame?.assetUrl ?? u?.avatarFrameUrl ?? null;

    io.to(`room:${rid}`).emit('seat_occupied', {
      seatNumber: seatNum, userId: uid, username: u?.name ?? null,
      avatarUrl: u?.avatarUrl ?? null, avatarFrameUrl, level: u?.level ?? 1, isMuted: false,
    });
    getVoiceSet(rid).add(uid);
    await emitVoiceUsers(io, rid);
    io.to(uid.toString()).emit('approve_mic', { roomId: rid, userId: uid });
    io.to(invite.fromUserId.toString()).emit('seat_invite_result', {
      roomId: rid, seatNumber: seatNum, userId: uid, accepted: true, username: u?.name ?? null,
    });
    await emitRoomState(io, rid);
  } catch (err) {
    console.error('[socket.seat_invite_response] handler error:', err);
    socket.emit('error', { event: 'seat_invite_response', message: 'Internal error' });
  }
});


    socket.on('reject_mic', async ({ roomId, targetUserId, userId }: any) => {
      const adminId = socket.userId;
      const rid = toInt(roomId);
      const targetId = toInt(targetUserId ?? userId);
      if (!adminId || !rid || !targetId) return;

      let adminsSet = getAdmins(rid);
      if (adminsSet.size === 0) {
        await populateAdmins(rid);
        adminsSet = getAdmins(rid);
      }
      if (!adminsSet.has(adminId)) return;

      const q = getQueue(rid).filter((id) => id !== targetId);
      roomMicQueue.set(rid, q);
      io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });
    });

    socket.on('set_seat_mute', async ({ roomId, seatNumber, targetUserId, mute }) => {
    const rid = toInt(roomId);
    const sn = toInt(seatNumber);
    const target = toInt(targetUserId);
    if (!rid || !sn || !target || socket.userId == null) return;

    await populateAdmins(rid);
    const admins = getAdmins(rid);
    if (!admins.has(socket.userId)) return; // only admins

    // verify target is actually on that seat
    const seats = getSeats(rid);
    if (seats.get(sn) !== target) return;

getMuted(rid).set(target, !!mute); // ✅ target = userId


    io.to(`room:${rid}`).emit('seat_mute_changed', {
      roomId: rid,
      seatNumber: sn,
      userId: target,
      isMuted: !!mute,
    });
    await emitRoomState(io, rid);
  });

socket.on('remove_from_seat', async ({ roomId, seatNumber, targetUserId }) => {
  const rid = toInt(roomId);
  const sn = toInt(seatNumber);
  const target = toInt(targetUserId);
  if (!rid || !sn || !target || socket.userId == null) return;

  await populateAdmins(rid);
  const admins = getAdmins(rid);
  if (!admins.has(socket.userId)) return;

  // Platform staff are immune on the seat path too, not just over REST:
  // a super admin may only be pulled down by another super admin, and an
  // admin only by an admin or above. Ranked so the room owner can never
  // touch either of them.
  try {
    const roles = await (prisma as any).user.findMany({
      where: { id: { in: [target, socket.userId] } },
      select: { id: true, isSuperAdmin: true, isAdmin: true },
    });
    const tier = (id: number) => {
      const r = roles.find((x: any) => x.id === id);
      return r?.isSuperAdmin ? 2 : r?.isAdmin ? 1 : 0;
    };
    if (tier(target) > 0 && tier(socket.userId) < tier(target)) return;
  } catch (e) {
    console.warn('remove_from_seat staff check failed:', e);
  }

  const seats = getSeats(rid);
  if (seats.get(sn) !== target) return;

  seats.delete(sn);
  getMuted(rid).delete(target); // ✅ FIX
  endBroadcast(target).catch(() => {}); // pulled off the mic → airtime stops

  io.to(`room:${rid}`).emit('seat_released', {
    roomId: rid,
    seatNumber: sn,
    userId: target,
  });

  await emitRoomState(io, rid);
});

    // ----------------------------
    // Seat controls
    // ----------------------------
    socket.on('leave_seat', async ({ roomId, seatNumber, seatId }: any) => {
      try {
        const rid = toInt(roomId);
        const seatNum = toInt(seatNumber ?? seatId);
        const uid = socket.userId;
        if (!uid || !rid || !seatNum) return;

        const seats = getSeats(rid);
        const occupiedUserId = seats.get(seatNum);

        if (occupiedUserId == null) {
          return socket.emit('error', { message: 'Seat not found' });
        }
        if (occupiedUserId !== uid) {
          return socket.emit('error', { message: 'Not your seat' });
        }

        seats.delete(seatNum);
        getMuted(rid).delete(uid);
        getVoiceSet(rid).delete(uid);

        console.log('[leave_seat]', { uid, rid, seatNum });

        io.to(`room:${rid}`).emit('seat_updated', {
          seatId: seatNum,
          seatNumber: seatNum,
          userId: null,
          micEnabled: false,
          isSpeaking: false,
          isMuted: true,
        });

        io.to(`room:${rid}`).emit('seat_released', {
          seatNumber: seatNum,
          userId: uid,
        });

        socket.emit('left_seat', { seatId: seatNum, seatNumber: seatNum, roomId: rid });

        await emitVoiceUsers(io, rid);
        await emitRoomState(io, rid);
      } catch (err) {
        console.error('leave_seat error:', err);
        socket.emit('error', { message: 'Could not leave seat' });
      }
    });

    socket.on('toggle_mute', async ({ roomId, seatNumber, isMuted }: any) => {
      const rid = toInt(roomId);
      const seatNum = toInt(seatNumber);
      const uid = socket.userId;
      if (!uid || !rid || !seatNum) return;

      const seats = getSeats(rid);
      if (seats.get(seatNum) !== uid) return;

      // Force-mute: an admin muted this user — block self-unmute, keep muted.
      if (!isMuted) {
        const fm = await prisma.roomMember
          .findUnique({
            where: { userId_roomId: { userId: uid, roomId: rid } },
            select: { forceMuted: true },
          })
          .catch(() => null);
        if (fm?.forceMuted) {
          getMuted(rid).set(uid, true);
          socket.emit('seat_mute_changed', {
            roomId: rid,
            seatNumber: seatNum,
            userId: uid,
            isMuted: true,
            forced: true,
          });
          return;
        }
      }

      getMuted(rid).set(uid, !!isMuted);

      console.log('[toggle_mute]', { uid, rid, seatNum, isMuted: !!isMuted });

      io.to(`room:${rid}`).emit('seat_mute_changed', {
        roomId: rid,
        seatNumber: seatNum,
        userId: uid,
        isMuted: !!isMuted,
      });

      if (!!isMuted) {
  getVoiceSet(rid).delete(uid);
} else {
  getVoiceSet(rid).add(uid);
}
await emitVoiceUsers(io, rid);
await emitRoomState(io, rid);

    });





    // ----------------------------
    // Voice presence (ONE SET ONLY)
    // ----------------------------
    socket.on('user_joined_voice', async ({ roomId }: any) => {
      const rid = Number(roomId);
      // ✅ FIX: always use socket.userId — never trust client-provided userId (was IDOR)
      const uid = socket.userId;
      if (!rid || !uid) return;

      // ✅ ensure membership in room to broadcast reliably (race safe)
      socket.join(`room:${rid}`);

      console.log('🎤 user_joined_voice', { rid, uid });

      getVoiceSet(rid).add(uid);
      await emitVoiceUsers(io, rid);
    });

    
    socket.on('get_voice_users', ({ roomId }: any) => {
      const rid = Number(roomId);
      if (!rid) return;

      const users = Array.from(getVoiceSet(rid).values());
      console.log('👥 voice_users', { rid, users });

      socket.emit('voice_users', { roomId: rid, users });
    });

    socket.on('user_left_voice', async ({ roomId, userId }: any) => {
      const rid = Number(roomId);
      const uid = Number(userId ?? socket.userId);
      if (!rid || !uid) return;

      console.log('🎤 user_left_voice', { rid, uid });

      getVoiceSet(rid).delete(uid);
      await emitVoiceUsers(io, rid);

    });

    // ----------------------------
    // WebRTC signaling (direct by userId room)
    // ----------------------------
socket.on('webrtc_offer', ({ to, offer }: any) => {
  if (to == null) return;
  const target = String(to);
  console.log('[webrtc_offer]', { from: socket.userId, to: target });
  io.to(target).emit('webrtc_offer', { from: socket.userId, offer });
});

socket.on('webrtc_answer', ({ to, answer }: any) => {
  if (to == null) return;
  const target = String(to);
  console.log('[webrtc_answer]', { from: socket.userId, to: target });
  io.to(target).emit('webrtc_answer', { from: socket.userId, answer });
});

socket.on('webrtc_ice_candidate', ({ to, candidate }: any) => {
  if (to == null) return;
  const target = String(to);
  console.log('[webrtc_ice]', { from: socket.userId, to: target });
  io.to(target).emit('webrtc_ice_candidate', { from: socket.userId, candidate });
});


    // ----------------------------
    // Disconnect cleanup (ONE ONLY)
    // ----------------------------
    socket.on('disconnect', () => {
      const uid = socket.userId;
      if (!uid) return;

      // Presence: announce only when the user's last socket goes away.
      if (markOffline(uid, socket.id)) {
        io.emit('presence:update', { userId: uid, online: false });
      }

      // voice cleanup
      for (const [rid, set] of voiceUsers.entries()) {
        if (set.delete(uid)) {
          socket.to(`room:${rid}`).emit('user_left_voice', { userId: uid, roomId: rid });
          emitVoiceUsers(io, rid); // ✅ ADD
        }
      }

      userCurrentRoom.delete(uid); // #25/#31: no longer in any room


      console.log('[disconnect]', { uid });

      // remove from all queues
      roomMicQueue.forEach((q, rid) => {
        if (q.includes(uid)) {
          const nq = q.filter((id) => id !== uid);
          roomMicQueue.set(rid, nq);
          io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: nq });
        }
      });

      // remove from all seats
      // Inside the disconnect handler, after the roomSeats.forEach loop:
roomSeats.forEach((seats, rid) => {
  let changed = false;
  for (const [num, occupant] of seats.entries()) {
    if (occupant === uid) {
      seats.delete(num);
      roomMuted.get(rid)?.delete(uid);
      io.to(`room:${rid}`).emit('seat_released', { seatNumber: num, userId: uid });
      // ✅ ADD THIS:
      io.to(`room:${rid}`).emit('user_left', { userId: uid, roomId: rid });
      changed = true;
    }
  }
  if (changed) {
    // Dropping off the mic — by leaving or by losing the connection — closes
    // the airtime stint. Safe to call when none is open.
    endBroadcast(uid).catch(() => {});
    emitRoomState(io, rid).catch(console.error);
    cleanupRoomStateIfEmpty(rid);
  }
});

    });
  });

  
};