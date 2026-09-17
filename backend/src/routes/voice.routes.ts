import { Router } from 'express';
import { AccessToken } from 'livekit-server-sdk';
import { authMiddleware } from '../middlewares/auth.middleware';
import prisma from '../utils/prisma';
import { readSettings } from '../controllers/settings.controller';

/**
 * Voice engine access — the SFU side of the room's audio.
 *
 * The original engine was a full mesh: every phone in a room opened a direct
 * WebRTC connection to every other phone, so a room of 20 meant 19 connections
 * and 19 outgoing audio copies per phone. It could not scale, and it did not.
 *
 * With LiveKit the phone opens ONE connection, to the server, and the server
 * forwards the audio. The app still asks this API for permission to enter a
 * voice room: it presents its normal JWT, and gets back a short-lived LiveKit
 * token scoped to exactly one room. The LiveKit API key and secret never leave
 * this process.
 *
 * Room naming: `room-<id>`, one LiveKit room per SamaFox room. LiveKit creates
 * it on first join and deletes it when the last participant leaves; nothing
 * here has to manage that.
 */
const router = Router();

const TOKEN_TTL = '6h';

/** Where the SFU lives, or null when the engine is not configured. */
async function livekitConfig() {
  const settings = await readSettings();
  const url = (settings.livekit_url ?? '').trim();
  const apiKey = (process.env.LIVEKIT_API_KEY ?? '').trim();
  const apiSecret = (process.env.LIVEKIT_API_SECRET ?? '').trim();
  if (!url || !apiKey || !apiSecret) return null;
  return { url, apiKey, apiSecret, engine: settings.voice_engine };
}

// POST /voice/token  { roomId }  →  { url, token, room }
//
// Authenticated: the LiveKit identity is the SamaFox user id, taken from the
// JWT and never from the body, so nobody can mint a token as someone else.
router.post('/token', authMiddleware, async (req, res) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const roomId = Number(req.body?.roomId);
    if (!Number.isInteger(roomId) || roomId <= 0) {
      return res.status(400).json({ success: false, message: 'roomId required' });
    }

    const cfg = await livekitConfig();
    if (!cfg) {
      // The app falls back to the mesh engine on this; it is not an error on
      // the device's side, only "not available here".
      return res.status(503).json({ success: false, message: 'voice engine not configured' });
    }

    const [room, user] = await Promise.all([
      prisma.room.findUnique({ where: { id: roomId }, select: { id: true, isActive: true } }),
      prisma.user.findUnique({ where: { id: userId }, select: { name: true } }),
    ]);
    if (!room?.isActive) {
      return res.status(404).json({ success: false, message: 'room not found' });
    }

    const at = new AccessToken(cfg.apiKey, cfg.apiSecret, {
      identity: String(userId),
      name: user?.name ?? `user-${userId}`,
      ttl: TOKEN_TTL,
    });
    // canPublish is granted to everyone in the room and the APP decides when
    // to publish (only while holding a seat), exactly as the mesh engine did.
    // Seat rules are enforced by the room's socket handlers; a client that
    // publishes without a seat is a rogue client either way, and the room
    // moderation tools (mute / remove) still reach it through the seat state.
    at.addGrant({
      room: `room-${roomId}`,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: false,
    });

    const token = await at.toJwt();
    return res.json({ success: true, url: cfg.url, token, room: `room-${roomId}` });
  } catch (e) {
    console.error('[voice.token]', e);
    return res.status(500).json({ success: false, message: 'Internal error' });
  }
});

export default router;
