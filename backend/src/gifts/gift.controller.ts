import { Request, Response } from 'express';
import { prisma } from '../lib/prisma';

export const listGifts = async (_req: Request, res: Response) => {
  const gifts = await prisma.gift.findMany({
    where: { isActive: true },
    orderBy: { sortOrder: 'asc' },
    select: {
      id: true,
      name: true,
      nameAr: true,
      imageUrl: true,
      animationUrl: true,
      category: true,
      isActive: true,
      priceCoins: true,
      coinsValue: true,
      sortOrder: true,
    },
  });
  return res.json({
    success: true,
    data: gifts.map((gift) => ({
      ...gift,
      coinsValue: gift.coinsValue > 0 ? gift.coinsValue : gift.priceCoins,
    })),
  });
};
