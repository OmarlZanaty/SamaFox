// File: src/routes/user.routes.ts

import { Router } from 'express';
import {
  getMe,
  getUserById,
  updateProfile,
  updateGenderAndCountry,
  searchUsers,
  getUsersByCountry,
  followUser,
  unfollowUser,
  getFollowers,
  getFollowing,
  getMyBlocks,
  blockUser,
  unblockUser,
  deleteMyAccount,
  getUserBadges,
  updateDmPrivacy,
} from '../controllers/user.controller';
import { authMiddleware } from '../middlewares/auth.middleware';
import { FeatureError, isFeatureKey, listMyFeatures, setMyFeatureSwitch } from '../services/features.service';

const router = Router();

// me
router.get('/me', authMiddleware, getMe);
router.put('/me', authMiddleware, updateProfile);
router.put('/me/gender-country', authMiddleware, updateGenderAndCountry);
// قفل الرسائل الخاصة — public / friends / paid (+ price).
router.put('/me/dm-privacy', authMiddleware, updateDmPrivacy);
router.delete('/me', authMiddleware, deleteMyAccount);

// «منح المميزات» — what the admin granted me, and my own switch for features
// that have one (الدخول المخفي). Everything is re-checked server-side wherever
// the feature is used; these only read and flip the switch.
router.get('/me/features', authMiddleware, async (req: any, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.json({ success: true, data: await listMyFeatures(req.userId) });
  } catch (e) {
    console.error('[users.features]', e);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
});
router.put('/me/features/:key', authMiddleware, async (req: any, res) => {
  try {
    const key = String(req.params.key ?? '').toUpperCase();
    if (!isFeatureKey(key)) return res.status(404).json({ success: false, code: 'UNKNOWN_FEATURE', message: 'ميزة غير معروفة' });
    const data = await setMyFeatureSwitch(req.userId, key, Boolean(req.body?.on));
    return res.json({ success: true, data });
  } catch (e) {
    if (e instanceof FeatureError) return res.status(e.status).json({ success: false, code: e.code, message: e.message });
    console.error('[users.features.set]', e);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
});

// personal blacklist (#2 settings menu) — /me/blocks must stay above /:userId
router.get('/me/blocks', authMiddleware, getMyBlocks);
router.post('/:targetUserId/block', authMiddleware, blockUser);
router.delete('/:targetUserId/block', authMiddleware, unblockUser);

// search (BEFORE /:userId) — auth required; previously leaked coins/email/phone unauthenticated
router.get('/search', authMiddleware, searchUsers);
router.get('/country/:countryCode', getUsersByCountry);

// follow system
router.post('/:targetUserId/follow', authMiddleware, followUser);
router.post('/:targetUserId/unfollow', authMiddleware, unfollowUser);

// followers/following list
router.get('/:userId/followers', getFollowers);
router.get('/:userId/following', getFollowing);

// #28: badges row — distinct owned special items (frames/effects/themes)
router.get('/:userId/badges', getUserBadges);

// profile
router.get('/:userId', getUserById);

export default router;
