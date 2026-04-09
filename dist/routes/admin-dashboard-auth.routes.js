"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const prisma_1 = __importDefault(require("../utils/prisma"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const router = express_1.default.Router();
function pickToken(resp) {
    const t = resp?.token ||
        resp?.accessToken ||
        resp?.jwt ||
        resp?.data?.token ||
        resp?.data?.accessToken ||
        resp?.data?.jwt ||
        resp?.data?.data?.token ||
        resp?.data?.data?.accessToken;
    return typeof t === 'string' && t.length > 10 ? t : null;
}
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body ?? {};
        if (!email || !password) {
            return res.status(400).json({ message: 'email/password required' });
        }
        const port = process.env.PORT || 3000;
        const base = process.env.INTERNAL_BASE_URL || `http://127.0.0.1:${port}`;
        const r = await fetch(`${base}/api/v1/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
            body: JSON.stringify({ email, password }),
        });
        const text = await r.text();
        let body = null;
        try {
            body = text ? JSON.parse(text) : null;
        }
        catch {
            body = { raw: text };
        }
        if (!r.ok) {
            const msg = body?.message || body?.error || `Login failed (HTTP ${r.status})`;
            return res.status(401).json({ message: msg });
        }
        const token = pickToken(body);
        if (!token) {
            return res.status(500).json({
                message: 'Auth login succeeded but token not found in response',
                debugKeys: Object.keys(body || {}),
            });
        }
        const decoded = jsonwebtoken_1.default.decode(token);
        const userId = Number(decoded?.userId || decoded?.id);
        if (!userId) {
            return res.status(500).json({ message: 'Token decoded but userId missing' });
        }
        const user = await prisma_1.default.user.findUnique({
            where: { id: userId },
            select: { id: true, isAdmin: true },
        });
        if (!user?.isAdmin) {
            return res.status(403).json({ message: 'Not admin' });
        }
        res.cookie('access_token', token, {
            httpOnly: true,
            sameSite: 'lax',
            secure: false,
            maxAge: 7 * 24 * 60 * 60 * 1000,
        });
        return res.json({ success: true });
    }
    catch (e) {
        console.error('admin-dashboard-auth login error', e);
        return res.status(500).json({ message: 'Server error' });
    }
});
router.post('/logout', (_req, res) => {
    res.clearCookie('access_token');
    return res.json({ success: true });
});
exports.default = router;
//# sourceMappingURL=admin-dashboard-auth.routes.js.map