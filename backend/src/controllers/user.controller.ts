// File: src/controllers/user.controller.ts

import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { firstStr } from '../utils/http';
import { getAgencyRole } from '../agencies/agency.controller';
import { getUserCurrentRoomId } from '../services/socket.service';
interface UpdateProfileRequest {
  name?: string;
  bio?: string;
  gender?: string;
  countryCode?: string;
  country?: string;
  avatarUrl?: string;
  phone?: string;
}

const PUBLIC_USER_FIELDS = [
  'id', 'name', 'displayId', 'avatarUrl', 'avatarFrameUrl', 'activeFrameId',
  'level', 'xp', 'bio', 'country', 'countryCode', 'gender', 'vipLevel',
  'age', 'isVerified', 'createdAt',
] as const;

const pickPublicUserFields = (user: any) => {
  const out: Record<string, any> = {};
  for (const k of PUBLIC_USER_FIELDS) {
    if (k in user) out[k] = (user as any)[k];
  }
  return out;
};

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

    const [followerCount, followingCount, agencyInfo] = await Promise.all([
      prisma.follow.count({ where: { followingId: userId, status: 'ACCEPTED' } }),
      prisma.follow.count({ where: { followerId: userId, status: 'ACCEPTED' } }),
      getAgencyRole(userId).catch(() => null),
    ]);

    return res.status(200).json({
      success: true,
      user: {
        ...formatUserResponse(user),
        followerCount, followingCount, followersCount: followerCount,
        agencyRole: agencyInfo?.agencyRole ?? null,
        agencyName: agencyInfo?.agencyName ?? null,
      },
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
      include: {
        // Room-card medals row (#redesign): most recently unlocked first, only
        // need the latest 4 — the card has no room for more.
        achievements: {
          include: { achievement: true },
          orderBy: { unlockedAt: 'desc' },
          take: 4,
        },
        ownedFamily: { select: { name: true } },
        familyMembership: { include: { family: { select: { name: true } } } },
      },
    });

    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const [followerCount, followingCount, agencyInfo] = await Promise.all([
      prisma.follow.count({ where: { followingId: userId, status: 'ACCEPTED' } }),
      prisma.follow.count({ where: { followerId: userId, status: 'ACCEPTED' } }),
      getAgencyRole(userId).catch(() => null),
    ]);

    // #31: the room this user is ACTUALLY in right now (guest or host), for
    // the live badge / مسار button — not just a room they happen to own.
    const currentRoomId = getUserCurrentRoomId(userId);

    return res.status(200).json({
      success: true,
      user: {
        ...pickPublicUserFields(user),
        followerCount, followingCount, followersCount: followerCount,
        agencyRole: agencyInfo?.agencyRole ?? null,
        agencyName: agencyInfo?.agencyName ?? null,
        liveRoomId: currentRoomId,
        // Real only — null when the user owns/joined no family, never a
        // placeholder name (matches the room-card redesign's no-fake-data rule).
        familyName: (user as any).ownedFamily?.name ?? (user as any).familyMembership?.family?.name ?? null,
        achievements: (user as any).achievements.map((ua: any) => ({
          name: ua.achievement.name,
          iconUrl: ua.achievement.iconUrl,
          unlockedAt: ua.unlockedAt,
        })),
      },
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

    const { name, bio, gender, countryCode, country, avatarUrl, phone, age } = req.body as UpdateProfileRequest & { age?: number };
    // avatarFrameUrl / activeFrameId are intentionally NOT accepted here.
    // Frames must be equipped via the coin-priced store endpoint (/store/activate-frame).

    if (!isValidGender(gender)) {
      return res.status(400).json({ success: false, message: 'Invalid gender' });
    }

    const data: any = {};
    if (name) {
      // Respect an admin-imposed name lock: the user cannot change their own name.
      const current = await (prisma as any).user.findUnique({ where: { id: userId }, select: { nameLocked: true, name: true } });
      if (current?.nameLocked && name !== current.name) {
        return res.status(403).json({ success: false, message: 'تم تثبيت اسمك من قبل الإدارة ولا يمكن تغييره.' });
      }
      data.name = name;
    }
    if (bio !== undefined) data.bio = bio;
    if (gender) data.gender = gender.toLowerCase();
    if (countryCode) data.countryCode = countryCode.toUpperCase();
    if (country !== undefined) data.country = country;
    if (avatarUrl) data.avatarUrl = avatarUrl;
    if (phone) data.phone = phone;
    if (age !== undefined && age !== null) {
      const a = Number(age);
      if (Number.isFinite(a) && a >= 1 && a <= 120) data.age = Math.floor(a);
    }
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

    // SQLite Prisma doesn't support `mode: insensitive`.
    // Also match numeric queries against the public displayId.
    const numeric = /^\d+$/.test(q) ? Number(q) : null;
    const users = await prisma.user.findMany({
      where: {
        isBanned: false,
        OR: [
          { name: { contains: q } },
          ...(numeric !== null ? [{ displayId: numeric }] : []),
        ],
      },
      // Only expose safe, public fields — never coins/email/phone/recharge here.
      select: {
        id: true,
        name: true,
        avatarUrl: true,
        displayId: true,
        level: true,
      },
      take: 20,
    });

    return res.status(200).json({ success: true, users });
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

    const existing = await prisma.follow.findUnique({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
    });

    if (existing?.status === 'ACCEPTED') return res.status(400).json({ success: false, message: 'Already following' });

    await prisma.follow.upsert({
      where: { followerId_followingId: { followerId, followingId: targetUserId } },
      create: {
        followerId,
        followingId: targetUserId,
        status: 'ACCEPTED',
      },
      update: { status: 'ACCEPTED' },
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

    await prisma.follow.delete({
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

    const rel = await prisma.follow.findMany({
      where: { followingId: userId, status: 'ACCEPTED' },
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

    const rel = await prisma.follow.findMany({
      where: { followerId: userId, status: 'ACCEPTED' },
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

// ------------------------------------
// Personal blacklist (القائمة السوداء) — #2 settings menu
// ------------------------------------
export const getMyBlocks = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    const blocks = await (prisma as any).userBlock.findMany({
      where: { blockerId: userId },
      orderBy: { createdAt: 'desc' },
    });
    const ids = blocks.map((b: any) => b.blockedId);
    const users = ids.length
      ? await prisma.user.findMany({ where: { id: { in: ids } } })
      : [];
    const byId = new Map(users.map((u) => [u.id, u]));
    const data = blocks.map((b: any) => ({
      blockedAt: b.createdAt,
      user: byId.has(b.blockedId) ? pickPublicUserFields(byId.get(b.blockedId)) : { id: b.blockedId, name: 'مستخدم محذوف' },
    }));
    return res.json({ success: true, data });
  } catch (e: any) {
    console.error('getMyBlocks error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};

export const blockUser = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
    const targetId = Number(req.params.targetUserId);
    if (!targetId || targetId <= 0) return res.status(400).json({ success: false, message: 'Invalid userId' });
    if (targetId === userId) return res.status(400).json({ success: false, message: 'لا يمكنك حظر نفسك' });

    const target = await prisma.user.findUnique({ where: { id: targetId }, select: { id: true } });
    if (!target) return res.status(404).json({ success: false, message: 'المستخدم غير موجود' });

    await (prisma as any).userBlock.upsert({
      where: { blockerId_blockedId: { blockerId: userId, blockedId: targetId } },
      create: { blockerId: userId, blockedId: targetId },
      update: {},
    });
    return res.json({ success: true, message: 'تم الحظر' });
  } catch (e: any) {
    console.error('blockUser error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};

export const unblockUser = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });
    const targetId = Number(req.params.targetUserId);
    if (!targetId || targetId <= 0) return res.status(400).json({ success: false, message: 'Invalid userId' });

    await (prisma as any).userBlock.deleteMany({ where: { blockerId: userId, blockedId: targetId } });
    return res.json({ success: true, message: 'تم إلغاء الحظر' });
  } catch (e: any) {
    console.error('unblockUser error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};

// ------------------------------------
// DELETE /users/me — delete (anonymize + disable) the caller's account (#2).
// Rows with FK history (gifts, transactions, rooms) survive; the account
// itself can never log in again and its identity fields are wiped.
// ------------------------------------
export const deleteMyAccount = async (req: Request, res: Response) => {
  try {
    const userId = (req as any).userId as number | undefined;
    if (!userId) return res.status(401).json({ success: false, message: 'Unauthorized' });

    await prisma.user.update({
      where: { id: userId },
      data: {
        name: 'حساب محذوف',
        email: `deleted+${userId}.${Date.now()}@deleted.samafox`,
        phone: null,
        googleId: null,
        passwordHash: null,
        avatarUrl: null,
        avatarFrameUrl: null,
        bio: null,
        isBanned: true,
        bannedAt: new Date(),
        banReason: 'حذف الحساب بواسطة صاحبه',
        banSource: 'system',
      } as any,
    });
    return res.json({ success: true, message: 'تم حذف الحساب' });
  } catch (e: any) {
    console.error('deleteMyAccount error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};

// ------------------------------------
// GET /users/:userId/badges — #28 badges row. One representative icon per
// distinct special-item type this user owns (frame, entrance effect, room
// theme, ...), for a compact badge row next to the name on the profile.
// ------------------------------------
export const getUserBadges = async (req: Request, res: Response) => {
  try {
    const userId = Number(req.params.userId);
    if (!userId || userId <= 0) return res.status(400).json({ success: false, message: 'Invalid userId' });

    const owned = await (prisma as any).userItem.findMany({
      where: { userId },
      include: { item: { select: { id: true, name: true, type: true, assetUrl: true } } },
      orderBy: { acquiredAt: 'asc' },
    });

    const byType = new Map<string, any>();
    for (const o of owned) {
      if (!o.item) continue;
      if (!byType.has(o.item.type)) byType.set(o.item.type, o.item);
    }

    const data = Array.from(byType.values()).map((item: any) => ({
      type: item.type,
      name: item.name,
      iconUrl: item.assetUrl,
    }));

    return res.json({ success: true, data });
  } catch (e: any) {
    console.error('getUserBadges error:', e);
    return res.status(500).json({ success: false, message: 'Failed' });
  }
};
