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
} from '../controllers/user.controller';
import { authMiddleware } from '../middlewares/auth.middleware';

const router = Router();

// me
router.get('/me', authMiddleware, getMe);
router.put('/me', authMiddleware, updateProfile);
router.put('/me/gender-country', authMiddleware, updateGenderAndCountry);

// search (BEFORE /:userId)
router.get('/search', searchUsers);
router.get('/country/:countryCode', getUsersByCountry);

// follow system
router.post('/:targetUserId/follow', authMiddleware, followUser);
router.post('/:targetUserId/unfollow', authMiddleware, unfollowUser);

// followers/following list
router.get('/:userId/followers', getFollowers);
router.get('/:userId/following', getFollowing);

// profile
router.get('/:userId', getUserById);

export default router;
