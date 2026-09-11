import { Request, Response, NextFunction, RequestHandler } from 'express';
import { verifyAccessToken } from '../utils/jwt';
import { getBanState, banMessage } from '../utils/banGuard';
import prisma from '../utils/prisma';
import { clientDeviceId, clientIp } from './deviceBan.middleware';

// ✅ Extend Express.Request globally (NO req.user, no conflicts)
declare global {
  namespace Express {
    interface Request {
      userId?: number;
      authUser?: { id: number };
    }
  }
}

function extractToken(req: Request): string | null {
  const h = req.headers.authorization;
  if (h && h.startsWith('Bearer ')) return h.slice('Bearer '.length).trim();

  const c1 = (req as any).cookies?.access_token as string | undefined;
  if (c1 && c1.length > 10) return c1;

  const raw = req.headers.cookie || '';
  const match = raw.match(/(?:^|;\s*)access_token=([^;]+)/);
  if (match?.[1] && match[1].length > 10) return match[1];

  return null;
}

export const authMiddleware: RequestHandler = async (req: Request, res: Response, next: NextFunction) => {
  let payload: { userId: number };
  try {
    const token = extractToken(req);
    if (!token) return res.status(401).json({ success: false, message: 'Missing token' });

    payload = verifyAccessToken(token);
  } catch {
    return res.status(401).json({ success: false, message: 'Invalid token' });
  }

  // A valid token used to be enough, so banning someone did nothing until
  // their token expired — and the refresh endpoint kept minting new ones, so
  // in practice never. Every authenticated request now checks the ban.
  const ban = await getBanState(payload.userId);
  if (ban.banned) {
    return res.status(403).json({
      success: false,
      code: 'BANNED',
      message: banMessage(ban),
      banExpiresAt: ban.expiresAt,
    });
  }

  req.userId = payload.userId;
  req.authUser = { id: payload.userId };

  // ✅ add this line for old controllers that expect req.user.id
  (req as any).user = { id: payload.userId };

  // F4 — note where this account is being used from. Fire-and-forget and
  // throttled: the response must not wait on it, and a failure must not cost
  // anyone their request.
  void recordLastSeen(payload.userId, clientDeviceId(req), clientIp(req));

  return next();
};

/**
 * F4 — the device-ban form asks for a device id, and until now nothing in the
 * system ever showed one: the admin was expected to invent it. Every
 * authenticated request carries the header the app now sends, so this is where
 * the association between account and handset gets recorded.
 *
 * At most one write per user per hour, tracked in memory. A busy user would
 * otherwise generate an UPDATE per request, which buys nothing — this is a
 * forensic breadcrumb, not a presence system. The map is bounded by clearing
 * it whole once it grows past a few thousand entries; losing it only means the
 * next request writes again.
 */
const lastSeenWrites = new Map<number, number>();
const LAST_SEEN_INTERVAL_MS = 60 * 60 * 1000;

async function recordLastSeen(
  userId: number,
  deviceId: string | null,
  ip: string | null,
): Promise<void> {
  if (!deviceId && !ip) return;
  const now = Date.now();
  const previous = lastSeenWrites.get(userId);
  if (previous && now - previous < LAST_SEEN_INTERVAL_MS) return;
  if (lastSeenWrites.size > 5000) lastSeenWrites.clear();
  lastSeenWrites.set(userId, now);

  try {
    await (prisma as any).user.update({
      where: { id: userId },
      data: {
        ...(deviceId ? { lastDeviceId: deviceId } : {}),
        ...(ip ? { lastIp: ip } : {}),
        lastSeenAt: new Date(now),
      },
    });
  } catch (e) {
    // Never surfaced: this is a breadcrumb, and a deleted user or a migration
    // that has not run yet must not break authentication for everyone.
    console.warn('[auth] last-seen write failed:', (e as Error).message);
  }
}

export const optionalAuth: RequestHandler = (req: Request, _res: Response, next: NextFunction) => {
  try {
    const token = extractToken(req);
    if (!token) return next();

    const payload = verifyAccessToken(token);
    req.userId = payload.userId;
    req.authUser = { id: payload.userId };

    // ✅ add this line for old controllers that expect req.user.id
    (req as any).user = { id: payload.userId };
    return next();
  } catch {
    return next();
  }
};

export const authenticate = authMiddleware;
export const requireAuth = authMiddleware;