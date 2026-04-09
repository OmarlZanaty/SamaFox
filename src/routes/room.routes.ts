import { Router } from 'express';
import {
  getRooms,
  getRoomById,
  createRoom,
  updateRoom,
  deleteRoom,
  joinRoom,
  leaveRoom
} from '../controllers/room.controller';
import { authMiddleware, optionalAuth } from '../middlewares/auth.middleware';
import prisma from '../utils/prisma';

const router = Router();

/* ===========================
   ROOMS LISTING & DETAILS
   =========================== */

router.get('/', optionalAuth, getRooms);
router.get('/:roomId', optionalAuth, getRoomById);

/* ===========================
   ROOM LIFECYCLE (AUTH ONLY)
   =========================== */

router.post('/', authMiddleware, createRoom);
router.patch('/:roomId', authMiddleware, updateRoom);
router.delete('/:roomId', authMiddleware, deleteRoom);

/* ===========================
   ROOM MEMBERSHIP
   =========================== */

router.post('/:roomId/join', authMiddleware, joinRoom);
router.post('/:roomId/leave', authMiddleware, leaveRoom);

/* ===========================
   ROOM MESSAGES (HISTORY)
   =========================== */

router.get('/:roomId/messages', authMiddleware, async (req, res) => {
  try {
    const roomId = Number(req.params.roomId);
    const limit = Number(req.query.limit ?? 50);
    const offset = Number(req.query.offset ?? 0);

    if (isNaN(roomId)) {
      return res.status(400).json({ error: 'Invalid roomId' });
    }

    console.log(
      `📜 Fetching messages for room ${roomId}, limit=${limit}, offset=${offset}`
    );

    const messages = await prisma.roomMessage.findMany({
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
  } catch (error) {
    console.error('❌ Error fetching room messages:', error);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

export default router;
