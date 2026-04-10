import * as jwt from 'jsonwebtoken';

export type TokenPayload = { userId: number };

const requiredSecret = (name: 'JWT_SECRET' | 'JWT_REFRESH_SECRET'): jwt.Secret => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} env variable is required`);
  }
  return value;
};

const accessExpiresIn: jwt.SignOptions['expiresIn'] =
  (process.env.JWT_EXPIRES_IN ?? '1d') as jwt.SignOptions['expiresIn'];

const refreshExpiresIn: jwt.SignOptions['expiresIn'] =
  (process.env.JWT_REFRESH_EXPIRES_IN ?? '7d') as jwt.SignOptions['expiresIn'];

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, requiredSecret('JWT_SECRET'), { expiresIn: accessExpiresIn });
}

export function signRefreshToken(payload: TokenPayload): string {
  return jwt.sign(payload, requiredSecret('JWT_REFRESH_SECRET'), { expiresIn: refreshExpiresIn });
}

export function verifyToken(token: string): TokenPayload {
  return jwt.verify(token, requiredSecret('JWT_SECRET')) as TokenPayload;
}

export function verifyRefreshToken(token: string): TokenPayload {
  return jwt.verify(token, requiredSecret('JWT_REFRESH_SECRET')) as TokenPayload;
}

export const signAccessToken = signToken;
export const verifyAccessToken = verifyToken;
export const signRefresh = signRefreshToken;
export const verifyRefresh = verifyRefreshToken;
