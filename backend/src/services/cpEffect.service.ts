import prisma from '../utils/prisma';
import { computeCpLevel, readCpSettings } from './cpUnlock.service';

const db = prisma as any;

/**
 * تأثير CP Level (2026-09-26, item 11).
 *
 * The server says WHICH seated users are CP partners, at what level, and which
 * effect (if any) their level earns. The app draws it only while the two sit
 * on NEIGHBOURING mics — the seat grid is the app's layout, so adjacency is
 * checked there — and drops it the moment either leaves the mic or the room,
 * because every such change produces a fresh seat snapshot without the link.
 *
 * Effects are configured in «CP Level Management»: required level, on/off,
 * effect id, duration (0 = while the condition holds), animation speed and
 * priority (the highest-priority eligible effect wins).
 */

export interface CpEffectRow {
  effectKey: string;
  name: string | null;
  requiredLevel: number;
  enabled: boolean;
  durationSec: number;
  animationSpeed: number;
  priority: number;
}

const TTL_MS = 15_000;
let effectsCache: { at: number; rows: CpEffectRow[] } | null = null;

export function invalidateCpEffectsCache() {
  effectsCache = null;
  linksCache.clear();
}

export async function getEnabledCpEffects(): Promise<CpEffectRow[]> {
  if (effectsCache && Date.now() - effectsCache.at < TTL_MS) return effectsCache.rows;
  let rows: CpEffectRow[] = [];
  try {
    rows = (await db.cpEffect.findMany({ where: { enabled: true }, orderBy: { priority: 'desc' } })).map((r: any) => ({
      effectKey: r.effectKey,
      name: r.name ?? null,
      requiredLevel: Number(r.requiredLevel),
      enabled: Boolean(r.enabled),
      durationSec: Number(r.durationSec),
      animationSpeed: Number(r.animationSpeed),
      priority: Number(r.priority),
    }));
  } catch (e) {
    console.warn('[cp-effect] read failed:', (e as Error).message);
  }
  effectsCache = { at: Date.now(), rows };
  return rows;
}

export interface CpSeatLink {
  userA: number;
  userB: number;
  seatA: number;
  seatB: number;
  level: number;
  effect: { key: string; durationSec: number; animationSpeed: number; priority: number } | null;
}

// The same seats produce the same links; a snapshot goes out on every seat
// change, so the pair lookup is cached briefly per seating.
const linksCache = new Map<string, { at: number; links: CpSeatLink[] }>();

/** CP partners among the users on mics right now, with the effect each pair earns. */
export async function cpSeatLinks(seats: Map<number, number>): Promise<CpSeatLink[]> {
  const bySeat = [...seats.entries()].filter(([, uid]) => uid);
  if (bySeat.length < 2) return [];
  const effects = await getEnabledCpEffects();
  const sig = bySeat.map(([s, u]) => `${s}:${u}`).sort().join(',');
  const hit = linksCache.get(sig);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.links;

  const ids = [...new Set(bySeat.map(([, u]) => u))];
  const seatOf = new Map<number, number>();
  for (const [s, u] of bySeat) if (!seatOf.has(u)) seatOf.set(u, s);

  let links: CpSeatLink[] = [];
  try {
    const [pairs, cfg] = await Promise.all([
      db.cpPair.findMany({
        where: { userAId: { in: ids }, userBId: { in: ids } },
        select: { userAId: true, userBId: true, cpValue: true, createdAt: true, levelOverride: true },
      }),
      readCpSettings(db),
    ]);
    links = pairs.map((p: any) => {
      const lvl = computeCpLevel({ cpValue: p.cpValue, createdAt: p.createdAt, levelOverride: p.levelOverride }, cfg);
      // The level table can name its own effect; otherwise the highest-priority
      // enabled effect whose required level is met.
      const named = lvl.effectKey ? effects.find((e) => e.effectKey === lvl.effectKey && lvl.level >= e.requiredLevel) : undefined;
      const fx = named ?? effects.find((e) => lvl.level >= e.requiredLevel) ?? null;
      return {
        userA: p.userAId,
        userB: p.userBId,
        seatA: seatOf.get(p.userAId)!,
        seatB: seatOf.get(p.userBId)!,
        level: lvl.level,
        effect: fx ? { key: fx.effectKey, durationSec: fx.durationSec, animationSpeed: fx.animationSpeed, priority: fx.priority } : null,
      };
    });
  } catch (e) {
    console.warn('[cp-effect] links failed:', (e as Error).message);
  }
  linksCache.set(sig, { at: Date.now(), links });
  if (linksCache.size > 2000) linksCache.clear();
  return links;
}
