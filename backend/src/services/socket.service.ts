import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from '../utils/jwt';
import prisma from '../utils/prisma';
import { createNotification } from './notification.service';
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

function toInt(v: any): number | null {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}


const roomLockedSeats = new Map<number, Set<number>>();

function getLockedSeats(roomId: number): Set<number> {
  if (!roomLockedSeats.has(roomId)) roomLockedSeats.set(roomId, new Set<number>());
  return roomLockedSeats.get(roomId)!;
}

// ✅ Track voice participants per room (GLOBAL ONLY)
const voiceUsers = new Map<number, Set<number>>();
const getVoiceSet = (roomId: number) => {
  if (!voiceUsers.has(roomId)) voiceUsers.set(roomId, new Set<number>());
  return voiceUsers.get(roomId)!;
};

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
  voiceUsers.delete(roomId);
  adminCacheTTL.delete(roomId);
}

const adminCacheTTL = new Map<number, number>(); // rid -> timestamp
const ADMIN_CACHE_DURATION_MS = 30_000; // 30 seconds

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
    if (m.role === 'owner' || m.role === 'admin') admins.add(m.userId);
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
    seats: seatDetails,
  });

}

async function emitVoiceUsers(io: Server, rid: number) {
  const users = Array.from(getVoiceSet(rid).values());
  io.to(`room:${rid}`).emit('voice_users', { roomId: rid, users });
}

export const initializeSocketHandlers = (io: Server) => {
  io.use((socket: AuthenticatedSocket, next) => {
  try {
    let token = socket.handshake.auth?.token 
      || socket.handshake.headers?.authorization?.replace('Bearer ', '');
    
    if (!token) return next(new Error('no token'));
    
    // ✅ Strip surrounding quotes if stored badly
    token = token.trim().replace(/^["']|["']$/g, '');
    
    if (!token) return next(new Error('no token'));
    
    const payload = verifyAccessToken(token);
    socket.userId = payload.userId;
    return next();
  } catch (err) {
    console.error('[socket auth error]', err);
    return next(new Error('invalid token'));
  }
});

  io.on('connection', (socket: AuthenticatedSocket) => {

 const uid = socket.userId;

if (uid) {
  socket.join(uid.toString());        // keep (used by WebRTC & approveMic in your code)
  socket.join(`user:${uid}`);         // ✅ ADD THIS (for dm_* events)
  console.log('[socket connected]', { uid, sid: socket.id });
}

socket.on('send_dm', async ({ toUserId, text }: any) => {
  try {
  const senderId = socket.userId;
  const receiverId = Number(toUserId);
  const clean = (text ?? '').toString().trim();
  if (!senderId || !receiverId || !clean) return;

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

  const u = await prisma.user.findUnique({
    where: { id: uid },
    select: {
  id: true,
  name: true,
  avatarUrl: true,        // 🔥 ADD THIS
  avatarFrameUrl: true,
  activeFrame: { select: { assetUrl: true } },
  level: true,
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
        select: { isLocked: true, accessCode: true, ownerId: true },
      });
      if (roomRow?.isLocked && roomRow.accessCode) {
        await populateAdmins(rid);
        const privileged = roomRow.ownerId === uid || getAdmins(rid).has(uid);
        const provided = code != null ? String(code).trim() : '';
        if (!privileged && provided !== roomRow.accessCode) {
          console.log('[join_denied]', { uid, rid, reason: 'locked', hadCode: provided.length > 0 });
          socket.emit('join_denied', { roomId: rid, reason: 'locked' });
          socket.leave(`room:${rid}`);
          return;
        }
      }

      const locked = getLockedSeats(rid);

      socket.join(`room:${rid}`);
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
  isMuted: false,
});

io.to(`room:${rid}`).emit('user_joined', {
  userId: uid,
  roomId: rid
});

getVoiceSet(rid).add(uid);
await emitVoiceUsers(io, rid);
//await emitRoomState(io, rid);


        } else {
          console.log('[auto-seat failed] no seat available', { uid, rid });
        }
      }

      // Unified snapshot (full seats 1..maxSeats) to avoid payload mismatches.
      await emitRoomState(io, rid);

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
        select: { name: true, avatarUrl: true },
      });
      const username = user?.name ?? 'Unknown';

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

  const seats = getSeats(rid);
  if (seats.get(sn) !== target) return;

  seats.delete(sn);
  getMuted(rid).delete(target); // ✅ FIX

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

      // voice cleanup
      for (const [rid, set] of voiceUsers.entries()) {
        if (set.delete(uid)) {
          socket.to(`room:${rid}`).emit('user_left_voice', { userId: uid, roomId: rid });
          emitVoiceUsers(io, rid); // ✅ ADD
        }
      }


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
    emitRoomState(io, rid).catch(console.error);
    cleanupRoomStateIfEmpty(rid);
  }
});

    });
  });

  
};