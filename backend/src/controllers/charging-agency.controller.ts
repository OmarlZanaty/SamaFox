import { findBlockingMembership, ALREADY_IN_AGENCY_MESSAGE } from '../agencies/oneAgencyRule';
import { AgencyAccessError } from '../services/agencyIdentity.service';
import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { recordAgencySelfCharge } from '../services/agencyReward.service';
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

export const CHARGING_WALLETS_FROZEN_KEY = 'charging_wallets_frozen';
export class AgencyWalletError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export async function chargingWalletFrozen(tx: any, agencyId?: number): Promise<boolean> {
  // Read within the money transaction, without a process cache, so an admin
  // change is visible on the next request on every server instance.
  const setting = await tx.appSetting.findUnique({ where: { key: CHARGING_WALLETS_FROZEN_KEY } });
  const global = ['1', 'true', 'yes', 'on', 'frozen'].includes(String(setting?.value ?? '').trim().toLowerCase());
  const agency = agencyId ? await tx.chargingAgency.findUnique({ where: { id: agencyId } }) : null;
  return global || !!agency?.walletFrozen;
}

async function findChargingAgencyForAgent(userId: number) {
  const seat = await prisma.agencyMember.findFirst({
    where: { userId, role: { in: ['OWNER', 'BRANCH'] }, agency: { type: 'CHARGING', status: 'approved' } },
    orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }],
  });
  return seat ? { id: seat.agencyId, funderId: userId } : null;
}

export const chargingRecipient = async (req: Request, res: Response) => {
  if (!req.userId) return res.status(401).json({ message: 'Unauthorized' });
  const userId = Number(req.params.userId);
  if (!Number.isSafeInteger(userId) || userId <= 0) return res.status(400).json({ message: 'Invalid userId' });
  try {
    return res.json({ isChargingAgent: !!(await findChargingAgencyForAgent(userId)) });
  } catch {
    return res.status(500).json({ message: 'Server error' });
  }
};

// Shared by both sale endpoints and withdrawal. All balances and ledger rows
// change in the same transaction. Personal credits are capped atomically too.
export async function moveAgencyWallet(userId: number, toUserId: number, amount: number,
  _wallet: unknown = undefined, agencyId?: number, withdraw = false, note?: string) {
  if (!Number.isSafeInteger(amount) || amount <= 0 || amount > MAX_COINS_BALANCE ||
      !Number.isSafeInteger(toUserId) || toUserId <= 0 ||
      (agencyId !== undefined && (!Number.isSafeInteger(agencyId) || agencyId <= 0))) throw new AgencyWalletError(400, 'Invalid amount/userId/agencyId');
  if (!withdraw && userId === toUserId) throw new AgencyWalletError(400, 'Cannot charge yourself');
  return prisma.$transaction(async tx => {
    const seat = await tx.agencyMember.findFirst({
      where: { userId, ...(agencyId !== undefined ? { agencyId } : {}), role: { in: ['OWNER', 'BRANCH'] }, agency: { type: 'CHARGING', status: 'approved' } },
      orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }],
    });
    if (!seat) throw new AgencyWalletError(403, 'لست وكيل أو فرع في وكالة شحن معتمدة');
    if (await chargingWalletFrozen(tx, seat.agencyId)) throw new AgencyWalletError(403, 'رصيد الوكالة مجمّد من الإدارة');
    // Keep the legacy wallet argument for callers, but route sales by recipient eligibility only.
    const recipientSeat = !withdraw ? await tx.agencyMember.findFirst({
      where: { userId: toUserId, role: { in: ['OWNER', 'BRANCH'] }, agency: { type: 'CHARGING', status: 'approved' } },
      orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }, { id: 'asc' }],
    }) : null;
    const wallet = recipientSeat ? 'agency' : 'personal';
    const recipient = await tx.user.findUnique({ where: { id: toUserId }, select: { coinsBalance: true } });
    if (!recipient) throw new AgencyWalletError(404, 'Receiver user not found');
    const debit = await tx.agencyMember.updateMany({
      where: { id: seat.id, agencyWalletCoins: { gte: BigInt(amount) } },
      data: { agencyWalletCoins: { decrement: BigInt(amount) } },
    });
    if (!debit.count) {
      const current = await tx.agencyMember.findUniqueOrThrow({ where: { id: seat.id } });
      throw new AgencyWalletError(409, `رصيد الوكالة غير كافٍ — المتاح ${current.agencyWalletCoins} كوينز`);
    }
    let recipientAgencyWallet: string | undefined;
    if (recipientSeat) {
      const credited = await tx.agencyMember.update({ where: { id: recipientSeat.id }, data: { agencyWalletCoins: { increment: BigInt(amount) } } });
      recipientAgencyWallet = String(credited.agencyWalletCoins);
    } else {
      const credit = await tx.user.updateMany({
        where: { id: toUserId, coinsBalance: { lte: MAX_COINS_BALANCE - amount } },
        data: { coinsBalance: { increment: amount }, ...(!withdraw ? { totalRecharge: { increment: amount } } : {}) },
      });
      if (!credit.count) throw new AgencyWalletError(400, `Max coins limit is ${MAX_COINS_BALANCE}`);
    }
    if (!withdraw) await tx.chargingAgency.update({ where: { id: seat.agencyId }, data: { totalSentCoins: { increment: amount } } });
    const transaction = await tx.transaction.create({ data: {
      userId: toUserId, senderId: userId, agencyId: seat.agencyId, amountCoins: amount,
      type: withdraw ? 'AGENCY_WALLET_WITHDRAW' : recipientSeat ? 'AGENCY_WALLET_TRANSFER' : 'AGENCY_TOPUP', status: 'completed',
    } });
    const branch = await tx.agencyBranch.findUnique({ where: { parentAgencyId_ownerUserId: { parentAgencyId: seat.agencyId, ownerUserId: userId } } });
    const transfer = await tx.agencyTransfer.create({ data: {
      agencyId: seat.agencyId, toUserId, amount, actorUserId: userId,
      branchId: seat.role === 'BRANCH' ? branch?.id : null, transactionId: transaction.id,
      note: `${withdraw ? 'withdraw' : wallet}: ${note ?? ''}`,
    } });
    const sender = await tx.agencyMember.findUniqueOrThrow({ where: { id: seat.id } });
    const personal = await tx.user.findUniqueOrThrow({ where: { id: toUserId }, select: { coinsBalance: true } });
    return { agencyWalletCoins: String(sender.agencyWalletCoins), userBalance: String(personal.coinsBalance), recipientAgencyWalletCoins: recipientAgencyWallet, transferId: transfer.id, wallet };
  });
}

