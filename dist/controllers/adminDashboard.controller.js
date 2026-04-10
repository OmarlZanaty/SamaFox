"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.adminDashboardUpdateAgencyStatus = exports.adminDashboardListChargingAgencies = exports.adminDashboardListRooms = exports.adminDashboardListUsers = exports.adminDashboardOverview = void 0;
const prisma_1 = __importDefault(require("../utils/prisma"));
const http_1 = require("../utils/http");
function serializeUser(user) {
    return {
        ...user,
        coinsBalance: user.coinsBalance?.toString() ?? "0",
    };
}
async function requireAdminDashboard(req) {
    const userId = req.userId;
    if (!userId)
        throw { status: 401, message: 'Unauthorized' };
    const user = await prisma_1.default.user.findUnique({
        where: { id: userId },
        select: { id: true, isAdmin: true }
    });
    if (!user || !user.isAdmin)
        throw { status: 403, message: 'Admin only (Dashboard)' };
}
function ok(res, data) {
    return res.json({ success: true, ...data });
}
function fail(res, status, message) {
    return res.status(status).json({ success: false, message });
}
function parseIntOr(v, def) {
    const n = Number(v);
    return Number.isFinite(n) ? n : def;
}
const adminDashboardOverview = async (req, res) => {
    try {
        await requireAdminDashboard(req);
        const [usersCount, roomsCount, agenciesCount, pendingAgencies] = await Promise.all([
            prisma_1.default.user.count(),
            prisma_1.default.room.count(),
            prisma_1.default.chargingAgency.count(),
            prisma_1.default.chargingAgency.count({ where: { status: 'pending' } })
        ]);
        return ok(res, {
            data: {
                usersCount,
                roomsCount,
                agenciesCount,
                pendingAgencies
            }
        });
    }
    catch (e) {
        return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
    }
};
exports.adminDashboardOverview = adminDashboardOverview;
const adminDashboardListUsers = async (req, res) => {
    try {
        await requireAdminDashboard(req);
        const page = parseIntOr(req.query.page, 1);
        const limit = parseIntOr(req.query.limit, 30);
        const skip = (page - 1) * limit;
        const [total, users] = await Promise.all([
            prisma_1.default.user.count(),
            prisma_1.default.user.findMany({
                orderBy: { createdAt: 'desc' },
                skip,
                take: limit
            })
        ]);
        return ok(res, {
            data: users.map(serializeUser),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit)
            }
        });
    }
    catch (e) {
        return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
    }
};
exports.adminDashboardListUsers = adminDashboardListUsers;
const adminDashboardListRooms = async (req, res) => {
    try {
        await requireAdminDashboard(req);
        const rooms = await prisma_1.default.room.findMany({
            orderBy: { createdAt: 'desc' },
            include: { owner: true }
        });
        return ok(res, { data: rooms });
    }
    catch (e) {
        return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
    }
};
exports.adminDashboardListRooms = adminDashboardListRooms;
const adminDashboardListChargingAgencies = async (req, res) => {
    try {
        await requireAdminDashboard(req);
        const status = (0, http_1.firstStr)(req.query.status);
        const agencies = await prisma_1.default.chargingAgency.findMany({
            where: status ? { status } : undefined,
            include: { user: true },
            orderBy: { createdAt: 'desc' }
        });
        return ok(res, { data: agencies });
    }
    catch (e) {
        return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
    }
};
exports.adminDashboardListChargingAgencies = adminDashboardListChargingAgencies;
const adminDashboardUpdateAgencyStatus = async (req, res) => {
    try {
        await requireAdminDashboard(req);
        const id = Number(req.params.id);
        const status = req.body?.status;
        if (!['approved', 'rejected', 'pending'].includes(status))
            return fail(res, 400, 'Invalid status');
        const updated = await prisma_1.default.chargingAgency.update({
            where: { id },
            data: { status }
        });
        return ok(res, { data: updated });
    }
    catch (e) {
        return fail(res, e?.status ?? 500, e?.message ?? 'Server error');
    }
};
exports.adminDashboardUpdateAgencyStatus = adminDashboardUpdateAgencyStatus;
//# sourceMappingURL=adminDashboard.controller.js.map