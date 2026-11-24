import type { Prisma } from '@prisma/client';

export const TABLE_TIERS = [
  [5, 0], [10, 0], [0, 100], [0, 250], [0, 500], [0, 1000],
  [5, 100], [5, 250], [5, 500], [5, 1000],
  [10, 100], [10, 250], [10, 500], [10, 1000],
] as const;
export interface TableRow {
  giftValue: number; thresholds: number[]; tier: number; counter: number;
  testTier: number; testCounter: number;
  fixed5?: number; fixed10?: number; testFixed5?: number; testFixed10?: number;
}
export function validTable(value: unknown, thresholds: unknown): thresholds is number[] {
  return Number.isInteger(value) && Number(value) > 0 && Number(value) <= 1_000_000 &&
    Array.isArray(thresholds) && thresholds.length === TABLE_TIERS.length &&
    thresholds.every(n => Number.isInteger(n) && n > 0 && n <= 2_000_000_000);
}
/** Table payout: each fired tier pays multiplier x UNIT price x mic count (never x quantity again). */
export function tablePayout(multiplier: number, unitValue: number, mics: number) {
  return multiplier * unitValue * Math.max(1, mics);
}
export interface FixedCounters { c5: number; c10: number }
/**
 * A batch is one draw on the entire stake; excess throws carry into subsequent tiers.
 *
 * With `fixed` (24/11 rule) the x5 and x10 rows are INDEPENDENT forever-counters:
 * x5 fires every thresholds[0] throws and x10 every thresholds[1] throws, whatever the
 * bigger tiers are doing; tiers 2..13 keep their own sequential ladder (wrapping to 2),
 * so a pending x1000 never blocks x5/x10. Without `fixed` the legacy 14-step ladder runs.
 */
export function advanceTable(thresholds: number[], tier: number, counter: number, throws: number, fixed?: FixedCounters) {
  if (!validTable(1, thresholds) || !Number.isInteger(throws) || throws < 1 || throws > 1_000_000 ||
      !Number.isInteger(tier) || tier < 0 || tier >= 14 || !Number.isInteger(counter) || counter < 0 ||
      (fixed && (!Number.isInteger(fixed.c5) || fixed.c5 < 0 || !Number.isInteger(fixed.c10) || fixed.c10 < 0))) {
    throw new Error('Invalid lucky table state or throw count');
  }
  counter += throws;
  let multiplier = 0;
  const fired: number[] = [];
  let c5: number | undefined;
  let c10: number | undefined;
  let first = 0;
  if (fixed) {
    c5 = fixed.c5 + throws;
    const n5 = Math.floor(c5 / thresholds[0]!);
    c5 -= n5 * thresholds[0]!;
    for (let i = 0; i < n5; i++) fired.push(0);
    multiplier += 5 * n5;
    c10 = fixed.c10 + throws;
    const n10 = Math.floor(c10 / thresholds[1]!);
    c10 -= n10 * thresholds[1]!;
    for (let i = 0; i < n10; i++) fired.push(1);
    multiplier += 10 * n10;
    first = 2;
    if (tier < 2) tier = 2;
  }
  while (counter >= thresholds[tier]!) {
    counter -= thresholds[tier]!;
    const [inner, outer] = TABLE_TIERS[tier]!;
    // Client combo thresholds scale by inner times outer (e.g. x5/x100 = x500).
    multiplier += inner && outer ? inner * outer : inner || outer;
    fired.push(tier);
    tier = tier + 1 >= TABLE_TIERS.length ? first : tier + 1;
  }
  return fixed ? { tier, counter, multiplier, fired, c5: c5!, c10: c10! } : { tier, counter, multiplier, fired };
}
export async function drawTable(tx: Prisma.TransactionClient, giftValue: number, throws: number, test = false, mics = 1) {
  // Older in-memory transaction adapters have no SQL interface.
  if (!tx.$queryRaw) return null;
  const rows = await tx.$queryRaw<TableRow[]>`SELECT * FROM lucky_control_rows WHERE "giftValue" = ${giftValue} FOR UPDATE`;
  const row = rows[0];
  if (!row) return null;
  // Independent x5/x10 counters exist once migration 20261124000000 is applied; before that
  // (columns absent) the legacy sequential ladder keeps running unchanged.
  const hasFixed = row.fixed5 !== undefined && row.fixed10 !== undefined;
  const prevTier = test ? row.testTier : row.tier;
  const prevCounter = test ? row.testCounter : row.counter;
  const prevFixed = hasFixed ? { c5: Number(test ? row.testFixed5 : row.fixed5), c10: Number(test ? row.testFixed10 : row.fixed10) } : undefined;
  const result = advanceTable(row.thresholds, prevTier, prevCounter, throws, prevFixed);
  const f = result as { c5?: number; c10?: number };
  if (test) {
    if (hasFixed) await tx.$executeRaw`UPDATE lucky_control_rows SET "testTier" = ${result.tier}, "testCounter" = ${result.counter}, "testFixed5" = ${f.c5}, "testFixed10" = ${f.c10} WHERE "giftValue" = ${giftValue}`;
    else await tx.$executeRaw`UPDATE lucky_control_rows SET "testTier" = ${result.tier}, "testCounter" = ${result.counter} WHERE "giftValue" = ${giftValue}`;
  } else {
    if (hasFixed) await tx.$executeRaw`UPDATE lucky_control_rows SET tier = ${result.tier}, counter = ${result.counter}, fixed5 = ${f.c5}, fixed10 = ${f.c10} WHERE "giftValue" = ${giftValue}`;
    else await tx.$executeRaw`UPDATE lucky_control_rows SET tier = ${result.tier}, counter = ${result.counter} WHERE "giftValue" = ${giftValue}`;
  }
  return { ...result, mode: 'table', giftValue, throws, mics, previousTier: prevTier,
    previousCounter: prevCounter, previousFixed5: prevFixed?.c5, previousFixed10: prevFixed?.c10, thresholds: row.thresholds };
}
