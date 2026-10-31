/**
 * Shared-round games take every bet even when the prize pool is short
 * (client rule, 31/10). Such a bet holds only what the pool had left, so the
 * round avoids an outcome that would owe a player more than is held for
 * them: starting at the fair roll, the next outcome in wheel order that every
 * table can pay wins. With no such outcome the fair roll stands and the short
 * winner is not paid (payPrize).
 */
export function steerForPool<T>(
  rolled: T,
  order: readonly T[],
  players: Iterable<{ stakes: Record<string, number>; reserved: number }>,
  payoutFor: (stakes: Record<string, number>, result: T) => number,
): T {
  const table = [...players];
  const fits = (result: T) => table.every(p => payoutFor(p.stakes, result) <= p.reserved);
  if (fits(rolled)) return rolled;
  const start = Math.max(0, order.indexOf(rolled));
  for (let i = 1; i < order.length; i++) {
    const candidate = order[(start + i) % order.length]!;
    if (fits(candidate)) return candidate;
  }
  return rolled;
}
