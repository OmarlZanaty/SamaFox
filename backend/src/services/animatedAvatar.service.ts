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
