import { findBlockingMembership, ALREADY_IN_AGENCY_MESSAGE } from '../agencies/oneAgencyRule';
import prisma from '../utils/prisma';
import { AgencyAccessError } from './agencyIdentity.service';
import { createNotification } from './notification.service';

export const MAX_BRANCHES = 3;

export const INVITE_TTL = 7 * 86_400_000;

export async function markInviteNotificationsRead(inviteeId: number, inviteId: number) {
  // 2026-10-23 — completed/replaced invites must no longer show action buttons.
  try {
    await prisma.notification.updateMany({
      where: { userId: inviteeId, type: 'AGENCY_INVITE', isRead: false, data: { path: ['inviteId'], equals: inviteId } },
      data: { isRead: true, readAt: new Date() },
    });
  } catch (e) {
    console.warn('[invite notifications read]', e);
  }
}

export async function expireAgencyInvites(where: { agencyId?: number; inviteeId?: number } = {}, now = new Date()) {
  return prisma.agencyInvite.updateMany({
    where: { ...where, status: 'pending', expiresAt: { lte: now } },
    data: { status: 'expired', updatedAt: now },
  });
}

export async function newAgencyInvite(agencyId: number, inviterId: number, inviteeId: number) {
  await expireAgencyInvites({ agencyId });
  const pending = await prisma.agencyInvite.findFirst({ where: { agencyId, inviteeId, status: 'pending' } });
  if (pending) return { invite: pending, existing: true };
  try {
    const invite = await prisma.agencyInvite.create({
      data: { agencyId, inviterId, inviteeId, expiresAt: new Date(Date.now() + INVITE_TTL) },
    });
    return { invite, existing: false };
  } catch (e: any) {
    if (e.code !== 'P2002') throw e;
    const raced = await prisma.agencyInvite.findFirst({ where: { agencyId, inviteeId, status: 'pending' } });
    if (!raced) throw e;
    return { invite: raced, existing: true };
  }
}

// Both branch entry points reserve a slot without granting access.
export async function requestBranchInvite(agencyId: number, inviterId: number, inviteeId: number) {
  const invite = await prisma.$transaction(async tx => {
    const agency = await tx.chargingAgency.findUnique({ where: { id: agencyId } });
    if (!agency || agency.userId !== inviterId || agency.status !== 'approved') {
      throw new AgencyAccessError(403, 'مالك الوكالة المعتمدة فقط');
    }
    if (!Number.isSafeInteger(inviteeId) || inviteeId <= 0 || inviteeId === inviterId) {
      throw new AgencyAccessError(400, 'مستخدم الفرع غير صالح');
    }
    if (!await tx.user.findUnique({ where: { id: inviteeId } })) throw new AgencyAccessError(404, 'المستخدم غير موجود');
    const seat = await tx.agencyMember.findUnique({ where: { agencyId_userId: { agencyId, userId: inviteeId } } });
    if (seat?.role === 'BRANCH' || seat?.role === 'OWNER') throw new AgencyAccessError(400, 'المستخدم فرع أو مالك بالفعل');
    if (await findBlockingMembership(tx, inviteeId, agencyId, 'BRANCH')) {
      throw new AgencyAccessError(409, ALREADY_IN_AGENCY_MESSAGE, 'ALREADY_IN_AGENCY');
    }
    const now = new Date();
    await tx.agencyInvite.updateMany({ where: { agencyId, status: 'pending', expiresAt: { lte: now } }, data: { status: 'expired', updatedAt: now } });
    const pending = await tx.agencyInvite.findFirst({ where: { agencyId, inviteeId, status: 'pending' } });
    if (pending) {
      if (pending.role === 'BRANCH') return pending;
      throw new AgencyAccessError(409, 'توجد دعوة عضوية معلقة لهذا المستخدم — ألغِ دعوة العضوية أولاً ثم أرسل طلب الفرع');
    }
    const branches = await tx.agencyMember.count({ where: { agencyId, role: 'BRANCH' } });
    const pendingBranches = await tx.agencyInvite.count({ where: { agencyId, role: 'BRANCH', status: 'pending' } });
    if (branches + pendingBranches >= MAX_BRANCHES) throw new AgencyAccessError(400, 'الحد الأقصى ثلاثة فروع بما فيها الطلبات المعلقة');
    return tx.agencyInvite.create({ data: { agencyId, inviterId, inviteeId, role: 'BRANCH', expiresAt: new Date(now.getTime() + INVITE_TTL) } });
  }, { isolationLevel: 'Serializable' });
  await notifyAgencyInvite(invite).catch(e => console.warn('[invite notification]', e));
  return { invite, state: 'PENDING' };
}

export async function notifyAgencyInvite(invite: { id: number; agencyId: number; inviteeId: number; inviterId: number; role?: string }) {
  const agency = await prisma.chargingAgency.findUnique({ where: { id: invite.agencyId }, select: { agencyName: true, type: true } });
  const role = invite.role ?? 'MEMBER';
  await createNotification({
    userId: invite.inviteeId, actorId: invite.inviterId, type: 'AGENCY_INVITE',
    title: role === 'BRANCH' ? 'دعوة لتكون فرعاً في وكالة' : 'دعوة للانضمام إلى وكالة',
    body: role === 'BRANCH'
      ? `تمت دعوتك لتكون فرعاً في وكالة ${agency?.agencyName ?? ''} (${agency?.type === 'HOSTING' ? 'مضيفين' : 'شحن'})`
      : `تمت دعوتك للانضمام إلى وكالة ${agency?.agencyName ?? ''}`,
    data: { inviteId: invite.id, agencyId: invite.agencyId, role },
  });
}

export async function changePendingInvite(userId: number, inviteId: number, resend: boolean) {
  await expireAgencyInvites();
  const invite = await prisma.$transaction(async tx => {
    const before = await tx.agencyInvite.findUnique({ where: { id: inviteId }, include: { agency: true } });
    if (!before) throw new AgencyAccessError(404, 'الدعوة غير موجودة');
    const manager = await tx.agencyMember.findFirst({
      where: { userId, agencyId: before.agencyId, role: { in: ['OWNER', 'BRANCH'] } },
    });
    if (before.agency.userId !== userId && (before.inviterId !== userId || !manager)) {
      throw new AgencyAccessError(403, 'غير مسموح');
    }
    if (before.status !== 'pending') throw new AgencyAccessError(409, 'الدعوة لم تعد معلقة');
    if (resend && before.agency.status !== 'approved') throw new AgencyAccessError(403, 'الوكالة غير متاحة');
    const now = new Date();
    const changed = await tx.agencyInvite.updateMany({
      where: { id: inviteId, status: 'pending', OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
      data: resend
        ? { resentAt: now, resendCount: { increment: 1 }, expiresAt: new Date(now.getTime() + INVITE_TTL), updatedAt: now }
        : { status: 'cancelled', respondedAt: now, updatedAt: now },
    });
    if (!changed.count) throw new AgencyAccessError(409, 'الدعوة لم تعد معلقة');
    return tx.agencyInvite.findUniqueOrThrow({ where: { id: inviteId } });
  }, { isolationLevel: 'Serializable' });
  await markInviteNotificationsRead(invite.inviteeId, invite.id);
  if (resend) await notifyAgencyInvite(invite).catch(e => console.warn('[invite notification]', e));
  return invite;
}
