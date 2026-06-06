import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { evaluateVip } from '../services/vip.service';

const db = prisma as any;

type AuthReq = Request & { userId?: number };

const fail = (res: Response, status: number, message: string) =>
  res.status(status).json({ success: false, message });

const serializeBigInt = <T>(value: T): T => {
  if (typeof value === 'bigint') return value.toString() as unknown as T;
  if (Array.isArray(value)) return value.map((v) => serializeBigInt(v)) as unknown as T;
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([k, v]) => [k, serializeBigInt(v)]),
    ) as T;
  }
  return value;
};

// POST /agencies/request
export const requestAgency = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const { type, agencyName, imageUrl, contactInfo } = req.body as {
      type?: string;
      agencyName?: string;
      imageUrl?: string;
      contactInfo?: string;
    };

    if (!type || !agencyName) return fail(res, 400, 'type and agencyName required');
    if (!['CHARGING', 'HOSTING'].includes(type)) return fail(res, 400, 'type must be CHARGING or HOSTING');

    const pending = await db.agencyRequest.findFirst({ where: { userId, type, status: 'pending' } });
    if (pending) return fail(res, 400, 'You already have a pending request');

    const request = await db.agencyRequest.create({
      data: {
        userId,
        type,
        agencyName,
        imageUrl: imageUrl ?? null,
        contactInfo: contactInfo ?? null,
      },
    });

    return res.status(201).json({ success: true, data: request });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/charging
