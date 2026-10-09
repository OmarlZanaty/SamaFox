import fs from 'fs/promises';
import path from 'path';

// Uploads from before the upload-time optimiser (20–25 Sep) are still on disk
// at camera size — a 3456×3456 avatar, a 3840×2160 room cover — and every
// phone that shows one downloads and decodes all of it. This brings them to
// the sizes new uploads get (avatars 512, everything else 1600) IN PLACE:
// same file name, same format, so every URL in the database keeps working.

export const AVATAR_MAX_SIDE = 512;
export const IMAGE_MAX_SIDE = 1600;

const STILL_IMAGE = new Set(['.jpg', '.jpeg', '.png', '.webp']);

export type ShrinkPlan = { file: string; width: number; height: number; maxSide: number };

/** The longest side [file] should have, or null when it is already small enough. */
export function targetSide(
  meta: { width?: number; height?: number; pages?: number },
  isAvatar: boolean,
): number | null {
  const { width, height } = meta;
  if (!width || !height) return null;
  if ((meta.pages ?? 1) > 1) return null; // animated WebP: left to the GIF policy
  const cap = isAvatar ? AVATAR_MAX_SIDE : IMAGE_MAX_SIDE;
  return Math.max(width, height) > cap ? cap : null;
}

/** "https://host/uploads/upload-1.jpg?x" → "upload-1.jpg"; null for anything else. */
export function uploadName(url: string | null | undefined): string | null {
  if (!url) return null;
  const m = /\/uploads\/([^/?#]+)/.exec(url);
  return m?.[1] ? decodeURIComponent(m[1]) : null;
}

export async function planShrink(dir: string, avatarNames: Set<string>): Promise<ShrinkPlan[]> {
  const sharp = (await import('sharp')).default;
  const plans: ShrinkPlan[] = [];
  for (const name of await fs.readdir(dir)) {
    if (!STILL_IMAGE.has(path.extname(name).toLowerCase())) continue;
    const file = path.join(dir, name);
    try {
      const meta = await sharp(file).metadata();
      // EXIF orientation 5–8 swaps the sides; the cap is on the longest one,
      // so it does not matter which is which.
      const maxSide = targetSide(meta, avatarNames.has(name));
      if (maxSide) plans.push({ file, width: meta.width!, height: meta.height!, maxSide });
    } catch {
      /* not an image sharp can read: leave it alone */
    }
  }
  return plans;
}

/** Resizes one file in place, keeping its format. Returns [before, after] bytes. */
export async function shrinkInPlace(plan: ShrinkPlan): Promise<[number, number]> {
  const sharp = (await import('sharp')).default;
  const before = (await fs.stat(plan.file)).size;
  const ext = path.extname(plan.file).toLowerCase();
  const tmp = `${plan.file}.shrink.tmp`;
  let img = sharp(plan.file, { animated: false })
    .rotate()
    .resize({ width: plan.maxSide, height: plan.maxSide, fit: 'inside', withoutEnlargement: true });
  img =
    ext === '.png'
      ? img.png({ compressionLevel: 9 })
      : ext === '.webp'
        ? img.webp({ quality: 82 })
        : img.jpeg({ quality: 85, mozjpeg: true });
  await img.toFile(tmp);
  await fs.rename(tmp, plan.file);
  return [before, (await fs.stat(plan.file)).size];
}
