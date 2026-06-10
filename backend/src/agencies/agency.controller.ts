import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';
import { evaluateVip } from '../services/vip.service';
import { createNotification } from '../services/notification.service';

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
      include: { agency: { select: { agencyName: true } } },
    });

    // The invitee learns about it from notifications/messages.
    try {
      await createNotification({
        userId: inviteeId,
        actorId: ownerId,
        type: 'AGENCY_INVITE',
        title: 'دعوة للانضمام إلى وكالة',
        body: `تمت دعوتك للانضمام إلى وكالة ${invite.agency?.agencyName ?? ''}`,
        data: { inviteId: invite.id, agencyId: m.agencyId },
      });
    } catch (e) {
      console.warn('agency invite notification failed:', e);
    }

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

    try {
      await createNotification({
        userId: invite.inviterId,
        actorId: userId,
        type: 'AGENCY_INVITE_RESPONSE',
        title: action === 'accept' ? 'انضمام مضيف جديد' : 'تم رفض الدعوة',
        body: action === 'accept' ? 'قبل المستخدم دعوة الانضمام إلى وكالتك' : 'رفض المستخدم دعوة الانضمام إلى وكالتك',
        data: { inviteId, agencyId: invite.agencyId },
      });
    } catch (e) {
      console.warn('agency invite response notification failed:', e);
    }

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

// Resolves the caller's OWNER membership of an approved agency (any type unless given).
const findOwnerMembership = async (userId: number, type?: string) => {
  const m = await db.agencyMember.findFirst({
    where: { userId, role: 'OWNER' },
    include: { agency: true },
  });
  if (!m || m.agency.status !== 'approved') return null;
  if (type && m.agency.type !== type) return null;
  return m;
};

