"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireAuth = exports.authenticate = exports.optionalAuth = exports.authMiddleware = void 0;
const jwt_1 = require("../utils/jwt");
function extractToken(req) {
    const h = req.headers.authorization;
    if (h && h.startsWith('Bearer '))
        return h.slice('Bearer '.length).trim();
    const q = req.query?.token;
    if (q && q.length > 10)
        return q;
    const c1 = req.cookies?.access_token;
    if (c1 && c1.length > 10)
        return c1;
    const raw = req.headers.cookie || '';
    const match = raw.match(/(?:^|;\s*)access_token=([^;]+)/);
    if (match?.[1] && match[1].length > 10)
        return match[1];
    return null;
}
const authMiddleware = (req, res, next) => {
    try {
        const token = extractToken(req);
        if (!token)
            return res.status(401).json({ success: false, message: 'Missing token' });
        const payload = (0, jwt_1.verifyAccessToken)(token);
        req.userId = payload.userId;
        req.authUser = { id: payload.userId };
        req.user = { id: payload.userId };
        return next();
    }
    catch {
        return res.status(401).json({ success: false, message: 'Invalid token' });
    }
};
exports.authMiddleware = authMiddleware;
const optionalAuth = (req, _res, next) => {
    try {
        const token = extractToken(req);
        if (!token)
            return next();
        const payload = (0, jwt_1.verifyAccessToken)(token);
        req.userId = payload.userId;
        req.authUser = { id: payload.userId };
        req.user = { id: payload.userId };
        return next();
    }
    catch {
        return next();
    }
};
exports.optionalAuth = optionalAuth;
exports.authenticate = exports.authMiddleware;
exports.requireAuth = exports.authMiddleware;
//# sourceMappingURL=auth.middleware.js.map