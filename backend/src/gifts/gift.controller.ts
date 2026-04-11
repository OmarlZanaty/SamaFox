import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export const listGifts = async (_req: Request, res: Response) => {
  const gifts = await prisma.gift.findMany({
    where: { isActive: true },
    orderBy: { sortOrder: 'asc' },
    select: {
      id: true,
      nameAr: true,
      imageUrl: true,
      animationUrl: true,
      coinsValue: true,
      sortOrder: true,
    },
  });

  return res.json({ success: true, data: gifts });
};
