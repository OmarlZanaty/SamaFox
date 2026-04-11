import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from '../utils/jwt';
import prisma from '../utils/prisma';


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

async function populateAdmins(roomId: number) {
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
  avatarFrameUrl: true,
  activeFrameId: true,
  activeFrame: { select: { assetUrl: true } },
  level: true,
}
      })
    : [];

  const usersById = new Map(seatedUsers.map(u => [u.id, u]));

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

    return {
      seatNumber,
      userId: occupant,
      username: u?.name ?? null,
      avatarUrl: u?.avatarUrl ?? null,
  avatarFrameUrl: occupant ? frameMap.get(occupant) ?? null : null, // ✅ ADD
      frameImageUrl: occupant ? frameMap.get(occupant) ?? null : null,
      activeFrameId: u?.activeFrameId ?? null,
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
    
    console.log('[socket auth] token prefix:', token.substring(0, 20));
    
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

  try {

  const effect: any[] = await prisma.$queryRaw`
    SELECT 
      ui.product_id,
      p.file_url
    FROM user_items  ui
    JOIN products p ON ui.product_id = p.id
    WHERE ui.user_id = ${uid} AND ui.is_active = 1
  `;

  if (effect.length > 0) {

    const videoUrl = effect[0].file_url;

    io.to(`room:${rid}`).emit("seat_effect", {
      userId: uid,
      seatNumber: sn,
      video: videoUrl
    });

  }
console.log("DEBUG USER:", u);
} catch (err) {
  console.error("Seat effect error:", err);
}
  // optional: if you use voice list as “on mic”, don’t add here until unmuted
  // getVoiceSet(rid).add(uid);
  // await emitVoiceUsers(io, rid);

  // optional full snapshot (strongest sync)
  await emitRoomState(io, rid);
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
    socket.on('join_room', async ({ roomId }) => {
      const uid = socket.userId;
      const rid = toInt(roomId);
      if (!uid || !rid) return;

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
await emitRoomState(io, rid);


        } else {
          console.log('[auto-seat failed] no seat available', { uid, rid });
        }
      }

      // Unified snapshot (full seats 1..maxSeats) to avoid payload mismatches.
      await emitRoomState(io, rid);

      io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue });
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

  io.to(`room:${rid}`).emit('mic_queue_updated', { roomId: rid, queue: q });

  io.to(`room:${rid}`).emit('user_left', {
  userId: uid,
  roomId: rid
});

});


    // ----------------------------
    // Chat
    // ----------------------------
    socket.on('send_message', async ({ roomId, username, message }: any) => {
      const uid = socket.userId;
      const rid = toInt(roomId);
      const clean = message?.toString().trim();
      if (!uid || !rid || !clean) return;

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
        avatar: null,
      });
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
    select: { id: true, name: true, avatarUrl: true, avatarFrameUrl: true, level: true },
  });

  const avatarFrameUrl = u?.avatarFrameUrl ?? null;

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
    socket.on('leave_seat', async ({ roomId, seatNumber }: any) => {
      const rid = toInt(roomId);
      const seatNum = toInt(seatNumber);
      const uid = socket.userId;
      if (!uid || !rid || !seatNum) return;

      const seats = getSeats(rid);
      if (seats.get(seatNum) === uid) {
        seats.delete(seatNum);
        getMuted(rid).delete(uid);

        console.log('[leave_seat]', { uid, rid, seatNum });

        io.to(`room:${rid}`).emit('seat_released', {
          seatNumber: seatNum,
          userId: uid,
        });

        getVoiceSet(rid).delete(uid);
        await emitVoiceUsers(io, rid);
        await emitRoomState(io, rid);

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




    socket.on('send_gift', async ({ roomId, giftId, quantity, receiverId, message, toUserId }: any) => {
  const rid = toInt(roomId);
  const senderId = socket.userId;
  const gid = Number(giftId);
  const qty = Math.max(1, Number(quantity || 1));
  const recvId = receiverId != null ? Number(receiverId) : (toUserId != null ? Number(toUserId) : undefined);

  if (!senderId || !rid || !gid) return;

  const isSelfGift = recvId != null && recvId === senderId;
  const resolvedReceiverId = recvId ?? senderId;

  const gift = await prisma.gift.findUnique({ where: { id: gid } });
  if (!gift || !gift.isActive) {
    socket.emit('error', { message: 'Invalid gift' });
    return;
  }

  const [sender, receiver] = await Promise.all([
    prisma.user.findUnique({
      where: { id: senderId },
      select: { id: true, name: true, avatarUrl: true, displayId: true },
    } as any),
    prisma.user.findUnique({
      where: { id: resolvedReceiverId },
      select: { id: true, name: true, avatarUrl: true, displayId: true },
    } as any),
  ]);

  if (!sender || !receiver) {
    socket.emit('error', { message: 'User not found' });
    return;
  }

  const unitCoins = gift.coinsValue || gift.priceCoins;
  const price = BigInt(unitCoins ?? 0);
  const totalCost = price * BigInt(qty);
  if (totalCost <= BigInt(0)) {
    socket.emit('gift_error', { message: 'Invalid gift price' });
    return;
  }

  const receiverCoins = recvId != null ? totalCost / BigInt(2) : BigInt(0);

  try {
    const result = await prisma.$transaction(async (tx) => {
      // ✅ race-safe sender decrement
      const updated = await tx.user.updateMany({
        where: { id: senderId, coinsBalance: { gte: Number(totalCost) } },
        data: { coinsBalance: { decrement: Number(totalCost) } },
      });
      if (updated.count === 0) throw new Error('INSUFFICIENT_COINS');

      let receiverNewBalance: bigint | null = null;
      if (recvId != null) {
        const ur = await tx.user.update({
          where: { id: recvId },
          data: { coinsBalance: { increment: Number(receiverCoins) } },
          select: { coinsBalance: true },
        });
        receiverNewBalance = BigInt(ur.coinsBalance);
      }

      const senderNew = await tx.user.findUnique({
        where: { id: senderId },
        select: { coinsBalance: true },
      });

      const createdLog = await tx.giftLog.create({
        data: {
          senderId,
          receiverId: recvId ?? senderId,
          giftId: gid,
          roomId: rid,
          coinsSpent: Number(totalCost),
          quantity: qty,
          message: message ?? null,
        },
        include: {
          gift: true,
          sender: { select: { id: true, name: true, avatarUrl: true } },
          receiver: { select: { id: true, name: true, avatarUrl: true } },
        },
      });

      

      await tx.transaction.create({
        data: { userId: senderId, type: 'gift_send', amountCoins: -Number(totalCost), status: 'completed' },
      });

      if (recvId != null) {
        await tx.transaction.create({
          data: { userId: recvId, type: 'gift_receive', amountCoins: Number(receiverCoins), status: 'completed' },
        });
      }

      return {
        createdLog,
        senderNewBalance: BigInt(senderNew?.coinsBalance ?? 0),
        receiverNewBalance,
      };
    });

    const createdLog = result.createdLog;

    
  const payload = {
  roomId: rid,
  type: 'sent',
  senderName: createdLog.sender.name,
  senderAvatar: createdLog.sender.avatarUrl,
  receiverName: createdLog.receiver.name,
  receiverAvatar: createdLog.receiver.avatarUrl,
  giftEvent: {
    id: createdLog.id,
    giftId: gid,
    giftName: createdLog.gift.nameAr || createdLog.gift.name,
    giftImageUrl: createdLog.gift.imageUrl,
    coinsSpent: Number(totalCost),
    quantity: qty,
    message: message ?? null,
    sender: createdLog.sender,
    receiver: createdLog.receiver,
    senderId,
    receiverId: recvId ?? senderId,
    senderNewBalance: result.senderNewBalance.toString(),
    receiverCoins: receiverCoins.toString(),
    receiverNewBalance: result.receiverNewBalance?.toString() ?? null,
    createdAt: createdLog.createdAt.toISOString()
  }
};

// broadcast to everyone in room
io.to(`room:${rid}`).emit('gift', payload);

const senderName = sender.name;
const senderDisplayId = (sender as any).displayId ?? null;
const receiverDisplayId = (receiver as any).displayId ?? null;
const senderAvatarUrl = sender.avatarUrl ?? null;
const receiverId = receiver.id;
const receiverName = receiver.name;
const receiverAvatarUrl = receiver.avatarUrl ?? null;

const sentAt = new Date().toISOString();

const giftReceivedPayload = {
  giftId: gift.id,
  giftNameAr: gift.nameAr,
  giftImageUrl: gift.imageUrl,
  giftAnimationUrl: gift.animationUrl ?? null,
  coinsValue: gift.coinsValue,
  senderId: sender.id,
  senderName: sender.name,
  senderAvatarUrl: sender.avatarUrl ?? null,
  senderDisplayId,
  receiverId: receiver.id,
  receiverName: receiver.name,
  receiverAvatarUrl: receiver.avatarUrl ?? null,
  receiverDisplayId,
  roomId: rid,
  sentAt,
};

io.to(`room:${rid}`).emit('gift_received', giftReceivedPayload);

io.to(`user:${receiverId}`).emit('gift_received_personal', {
  giftNameAr: gift.nameAr,
  giftImageUrl: gift.imageUrl,
  coinsValue: gift.coinsValue,
  senderName: sender.name,
  senderAvatarUrl: sender.avatarUrl ?? null,
  sentAt,
});

// ALSO send directly to receiver (important for reliability)
if (recvId) {
  io.to(`user:${recvId}`).emit('gift', payload);
}

if (gift.coinsValue >= MEGA_GIFT_THRESHOLD) {
  const room = await prisma.room.findUnique({
    where: { id: rid },
    select: { id: true, name: true },
  });

  io.emit('global_gift_broadcast', {
    type: 'MEGA_GIFT',
    giftId: gift.id,
    giftNameAr: gift.nameAr,
    giftImageUrl: gift.imageUrl,
    giftAnimationUrl: gift.animationUrl ?? null,
    coinsValue: gift.coinsValue,
    senderId,
    senderName,
    senderAvatarUrl,
    receiverId,
    receiverName,
    receiverAvatarUrl,
    roomId: room?.id ?? rid,
    roomName: room?.name ?? 'غرفة',
    sentAt: new Date().toISOString(),
  });
}
  } catch (e: any) {
    if (e?.message === 'INSUFFICIENT_COINS') {
      socket.emit('gift_error', { message: 'Insufficient coins balance' });
      return;
    }
    console.error('send_gift socket error:', e);
    socket.emit('gift_error', { message: 'Gift failed' });
  }
    });




    // ----------------------------
    // Voice presence (ONE SET ONLY)
    // ----------------------------
    socket.on('user_joined_voice', async ({ roomId, userId }: any) => {
      const rid = Number(roomId);
      const uid = Number(userId ?? socket.userId);
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
  console.log('[webrtc_offer]', { from: socket.userId, to });
  io.to(to.toString()).emit('webrtc_offer', { from: socket.userId, offer });
});

socket.on('webrtc_answer', ({ to, answer }: any) => {
  console.log('[webrtc_answer]', { from: socket.userId, to });
  io.to(to.toString()).emit('webrtc_answer', { from: socket.userId, answer });
});

socket.on('webrtc_ice_candidate', ({ to, candidate }: any) => {
  console.log('[webrtc_ice]', { from: socket.userId, to });
  io.to(to.toString()).emit('webrtc_ice_candidate', { from: socket.userId, candidate });
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
      roomSeats.forEach((seats, rid) => {
  let changed = false;

  for (const [num, occupant] of seats.entries()) {
    if (occupant === uid) {
      seats.delete(num);
      roomMuted.get(rid)?.delete(uid);
      io.to(`room:${rid}`).emit('seat_released', { seatNumber: num, userId: uid });
      changed = true;
    }
  }

  if (changed) {
    emitRoomState(io, rid).catch(console.error);
  }
});

    });
  });

  
};
