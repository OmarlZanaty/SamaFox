import { createHash } from 'node:crypto';
import prisma from '../utils/prisma';

const db = prisma as any;
export function normalizeBannedName(s: string): string {
  return s.replace(/[\u064B-\u065F\u0670\u0640]/g, '').trim().toLowerCase().replace(/\s+/g, ' ');
}
export const sha256 = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');
export async function isBanBypassUser(userId?: number): Promise<boolean> {
  return !!(userId && await db.banBypassUser.findUnique({ where: { userId } }));
}
export async function isNameBanned(name: string, userId?: number): Promise<boolean> {
  if (await isBanBypassUser(userId)) return false;
  return !!await db.bannedName.findUnique({ where: { value: normalizeBannedName(name) } });
}
export async function isImageHashBanned(hash: string, userId?: number): Promise<boolean> {
  if (await isBanBypassUser(userId)) return false;
  return !!await db.bannedImage.findUnique({ where: { sha256: hash.toLowerCase() } });
}
export async function isImageUrlBanned(sampleUrl: string, userId?: number): Promise<boolean> {
  if (await isBanBypassUser(userId)) return false;
  return !!await db.bannedImage.findFirst({ where: { sampleUrl } });
}
