/**
 * أثيرفول — Aetherfall RTP simulator.
 *
 * Replays the *shipped* spin math (`verifySpin`, the same pure function the
 * provably-fair endpoint uses) over a large number of nonces and reports what
 * the paytable actually returns. Nothing here re-implements the game — if the
 * weights or the paytable move, this measures the new ones on the next run.
 *
 *   npm run sim:aetherfall                       # 400k spins, default seeds
 *   npm run sim:aetherfall -- --spins 1000000    # longer run
 *   npm run sim:aetherfall -- --bet 1000         # check payout rounding at a bigger stake
 *   npm run sim:aetherfall -- --seeds 5          # more independent seeds
 *
 * Why more than one seed: the Skyfire Vault fires about 1 in 115 spins and pays
 * ~22x bet, so it supplies a fifth of the return from a thin tail. A single
 * 100k-spin run can land a point or two off purely on how many bonuses it drew.
 * Read the spread across seeds, not any one number.
 *
 * Note: importing the service pulls in Prisma, but no query runs — `verifySpin`
 * is pure, so this never touches the database.
 */

import { verifySpin, MIN_BET, MAX_BET } from '../src/services/aetherfall.service';

interface Args {
  spins: number;
  bet: number;
  seeds: number;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { spins: 400_000, bet: MIN_BET, seeds: 3 };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const value = Number(argv[i + 1]);
    if (flag === '--spins' && Number.isFinite(value)) { args.spins = Math.trunc(value); i++; }
    else if (flag === '--bet' && Number.isFinite(value)) { args.bet = Math.trunc(value); i++; }
    else if (flag === '--seeds' && Number.isFinite(value)) { args.seeds = Math.trunc(value); i++; }
  }
  if (args.bet < MIN_BET || args.bet > MAX_BET) {
    throw new Error(`--bet must be between ${MIN_BET} and ${MAX_BET}`);
  }
  if (args.spins < 1 || args.seeds < 1) throw new Error('--spins and --seeds must be positive');
  return args;
}

interface Run {
  seed: string;
  rtp: number;
  baseRtp: number;
  bonusRtp: number;
  hitRate: number;
  bonusRate: number;
  avgBonusPay: number;
  maxWinX: number;
}

function simulate(seed: string, spins: number, bet: number): Run {
  let returned = 0;
  let baseReturned = 0;
  let bonusReturned = 0;
  let wins = 0;
  let bonuses = 0;
  let maxWin = 0;

  for (let nonce = 0; nonce < spins; nonce++) {
    const spin = verifySpin(seed, 'sim', nonce, bet);
    returned += spin.grandTotal;
    baseReturned += spin.baseTotal;
    bonusReturned += spin.bonusTotal;
    if (spin.grandTotal > 0) wins++;
    if (spin.bonusTriggered) bonuses++;
    if (spin.grandTotal > maxWin) maxWin = spin.grandTotal;
  }

  const staked = spins * bet;
  return {
    seed: seed.slice(0, 8),
    rtp: (returned / staked) * 100,
    baseRtp: (baseReturned / staked) * 100,
    bonusRtp: (bonusReturned / staked) * 100,
    hitRate: (wins / spins) * 100,
    bonusRate: spins / Math.max(bonuses, 1),
    avgBonusPay: bonusReturned / Math.max(bonuses, 1) / bet,
    maxWinX: maxWin / bet,
  };
}

function main() {
  const { spins, bet, seeds } = parseArgs(process.argv.slice(2));

  console.log(
    `\nAetherfall RTP — ${seeds} seed(s) x ${spins.toLocaleString()} spins at ${bet} coins\n`,
  );

  const runs: Run[] = [];
  for (let i = 0; i < seeds; i++) {
    // Fixed, boring seeds so a run is reproducible and two people comparing
    // numbers are comparing the same thing.
    const seed = `aetherfall-sim-seed-${i}`.padEnd(64, '0');
    const started = Date.now();
    const run = simulate(seed, spins, bet);
    runs.push(run);
    console.log(
      `  seed ${i}  RTP ${run.rtp.toFixed(2)}%` +
        `   base ${run.baseRtp.toFixed(2)}%` +
        `   bonus ${run.bonusRtp.toFixed(2)}%` +
        `   hit ${run.hitRate.toFixed(2)}%` +
        `   bonus 1 in ${Math.round(run.bonusRate)}` +
        `   max ${run.maxWinX.toFixed(0)}x` +
        `   (${((Date.now() - started) / 1000).toFixed(1)}s)`,
    );
  }

  const mean = (pick: (r: Run) => number) => runs.reduce((a, r) => a + pick(r), 0) / runs.length;
  const rtp = mean((r) => r.rtp);
  const low = Math.min(...runs.map((r) => r.rtp));
  const high = Math.max(...runs.map((r) => r.rtp));

  console.log(
    `\n  MEAN RTP        ${rtp.toFixed(2)}%   (spread ${low.toFixed(2)}–${high.toFixed(2)}%)` +
      `\n  house edge      ${(100 - rtp).toFixed(2)}%` +
      `\n  base / bonus    ${mean((r) => r.baseRtp).toFixed(2)}% / ${mean((r) => r.bonusRtp).toFixed(2)}%` +
      `\n  hit rate        ${mean((r) => r.hitRate).toFixed(2)}%` +
      `\n  bonus rate      1 in ${Math.round(mean((r) => r.bonusRate))}` +
      `\n  avg bonus pay   ${mean((r) => r.avgBonusPay).toFixed(1)}x bet\n`,
  );

  if (rtp >= 100) {
    console.error('  ✗ RTP is at or above 100% — the game loses coins on every spin.\n');
    process.exitCode = 1;
  }
}

main();
