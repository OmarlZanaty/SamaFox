import 'dotenv/config';
import { Prisma, PrismaClient } from '@prisma/client';
import { GIFT_TEMPLATES } from '../src/gifts/templates';

const prisma = new PrismaClient();

async function main() {
  let inserted = 0;
  let updated = 0;
  let i = 0;
  for (const t of GIFT_TEMPLATES) {
    const existing = await prisma.gift.findFirst({ where: { name: t.name } });
    const data = {
      name: t.name,
      nameAr: t.nameAr,
      iconUrl: `/assets/icons/${t.key}.png`,
      format: 'SVG_CSS' as const,
      animationHtml: t.html,
      animationUrl: null,
      videoHasAlpha: false,
      fireworksEnabled: false,
      fireworksColors: Prisma.JsonNull,
      coinCost: t.coinCost,
      tier: t.tier,
      animationMs: t.animationMs,
      isComboEligible: t.tier !== 'LEGENDARY',
      broadcastGlobal: t.tier === 'LEGENDARY',
      isActive: true,
      sortOrder: i + 1,
      category: t.category,
    };
    if (existing) {
      await prisma.gift.update({ where: { id: existing.id }, data });
      updated++;
    } else {
      await prisma.gift.create({ data });
      inserted++;
    }
    i++;
  }
  console.log(`Gift seed complete. Inserted: ${inserted}, Updated: ${updated}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