export const listChargingAgencies = async (_req: Request, res: Response) => {
  try {
    const agencies = await db.chargingAgency.findMany({
      where: { type: 'CHARGING', status: 'approved' },
      select: {
        id: true,
        agencyName: true,
        logoUrl: true,
        contactInfo: true,
        members: {
          where: { role: 'OWNER' },
          include: { user: { select: { id: true, name: true, avatarUrl: true } } },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return res.json({ success: true, data: agencies });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/hosting
export const listHostingAgencies = async (_req: Request, res: Response) => {
  try {
    const agencies = await db.chargingAgency.findMany({
      where: { type: 'HOSTING', status: 'approved' },
      include: { members: { include: { user: { select: { id: true, name: true, avatarUrl: true } } } } },
      orderBy: { createdAt: 'desc' },
    });

    return res.json({
      success: true,
      data: agencies.map((a: any) => ({
        id: a.id,
        agencyName: a.agencyName,
        logoUrl: a.logoUrl,
        imageUrl: a.agencyImageUrl,
        targetCoins: a.targetCoins.toString(),
        earnedCoins: a.earnedCoins.toString(),
        memberCount: a.members.length,
        progress:
          a.targetCoins > 0n
            ? Math.min(100, Math.round(Number((a.earnedCoins * 100n) / a.targetCoins)))
            : 0,
        members: a.members.map((m: any) => m.user),
      })),
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/my-agency
export const getMyAgency = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const m = await db.agencyMember.findFirst({
      where: { userId, role: 'OWNER' },
      include: {
        agency: {
          include: {
            members: {
              include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true } } },
            },
          },
        },
      },
    });

    if (!m) return fail(res, 404, 'No agency found');

    return res.json({ success: true, data: serializeBigInt(m.agency) });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/send-coins
export const sendCoinsToUser = async (req: AuthReq, res: Response) => {
  try {
    const senderId = req.userId;
    if (!senderId) return fail(res, 401, 'Unauthorized');

    const { userId, amount } = req.body as { userId?: number | string; amount?: number | string };
    const targetUserId = Number(userId);
    const coins = Number(amount);

    if (!targetUserId || !Number.isFinite(coins) || coins <= 0) {
      return fail(res, 400, 'userId and positive amount required');
    }

    const membership = await db.agencyMember.findFirst({
      where: { userId: senderId, role: 'OWNER' },
      include: { agency: true },
    });

    if (!membership) return fail(res, 403, 'Not an agency owner');
    if (membership.agency.type !== 'CHARGING') return fail(res, 403, 'Only charging agencies can send coins');

    try {
      await db.$transaction(async (tx: any) => {
        const agency = await tx.chargingAgency.findUnique({ where: { id: membership.agencyId } });
        if (!agency || agency.balanceCoins < coins) throw new Error('INSUFFICIENT_AGENCY_BALANCE');

        await tx.chargingAgency.update({
          where: { id: agency.id },
          data: { balanceCoins: { decrement: coins }, totalSentCoins: { increment: coins } },
        });

        await tx.user.update({
          where: { id: targetUserId },
          data: { coinsBalance: { increment: coins }, totalRecharge: { increment: coins } },
        });

        await tx.transaction.create({
          data: {
            userId: targetUserId,
            type: 'AGENCY_TOPUP',
            amountCoins: coins,
            description: `من وكالة ${agency.agencyName}`,
          },
        });
      });

      // Top-up counts toward VIP — re-evaluate after the transfer commits.
      try { await evaluateVip(targetUserId); } catch (e) { console.warn('evaluateVip failed:', e); }
    } catch (e: any) {
      if (e?.message === 'INSUFFICIENT_AGENCY_BALANCE') {
        return fail(res, 400, 'INSUFFICIENT_AGENCY_BALANCE');
      }
      throw e;
    }

    return res.json({ success: true, message: 'Coins sent successfully' });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/invite/:userId
export const inviteMember = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');

    const inviteeId = Number(req.params.userId);
    if (!inviteeId) return fail(res, 400, 'Invalid userId');

    const m = await db.agencyMember.findFirst({ where: { userId: ownerId, role: 'OWNER' } });
    if (!m) return fail(res, 403, 'Not an agency owner');

    const existing = await db.agencyInvite.findFirst({
      where: { agencyId: m.agencyId, inviteeId, status: 'pending' },
    });
    if (existing) return fail(res, 400, 'Already invited');

    const invite = await db.agencyInvite.create({
      data: { agencyId: m.agencyId, inviterId: ownerId, inviteeId },
    });

    return res.status(201).json({ success: true, data: invite });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/invite/:inviteId/respond
export const respondInvite = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const inviteId = Number(req.params.inviteId);
    const { action } = req.body as { action?: string };

    if (!['accept', 'reject'].includes(String(action))) return fail(res, 400, 'action must be accept or reject');

    const invite = await db.agencyInvite.findUnique({ where: { id: inviteId } });
    if (!invite || invite.inviteeId !== userId) return fail(res, 403, 'Not your invite');
    if (invite.status !== 'pending') return fail(res, 400, 'Already processed');

    await db.$transaction(async (tx: any) => {
      await tx.agencyInvite.update({
        where: { id: inviteId },
        data: { status: action === 'accept' ? 'accepted' : 'rejected' },
      });

      if (action === 'accept') {
        await tx.agencyMember.upsert({
          where: { agencyId_userId: { agencyId: invite.agencyId, userId } },
          update: { role: 'MEMBER' },
          create: { agencyId: invite.agencyId, userId, role: 'MEMBER' },
        });
      }
    });

    return res.json({ success: true });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/:agencyId/join-request
export const requestJoinHostingAgency = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const agencyId = Number(req.params.agencyId);
    if (!agencyId) return fail(res, 400, 'Invalid agencyId');

    const agency = await db.chargingAgency.findUnique({
      where: { id: agencyId },
      select: { id: true, userId: true, type: true, status: true },
    });
    if (!agency || agency.type !== 'HOSTING' || agency.status !== 'approved') {
      return fail(res, 404, 'Hosting agency not found');
    }
    if (agency.userId === userId) return fail(res, 400, 'Owner cannot request join');

    const alreadyMember = await db.agencyMember.findFirst({ where: { agencyId, userId } });
    if (alreadyMember) return fail(res, 400, 'Already a member');

    const existing = await db.agencyInvite.findFirst({
      where: { agencyId, inviteeId: userId, status: 'pending' },
      select: { id: true },
    });
    if (existing) return fail(res, 400, 'Request already pending');

    const invite = await db.agencyInvite.create({
      data: { agencyId, inviterId: agency.userId, inviteeId: userId, status: 'pending' },
    });

    return res.status(201).json({ success: true, data: invite });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/join-requests/my-agency
export const listMyAgencyJoinRequests = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const ownerMembership = await db.agencyMember.findFirst({
      where: { userId, role: 'OWNER' },
      include: { agency: { select: { id: true, type: true } } },
    });
    if (!ownerMembership || ownerMembership.agency.type !== 'HOSTING') {
      return fail(res, 403, 'Not a hosting agency owner');
    }

    const items = await db.agencyInvite.findMany({
      where: { agencyId: ownerMembership.agencyId, inviterId: userId, status: 'pending' },
      orderBy: { createdAt: 'desc' },
      include: {
        agency: { select: { id: true, agencyName: true } },
      },
    });

    const userIds = items.map((i: any) => i.inviteeId);
    const users = userIds.length
      ? await db.user.findMany({
          where: { id: { in: userIds } },
          select: { id: true, name: true, avatarUrl: true, displayId: true },
        })
      : [];
    const userMap = new Map(users.map((u: any) => [u.id, u]));

    return res.json({
      success: true,
      data: items.map((i: any) => ({ ...i, requester: userMap.get(i.inviteeId) ?? null })),
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// PATCH /agencies/join-requests/:inviteId/review
export const reviewJoinRequest = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const inviteId = Number(req.params.inviteId);
    const action = String((req.body as any)?.action || '').toLowerCase();
    if (!inviteId) return fail(res, 400, 'Invalid inviteId');
    if (!['accept', 'reject'].includes(action)) return fail(res, 400, 'action must be accept or reject');

    const invite = await db.agencyInvite.findUnique({ where: { id: inviteId } });
    if (!invite || invite.status !== 'pending') return fail(res, 404, 'Pending request not found');

    const ownerMembership = await db.agencyMember.findFirst({
      where: { userId, agencyId: invite.agencyId, role: 'OWNER' },
      include: { agency: { select: { type: true } } },
    });
    if (!ownerMembership || ownerMembership.agency.type !== 'HOSTING') return fail(res, 403, 'Not allowed');

    await db.$transaction(async (tx: any) => {
      await tx.agencyInvite.update({
        where: { id: inviteId },
        data: { status: action === 'accept' ? 'accepted' : 'rejected' },
      });
      if (action === 'accept') {
        await tx.agencyMember.upsert({
          where: { agencyId_userId: { agencyId: invite.agencyId, userId: invite.inviteeId } },
          update: { role: 'MEMBER' },
          create: { agencyId: invite.agencyId, userId: invite.inviteeId, role: 'MEMBER' },
        });
      }
    });

    return res.json({ success: true });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/my-invites
export const getMyInvites = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const invites = await db.agencyInvite.findMany({
      where: { inviteeId: userId, status: 'pending' },
      include: { agency: { select: { id: true, agencyName: true, logoUrl: true, type: true } } },
    });

    return res.json({ success: true, data: invites });
  } catch {
    return fail(res, 500, 'Server error');
  }
};
