import express from 'express';
import prisma from '../utils/prisma';
import jwt from 'jsonwebtoken';
import { verifyAccessToken } from '../utils/jwt';

const router = express.Router();

function pickToken(resp: any): string | null {
  // common shapes:
  // { token: "..." }
  // { accessToken: "..." }
  // { data: { token: "..." } }
  // { data: { accessToken: "..." } }
  // { data: { jwt: "..." } }
  const t =
    resp?.token ||
    resp?.accessToken ||
    resp?.jwt ||
    resp?.data?.token ||
    resp?.data?.accessToken ||
    resp?.data?.jwt ||
    resp?.data?.data?.token ||
    resp?.data?.data?.accessToken;

  return typeof t === 'string' && t.length > 10 ? t : null;
}

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    if (!email || !password) {
      return res.status(400).json({ message: 'email/password required' });
    }

    // Call your existing auth login route (it knows how to validate password)
    const port = process.env.PORT || 3000;
    const base = process.env.INTERNAL_BASE_URL || `http://127.0.0.1:${port}`;

    const r = await fetch(`${base}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    const text = await r.text();
    let body: any = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = { raw: text }; }

    if (!r.ok) {
      const msg = body?.message || body?.error || `Login failed (HTTP ${r.status})`;
      return res.status(401).json({ message: msg });
    }

    const token = pickToken(body);
    if (!token) {
      return res.status(500).json({
        message: 'Auth login succeeded but token not found in response',
        debugKeys: Object.keys(body || {}),
      });
    }

    // decode to get userId (your JWT uses { userId })
    const decoded = jwt.decode(token) as any;
    const userId = Number(decoded?.userId || decoded?.id);
    if (!userId) {
      return res.status(500).json({ message: 'Token decoded but userId missing' });
    }

    // verify admin from prisma
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, isAdmin: true },
    });

    if (!user?.isAdmin) {
      return res.status(403).json({ message: 'Not admin' });
    }

    // ✅ set HttpOnly cookie
    res.cookie('access_token', token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: false, // set true when HTTPS
      maxAge: 7 * 24 * 60 * 60 * 1000,
    });

    return res.json({ success: true });
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