export async function adjustOwnerAgencyWallet(tx: any, agencyId: number, delta: number, adminId: number, note?: string) {
  if (!Number.isSafeInteger(delta) || delta === 0 || Math.abs(delta) > MAX_COINS_BALANCE) throw new AgencyWalletError(400, 'Invalid amount');
  const agency = await tx.chargingAgency.findUnique({ where: { id: agencyId } });
  if (!agency || agency.type !== 'CHARGING') throw new AgencyWalletError(404, 'Charging agency not found');
  const owner = await tx.agencyMember.findFirst({ where: { agencyId, role: 'OWNER' } }) ??
    await tx.agencyMember.upsert({ where: { agencyId_userId: { agencyId, userId: agency.userId } },
      create: { agencyId, userId: agency.userId, role: 'OWNER' }, update: { role: 'OWNER' } });
  const changed = await tx.agencyMember.updateMany({
    where: { id: owner.id, ...(delta < 0 ? { agencyWalletCoins: { gte: BigInt(-delta) } } : {}) },
    data: { agencyWalletCoins: { increment: BigInt(delta) } },
  });
  if (!changed.count) throw new AgencyWalletError(409, 'Balance cannot go negative');
  await tx.transaction.create({ data: { userId: owner.userId, senderId: adminId, agencyId, type: 'AGENCY_WALLET_ADJUST', amountCoins: delta, status: 'completed' } });
  const updated = await tx.agencyMember.findUniqueOrThrow({ where: { id: owner.id } });
  await tx.adminAuditLog.create({ data: { adminId, action: 'agency_wallet_adjust', targetType: 'agency', targetId: String(agencyId), reason: note,
    before: { agencyWalletCoins: String(BigInt(updated.agencyWalletCoins) - BigInt(delta)) }, after: { agencyWalletCoins: String(updated.agencyWalletCoins), delta } } });
  return { id: agencyId, balanceCoins: String(updated.agencyWalletCoins), agencyWalletCoins: String(updated.agencyWalletCoins), walletFrozen: agency.walletFrozen, status: agency.status };
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

    // 2026-08-23 — this used to be `where: { userId }`, i.e. the OWNER only.
    // A فرع therefore opened وكالة الشحن to an empty list and could not charge
    // anybody, which is the client's "فروع وكالة الشحن ... لا تعمل". Branch
    // memberships are included now; the funding wallet is still the caller's
    // own either way (see findChargingAgencyForAgent).
    const memberships = await prisma.agencyMember.findMany({
      where: {
        userId,
        role: { in: ['OWNER', 'BRANCH'] },
        agency: { type: 'CHARGING' },
      },
      select: { agencyId: true, role: true },
    });
    const roleByAgency = new Map<number, string>(
      memberships.map((m: any) => [m.agencyId, m.role]),
    );

    const items = await prisma.chargingAgency.findMany({
      where: {
        type: 'CHARGING',
        OR: [
          { userId },
          ...(roleByAgency.size ? [{ id: { in: [...roleByAgency.keys()] } }] : []),
        ],
      },
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

    // `myRole` lets the panel show a فرع the selling tools without the
    // owner-only ones (branch management, top-up requests).
    return res.json(
      items.map((a: any) => ({
        ...a,
        myRole: a.userId === userId ? 'OWNER' : roleByAgency.get(a.id) ?? 'BRANCH',
      })),
    );
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

export const myAgencyBalance = async (req: Request, res: Response) => {
  try {
    if (!req.userId) return res.status(401).json({ message: 'Unauthorized' });
    const seat = await prisma.agencyMember.findFirst({ where: { userId: req.userId, role: { in: ['OWNER', 'BRANCH'] }, agency: { type: 'CHARGING' } }, include: { agency: true }, orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }] });
    const personal = await prisma.user.findUnique({ where: { id: req.userId }, select: { coinsBalance: true } });
    const agency = seat?.agency ?? await prisma.chargingAgency.findFirst({ where: { userId: req.userId, type: 'CHARGING' }, orderBy: { createdAt: 'desc' } });
    const agencyWalletCoins = String(seat?.agencyWalletCoins ?? 0);
    return res.json({ id: agency?.id, agencyName: agency?.agencyName, status: agency?.status ?? 'none', balanceCoins: agencyWalletCoins, agencyWalletCoins, personalCoins: String(personal?.coinsBalance ?? 0), frozen: await chargingWalletFrozen(prisma, agency?.id) });
  } catch { return res.status(500).json({ message: 'Server error' }); }
};

export const withdrawAgencyWallet = async (req: Request, res: Response) => {
  try {
    if (!req.userId) return res.status(401).json({ message: 'Unauthorized' });
    const result = await moveAgencyWallet(req.userId, req.userId, Number(req.body?.amount), 'personal', req.body?.agencyId === undefined ? undefined : Number(req.body.agencyId), true);
    return res.json({ message: 'Withdrawal successful', agencyWalletCoins: result.agencyWalletCoins, personalCoins: result.userBalance, transferId: result.transferId });
  } catch (e) { return res.status(e instanceof AgencyWalletError ? e.status : 500).json({ message: e instanceof AgencyWalletError ? e.message : 'Server error' }); }
};

/**
 * GET /api/v1/charging-agencies/my/transfers
 * Agent transfer history
 */
export const myAgencyTransfers = async (req: Request, res: Response) => {
  try {
    const userId = getUserId(req);
    if (!userId) return res.status(401).json({ message: 'Unauthorized' });

    const agency = await findChargingAgencyForAgent(userId);

    if (!agency) return res.status(404).json({ message: 'No approved agency for this user' });

    // SPEC52 #36 — a branch sees only its own charges; the agency owner sees
    // all of them (optionally one branch with ?branchId=).
    const owner = await prisma.chargingAgency.findUnique({ where: { id: agency.id }, select: { userId: true } });
    const isOwner = owner?.userId === userId;
    const branchFilter = isOwner
      ? (req.query.branchId ? { branchId: Number(req.query.branchId) } : {})
      : { actorUserId: userId };
    const items = await prisma.agencyTransfer.findMany({
      where: { agencyId: agency.id, ...(branchFilter as any) },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        agencyId: true,
        toUserId: true,
        amount: true,
        note: true,
        createdAt: true,
        branchId: true,
        actorUserId: true,
        transactionId: true,
        toUser: { select: { id: true, name: true, avatarUrl: true } },
      } as any,
    });

    return res.json(items);
  } catch (e) {
    console.error('myAgencyTransfers error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};

export const agencyTransferCoins = async (req: Request, res: Response) => {
  try {
    if (!req.userId) return res.status(401).json({ message: 'Unauthorized' });
    const result = await moveAgencyWallet(req.userId, Number(req.body?.toUserId), Number(req.body?.amount), req.body?.wallet ?? 'personal', req.body?.agencyId === undefined ? undefined : Number(req.body.agencyId), false, req.body?.note);
    if (result.wallet === 'personal') { try { await evaluateVip(Number(req.body.toUserId)); } catch (e) { console.warn('evaluateVip failed:', e); } }
    return res.json({ message: 'Transfer successful', ...result, agencyBalance: result.agencyWalletCoins, senderBalance: result.agencyWalletCoins });
  } catch (e) { return res.status(e instanceof AgencyWalletError ? e.status : 500).json({ message: e instanceof AgencyWalletError ? e.message : 'Server error' }); }
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

    if (!Number.isSafeInteger(amount) || amount <= 0 || amount > MAX_COINS_BALANCE || !receiptUrl) {
      return res.status(400).json({ message: 'Invalid amount/receiptUrl' });
    }

    // Requests retain the requester for audit; approval funds the OWNER seat.
    const agency = await findChargingAgencyForAgent(userId);
    if (!agency) return res.status(403).json({ message: 'Not approved agency' });

    const reqRow = await prisma.agencyTopupRequest.create({
      data: {
        agencyId: agency.id,
        requesterId: userId,
        amount,
        receiptUrl,
        note,
        status: 'pending',
      },
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
          select: { id: true, agencyName: true, phoneNumber: true, userId: true, balanceCoins: true, walletFrozen: true, members: { where: { role: 'OWNER' }, select: { agencyWalletCoins: true }, take: 1 } },
        },
      },
    });

    return res.json(items.map((item: any) => ({ ...item, amount: item.amount?.toString?.() ?? item.amount, agency: item.agency ? { ...item.agency, balanceCoins: String(item.agency.members[0]?.agencyWalletCoins ?? 0), agencyWalletCoins: String(item.agency.members[0]?.agencyWalletCoins ?? 0), members: undefined } : null })));
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

    // Set inside the transaction, acted on after it commits — the reward ladder
    // must never be able to roll back an approved top-up.
    let chargedAgencyId = 0;
    let chargedAmount = 0;

    const result = await prisma.$transaction(async (tx) => {
      const request = await tx.agencyTopupRequest.findUnique({ where: { id: requestId } });
      if (!request) throw new AgencyWalletError(404, 'Topup request not found');

      if (request.status !== 'pending') {
        return { ok: false as const, reason: 'already_processed' as const };
      }

      const claimed = await tx.agencyTopupRequest.updateMany({ where: { id: requestId, status: 'pending' }, data: { status, reviewedBy: adminId, reviewedAt: new Date() } });
      if (!claimed.count) return { ok: false as const, reason: 'already_processed' as const };
      if (status === 'approved') {
        await adjustOwnerAgencyWallet(tx, request.agencyId, request.amount, adminId, `Topup request ${requestId}`);
        chargedAgencyId = request.agencyId;
        chargedAmount = request.amount;
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

    // Counts as a self-charge (B10) and pays any reward rung crossed (B11).
    if (chargedAgencyId) await recordAgencySelfCharge(chargedAgencyId, chargedAmount);
    return res.json({ message: 'Topup reviewed', request: result.updated });
  } catch (e) {
    if (e instanceof AgencyWalletError) return res.status(e.status).json({ message: e.message });
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
    if (!Number.isSafeInteger(agencyId) || agencyId <= 0 || !Number.isSafeInteger(delta) || delta === 0 || Math.abs(delta) > MAX_COINS_BALANCE) {
      return res.status(400).json({ message: 'Invalid agencyId/delta' });
    }
    const agency = await prisma.$transaction(async tx => {
      const updated = await adjustOwnerAgencyWallet(tx, agencyId, delta, adminId, req.body?.note);
      if (delta > 0) await tx.chargingAgency.update({ where: { id: agencyId }, data: { totalTopupCoins: { increment: delta } } });
      return updated;
    });
    return res.json({ message: 'Agency balance updated', agency });
  } catch (e) {
    if (e instanceof AgencyWalletError) return res.status(e.status).json({ message: e.message });
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

    const updated = await prisma.$transaction(async (tx) => {
      const agency = await tx.chargingAgency.update({
        where: { id },
        data: { status },
      });
      // The OWNER AgencyMember row is what every owner-gated feature checks
      // (branches/فروع, شحن مستخدم, members roster). Approving without it left
      // the agent locked out of his own agency, so create it here too — the
      // dashboard's own approve path does the same.
      if (status === 'approved') {
        const existingMember = await tx.agencyMember.findUnique({
          where: { agencyId_userId: { agencyId: agency.id, userId: agency.userId } },
        });
        if (!existingMember && await findBlockingMembership(tx, agency.userId, agency.id, 'OWNER')) {
          throw new AgencyAccessError(409, ALREADY_IN_AGENCY_MESSAGE, 'ALREADY_IN_AGENCY');
        }
        await tx.agencyMember.upsert({
          where: { agencyId_userId: { agencyId: agency.id, userId: agency.userId } },
          update: { role: 'OWNER' },
          create: { agencyId: agency.id, userId: agency.userId, role: 'OWNER' },
        });
      }
      return agency;
    });

    return res.json(updated);
  } catch (e) {
    if (e instanceof AgencyAccessError) return res.status(e.status).json({ success: false, code: e.code, message: e.message });
    console.error('updateChargingAgencyStatus error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};
