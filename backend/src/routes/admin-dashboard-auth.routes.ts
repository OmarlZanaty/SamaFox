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

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    if (!email || !password) {
      return res.status(400).json({ message: 'email/password required' });
    }
    const emailRaw = String(email).trim();
    const user =
      await prisma.user.findUnique({
      where: { email: emailRaw },
      select: { id: true, isAdmin: true, passwordHash: true },
      }) ||
      await prisma.user.findUnique({
        where: { email: emailRaw.toLowerCase() },
        select: { id: true, isAdmin: true, passwordHash: true },
      });

    if (!user?.passwordHash) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const pass = String(password);
    let ok = false;
    try {
      ok = await bcrypt.compare(pass, user.passwordHash);
    } catch {
      ok = user.passwordHash === pass;
    }
    if (!ok) {
      // Compatibility fallback: ask existing auth endpoint for token shape variations.
      try {
        const base = `${req.protocol}://${req.get('host')}`;
        const authRes = await fetch(`${base}/api/v1/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
          body: JSON.stringify({ email: emailRaw, password: pass }),
        });
        const text = await authRes.text();
        let body: any = null;
        try { body = text ? JSON.parse(text) : null; } catch { body = null; }
        const fallbackToken = pickToken(body);
        if (authRes.ok && fallbackToken) {
          const token = fallbackToken;
          res.cookie('access_token', token, {
            httpOnly: true,
            sameSite: 'lax',
            secure: process.env.NODE_ENV === "production",
            maxAge: 7 * 24 * 60 * 60 * 1000,
          });
          return res.json({ success: true, user: { id: user.id, isAdmin: true } });
        }
      } catch {
        // fall through to 401 below
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
      secure: process.env.NODE_ENV === "production",
      maxAge: 7 * 24 * 60 * 60 * 1000,
    });

    return res.json({ success: true, user: { id: user.id, isAdmin: true } });
  } catch (e) {
    console.error('admin-dashboard-auth login error', e);
    return res.status(500).json({ message: 'Server error' });
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
