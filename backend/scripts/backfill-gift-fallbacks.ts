/**
 * SPEC52 #24 — one-off: build the H.264 Baseline fallback rendition for video
 * gifts uploaded before the fallback existed, and store gifts.videoFallbackUrl.
 *
 *   npx ts-node scripts/backfill-gift-fallbacks.ts            # dry run — reports only
 *   npx ts-node scripts/backfill-gift-fallbacks.ts --apply    # do it
 *
 * The original clip is never touched; the copy is written next to it as
 * `<file>.baseline.mp4`. Not run automatically.
 */
import fs from 'fs/promises';
import path from 'path';
import prisma from '../src/utils/prisma';
import { createGiftFallback } from '../src/utils/mediaOptimize';
import { bumpCatalogVersion } from '../src/gifts/catalogCache';

const APPLY = process.argv.includes('--apply');
const ASSETS = process.env.GIFT_ASSETS_DIR?.trim() || path.join(process.cwd(), 'public', 'assets');
const UPLOADS = path.join(process.cwd(), 'uploads');

/** The file on this server behind a gift's animationUrl, or null. */
async function localFileFor(url: string): Promise<string | null> {
  const clean = url.split('?')[0] ?? '';
  const name = path.basename(clean);
  const candidates = clean.includes('/assets/videos/')
    ? [path.join(ASSETS, 'videos', name)]
    : clean.includes('/uploads/')
      ? [path.join(UPLOADS, name)]
      : [];
  for (const c of candidates) {
    try { await fs.access(c); return c; } catch { /* next */ }
  }
  return null;
}

async function main() {
  const gifts = await prisma.gift.findMany({
    where: { format: 'VIDEO', videoFallbackUrl: null, animationUrl: { not: null } },
    select: { id: true, name: true, animationUrl: true },
  });
  console.log(`${gifts.length} video gift(s) without a fallback${APPLY ? '' : ' (dry run)'}`);
  let done = 0;
  for (const g of gifts) {
    const file = await localFileFor(g.animationUrl!);
    if (!file) { console.log(`  skip ${g.id} ${g.name}: file not on this server (${g.animationUrl})`); continue; }
    if (!APPLY) { console.log(`  would build ${path.basename(file)}.baseline.mp4 for ${g.id} ${g.name}`); continue; }
    try {
      const out = await createGiftFallback(file);
      const base = g.animationUrl!.split('?')[0]!.replace(/[^/]+$/, '');
      await prisma.gift.update({ where: { id: g.id }, data: { videoFallbackUrl: base + path.basename(out) } });
      done++;
      console.log(`  ✓ ${g.id} ${g.name} → ${path.basename(out)}`);
    } catch (e) {
      console.error(`  ✗ ${g.id} ${g.name}:`, (e as Error).message);
    }
  }
  if (done) await bumpCatalogVersion();
  console.log(APPLY ? `built ${done}` : 'dry run — nothing written; pass --apply');
}

main().finally(() => prisma.$disconnect());
