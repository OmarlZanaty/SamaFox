import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const gifts = [
  { name: 'Rose', nameAr: 'ورد', imageUrl: '/gifts/ward.png', animationUrl: null, priceCoins: 100, coinsValue: 100, sortOrder: 1, category: 'arabic', isActive: true },
  { name: 'Heart', nameAr: 'قلب', imageUrl: '/gifts/heart.png', animationUrl: null, priceCoins: 250, coinsValue: 250, sortOrder: 2, category: 'arabic', isActive: true },
  { name: 'Star', nameAr: 'نجمة', imageUrl: '/gifts/star.png', animationUrl: null, priceCoins: 500, coinsValue: 500, sortOrder: 3, category: 'arabic', isActive: true },
  { name: 'Crown', nameAr: 'تاج', imageUrl: '/gifts/crown.png', animationUrl: null, priceCoins: 900, coinsValue: 900, sortOrder: 4, category: 'arabic', isActive: true },
  { name: 'Car', nameAr: 'سيارة', imageUrl: '/gifts/car.png', animationUrl: null, priceCoins: 1500, coinsValue: 1500, sortOrder: 5, category: 'arabic', isActive: true },
  { name: 'Plane', nameAr: 'طيارة', imageUrl: '/gifts/plane.png', animationUrl: null, priceCoins: 5000, coinsValue: 5000, sortOrder: 6, category: 'arabic', isActive: true },
  { name: 'Castle', nameAr: 'قصر', imageUrl: '/gifts/castle.png', animationUrl: null, priceCoins: 9000, coinsValue: 9000, sortOrder: 7, category: 'arabic', isActive: true },
  { name: 'Yacht', nameAr: 'يخت', imageUrl: '/gifts/yacht.png', animationUrl: null, priceCoins: 12000, coinsValue: 12000, sortOrder: 8, category: 'arabic', isActive: true }
];

async function seedGifts() {
  console.log('🎁 Starting gift seeding...');
  try {
    await prisma.gift.deleteMany({});
    console.log('✅ Cleared existing gifts');
    for (const gift of gifts) {
      await prisma.gift.create({ data: gift });
      console.log(`✅ Created: ${gift.name} (${gift.priceCoins} coins)`);
    }
    console.log(`\n🎉 Successfully seeded ${gifts.length} gifts!`);
  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  } finally {
    await prisma.$disconnect();
  }
}

seedGifts().catch((error) => { console.error(error); process.exit(1); });
