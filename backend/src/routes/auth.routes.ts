// File: src/routes/auth.routes.ts

import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import * as authController from '../controllers/auth.controller';
import { authMiddleware } from '../middlewares/auth.middleware';
import { deviceBanMiddleware } from '../middlewares/deviceBan.middleware';
import { refreshIpLimiter, refreshTokenLimiter } from '../middlewares/refreshLimit';

const router = Router();

// ✅ FIX: rate limit brute-force on auth endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many attempts. Please try again in 15 minutes.' },
});

// Tighter limiter for login (most abuse-prone)
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many login attempts. Please try again in 15 minutes.' },
});

// F4 — deviceBanMiddleware guards every way IN, registration included: an
// account ban that a new signup defeats is not a ban.
router.post('/register', authLimiter, deviceBanMiddleware, authController.register);
router.post('/login', loginLimiter, deviceBanMiddleware, authController.login);
router.post('/google/mobile', authLimiter, deviceBanMiddleware, authController.googleLogin);
router.post('/refresh', refreshIpLimiter, refreshTokenLimiter, authController.refreshToken);
router.post('/facebook', deviceBanMiddleware, authController.facebookLogin);
router.get('/me', authMiddleware, authController.getCurrentUser);

// SPEC52 #37 — link a verified phone number to the current account.
const phoneRoute = (fn: (req: any) => Promise<unknown>) => async (req: any, res: any) => {
  try {
    return res.json({ success: true, data: await fn(req) });
  } catch (e: any) {
    if (e?.name === 'Error' && e?.status) return res.status(e.status).json({ success: false, code: e.code, message: e.message });
    console.error('[auth.phone]', e);
    return res.status(500).json({ success: false, message: 'تعذر إتمام العملية' });
  }
};
router.get('/phone', authMiddleware, phoneRoute(async (req) => (await import('../services/phoneLink.service')).linkedPhone(req.userId)));
router.post('/phone/send-otp', authMiddleware, authLimiter, phoneRoute(async (req) => (await import('../services/phoneLink.service')).sendPhoneOtp(req.userId, req.body?.phone)));
router.post('/phone/verify', authMiddleware, authLimiter, phoneRoute(async (req) => (await import('../services/phoneLink.service')).verifyPhoneOtp(req.userId, req.body?.phone, req.body?.code)));
router.post('/logout', authMiddleware, authController.logout);

export default router;
