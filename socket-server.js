import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from '../utils/jwt';
import Database from 'better-sqlite3';
import path from 'path';

// Initialize SQLite database with foreign keys disabled
const db = new Database(path.join(__dirname, '../../prisma/dev.db'));
db.pragma('foreign_keys = OFF');

interface AuthenticatedSocket extends Socket {
  userId?: number;
}

// Global WebRTC room tracking (shared across all connections)
const webrtcRooms = new Map<number, Set<number>>(); // roomId -> Set of userIds

export const initializeSocketHandlers = (io: Server) => {
  // Authentication middleware
  io.use((socket: AuthenticatedSocket, next) => {
    try {
      const token = socket.handshake.auth.token;

      if (!token) {
        return next(new Error('Authentication error: No token provided'));
      }

      const payload = verifyAccessToken(token);
      socket.userId = payload.userId;
      next();
    } catch (error) {
      next(new Error('Authentication error: Invalid token'));
    }
  });

  io.on('connection', (socket: AuthenticatedSocket) => {
    console.log(`User ${socket.userId} connected with socket ID: ${socket.id}`);

    // ========== ROOM CHAT MESSAGES (WITH DATABASE PERSISTENCE) ==========
    
    // Join chat room
    socket.on('join_room', ({ roomId, userId, username }: any) => {
      socket.join(`room:${roomId}`);
      console.log(`✅ User (${userId}) joined chat room ${roomId}`);
    });

    // Leave chat room
    socket.on('leave_room', ({ roomId, userId }: any) => {
      socket.leave(`room:${roomId}`);
      console.log(`🚪 User ${userId} left chat room ${roomId}`);
    });

    // Send message (WITH DATABASE SAVE using better-sqlite3)
    socket.on('send_message', ({ roomId, userId, username, message, timestamp }: any) => {
      console.log(`💬 Message from ${username} (${userId}) in room ${roomId}: ${message}`);

      try {
        // Save to database using better-sqlite3 (NO Prisma, NO foreign keys!)
        const stmt = db.prepare(`
          INSERT INTO room_messages (roomId, userId, username, content, timestamp)
          VALUES (?, ?, ?, ?, datetime('now'))
        `);

        const result = stmt.run(parseInt(roomId), parseInt(userId), username, message);
        const messageId = result.lastInsertRowid;

        console.log(`✅ Message saved to database with ID: ${messageId}`);

        // Broadcast to all devices in the room
        const broadcastData = {
          messageId,
          roomId: parseInt(roomId),
          userId: parseInt(userId),
          username,
          message,
          timestamp: Date.now(),
          avatar: null
        };

        io.to(`room:${roomId}`).emit('new_message', broadcastData);
        console.log(`📡 Message broadcasted to room:${roomId}`);

      } catch (error) {
        console.error('❌ Error saving/broadcasting message:', error);
      }
    });

    // Typing indicator
    socket.on('typing', ({ roomId, userId, username, isTyping }: any) => {
      socket.to(`room:${roomId}`).emit('typing', { userId, username, isTyping });
    });

    // ========== ORIGINAL HANDLERS (VOICE CHAT, WEBRTC, ETC) ==========

    // Join room
    socket.on('room:join', (roomId: number) => {
      socket.join(`room:${roomId}`);
      console.log(`User ${socket.userId} joined room ${roomId}`);

      // Notify others in the room
      socket.to(`room:${roomId}`).emit('room:user-joined', {
        userId: socket.userId,
        socketId: socket.id
      });

      // Send current room state to the user
      io.in(`room:${roomId}`).fetchSockets().then(sockets => {
        socket.emit('room:state', {
          roomId,
          participants: sockets.map(s => ({
            userId: (s as any).userId,
            socketId: s.id
          }))
        });
      });
    });

    // Leave room
    socket.on('room:leave', (roomId: number) => {
      socket.leave(`room:${roomId}`);
      console.log(`User ${socket.userId} left room ${roomId}`);

      // Notify others
      socket.to(`room:${roomId}`).emit('room:user-left', {
        userId: socket.userId,
        socketId: socket.id
      });
    });

    // Microphone toggle
    socket.on('room:mic-toggle', ({ roomId, isMuted }: { roomId: number; isMuted: boolean }) => {
      socket.to(`room:${roomId}`).emit('room:user-mic-toggle', {
        userId: socket.userId,
        isMuted
      });
    });

    // Speaking indicator
    socket.on('room:speaking', ({ roomId, isSpeaking }: { roomId: number; isSpeaking: boolean }) => {
      socket.to(`room:${roomId}`).emit('room:user-speaking', {
        userId: socket.userId,
        isSpeaking
      });
    });

    // Gift sent notification
    socket.on('gift:sent', ({ roomId, receiverId, gift }: any) => {
      // Notify the room
      io.to(`room:${roomId}`).emit('gift:received', {
        senderId: socket.userId,
        receiverId,
        gift
      });
    });

    // Private message
    socket.on('message:send', ({ receiverId, content }: { receiverId: number; content: string }) => {
      // Find receiver's socket
      const receiverSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === receiverId
      );

      receiverSockets.forEach(receiverSocket => {
        receiverSocket.emit('message:new', {
          senderId: socket.userId,
          content,
          timestamp: new Date()
        });
      });
    });

    // Typing indicator (for private messages)
    socket.on('message:typing', ({ receiverId, isTyping }: { receiverId: number; isTyping: boolean }) => {
      const receiverSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === receiverId
      );

      receiverSockets.forEach(receiverSocket => {
        receiverSocket.emit('message:user-typing', {
          userId: socket.userId,
          isTyping
        });
      });
    });

    // ========== ROOM-BASED WEBRTC SIGNALING ==========

    // Join WebRTC room
    socket.on('webrtc:room-join', (roomId: number) => {
      console.log(`\n========== WEBRTC ROOM JOIN ==========`);
      console.log(`🎤 User ${socket.userId} joining WebRTC room ${roomId}`);
      
      // Initialize room if it doesn't exist
      if (!webrtcRooms.has(roomId)) {
        console.log(`📦 Creating new WebRTC room ${roomId}`);
        webrtcRooms.set(roomId, new Set());
      }
      
      const roomMembers = webrtcRooms.get(roomId)!;
      console.log(`👥 Current members in room ${roomId} BEFORE join:`, Array.from(roomMembers));
      
      // Get existing members before adding new one
      const existingMembers = Array.from(roomMembers).map(userId => ({ userId }));
      
      // Send existing members to the new joiner
      socket.emit('webrtc:room-members', {
        roomId,
        members: existingMembers
      });
      console.log(`📡 Sent ${existingMembers.length} existing members to user ${socket.userId}:`, existingMembers);
      
      // Add new member to room
      roomMembers.add(socket.userId!);
      console.log(`➕ Added user ${socket.userId} to room ${roomId}`);
      console.log(`👥 Current members in room ${roomId} AFTER join:`, Array.from(roomMembers));
      
      // Notify existing members about new member
      socket.to(`room:${roomId}`).emit('webrtc:room-new-member', {
        roomId,
        userId: socket.userId
      });
      console.log(`📢 Notified ${existingMembers.length} existing members about new member ${socket.userId}`);
      console.log(`======================================\n`);
    });

    // Room-based offer
    socket.on('webrtc:room-offer', ({ roomId, toUserId, offer }: { roomId: number; toUserId: number; offer: any }) => {
      console.log(`\n========== WEBRTC OFFER ==========`);
      console.log(`📞 Offer from User ${socket.userId} to User ${toUserId} in room ${roomId}`);
      
      const targetSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === toUserId
      );
      console.log(`🎯 Found ${targetSockets.length} socket(s) for user ${toUserId}`);

      targetSockets.forEach(targetSocket => {
        targetSocket.emit('webrtc:room-offer', {
          roomId,
          fromUserId: socket.userId,
          offer
        });
        console.log(`✅ Forwarded offer to socket ${targetSocket.id}`);
      });
      console.log(`==================================\n`);
    });

    // Room-based answer
    socket.on('webrtc:room-answer', ({ roomId, toUserId, answer }: { roomId: number; toUserId: number; answer: any }) => {
      console.log(`\n========== WEBRTC ANSWER ==========`);
      console.log(`✅ Answer from User ${socket.userId} to User ${toUserId} in room ${roomId}`);
      
      const targetSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === toUserId
      );
      console.log(`🎯 Found ${targetSockets.length} socket(s) for user ${toUserId}`);

      targetSockets.forEach(targetSocket => {
        targetSocket.emit('webrtc:room-answer', {
          roomId,
          fromUserId: socket.userId,
          answer
        });
        console.log(`✅ Forwarded answer to socket ${targetSocket.id}`);
      });
      console.log(`===================================\n`);
    });

    // Room-based ICE candidate
    socket.on('webrtc:room-ice-candidate', ({ roomId, toUserId, candidate }: { roomId: number; toUserId: number; candidate: any }) => {
      console.log(`🧊 ICE candidate from User ${socket.userId} to User ${toUserId} in room ${roomId}`);
      
      const targetSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === toUserId
      );

      targetSockets.forEach(targetSocket => {
        targetSocket.emit('webrtc:room-ice-candidate', {
          roomId,
          fromUserId: socket.userId,
          candidate
        });
      });
      console.log(`✅ Forwarded ICE candidate to ${targetSockets.length} socket(s)`);
    });

    // Leave WebRTC room
    socket.on('webrtc:room-leave', (roomId: number) => {
      console.log(`🚪 User ${socket.userId} leaving WebRTC room ${roomId}`);
      
      const roomMembers = webrtcRooms.get(roomId);
      if (roomMembers) {
        roomMembers.delete(socket.userId!);
        
        // Notify others
        socket.to(`room:${roomId}`).emit('webrtc:room-member-left', {
          roomId,
          userId: socket.userId
        });
      }
    });

    // ========== LEGACY PEER-TO-PEER WEBRTC (Keep for backward compatibility) ==========
    
    // WebRTC Signaling Events
    // Offer: User A sends offer to User B
    socket.on('webrtc:offer', ({ targetUserId, offer }: { targetUserId: number; offer: any }) => {
      const targetSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === targetUserId
      );

      targetSockets.forEach(targetSocket => {
        targetSocket.emit('webrtc:offer', {
          fromUserId: socket.userId,
          offer
        });
      });
      console.log(`WebRTC offer sent from ${socket.userId} to ${targetUserId}`);
    });

    // Answer: User B responds to User A's offer
    socket.on('webrtc:answer', ({ targetUserId, answer }: { targetUserId: number; answer: any }) => {
      const targetSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === targetUserId
      );

      targetSockets.forEach(targetSocket => {
        targetSocket.emit('webrtc:answer', {
          fromUserId: socket.userId,
          answer
        });
      });
      console.log(`WebRTC answer sent from ${socket.userId} to ${targetUserId}`);
    });

    // ICE Candidate: Exchange network information
    socket.on('webrtc:ice-candidate', ({ targetUserId, candidate }: { targetUserId: number; candidate: any }) => {
      const targetSockets = Array.from(io.sockets.sockets.values()).filter(
        (s: any) => s.userId === targetUserId
      );

      targetSockets.forEach(targetSocket => {
        targetSocket.emit('webrtc:ice-candidate', {
          fromUserId: socket.userId,
          candidate
        });
      });
    });

    // Disconnect
    socket.on('disconnect', () => {
      console.log(`User ${socket.userId} disconnected`);

      // Notify all rooms this user was in
      const rooms = Array.from(socket.rooms).filter(room => room.startsWith('room:'));
      rooms.forEach(room => {
        socket.to(room).emit('room:user-left', {
          userId: socket.userId,
          socketId: socket.id
        });
      });
    });
  });

  console.log('✅ Socket.IO handlers initialized with database persistence (better-sqlite3)');
};