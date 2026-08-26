// File: src/controllers/auth.controller.ts

import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { OAuth2Client } from 'google-auth-library';
import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { nextDisplayId } from '../utils/displayId';
import { assertNotBanned, banMessage, invalidateBanCache } from '../utils/banGuard';
import { grantAutoItemsToUser } from '../services/auto-grant.service';

const googleClient = new OAuth2Client();

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

const DEFAULT_GOOGLE_SERVER_CLIENT_ID = '62771458278-73dh3jp1t12udcs1gp1e6atuga6ie5lg.apps.googleusercontent.com';

const isConfiguredGoogleClientId = (value?: string): value is string => {
  if (!value) return false;
  const trimmed = value.trim();
  if (!trimmed) return false;

  const normalized = trimmed.toLowerCase();
  if (normalized.includes('your-google-client-id') || normalized.startsWith('your-google-')) return false;

  return true;
};


const getGoogleAudiences = (): string[] => {
  const ids = [
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_WEB_CLIENT_ID,
    process.env.GOOGLE_ANDROID_CLIENT_ID,
    process.env.GOOGLE_IOS_CLIENT_ID,
    process.env.GOOGLE_SERVER_CLIENT_ID,
  ].filter(isConfiguredGoogleClientId);

  if (ids.length > 0) return [...new Set(ids)];

  // Development-safe fallback to avoid broken auth when env is accidentally left as placeholder values.
  return [DEFAULT_GOOGLE_SERVER_CLIENT_ID];
};


const getTokenAudience = (idToken: string): string | null => {
  try {
    const parts = idToken.split('.');
    if (parts.length < 2) return null;

    const payloadPart = parts[1];
    if (!payloadPart) return null;

    const payload = JSON.parse(Buffer.from(payloadPart, 'base64url').toString('utf8')) as { aud?: string };
    return typeof payload.aud === 'string' ? payload.aud : null;
  } catch {
    return null;
  }
};

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
  const displayId = await nextDisplayId(tx); // 6-digit, unique
  const user = await tx.user.create({ data: { ...userData, displayId } });
  // منتجات مُنحت لجميع المستخدمين تصل الحساب الجديد فوراً. لا نُفشل التسجيل
  // إن تعذّر ذلك — المنتج ثانوي بالنسبة لإنشاء الحساب.
  try {
    await grantAutoItemsToUser(user.id, tx);
  } catch (e) {
    console.warn('auto-grant on register failed:', e);
  }
  return user;
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
    return res.status(500).json({ success: false, message: 'Registration failed' });
  }
};

// ------------------------------------
// Facebook login (mobile)
// ------------------------------------
// ------------------------------------
// Facebook login (mobile)
// ------------------------------------
interface FacebookData {
  id: string;
  name?: string;
  email?: string;
  picture?: {
    data?: {
      url?: string;
    };
  };
  error?: any;
}

export const facebookLogin = async (req: Request, res: Response) => {
  const { facebookToken } = req.body;

  try {
    if (!facebookToken) return res.status(400).json({ success: false, message: 'facebookToken required' });

    // Verify token with Facebook Graph API
    const fbResponse = await fetch(`https://graph.facebook.com/me?fields=id,name,email,picture&access_token=${facebookToken}` );
    const fbData = (await fbResponse.json()) as FacebookData;

    if (!fbData || fbData.error) {
      return res.status(400).json({ success: false, message: 'Invalid Facebook token' });
    }

    const { email, name, id: fbId } = fbData;
    const picture = fbData.picture?.data?.url || null;

    // Use email as unique identifier, or fallback to facebook ID if email is not provided
    const userEmail = email || `${fbId}@facebook.com`;

    let user = await prisma.user.findUnique({ where: { email: userEmail } });

    if (!user) {
      user = await prisma.$transaction(async (tx) => {
        return createUserWithDisplayId(tx, {
          name: name || 'Facebook User',
          email: userEmail,
          // Note: If 'avatarUrl' caused an error, check your Prisma schema.
          // It's likely called 'avatarUrl' or similar.
          // I'm using 'avatarUrl' here, but change it to the correct field name from your User model.
          avatarUrl: picture,
          isVerified: true,
        });
      });
    }

    // Social sign-in bypassed the ban entirely — a banned user just tapped
    // "continue with Facebook" and was back in.
    const fbBan = await assertNotBanned(user.id);
    if (fbBan) {
      return res.status(403).json({
        success: false,
        code: 'BANNED',
        message: banMessage(fbBan),
        banExpiresAt: fbBan.expiresAt,
      });
    }

    const { accessToken, refreshToken } = generateTokens(user.id);

    return res.status(200).json({
      success: true,
      message: 'Facebook login successful',
      accessToken,
      refreshToken,
      user: formatUserResponse(user),
    });
  } catch (e: any) {
    console.error('facebookLogin error:', e);
    return res.status(500).json({ success: false, message: 'Facebook login failed' });
  }
};



