import { Request, Response, NextFunction, RequestHandler } from 'express';
import { verifyAccessToken } from '../utils/jwt';
import { getBanState, banMessage } from '../utils/banGuard';

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
  return next();
};

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