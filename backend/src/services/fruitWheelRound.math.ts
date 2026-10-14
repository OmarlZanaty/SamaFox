import crypto from 'crypto';

export const SEGMENTS = [
  { key: 'watermelon', multiplier: 2, weight: 3500 },
  { key: 'plum', multiplier: 2, weight: 3500 },
  { key: 'sevens', multiplier: 8, weight: 875 },
  { key: 'crown', multiplier: 0, weight: 2125 },
] as const;
export type Outcome = typeof SEGMENTS[number]['key'];
export type Card = Exclude<Outcome, 'crown'>;
export const WHEEL_ORDER: Outcome[] = [
  'watermelon', 'plum', 'watermelon', 'plum', 'sevens',
  'watermelon', 'plum', 'watermelon', 'plum', 'crown',
];
export const MULTIPLIERS = { watermelon: 2, sevens: 8, plum: 2 };
export const TOTAL_WEIGHT = 10000;
export const CHIPS = [100, 1000, 10000, 100000];
export const MIN_BET = 100;
export const MAX_PER_KEY = 1_000_000;
export function assertBalancedTable() {
  if (SEGMENTS.reduce((n, s) => n + s.weight, 0) !== TOTAL_WEIGHT ||
      SEGMENTS.some(s => s.key !== 'crown' && s.multiplier * s.weight !== 7000)) {
    throw new Error('FRUIT WHEEL must return exactly 70% on every card');
  }
}
assertBalancedTable();
export function parseBetKey(key: unknown) {
  return SEGMENTS.find(s => s.key !== 'crown' && s.key === key) ?? null;
}
export function payoutFor(stakes: Record<string, number>, result: string): number {
  const card = parseBetKey(result);
  return card ? Math.max(0, stakes[result] ?? 0) * card.multiplier : 0;
}
export function maxPayout(stakes: Record<string, number>): number {
  return Math.max(...SEGMENTS.map(s => payoutFor(stakes, s.key)));
}
export function rollFromSeed(seed: string, roundId: number): Outcome {
  const digest = crypto.createHash('sha256').update(`${seed}:${roundId}`).digest('hex');
  let roll = Number(BigInt(`0x${digest.slice(0, 13)}`) % BigInt(TOTAL_WEIGHT));
  for (const s of SEGMENTS) {
    if (roll < s.weight) return s.key;
    roll -= s.weight;
  }
  throw new Error('Invalid FRUIT WHEEL weights');
}
/** Presentation only; the weighted outcome has already been committed. */
export function presentationFor(outcome: Outcome) {
  const slots = WHEEL_ORDER.flatMap((key, i) => key === outcome ? [i] : []);
  return { segment: slots[crypto.randomInt(slots.length)]!, offset: crypto.randomInt(150, 851) / 1000 };
}
export const returnOf = (key: Card) => {
  const s = parseBetKey(key)!;
  return s.multiplier * s.weight / TOTAL_WEIGHT;
};
