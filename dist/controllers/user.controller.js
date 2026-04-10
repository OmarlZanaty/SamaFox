"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getFollowing = exports.getFollowers = exports.unfollowUser = exports.followUser = exports.getUsersByCountry = exports.searchUsers = exports.updateGenderAndCountry = exports.updateProfile = exports.getUserById = exports.getMe = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
const isValidGender = (gender) => {
    if (!gender)
        return true;
    return ['male', 'female', 'other'].includes(gender.toLowerCase());
};
const formatUserResponse = (user) => {
    const { passwordHash, ...safe } = user;
    return safe;
};
const getMe = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        const user = await prisma_1.default.user.findUnique({
            where: { id: userId },
            include: { achievements: true },
        });
        if (!user)
            return res.status(404).json({ success: false, message: 'User not found' });
        return res.status(200).json({ success: true, user: formatUserResponse(user) });
    }
    catch (e) {
        console.error('getMe error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.getMe = getMe;
const getUserById = async (req, res) => {
    try {
        const userIdStr = req.params.userId;
        const userId = Number(userIdStr);
        if (!userId || userId <= 0)
            return res.status(400).json({ success: false, message: 'Valid userId required' });
        const user = await prisma_1.default.user.findUnique({
            where: { id: userId },
            include: { achievements: true },
        });
        if (!user)
            return res.status(404).json({ success: false, message: 'User not found' });
        return res.status(200).json({ success: true, user: formatUserResponse(user) });
    }
    catch (e) {
        console.error('getUserById error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.getUserById = getUserById;
const updateProfile = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        const { name, bio, gender, countryCode, country, avatarUrl, phone, avatarFrameUrl } = req.body;
        if (!isValidGender(gender)) {
            return res.status(400).json({ success: false, message: 'Invalid gender' });
        }
        const data = {};
        if (name)
            data.name = name;
        if (bio !== undefined)
            data.bio = bio;
        if (gender)
            data.gender = gender.toLowerCase();
        if (countryCode)
            data.countryCode = countryCode.toUpperCase();
        if (country !== undefined)
            data.country = country;
        if (avatarUrl)
            data.avatarUrl = avatarUrl;
        if (phone)
            data.phone = phone;
        if (avatarFrameUrl !== undefined)
            data.avatarFrameUrl = avatarFrameUrl;
        const user = await prisma_1.default.user.update({ where: { id: userId }, data });
        return res.status(200).json({ success: true, message: 'Profile updated', user: formatUserResponse(user) });
    }
    catch (e) {
        console.error('updateProfile error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.updateProfile = updateProfile;
const updateGenderAndCountry = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        const { gender, countryCode, country } = req.body;
        if (!isValidGender(gender))
            return res.status(400).json({ success: false, message: 'Invalid gender' });
        const user = await prisma_1.default.user.update({
            where: { id: userId },
            data: {
                gender: gender ? gender.toLowerCase() : undefined,
                countryCode: countryCode ? countryCode.toUpperCase() : undefined,
                country: country !== undefined ? country : undefined,
            },
        });
        return res.status(200).json({ success: true, message: 'Updated', user: formatUserResponse(user) });
    }
    catch (e) {
        console.error('updateGenderAndCountry error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.updateGenderAndCountry = updateGenderAndCountry;
const searchUsers = async (req, res) => {
    try {
        const q = req.query.query;
        if (!q || typeof q !== 'string')
            return res.status(400).json({ success: false, message: 'query is required' });
        const users = await prisma_1.default.user.findMany({
            where: {
                OR: [{ name: { contains: q } }, { email: { contains: q } }],
            },
            take: 20,
        });
        return res.status(200).json({ success: true, users: users.map(formatUserResponse) });
    }
    catch (e) {
        console.error('searchUsers error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.searchUsers = searchUsers;
const getUsersByCountry = async (req, res) => {
    try {
        const cc = (0, http_1.firstStr)(req.params.countryCode);
        if (!cc)
            return res.status(400).json({ success: false, message: 'countryCode is required' });
        const users = await prisma_1.default.user.findMany({
            where: { countryCode: cc.toUpperCase() },
            take: 50,
        });
        return res.status(200).json({ success: true, users: users.map((u) => {
                const { passwordHash, ...safe } = u;
                return safe;
            }) });
    }
    catch (e) {
        console.error('getUsersByCountry error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.getUsersByCountry = getUsersByCountry;
const followUser = async (req, res) => {
    try {
        const followerId = req.userId;
        const targetUserId = Number(req.params.targetUserId);
        if (!followerId)
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        if (!targetUserId || targetUserId <= 0)
            return res.status(400).json({ success: false, message: 'Invalid targetUserId' });
        if (followerId === targetUserId)
            return res.status(400).json({ success: false, message: 'Cannot follow yourself' });
        const existing = await prisma_1.default.relationship.findUnique({
            where: { followerId_followingId: { followerId, followingId: targetUserId } },
        });
        if (existing)
            return res.status(400).json({ success: false, message: 'Already following' });
        await prisma_1.default.relationship.create({
            data: {
                followerId,
                followingId: targetUserId,
                status: 'accepted',
                type: 'fan',
            },
        });
        return res.status(200).json({ success: true, message: 'Followed' });
    }
    catch (e) {
        console.error('followUser error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.followUser = followUser;
const unfollowUser = async (req, res) => {
    try {
        const followerId = req.userId;
        const targetUserId = Number(req.params.targetUserId);
        if (!followerId)
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        if (!targetUserId || targetUserId <= 0)
            return res.status(400).json({ success: false, message: 'Invalid targetUserId' });
        await prisma_1.default.relationship.delete({
            where: { followerId_followingId: { followerId, followingId: targetUserId } },
        });
        return res.status(200).json({ success: true, message: 'Unfollowed' });
    }
    catch (e) {
        console.error('unfollowUser error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.unfollowUser = unfollowUser;
const getFollowers = async (req, res) => {
    try {
        const userId = Number(req.params.userId);
        if (!userId || userId <= 0)
            return res.status(400).json({ success: false, message: 'Invalid userId' });
        const rel = await prisma_1.default.relationship.findMany({
            where: { followingId: userId },
            include: { follower: true },
            take: 200,
            orderBy: { createdAt: 'desc' },
        });
        return res.status(200).json({ success: true, users: rel.map((r) => formatUserResponse(r.follower)) });
    }
    catch (e) {
        console.error('getFollowers error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.getFollowers = getFollowers;
const getFollowing = async (req, res) => {
    try {
        const userId = Number(req.params.userId);
        if (!userId || userId <= 0)
            return res.status(400).json({ success: false, message: 'Invalid userId' });
        const rel = await prisma_1.default.relationship.findMany({
            where: { followerId: userId },
            include: { following: true },
            take: 200,
            orderBy: { createdAt: 'desc' },
        });
        return res.status(200).json({ success: true, users: rel.map((r) => formatUserResponse(r.following)) });
    }
    catch (e) {
        console.error('getFollowing error:', e);
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.getFollowing = getFollowing;
//# sourceMappingURL=user.controller.js.map