// File: src/routes/auth.routes.ts

import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import * as authController from '../controllers/auth.controller';
import { authMiddleware } from '../middlewares/auth.middleware';
import { deviceBanMiddleware } from '../middlewares/deviceBan.middleware';

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
router.post('/refresh', authLimiter, authController.refreshToken);
router.post('/facebook', deviceBanMiddleware, authController.facebookLogin);
router.get('/me', authMiddleware, authController.getCurrentUser);
router.post('/logout', authMiddleware, authController.logout);

export default router;
