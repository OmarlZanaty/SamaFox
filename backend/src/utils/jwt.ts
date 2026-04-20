// src/utils/jwt.ts
import * as jwt from 'jsonwebtoken';

export type TokenPayload = { userId: number };

function requireEnvSecret(name: 'JWT_SECRET' | 'JWT_REFRESH_SECRET'): jwt.Secret {
  const value = process.env[name];
  if (!value || value.trim().length < 32) {
    throw new Error(`${name} is required and must be at least 32 characters`);
  }
  return value;
}

const accessSecret = (): jwt.Secret => requireEnvSecret('JWT_SECRET');
const refreshSecret = (): jwt.Secret => requireEnvSecret('JWT_REFRESH_SECRET');

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
