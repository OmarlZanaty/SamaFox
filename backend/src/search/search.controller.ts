import { resolveUserByPublicId } from '../utils/resolveUserByPublicId';
import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export const search = async (req: Request, res: Response) => {
  const q = String(req.query.q ?? '').trim();
  const type = String(req.query.type ?? 'all');

  if (!q) {
    return res.status(400).json({ success: false, message: 'Query q is required' });
  }

  const isNum = /^\d+$/.test(q);
  const numQ = isNum ? Number(q) : null;

  const [rooms, users] = await Promise.all([
    type === 'all' || type === 'rooms'
      ? prisma.room.findMany({
          where: {
            isActive: true,
            OR: [
              { name: { contains: q } },
              ...(numQ !== null ? [{ id: numQ }] : []),
            ],
          },
          select: {
            id: true,
            name: true,
            coverImageUrl: true,
            members: { select: { userId: true } },
          },
          take: 20,
        })
      : Promise.resolve([]),

    type === 'all' || type === 'users'
      ? prisma.user.findMany({
          where: {
            isBanned: false,
            OR: [
              ...(numQ === null ? [{ name: { contains: q } }] : []),
              ...(numQ !== null ? [{ id: (await resolveUserByPublicId(numQ))?.id ?? -1 }] : []),
            ],
          },
          select: {
            id: true,
            name: true,
            avatarUrl: true,
            displayId: true,
            level: true,
          },
          take: 20,
        })
      : Promise.resolve([]),
  ]);

  const results = [
    ...rooms.map((r) => ({
      type: 'room',
      id: r.id,
      name: r.name,
      imageUrl: r.coverImageUrl,
      subtitle: `${r.members.length} مستخدم`,
    })),
    ...users.map((u) => ({
      type: 'user',
      id: u.id,
      name: u.name,
      imageUrl: u.avatarUrl,
      displayId: u.displayId,
      subtitle: `#${u.displayId ?? u.id}`,
      level: u.level,
    })),
  ];

  return res.json({ success: true, data: results, query: q });
};