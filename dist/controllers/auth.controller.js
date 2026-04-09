"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.logout = exports.getCurrentUser = exports.refreshToken = exports.googleLogin = exports.login = exports.register = void 0;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const bcrypt_1 = __importDefault(require("bcrypt"));
const google_auth_library_1 = require("google-auth-library");
const prisma_1 = __importDefault(require("../utils/prisma"));
const googleClient = new google_auth_library_1.OAuth2Client(process.env.GOOGLE_CLIENT_ID);
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'your-refresh-secret';
const generateTokens = (userId) => {
    const accessToken = jsonwebtoken_1.default.sign({ userId }, JWT_SECRET, { expiresIn: '24h' });
    const refreshToken = jsonwebtoken_1.default.sign({ userId }, JWT_REFRESH_SECRET, { expiresIn: '7d' });
    return { accessToken, refreshToken };
};
const isValidGender = (gender) => {
    if (!gender)
        return true;
    return ['male', 'female', 'other'].includes(gender.toLowerCase());
};
const formatUserResponse = (user) => {
    const { passwordHash, ...safe } = user;
    return safe;
};
const register = async (req, res) => {
    try {
        const { name, email, password, gender, countryCode, country, phone } = req.body;
        if (!name || !email || !password) {
            return res.status(400).json({ success: false, message: 'name, email, password are required' });
        }
        if (!isValidGender(gender)) {
            return res.status(400).json({ success: false, message: 'Invalid gender' });
        }
        const exists = await prisma_1.default.user.findUnique({ where: { email } });
        if (exists)
            return res.status(409).json({ success: false, message: 'Email already registered' });
        const passwordHash = await bcrypt_1.default.hash(password, 10);
        const user = await prisma_1.default.user.create({
            data: {
                name,
                email,
                phone: phone || null,
                passwordHash,
                gender: gender?.toLowerCase() || null,
                countryCode: countryCode?.toUpperCase() || null,
                country: country || null,
                isVerified: false,
            },
        });
        const { accessToken, refreshToken } = generateTokens(user.id);
        return res.status(201).json({
            success: true,
            message: 'Registered',
            accessToken,
            refreshToken,
            user: formatUserResponse(user),
        });
    }
    catch (e) {
        console.error('register error:', e);
        return res.status(500).json({ success: false, message: 'Registration failed', error: e?.message || 'Unknown' });
    }
};
exports.register = register;
const login = async (req, res) => {
    try {
        const { email, password } = req.body;
        if (!email || !password)
            return res.status(400).json({ success: false, message: 'email and password required' });
        const user = await prisma_1.default.user.findUnique({ where: { email } });
        if (!user || !user.passwordHash) {
            return res.status(401).json({ success: false, message: 'Invalid email or password' });
        }
        const ok = await bcrypt_1.default.compare(password, user.passwordHash);
        if (!ok)
            return res.status(401).json({ success: false, message: 'Invalid email or password' });
        await prisma_1.default.user.update({
            where: { id: user.id },
            data: { lastLoginAt: new Date() },
        });
        const { accessToken, refreshToken } = generateTokens(user.id);
        return res.status(200).json({
            success: true,
            message: 'Login successful',
            accessToken,
            refreshToken,
            user: formatUserResponse(user),
        });
    }
    catch (e) {
        console.error('login error:', e);
        return res.status(500).json({ success: false, message: 'Login failed', error: e?.message || 'Unknown' });
    }
};
exports.login = login;
const googleLogin = async (req, res) => {
    try {
        const { idToken } = req.body;
        if (!idToken)
            return res.status(400).json({ success: false, message: 'idToken required' });
        const ticket = await googleClient.verifyIdToken({ idToken, audience: process.env.GOOGLE_CLIENT_ID });
        const payload = ticket.getPayload();
        if (!payload?.email)
            return res.status(400).json({ success: false, message: 'Invalid Google token' });
        const email = payload.email;
        const name = payload.name || 'Google User';
        const picture = payload.picture || null;
        const googleSub = payload.sub || null;
        let user = await prisma_1.default.user.findUnique({ where: { email } });
        if (!user) {
            user = await prisma_1.default.user.create({
                data: {
                    email,
                    name,
                    avatarUrl: picture,
                    googleId: googleSub,
                    isVerified: true,
                    lastLoginAt: new Date(),
                },
            });
        }
        else {
            user = await prisma_1.default.user.update({
                where: { id: user.id },
                data: {
                    avatarUrl: user.avatarUrl || picture,
                    googleId: user.googleId || googleSub,
                    isVerified: true,
                    lastLoginAt: new Date(),
                },
            });
        }
        const { accessToken, refreshToken } = generateTokens(user.id);
        return res.status(200).json({
            success: true,
            message: 'Google login successful',
            accessToken,
            refreshToken,
            user: formatUserResponse(user),
        });
    }
    catch (e) {
        console.error('googleLogin error:', e);
        return res.status(500).json({ success: false, message: 'Google login failed', error: e?.message || 'Unknown' });
    }
};
exports.googleLogin = googleLogin;
const refreshToken = async (req, res) => {
    try {
        const { refreshToken: token } = req.body;
        if (!token)
            return res.status(400).json({ success: false, message: 'refreshToken required' });
        const decoded = jsonwebtoken_1.default.verify(token, JWT_REFRESH_SECRET);
        const user = await prisma_1.default.user.findUnique({ where: { id: decoded.userId } });
        if (!user)
            return res.status(401).json({ success: false, message: 'User not found' });
        const { accessToken, refreshToken: newRefresh } = generateTokens(user.id);
        return res.status(200).json({
            success: true,
            message: 'Token refreshed',
            accessToken,
            refreshToken: newRefresh,
            user: formatUserResponse(user),
        });
    }
    catch (e) {
        return res.status(401).json({ success: false, message: 'Invalid refresh token', error: e?.message || 'Unknown' });
    }
};
exports.refreshToken = refreshToken;
const getCurrentUser = async (req, res) => {
    try {
        const userId = req.userId;
        if (!userId)
            return res.status(401).json({ success: false, message: 'Unauthorized' });
        const user = await prisma_1.default.user.findUnique({ where: { id: userId } });
        if (!user)
            return res.status(404).json({ success: false, message: 'User not found' });
        return res.status(200).json({ success: true, user: formatUserResponse(user) });
    }
    catch (e) {
        return res.status(500).json({ success: false, message: 'Failed', error: e?.message || 'Unknown' });
    }
};
exports.getCurrentUser = getCurrentUser;
const logout = async (_req, res) => {
    return res.status(200).json({ success: true, message: 'Logout successful' });
};
exports.logout = logout;
//# sourceMappingURL=auth.controller.js.map