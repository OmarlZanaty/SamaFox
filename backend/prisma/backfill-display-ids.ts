/**
 * One-time backfill: give every user a 6-digit public display ID.
 * Run once after deploying the 6-digit switch:
 *   npx ts-node prisma/backfill-display-ids.ts
 */
import { PrismaClient } from '@prisma/client';
import { nextDisplayId, MIN_DISPLAY_ID } from '../src/utils/displayId';

const prisma = new PrismaClient();

async function main() {
  const stale = await prisma.user.findMany({
    where: { OR: [{ displayId: null }, { displayId: { lt: MIN_DISPLAY_ID } }] },
    select: { id: true, displayId: true, name: true },
    orderBy: { id: 'asc' },
  });

  console.log(`Found ${stale.length} user(s) needing a 6-digit ID.`);

  for (const u of stale) {
    const newId = await prisma.$transaction((tx) => nextDisplayId(tx));
    await prisma.user.update({ where: { id: u.id }, data: { displayId: newId } });
    console.log(`  user ${u.id} (${u.name}): ${u.displayId ?? 'null'} -> ${newId}`);
  }

  console.log('Backfill complete.');
}

main()
  .catch((e) => {
    console.error('Backfill failed:', e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
