// Run manually from backend: npx ts-node tools/backfill-video-posters.ts
import 'dotenv/config';
import path from 'path';
import fs from 'fs/promises';
import prisma from '../src/utils/prisma';
import { extractPosterFrame } from '../src/gifts/videoValidate';
import { localVideoPath } from '../src/utils/videoPosterBackfill';

async function main() {
  const uploads = path.resolve(process.env.UPLOADS_DIR || 'uploads');
  let cursor: string | undefined;
  let saved = 0, skipped = 0;
  for (;;) {
    const items = await prisma.item.findMany({
      where: { OR: [{ previewUrl: null }, { previewUrl: '' }] },
      orderBy: { id: 'asc' }, take: 100,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      select: { id: true, assetUrl: true },
    });
    if (!items.length) break;
    for (const item of items) {
      cursor = item.id;
      const file = localVideoPath(item.assetUrl, uploads);
      if (!file) { skipped++; continue; }
      try {
        await fs.access(file);
        const poster = await extractPosterFrame(file);
        if (!poster) throw new Error('No poster extracted');
        const url = new URL(item.assetUrl, process.env.BASE_URL || 'http://local');
        url.pathname += '.poster.jpg'; url.search = ''; url.hash = '';
        const previewUrl = /^https?:/i.test(item.assetUrl) ? url.toString() : url.pathname;
        const updated = await prisma.item.updateMany({
          where: { id: item.id, assetUrl: item.assetUrl, OR: [{ previewUrl: null }, { previewUrl: '' }] },
          data: { previewUrl },
        });
        saved += updated.count;
      } catch (e) { skipped++; console.warn(item.id, (e as Error).message); }
    }
  }
  console.log({ saved, skipped });
}
main().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => prisma.$disconnect());
