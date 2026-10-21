import crypto from 'crypto';

// 2026-10-21: back to ×2 / ×2 / ×8 WITH the crown (no-win slice). The client
// objected to ×1.6 / ×5.6 («ليه قللت المضاعف»); ×2/×8 with no losing slice would
// return 100% on the 77, so the crown (21.25%) is what keeps every card at 70%.
export const SEGMENTS = [
  { key: 'watermelon', multiplierX10: 20, weight: 3500 },
  { key: 'plum', multiplierX10: 20, weight: 3500 },
  { key: 'sevens', multiplierX10: 80, weight: 875 },
  { key: 'crown', multiplierX10: 0, weight: 2125 },
] as const;
export type Outcome = typeof SEGMENTS[number]['key'];
export type Card = Exclude<Outcome, 'crown'>;
export type BonusKind = 'double' | 'triple' | null;

/** Primary stays first, including when a triple must fall back to a double. */
export function winningCards(seed: string, roundNumber: number, primary: string, bonus: BonusKind): string[] {
  if (!bonus) return [primary];
  const others = SEGMENTS.filter(s => s.key !== 'crown' && s.key !== primary).map(s => s.key);
  if (bonus === 'triple') return [primary, ...others];
  const digest = crypto.createHash('sha256').update(`${seed}:${roundNumber}:bonus`).digest('hex');
  return [primary, others[Number(BigInt(`0x${digest}`) % BigInt(others.length))]!];
}

/** A bonus round is never a crown: re-draw the primary among the cards by their weights. */
export function bonusPrimaryFromSeed(seed: string, roundNumber: number): Card {
  const cards = SEGMENTS.filter(s => s.key !== 'crown');
  const total = cards.reduce((n, s) => n + s.weight, 0);
  const digest = crypto.createHash('sha256').update(`${seed}:${roundNumber}:bonus-primary`).digest('hex');
  let roll = Number(BigInt(`0x${digest.slice(0, 13)}`) % BigInt(total));
  for (const c of cards) {
    if (roll < c.weight) return c.key as Card;
    roll -= c.weight;
  }
  return cards[0]!.key as Card;
}

export function payoutForResults(stakes: Record<string, number>, results: readonly string[]): number {
  return results.reduce((total, card) => total + payoutFor(stakes, card), 0);
}
// Installed apps use these indices; the crown is slot 9.
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
      SEGMENTS.some(s => s.key !== 'crown' && s.multiplierX10 * s.weight !== 70000)) {
    throw new Error('FRUIT WHEEL must return exactly 70% on every card');
  }
}
assertBalancedTable();
export function parseBetKey(key: unknown) {
  return SEGMENTS.find(s => s.key !== 'crown' && s.key === key) ?? null;
}
export function payoutFor(stakes: Record<string, number>, result: string): number {
  const card = parseBetKey(result);
  return card ? Math.floor(Math.max(0, stakes[result] ?? 0) * card.multiplierX10 / 10) : 0;
}
export function maxPayout(stakes: Record<string, number>): number {
  return Math.max(...SEGMENTS.map(s => payoutFor(stakes, s.key)));
}
export function rollFromSeed(seed: string, roundId: number): Outcome {
  const digest = crypto.createHash('sha256').update(`${seed}:${roundId}`).digest('hex');
  let roll = Number(BigInt(`0x${digest.slice(0, 13)}`) % BigInt(TOTAL_WEIGHT));
  for (const s of SEGMENTS) {
    if (s.weight <= 0) continue;
    if (roll < s.weight) return s.key;
    roll -= s.weight;
  }
  throw new Error('Invalid FRUIT WHEEL weights');
}
/** Presentation only; the weighted outcome has already been committed. */
export function presentationFor(outcome: Outcome) {
  if (!WHEEL_ORDER.includes(outcome)) throw new Error('Invalid FRUIT WHEEL outcome');
  const slots = WHEEL_ORDER.flatMap((key, i) => key === outcome ? [i] : []);
  return { segment: slots[crypto.randomInt(slots.length)]!, offset: crypto.randomInt(150, 851) / 1000 };
}
export const returnOf = (key: Card) => {
  const s = parseBetKey(key)!;
  return s.multiplierX10 * s.weight / (10 * TOTAL_WEIGHT);
};