// GET /agencies/search-user?q=  — agent looks up a user by display ID (or name) to invite
export const searchUserForInvite = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const m = await findOwnerMembership(userId);
    if (!m) return fail(res, 403, 'Not an agency owner');

    const q = String((req.query as any)?.q ?? '').trim();
    if (!q) return fail(res, 400, 'q required');

    const numQ = /^\d+$/.test(q) ? Number(q) : null;
    const users = await db.user.findMany({
      where: {
        id: { not: userId },
        OR: [
          ...(numQ !== null ? [{ displayId: numQ }] : []),
          { name: { contains: q, mode: 'insensitive' } },
        ],
      },
      select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true },
      take: 10,
    });

    const memberIds = new Set(
      (await db.agencyMember.findMany({
        where: { agencyId: m.agencyId, userId: { in: users.map((u: any) => u.id) } },
        select: { userId: true },
      })).map((r: any) => r.userId),
    );

    return res.json({
      success: true,
      data: users.map((u: any) => ({ ...u, isMember: memberIds.has(u.id) })),
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/members-stats — agent sees each member's target (gift earnings since joining)
export const getMembersStats = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const m = await findOwnerMembership(userId);
    if (!m) return fail(res, 403, 'Not an agency owner');

    const members = await db.agencyMember.findMany({
      where: { agencyId: m.agencyId },
      include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true } } },
      orderBy: { joinedAt: 'asc' },
    });

    const stats = await Promise.all(
      members.map(async (member: any) => {
        const earned = await db.giftTransaction.aggregate({
          where: { recipientId: member.userId, createdAt: { gte: member.joinedAt } },
          _sum: { totalCoins: true },
        });
        return {
          memberId: member.id,
          role: member.role,
          joinedAt: member.joinedAt,
          user: member.user,
          // The agent sees the member's target/earnings, never their wallet balance.
          targetCoins: earned._sum.totalCoins ?? 0,
        };
      }),
    );

    return res.json({
      success: true,
      data: {
        agency: {
          id: m.agency.id,
          agencyName: m.agency.agencyName,
          type: m.agency.type,
          exitLocked: m.agency.exitLocked,
          exitPriceCoins: m.agency.exitPriceCoins,
        },
        members: stats,
      },
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// DELETE /agencies/members/:userId — agent removes a member from his agency
export const removeMember = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');

    const targetUserId = Number(req.params.userId);
    if (!targetUserId) return fail(res, 400, 'Invalid userId');
    if (targetUserId === ownerId) return fail(res, 400, 'Owner cannot remove himself');

    const m = await findOwnerMembership(ownerId);
    if (!m) return fail(res, 403, 'Not an agency owner');

    const member = await db.agencyMember.findFirst({
      where: { agencyId: m.agencyId, userId: targetUserId },
    });
    if (!member) return fail(res, 404, 'Not a member of your agency');
    if (member.role === 'OWNER') return fail(res, 400, 'Cannot remove the owner');

    await db.agencyMember.delete({ where: { id: member.id } });

    try {
      await createNotification({
        userId: targetUserId,
        actorId: ownerId,
        type: 'AGENCY_REMOVED',
        title: 'تمت إزالتك من الوكالة',
        body: `قام الوكيل بإزالتك من وكالة ${m.agency.agencyName}`,
        data: { agencyId: m.agencyId },
      });
    } catch (e) {
      console.warn('agency removal notification failed:', e);
    }

    return res.json({ success: true });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// PATCH /agencies/exit-settings — agent locks/unlocks member exit and sets its coin price
export const setExitSettings = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');

    const m = await findOwnerMembership(ownerId);
    if (!m) return fail(res, 403, 'Not an agency owner');

    const { exitLocked, exitPriceCoins } = req.body as {
      exitLocked?: boolean;
      exitPriceCoins?: number | string;
    };

    const price = exitPriceCoins != null ? Number(exitPriceCoins) : undefined;
    if (price != null && (!Number.isFinite(price) || price < 0)) {
      return fail(res, 400, 'exitPriceCoins must be >= 0');
    }

    const updated = await db.chargingAgency.update({
      where: { id: m.agencyId },
      data: {
        ...(exitLocked != null ? { exitLocked: Boolean(exitLocked) } : {}),
        ...(price != null ? { exitPriceCoins: price } : {}),
      },
      select: { id: true, exitLocked: true, exitPriceCoins: true },
    });

    return res.json({ success: true, data: updated });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// GET /agencies/my-membership — member side: role, agency and its exit policy
export const getMyMembership = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const m = await db.agencyMember.findFirst({
      where: { userId, agency: { status: 'approved' } },
      include: {
        agency: {
          select: {
            id: true, agencyName: true, logoUrl: true, type: true,
            exitLocked: true, exitPriceCoins: true, userId: true,
          },
        },
      },
    });

    console.log('[my-membership]', { userId, found: !!m, role: m?.role });
    if (!m) return res.json({ success: true, data: null });

    return res.json({
      success: true,
      data: {
        memberId: m.id,
        role: m.role,
        joinedAt: m.joinedAt,
        agency: m.agency,
      },
    });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/leave — member leaves; pays the exit price when the agency locks exit
export const leaveAgency = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const m = await db.agencyMember.findFirst({
      where: { userId, agency: { status: 'approved' } },
      include: { agency: true },
    });
    if (!m) return fail(res, 404, 'Not a member of any agency');
    if (m.role === 'OWNER') return fail(res, 400, 'Owner cannot leave; transfer ownership first');

    const price = m.agency.exitLocked ? Number(m.agency.exitPriceCoins || 0) : 0;

    try {
      await db.$transaction(async (tx: any) => {
        if (price > 0) {
          const user = await tx.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } });
          if (!user || user.coinsBalance < price) throw new Error('INSUFFICIENT_COINS');

          // The exit fee goes to the agency owner who invested in the member.
          await tx.user.update({ where: { id: userId }, data: { coinsBalance: { decrement: price } } });
          await tx.user.update({ where: { id: m.agency.userId }, data: { coinsBalance: { increment: price } } });
          await tx.transaction.create({
            data: {
              userId,
              type: 'AGENCY_EXIT_FEE',
              amountCoins: -price,
              description: `رسوم الخروج من وكالة ${m.agency.agencyName}`,
            },
          });
          await tx.transaction.create({
            data: {
              userId: m.agency.userId,
              type: 'AGENCY_EXIT_FEE',
              amountCoins: price,
              description: `رسوم خروج مضيف من وكالتك`,
            },
          });
        }
        await tx.agencyMember.delete({ where: { id: m.id } });
      });
    } catch (e: any) {
      if (e?.message === 'INSUFFICIENT_COINS') {
        return fail(res, 400, 'INSUFFICIENT_COINS');
      }
      throw e;
    }

    try {
      await createNotification({
        userId: m.agency.userId,
        actorId: userId,
        type: 'AGENCY_MEMBER_LEFT',
        title: 'غادر مضيف وكالتك',
        body: price > 0 ? `غادر مضيف وكالتك بعد دفع رسوم الخروج (${price} كوينز)` : 'غادر مضيف وكالتك',
        data: { agencyId: m.agencyId, paidCoins: price },
      });
    } catch (e) {
      console.warn('agency leave notification failed:', e);
    }

    return res.json({ success: true, data: { paidCoins: price } });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/transfer-ownership — agent hands the whole system to another user
