import crypto from 'crypto';

/**
 * Versioned, pure server math for عجلة الفواكه (FRUIT WHEEL). The client only
 * replays what this returns.
 *
 * Players stack chips on three cards — watermelon ×2, 777 ×3, plum ×2 — and the
 * wheel picks one outcome. A card that matches pays its stake × its multiplier
 * (stake included); the others lose.
 *
 * The outcome is rolled by WEIGHT, then drawn onto one of the matching wheel
 * segments, exactly like القط الجشع. Card weights are proportional to
 * 1/multiplier, so every card returns the same share of its stake.
 *
 * BONUS lands 12% of the time: card bets lose, and the player opens one of
 * three orbs worth ×2 / ×3 / ×5 of a tenth of the total stake. The value is
 * decided with the outcome: whichever orb is tapped reveals it.
 *
 *   card return  = 3300 × 2 / 10000 = 2200 × 3 / 10000 = 66%
 *   bonus return = 12% × 10% × E[orb] (2.8)              ≈ 3.4%
 *   total RTP    ≈ 69.4% (scripts/fruit-wheel-sim.ts measures it)
 */
export const MATH_VERSION = 1;
export const CARDS = ['watermelon', 'sevens', 'plum'] as const;
export type Card = typeof CARDS[number];
export type Outcome = Card | 'bonus';
export const MULTIPLIERS: Record<Card, number> = { watermelon: 2, sevens: 3, plum: 2 };
export const WEIGHTS: Record<Outcome, number> = { watermelon: 3300, plum: 3300, sevens: 2200, bonus: 1200 };
export const TOTAL_WEIGHT = Object.values(WEIGHTS).reduce((a, b) => a + b, 0);
/** Ten equal segments, clockwise from the pointer. Presentation only. */
export const SEGMENTS: Outcome[] = [
  'watermelon', 'plum', 'watermelon', 'plum', 'sevens',
  'watermelon', 'plum', 'watermelon', 'plum', 'bonus',
];
export const ORBS = [
  { multiplier: 2, weight: 50 },
  { multiplier: 3, weight: 35 },
  { multiplier: 5, weight: 15 },
] as const;
/** The orb multiplies this share of the total stake. */
export const BONUS_BASE = 0.1;
export const CHIPS = [100, 1000, 10000, 100000];
export const MIN_BET = 100;
export const MAX_BET = 300000;
/** Largest payout as a multiple of the TOTAL stake (all of it on 777). */
export const MAX_MULTIPLIER = 3;
export const TARGET_RTP = 0.694;

export interface Rng { nextFloat(): number }
export class RngStream implements Rng {
  private block = Buffer.alloc(0);
  private cursor = 0;
  private index = 0;
  constructor(private serverSeed: string, private clientSeed: string, private nonce: number) {}
  nextFloat(): number {
    if (this.cursor + 4 > this.block.length) {
      this.block = crypto.createHmac('sha256', this.serverSeed)
        .update(`${this.clientSeed}:${this.nonce}:${this.index++}`).digest();
      this.cursor = 0;
    }
    const n = this.block.readUInt32BE(this.cursor);
    this.cursor += 4;
    return n / 0x100000000;
  }
}

export type Bets = Record<Card, number>;

/** Every card present, whole non-negative coins, a chip-sized total within range. */
export function parseBets(input: unknown, min = MIN_BET, max = MAX_BET): Bets | null {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const raw = input as Record<string, unknown>;
  if (Object.keys(raw).some(k => !(CARDS as readonly string[]).includes(k))) return null;
  const bets = {} as Bets;
  for (const card of CARDS) {
    const v = raw[card] ?? 0;
    if (typeof v !== 'number' || !Number.isSafeInteger(v) || v < 0 || v % MIN_BET !== 0) return null;
    bets[card] = v;
  }
  const total = totalOf(bets);
  return total >= min && total <= max ? bets : null;
}
export const totalOf = (bets: Bets) => CARDS.reduce((s, c) => s + bets[c], 0);

function pickWeighted<T>(rng: Rng, entries: [T, number][]): T {
  const total = entries.reduce((s, [, w]) => s + w, 0);
  let roll = rng.nextFloat() * total;
  for (const [value, weight] of entries) {
    if (roll < weight) return value;
    roll -= weight;
  }
  return entries[entries.length - 1]![0];
}

/** The most one round can pay for these bets. */
export function maxPrize(bets: Bets): number {
  return Math.max(...CARDS.map(c => bets[c] * MULTIPLIERS[c]), Math.floor(totalOf(bets) * BONUS_BASE * 5));
}

export interface Spin {
  mathVersion: number;
  bets: Bets;
  totalBet: number;
  outcome: Outcome;
  /** Wheel segment index (0–9) the pointer stops on. */
  segment: number;
  /** Fraction (0–1) across that segment where it stops, so landings vary. */
  offset: number;
  /** Card that won, if any, and what it paid. */
  winner: Card | null;
  cardPrize: number;
  /** Bonus only: the orb value won first, then the two the player did not open. */
  orbs: number[] | null;
  bonusPrize: number;
  totalPrize: number;
}

export function computeSpin(rng: Rng, bets: Bets): Spin {
  const outcome = pickWeighted(rng, Object.entries(WEIGHTS) as [Outcome, number][]);
  const slots = SEGMENTS.map((s, i) => [s, i] as const).filter(([s]) => s === outcome).map(([, i]) => i);
  const segment = slots[Math.floor(rng.nextFloat() * slots.length)]!;
  // Keep clear of the segment borders so the pointer never sits on a line.
  const offset = Math.round((0.15 + rng.nextFloat() * 0.7) * 1000) / 1000;
  const totalBet = totalOf(bets);
  let winner: Card | null = null, cardPrize = 0, orbs: number[] | null = null, bonusPrize = 0;
  if (outcome === 'bonus') {
    const value = pickWeighted(rng, ORBS.map(o => [o.multiplier, o.weight] as [number, number]));
    const others = ORBS.map(o => o.multiplier as number).filter(m => m !== value);
    if (rng.nextFloat() < 0.5) others.reverse();
    orbs = [value, ...others];
    bonusPrize = Math.floor(totalBet * BONUS_BASE * value);
  } else {
    winner = outcome;
    cardPrize = bets[outcome] * MULTIPLIERS[outcome];
  }
  return { mathVersion: MATH_VERSION, bets, totalBet, outcome, segment, offset, winner, cardPrize,
    orbs, bonusPrize, totalPrize: cardPrize + bonusPrize };
}