// ------------------------------------
// Login (email + password)
// ------------------------------------
export const login = async (req: Request, res: Response) => {
  try {
    const { email: rawEmail, password } = req.body as LoginRequest;
    // Trim stray whitespace/tabs so a leading tab from a keyboard/autofill
    // can't cause a false "invalid email or password".
    const email = typeof rawEmail === 'string' ? rawEmail.trim() : rawEmail;
    if (!email || !password) return res.status(400).json({ success: false, message: 'email and password required' });

    let user: any = null;
    try {
      user = await prisma.user.findUnique({ where: { email } });
    } catch (userLookupError: any) {
      const message = String(userLookupError?.message || '');
      const missingPasswordHashColumn =
        message.includes('no such column') ||
        message.includes('Unknown column') ||
        (message.toLowerCase().includes('column') && message.toLowerCase().includes('does not exist')) ||
        message.includes('passwordHash');

      if (!missingPasswordHashColumn) {
        throw userLookupError;
      }

      try {
        const rows = await prisma.$queryRaw<Array<{ id: number; passwordHash: string | null }>>`
          SELECT id, "passwordHash" AS "passwordHash" FROM "users" WHERE LOWER(email) = LOWER(${email}) LIMIT 1
        `;
        user = rows[0] ?? null;
      } catch {
        try {
          const rows = await prisma.$queryRaw<Array<{ id: number; passwordHash: string | null }>>`
            SELECT id, "password" AS "passwordHash" FROM "users" WHERE LOWER(email) = LOWER(${email}) LIMIT 1
          `;
          user = rows[0] ?? null;
        } catch {
          try {
            const rows = await prisma.$queryRaw<Array<{ id: number; passwordHash: string | null }>>`
              SELECT id, passwordHash AS passwordHash FROM users WHERE LOWER(email) = LOWER(${email}) LIMIT 1
            `;
            user = rows[0] ?? null;
          } catch {
            try {
              const rows = await prisma.$queryRaw<Array<{ id: number; passwordHash: string | null }>>`
                SELECT id, password AS passwordHash FROM users WHERE LOWER(email) = LOWER(${email}) LIMIT 1
              `;
              user = rows[0] ?? null;
            } catch {
              user = null;
            }
          }
        }
      }
    }
    if (!user || !user.passwordHash) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    // Ban check — shared with the refresh endpoint, the social logins, the
    // auth middleware and the socket handshake, so all five agree and timed
    // bans expire in exactly one place.
    const ban = await assertNotBanned(user.id);
    if (ban) {
      return res.status(403).json({
        success: false,
        code: 'BANNED',
        message: banMessage(ban),
        banExpiresAt: ban.expiresAt,
      });
    }

    const ok = await bcrypt.compare(password, user.passwordHash);
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
    return res.status(500).json({ success: false, message: 'Login failed' });
  }
};

// ------------------------------------
// Google login (mobile)
// ------------------------------------
export const googleLogin = async (req: Request, res: Response) => {
  const { idToken } = req.body as GoogleLoginRequest;

  try {
    if (!idToken) return res.status(400).json({ success: false, message: 'idToken required' });

    const audiences = getGoogleAudiences();
    if (audiences.length === 0) {
      return res.status(500).json({
        success: false,
        message: 'Google auth is not configured',
        error: 'Missing valid GOOGLE_CLIENT_ID / GOOGLE_WEB_CLIENT_ID / GOOGLE_ANDROID_CLIENT_ID / GOOGLE_IOS_CLIENT_ID / GOOGLE_SERVER_CLIENT_ID',
      });
    }

    const ticket = await googleClient.verifyIdToken({ idToken, audience: audiences });
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

    const googleBan = await assertNotBanned(user.id);
    if (googleBan) {
      return res.status(403).json({
        success: false,
        code: 'BANNED',
        message: banMessage(googleBan),
        banExpiresAt: googleBan.expiresAt,
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
    const errorMessage = String(e?.message || 'Unknown');
    const invalidAudience =
      errorMessage.includes('Wrong recipient') ||
      errorMessage.includes('payload audience') ||
      errorMessage.includes('requiredAudience');

    if (invalidAudience) {
      const tokenAudience = getTokenAudience(idToken);
      const allowedAudiences = getGoogleAudiences();

      return res.status(401).json({
        success: false,
        message: 'Google token audience mismatch',
        error: errorMessage,
        details: {
          tokenAudience,
          allowedAudiences,
        },
      });
    }

    console.error('googleLogin error:', errorMessage);
    return res.status(500).json({ success: false, message: 'Google login failed' });
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

    // Without this the ban was effectively unenforceable: refresh tokens last
    // 7 days and roll over on every use, so a banned client just kept minting
    // fresh access tokens and never noticed.
    const ban = await assertNotBanned(user.id);
    if (ban) {
      return res.status(403).json({
        success: false,
        code: 'BANNED',
        message: banMessage(ban),
        banExpiresAt: ban.expiresAt,
      });
    }

    const { accessToken, refreshToken: newRefresh } = generateTokens(user.id);

    return res.status(200).json({
      success: true,
      message: 'Token refreshed',
      accessToken,
      refreshToken: newRefresh,
      user: formatUserResponse(user),
    });
  } catch (e: any) {
    console.error('refreshToken error:', e);
    return res.status(401).json({ success: false, message: 'Invalid refresh token' });
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
    console.error('getCurrentUser error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};

export const logout = async (_req: Request, res: Response) => {
  return res.status(200).json({ success: true, message: 'Logout successful' });
};
