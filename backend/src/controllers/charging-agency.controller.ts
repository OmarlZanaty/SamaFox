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

/**
 * The approved CHARGING agency this user may act for — as its OWNER **or** as a
 * فرع (BRANCH). These endpoints used to match on `ChargingAgency.userId`, i.e.
 * the owner only, so a branch got "You are not an approved agency" on every
 * charge and an empty transfer history. Branches have the same day-to-day
 * selling rights as the owner (see agency.controller.ts sendCoinsToUser).
 */
async function findChargingAgencyForAgent(userId: number) {
  const membership = await prisma.agencyMember.findFirst({
    where: {
      userId,
      role: { in: ['OWNER', 'BRANCH'] },
      agency: { status: AGENCY_STATUS.APPROVED, type: 'CHARGING' },
    },
    select: { agencyId: true, role: true },
    // Owner rows before branch rows, so acting for your OWN agency wins.
    orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }],
  });

  // `funderId` is always the caller: owner and فرع each sell from their OWN
  // wallet (client rule — a branch is topped up personally and spends what he
  // holds; the owner's wallet is never debited by a branch's sale).
  if (membership) return { id: membership.agencyId, funderId: userId };

  // Fallback for an agency approved before the OWNER membership row existed.
  const owned = await prisma.chargingAgency.findFirst({
    where: { userId, status: AGENCY_STATUS.APPROVED, type: 'CHARGING' },
    select: { id: true },
  });
  return owned ? { id: owned.id, funderId: userId } : null;
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

/**
 * GET /api/v1/charging-agencies/my/balance
 * The coins the caller can charge with. There is no separate agency pot (client
 * rule 2026-08) — everyone sells from his OWN wallet, owner and فرع alike, so
 * this is simply the caller's balance.
 */
export const myAgencyBalance = async (req: any, res: Response) => {
  const userId = req.userId;
  if (!userId) return res.status(401).json({ message: 'Unauthorized' });

  const funder = await findChargingAgencyForAgent(userId);
  const walletOwnerId = funder?.funderId ?? userId;

  const me = await prisma.user.findUnique({
    where: { id: walletOwnerId },
    select: { coinsBalance: true },
  });
  const balanceCoins = String(me?.coinsBalance ?? 0);

  // Scoped to type:'CHARGING' — a user who also owns a HOSTING agency must
  // not have that one picked up here (dual-owner bug, see agency.controller.ts).
  // A فرع owns no agency row, so fall back to the agency he is a branch of;
  // otherwise he was told status:'none' while he could charge perfectly well.
  const agency =
    (await prisma.chargingAgency.findFirst({
      where: { userId, type: 'CHARGING' }, // ✅ remove approved filter
      select: { id: true, agencyName: true, status: true },
      orderBy: { createdAt: 'desc' },
    })) ??
    (
      await prisma.agencyMember.findFirst({
        where: {
          userId,
          role: 'BRANCH',
          agency: { status: AGENCY_STATUS.APPROVED, type: 'CHARGING' },
        },
        select: { agency: { select: { id: true, agencyName: true, status: true } } },
        orderBy: { joinedAt: 'asc' },
      })
    )?.agency;

  if (!agency) return res.json({ balanceCoins, status: 'none' });

  return res.json({ ...agency, balanceCoins });
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

  const agency = await findChargingAgencyForAgent(userId);

  if (!agency) return res.status(403).json({ message: 'لست وكيل أو فرع في وكالة شحن معتمدة' });

  const receiver = await prisma.user.findUnique({
    where: { id: toUserId },
    select: { id: true },
  });

  if (!receiver) return res.status(404).json({ message: 'Receiver user not found' });

  if (toUserId === userId) return res.status(400).json({ message: 'Cannot charge yourself' });
  // Whose wallet pays: the seller's own, فرع included.
  const funderId = agency.funderId;

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

      // Debit the agent's wallet. The `gte` guard makes the check and the
      // debit one statement so concurrent charges can't drive it negative.
      const debited = await tx.user.updateMany({
        where: { id: funderId, coinsBalance: { gte: Number(BigInt(amount)) } },
        data: { coinsBalance: { decrement: Number(BigInt(amount)) } },
      });
      if (debited.count === 0) {
        const wallet = await tx.user.findUnique({
          where: { id: funderId },
          select: { coinsBalance: true },
        });
        return {
          ok: false as const,
          reason: 'insufficient_balance' as const,
          available: BigInt(wallet?.coinsBalance ?? 0),
        };
      }

      const senderNow = await tx.user.findUnique({
        where: { id: funderId },
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

    // Set inside the transaction, acted on after it commits — the reward ladder
    // must never be able to roll back an approved top-up.
    let chargedAgencyId = 0;
    let chargedAmount = 0;

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
        const agency = await tx.chargingAgency.findUniqueOrThrow({
          where: { id: request.agencyId },
          select: { userId: true },
        });

        await tx.user.update({
          where: { id: agency.userId },
          data: { coinsBalance: { increment: request.amount } },
        });
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
    console.error('updateChargingAgencyStatus error:', e);
    return res.status(500).json({ message: 'Server error' });
  }
};
