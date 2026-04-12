// File: src/controllers/auth.controller.ts

import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { OAuth2Client } from 'google-auth-library';
import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';

const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

type JwtPayload = { userId: number };

interface RegisterRequest {
  name: string;
  email: string;
  password: string;
  gender?: string;
  countryCode?: string;
  country?: string;
  phone?: string;
}

interface LoginRequest {
  email: string;
  password: string;
}

interface GoogleLoginRequest {
  idToken: string;
}

if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET env variable is required');
if (!process.env.JWT_REFRESH_SECRET) throw new Error('JWT_REFRESH_SECRET env variable is required');

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET;

const generateTokens = (userId: number) => {
  const accessToken = jwt.sign({ userId } satisfies JwtPayload, JWT_SECRET, { expiresIn: '24h' });
  const refreshToken = jwt.sign({ userId } satisfies JwtPayload, JWT_REFRESH_SECRET, { expiresIn: '7d' });
  return { accessToken, refreshToken };
};

const isValidGender = (gender?: string) => {
  if (!gender) return true;
  return ['male', 'female', 'other'].includes(gender.toLowerCase());
};

const formatUserResponse = (user: any) => {
  const { passwordHash, ...safe } = user;
  return safe;
};

async function createUserWithDisplayId(
  tx: Prisma.TransactionClient,
  userData: Omit<Prisma.UserCreateInput, 'displayId'>,
) {
  const seq = await tx.userIdSequence.upsert({
    where: { id: 1 },
    update: {},
    create: { id: 1, nextId: 10000 },
  });

  let candidate = seq.nextId;
  for (let attempts = 0; attempts < 200; attempts++) {
    const taken = await tx.user.findUnique({ where: { displayId: candidate } });
    if (!taken) break;
    candidate++;
  }

  await tx.userIdSequence.update({
    where: { id: 1 },
    data: { nextId: candidate + 1 },
  });

  return tx.user.create({ data: { ...userData, displayId: candidate } });
}

