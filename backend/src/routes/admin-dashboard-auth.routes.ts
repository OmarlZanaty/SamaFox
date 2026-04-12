import express from 'express';
import bcrypt from 'bcrypt';
import prisma from '../utils/prisma';
import { signAccessToken, verifyAccessToken } from '../utils/jwt';

const router = express.Router();

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body ?? {};
    if (!email || !password) {
      return res.status(400).json({ message: 'email/password required' });
    }
    const user = await prisma.user.findUnique({
      where: { email: String(email).toLowerCase() },
      select: { id: true, isAdmin: true, passwordHash: true },
    });

    if (!user?.passwordHash) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const ok = await bcrypt.compare(String(password), user.passwordHash);
    if (!ok) {
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
