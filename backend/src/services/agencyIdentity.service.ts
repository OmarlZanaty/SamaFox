import { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';
import { auditContext, recordAdminAuditStrict } from './adminAudit.service';

export class AgencyAccessError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

// Rechecked inside financial transactions, so revocation cannot race a charge.
export async function chargingScope(tx: Prisma.TransactionClient, agencyId: number, userId: number, active = false) {
  const agency = await tx.chargingAgency.findUnique({ where: { id: agencyId } });
  if (!agency || agency.type !== 'CHARGING' || agency.status !== 'approved') {
    throw new AgencyAccessError(403, 'وكالة الشحن غير متاحة');
  }
  if (agency.userId === userId) return { agency, branchId: null, isOwner: true };
  const member = await tx.agencyMember.findUnique({ where: { agencyId_userId: { agencyId, userId } } });
  const branch = await tx.agencyBranch.findUnique({
    where: { parentAgencyId_ownerUserId: { parentAgencyId: agencyId, ownerUserId: userId } },
  });
  if (member?.role !== 'BRANCH' || !branch || branch.status === 'CLOSED' || (active && branch.status !== 'ACTIVE')) {
    throw new AgencyAccessError(403, 'لا تملك صلاحية الوصول إلى هذا الفرع');
  }
  return { agency, branchId: branch.id, isOwner: false };
}

export function transferScope(scope: { isOwner: boolean; branchId: number | null }, requested?: unknown) {
  const filter = requested == null || requested === '' ? undefined : Number(requested);
  if (filter !== undefined && (!Number.isSafeInteger(filter) || filter <= 0)) {
    throw new AgencyAccessError(400, 'رقم الفرع غير صالح');
  }
  if (!scope.isOwner && filter !== undefined && filter !== scope.branchId) {
    throw new AgencyAccessError(403, 'لا تملك صلاحية الوصول إلى هذا الفرع');
  }
  return scope.isOwner ? (filter === undefined ? {} : { branchId: filter }) : { branchId: scope.branchId };
}

export async function updateAgencyProfile(req: any, admin = false) {
  const id = Number(req.params.id);
  if (!Number.isSafeInteger(id) || id <= 0) throw new AgencyAccessError(400, 'رقم الوكالة غير صالح');
  return prisma.$transaction(async tx => {
    const before = await tx.chargingAgency.findUnique({ where: { id } });
    if (!before) throw new AgencyAccessError(404, 'الوكالة غير موجودة');
    if (!admin && before.userId !== req.userId) throw new AgencyAccessError(403, 'مالك الوكالة فقط');
    const data: { agencyName?: string; agencyImageUrl?: string; nameLocked?: boolean } = {};
    if (req.body?.agencyName !== undefined) {
      const name = typeof req.body.agencyName === 'string' ? req.body.agencyName.trim() : '';
      if (!name || name.length > 120) throw new AgencyAccessError(400, 'اسم الوكالة غير صالح');
      if (!admin && before.nameLocked && name !== before.agencyName) throw new AgencyAccessError(403, 'اسم الوكالة مقفل');
      data.agencyName = name;
    }
    if (req.body?.agencyImageUrl !== undefined) {
      const image = typeof req.body.agencyImageUrl === 'string' ? req.body.agencyImageUrl.trim() : '';
      if (image.length > 2048 || !/^(https?:\/\/|\/uploads\/)\S+$/i.test(image)) {
        throw new AgencyAccessError(400, 'رابط صورة الوكالة غير صالح');
      }
      data.agencyImageUrl = image;
    }
    if (admin && req.body?.nameLocked !== undefined) {
      if (typeof req.body.nameLocked !== 'boolean') throw new AgencyAccessError(400, 'قيمة قفل الاسم غير صالحة');
      data.nameLocked = req.body.nameLocked;
    }
    if (!Object.keys(data).length) throw new AgencyAccessError(400, 'لا توجد تغييرات');
    const after = await tx.chargingAgency.update({ where: { id }, data });
    for (const [key, field] of [['agencyName', 'name'], ['agencyImageUrl', 'image']] as const) {
      if (before[key] !== after[key]) await tx.agencyProfileChange.create({
        data: { agencyId: id, field, oldValue: before[key], newValue: after[key], changedBy: req.userId },
      });
    }
    if (admin) await recordAdminAuditStrict(tx, {
      adminId: req.userId, action: 'AGENCY_PROFILE_UPDATE', targetType: 'agency', targetId: id,
      before, after, ...auditContext(req),
    });
    return { id, agencyName: after.agencyName, agencyImageUrl: after.agencyImageUrl, nameLocked: after.nameLocked };
  }, { isolationLevel: 'Serializable' });
}

export async function createChargingBranch(req: any, agencyId: number, ownerUserId: number, name?: string) {
  return prisma.$transaction(async tx => {
    const scope = await chargingScope(tx, agencyId, req.userId);
    if (!scope.isOwner) throw new AgencyAccessError(403, 'مالك الوكالة فقط');
    if (!Number.isSafeInteger(ownerUserId) || ownerUserId <= 0 || ownerUserId === req.userId) {
      throw new AgencyAccessError(400, 'مالك الفرع غير صالح');
    }
    const user = await tx.user.findUnique({ where: { id: ownerUserId }, select: { name: true } });
    if (!user) throw new AgencyAccessError(404, 'المستخدم غير موجود');
    const branchName = name === undefined ? user.name : String(name).trim();
    if (!branchName || branchName.length > 120) throw new AgencyAccessError(400, 'اسم الفرع غير صالح');
    const existing = await tx.agencyBranch.findUnique({
      where: { parentAgencyId_ownerUserId: { parentAgencyId: agencyId, ownerUserId } },
    });
    if (existing && existing.status !== 'CLOSED') throw new AgencyAccessError(409, 'الفرع موجود بالفعل');
    if (await tx.agencyMember.count({ where: { agencyId, role: 'BRANCH' } }) >= 3) {
      throw new AgencyAccessError(400, 'الحد الأقصى ثلاثة فروع');
    }
    const after = await tx.agencyBranch.upsert({
      where: { parentAgencyId_ownerUserId: { parentAgencyId: agencyId, ownerUserId } },
      create: { parentAgencyId: agencyId, ownerUserId, name: branchName },
      update: { name: branchName, status: 'ACTIVE' },
    });
    await tx.agencyMember.upsert({
      where: { agencyId_userId: { agencyId, userId: ownerUserId } },
      create: { agencyId, userId: ownerUserId, role: 'BRANCH' }, update: { role: 'BRANCH' },
    });
    await recordAdminAuditStrict(tx, {
      adminId: req.userId, action: 'AGENCY_BRANCH_CREATE', targetType: 'agency_branch', targetId: after.id,
      before: existing, after, ...auditContext(req),
    });
    return after;
  }, { isolationLevel: 'Serializable' });
}

export async function updateChargingBranch(req: any, agencyId: number, branchId: number, admin = false) {
  return prisma.$transaction(async tx => {
    if (!admin && !(await chargingScope(tx, agencyId, req.userId)).isOwner) {
      throw new AgencyAccessError(403, 'مالك الوكالة فقط');
    }
    const before = await tx.agencyBranch.findFirst({ where: { id: branchId, parentAgencyId: agencyId } });
    if (!before) throw new AgencyAccessError(404, 'الفرع غير موجود');
    const data: { name?: string; status?: string } = {};
    if (req.body?.name !== undefined && !admin) {
      data.name = String(req.body.name).trim();
      if (!data.name || data.name.length > 120) throw new AgencyAccessError(400, 'اسم الفرع غير صالح');
    }
    if (req.body?.status !== undefined) {
      if (!['ACTIVE', 'SUSPENDED', 'CLOSED'].includes(req.body.status)) throw new AgencyAccessError(400, 'حالة الفرع غير صالحة');
      data.status = req.body.status;
    }
    if (!Object.keys(data).length) throw new AgencyAccessError(400, 'لا توجد تغييرات');
    if (before.status === 'CLOSED' && data.status && data.status !== 'CLOSED') {
      if (await tx.agencyMember.count({ where: { agencyId, role: 'BRANCH' } }) >= 3) {
        throw new AgencyAccessError(400, 'الحد الأقصى ثلاثة فروع');
      }
    }
    const after = await tx.agencyBranch.update({ where: { id: branchId }, data });
    if (data.status) {
      await tx.agencyMember.upsert({
        where: { agencyId_userId: { agencyId, userId: before.ownerUserId } },
        create: { agencyId, userId: before.ownerUserId, role: data.status === 'CLOSED' ? 'MEMBER' : 'BRANCH' },
        update: { role: data.status === 'CLOSED' ? 'MEMBER' : 'BRANCH' },
      });
    }
    await recordAdminAuditStrict(tx, {
      adminId: req.userId, action: 'AGENCY_BRANCH_UPDATE', targetType: 'agency_branch', targetId: branchId,
      before, after, ...auditContext(req),
    });
    return after;
  }, { isolationLevel: 'Serializable' });
}
