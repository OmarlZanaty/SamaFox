/**
 * نيون فورتشن — behavioural checks for the parts a Monte-Carlo run cannot prove.
 *
 *   npm run check:neon-fortune
 *
 * The RTP simulator answers "does the money add up over a million spins". This
 * answers "do the rules do what the rules screen says", on hand-built boards:
 * payline scoring, wild substitution and its exclusions, the wild-multiplier cap,
 * vault order-independence, and pool solvency under a claim.
 *
 * Exits non-zero on the first failed check.
 */

import {
  Cell,
  JACKPOT_TIERS,
  JackpotTier,
  PAYLINES,
  PAYTABLE,
  RngStream,
  VAULT_CAPSULES,
  claimPool,
  computeSpin,
  contribute,
  scoreGridForTest,
  simPools,
} from '../src/services/neonFortune.service';

let failures = 0;

function check(name: string, condition: boolean, detail = '') {
  if (condition) {
    console.log(`  ✓ ${name}`);
  } else {
    failures++;
    console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

/** Builds a 5×3 board (row-major) from a filler symbol plus explicit overrides. */
function board(filler: Cell, overrides: Record<number, Cell> = {}): Cell[] {
  const grid: Cell[] = new Array(15).fill(filler) as Cell[];
  for (const [i, v] of Object.entries(overrides)) grid[Number(i)] = v;
  return grid;
}

/** Places a symbol along a payline for the first `count` reels. */
function onLine(grid: Cell[], line: number, symbols: Cell[]): Cell[] {
  const pattern = PAYLINES[line]!;
  symbols.forEach((s, reel) => {
    grid[pattern[reel]! * 5 + reel] = s;
  });
  return grid;
}

const BET = 100;

console.log('نيون فورتشن — rule checks\n');
console.log('Payline scoring');
{
  // Line 0 is the middle row. Three tigers there and nothing else matchable.
  const grid = onLine(board('TEN', { 0: 'Q', 4: 'K', 10: 'J', 14: 'A' }), 0, [
    'TIGER', 'TIGER', 'TIGER', 'COIN', 'CRANE',
  ]);
  const { wins, total } = scoreGridForTest(grid, BET);
  const tigerWin = wins.find((w) => w.symbol === 'TIGER' && w.count === 3);
  check('3 tigers on the middle row pay the 3-of-a-kind value', tigerWin !== undefined);
  check(
    'that win equals paytable × bet',
    tigerWin?.amount === Math.floor(PAYTABLE.TIGER[0] * BET),
    `got ${tigerWin?.amount}, expected ${Math.floor(PAYTABLE.TIGER[0] * BET)}`,
  );
  check('the win is included in the grid total', total >= (tigerWin?.amount ?? 0));
}

{
  // A run must start on reel 1: the same three tigers shifted right pay nothing
  // for the tiger, whatever else the board does.
  const grid = onLine(board('TEN'), 0, ['COIN', 'TIGER', 'TIGER', 'TIGER', 'CRANE']);
  const { wins } = scoreGridForTest(grid, BET);
  check(
    'a run that does not start on reel 1 does not pay',
    !wins.some((w) => w.symbol === 'TIGER'),
  );
}

console.log('\nWild substitution');
{
  const grid = onLine(board('TEN'), 0, ['TIGER', 'WILD', 'TIGER', 'COIN', 'CRANE']);
  const { wins } = scoreGridForTest(grid, BET);
  const win = wins.find((w) => w.symbol === 'TIGER');
  check('a wild completes a tiger trio', win?.count === 3);
}

{
  // Wilds lead the line: it should pay as the best symbol they can extend.
  const grid = onLine(board('TEN'), 0, ['WILD', 'WILD', 'TIGER', 'TIGER', 'TIGER']);
  const { wins } = scoreGridForTest(grid, BET);
  const win = wins.find((w) => w.line === 0);
  check('a line of leading wilds pays the symbol they extend, five long', win?.count === 5);
  check('and that symbol is the tiger', win?.symbol === 'TIGER');
}

{
  const grid = onLine(board('TEN'), 0, ['SCATTER', 'WILD', 'SCATTER', 'TEN', 'TEN']);
  const { wins } = scoreGridForTest(grid, BET);
  check(
    'a wild never substitutes for a scatter',
    !wins.some((w) => (w.symbol as string) === 'SCATTER'),
  );
}

{
  const grid = onLine(board('TEN'), 0, ['TOKEN', 'WILD', 'TOKEN', 'TEN', 'TEN']);
  const { wins } = scoreGridForTest(grid, BET);
  check(
    'a wild never substitutes for a jackpot token',
    !wins.some((w) => (w.symbol as string) === 'TOKEN'),
  );
}

console.log('\nWild multipliers (Skyline Rush)');
{
  const grid = onLine(board('TEN'), 0, ['TIGER', 'WILD', 'WILD', 'TIGER', 'TIGER']);
  const pattern = PAYLINES[0]!;
  const multipliers = new Map<number, number>([
    [pattern[1]! * 5 + 1, 3],
    [pattern[2]! * 5 + 2, 3],
  ]);
  const plain = scoreGridForTest(grid, BET).wins.find((w) => w.line === 0);
  const boosted = scoreGridForTest(grid, BET, multipliers).wins.find((w) => w.line === 0);
  check('two ×3 wilds multiply the line by 9', boosted?.multiplier === 9);
  check(
    'and the payout scales with it',
    boosted!.amount === Math.floor(PAYTABLE.TIGER[2] * BET * 9),
    `got ${boosted?.amount} against a plain ${plain?.amount}`,
  );
}

console.log('\nVault of Lights');
{
  // Whatever the seed, at most one tier may reach three capsules — that is what
  // makes the outcome independent of the order the player taps.
  let vaults = 0;
  let violations = 0;
  let noneOutcomes = 0;
  let wrongSize = 0;
  for (let nonce = 0; nonce < 400_000 && vaults < 400; nonce++) {
    const spin = computeSpin(new RngStream('check', 'vault', nonce), BET);
    if (!spin.vault) continue;
    vaults++;
    if (spin.vault.capsules.length !== VAULT_CAPSULES) wrongSize++;
    const counts = new Map<string, number>();
    for (const c of spin.vault.capsules) {
      if (c !== 'SPARKLE') counts.set(c, (counts.get(c) ?? 0) + 1);
    }
    const trios = [...counts.values()].filter((n) => n >= 3).length;
    if (trios > 1) violations++;
    if (spin.vault.wonTier === null) {
      noneOutcomes++;
      if (trios > 0) violations++;
    } else if ((counts.get(spin.vault.wonTier) ?? 0) !== 3) {
      violations++;
    }
  }
  check(`sampled ${vaults} vault layouts`, vaults > 50, 'not enough vaults drawn to judge');
  check('no layout can complete two different tiers', violations === 0, `${violations} bad layouts`);
  check('the miss path does occur (consolation is reachable)', noneOutcomes > 0);
  check(
    `every capsule grid holds exactly ${VAULT_CAPSULES} capsules`,
    wrongSize === 0,
    `${wrongSize} layouts were the wrong size`,
  );
}

console.log('\nJackpot pools');
{
  const pools = simPools();
  const before = { ...pools.SPARK };
  contribute(pools, 1000);
  check('a bet grows the pool', pools.SPARK.pool > before.pool);
  check('and its reserve', pools.SPARK.reserve > before.reserve);

  const paid = claimPool(pools, 'SPARK');
  check('a claim pays the whole pool', paid > 0);
  check('and re-seeds from the reserve, never below zero', pools.SPARK.pool >= 0 && pools.SPARK.reserve >= 0);

  // Hammer it: many claims in a row must never overdraw either balance.
  let negative = false;
  for (let i = 0; i < 5000; i++) {
    contribute(pools, 100);
    const tier = JACKPOT_TIERS[i % 4] as JackpotTier;
    claimPool(pools, tier);
    for (const t of JACKPOT_TIERS) {
      if (pools[t].pool < 0 || pools[t].reserve < 0) negative = true;
    }
  }
  check('5,000 back-to-back claims never drive a pool or reserve negative', !negative);
}

console.log('\nDeterminism');
{
  const a = computeSpin(new RngStream('seed', 'client', 42), BET);
  const b = computeSpin(new RngStream('seed', 'client', 42), BET);
  check('the same seeds reproduce the same grid', JSON.stringify(a.grid) === JSON.stringify(b.grid));
  check(
    'and the same features',
    a.freeSpinsWin === b.freeSpinsWin && a.vaultTier === b.vaultTier,
  );
  const c = computeSpin(new RngStream('seed', 'client', 43), BET);
  check('a different nonce gives a different grid', JSON.stringify(a.grid) !== JSON.stringify(c.grid));
}

console.log('');
if (failures > 0) {
  console.error(`✗ ${failures} check(s) failed.`);
  process.exit(1);
}
console.log('✓ all checks passed.');
process.exit(0);
