import { Request, Response } from 'express';
import prisma from '../utils/prisma';
import { AgencyAccessError, chargingScope, transferScope, updateAgencyProfile, createChargingBranch, updateChargingBranch } from '../services/agencyIdentity.service';

export function agencyError(res: Response, error: unknown) {
  if (error instanceof AgencyAccessError) return res.status(error.status).json({ success: false, message: error.message });
  if (['P2034', 'P2002'].includes((error as any)?.code)) return res.status(409).json({ success: false, message: 'تم تعديل البيانات للتو، حاول مجدداً' });
  console.error('[agencyIdentity]', error);
  return res.status(500).json({ success: false, message: 'تعذر إتمام العملية' });
}

export const profile = async (req: Request, res: Response) => {
  try { return res.json({ success: true, data: await updateAgencyProfile(req) }); }
  catch (e) { return agencyError(res, e); }
};
export const profileHistory = async (req: Request, res: Response) => {
  try {
    const agency = await prisma.chargingAgency.findUnique({ where: { id: Number(req.params.id) } });
    const user = await prisma.user.findUnique({ where: { id: req.userId! }, select: { isAdmin: true, isOwner: true } });
    if (!agency || (agency.userId !== req.userId && !user?.isAdmin && !user?.isOwner)) throw new AgencyAccessError(403, 'غير مسموح');
    const data = await prisma.agencyProfileChange.findMany({
      where: { agencyId: agency.id }, orderBy: { id: 'desc' }, take: 100,
      ...(req.query.beforeId ? { cursor: { id: Number(req.query.beforeId) }, skip: 1 } : {}),
    });
    return res.json({ success: true, data });
  } catch (e) { return agencyError(res, e); }
};
export const branches = (admin = false) => async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const scope = admin ? null : await chargingScope(prisma, id, req.userId!);
    const data = await prisma.agencyBranch.findMany({
      where: { parentAgencyId: id, ...(scope && !scope.isOwner ? { id: scope.branchId! } : {}) },
      orderBy: { id: 'asc' },
    });
    return res.json({ success: true, data });
  } catch (e) { return agencyError(res, e); }
};
export const createBranch = async (req: Request, res: Response) => {
  try {
    return res.status(201).json({ success: true, data: await createChargingBranch(req, Number(req.params.id), Number(req.body.ownerUserId), req.body.name) });
  } catch (e) { return agencyError(res, e); }
};
export const patchBranch = (admin = false) => async (req: Request, res: Response) => {
  try {
    return res.json({ success: true, data: await updateChargingBranch(req, Number(req.params.id), Number(req.params.branchId), admin) });
  } catch (e) { return agencyError(res, e); }
};
export const branchTransfers = async (req: Request, res: Response) => {
  try {
    const id = Number(req.params.id);
    const scope = await chargingScope(prisma, id, req.userId!);
    const where = { agencyId: id, ...transferScope(scope, req.params.branchId) };
    const data = await prisma.agencyTransfer.findMany({
      where, include: { branch: true, toUser: { select: { id: true, name: true } } },
      orderBy: { id: 'desc' }, take: 100,
      ...(req.query.beforeId ? { cursor: { id: Number(req.query.beforeId) }, skip: 1 } : {}),
    });
    return res.json({ success: true, data: data.map(r => ({ ...r, parentAgencyId: r.agencyId, coins: r.amount })) });
  } catch (e) { return agencyError(res, e); }
};
