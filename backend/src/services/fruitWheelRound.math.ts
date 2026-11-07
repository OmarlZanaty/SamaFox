import crypto from 'crypto';

// Natural weights; occupied rounds only draw cards the pool can fund.
export const SEGMENTS = [
  { key: 'watermelon', multiplierX10: 20, weight: 4500 },
  { key: 'plum', multiplierX10: 20, weight: 4500 },
  { key: 'sevens', multiplierX10: 80, weight: 1000 },
] as const;
export type Outcome = typeof SEGMENTS[number]['key'];
export type Card = Outcome;
export type BonusKind = 'double' | 'triple' | null;

/** Absent/null intervals mean a fixed 13 occupied rounds; explicit ranges remain supported. */
export function bonusInterval(settings: { bonusEveryRounds?: number | null; bonusMaxRounds?: number | null }) {
  const bonusEveryRounds = settings.bonusEveryRounds ?? 13;
  return {
    bonusEveryRounds,
    bonusMaxRounds: Math.max(bonusEveryRounds, settings.bonusMaxRounds ?? bonusEveryRounds),
  };
}

/** Doubles always pair 77 with one fruit. */
export function winningCards(seed: string, roundNumber: number, primary: string, bonus: BonusKind): string[] {
  if (!bonus) return [primary];
  if (bonus === 'triple') return [primary, ...SEGMENTS.filter(s => s.key !== primary).map(s => s.key)];
  const digest = crypto.createHash('sha256').update(`${seed}:${roundNumber}:bonus`).digest('hex');
  return ['sevens', ['watermelon', 'plum'][Number(BigInt(`0x${digest}`) % 2n)]!];
}

export function payoutForResults(stakes: Record<string, number>, results: readonly string[]): number {
  return results.reduce((total, card) => total + payoutFor(stakes, card), 0);
}
// Installed apps still paint a crown at slot 9; never present that slot.
export const WHEEL_ORDER: Outcome[] = [
  'watermelon', 'plum', 'watermelon', 'plum', 'sevens',
  'watermelon', 'plum', 'watermelon', 'plum', 'sevens',
];
export const MULTIPLIERS = { watermelon: 2, sevens: 8, plum: 2 };
export const TOTAL_WEIGHT = 10000;
export const CHIPS = [100, 1000, 10000, 100000];
export const MIN_BET = 100;
export function assertValidTable() {
  if (SEGMENTS.reduce((n, s) => n + s.weight, 0) !== TOTAL_WEIGHT ||
      SEGMENTS.some(s => s.multiplierX10 <= 0)) {
    throw new Error('Invalid FRUIT WHEEL outcome table');
  }
}
assertValidTable();
export function parseBetKey(key: unknown) {
  return SEGMENTS.find(s => s.key === key) ?? null;
}
export function payoutFor(stakes: Record<string, number>, result: string): number {
  const card = parseBetKey(result);
  return card ? Math.floor(Math.max(0, stakes[result] ?? 0) * card.multiplierX10 / 10) : 0;
}
export function maxPayout(stakes: Record<string, number>): number {
  return Math.max(...SEGMENTS.map(s => payoutFor(stakes, s.key)));
}
export function rollFromSeed(seed: string, roundId: number): Outcome {
  return rollAmongFromSeed(seed, roundId, SEGMENTS.map(s => s.key));
}
export function rollAmongFromSeed(seed: string, roundId: number, allowedKeys: readonly string[]): Outcome {
  const allowed = SEGMENTS.filter(s => allowedKeys.includes(s.key));
  const total = allowed.reduce((n, s) => n + s.weight, 0);
  if (!total) throw new Error('No FRUIT WHEEL outcomes allowed');
  const digest = crypto.createHash('sha256').update(`${seed}:${roundId}`).digest('hex');
  let roll = Number(BigInt(`0x${digest.slice(0, 13)}`) % BigInt(total));
  for (const s of allowed) {
    if (s.weight <= 0) continue;
    if (roll < s.weight) return s.key;
    roll -= s.weight;
  }
  throw new Error('Invalid FRUIT WHEEL weights');
}
/** Presentation only; the weighted outcome has already been committed. */
export function presentationFor(outcome: Outcome) {
  if (!WHEEL_ORDER.includes(outcome)) throw new Error('Invalid FRUIT WHEEL outcome');
  const slots = WHEEL_ORDER.flatMap((key, i) => key === outcome && i !== 9 ? [i] : []);
  return { segment: slots[crypto.randomInt(slots.length)]!, offset: crypto.randomInt(150, 851) / 1000 };
}
export const returnOf = (key: Card) => {
  const s = parseBetKey(key)!;
  return s.multiplierX10 * s.weight / (10 * TOTAL_WEIGHT);
};
