/**
 * القط الجشع — Greedy Cat RTP simulator.
 *
 * Replays the *shipped* roll (`rollFromSeed`, the same pure function the round
 * engine calls when betting closes) over a large number of rounds and reports
 * what each bet actually returns. Nothing here re-implements the game — if a
 * weight or a multiplier moves, this measures the new ones on the next run.
 *
 *   npm run sim:greedy                        # 500k rounds, default seeds
 *   npm run sim:greedy -- --rounds 2000000    # longer run
 *   npm run sim:greedy -- --bet 100           # check payout rounding at the min stake
 *   npm run sim:greedy -- --seeds 5           # more independent seeds
 *
 * What to look for: every one of the ten bets — eight symbols plus the two
 * category shortcuts — should converge on the SAME return, 97.19%. That equality
 * is the design guarantee (weights are proportional to 1/multiplier), and it is
 * what lets the rules modal say no bet on the table is better than any other.
 *
 * The 45× chicken carries a third of its return from a 1-in-46 tail, so a short
 * run can sit a point or two off. Read the spread across seeds, not any one
 * number.
 *
 * Note: importing the service pulls in Prisma, but no query runs — `rollFromSeed`
 * is pure, so this never touches the database.
 */

import crypto from 'crypto';
import {
  CATEGORIES,
  CATEGORY_SPLIT,
  MIN_BET,
  RTP,
  SYMBOLS,
  rollFromSeed,
} from '../src/services/greedyCat.service';

interface Args {
  rounds: number;
  bet: number;
  seeds: number;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { rounds: 500_000, bet: 1_000, seeds: 3 };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const value = Number(argv[i + 1]);
    if (flag === '--rounds' && Number.isFinite(value)) { args.rounds = Math.trunc(value); i++; }
    else if (flag === '--bet' && Number.isFinite(value)) { args.bet = Math.trunc(value); i++; }
    else if (flag === '--seeds' && Number.isFinite(value)) { args.seeds = Math.trunc(value); i++; }
  }
  if (args.bet < MIN_BET) {
    throw new Error(`--bet must be at least ${MIN_BET}`);
  }
  if (args.bet % CATEGORY_SPLIT !== 0) {
    throw new Error(`--bet must divide by ${CATEGORY_SPLIT} so a category bet can be split`);
  }
  return args;
}

const TOTAL_WEIGHT = SYMBOLS.reduce((sum, s) => sum + s.weight, 0);

/** Mirrors `splitCategory` in the service: even shares, remainder on the last. */
function splitCategory(keys: readonly string[], amount: number): Record<string, number> {
  const share = Math.floor(amount / CATEGORY_SPLIT);
  const out: Record<string, number> = {};
  let handed = 0;
  keys.forEach((key, i) => {
    const value = i === keys.length - 1 ? amount - handed : share;
    out[key] = value;
    handed += value;
  });
  return out;
}

interface Tally {
  staked: number;
  returned: number;
}

function runSeed(seed: string, rounds: number, bet: number) {
  const hits = new Map<string, number>(SYMBOLS.map((s) => [s.key, 0]));
  // One tally per bet a player can actually place: 8 symbols + 2 categories.
  const tallies = new Map<string, Tally>();
  for (const s of SYMBOLS) tallies.set(s.key, { staked: 0, returned: 0 });
  for (const key of Object.keys(CATEGORIES)) tallies.set(key, { staked: 0, returned: 0 });

  const categoryStakes = new Map<string, Record<string, number>>();
  for (const [key, members] of Object.entries(CATEGORIES)) {
    categoryStakes.set(key, splitCategory(members, bet));
  }

  for (let round = 1; round <= rounds; round++) {
    const index = rollFromSeed(seed, round);
    const winner = SYMBOLS[index]!;
    hits.set(winner.key, (hits.get(winner.key) ?? 0) + 1);

    // A flat bet on every symbol, scored independently.
    for (const s of SYMBOLS) {
      const tally = tallies.get(s.key)!;
      tally.staked += bet;
      if (s.key === winner.key) tally.returned += Math.floor(bet * winner.multiplier);
    }

    // And a flat bet on each category, settled the way the service settles it:
    // four symbol stakes, only the winning one pays.
    for (const key of Object.keys(CATEGORIES)) {
      const tally = tallies.get(key)!;
      tally.staked += bet;
      const onWinner = categoryStakes.get(key)![winner.key] ?? 0;
      if (onWinner > 0) tally.returned += Math.floor(onWinner * winner.multiplier);
    }
  }

  return { hits, tallies };
}

function pct(n: number): string {
  return `${(n * 100).toFixed(2)}%`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const target = RTP;

  console.log('القط الجشع — Greedy Cat RTP simulator');
  console.log(
    `rounds=${args.rounds.toLocaleString()}  bet=${args.bet.toLocaleString()}  seeds=${args.seeds}`,
  );
  console.log(`design RTP = 450/${TOTAL_WEIGHT} = ${pct(target)} on every bet\n`);

  const byBet = new Map<string, number[]>();
  const byHit = new Map<string, number[]>();

  for (let s = 0; s < args.seeds; s++) {
    const seed = crypto.randomBytes(16).toString('hex');
    const { hits, tallies } = runSeed(seed, args.rounds, args.bet);

    for (const [key, tally] of tallies) {
      const list = byBet.get(key) ?? [];
      list.push(tally.returned / tally.staked);
      byBet.set(key, list);
    }
    for (const [key, count] of hits) {
      const list = byHit.get(key) ?? [];
      list.push(count / args.rounds);
      byHit.set(key, list);
    }
  }

  const mean = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;

  console.log('symbol      mult   weight   expected hit   measured hit    measured RTP');
  console.log('─────────────────────────────────────────────────────────────────────────');
  for (const s of SYMBOLS) {
    const expected = s.weight / TOTAL_WEIGHT;
    const measured = mean(byHit.get(s.key)!);
    const rtp = mean(byBet.get(s.key)!);
    console.log(
      `${s.key.padEnd(10)} ${String(s.multiplier).padStart(4)}×  ${String(s.weight).padStart(5)}   ` +
        `${pct(expected).padStart(11)}   ${pct(measured).padStart(11)}   ${pct(rtp).padStart(13)}`,
    );
  }

  console.log('\ncategory shortcut (stake split four ways)          measured RTP');
  console.log('─────────────────────────────────────────────────────────────────────────');
  for (const key of Object.keys(CATEGORIES)) {
    const rtp = mean(byBet.get(key)!);
    const members = CATEGORIES[key as keyof typeof CATEGORIES].join(', ');
    console.log(`${key.padEnd(8)} (${members})`.padEnd(50) + pct(rtp).padStart(13));
  }

  const all = [...byBet.values()].map(mean);
  const worst = Math.max(...all.map((r) => Math.abs(r - target)));
  console.log(
    `\nwidest drift from the design RTP across all ten bets: ${(worst * 100).toFixed(2)} points`,
  );
  // Sampling noise on the 45× tail is the dominant term; anything past a point
  // and a half on a run this long means the weights and multipliers disagree.
  console.log(worst < 0.015 ? 'PASS — every bet returns the same 97.19%.' : 'CHECK — a bet is drifting; re-read the weights.');
}

main();
