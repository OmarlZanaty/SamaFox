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
} from '../controllers/user.controller';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

// me
router.get('/me', authMiddleware, getMe);
router.put('/me', authMiddleware, updateProfile);
router.put('/me/gender-country', authMiddleware, updateGenderAndCountry);
router.delete('/me', authMiddleware, deleteMyAccount);

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
