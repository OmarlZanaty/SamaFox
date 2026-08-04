import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { MAX_COINS_BALANCE } from '../utils/coins';
import { evaluateVip } from '../services/vip.service';

// Helper: get authed userId
function getUserId(req: Request): number | null {
  return typeof req.userId === 'number' ? req.userId : null;
}

const AGENCY_STATUS = {
  PENDING: 'pending',
  APPROVED: 'approved',
  REJECTED: 'rejected',
} as const;

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
    const type = typeof req.query.type === 'string' ? req.query.type.toUpperCase() : null;
    const where: any = { status };
    if (type === 'CHARGING' || type === 'HOSTING') where.type = type;

    const items = await prisma.chargingAgency.findMany({
      where,
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
        type: true,
        contactInfo: true,
        targetCoins: true,
        earnedCoins: true,
        createdAt: true,
      },
    });

    return res.json(items.map((item: any) => ({ ...item, balanceCoins: item.balanceCoins?.toString?.() ?? item.balanceCoins, totalSentCoins: item.totalSentCoins?.toString?.() ?? item.totalSentCoins, totalTopupCoins: item.totalTopupCoins?.toString?.() ?? item.totalTopupCoins })));
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
    const agencyTypeRaw = typeof (req.body as any)?.type === 'string' ? String((req.body as any).type).toUpperCase() : 'CHARGING';
    const agencyType = agencyTypeRaw === 'HOSTING' ? 'HOSTING' : 'CHARGING';

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
        type: agencyType,
        contactInfo: String(phoneNumber).trim(),
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
        type: true,
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

  // Scoped to type:'CHARGING' — a user who also owns a HOSTING agency must
  // not have that one picked up here (dual-owner bug, see agency.controller.ts).
  const agency = await prisma.chargingAgency.findFirst({
    where: { userId, type: 'CHARGING' }, // ✅ remove approved filter
    select: { id: true, balanceCoins: true, agencyName: true, status: true },
    orderBy: { createdAt: 'desc' },
  });

  if (!agency) return res.json({ balanceCoins: "0", status: 'none' });

  return res.json({ ...agency, balanceCoins: agency.balanceCoins.toString() });
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
      where: { userId, status: 'approved', type: 'CHARGING' },
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
 * ✅ Atomic: decrement the AGENT'S OWN wallet, increment user.coinsBalance,
 * create AgencyTransfer. The agency no longer holds a separate coin pot — see
 * agency.controller.ts sendCoinsToUser for the same change on the app's path.
 */
