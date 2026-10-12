import crypto from 'crypto';

/**
 * Pure maths for عجلة السيارات (CAR WHEEL), one shared eight-segment table.
 * Clockwise from the top pointer. Returns include the stake: each segment's
 * multiplier × weight is 6600, so every bet returns 6600/8942 (73.81%).
 * This stays below the platform's 75% prize-pool share.
 */
export const SEGMENTS = [
  { key: 'aurelia', name: 'Aurelia', multiplier: 8, weight: 825 },
  { key: 'bavaro', name: 'Bavaro', multiplier: 10, weight: 660 },
  { key: 'stellaro', name: 'Stellaro', multiplier: 66, weight: 100 },
  { key: 'ferrarion', name: 'Ferrarion', multiplier: 50, weight: 132 },
  { key: 'lambrex', name: 'Lambrex', multiplier: 88, weight: 75 },
  { key: 'voltara', name: 'Voltara', multiplier: 3, weight: 2200 },
  { key: 'porsenna', name: 'Porsenna', multiplier: 2, weight: 3300 },
  { key: 'bentara', name: 'Bentara', multiplier: 4, weight: 1650 },
] as const;
export type SegmentKey = typeof SEGMENTS[number]['key'];
export const WHEEL_ORDER = SEGMENTS.map(s => s.key);
export const MULTIPLIERS = Object.fromEntries(SEGMENTS.map(s => [s.key, s.multiplier])) as Record<SegmentKey, number>;
export const TOTAL_WEIGHT = 8942;
export const CHIPS = [100, 1000, 10000, 100000];
export const MAX_PER_KEY = 1_000_000;

export function assertBalancedTable() {
  if (SEGMENTS.some(s => s.multiplier * s.weight !== 6600)
      || SEGMENTS.reduce((sum, s) => sum + s.weight, 0) !== TOTAL_WEIGHT) {
    throw new Error('CAR WHEEL table must return 6600/8942 on every segment');
  }
}
assertBalancedTable();

/** One canonical key per segment; unknown keys never become a bet. */
export function parseBetKey(key: unknown) {
  return SEGMENTS.find(s => s.key === key) ?? null;
}

export function payoutFor(stakes: Record<string, number>, result: string): number {
  const segment = parseBetKey(result);
  return segment ? Math.max(0, stakes[result] ?? 0) * segment.multiplier : 0;
}

/** Reserve only the most the player can win on a single result. */
export function maxPayout(stakes: Record<string, number>): number {
  return Math.max(...WHEEL_ORDER.map(key => payoutFor(stakes, key)));
}

/** A committed seed fixes the weighted draw before any stakes are settled. */
export function rollFromSeed(seed: string, roundId: number): SegmentKey {
  const digest = crypto.createHash('sha256').update(`${seed}:${roundId}`).digest('hex');
  let roll = Number(BigInt(`0x${digest.slice(0, 13)}`) % 8942n);
  for (const segment of SEGMENTS) {
    if (roll < segment.weight) return segment.key;
    roll -= segment.weight;
  }
  throw new Error('Invalid CAR WHEEL weights');
}

export const returnOf = (key: SegmentKey) => {
  const segment = parseBetKey(key)!;
  return segment.multiplier * segment.weight / TOTAL_WEIGHT;
};
