import express from 'express';
import bcrypt from 'bcrypt';
import prisma from '../utils/prisma';
import { signAccessToken, verifyAccessToken } from '../utils/jwt';

const router = express.Router();

function pickToken(resp: any): string | null {
  const t =
    resp?.token ||
    resp?.accessToken ||
    resp?.jwt ||
    resp?.data?.token ||
    resp?.data?.accessToken ||
    resp?.data?.jwt;
  return typeof t === 'string' && t.length > 10 ? t : null;
}

async function loginViaPublicAuth(base: string, email: string, password: string) {
  const authRes = await fetch(`${base}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const text = await authRes.text();
  let body: any = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = null; }
  return { ok: authRes.ok, token: pickToken(body) };
}

const internalAuthBase = process.env.INTERNAL_API_BASE_URL?.trim();

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    if (!email || !password) {
      return res.status(400).json({ message: 'email/password required' });
    }
    const emailRaw = String(email).trim();
    const pass = String(password);
    const base = internalAuthBase;

    // Primary compatibility path: reuse existing /auth/login if available.
    if (base) {
      try {
        const publicAuth = await loginViaPublicAuth(base, emailRaw, pass);
        if (publicAuth.ok && publicAuth.token) {
          res.cookie('access_token', publicAuth.token, {
            httpOnly: true,
            sameSite: 'lax',
            secure: req.secure, // user-approved: site is HTTP-only, a secure cookie is never sent back so the whole dashboard 401s. Enable HTTPS to restore secure cookies.
            maxAge: 7 * 24 * 60 * 60 * 1000,
          });
          return res.json({ success: true });
        }
      } catch {
        // fallback to direct DB auth below
      }
    }

    let user: { id: number; isAdmin: boolean; passwordHash: string | null } | null = null;
    try {
      user =
        await prisma.user.findFirst({
          where: { email: emailRaw },
          select: { id: true, isAdmin: true, passwordHash: true },
        }) ||
        await prisma.user.findFirst({
          where: { email: emailRaw.toLowerCase() },
          select: { id: true, isAdmin: true, passwordHash: true },
        });
    } catch (userLookupError: any) {
      const message = String(userLookupError?.message || '');
      const missingPasswordHashColumn =
        message.includes('no such column') ||
        message.includes('Unknown column') ||
        (message.toLowerCase().includes('column') && message.toLowerCase().includes('does not exist')) ||
        message.includes('passwordHash');
      if (!missingPasswordHashColumn) throw userLookupError;

      try {
        const rows = await prisma.$queryRaw<Array<{ id: number; isAdmin: number; passwordHash: string | null }>>`
          SELECT id, "isAdmin" AS "isAdmin", "passwordHash" AS "passwordHash"
          FROM "users"
          WHERE LOWER(email) IN (LOWER(${emailRaw}), LOWER(${emailRaw.toLowerCase()}))
          LIMIT 1
        `;
        const row = rows[0];
        user = row ? { id: row.id, isAdmin: Number(row.isAdmin) === 1, passwordHash: row.passwordHash } : null;
      } catch {
        try {
          const rows = await prisma.$queryRaw<Array<{ id: number; isAdmin: number; passwordHash: string | null }>>`
            SELECT id, "isAdmin" AS "isAdmin", "password" AS "passwordHash"
            FROM "users"
            WHERE LOWER(email) IN (LOWER(${emailRaw}), LOWER(${emailRaw.toLowerCase()}))
            LIMIT 1
          `;
          const row = rows[0];
          user = row ? { id: row.id, isAdmin: Number(row.isAdmin) === 1, passwordHash: row.passwordHash } : null;
        } catch {
          try {
            const rows = await prisma.$queryRaw<Array<{ id: number; isAdmin: number; passwordHash: string | null }>>`
              SELECT id, isAdmin AS isAdmin, passwordHash AS passwordHash
              FROM users
              WHERE LOWER(email) IN (LOWER(${emailRaw}), LOWER(${emailRaw.toLowerCase()}))
              LIMIT 1
            `;
            const row = rows[0];
            user = row ? { id: row.id, isAdmin: Number(row.isAdmin) === 1, passwordHash: row.passwordHash } : null;
          } catch {
            try {
              const rows = await prisma.$queryRaw<Array<{ id: number; isAdmin: number; passwordHash: string | null }>>`
                SELECT id, isAdmin AS isAdmin, password AS passwordHash
                FROM users
                WHERE LOWER(email) IN (LOWER(${emailRaw}), LOWER(${emailRaw.toLowerCase()}))
                LIMIT 1
              `;
              const row = rows[0];
              user = row ? { id: row.id, isAdmin: Number(row.isAdmin) === 1, passwordHash: row.passwordHash } : null;
            } catch {
              user = null;
            }
          }
        }
      }
    }

    if (!user?.passwordHash) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const ok = await bcrypt.compare(pass, user.passwordHash);
    if (!ok) {
      // Compatibility fallback: ask existing auth endpoint for token shape variations.
      if (base) {
        try {
          const publicAuth = await loginViaPublicAuth(base, emailRaw, pass);
          if (publicAuth.ok && publicAuth.token) {
            const token = publicAuth.token;
            res.cookie('access_token', token, {
              httpOnly: true,
              sameSite: 'lax',
              secure: req.secure, // user-approved: site is HTTP-only, a secure cookie is never sent back so the whole dashboard 401s. Enable HTTPS to restore secure cookies.
              maxAge: 7 * 24 * 60 * 60 * 1000,
            });
            return res.json({ success: true });
          }
        } catch {
          // fall through to 401 below
        }
      }
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    if (!user.isAdmin) {
      return res.status(403).json({ success: false, message: 'Not admin' });
    }

    const token = signAccessToken({ userId: user.id });

    // ✅ set HttpOnly cookie
    res.cookie('access_token', token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: req.secure, // user-approved: site is HTTP-only, a secure cookie is never sent back so the whole dashboard 401s. Enable HTTPS to restore secure cookies.
      maxAge: 7 * 24 * 60 * 60 * 1000,
    });

    return res.json({ success: true, user: { id: user.id, isAdmin: true } });
  } catch (e) {
    console.error('admin-dashboard-auth login error', e);
    const detail = (e as any)?.message || 'Unknown';
    return res.status(500).json({ success: false, message: `Admin login failed: ${detail}`, error: detail });
  }
});

router.post('/logout', (_req, res) => {
  res.clearCookie('access_token');
  return res.json({ success: true });
});

router.get('/status', async (req, res) => {
  try {
    const token = req.cookies?.access_token as string | undefined;
    if (!token) return res.status(401).json({ success: false, message: 'Missing token' });

    const payload = verifyAccessToken(token);
    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
      select: { id: true, isAdmin: true },
    });

    if (!user) return res.status(401).json({ success: false, message: 'Unauthorized' });
    if (!user.isAdmin) return res.status(403).json({ success: false, message: 'Not admin' });

    return res.json({ success: true, user: { id: user.id, isAdmin: user.isAdmin } });
  } catch {
    return res.status(401).json({ success: false, message: 'Invalid token' });
  }
});

export default router;