export const agencyTransferCoins = async (req: Request, res: Response) => {
  const userId = getUserId(req);
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const toUserId = Number((req.body as any)?.toUserId);
  const amount = Number((req.body as any)?.amount);
  const amountBig = BigInt(amount || 0);
  const note = (req.body as any)?.note ? String((req.body as any).note) : null;

  if (!toUserId || !amount || amountBig <= BigInt(0)) {
    return res.status(400).json({ message: 'Invalid toUserId/amount' });
  }

  const agency = await prisma.chargingAgency.findFirst({
    where: { userId, status: 'approved', type: 'CHARGING' },
    select: { id: true },
  });

  if (!agency) return res.status(403).json({ message: 'You are not an approved agency' });

  const receiver = await prisma.user.findUnique({
    where: { id: toUserId },
    select: { id: true },
  });

  if (!receiver) return res.status(404).json({ message: 'Receiver user not found' });

  if (toUserId === userId) return res.status(400).json({ message: 'Cannot charge yourself' });

  try {
    type TransferTxResult =
      | { ok: false; reason: 'insufficient_balance'; available: bigint }
      | {
          ok: true;
          senderBalance: bigint;
          updatedUser: { id: number; coinsBalance: bigint };
          transfer: { id: number };
        };

    const result: TransferTxResult = await prisma.$transaction(async (tx) => {
      const receiverNow = await tx.user.findUnique({
        where: { id: toUserId },
        select: { coinsBalance: true },
      });
      if (!receiverNow) throw new Error('receiver_missing');
      if (BigInt(receiverNow.coinsBalance) + BigInt(amount) > BigInt(MAX_COINS_BALANCE)) {
        throw new Error('coins_overflow');
      }

      // Debit the agent's own wallet. The `gte` guard makes the check and the
      // debit one statement so concurrent charges can't drive it negative.
      const debited = await tx.user.updateMany({
        where: { id: userId, coinsBalance: { gte: Number(BigInt(amount)) } },
        data: { coinsBalance: { decrement: Number(BigInt(amount)) } },
      });
      if (debited.count === 0) {
        const wallet = await tx.user.findUnique({
          where: { id: userId },
          select: { coinsBalance: true },
        });
        return {
          ok: false as const,
          reason: 'insufficient_balance' as const,
          available: BigInt(wallet?.coinsBalance ?? 0),
        };
      }

      const senderNow = await tx.user.findUnique({
        where: { id: userId },
        select: { coinsBalance: true },
      });

      // Kept as a lifetime stat only — it is no longer a funding source.
      await tx.chargingAgency.update({
        where: { id: agency.id },
        data: { totalSentCoins: { increment: Number(BigInt(amount)) } },
      });

      const updatedUserDb = await tx.user.update({
        where: { id: toUserId },
        data: {
          coinsBalance: { increment: Number(BigInt(amount)) },
          totalRecharge: { increment: Number(BigInt(amount)) },
        },
        select: { id: true, coinsBalance: true },
      });

      const updatedUser = { id: updatedUserDb.id, coinsBalance: BigInt(updatedUserDb.coinsBalance) };

      const transfer = await tx.agencyTransfer.create({
        data: { agencyId: agency.id, toUserId, amount: Number(BigInt(amount)), note },
        select: { id: true },
      });

      return {
        ok: true as const,
        senderBalance: BigInt(senderNow?.coinsBalance ?? 0),
        updatedUser,
        transfer,
      };
    });

    if (result.ok === false) {
      return res.status(409).json({
        message: `رصيد محفظتك غير كافٍ — المتاح ${result.available.toString()} كوينز`,
      });
    }

    // Top-up counts toward VIP — re-evaluate after the transfer commits.
    try { await evaluateVip(toUserId); } catch (e) { console.warn('evaluateVip failed:', e); }

    return res.json({
      message: 'Transfer successful',
      // `agencyBalance` is kept in the response shape for old clients, but it
      // now reports the agent's wallet — the only balance a charge touches.
      agencyBalance: result.senderBalance.toString(),
      senderBalance: result.senderBalance.toString(),
      userBalance: result.updatedUser.coinsBalance.toString(),
      transferId: result.transfer.id,
    });
  } catch (e) {
    if ((e as Error)?.message === 'coins_overflow') {
      return res.status(400).json({ message: `Max coins limit is ${MAX_COINS_BALANCE}` });
    }
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
  const amountBig = BigInt(amount || 0);
    const receiptUrl = (req.body as any)?.receiptUrl ? String((req.body as any).receiptUrl) : null;
    const note = (req.body as any)?.note ? String((req.body as any).note) : null;

    if (!amount || amount <= 0 || !receiptUrl) {
      return res.status(400).json({ message: 'Invalid amount/receiptUrl' });
    }

    const agency = await prisma.chargingAgency.findFirst({
      where: { userId, status: 'approved', type: 'CHARGING' },
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
      where: { userId, type: 'CHARGING' },
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

    return res.json(items.map((item: any) => ({ ...item, amount: item.amount?.toString?.() ?? item.amount, agency: item.agency ? { ...item.agency, balanceCoins: item.agency.balanceCoins?.toString?.() ?? item.agency.balanceCoins } : null })));
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
        // Charges are paid out of the agent's own wallet now, so an approved
        // top-up has to land THERE. Crediting the agency pot left the agent
        // with an approved request and still no coins to charge anyone with.
        const agency = await tx.chargingAgency.update({
          where: { id: request.agencyId },
          data: { totalTopupCoins: { increment: request.amount } },
          select: { userId: true },
        });

        await tx.user.update({
          where: { id: agency.userId },
          data: { coinsBalance: { increment: request.amount } },
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
    const deltaBig = BigInt(Math.trunc(delta || 0));

    if (!agencyId || !Number.isFinite(delta) || deltaBig === BigInt(0)) {
      return res.status(400).json({ message: 'Invalid agencyId/delta' });
    }

    const result = await prisma.$transaction(async (tx) => {
      const agency = await tx.chargingAgency.findUnique({
        where: { id: agencyId },
        select: { balanceCoins: true },
      });
      if (!agency) throw new Error('agency_not_found');

      const newBal = BigInt(agency.balanceCoins) + deltaBig;
      if (newBal < BigInt(0)) return { ok: false as const };

      const updated = await tx.chargingAgency.update({
        where: { id: agencyId },
        data: {
          balanceCoins: deltaBig > BigInt(0) ? { increment: Number(deltaBig) } : { decrement: Number(deltaBig * BigInt(-1)) },
          totalTopupCoins: deltaBig > BigInt(0) ? { increment: Number(deltaBig) } : undefined,
        },
        select: { id: true, balanceCoins: true, status: true },
      });

      return { ok: true as const, updated };
    });

    if (result.ok === false) return res.status(409).json({ message: 'Balance cannot go negative' });

    return res.json({ message: 'Agency balance updated', agency: { ...result.updated, balanceCoins: result.updated.balanceCoins.toString() } });
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
