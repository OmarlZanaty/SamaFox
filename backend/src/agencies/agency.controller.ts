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

    // #8: a user can own BOTH a hosting and a charging agency. The old
    // findFirst() returned only one, so the app never showed the other
    // ("بيجيلي استضافة بس، ومبيجيليش وكالة شحن"). Return every owned agency.
    const memberships = await db.agencyMember.findMany({
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

    const agencies = memberships.map((m: any) => serializeBigInt(m.agency));

    // `data` is now an array (all owned agencies). `agency` keeps the first one
    // for backward-compatible single-object consumers.
    return res.json({
      success: true,
      data: agencies,
      agency: agencies[0] ?? null,
    });
  } catch (e) {
    console.error('[agency.getMyAgency] failed:', e);
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

    // Owners AND branches (فرع) may sell/send coins from the agency balance.
    const membership = await db.agencyMember.findFirst({
      where: { userId: senderId, role: { in: ['OWNER', 'BRANCH'] } },
      include: { agency: true },
    });

    if (!membership) return fail(res, 403, 'Not an agency owner or branch');
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
            // NOTE: Transaction has no `description` column — passing it threw a
            // PrismaClientValidationError that made every send-coins fail (#6).
            status: 'completed',
          },
        });
      });

      // Top-up counts toward VIP — re-evaluate after the transfer commits.
      try { await evaluateVip(targetUserId); } catch (e) { console.warn('evaluateVip failed:', e); }

      // #6: tell the recipient who charged them and how much.
      try {
        const sender = await db.user.findUnique({ where: { id: senderId }, select: { name: true } });
        await createNotification({
          userId: targetUserId,
          actorId: senderId,
          type: 'AGENCY_TOPUP',
          title: 'تم شحن رصيدك 🪙',
          body: `قام ${sender?.name ?? 'وكيل الشحن'} بشحن ${coins} كوينز لك`,
          data: { amount: coins, senderId },
        });
      } catch (e) {
        console.warn('agency topup notification failed:', e);
      }
    } catch (e: any) {
      if (e?.message === 'INSUFFICIENT_AGENCY_BALANCE') {
        return fail(res, 400, 'INSUFFICIENT_AGENCY_BALANCE');
      }
      throw e;
    }

    return res.json({ success: true, message: 'Coins sent successfully' });
  } catch (e) {
    console.error('[agency.sendCoinsToUser] failed:', e);
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

    const m = await findManagerMembership(ownerId);
    if (!m) return fail(res, 403, 'Not an agency owner or branch');

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
  } catch (e) {
    // Was a blind `catch {}` that hid the real cause behind a generic 500 —
    // that opacity was #35 "invite shows an error with no detail". Log it.
    console.error('[agency.inviteMember] failed:', e);
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
      where: { userId, role: { in: ['OWNER', 'BRANCH'] } },
      include: { agency: { select: { id: true, type: true } } },
    });
    if (!ownerMembership || ownerMembership.agency.type !== 'HOSTING') {
      return fail(res, 403, 'Not a hosting agency owner');
    }

    // Agency-wide, not just this manager's own invites — a branch should see
    // pending requests the owner (or another branch) sent too.
    const items = await db.agencyInvite.findMany({
      where: { agencyId: ownerMembership.agencyId, status: 'pending' },
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
      where: { userId, agencyId: invite.agencyId, role: { in: ['OWNER', 'BRANCH'] } },
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

// Resolves the caller's OWNER membership of an approved agency (any type unless
// given). IMPORTANT: `type` must be pushed into the Prisma WHERE clause, not
// checked after findFirst() — a user can own BOTH a HOSTING and a CHARGING
// agency (#8), so an untyped findFirst() can grab the wrong-type row and then
// wrongly report "no owner membership" even though a matching one exists.
const findOwnerMembership = async (userId: number, type?: string) => {
  const m = await db.agencyMember.findFirst({
    where: { userId, role: 'OWNER', ...(type ? { agency: { type } } : {}) },
    include: { agency: true },
  });
  if (!m || m.agency.status !== 'approved') return null;
  return m;
};

// Resolves the caller's OWNER **or** BRANCH (فرع) membership. A branch has the
// same day-to-day management abilities as the owner (invite/remove hosts, view
// members' targets) but never owns the agency (#2-4). Used for host-management
// actions; branch-management itself (add/remove a branch) stays OWNER-only.
// Same multi-agency caveat as findOwnerMembership above — filter by type in
// the query, not after the fact.
const findManagerMembership = async (userId: number, type?: string) => {
  const m = await db.agencyMember.findFirst({
    where: { userId, role: { in: ['OWNER', 'BRANCH'] }, ...(type ? { agency: { type } } : {}) },
    include: { agency: true },
  });
  if (!m || m.agency.status !== 'approved') return null;
  return m;
};

// GET /agencies/search-user?q=  — agent looks up a user by display ID (or name) to invite
export const searchUserForInvite = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const m = await findManagerMembership(userId);
    if (!m) return fail(res, 403, 'Not an agency owner or branch');

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

    const m = await findManagerMembership(userId);
    if (!m) return fail(res, 403, 'Not an agency owner or branch');

    const members = await db.agencyMember.findMany({
      where: { agencyId: m.agencyId },
      include: { user: { select: { id: true, name: true, avatarUrl: true, displayId: true, vipLevel: true } } },
      orderBy: { joinedAt: 'asc' },
    });

    const stats = await Promise.all(
      members.map(async (member: any) => {
        const earned = await db.giftTransaction.aggregate({
          // Target = gifts RECEIVED since joining, excluding self-gifts so a
          // member can't inflate their own target (#19). createdAt >= joinedAt
          // makes the target start at 0 on join automatically (#21).
          where: {
            recipientId: member.userId,
            senderId: { not: member.userId },
            createdAt: { gte: member.joinedAt },
          },
          _sum: { totalCoins: true },
        });
        const earnedCoins = Number(earned._sum.totalCoins ?? 0);
        const goal = Number(member.targetGoalCoins ?? 0n);
        return {
          memberId: member.id,
          role: member.role,
          joinedAt: member.joinedAt,
          user: member.user,
          // The agent sees the member's target/earnings, never their wallet balance.
          targetCoins: earnedCoins, // earned so far (kept for backward compat)
          earnedCoins, // #24 explicit
          targetGoalCoins: goal, // goal set by owner/admin (#24)
          remainingCoins: goal > 0 ? Math.max(0, goal - earnedCoins) : 0,
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

    const m = await findManagerMembership(ownerId);
    if (!m) return fail(res, 403, 'Not an agency owner or branch');

    const member = await db.agencyMember.findFirst({
      where: { agencyId: m.agencyId, userId: targetUserId },
    });
    if (!member) return fail(res, 404, 'Not a member of your agency');
    if (member.role === 'OWNER') return fail(res, 400, 'Cannot remove the owner');
    // Only the owner manages branches — a branch cannot remove another branch.
    if (member.role === 'BRANCH' && m.role !== 'OWNER') {
      return fail(res, 403, 'Only the owner can remove a branch');
    }

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

// GET /agencies/my-memberships — ALL of the caller's memberships (owner, branch,
// or plain member/host), across every agency they belong to (#8: a user can own
// or work in more than one agency at once). Used by the app to compute, per
// agency, whether the current user can manage it (owner or branch).
export const getMyMemberships = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const rows = await db.agencyMember.findMany({
      where: { userId, agency: { status: 'approved' } },
      include: {
        agency: {
          select: { id: true, agencyName: true, logoUrl: true, type: true, userId: true },
        },
      },
    });

    return res.json({
      success: true,
      data: rows.map((m: any) => ({
        memberId: m.id,
        role: m.role,
        joinedAt: m.joinedAt,
        agency: m.agency,
      })),
    });
  } catch (e) {
    console.error('[agency.getMyMemberships] failed:', e);
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
          // Transaction has no `description` column — omit it (see #6 fix above).
          await tx.transaction.create({
            data: { userId, type: 'AGENCY_EXIT_FEE', amountCoins: -price, status: 'completed' },
          });
          await tx.transaction.create({
            data: { userId: m.agency.userId, type: 'AGENCY_EXIT_FEE', amountCoins: price, status: 'completed' },
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

// ============================================================
// BRANCH (فرع) system — an OWNER (hosting or charging agency) grants a
// partner the SAME day-to-day system access — for a charging agency: sell/
// send coins from the agency balance; for a hosting agency: invite/remove
// hosts and view their targets — WITHOUT transferring ownership. Reuses
// AgencyMember with role 'BRANCH'. Owner can add/remove any time, and up to
// MAX_BRANCHES at once (#2-4: "عايز اتنين أو تلاتة أديهم فروع").
// ============================================================

const MAX_BRANCHES = 3;

// Body/query may specify which of the owner's agencies (HOSTING or CHARGING)
// to act on, since an owner can own both (#8). Defaults to CHARGING for
// backward compatibility with older app builds that don't send it.
const resolveAgencyType = (raw: unknown): string =>
  String(raw ?? 'CHARGING').toUpperCase() === 'HOSTING' ? 'HOSTING' : 'CHARGING';

// GET /agencies/branches?agencyType=HOSTING|CHARGING — owner lists their branches.
export const listBranches = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');
    const agencyType = resolveAgencyType((req.query as any)?.agencyType);
    const owner = await findOwnerMembership(ownerId, agencyType);
    if (!owner) return fail(res, 403, `Not a ${agencyType.toLowerCase()}-agency owner`);

    const rows = await db.agencyMember.findMany({
      where: { agencyId: owner.agencyId, role: 'BRANCH' },
      orderBy: { joinedAt: 'desc' },
    });
    const userIds = rows.map((r: any) => r.userId);
    const users = userIds.length
      ? await db.user.findMany({
          where: { id: { in: userIds } },
          select: { id: true, name: true, avatarUrl: true, displayId: true },
        })
      : [];
    const byId = new Map(users.map((u: any) => [u.id, u]));
    const data = rows.map((r: any) => ({
      memberId: r.id,
      userId: r.userId,
      joinedAt: r.joinedAt,
      user: byId.get(r.userId) ?? null,
    }));
    return res.json({ success: true, data });
  } catch (e) {
    console.error('[agency.listBranches] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/branches  { userId, agencyType }  — owner adds a partner as a branch.
export const addBranch = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');
    const agencyType = resolveAgencyType((req.body as any)?.agencyType);
    const owner = await findOwnerMembership(ownerId, agencyType);
    if (!owner) return fail(res, 403, `Not a ${agencyType.toLowerCase()}-agency owner`);

    const targetId = Number((req.body as any)?.userId);
    if (!targetId) return fail(res, 400, 'userId required');
    if (targetId === ownerId) return fail(res, 400, 'Owner cannot be their own branch');

    const target = await db.user.findUnique({ where: { id: targetId }, select: { id: true, name: true } });
    if (!target) return fail(res, 404, 'User not found');

    const existing = await db.agencyMember.findFirst({
      where: { agencyId: owner.agencyId, userId: targetId },
    });
    if (existing?.role === 'BRANCH') return fail(res, 400, 'Already a branch');

    if (!existing) {
      // Cap enforced only when creating a NEW branch slot (#2-4: 2-3 branches).
      const branchCount = await db.agencyMember.count({
        where: { agencyId: owner.agencyId, role: 'BRANCH' },
      });
      if (branchCount >= MAX_BRANCHES) {
        return fail(res, 400, `Maximum ${MAX_BRANCHES} branches reached`);
      }
      await db.agencyMember.create({
        data: { agencyId: owner.agencyId, userId: targetId, role: 'BRANCH' },
      });
    } else {
      await db.agencyMember.update({ where: { id: existing.id }, data: { role: 'BRANCH' } });
    }

    const isHosting = agencyType === 'HOSTING';
    try {
      await createNotification({
        userId: targetId,
        actorId: ownerId,
        type: 'AGENCY_BRANCH_ADDED',
        title: isHosting ? 'أصبحت فرعاً في وكالة المضيفين' : 'أصبحت فرعاً في وكالة الشحن',
        body: isHosting
          ? `تمت إضافتك كفرع في وكالة ${owner.agency.agencyName} — يمكنك الآن إدارة المضيفين`
          : `تمت إضافتك كفرع في وكالة ${owner.agency.agencyName} — يمكنك الآن البيع والشحن`,
        data: { agencyId: owner.agencyId },
      });
    } catch (e) {
      console.warn('branch add notification failed:', e);
    }

    return res.json({ success: true });
  } catch (e) {
    console.error('[agency.addBranch] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// DELETE /agencies/branches/:userId?agencyType=... — owner revokes a branch.
export const removeBranch = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');
    const agencyType = resolveAgencyType((req.query as any)?.agencyType);
    const owner = await findOwnerMembership(ownerId, agencyType);
    if (!owner) return fail(res, 403, `Not a ${agencyType.toLowerCase()}-agency owner`);

    const targetId = Number(req.params.userId);
    if (!targetId) return fail(res, 400, 'Invalid userId');

    const branch = await db.agencyMember.findFirst({
      where: { agencyId: owner.agencyId, userId: targetId, role: 'BRANCH' },
    });
    if (!branch) return fail(res, 404, 'Branch not found');

    await db.agencyMember.delete({ where: { id: branch.id } });
    return res.json({ success: true });
  } catch (e) {
    console.error('[agency.removeBranch] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// ============================================================
// TARGET system (#13, #24)
// ============================================================

// GET /agencies/my-target — the logged-in user's own target(s) as a host.
// earned = gifts received since joining (excluding self-gifts); the goal is
// set per-membership by the agency owner; remaining = goal - earned.
export const getMyTarget = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    // Hosting memberships where the user is a host (not the owner).
    const memberships = await db.agencyMember.findMany({
      where: { userId, role: { not: 'OWNER' }, agency: { type: 'HOSTING', status: 'approved' } },
      include: { agency: { select: { id: true, agencyName: true } } },
      orderBy: { joinedAt: 'asc' },
    });

    const items = await Promise.all(
      memberships.map(async (mm: any) => {
        const earned = await db.giftTransaction.aggregate({
          where: {
            recipientId: userId,
            senderId: { not: userId },
            createdAt: { gte: mm.joinedAt },
          },
          _sum: { totalCoins: true },
        });
        const earnedCoins = Number(earned._sum.totalCoins ?? 0);
        const goal = Number(mm.targetGoalCoins ?? 0n);
        return {
          agencyId: mm.agency.id,
          agencyName: mm.agency.agencyName,
          joinedAt: mm.joinedAt,
          earnedCoins,
          targetGoalCoins: goal,
          remainingCoins: goal > 0 ? Math.max(0, goal - earnedCoins) : 0,
        };
      }),
    );

    const totalEarned = items.reduce((s, i) => s + i.earnedCoins, 0);
    return res.json({
      success: true,
      data: { totalEarned, hasTarget: items.length > 0, items },
    });
  } catch (e) {
    console.error('[agency.getMyTarget] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// PATCH /agencies/members/:userId/target  { targetGoalCoins }
// A hosting-agency owner sets a member's target goal.
export const setMemberTarget = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');
    const owner = await findOwnerMembership(ownerId, 'HOSTING');
    if (!owner) return fail(res, 403, 'Not a hosting-agency owner');

    const targetId = Number(req.params.userId);
    if (!targetId) return fail(res, 400, 'Invalid userId');

    const raw = (req.body as any)?.targetGoalCoins;
    const goal = Number(raw);
    if (!Number.isFinite(goal) || goal < 0) return fail(res, 400, 'targetGoalCoins must be >= 0');

    const member = await db.agencyMember.findFirst({
      where: { agencyId: owner.agencyId, userId: targetId },
    });
    if (!member) return fail(res, 404, 'Member not in your agency');

    await db.agencyMember.update({
      where: { id: member.id },
      data: { targetGoalCoins: BigInt(Math.floor(goal)) },
    });

    try {
      await createNotification({
        userId: targetId,
        actorId: ownerId,
        type: 'AGENCY_TARGET_SET',
        title: 'تم تحديد التارجت الخاص بك 🎯',
        body: `حدد لك الوكيل تارجت بقيمة ${Math.floor(goal)} كوينز`,
        data: { agencyId: owner.agencyId, targetGoalCoins: Math.floor(goal) },
      });
    } catch (e) {
      console.warn('set member target notification failed:', e);
    }

    return res.json({ success: true, data: { targetGoalCoins: Math.floor(goal) } });
  } catch (e) {
    console.error('[agency.setMemberTarget] failed:', e);
    return fail(res, 500, 'Server error');
  }
};
