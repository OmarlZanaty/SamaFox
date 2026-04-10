"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.updateChargingAgencyStatus = exports.adminAdjustAgencyBalance = exports.reviewTopupRequest = exports.adminListTopups = exports.myTopupRequests = exports.createTopupRequest = exports.agencyTransferCoins = exports.myAgencyTransfers = exports.myAgencyBalance = exports.createChargingAgency = exports.listChargingAgencies = void 0;
exports.myChargingAgencies = myChargingAgencies;
const prisma_1 = __importDefault(require("../utils/prisma"));
function getUserId(req) {
    return typeof req.userId === 'number' ? req.userId : null;
}
async function assertAdmin(userId) {
    const u = await prisma_1.default.user.findUnique({
        where: { id: userId },
        select: { isAdmin: true },
    });
    return !!u?.isAdmin;
}
const listChargingAgencies = async (req, res) => {
    try {
        const status = req.query.status || 'approved';
        const items = await prisma_1.default.chargingAgency.findMany({
            where: { status },
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                userId: true,
                agencyName: true,
                phoneNumber: true,
                agencyImageUrl: true,
                idFrontUrl: true,
                idBackUrl: true,
                status: true,
                createdAt: true,
            },
        });
        return res.json(items);
    }
    catch (e) {
        console.error('listChargingAgencies error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.listChargingAgencies = listChargingAgencies;
async function myChargingAgencies(req, res) {
    try {
        const userId = getUserId(req);
        if (!userId)
            return res.status(401).json({ message: 'Unauthorized' });
        const items = await prisma_1.default.chargingAgency.findMany({
            where: { userId },
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                userId: true,
                agencyName: true,
                phoneNumber: true,
                agencyImageUrl: true,
                idFrontUrl: true,
                idBackUrl: true,
                status: true,
                balanceCoins: true,
                totalSentCoins: true,
                totalTopupCoins: true,
                createdAt: true,
            },
        });
        return res.json(items);
    }
    catch (e) {
        console.error('myChargingAgencies error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
}
;
const createChargingAgency = async (req, res) => {
    try {
        const userId = getUserId(req);
        if (!userId)
            return res.status(401).json({ message: 'Unauthorized' });
        const { agencyName, phoneNumber, agencyImageUrl, idFrontUrl, idBackUrl } = req.body;
        if (!agencyName || !phoneNumber || !agencyImageUrl || !idFrontUrl || !idBackUrl) {
            return res.status(400).json({ message: 'Missing required fields' });
        }
        const existingPending = await prisma_1.default.chargingAgency.findFirst({
            where: { userId, status: 'pending' },
            select: { id: true },
        });
        if (existingPending) {
            return res.status(409).json({ message: 'You already have a pending request' });
        }
        const created = await prisma_1.default.chargingAgency.create({
            data: {
                userId,
                agencyName: String(agencyName).trim(),
                phoneNumber: String(phoneNumber).trim(),
                agencyImageUrl: String(agencyImageUrl),
                idFrontUrl: String(idFrontUrl),
                idBackUrl: String(idBackUrl),
                status: 'pending',
            },
            select: {
                id: true,
                userId: true,
                agencyName: true,
                phoneNumber: true,
                agencyImageUrl: true,
                idFrontUrl: true,
                idBackUrl: true,
                status: true,
                createdAt: true,
            },
        });
        return res.status(201).json(created);
    }
    catch (e) {
        console.error('createChargingAgency error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.createChargingAgency = createChargingAgency;
const myAgencyBalance = async (req, res) => {
    const userId = req.userId;
    if (!userId)
        return res.status(401).json({ message: 'Unauthorized' });
    const agency = await prisma_1.default.chargingAgency.findFirst({
        where: { userId },
        select: { id: true, balanceCoins: true, agencyName: true, status: true },
        orderBy: { createdAt: 'desc' },
    });
    if (!agency)
        return res.json({ balanceCoins: 0, status: 'none' });
    return res.json(agency);
};
exports.myAgencyBalance = myAgencyBalance;
const myAgencyTransfers = async (req, res) => {
    try {
        const userId = getUserId(req);
        if (!userId)
            return res.status(401).json({ message: 'Unauthorized' });
        const agency = await prisma_1.default.chargingAgency.findFirst({
            where: { userId, status: 'approved' },
            select: { id: true },
        });
        if (!agency)
            return res.status(404).json({ message: 'No approved agency for this user' });
        const items = await prisma_1.default.agencyTransfer.findMany({
            where: { agencyId: agency.id },
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                agencyId: true,
                toUserId: true,
                amount: true,
                note: true,
                createdAt: true,
                toUser: { select: { id: true, name: true, avatarUrl: true } },
            },
        });
        return res.json(items);
    }
    catch (e) {
        console.error('myAgencyTransfers error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.myAgencyTransfers = myAgencyTransfers;
const agencyTransferCoins = async (req, res) => {
    const userId = getUserId(req);
    if (!userId)
        return res.status(401).json({ message: 'Unauthorized' });
    const toUserId = Number(req.body?.toUserId);
    const amount = Number(req.body?.amount);
    const note = req.body?.note ? String(req.body.note) : null;
    if (!toUserId || !amount || amount <= 0) {
        return res.status(400).json({ message: 'Invalid toUserId/amount' });
    }
    const agency = await prisma_1.default.chargingAgency.findFirst({
        where: { userId, status: 'approved' },
        select: { id: true },
    });
    if (!agency)
        return res.status(403).json({ message: 'You are not an approved agency' });
    const receiver = await prisma_1.default.user.findUnique({
        where: { id: toUserId },
        select: { id: true },
    });
    if (!receiver)
        return res.status(404).json({ message: 'Receiver user not found' });
    try {
        const result = await prisma_1.default.$transaction(async (tx) => {
            const agencyNow = await tx.chargingAgency.findUnique({
                where: { id: agency.id },
                select: { balanceCoins: true },
            });
            if (!agencyNow)
                throw new Error('agency_missing');
            if (agencyNow.balanceCoins < amount) {
                return { ok: false, reason: 'insufficient_balance' };
            }
            const updatedAgency = await tx.chargingAgency.update({
                where: { id: agency.id },
                data: {
                    balanceCoins: { decrement: amount },
                    totalSentCoins: { increment: amount },
                },
                select: { id: true, balanceCoins: true },
            });
            const updatedUser = await tx.user.update({
                where: { id: toUserId },
                data: { coinsBalance: { increment: amount } },
                select: { id: true, coinsBalance: true },
            });
            const transfer = await tx.agencyTransfer.create({
                data: { agencyId: agency.id, toUserId, amount, note },
                select: { id: true },
            });
            return { ok: true, updatedAgency, updatedUser, transfer };
        });
        if (result.ok === false) {
            return res.status(409).json({ message: 'Insufficient agency balance' });
        }
        return res.json({
            message: 'Transfer successful',
            agencyBalance: result.updatedAgency.balanceCoins,
            userBalance: result.updatedUser.coinsBalance,
            transferId: result.transfer.id,
        });
    }
    catch (e) {
        console.error('agencyTransferCoins error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.agencyTransferCoins = agencyTransferCoins;
const createTopupRequest = async (req, res) => {
    try {
        const userId = getUserId(req);
        if (!userId)
            return res.status(401).json({ message: 'Unauthorized' });
        const amount = Number(req.body?.amount);
        const receiptUrl = req.body?.receiptUrl ? String(req.body.receiptUrl) : null;
        const note = req.body?.note ? String(req.body.note) : null;
        if (!amount || amount <= 0 || !receiptUrl) {
            return res.status(400).json({ message: 'Invalid amount/receiptUrl' });
        }
        const agency = await prisma_1.default.chargingAgency.findFirst({
            where: { userId, status: 'approved' },
            select: { id: true },
        });
        if (!agency)
            return res.status(403).json({ message: 'Not approved agency' });
        const reqRow = await prisma_1.default.agencyTopupRequest.create({
            data: { agencyId: agency.id, amount, receiptUrl, note, status: 'pending' },
        });
        return res.status(201).json(reqRow);
    }
    catch (e) {
        console.error('createTopupRequest error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.createTopupRequest = createTopupRequest;
const myTopupRequests = async (req, res) => {
    try {
        const userId = getUserId(req);
        if (!userId)
            return res.status(401).json({ message: 'Unauthorized' });
        const agency = await prisma_1.default.chargingAgency.findFirst({
            where: { userId },
            select: { id: true },
        });
        if (!agency)
            return res.status(404).json({ message: 'No agency found' });
        const items = await prisma_1.default.agencyTopupRequest.findMany({
            where: { agencyId: agency.id },
            orderBy: { createdAt: 'desc' },
        });
        return res.json(items);
    }
    catch (e) {
        console.error('myTopupRequests error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.myTopupRequests = myTopupRequests;
const adminListTopups = async (req, res) => {
    try {
        const userId = getUserId(req);
        if (!userId)
            return res.status(401).json({ message: 'Unauthorized' });
        const isAdmin = await assertAdmin(userId);
        if (!isAdmin)
            return res.status(403).json({ message: 'Admin only' });
        const status = (req.query.status || 'pending').toLowerCase();
        const items = await prisma_1.default.agencyTopupRequest.findMany({
            where: { status },
            orderBy: { createdAt: 'desc' },
            select: {
                id: true,
                agencyId: true,
                amount: true,
                receiptUrl: true,
                note: true,
                status: true,
                reviewedBy: true,
                reviewedAt: true,
                createdAt: true,
                agency: {
                    select: { id: true, agencyName: true, phoneNumber: true, userId: true, balanceCoins: true },
                },
            },
        });
        return res.json(items);
    }
    catch (e) {
        console.error('adminListTopups error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.adminListTopups = adminListTopups;
const reviewTopupRequest = async (req, res) => {
    try {
        const adminId = getUserId(req);
        if (!adminId)
            return res.status(401).json({ message: 'Unauthorized' });
        const isAdmin = await assertAdmin(adminId);
        if (!isAdmin)
            return res.status(403).json({ message: 'Admin only' });
        const requestId = Number(req.params.id);
        const status = String(req.body?.status || '');
        if (!requestId || !['approved', 'rejected'].includes(status)) {
            return res.status(400).json({ message: 'Invalid id/status' });
        }
        const result = await prisma_1.default.$transaction(async (tx) => {
            const request = await tx.agencyTopupRequest.findUnique({ where: { id: requestId } });
            if (!request)
                throw new Error('not_found');
            if (request.status !== 'pending') {
                return { ok: false, reason: 'already_processed' };
            }
            if (status === 'approved') {
                await tx.chargingAgency.update({
                    where: { id: request.agencyId },
                    data: {
                        balanceCoins: { increment: request.amount },
                        totalTopupCoins: { increment: request.amount },
                    },
                });
            }
            const updated = await tx.agencyTopupRequest.update({
                where: { id: requestId },
                data: {
                    status,
                    reviewedBy: adminId,
                    reviewedAt: new Date(),
                },
            });
            return { ok: true, updated };
        });
        if (result.ok === false) {
            return res.status(409).json({ message: 'Already processed' });
        }
        return res.json({ message: 'Topup reviewed', request: result.updated });
    }
    catch (e) {
        console.error('reviewTopupRequest error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.reviewTopupRequest = reviewTopupRequest;
const adminAdjustAgencyBalance = async (req, res) => {
    try {
        const adminId = getUserId(req);
        if (!adminId)
            return res.status(401).json({ message: 'Unauthorized' });
        const isAdmin = await assertAdmin(adminId);
        if (!isAdmin)
            return res.status(403).json({ message: 'Admin only' });
        const agencyId = Number(req.params.id);
        const delta = Number(req.body?.delta);
        if (!agencyId || !Number.isFinite(delta) || delta === 0) {
            return res.status(400).json({ message: 'Invalid agencyId/delta' });
        }
        const result = await prisma_1.default.$transaction(async (tx) => {
            const agency = await tx.chargingAgency.findUnique({
                where: { id: agencyId },
                select: { balanceCoins: true },
            });
            if (!agency)
                throw new Error('agency_not_found');
            const newBal = agency.balanceCoins + delta;
            if (newBal < 0)
                return { ok: false };
            const updated = await tx.chargingAgency.update({
                where: { id: agencyId },
                data: {
                    balanceCoins: delta > 0 ? { increment: delta } : { decrement: Math.abs(delta) },
                    totalTopupCoins: delta > 0 ? { increment: delta } : undefined,
                },
                select: { id: true, balanceCoins: true, status: true },
            });
            return { ok: true, updated };
        });
        if (result.ok === false)
            return res.status(409).json({ message: 'Balance cannot go negative' });
        return res.json({ message: 'Agency balance updated', agency: result.updated });
    }
    catch (e) {
        console.error('adminAdjustAgencyBalance error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.adminAdjustAgencyBalance = adminAdjustAgencyBalance;
const updateChargingAgencyStatus = async (req, res) => {
    try {
        const adminId = getUserId(req);
        if (!adminId)
            return res.status(401).json({ message: 'Unauthorized' });
        const isAdmin = await assertAdmin(adminId);
        if (!isAdmin)
            return res.status(403).json({ message: 'Admin only' });
        const id = Number(req.params.id);
        const status = String(req.body?.status || '');
        if (!id || !['pending', 'approved', 'rejected'].includes(status)) {
            return res.status(400).json({ message: 'Invalid id/status' });
        }
        const updated = await prisma_1.default.chargingAgency.update({
            where: { id },
            data: { status },
        });
        return res.json(updated);
    }
    catch (e) {
        console.error('updateChargingAgencyStatus error:', e);
        return res.status(500).json({ message: 'Server error' });
    }
};
exports.updateChargingAgencyStatus = updateChargingAgencyStatus;
//# sourceMappingURL=charging-agency.controller.js.map