// ------------------------------------
// Register (email + password)
// ------------------------------------
export const register = async (req: Request, res: Response) => {
  try {
    const { name, email, password, gender, countryCode, country, phone } = req.body as RegisterRequest;

    if (!name || !email || !password) {
      return res.status(400).json({ success: false, message: 'name, email, password are required' });
    }

    if (!isValidGender(gender)) {
      return res.status(400).json({ success: false, message: 'Invalid gender' });
    }

    const exists = await prisma.user.findUnique({ where: { email } });
    if (exists) return res.status(409).json({ success: false, message: 'Email already registered' });

    const passwordHash = await bcrypt.hash(password, 10);

    const user = await prisma.$transaction(async (tx) => {
      return createUserWithDisplayId(tx, {
        name,
        email,
        phone: phone || null,
        passwordHash,
        gender: gender?.toLowerCase() || null,
        countryCode: countryCode?.toUpperCase() || null,
        country: country || null,
        isVerified: false,
      });
    });

    const { accessToken, refreshToken } = generateTokens(user.id);

    return res.status(201).json({
      success: true,
      message: 'Registered',
      accessToken,
      refreshToken,
      user: formatUserResponse(user),
    });
  } catch (e: any) {
    console.error('register error:', e);
    return res.status(500).json({ success: false, message: 'Registration failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// Login (email + password)
// ------------------------------------
export const login = async (req: Request, res: Response) => {
  try {
    const { email, password } = req.body as LoginRequest;
    if (!email || !password) return res.status(400).json({ success: false, message: 'email and password required' });

    let user: any = null;
    try {
      user = await prisma.user.findUnique({ where: { email } });
    } catch (userLookupError: any) {
      const message = String(userLookupError?.message || '');
      const missingPasswordHashColumn =
        message.includes('no such column') ||
        message.includes('Unknown column') ||
        message.includes('passwordHash');

      if (!missingPasswordHashColumn) {
        throw userLookupError;
      }

      const columns = await prisma.$queryRaw<Array<{ name: string }>>`PRAGMA table_info(users)`;
      const columnNames = new Set(columns.map((c) => String(c.name)));
      const passwordColumn = columnNames.has('passwordHash')
        ? 'passwordHash'
        : (columnNames.has('password') ? 'password' : null);

      if (!passwordColumn) {
        return res.status(401).json({ success: false, message: 'Invalid email or password' });
      }

      // Backward compatibility for older schemas that still store plaintext `password`.
      const rawRows = await prisma.$queryRawUnsafe<Array<{
        id: number;
        passwordHash: string | null;
      }>>(
        `SELECT id, ${passwordColumn} AS passwordHash FROM users WHERE email = ? LIMIT 1`,
        email,
      );
      user = rawRows[0] ?? null;
    }
    if (!user || !user.passwordHash) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    // Keep raw query for ban fields to remain compatible with stale generated Prisma client types.
    // Also tolerate environments where the ban migration has not been applied yet.
    try {
      const bannedRows = await prisma.$queryRaw<Array<{ isBanned: number; banReason: string | null }>>`
        SELECT isBanned, banReason FROM users WHERE id = ${user.id} LIMIT 1
      `;
      const banned = bannedRows[0];
      if (banned && Number(banned.isBanned) === 1) {
        return res.status(403).json({ success: false, message: banned.banReason || 'User is banned' });
      }
    } catch (banCheckError: any) {
      const message = String(banCheckError?.message || '');
      const missingColumn =
        message.includes('no such column') ||
        message.includes('Unknown column') ||
        message.includes('isBanned');

      if (!missingColumn) {
        throw banCheckError;
      }
    }

    let ok = false;
    try {
      ok = await bcrypt.compare(password, user.passwordHash);
    } catch {
      // Legacy compatibility: tolerate plaintext stored passwords
      ok = user.passwordHash === password;
    }
    if (!ok) return res.status(401).json({ success: false, message: 'Invalid email or password' });

    try {
      await prisma.user.update({
        where: { id: user.id },
        data: { lastLoginAt: new Date() },
      });
    } catch (updateError: any) {
      const message = String(updateError?.message || '');
      const missingLastLoginColumn =
        message.includes('no such column') ||
        message.includes('Unknown column') ||
        message.includes('lastLoginAt');
      if (!missingLastLoginColumn) {
        throw updateError;
      }
    }

    const { accessToken, refreshToken } = generateTokens(user.id);

    return res.status(200).json({
      success: true,
      message: 'Login successful',
      accessToken,
      refreshToken,
      user: formatUserResponse(user),
    });
  } catch (e: any) {
    console.error('login error:', e);
    return res.status(500).json({ success: false, message: 'Login failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// Google login (mobile)
// ------------------------------------
export const googleLogin = async (req: Request, res: Response) => {
  try {
    const { idToken } = req.body as GoogleLoginRequest;
    if (!idToken) return res.status(400).json({ success: false, message: 'idToken required' });

    const ticket = await googleClient.verifyIdToken({ idToken, audience: process.env.GOOGLE_CLIENT_ID });
    const payload = ticket.getPayload();

    if (!payload?.email) return res.status(400).json({ success: false, message: 'Invalid Google token' });

    const email = payload.email;
    const name = payload.name || 'Google User';
    const picture = payload.picture || null;
    const googleSub = payload.sub || null;

    let user = await prisma.user.findUnique({ where: { email } });

    if (!user) {
      user = await prisma.$transaction(async (tx) => {
        return createUserWithDisplayId(tx, {
          email,
          name,
          avatarUrl: picture,
          googleId: googleSub,
          isVerified: true,
          lastLoginAt: new Date(),
        });
      });
    } else {
      user = await prisma.user.update({
        where: { id: user.id },
        data: {
          avatarUrl: user.avatarUrl || picture,
          googleId: user.googleId || googleSub,
          isVerified: true,
          lastLoginAt: new Date(),
        },
      });
    }

    const { accessToken, refreshToken } = generateTokens(user.id);

    return res.status(200).json({
      success: true,
      message: 'Google login successful',
      accessToken,
      refreshToken,
      user: formatUserResponse(user),
    });
  } catch (e: any) {
    console.error('googleLogin error:', e);
    return res.status(500).json({ success: false, message: 'Google login failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// Refresh token
// ------------------------------------
export const refreshToken = async (req: Request, res: Response) => {
  try {
    const { refreshToken: token } = req.body as { refreshToken?: string };
    if (!token) return res.status(400).json({ success: false, message: 'refreshToken required' });

    const decoded = jwt.verify(token, JWT_REFRESH_SECRET) as JwtPayload;

    const user = await prisma.user.findUnique({ where: { id: decoded.userId } });
    if (!user) return res.status(401).json({ success: false, message: 'User not found' });

    const { accessToken, refreshToken: newRefresh } = generateTokens(user.id);

    return res.status(200).json({
      success: true,
      message: 'Token refreshed',
      accessToken,
      refreshToken: newRefresh,
      user: formatUserResponse(user),
    });
  } catch (e: any) {
    return res.status(401).json({ success: false, message: 'Invalid refresh token', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// Me
// ------------------------------------
export const getCurrentUser = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    return res.status(200).json({ success: true, user: formatUserResponse(user) });
  } catch (e: any) {
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

export const logout = async (_req: Request, res: Response) => {
  return res.status(200).json({ success: true, message: 'Logout successful' });
};
