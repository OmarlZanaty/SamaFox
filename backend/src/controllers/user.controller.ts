// File: src/controllers/user.controller.ts

import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { firstStr } from '../utils/http';
interface UpdateProfileRequest {
  name?: string;
  bio?: string;
  gender?: string;
  countryCode?: string;
  country?: string;
  avatarUrl?: string;
    avatarFrameUrl?: string; // 🔥 ADD THIS
  phone?: string;
}

const isValidGender = (gender?: string): boolean => {
  if (!gender) return true;
  return ['male', 'female', 'other'].includes(gender.toLowerCase());
};

const formatUserResponse = (user: any) => {
  const { passwordHash, ...safe } = user;
  return safe;
};

// ------------------------------------
// GET /users/me
// ------------------------------------
export const getMe = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { achievements: true },
    });

    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const [followerCount, followingCount] = await Promise.all([
      prisma.follow.count({ where: { followingId: userId, status: 'ACCEPTED' } }),
      prisma.follow.count({ where: { followerId: userId, status: 'ACCEPTED' } }),
    ]);

    return res.status(200).json({
      success: true,
      user: { ...formatUserResponse(user), followerCount, followingCount, followersCount: followerCount },
    });
  } catch (e: any) {
    console.error('getMe error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// GET /users/:userId
// ------------------------------------
export const getUserById = async (req: Request, res: Response) => {
  try {
    const userIdStr = req.params.userId;
    const userId = Number(userIdStr);
    if (!userId || userId <= 0) return res.status(400).json({ success: false, message: 'Valid userId required' });

    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: { achievements: true },
    });

    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const [followerCount, followingCount] = await Promise.all([
      prisma.follow.count({ where: { followingId: userId, status: 'ACCEPTED' } }),
      prisma.follow.count({ where: { followerId: userId, status: 'ACCEPTED' } }),
    ]);

    return res.status(200).json({
      success: true,
      user: { ...formatUserResponse(user), followerCount, followingCount, followersCount: followerCount },
    });
  } catch (e: any) {
    console.error('getUserById error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// PUT /users/me
// ------------------------------------
export const updateProfile = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { name, bio, gender, countryCode, country, avatarUrl, phone, avatarFrameUrl } = req.body as UpdateProfileRequest;

    

    if (!isValidGender(gender)) {
      return res.status(400).json({ success: false, message: 'Invalid gender' });
    }

    const data: any = {};
    if (name) data.name = name;
    if (bio !== undefined) data.bio = bio;
    if (gender) data.gender = gender.toLowerCase();
    if (countryCode) data.countryCode = countryCode.toUpperCase();
    if (country !== undefined) data.country = country;
    if (avatarUrl) data.avatarUrl = avatarUrl;
    if (phone) data.phone = phone;
    if (avatarFrameUrl !== undefined) data.avatarFrameUrl = avatarFrameUrl;
    const user = await prisma.user.update({ where: { id: userId }, data });

    return res.status(200).json({ success: true, message: 'Profile updated', user: formatUserResponse(user) });
  } catch (e: any) {
    console.error('updateProfile error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// PUT /users/me/gender-country
// ------------------------------------
export const updateGenderAndCountry = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const { gender, countryCode, country } = req.body as UpdateProfileRequest;

    if (!isValidGender(gender)) return res.status(400).json({ success: false, message: 'Invalid gender' });

    const user = await prisma.user.update({
      where: { id: userId },
      data: {
        gender: gender ? gender.toLowerCase() : undefined,
        countryCode: countryCode ? countryCode.toUpperCase() : undefined,
        country: country !== undefined ? country : undefined,
      },
    });

    return res.status(200).json({ success: true, message: 'Updated', user: formatUserResponse(user) });
  } catch (e: any) {
    console.error('updateGenderAndCountry error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// GET /users/search?query=...
// ------------------------------------
export const searchUsers = async (req: Request, res: Response) => {
  try {
    const q = req.query.query;
    if (!q || typeof q !== 'string') return res.status(400).json({ success: false, message: 'query is required' });

    // SQLite Prisma doesn't support `mode: insensitive`
    const users = await prisma.user.findMany({
      where: {
        OR: [{ name: { contains: q } }, { email: { contains: q } }],
      },
      take: 20,
    });

    return res.status(200).json({ success: true, users: users.map(formatUserResponse) });
  } catch (e: any) {
    console.error('searchUsers error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// GET /users/country/:countryCode
// ------------------------------------
export const getUsersByCountry = async (req: Request, res: Response) => {
  try {
    const cc = firstStr(req.params.countryCode);
    if (!cc) return res.status(400).json({ success: false, message: 'countryCode is required' });

    const users = await prisma.user.findMany({
      where: { countryCode: cc.toUpperCase() },
      take: 50,
    });

    return res.status(200).json({ success: true, users: users.map((u: any) => {
      const { passwordHash, ...safe } = u;
      return safe;
    }) });
  } catch (e: any) {
    console.error('getUsersByCountry error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// POST /users/:targetUserId/follow
// Relationship has composite key: (followerId, followingId)
// ------------------------------------
export const followUser = async (req: Request, res: Response) => {
  try {
    const followerId = (req as any).userId as number | undefined;
    const targetUserId = Number(req.params.targetUserId);

    if (!followerId) return res.status(401).json({ success: false, message: 'Unauthorized' });
    if (!targetUserId || targetUserId <= 0) return res.status(400).json({ success: false, message: 'Invalid targetUserId' });
    if (followerId === targetUserId) return res.status(400).json({ success: false, message: 'Cannot follow yourself' });

    const existing = await prisma.relationship.findUnique({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
    });

    if (existing) return res.status(400).json({ success: false, message: 'Already following' });

    await prisma.relationship.create({
      data: {
        followerId,
        followingId: targetUserId,
        status: 'accepted',
        type: 'fan',
      },
    });

    return res.status(200).json({ success: true, message: 'Followed' });
  } catch (e: any) {
    console.error('followUser error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// POST /users/:targetUserId/unfollow
// ------------------------------------
export const unfollowUser = async (req: Request, res: Response) => {
  try {
    const followerId = (req as any).userId as number | undefined;
    const targetUserId = Number(req.params.targetUserId);

    if (!followerId) return res.status(401).json({ success: false, message: 'Unauthorized' });
    if (!targetUserId || targetUserId <= 0) return res.status(400).json({ success: false, message: 'Invalid targetUserId' });

    await prisma.relationship.delete({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
    });

    return res.status(200).json({ success: true, message: 'Unfollowed' });
  } catch (e: any) {
    console.error('unfollowUser error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// GET /users/:userId/followers
// Return users who follow userId
// ------------------------------------
export const getFollowers = async (req: Request, res: Response) => {
  try {
    const userId = Number(req.params.userId);
    if (!userId || userId <= 0) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const rel = await prisma.relationship.findMany({
      where: { followingId: userId },
      include: { follower: true },
      take: 200,
      orderBy: { createdAt: 'desc' },
    });

    return res.status(200).json({ success: true, users: rel.map((r) => formatUserResponse(r.follower)) });
  } catch (e: any) {
    console.error('getFollowers error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};

// ------------------------------------
// GET /users/:userId/following
// Return users the userId follows
// ------------------------------------
export const getFollowing = async (req: Request, res: Response) => {
  try {
    const userId = Number(req.params.userId);
    if (!userId || userId <= 0) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const rel = await prisma.relationship.findMany({
      where: { followerId: userId },
      include: { following: true },
      take: 200,
      orderBy: { createdAt: 'desc' },
    });

    return res.status(200).json({ success: true, users: rel.map((r) => formatUserResponse(r.following)) });
  } catch (e: any) {
    console.error('getFollowing error:', e);
    return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
  }
};
