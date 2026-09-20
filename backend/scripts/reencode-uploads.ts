/**
 * One-off: shrink the media already in uploads/ and repoint the rows at it.
 *
 *   npx ts-node scripts/reencode-uploads.ts            # dry run — reports only
 *   npx ts-node scripts/reencode-uploads.ts --apply    # do it
 *
 * Originals are moved to uploads/originals/ first, never deleted. Rules are
 * the same as at upload time (utils/mediaOptimize): GIFs keep their size and
 * get a palette; clips go to ≤720p H.264 unless they carry alpha; gift icons
 * become 256px WebP; other stills become WebP at their own size. A row is
 * only rewritten when the file on disk actually changed.
 */
import fs from 'fs/promises';
import path from 'path';
import prisma from '../src/utils/prisma';
import { optimizeGif, optimizeImage, shrinkVideo } from '../src/utils/mediaOptimize';
import { probeGiftVideo } from '../src/gifts/videoValidate';

const APPLY = process.argv.includes('--apply');
const UPLOADS = path.join(process.cwd(), 'uploads');
const ORIGINALS = path.join(UPLOADS, 'originals');
const MIN_GIF = 1.5 * 1024 * 1024;
const MIN_VIDEO = 5 * 1024 * 1024;
const MIN_STILL = 150 * 1024;

type Target = { table: string; column: string; idColumn: string; iconLike?: boolean };
const TARGETS: Target[] = [
  { table: 'gifts', column: 'iconUrl', idColumn: 'id', iconLike: true },
  { table: 'gifts', column: 'animationUrl', idColumn: 'id' },
  { table: 'items', column: 'assetUrl', idColumn: 'id' },
  { table: 'items', column: 'previewUrl', idColumn: 'id' },
  { table: 'users', column: 'avatarUrl', idColumn: 'id', iconLike: true },
  { table: 'users', column: 'avatarFrameUrl', idColumn: 'id' },
  { table: 'rooms', column: 'backgroundImageUrl', idColumn: 'id' },
  { table: 'rooms', column: 'coverImageUrl', idColumn: 'id' },
];

const fmt = (n: number) => (n / 1024 / 1024).toFixed(2) + ' MB';

async function main() {
  await fs.mkdir(ORIGINALS, { recursive: true });
  let totalBefore = 0;
  let totalAfter = 0;
  const done = new Map<string, string>(); // filename → new filename

  for (const t of TARGETS) {
    const rows: { id: any; url: string | null }[] = await prisma.$queryRawUnsafe(
      `select "${t.idColumn}" as id, "${t.column}" as url from "${t.table}" where "${t.column}" like '%/uploads/%'`,
    );
    for (const row of rows) {
      const url = row.url!;
      const name = url.split('/uploads/')[1]?.split('?')[0];
      if (!name || name.includes('/')) continue;
      const file = path.join(UPLOADS, name);
      let newName = done.get(name);
      if (newName === undefined) {
        newName = name;
        let size: number;
        try {
          size = (await fs.stat(file)).size;
        } catch {
          continue;
        }
        const ext = path.extname(name).toLowerCase();
        totalBefore += size;
        let after = size;
        const work = async () => {
          if (ext === '.gif' && size > MIN_GIF) {
            // A GIF used as an ICON (gift tile, avatar) is drawn at ≤ 80px; a
            // 4 MB 600px clip there is pure waste — shrink it to 256 / 512.
            const r = await optimizeGif(file, t.iconLike ? { maxSide: t.table === 'users' ? 512 : 256, fps: 15 } : {});
            after = r.after;
          } else if (['.mp4', '.mov', '.m4v', '.webm'].includes(ext) && size > MIN_VIDEO) {
            const probe = await probeGiftVideo(file).catch(() => null);
            if (probe && !probe.hasAlpha) {
              const r = await shrinkVideo(file);
              after = r.after;
            }
          } else if (['.png', '.jpg', '.jpeg'].includes(ext) && (size > MIN_STILL || (t.iconLike && size > 40 * 1024))) {
            const r = await optimizeImage(file, t.iconLike ? { maxSide: t.table === 'users' ? 512 : 256 } : {});
            after = r.after;
            newName = path.basename(r.path);
          }
        };
        const candidate = (ext === '.gif' && size > MIN_GIF)
          || (['.mp4', '.mov', '.m4v', '.webm'].includes(ext) && size > MIN_VIDEO)
          || (['.png', '.jpg', '.jpeg'].includes(ext) && (size > MIN_STILL || (t.iconLike && size > 40 * 1024)));
        if (candidate && APPLY) {
          await fs.copyFile(file, path.join(ORIGINALS, name));
          await work();
          console.log(`${t.table}.${t.column}  ${name} → ${newName}  ${fmt(size)} → ${fmt(after)}`);
        } else if (candidate) {
          console.log(`[dry] ${t.table}.${t.column}  ${name}  ${fmt(size)}`);
        }
        totalAfter += after;
        done.set(name, newName);
      }
      if (APPLY && newName !== name) {
        const newUrl = url.replace(`/uploads/${name}`, `/uploads/${newName}`);
        await prisma.$executeRawUnsafe(
          `update "${t.table}" set "${t.column}" = $1 where "${t.idColumn}" = $2`,
          newUrl,
          row.id,
        );
      }
    }
  }
  console.log(`\n${APPLY ? 'applied' : 'dry run'}: ${fmt(totalBefore)} → ${fmt(totalAfter)} across ${done.size} files`);
  await prisma.$disconnect();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
