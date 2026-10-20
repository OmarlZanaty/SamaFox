import fs from 'fs';
import path from 'path';
import prisma from '../utils/prisma';

/**
 * A16 — "صورة شخصية متحركة GIF".
 *
 * Client spec (17/08 23:00): an animated profile photo is a paid perk, and the
 * dashboard decides which VIP tier unlocks it — "مثلاً VIP10 وما فوق ياخذوا
 * خاصية الصوره المتحركه".
 *
 * The permission is stored per tier (`VipLevelConfig.allowAnimatedAvatar`) and
 * read as "the lowest tier that has it switched on". That is what makes the
 * client's "وما فوق" true without the admin having to tick every tier above
 * it, and it means an admin who ticks VIP10 alone still grants VIP11+ the perk.
 *
 * With no tier ticked anywhere the perk is simply off for everyone, which is
 * the pre-existing behaviour — the feature cannot switch itself on.
 */

/** Extensions/mime types that carry animation. WEBP may or may not, so a
 *  static .webp is treated as animated too: refusing it is a harmless false
 *  positive next to letting an un-entitled account upload a moving avatar. */
const ANIMATED_EXTENSIONS = ['.gif', '.webp', '.apng'];
const ANIMATED_MIME_TYPES = ['image/gif', 'image/webp', 'image/apng'];

export function isAnimatedImage(opts: { filename?: string | null; mimetype?: string | null }): boolean {
  const mime = (opts.mimetype ?? '').toLowerCase();
  if (ANIMATED_MIME_TYPES.includes(mime)) return true;
  const name = (opts.filename ?? '').toLowerCase().split('?')[0] ?? '';
  return ANIMATED_EXTENSIONS.some((ext) => name.endsWith(ext));
}

/** The lowest VIP level with the perk switched on, or null when nobody has it. */
export async function animatedAvatarMinVipLevel(): Promise<number | null> {
  const row = await (prisma as any).vipLevelConfig.findFirst({
    where: { allowAnimatedAvatar: true },
    orderBy: { level: 'asc' },
    select: { level: true },
  });
  return row?.level ?? null;
}

export async function canUseAnimatedAvatar(userId: number): Promise<{ allowed: boolean; minLevel: number | null }> {
  const minLevel = await animatedAvatarMinVipLevel();
  if (minLevel == null) return { allowed: false, minLevel: null };
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { vipLevel: true, vipExpiresAt: true },
  });
  if (!user) return { allowed: false, minLevel };
  // An expired bought tier grants nothing.
  const vipActive = !user.vipExpiresAt || user.vipExpiresAt.getTime() > Date.now();
  return { allowed: vipActive && user.vipLevel >= minLevel, minLevel };
}

/**
 * SPEC52 #6 (2026-10-20) — the gate was being sidestepped: a GIF sent with a
 * `.jpg` name / `image/jpeg` type, or an animated URL written straight into the
 * profile through PUT /users/me. These two helpers close both holes: the file's
 * own bytes decide whether it moves, and every avatar assignment is checked.
 */
export function isAnimatedFile(filePath: string): boolean {
  let fd: number | null = null;
  try {
    fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(256 * 1024);
    const n = fs.readSync(fd, buf, 0, buf.length, 0);
    const b = buf.subarray(0, n);
    if (b.length >= 6 && /^GIF8[79]a/.test(b.subarray(0, 6).toString('latin1'))) return true;
    // APNG: a PNG with an acTL chunk before the first IDAT.
    if (b.length > 8 && b[0] === 0x89 && b.subarray(1, 4).toString('latin1') === 'PNG') {
      const idat = b.indexOf('IDAT', 8, 'latin1');
      const actl = b.indexOf('acTL', 8, 'latin1');
      return actl !== -1 && (idat === -1 || actl < idat);
    }
    // Animated WebP: RIFF....WEBP with a VP8X ANIM flag or an ANIM chunk.
    if (b.length > 16 && b.subarray(0, 4).toString('latin1') === 'RIFF' && b.subarray(8, 12).toString('latin1') === 'WEBP') {
      if (b.subarray(12, 16).toString('latin1') === 'VP8X' && b.length > 20 && ((b[20] ?? 0) & 0x02) !== 0) return true;
      return b.indexOf('ANIM', 12, 'latin1') !== -1;
    }
    return false;
  } catch {
    return false;
  } finally {
    if (fd != null) try { fs.closeSync(fd); } catch { /* ignore */ }
  }
}

/** True when an uploaded file or URL is (or may be) animated. */
export function isAnimatedUpload(opts: { filename?: string | null; mimetype?: string | null; filePath?: string | null }): boolean {
  if (isAnimatedImage(opts)) return true;
  return !!opts.filePath && isAnimatedFile(opts.filePath);
}

/** Resolve one of OUR /uploads/ URLs to its file on disk (null for foreign URLs). */
export function localUploadPath(url: string): string | null {
  const m = /\/uploads\/(?:v2\/)?([A-Za-z0-9._-]+)(?:\?|$)/.exec(url);
  if (!m) return null;
  const p = path.join(process.cwd(), 'uploads', m[1] ?? '');
  return fs.existsSync(p) ? p : null;
}

/** Is assigning this avatar URL allowed for the user? (null = allowed) */
export async function animatedAvatarUrlDenial(userId: number, url: string): Promise<string | null> {
  const local = localUploadPath(url);
  const animated = isAnimatedImage({ filename: url }) || (local ? isAnimatedFile(local) : false);
  if (!animated) return null;
  const { allowed, minLevel } = await canUseAnimatedAvatar(userId);
  if (allowed) return null;
  return minLevel == null ? 'الصورة المتحركة غير متاحة حالياً' : `الصورة المتحركة متاحة لأعضاء VIP ${minLevel} فما فوق`;
}
