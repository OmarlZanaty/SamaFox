import prisma from './prisma';

/** Human-entered IDs resolve public IDs first. Never use this for foreign keys. */
export async function resolveUserByPublicId(n: number, db: any = prisma, select: any = { id: true, displayId: true, name: true }) {
  if (!Number.isSafeInteger(n) || n <= 0 || n > 2147483647) return null;
  return (await db.user.findUnique({ where: { displayId: n }, select }))
    ?? (await db.user.findUnique({ where: { id: n }, select }));
}
