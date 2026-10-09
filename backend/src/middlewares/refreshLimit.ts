import crypto from 'crypto';
import type { Request } from 'express';
import rateLimit from 'express-rate-limit';

// Token refresh had the login limiter's budget: 20 per 15 minutes per IP.
// A refresh cannot be guessed (it needs a token signed by the server), and
// phones on one carrier share an address behind CGNAT, so a whole carrier
// could run out together — and builds up to 1.0.48 log the user out on the
// 429. Two ceilings instead: one per token (a client stuck in a loop), and a
// generous one per IP (a flood of made-up tokens).

const WINDOW_MS = 15 * 60 * 1000;

/** The limiter key for one refresh token; the token itself is never stored. */
export function refreshTokenKey(req: Pick<Request, 'body' | 'ip'>): string {
  const token = (req.body as { refreshToken?: unknown } | undefined)?.refreshToken;
  if (typeof token !== 'string' || token.length === 0) return `refresh-ip:${req.ip ?? 'unknown'}`;
  return `refresh-token:${crypto.createHash('sha256').update(token).digest('hex').slice(0, 32)}`;
}

const tooMany = {
  success: false,
  message: 'Too many attempts. Please try again in 15 minutes.',
};

export const refreshTokenLimiter = rateLimit({
  windowMs: WINDOW_MS,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => refreshTokenKey(req),
  message: tooMany,
});

export const refreshIpLimiter = rateLimit({
  windowMs: WINDOW_MS,
  max: 600,
  standardHeaders: true,
  legacyHeaders: false,
  message: tooMany,
});
