/**
 * One-time backfill: gifts that were uploaded with a video file but left on
 * format = 'SVG_CSS' render as a still image on the client. Flip them to
 * 'VIDEO' so GiftPlayer routes them to the video player.
 *
 * Run once after deploy:  npx ts-node prisma/fix-gift-video-format.ts
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const VIDEO_EXTENSIONS = ['.mp4', '.webm', '.mov', '.m4v', '.ogv'];

function looksLikeVideo(url: string | null): boolean {
  if (!url) return false;
  const path = (url.split('?')[0] ?? '').split('#')[0]?.toLowerCase() ?? '';
  return VIDEO_EXTENSIONS.some((ext) => path.endsWith(ext));
}

async function main() {
  const gifts = await prisma.gift.findMany({
    select: { id: true, name: true, format: true, animationUrl: true },
  });

  const broken = gifts.filter((g) => g.format !== 'VIDEO' && looksLikeVideo(g.animationUrl));
  if (broken.length === 0) {
    console.log('Nothing to fix — no gifts have a video URL with a non-VIDEO format.');
    return;
  }

  for (const g of broken) {
    await prisma.gift.update({ where: { id: g.id }, data: { format: 'VIDEO' } });
    console.log(`fixed: ${g.name} (${g.id}) -> VIDEO  [${g.animationUrl}]`);
  }
  console.log(`\nDone. ${broken.length} gift(s) switched to VIDEO.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
