import prisma from '../utils/prisma';

/**
 * SPEC52 #7 — VIP name colours (2026-10-20).
 *
 * The owner sets a colour (and later, optionally, a gradient) per VIP tier in
 * the dashboard; the SERVER decides what colour a name is drawn in and ships
 * it with every user it sends (`nameColor`, `nameGradient`). The phone never
 * picks a colour from its own idea of the VIP table.
 *
 * Sync accessors read an in-memory copy refreshed every minute and right
 * after an admin edit, so socket payload builders (which are synchronous) can
 * use it without a query per user.
 */
export const DEFAULT_NAME_COLORS: Record<number, string> = {
  1: '#FFFFFF',
  2: '#4CAF50',
  3: '#2196F3',
  4: '#9C27B0',
  5: '#FFD700',
};

const HEX = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;
export const isHexColor = (v: string) => HEX.test(v.trim());

interface TierStyle {
  nameColor: string | null;
  nameGradient: string[] | null;
}

let styles = new Map<number, TierStyle>();
let loadedAt = 0;
let loading: Promise<void> | null = null;
const TTL_MS = 60_000;

async function load(): Promise<void> {
  try {
    const rows = await (prisma as any).vipLevelConfig.findMany({
      select: { level: true, nameColor: true, nameGradient: true },
    });
    const next = new Map<number, TierStyle>();
    for (const r of rows) {
      const g = Array.isArray(r.nameGradient) ? (r.nameGradient as unknown[]).map(String).filter(isHexColor) : null;
      next.set(r.level, { nameColor: r.nameColor && isHexColor(r.nameColor) ? r.nameColor : null, nameGradient: g && g.length >= 2 ? g : null });
    }
    styles = next;
    loadedAt = Date.now();
  } catch (e) {
    console.warn('[vipStyle] load failed:', (e as Error).message);
  } finally {
    loading = null;
  }
}

function refreshIfStale() {
  if (Date.now() - loadedAt > TTL_MS && !loading) loading = load();
}

export async function warmVipStyles(): Promise<void> {
  if (!loading) loading = load();
  await loading;
}

export function invalidateVipStyleCache() {
  loadedAt = 0;
  loading = load();
}

/** Tier style; a configured row wins, otherwise the built-in defaults for 1–5. */
export function vipStyleSync(vipLevel: number | null | undefined): TierStyle {
  refreshIfStale();
  const lvl = Number(vipLevel ?? 0);
  if (!lvl || lvl < 1) return { nameColor: null, nameGradient: null };
  const row = styles.get(lvl);
  if (row && (row.nameColor || row.nameGradient)) return row;
  return { nameColor: DEFAULT_NAME_COLORS[lvl] ?? null, nameGradient: null };
}

export function nameColorSync(vipLevel: number | null | undefined, vipExpiresAt?: Date | string | null): string | null {
  if (vipExpiresAt && new Date(vipExpiresAt).getTime() <= Date.now()) return null;
  return vipStyleSync(vipLevel).nameColor;
}

/**
 * Adds `nameColor` / `nameGradient` to a user-shaped object that carries
 * `vipLevel` (and optionally `vipExpiresAt`). Returns the same object.
 * Leaves objects without a vipLevel untouched.
 */
export function withNameStyle<T extends Record<string, any>>(u: T | null | undefined): T {
  if (!u || typeof u !== 'object') return u as unknown as T;
  if (!('vipLevel' in u)) return u;
  const expired = u.vipExpiresAt && new Date(u.vipExpiresAt).getTime() <= Date.now();
  const s = expired ? { nameColor: null, nameGradient: null } : vipStyleSync(u.vipLevel);
  (u as any).nameColor = s.nameColor;
  (u as any).nameGradient = s.nameGradient;
  return u;
}

export function withNameStyles<T extends Record<string, any>>(list: T[] | null | undefined): T[] {
  return (list ?? []).map((u) => withNameStyle(u));
}
