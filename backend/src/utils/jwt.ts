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

// Parse an expiresIn env value. An empty string (e.g. `JWT_EXPIRES_IN=` in
// .env) is NOT caught by `??`, and jwt.sign rejects it with "expiresIn should
// be a number of seconds or string...". Accept numeric seconds or a timespan
// string (1d/20h/30m/60s), otherwise fall back.
function parseExpiresIn(
  raw: string | undefined,
  fallback: string,
): jwt.SignOptions['expiresIn'] {
  const v = (raw ?? '').trim();
  if (!v) return fallback as jwt.SignOptions['expiresIn'];
  if (/^\d+$/.test(v)) return Number(v) as jwt.SignOptions['expiresIn'];
  if (/^\d+\s*(ms|s|m|h|d|w|y)$/i.test(v)) return v as jwt.SignOptions['expiresIn'];
  return fallback as jwt.SignOptions['expiresIn'];
}

const accessExpiresIn = parseExpiresIn(process.env.JWT_EXPIRES_IN, '1d');
const refreshExpiresIn = parseExpiresIn(process.env.JWT_REFRESH_EXPIRES_IN, '7d');

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
