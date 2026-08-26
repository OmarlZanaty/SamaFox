/**
 * One-shot backfill: give every VIDEO product a still poster.
 *
 * A25/B5 — the store grid no longer builds a `VideoPlayerController` per tile
 * (that is what made فتح المتجر so heavy) and draws `preview_url` instead.
 * Products uploaded from now on get their poster at upload time; this fills in
 * everything that already existed, which would otherwise keep rendering as a
 * blank grey placeholder.
 *
 * Safe to run repeatedly: an item that already has a poster is skipped, and a
 * clip ffmpeg cannot read is left alone (its tile keeps the placeholder).
 *
 *   npm run backfill:posters
 *
 * Lives beside the other one-off maintenance scripts under prisma/, which the
 * build excludes.
 */
import path from 'path';
import { existsSync } from 'fs';

import prisma from '../src/utils/prisma';
import { extractPosterFrame } from '../src/gifts/videoValidate';

const VIDEO_EXTENSIONS = ['.mp4', '.webm', '.mov', '.m4v', '.mkv'];

const isVideoAsset = (url: string): boolean => {
  const clean = (url || '').toLowerCase().split('?')[0] ?? '';
  return VIDEO_EXTENSIONS.some((ext) => clean.endsWith(ext));
};

/** Local file for an asset URL, or null when it is not one of ours. */
function localPathFor(assetUrl: string): string | null {
  const marker = '/uploads/';
  const at = assetUrl.indexOf(marker);
  if (at < 0) return null;
  const filename = path.basename(assetUrl.slice(at + marker.length));
  if (!filename) return null;
  const full = path.join(process.cwd(), 'uploads', filename);
  return existsSync(full) ? full : null;
}

async function main(): Promise<void> {
  const items = await prisma.item.findMany({
    where: { previewUrl: null },
    select: { id: true, name: true, assetUrl: true },
  });

  const videos = items.filter((i) => isVideoAsset(i.assetUrl));
  console.log(`[backfill-posters] ${videos.length} video product(s) without a poster`);

  let made = 0;
  let skipped = 0;

  for (const item of videos) {
    const filePath = localPathFor(item.assetUrl);
    if (!filePath) {
      console.warn(`  – ${item.name}: asset file not found locally, skipped`);
      skipped++;
      continue;
    }

    const posterPath = await extractPosterFrame(filePath);
    if (!posterPath) {
      console.warn(`  – ${item.name}: ffmpeg produced no frame, skipped`);
      skipped++;
      continue;
    }

    // Keep the same origin the asset was stored with, so the poster is reachable
    // wherever the clip is.
    const base = item.assetUrl.slice(0, item.assetUrl.indexOf('/uploads/'));
    const previewUrl = `${base}/uploads/${path.basename(posterPath)}`;
    await prisma.item.update({ where: { id: item.id }, data: { previewUrl } });
    console.log(`  ✓ ${item.name} → ${previewUrl}`);
    made++;
  }

  console.log(`[backfill-posters] done: ${made} created, ${skipped} skipped`);
}

main()
  .catch((e) => {
    console.error('[backfill-posters] failed:', e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
