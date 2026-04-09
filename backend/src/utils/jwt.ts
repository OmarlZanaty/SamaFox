// src/utils/jwt.ts
import * as jwt from 'jsonwebtoken';

export type TokenPayload = { userId: number };

const accessSecret = (): jwt.Secret => process.env.JWT_SECRET ?? 'your-secret-key';
const refreshSecret = (): jwt.Secret =>
  process.env.JWT_REFRESH_SECRET ?? 'your-refresh-secret-key';

const accessExpiresIn: jwt.SignOptions['expiresIn'] =
  (process.env.JWT_EXPIRES_IN ?? '1d') as jwt.SignOptions['expiresIn'];

const refreshExpiresIn: jwt.SignOptions['expiresIn'] =
  (process.env.JWT_REFRESH_EXPIRES_IN ?? '7d') as jwt.SignOptions['expiresIn'];

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, accessSecret(), { expiresIn: accessExpiresIn });
}

export function signRefreshToken(payload: TokenPayload): string {
  return jwt.sign(payload, refreshSecret(), { expiresIn: refreshExpiresIn });
}

export function verifyToken(token: string): TokenPayload {
  return jwt.verify(token, accessSecret()) as TokenPayload;
}

export function verifyRefreshToken(token: string): TokenPayload {
  return jwt.verify(token, refreshSecret()) as TokenPayload;
}

// Backwards-compatible aliases (old code expects these names)
export const signAccessToken = signToken;
export const verifyAccessToken = verifyToken;

export const signRefresh = signRefreshToken;
export const verifyRefresh = verifyRefreshToken;