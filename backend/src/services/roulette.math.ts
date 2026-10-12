import crypto from 'crypto';

/**
 * Pure maths for الروليت (ROULETTE): a single-zero European wheel shared by
 * every player in a timed round (roulette.service.ts runs the rounds).
 *
 * Pockets are the standard European order. Every number 0–36 is equally
 * likely: the round's committed seed is hashed and reduced mod 37.
 *
 * Payouts are TOTAL returns (stake included), cut from the casino table so the
 * game fits the platform's 25% program / 75% prize-pool split — the same
 * reasoning that took القط الجشع from 97% to 79.75%. Standard European play
 * returns 97.3%, more than the pool ever receives. Here every bet returns
 * close to 70%:
 *
 *   bet          covers  pays   return
 *   straight       1     ×26    70.3%
 *   split          2     ×13    70.3%
 *   street         3     ×8.6   69.7%
 *   corner / 0-1-2-3  4  ×6.5   70.3%
 *   six line       6     ×4.3   69.7%
 *   dozen / column 12    ×2.1   68.1%
 *   red, black, odd, even, 1–18, 19–36   18   ×1.4   68.1%
 *
 * Zero loses every outside bet; it wins only bets that cover it.
 */
export const WHEEL_ORDER = [
  0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5,
  24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
] as const;
export const RED = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]);
export const colorOf = (n: number): 'green' | 'red' | 'black' => (n === 0 ? 'green' : RED.has(n) ? 'red' : 'black');

export type BetType = 'straight' | 'split' | 'street' | 'corner' | 'sixLine' | 'firstFour'
  | 'red' | 'black' | 'odd' | 'even' | 'low' | 'high'
  | 'dozen1' | 'dozen2' | 'dozen3' | 'column1' | 'column2' | 'column3';

/** Total return per coin staked, by bet type. */
export const MULTIPLIERS: Record<BetType, number> = {
  straight: 26, split: 13, street: 8.6, corner: 6.5, sixLine: 4.3, firstFour: 6.5,
  red: 1.4, black: 1.4, odd: 1.4, even: 1.4, low: 1.4, high: 1.4,
  dozen1: 2.1, dozen2: 2.1, dozen3: 2.1, column1: 2.1, column2: 2.1, column3: 2.1,
};
/** The same table in tenths, so payouts are integer maths (1.4 × 500 is not 700 in floats). */
const TENTHS = Object.fromEntries(Object.entries(MULTIPLIERS).map(([k, m]) => [k, Math.round(m * 10)])) as Record<BetType, number>;
export const CHIPS = [100, 500, 1000, 5000, 10000];
export const MAX_PER_KEY = 1_000_000;

const range = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => from + i);
const OUTSIDE: Record<string, number[]> = {
  red: [...RED].sort((a, b) => a - b),
  black: range(1, 36).filter(n => !RED.has(n)),
  odd: range(1, 36).filter(n => n % 2 === 1),
  even: range(1, 36).filter(n => n % 2 === 0),
  low: range(1, 18), high: range(19, 36),
  dozen1: range(1, 12), dozen2: range(13, 24), dozen3: range(25, 36),
  column1: range(1, 36).filter(n => n % 3 === 1),
  column2: range(1, 36).filter(n => n % 3 === 2),
  column3: range(1, 36).filter(n => n % 3 === 0),
};

export interface Bet { key: string; type: BetType; numbers: number[] }

/**
 * Bet keys, as the client sends them:
 *   n:17 · split:17-20 · street:16 · corner:16-17-19-20 · six:16 · ff (0-1-2-3)
 *   red black odd even low high dozen1-3 column1-3
 * The table is 12 rows of three (1-2-3, 4-5-6 …); `street:n` and `six:n` take
 * the first number of their (top) row. Anything that is not a real table
 * position returns null.
 */
export function parseBetKey(key: unknown): Bet | null {
  if (typeof key !== 'string' || key.length > 24) return null;
  if (key in OUTSIDE) return { key, type: key as BetType, numbers: OUTSIDE[key]! };
  if (key === 'ff') return { key, type: 'firstFour', numbers: [0, 1, 2, 3] };
  const [kind, rest] = key.split(':') as [string, string | undefined];
  if (!rest) return null;
  const nums = rest.split('-').map(s => (/^\d{1,2}$/.test(s) ? Number(s) : NaN));
  if (nums.some(n => !Number.isInteger(n) || n < 0 || n > 36)) return null;
  const [a] = nums as [number];
  const sorted = [...nums].sort((x, y) => x - y);
  if (sorted.join('-') !== rest) return null; // one spelling per bet
  switch (kind) {
    case 'n':
      return nums.length === 1 ? { key, type: 'straight', numbers: [a] } : null;
    case 'split': {
      if (nums.length !== 2) return null;
      const [x, y] = sorted as [number, number];
      // Zero splits with 1, 2 or 3; otherwise neighbours across or down a row.
      const ok = x === 0 ? y >= 1 && y <= 3
        : (y === x + 1 && x % 3 !== 0) || y === x + 3;
      return ok ? { key, type: 'split', numbers: sorted } : null;
    }
    case 'street':
      return nums.length === 1 && a >= 1 && a % 3 === 1 ? { key, type: 'street', numbers: [a, a + 1, a + 2] } : null;
    case 'six':
      return nums.length === 1 && a >= 1 && a <= 31 && a % 3 === 1
        ? { key, type: 'sixLine', numbers: range(a, a + 5) } : null;
    case 'corner': {
      if (nums.length !== 4) return null;
      const [x] = sorted as [number];
      const ok = x >= 1 && x % 3 !== 0 && x <= 32 && sorted.join('-') === [x, x + 1, x + 3, x + 4].join('-');
      return ok ? { key, type: 'corner', numbers: sorted } : null;
    }
    default:
      return null;
  }
}

/** What a set of stakes returns when the ball lands on [result]. */
export function payoutFor(stakes: Record<string, number>, result: number): number {
  let tenths = 0;
  for (const [key, amount] of Object.entries(stakes)) {
    const bet = parseBetKey(key);
    if (bet && amount > 0 && bet.numbers.includes(result)) tenths += amount * TENTHS[bet.type];
  }
  return Math.floor(tenths / 10);
}

/** The most these stakes could return on any single number. */
export function maxPayout(stakes: Record<string, number>): number {
  let best = 0;
  for (let n = 0; n <= 36; n++) best = Math.max(best, payoutFor(stakes, n));
  return best;
}

/** The pocket a committed round seed always meant: sha256(seed:roundId) mod 37. */
export function rollFromSeed(seed: string, roundId: number): number {
  const digest = crypto.createHash('sha256').update(`${seed}:${roundId}`).digest('hex');
  return Number(BigInt(`0x${digest.slice(0, 13)}`) % 37n);
}

/** Average return of one bet type, for the help screen and the tests. */
export function returnOf(type: BetType, coverage: number): number {
  return (MULTIPLIERS[type] * coverage) / 37;
}
