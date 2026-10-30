import { Request, Response } from 'express';
import type {} from '../middlewares/auth.middleware'; // req.userId typing
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import prisma from '../utils/prisma';
import { getPublicBaseUrl } from '../utils/public-url';
import { resolveUserByPublicId } from '../utils/resolveUserByPublicId';
import { normalizeBannedName, sha256 } from '../services/nameImageBan.service';

const db = prisma as any;
export const banHandler = (fn: (req: Request) => Promise<any>) => async (req: Request, res: Response) => {
  try { return res.json({ success: true, data: await fn(req) }); }
  catch (e: any) {
    if (!e.status) console.error('[nameImageBan]', e);
    return res.status(e.status || 500).json({ success: false, message: e.status ? e.message : 'تعذر تنفيذ الطلب' });
  }
};
export function banError(status: number, message: string): never { throw Object.assign(new Error(message), { status }); }
export function positiveId(value: unknown): number {
  const id = Number(value);
  if (!Number.isSafeInteger(id) || id <= 0 || id > 2147483647) banError(400, 'رقم غير صالح');
  return id;
}
async function currentUser(req: Request) {
  const user = await db.user.findUnique({ where: { id: positiveId(req.params.userId) } });
  if (!user) banError(404, 'المستخدم غير موجود');
  return user;
}
export const banUserName = banHandler(async req => {
  const user = await currentUser(req);
  const value = normalizeBannedName(user.name);
  if (!value) banError(400, 'الاسم فارغ');
  return db.$transaction(async (tx: any) => {
    const row = await tx.bannedName.upsert({ where: { value }, update: {}, create: { value, original: user.name, createdById: req.userId } });
    const name = `مستخدم${user.displayId ?? user.id}`;
    await tx.user.update({ where: { id: user.id }, data: { name } });
    await tx.adminAuditLog.create({ data: { adminId: req.userId, action: 'BAN_USER_NAME', targetUserId: user.id, before: { name: user.name }, after: { name, bannedNameId: row.id } } });
    return row;
  });
});
async function avatarBytes(url: string, req: Request): Promise<Buffer> {
  const base = new URL(getPublicBaseUrl(req));
  const avatar = new URL(url, base);
  const prefix = `${base.pathname.replace(/\/$/, '')}/uploads/`;
  if (avatar.origin === base.origin && avatar.pathname.startsWith(prefix)) {
    const filename = decodeURIComponent(avatar.pathname.slice(prefix.length));
    if (!filename || path.basename(filename) !== filename || /[\\/]/.test(filename)) banError(400, 'مسار الصورة غير صالح');
    return readFile(path.join(__dirname, '../../uploads', filename));
  }
  if (!['http:', 'https:'].includes(avatar.protocol)) banError(400, 'رابط الصورة غير صالح');
  const response = await fetch(avatar.href, { signal: AbortSignal.timeout(5000) });
  if (!response.ok) banError(400, 'تعذر تحميل الصورة');
  return Buffer.from(await response.arrayBuffer());
}
export const banUserImage = banHandler(async req => {
  const user = await currentUser(req);
  if (!user.avatarUrl) banError(400, 'لا توجد صورة للمستخدم');
  const hash = sha256(await avatarBytes(user.avatarUrl, req));
  return db.$transaction(async (tx: any) => {
    const row = await tx.bannedImage.upsert({ where: { sha256: hash }, update: {}, create: { sha256: hash, sampleUrl: user.avatarUrl, createdById: req.userId } });
    await tx.user.update({ where: { id: user.id }, data: { avatarUrl: null } });
    await tx.adminAuditLog.create({ data: { adminId: req.userId, action: 'BAN_USER_IMAGE', targetUserId: user.id, before: { avatarUrl: user.avatarUrl }, after: { bannedImageId: row.id, avatarUrl: null } } });
    return row;
  });
});
export const listNameBans = banHandler(async () => db.bannedName.findMany({ orderBy: { id: 'desc' } }));
export const listImageBans = banHandler(async () => db.bannedImage.findMany({ orderBy: { id: 'desc' } }));
export const deleteNameBan = banHandler(async req => db.bannedName.deleteMany({ where: { id: positiveId(req.params.id) } }));
export const deleteImageBan = banHandler(async req => db.bannedImage.deleteMany({ where: { id: positiveId(req.params.id) } }));
export const listBanBypass = banHandler(async () => {
  const rows = await db.banBypassUser.findMany({ orderBy: { id: 'desc' } });
  const users = await db.user.findMany({ where: { id: { in: rows.map((r: any) => r.userId) } }, select: { id: true, displayId: true, name: true } });
  return rows.map((r: any) => ({ ...r, user: users.find((u: any) => u.id === r.userId) ?? null }));
});
export const addBanBypass = banHandler(async req => {
  const user = await resolveUserByPublicId(positiveId(req.body.publicId));
  if (!user) banError(404, 'المستخدم غير موجود');
  return db.banBypassUser.upsert({ where: { userId: user.id }, update: {}, create: { userId: user.id, createdById: req.userId } });
});
export const deleteBanBypass = banHandler(async req => db.banBypassUser.deleteMany({ where: { userId: positiveId(req.params.userId) } }));
