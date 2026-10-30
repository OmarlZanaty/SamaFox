import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { resolveUserByPublicId } from '../utils/resolveUserByPublicId';
import { recordAdminAuditStrict, auditContext } from '../services/adminAudit.service';

const fail = (res: Response, code: number, message: string) => res.status(code).json({ success: false, message });

export async function listHeldItems(req: Request, res: Response) {
  try {
    const user = await resolveUserByPublicId(Number(req.params.publicId));
    if (!user) return fail(res, 404, 'المستخدم غير موجود');
    const items = await prisma.userItem.findMany({ where: { userId: user.id,
      OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
    }, include: { item: true }, orderBy: { acquiredAt: 'desc' } });
    return res.json({ success: true, data: { user, items } });
  } catch (e) { console.error('[grants.list]', e); return fail(res, 500, 'تعذر تحميل ممتلكات المستخدم'); }
}

/** Delete ownership and clear equipped references together; catalogue is retained. */
export async function revokeHeldItem(req: Request, res: Response) {
  try {
    const itemId = String(req.body?.itemId ?? '');
    const all = req.body?.scope === 'all';
    const user = all ? null : await resolveUserByPublicId(Number(req.body?.publicId));
    if (!itemId || (!all && !user)) return fail(res, 400, 'حدد المنتج والمستخدم أو الكل');
    const result = await prisma.$transaction(async (tx) => {
      const item = await tx.item.findUnique({ where: { id: itemId } });
      if (!item) return null;
      // Bulk withdrawal removes grants, preserving purchases and gifts.
      const where = { itemId, ...(all ? { source: 'grant' } : { userId: user.id }) };
      const rows = await tx.userItem.findMany({ where });
      const ids = rows.map(r => r.userId);
      await tx.user.updateMany({ where: { id: { in: ids }, activeFrameId: itemId }, data: { activeFrameId: null, avatarFrameUrl: null } });
      await tx.room.updateMany({ where: { ownerId: { in: ids }, activeThemeId: itemId }, data: { activeThemeId: null } });
      if (item.assetUrl && item.type === 'PROFILE_BACKGROUND') {
        await tx.user.updateMany({ where: { id: { in: ids }, profileBgUrl: item.assetUrl }, data: { profileBgUrl: null, profileBgType: 'image' } });
      }
      if (item.assetUrl && item.type === 'PROFILE_DECOR') {
        await tx.user.updateMany({ where: { id: { in: ids }, profileDecorUrl: item.assetUrl }, data: { profileDecorUrl: null, profileDecorType: 'image' } });
      }
      await tx.userItem.deleteMany({ where });
      if (all) await tx.item.update({ where: { id: itemId }, data: { grantToAll: false } });
      // End temporary grants too so expiry processing cannot restore withdrawn ownership.
      await tx.temporaryEntitlement.updateMany({ where: { userId: { in: ids }, itemId, status: 'ACTIVE' }, data: { status: 'REVOKED' } });
      await recordAdminAuditStrict(tx, { adminId: Number((req as any).userId), action: 'ITEM_REVOKE',
        targetUserId: user?.id, targetType: 'item', targetId: itemId,
        before: { rows, grantToAll: item.grantToAll }, after: { count: rows.length, scope: all ? 'all' : 'user' }, ...auditContext(req) });
      return { count: rows.length };
    });
    if (!result) return fail(res, 404, 'المنتج غير موجود');
    return res.json({ success: true, data: result });
  } catch (e) { console.error('[grants.revoke]', e); return fail(res, 500, 'تعذر سحب المنتج'); }
}
