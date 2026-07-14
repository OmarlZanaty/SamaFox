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

// Coins each user received as gifts IN THIS ROOM over the last 24h.
// Returns { data: { "<userId>": <coins> } } for the seated users.
router.get('/:roomId/seat-earnings', optionalAuth, async (req, res) => {
  try {
    const roomId = Number(req.params.roomId);
    if (!roomId) return res.status(400).json({ success: false, message: 'Invalid roomId' });
    const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    // #4: honor the admin's reset point — counters show only gifts since the later
    // of (24h ago, contributionResetAt).
    const room = await prisma.room.findUnique({ where: { id: roomId }, select: { contributionResetAt: true } });
    const reset = room?.contributionResetAt;
    const since = reset && reset > dayAgo ? reset : dayAgo;
    const rows = await prisma.giftTransaction.groupBy({
      by: ['recipientId'],
      where: { roomId, createdAt: { gte: since } },
      _sum: { totalCoins: true },
    });
    const data: Record<string, number> = {};
    for (const r of rows) data[String(r.recipientId)] = r._sum.totalCoins ?? 0;
    return res.json({ success: true, data });
  } catch (e) {
    console.error('seat-earnings error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
});

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
    const rawLimit = Number(req.query.limit ?? 50);
    const rawOffset = Number(req.query.offset ?? 0);
    const limit = Math.min(100, Math.max(1, Number.isFinite(rawLimit) ? Math.floor(rawLimit) : 50));
    const offset = Math.max(0, Number.isFinite(rawOffset) ? Math.floor(rawOffset) : 0);

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
