import type { Prisma } from '@prisma/client';

export const TABLE_TIERS = [
  [5, 0], [10, 0], [0, 100], [0, 250], [0, 500], [0, 1000],
  [5, 100], [5, 250], [5, 500], [5, 1000],
  [10, 100], [10, 250], [10, 500], [10, 1000],
] as const;
export interface TableRow {
  giftValue: number; thresholds: number[]; tier: number; counter: number;
  testTier: number; testCounter: number;
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
/** A batch is one draw on the entire stake; excess throws carry into subsequent tiers. */
export function advanceTable(thresholds: number[], tier: number, counter: number, throws: number) {
  if (!validTable(1, thresholds) || !Number.isInteger(throws) || throws < 1 || throws > 1_000_000 ||
      !Number.isInteger(tier) || tier < 0 || tier >= 14 || !Number.isInteger(counter) || counter < 0) {
    throw new Error('Invalid lucky table state or throw count');
  }
  counter += throws;
  let multiplier = 0;
  const fired: number[] = [];
  while (counter >= thresholds[tier]!) {
    counter -= thresholds[tier]!;
    const [inner, outer] = TABLE_TIERS[tier]!;
    // Client combo thresholds scale by inner times outer (e.g. x5/x100 = x500).
    multiplier += inner && outer ? inner * outer : inner || outer;
    fired.push(tier);
    tier = (tier + 1) % TABLE_TIERS.length;
  }
  return { tier, counter, multiplier, fired };
}
export async function drawTable(tx: Prisma.TransactionClient, giftValue: number, throws: number, test = false, mics = 1) {
  // Older in-memory transaction adapters have no SQL interface.
  if (!tx.$queryRaw) return null;
  const rows = await tx.$queryRaw<TableRow[]>`SELECT * FROM lucky_control_rows WHERE "giftValue" = ${giftValue} FOR UPDATE`;
  const row = rows[0];
  if (!row) return null;
  const result = advanceTable(row.thresholds, test ? row.testTier : row.tier, test ? row.testCounter : row.counter, throws);
  if (test) {
    await tx.$executeRaw`UPDATE lucky_control_rows SET "testTier" = ${result.tier}, "testCounter" = ${result.counter} WHERE "giftValue" = ${giftValue}`;
  } else {
    await tx.$executeRaw`UPDATE lucky_control_rows SET tier = ${result.tier}, counter = ${result.counter} WHERE "giftValue" = ${giftValue}`;
  }
  return { ...result, mode: 'table', giftValue, throws, mics, previousTier: test ? row.testTier : row.tier,
    previousCounter: test ? row.testCounter : row.counter, thresholds: row.thresholds };
}