export const transferOwnership = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');

    const toUserId = Number((req.body as any)?.toUserId);
    if (!toUserId) return fail(res, 400, 'toUserId required');
    if (toUserId === ownerId) return fail(res, 400, 'Already the owner');

    const m = await findOwnerMembership(ownerId);
    if (!m) return fail(res, 403, 'Not an agency owner');

    const target = await db.user.findUnique({ where: { id: toUserId }, select: { id: true } });
    if (!target) return fail(res, 404, 'User not found');

    await db.$transaction(async (tx: any) => {
      await tx.chargingAgency.update({ where: { id: m.agencyId }, data: { userId: toUserId } });
      // Old owner steps down to MEMBER; new owner takes the OWNER seat.
      await tx.agencyMember.update({ where: { id: m.id }, data: { role: 'MEMBER' } });
      await tx.agencyMember.upsert({
        where: { agencyId_userId: { agencyId: m.agencyId, userId: toUserId } },
        update: { role: 'OWNER' },
        create: { agencyId: m.agencyId, userId: toUserId, role: 'OWNER' },
      });
    });

    try {
      await createNotification({
        userId: toUserId,
        actorId: ownerId,
        type: 'AGENCY_OWNERSHIP',
        title: 'أصبحت وكيلاً',
        body: `تم نقل ملكية وكالة ${m.agency.agencyName} إليك`,
        data: { agencyId: m.agencyId },
      });
    } catch (e) {
      console.warn('agency ownership notification failed:', e);
    }

    return res.json({ success: true });
  } catch {
    return fail(res, 500, 'Server error');
  }
};

/**
 * Role label helper used by profile endpoints:
 * OWNER of an approved agency → 'agent' (وكيل), MEMBER → 'host' (مضيف).
 */
export const getAgencyRole = async (
  userId: number,
): Promise<{ agencyRole: 'agent' | 'host'; agencyName: string; agencyId: number } | null> => {
  const m = await db.agencyMember.findFirst({
    where: { userId, agency: { status: 'approved' } },
    include: { agency: { select: { id: true, agencyName: true } } },
    orderBy: { role: 'asc' }, // 'MEMBER' < 'OWNER' alphabetically; prefer OWNER below
  });
  if (!m) return null;
  const owner = await db.agencyMember.findFirst({
    where: { userId, role: 'OWNER', agency: { status: 'approved' } },
    include: { agency: { select: { id: true, agencyName: true } } },
  });
  const eff = owner ?? m;
  return {
    agencyRole: eff.role === 'OWNER' ? 'agent' : 'host',
    agencyName: eff.agency.agencyName,
    agencyId: eff.agency.id,
  };
};
