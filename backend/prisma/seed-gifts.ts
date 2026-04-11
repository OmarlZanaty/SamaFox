import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();
async function main() {
  const gifts = [
    { nameAr: 'ورد',    coinsValue: 50,    sortOrder: 1,  imageUrl: '/gifts/ward.png' },
    { nameAr: 'قلب',    coinsValue: 100,   sortOrder: 2,  imageUrl: '/gifts/heart.png' },
    { nameAr: 'نجمة',   coinsValue: 200,   sortOrder: 3,  imageUrl: '/gifts/star.png' },
    { nameAr: 'تاج',    coinsValue: 500,   sortOrder: 4,  imageUrl: '/gifts/crown.png' },
    { nameAr: 'سيارة',  coinsValue: 1000,  sortOrder: 5,  imageUrl: '/gifts/car.png' },
    { nameAr: 'طيارة',  coinsValue: 2000,  sortOrder: 6,  imageUrl: '/gifts/plane.png' },
    { nameAr: 'قصر',    coinsValue: 5000,  sortOrder: 7,  imageUrl: '/gifts/palace.png' },
    { nameAr: 'يخت',    coinsValue: 10000, sortOrder: 8,  imageUrl: '/gifts/yacht.png' },
    { nameAr: 'خاتم',   coinsValue: 1000,  sortOrder: 9,  imageUrl: '/gifts/ring.png' },
  ];
  for (const g of gifts) {
    await prisma.gift.upsert({ where: { id: g.sortOrder }, update: g, create: g });
  }
  console.log('Gifts seeded.');
}
main().finally(() => prisma.$disconnect());
