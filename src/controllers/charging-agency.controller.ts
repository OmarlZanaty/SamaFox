import { Request, Response } from 'express';
import prisma from '../utils/prisma';

// Helper: get authed userId
function getUserId(req: Request): number | null {
  return typeof req.userId === 'number' ? req.userId : null;
}

// Helper: admin check
async function assertAdmin(userId: number) {
  const u = await prisma.user.findUnique({
    where: { id: userId },
    select: { isAdmin: true },
  });
  return !!u?.isAdmin;
}

/**
 * GET /api/v1/charging-agencies?status=approved
 * Public list by status
 * Returns raw array (Flutter expects List)
 */
export const listChargingAgencies = async (req: Request, res: Response) => {
  try {
    const status = (req.query.status as string) || 'approved';

    const items = await prisma.chargingAgency.findMany({
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
  } catch (e) {
    console.error('listChargingAgencies error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * GET /api/v1/charging-agencies/me
 * My agency requests
 */
export async function myChargingAgencies(req: Request, res: Response) {
    try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const items = await prisma.chargingAgency.findMany({
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
  } catch (e) {
    console.error('myChargingAgencies error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * POST /api/v1/charging-agencies
 * Create agency request (pending)
 */
export const createChargingAgency = async (req: Request, res: Response) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const { agencyName, phoneNumber, agencyImageUrl, idFrontUrl, idBackUrl } = req.body as any;

    if (!agencyName || !phoneNumber || !agencyImageUrl || !idFrontUrl || !idBackUrl) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    // Prevent multiple pending requests
    const existingPending = await prisma.chargingAgency.findFirst({
      where: { userId, status: 'pending' },
      select: { id: true },
    });

    if (existingPending) {
      return res.status(409).json({ message: 'You already have a pending request' });
    }

    const created = await prisma.chargingAgency.create({
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
  } catch (e) {
    console.error('createChargingAgency error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * GET /api/v1/charging-agencies/my/balance
 * Agent wallet balance (approved agency only)
 */
export const myAgencyBalance = async (req: any, res: Response) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const agency = await prisma.chargingAgency.findFirst({
    where: { userId }, // ✅ remove approved filter
    select: { id: true, balanceCoins: true, agencyName: true, status: true },
    orderBy: { createdAt: 'desc' },
  });

  if (!agency) return res.json({ balanceCoins: 0, status: 'none' });

  return res.json(agency);
};


/**
 * GET /api/v1/charging-agencies/my/transfers
 * Agent transfer history
 */
export const myAgencyTransfers = async (req: Request, res: Response) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const agency = await prisma.chargingAgency.findFirst({
      where: { userId, status: 'approved' },
      select: { id: true },
    });

    if (!agency) return res.status(404).json({ message: 'No approved agency for this user' });

    const items = await prisma.agencyTransfer.findMany({
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
  } catch (e) {
    console.error('myAgencyTransfers error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * POST /api/v1/charging-agencies/transfer
 * Body: { toUserId:number, amount:number, note?:string }
 * ✅ Atomic: decrement agency balance, increment user.coinsBalance, create AgencyTransfer
 */
export const agencyTransferCoins = async (req: Request, res: Response) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const toUserId = Number((req.body as any)?.toUserId);
  const amount = Number((req.body as any)?.amount);
  const note = (req.body as any)?.note ? String((req.body as any).note) : null;

  if (!toUserId || !amount || amount <= 0) {
    return res.status(400).json({ message: 'Invalid toUserId/amount' });
  }

  const agency = await prisma.chargingAgency.findFirst({
    where: { userId, status: 'approved' },
    select: { id: true },
  });

  if (!agency) return res.status(403).json({ message: 'You are not an approved agency' });

  const receiver = await prisma.user.findUnique({
    where: { id: toUserId },
    select: { id: true },
  });

  if (!receiver) return res.status(404).json({ message: 'Receiver user not found' });

  try {
    type TransferTxResult =
      | { ok: false; reason: 'insufficient_balance' }
      | {
          ok: true;
          updatedAgency: { id: number; balanceCoins: number };
          updatedUser: { id: number; coinsBalance: number };
          transfer: { id: number };
        };

    const result: TransferTxResult = await prisma.$transaction(async (tx) => {
      const agencyNow = await tx.chargingAgency.findUnique({
        where: { id: agency.id },
        select: { balanceCoins: true },
      });

      if (!agencyNow) throw new Error('agency_missing');

      if (agencyNow.balanceCoins < amount) {
        return { ok: false as const, reason: 'insufficient_balance' as const };
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

      return { ok: true as const, updatedAgency, updatedUser, transfer };
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
  } catch (e) {
    console.error('agencyTransferCoins error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * POST /api/v1/charging-agencies/topup
 * Agent submits topup request (pending)
 * Body: { amount:number, receiptUrl:string, note?:string }
 */
export const createTopupRequest = async (req: Request, res: Response) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const amount = Number((req.body as any)?.amount);
    const receiptUrl = (req.body as any)?.receiptUrl ? String((req.body as any).receiptUrl) : null;
    const note = (req.body as any)?.note ? String((req.body as any).note) : null;

    if (!amount || amount <= 0 || !receiptUrl) {
      return res.status(400).json({ message: 'Invalid amount/receiptUrl' });
    }

    const agency = await prisma.chargingAgency.findFirst({
      where: { userId, status: 'approved' },
      select: { id: true },
    });

    if (!agency) return res.status(403).json({ message: 'Not approved agency' });

    const reqRow = await prisma.agencyTopupRequest.create({
      data: { agencyId: agency.id, amount, receiptUrl, note, status: 'pending' },
    });

    return res.status(201).json(reqRow);
  } catch (e) {
    console.error('createTopupRequest error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * GET /api/v1/charging-agencies/my/topups
 */
export const myTopupRequests = async (req: Request, res: Response) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const agency = await prisma.chargingAgency.findFirst({
      where: { userId },
      select: { id: true },
    });

    if (!agency) return res.status(404).json({ message: 'No agency found' });

    const items = await prisma.agencyTopupRequest.findMany({
      where: { agencyId: agency.id },
      orderBy: { createdAt: 'desc' },
    });

    return res.json(items);
  } catch (e) {
    console.error('myTopupRequests error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * ADMIN: GET /api/v1/charging-agencies/admin/topups?status=pending
 */
export const adminListTopups = async (req: Request, res: Response) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const isAdmin = await assertAdmin(userId);
    if (!isAdmin) return res.status(403).json({ message: 'Admin only' });

    const status = ((req.query.status as string) || 'pending').toLowerCase();

    const items = await prisma.agencyTopupRequest.findMany({
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
  } catch (e) {
    console.error('adminListTopups error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * ADMIN: PATCH /api/v1/charging-agencies/topup/:id/review
 * Body: { status: "approved" | "rejected" }
 * If approved => increments agency balance
 */
export const reviewTopupRequest = async (req: Request, res: Response) => {
  try {
    const adminId = getUserId(req);
    if (!adminId) return res.status(401).json({ message: 'Unauthorized' });

    const isAdmin = await assertAdmin(adminId);
    if (!isAdmin) return res.status(403).json({ message: 'Admin only' });

    const requestId = Number(req.params.id);
    const status = String((req.body as any)?.status || '');

    if (!requestId || !['approved', 'rejected'].includes(status)) {
      return res.status(400).json({ message: 'Invalid id/status' });
    }

    const result = await prisma.$transaction(async (tx) => {
      const request = await tx.agencyTopupRequest.findUnique({ where: { id: requestId } });
      if (!request) throw new Error('not_found');

      if (request.status !== 'pending') {
        return { ok: false as const, reason: 'already_processed' as const };
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

      return { ok: true as const, updated };
    });

    if (result.ok === false) {
      return res.status(409).json({ message: 'Already processed' });
    }

    return res.json({ message: 'Topup reviewed', request: result.updated });
  } catch (e) {
    console.error('reviewTopupRequest error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * ADMIN: PATCH /api/v1/charging-agencies/:id/balance
 * Body: { delta:number, note?:string }
 */
export const adminAdjustAgencyBalance = async (req: Request, res: Response) => {
  try {
    const adminId = getUserId(req);
    if (!adminId) return res.status(401).json({ message: 'Unauthorized' });

    const isAdmin = await assertAdmin(adminId);
    if (!isAdmin) return res.status(403).json({ message: 'Admin only' });

    const agencyId = Number(req.params.id);
    const delta = Number((req.body as any)?.delta);

    if (!agencyId || !Number.isFinite(delta) || delta === 0) {
      return res.status(400).json({ message: 'Invalid agencyId/delta' });
    }

    const result = await prisma.$transaction(async (tx) => {
      const agency = await tx.chargingAgency.findUnique({
        where: { id: agencyId },
        select: { balanceCoins: true },
      });
      if (!agency) throw new Error('agency_not_found');

      const newBal = agency.balanceCoins + delta;
      if (newBal < 0) return { ok: false as const };

      const updated = await tx.chargingAgency.update({
        where: { id: agencyId },
        data: {
          balanceCoins: delta > 0 ? { increment: delta } : { decrement: Math.abs(delta) },
          totalTopupCoins: delta > 0 ? { increment: delta } : undefined,
        },
        select: { id: true, balanceCoins: true, status: true },
      });

      return { ok: true as const, updated };
    });

    if (result.ok === false) return res.status(409).json({ message: 'Balance cannot go negative' });

    return res.json({ message: 'Agency balance updated', agency: result.updated });
  } catch (e) {
    console.error('adminAdjustAgencyBalance error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

/**
 * ADMIN: PATCH /api/v1/charging-agencies/:id/status
 * Body: { status: "pending" | "approved" | "rejected" }
 */
export const updateChargingAgencyStatus = async (req: Request, res: Response) => {
  try {
    const adminId = getUserId(req);
    if (!adminId) return res.status(401).json({ message: 'Unauthorized' });

    const isAdmin = await assertAdmin(adminId);
    if (!isAdmin) return res.status(403).json({ message: 'Admin only' });

    const id = Number(req.params.id);
    const status = String((req.body as any)?.status || '');

    if (!id || !['pending', 'approved', 'rejected'].includes(status)) {
      return res.status(400).json({ message: 'Invalid id/status' });
    }

    const updated = await prisma.chargingAgency.update({
      where: { id },
      data: { status },
    });

    return res.json(updated);
  } catch (e) {
    console.error('updateChargingAgencyStatus error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};
