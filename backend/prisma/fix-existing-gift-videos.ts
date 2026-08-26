/**
 * Repairs gift clips uploaded before the server started probing/transcoding:
 *  - HEVC/H.265 clips (unplayable in Chrome, flaky on Android decoders) are
 *    re-encoded to H.264 under a NEW filename, so clients that already cached
 *    the broken file refetch the working one.
 *  - animationMs is set to the clip's real duration instead of the 3000ms
 *    schema default, which cut longer clips off mid-play.
 *
 * Run from backend/:  npm run fix:gift-videos
 */
import { PrismaClient } from '@prisma/client';
import path from 'path';
import fs from 'fs/promises';
import { probeGiftVideo, needsTranscode, transcodeToH264 } from '../src/gifts/videoValidate';

const prisma = new PrismaClient();
const UPLOADS = path.join(process.cwd(), 'uploads');

async function main() {
  const gifts = await prisma.gift.findMany({ where: { NOT: { animationUrl: null } } });
  if (gifts.length === 0) {
    console.log('No gifts carry an animationUrl — nothing to do.');
    return;
  }

  for (const g of gifts) {
    const label = g.nameAr ?? g.name;
    const url = g.animationUrl!;
    const name = url.split('/').pop()!.split('?')[0]!;
    const src = path.join(UPLOADS, name);

    try {
      await fs.access(src);
    } catch {
      console.log(`skip ${label}: file not found on disk (${name})`);
      continue;
    }

    let probe;
    try {
      probe = await probeGiftVideo(src);
    } catch (err) {
      console.log(`skip ${label}: ${(err as Error).message}`);
      continue;
    }

    let newUrl = url;
    if (needsTranscode(probe.codec)) {
      const outName = `${name.replace(/\.[^.]+$/, '')}-h264.mp4`;
      const out = path.join(UPLOADS, outName);
      await fs.copyFile(src, out);
      await transcodeToH264(out);
      newUrl = url.replace(name, outName);
    }

    const data: any = {
      format: 'VIDEO',
      animationMs: Math.min(15000, Math.max(1000, probe.durationMs)),
    };
    if (newUrl !== url) data.animationUrl = newUrl;

    await prisma.gift.update({ where: { id: g.id }, data });
    console.log(
      `fixed ${label}: codec=${probe.codec}${newUrl !== url ? ' -> h264 (new file)' : ' (kept)'}, animationMs=${data.animationMs}`,
    );
  }
  console.log('\nDone. Restart is not required — the catalog cache expires within 60s.');
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
