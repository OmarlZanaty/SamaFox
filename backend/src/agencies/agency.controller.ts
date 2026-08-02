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
          select: { id: true, role: true, user: { select: { id: true, name: true, avatarUrl: true } } },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return res.json({ success: true, data: agencies });
  } catch (err) {
    console.error('[listChargingAgencies]', err);
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

    // `earnedCoins` on the row is a dead column — nothing has ever written it,
    // so it always reads 0 and the progress bar was permanently empty. Compute
    // the agency's real production instead.
    const data = await Promise.all(
      agencies.map(async (a: any) => {
        const goal = Number(a.targetCoins ?? 0n);
        const earned = await computeAgencyEarnedCoins(a.id);
        return {
          id: a.id,
          agencyName: a.agencyName,
          logoUrl: a.logoUrl,
          imageUrl: a.agencyImageUrl,
          targetCoins: goal.toString(),
          earnedCoins: earned.toString(),
          memberCount: a.members.length,
          progress: goal > 0 ? Math.min(100, Math.round((earned * 100) / goal)) : 0,
          members: a.members.map((m: any) => m.user),
        };
      }),
    );

    return res.json({ success: true, data });
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
    //
    // The CHARGING + approved filter belongs in the query, not in a check after
    // it: an untyped findFirst returns whichever membership comes first, so an
    // agent who also owns a HOSTING agency got that one back and every charge
    // died on 'Only charging agencies can send coins'. Owner rows are preferred
    // over branch rows, and rejected/pending agencies never qualify.
    const membership = await db.agencyMember.findFirst({
      where: {
        userId: senderId,
        role: { in: ['OWNER', 'BRANCH'] },
        agency: { type: 'CHARGING', status: 'approved' },
      },
      include: { agency: true },
      orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }],
    });

    if (!membership) return fail(res, 403, 'لست وكيل أو فرع في وكالة شحن معتمدة');

    try {
      await db.$transaction(async (tx: any) => {
        const agency = await tx.chargingAgency.findUnique({ where: { id: membership.agencyId } });
        if (!agency || agency.balanceCoins < coins) {
          // Carry the balance so the caller can be told how short they are.
          throw new Error(`INSUFFICIENT_AGENCY_BALANCE:${agency?.balanceCoins ?? 0}`);
        }

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
            // Group 7: attribute the charge so the dashboard can answer
            // "who charged this user" during complaint investigations.
            agencyId: membership.agencyId,
            senderId,
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
      if (String(e?.message ?? '').startsWith('INSUFFICIENT_AGENCY_BALANCE')) {
        const balance = String(e.message).split(':')[1] ?? '0';
        return fail(res, 400, `رصيد الوكالة غير كافٍ — المتاح ${balance} كوينز`);
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

    // Same type filter the roster uses. Without it an agent who owns BOTH a
    // HOSTING and a CHARGING agency (#8) invites into whichever they joined
    // first — so the host accepts, lands in the other agency, and never shows
    // up in the panel the agent is looking at ("المضيف انحذف لوحده").
    const requestedType = (req.query as any)?.agencyType ?? (req.body as any)?.agencyType;
    const inviteType = requestedType ? String(requestedType).toUpperCase() : undefined;
    const m = await findManagerMembership(ownerId, inviteType);
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
// `status` belongs in the WHERE clause for the same reason `type` does: checked
// afterwards, a pending agency row returned by findFirst masks an approved one
// the user actually owns, and the caller is wrongly told they own nothing.
const findOwnerMembership = async (userId: number, type?: string) => {
  return db.agencyMember.findFirst({
    where: {
      userId,
      role: 'OWNER',
      agency: { status: 'approved', ...(type ? { type } : {}) },
    },
    include: { agency: true },
    orderBy: { joinedAt: 'asc' },
  });
};

// Resolves the caller's OWNER **or** BRANCH (فرع) membership. A branch has the
// same day-to-day management abilities as the owner (invite/remove hosts, view
// members' targets) but never owns the agency (#2-4). Used for host-management
// actions; branch-management itself (add/remove a branch) stays OWNER-only.
// Same multi-agency caveat as findOwnerMembership above — filter by type in
// the query, not after the fact.
const findManagerMembership = async (userId: number, type?: string) => {
  return db.agencyMember.findFirst({
    where: {
      userId,
      role: { in: ['OWNER', 'BRANCH'] },
      agency: { status: 'approved', ...(type ? { type } : {}) },
    },
    include: { agency: true },
    // Owner rows before branch rows, so managing your OWN agency always wins
    // over an agency where you are merely a branch.
    orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }],
  });
};

// GET /agencies/search-user?q=  — agent looks up a user by display ID (or name) to invite
export const searchUserForInvite = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const searchType = (req.query as any)?.agencyType
      ? String((req.query as any).agencyType).toUpperCase()
      : undefined;
    const m = await findManagerMembership(userId, searchType);
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

    // A user can own/branch BOTH a HOSTING and a CHARGING agency (#8). Without
    // a type filter the untyped findFirst can return the WRONG agency, so the
    // manager opens the roster and sees the other agency's members. Clients
    // pass which one they mean; unspecified still falls back to "whichever"
    // for older builds where the user only ever has one.
    const requestedType = (req.query as any)?.agencyType
      ? String((req.query as any).agencyType).toUpperCase()
      : undefined;
    const m = await findManagerMembership(userId, requestedType);
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

    // Owner/branch (the "agent" row) always first, then members sorted by
    // target (earnedCoins) descending — the roster is meant to read as a
    // leaderboard under the agent, not a join-date list.
    const rolePriority = (role: string) => (role === 'OWNER' ? 0 : role === 'BRANCH' ? 1 : 2);
    stats.sort((a, b) => {
      const roleDiff = rolePriority(a.role) - rolePriority(b.role);
      if (roleDiff !== 0) return roleDiff;
      return b.earnedCoins - a.earnedCoins;
    });

    // The agent's own target rides along with the roster so the panel can show
    // "how is MY agency doing" next to "how is each host doing".
    const agencyGoal = Number(m.agency.targetCoins ?? 0n);
    const agencyEarned = await computeAgencyEarnedCoins(m.agencyId);

    return res.json({
      success: true,
      data: {
        agency: {
          id: m.agency.id,
          agencyName: m.agency.agencyName,
          type: m.agency.type,
          exitLocked: m.agency.exitLocked,
          exitPriceCoins: m.agency.exitPriceCoins,
          targetGoalCoins: agencyGoal,
          earnedCoins: agencyEarned,
          remainingCoins: agencyGoal > 0 ? Math.max(0, agencyGoal - agencyEarned) : 0,
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

    // Typed for the same reason as inviteMember above — otherwise the remove
    // button can resolve to the agency the agent is NOT looking at.
    const removeType = (req.query as any)?.agencyType
      ? String((req.query as any).agencyType).toUpperCase()
      : undefined;
    const m = await findManagerMembership(ownerId, removeType);
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

    // Which agency the price is being set on. Untyped, an owner of both a
    // hosting and a charging agency could set the fee from the hosting panel
    // and have it silently written to the other agency.
    const requestedType = (req.body as any)?.agencyType
      ? String((req.body as any).agencyType).toUpperCase()
      : undefined;
    const m = await findOwnerMembership(ownerId, requestedType);
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

    // `agencyType` picks which one is meant. Without it this findFirst returned
    // an arbitrary row, so a user who owns BOTH a hosting and a charging agency
    // opened whichever the database happened to hand back first (#8).
    const requestedType = (req.query as any)?.agencyType
      ? String((req.query as any).agencyType).toUpperCase()
      : undefined;

    const m = await db.agencyMember.findFirst({
      where: {
        userId,
        agency: { status: 'approved', ...(requestedType ? { type: requestedType } : {}) },
      },
      include: {
        agency: {
          select: {
            id: true, agencyName: true, logoUrl: true, type: true,
            exitLocked: true, exitPriceCoins: true, userId: true,
          },
        },
      },
      // Manager rows first so owning an agency always beats merely belonging
      // to one, then oldest — deterministic instead of database order.
      orderBy: [{ role: 'desc' }, { joinedAt: 'asc' }],
    });

    console.log('[my-membership]', { userId, type: requestedType, found: !!m, role: m?.role });
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

    // WHICH agency is being left. This used to be an unqualified findFirst, so
    // a user with two memberships left an arbitrary one — typically the
    // unlocked agency, which is why the exit fee "stopped working" the moment
    // someone joined a second agency. `agencyId` is exact; `agencyType`
    // narrows; neither given falls back to a deterministic pick that prefers a
    // leavable (non-OWNER) row over an owner row.
    const agencyId = req.body?.agencyId != null ? Number(req.body.agencyId) : undefined;
    const agencyType = req.body?.agencyType
      ? String(req.body.agencyType).toUpperCase()
      : undefined;
    if (agencyId !== undefined && !Number.isFinite(agencyId)) {
      return fail(res, 400, 'agencyId must be a number');
    }

    const m = await db.agencyMember.findFirst({
      where: {
        userId,
        ...(agencyId !== undefined ? { agencyId } : {}),
        agency: { status: 'approved', ...(agencyType ? { type: agencyType } : {}) },
      },
      include: { agency: true },
      // Ascending: 'BRANCH' < 'MEMBER' < 'OWNER', so leavable rows come first
      // and an OWNER row can no longer shadow the membership the user meant.
      orderBy: [{ role: 'asc' }, { joinedAt: 'asc' }],
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

    // Echo which agency was actually left so the client can show the right
    // name and never has to assume it matched what was on screen.
    return res.json({
      success: true,
      data: {
        paidCoins: price,
        agencyId: m.agencyId,
        agencyName: m.agency.agencyName,
        agencyType: m.agency.type,
      },
    });
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

    // A user can own both a HOSTING and a CHARGING agency at once (#8) —
    // without a type filter, findOwnerMembership's findFirst picks whichever
    // one happens to come back first, which could silently transfer the
    // WRONG agency. The client passes which one it means; only fall back to
    // "whichever agency" for a caller with just one.
    const requestedType = req.body?.agencyType ? String(req.body.agencyType).toUpperCase() : undefined;
    const m = await findOwnerMembership(ownerId, requestedType);
    if (!m) return fail(res, 403, 'Not an agency owner');

    const target = await db.user.findUnique({ where: { id: toUserId }, select: { id: true } });
    if (!target) return fail(res, 404, 'User not found');

    await db.$transaction(async (tx: any) => {
      await tx.chargingAgency.update({ where: { id: m.agencyId }, data: { userId: toUserId } });
      // Old owner steps down to MEMBER. Their joinedAt is RESET to now: a
      // member's target is "gifts received since joinedAt", so keeping the
      // original date would hand the ex-owner an instant target covering the
      // agency's entire history — and make them owe commission on all of it.
      // convertedTargetCoins is cleared for the same reason: it caps
      // conversions against earnings that no longer count.
      await tx.agencyMember.update({
        where: { id: m.id },
        data: {
          role: 'MEMBER',
          joinedAt: new Date(),
          targetGoalCoins: BigInt(0),
          convertedTargetCoins: BigInt(0),
        },
      });
      // New owner takes the OWNER seat. An existing member being promoted
      // keeps their row (and history); a brand-new owner gets a fresh one.
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
  } catch (err) {
    console.error('[transferOwnership]', err);
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

    // Demote rather than delete. A branch of a hosting agency is also a host
    // whose target is derived from `joinedAt`; deleting the row would wipe
    // that history and drop them out of the agency entirely, which is not
    // what "revoke branch access" should mean. Earnings rules are identical
    // for BRANCH and MEMBER, so this changes access only.
    await db.agencyMember.update({ where: { id: branch.id }, data: { role: 'MEMBER' } });
    return res.json({ success: true });
  } catch (e) {
    console.error('[agency.removeBranch] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// ============================================================
// TARGET system (#13, #24)
// ============================================================

/**
 * An agency's total production: the coins its hosts have earned in gifts,
 * summed across every member, each counted only from their own `joinedAt`
 * (same rule the per-member target uses) and excluding self-gifts.
 *
 * This is the basis of the AGENT's target. Deliberately computed live rather
 * than read from `ChargingAgency.earnedCoins` — nothing has ever written that
 * column, so it is always 0 and cannot be trusted.
 */
export const computeAgencyEarnedCoins = async (agencyId: number): Promise<number> => {
  const members = await db.agencyMember.findMany({
    where: { agencyId },
    select: { userId: true, joinedAt: true },
  });
  if (members.length === 0) return 0;

  const sums = await Promise.all(
    members.map(async (m: any) => {
      const agg = await db.giftTransaction.aggregate({
        where: {
          recipientId: m.userId,
          senderId: { not: m.userId },
          createdAt: { gte: m.joinedAt },
        },
        _sum: { totalCoins: true },
      });
      return Number(agg._sum.totalCoins ?? 0);
    }),
  );
  return sums.reduce((a, b) => a + b, 0);
};

/**
 * The AGENT's own target for EVERY approved agency they own: goal set by
 * platform admin on the agency (`ChargingAgency.targetCoins`, PATCH
 * /admin/agencies/:id/target), progress = that agency's total production.
 *
 * A user can own BOTH a HOSTING and a CHARGING agency (#8), and each carries
 * its own goal — so this returns one entry per agency instead of picking an
 * arbitrary one. Ordered by joinedAt so the default pick is stable.
 * Empty array when the caller owns no approved agency.
 */
const buildAgentTargets = async (userId: number) => {
  const owned = await db.agencyMember.findMany({
    where: { userId, role: 'OWNER', agency: { status: 'approved' } },
    include: { agency: true },
    orderBy: { joinedAt: 'asc' },
  });

  return Promise.all(
    owned.map(async (owner: any) => {
      const goal = Number(owner.agency.targetCoins ?? 0n);
      const earnedCoins = await computeAgencyEarnedCoins(owner.agencyId);
      return {
        agencyId: owner.agencyId,
        agencyName: owner.agency.agencyName,
        agencyType: owner.agency.type,
        goalCoins: goal,
        earnedCoins,
        remainingCoins: goal > 0 ? Math.max(0, goal - earnedCoins) : 0,
        earnedDollars: await coinsToDollars(earnedCoins),
        hasGoal: goal > 0,
      };
    }),
  );
};

// Dollar value for a given earned-coins amount, derived from admin-managed
// TargetTier rows: use the ratio (dollars/coins) of the highest tier whose
// coins threshold is <= the earned amount. No tier reached yet -> $0.
async function coinsToDollars(coins: number): Promise<number> {
  if (coins <= 0) return 0;
  const tiers = await (db as any).targetTier.findMany({ orderBy: { coins: 'asc' } });
  let ratio = 0;
  for (const t of tiers) {
    const tierCoins = Number(t.coins);
    if (tierCoins <= coins && tierCoins > 0) ratio = t.dollars / tierCoins;
  }
  return Math.round(coins * ratio * 100) / 100;
}

// GET /agencies/my-target — the logged-in user's own target(s) as a host.
// earned = gifts received since joining (excluding self-gifts); the goal is
// set per-membership by the agency owner; remaining = goal - earned.
export const getMyTarget = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    // Hosting memberships. Owners are included too: an agent earns gifts like
    // any host and has their own convertedTargetCoins row, so excluding them
    // left تبديل الكوينزات permanently empty for every وكيل.
    const memberships = await db.agencyMember.findMany({
      where: { userId, agency: { type: 'HOSTING', status: 'approved' } },
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
        const converted = Number(mm.convertedTargetCoins ?? 0n);
        return {
          agencyId: mm.agency.id,
          agencyName: mm.agency.agencyName,
          joinedAt: mm.joinedAt,
          earnedCoins,
          targetGoalCoins: goal,
          remainingCoins: goal > 0 ? Math.max(0, goal - earnedCoins) : 0,
          earnedDollars: await coinsToDollars(earnedCoins),
          convertedTargetCoins: converted,
          convertibleCoins: Math.max(0, earnedCoins - converted),
        };
      }),
    );

    // The target card must appear on EVERY profile, not only for hosts in a
    // hosting agency. With no membership there is no goal to hit, but the
    // user's lifetime gift earnings are still what the card reports — so fall
    // back to those instead of returning nothing and hiding the card.
    let totalEarned: number;
    if (items.length > 0) {
      totalEarned = items.reduce((s, i) => s + i.earnedCoins, 0);
    } else {
      const lifetime = await db.giftTransaction.aggregate({
        where: { recipientId: userId, senderId: { not: userId } },
        _sum: { totalCoins: true },
      });
      totalEarned = Number(lifetime._sum.totalCoins ?? 0);
    }

    const totalGifts = await db.giftTransaction.aggregate({
      where: { recipientId: userId, senderId: { not: userId } },
      _sum: { quantity: true },
    });

    // The AGENT's own target, when this user owns an agency. Hosts get their
    // per-membership goal above; the agent's goal is set on the agency by the
    // platform admin and progresses with the whole agency's production.
    //
    // `agencyType` picks which owned agency is meant, exactly like the roster
    // endpoint above — without it a user owning both a HOSTING and a CHARGING
    // agency (#8) would see a different agency here than in وكالة/agency panel.
    // No type given → every owned agency comes back in `agentTargets`, and
    // `agentTarget` stays the earliest-joined one for older clients.
    const requestedType = (req.query as any)?.agencyType
      ? String((req.query as any).agencyType).toUpperCase()
      : undefined;
    const agentTargets = await buildAgentTargets(userId);
    const agentTarget = requestedType
      ? agentTargets.find((t) => t.agencyType === requestedType) ?? null
      : agentTargets[0] ?? null;

    // Drives whether the client offers بيع المستهدف at all — it is an
    // OWNER/BRANCH action on a HOSTING agency, so everyone else was tapping a
    // tile that could only ever answer 403.
    const hostingManager = await findManagerMembership(userId, 'HOSTING');

    const totalDollars = await coinsToDollars(totalEarned);
    return res.json({
      success: true,
      data: {
        totalEarned,
        totalDollars,
        totalGifts: Number(totalGifts._sum.quantity ?? 0),
        canSellMemberTarget: !!hostingManager,
        agentTarget,
        agentTargets,
        // Always true so the client renders the card; `hasGoal` says whether
        // there is an agency-set goal to show progress against.
        hasTarget: true,
        hasGoal: items.length > 0,
        items,
      },
    });
  } catch (e) {
    console.error('[agency.getMyTarget] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/target/convert { agencyId, amount } — تبديل الكوينزات:
// cash out `amount` of ACCUMULATED (uncashed) target as coins at 50%. The
// target total itself is never reduced by this — only future conversions
// are capped by what's already been cashed out (convertedTargetCoins).
export const convertTarget = async (req: AuthReq, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return fail(res, 401, 'Unauthorized');

    const agencyId = Number(req.body?.agencyId);
    const amount = Math.floor(Number(req.body?.amount));
    if (!agencyId || !Number.isFinite(amount) || amount <= 0) {
      return fail(res, 400, 'agencyId و amount مطلوبة');
    }

    // Owners convert their own earned target too — same rule as getMyTarget.
    const membership = await db.agencyMember.findFirst({
      where: { userId, agencyId, agency: { type: 'HOSTING', status: 'approved' } },
    });
    if (!membership) return fail(res, 404, 'لست عضواً في هذه الوكالة');

    const earned = await db.giftTransaction.aggregate({
      where: { recipientId: userId, senderId: { not: userId }, createdAt: { gte: membership.joinedAt } },
      _sum: { totalCoins: true },
    });
    const earnedCoins = Number(earned._sum.totalCoins ?? 0);
    const converted = Number(membership.convertedTargetCoins ?? 0n);
    const available = Math.max(0, earnedCoins - converted);

    if (amount > available) {
      return fail(res, 400, `أقصى مبلغ متاح للتبديل الآن هو ${available} كوينز`);
    }

    const credit = Math.floor(amount / 2);
    const [, updatedUser] = await db.$transaction([
      db.agencyMember.update({
        where: { id: membership.id },
        data: { convertedTargetCoins: { increment: amount } },
      }),
      db.user.update({
        where: { id: userId },
        data: { coinsBalance: { increment: credit } },
        select: { coinsBalance: true },
      }),
    ]);

    return res.json({
      success: true,
      data: { convertedAmount: amount, creditedCoins: credit, newBalance: updatedUser.coinsBalance, remainingConvertible: available - amount },
    });
  } catch (e) {
    console.error('[agency.convertTarget] failed:', e);
    return fail(res, 500, 'Server error');
  }
};

// POST /agencies/target/sell  { memberUserId, amount }
// "بيع المستهدف" (#5) — the agency owner/branch cashes out PART OF A MEMBER's
// own earned-but-unconverted target on their behalf, at the same 50% rate as
// the member's self-service convertTarget above. The coins land on the
// MEMBER's balance (this sells the member's target for them, it does not
// move money to the owner) — distinct from the #4 commission, which is the
// owner's own separate cut credited on gift receipt.
export const sellMemberTarget = async (req: AuthReq, res: Response) => {
  try {
    const ownerId = req.userId;
    if (!ownerId) return fail(res, 401, 'Unauthorized');

    const memberUserId = Number(req.body?.memberUserId);
    const amount = Math.floor(Number(req.body?.amount));
    if (!memberUserId || !Number.isFinite(amount) || amount <= 0) {
      return fail(res, 400, 'memberUserId و amount مطلوبة');
    }

    const manager = await findManagerMembership(ownerId, 'HOSTING');
    if (!manager) return fail(res, 403, 'لست وكيل أو فرع في وكالة استضافة');

    // The agent types the ID they can actually see — the public `displayId`
    // printed on profiles and in the roster — not the internal user.id. Resolve
    // it the same way invite-search does, then fall back to a raw id so an
    // internal id still works.
    const byDisplayId = await db.user.findFirst({
      where: { displayId: memberUserId },
      select: { id: true },
    });
    const resolvedUserId = byDisplayId?.id ?? memberUserId;

    const membership = await db.agencyMember.findFirst({
      where: { userId: resolvedUserId, agencyId: manager.agencyId, role: { not: 'OWNER' } },
    });
    if (!membership) return fail(res, 404, 'هذا المستخدم ليس عضواً في وكالتك');

    const earned = await db.giftTransaction.aggregate({
      where: { recipientId: resolvedUserId, senderId: { not: resolvedUserId }, createdAt: { gte: membership.joinedAt } },
      _sum: { totalCoins: true },
    });
    const earnedCoins = Number(earned._sum.totalCoins ?? 0);
    const converted = Number(membership.convertedTargetCoins ?? 0n);
    const available = Math.max(0, earnedCoins - converted);

    if (amount > available) {
      return fail(res, 400, `أقصى مبلغ متاح للبيع الآن هو ${available} كوينز`);
    }

    const credit = Math.floor(amount / 2);
    const [, updatedUser] = await db.$transaction([
      db.agencyMember.update({
        where: { id: membership.id },
        data: { convertedTargetCoins: { increment: amount } },
      }),
      db.user.update({
        where: { id: resolvedUserId },
        data: { coinsBalance: { increment: credit } },
        select: { coinsBalance: true },
      }),
    ]);

    try {
      await createNotification({
        userId: resolvedUserId,
        actorId: ownerId,
        type: 'TARGET_SOLD',
        title: '🎯 تم بيع جزء من المستهدف',
        body: `قام الوكيل ببيع ${amount} كوينز من رصيد المستهدف الخاص بك مقابل ${credit} كوينز في رصيدك`,
        data: { agencyId: manager.agencyId, amount, credit },
      });
    } catch (e) {
      console.warn('sellMemberTarget notification failed:', e);
    }

    return res.json({
      success: true,
      data: { soldAmount: amount, creditedCoins: credit, memberNewBalance: updatedUser.coinsBalance, remainingConvertible: available - amount },
    });
  } catch (e) {
    console.error('[agency.sellMemberTarget] failed:', e);
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
