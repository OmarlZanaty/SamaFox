/**
 * بوابات أوليمبوس — Gates of Olympus RTP simulator.
 *
 * Replays the *shipped* spin math (`verifySpin`, the same pure function the
 * provably-fair endpoint uses) over a large number of nonces and reports what
 * the paytable actually returns. Nothing here re-implements the game — if the
 * weights, the paytable or the multiplier table move, this measures the new
 * ones on the next run.
 *
 *   npm run sim:olympus                       # 300k spins, default seeds
 *   npm run sim:olympus -- --spins 1000000    # longer run
 *   npm run sim:olympus -- --bet 1000         # payout rounding at a bigger stake
 *   npm run sim:olympus -- --seeds 5          # more independent seeds
 *
 * Why more than one seed: free spins fire around 1 in 200 spins and carry a
 * multiplier meter that never resets, so a large share of the return arrives
 * through a thin, heavy tail. A single run can land a point or two off purely
 * on how many good bonuses it drew. Read the spread across seeds, not any one
 * number.
 *
 * Tuning note: every payout is linear in PAYTABLE, so multiplying the whole
 * table by (target / measured) moves RTP by that factor and leaves hit rate,
 * bonus frequency and the shape of the game untouched. Reach for that before
 * touching weights.
 *
 * Note: importing the service pulls in Prisma, but no query runs — `verifySpin`
 * is pure, so this never touches the database.
 */

import {
  verifySpin,
  MIN_BET,
  MAX_BET,
  MAX_WIN_MULTIPLE,
} from '../src/services/olympus.service';

interface Args {
  spins: number;
  bet: number;
  seeds: number;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { spins: 300_000, bet: MIN_BET, seeds: 3 };
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
  freeRtp: number;
  /** How much return the MAX_WIN_MULTIPLE ceiling removed, in RTP points. */
  cappedRtp: number;
  capHits: number;
  hitRate: number;
  multRate: number;
  freeRate: number;
  avgFreePay: number;
  maxWinX: number;
}

function simulate(seed: string, spins: number, bet: number): Run {
  let returned = 0;
  let baseReturned = 0;
  let freeReturned = 0;
  let uncapped = 0;
  let capHits = 0;
  let wins = 0;
  let multWins = 0;
  let bonuses = 0;
  let maxWin = 0;

  for (let nonce = 0; nonce < spins; nonce++) {
    const spin = verifySpin(seed, 'sim', nonce, bet);
    returned += spin.grandTotal;
    baseReturned += spin.baseTotal;
    freeReturned += spin.freeTotal;
    uncapped += spin.uncappedTotal;
    if (spin.capped) capHits++;
    if (spin.grandTotal > 0) wins++;
    if (spin.baseWin > 0 && spin.baseMultiplier > 0) multWins++;
    if (spin.freeTriggered) bonuses++;
    if (spin.grandTotal > maxWin) maxWin = spin.grandTotal;
  }

  const staked = spins * bet;
  return {
    seed: seed.slice(0, 8),
    rtp: (returned / staked) * 100,
    baseRtp: (baseReturned / staked) * 100,
    freeRtp: (freeReturned / staked) * 100,
    cappedRtp: ((uncapped - returned) / staked) * 100,
    capHits,
    hitRate: (wins / spins) * 100,
    multRate: (multWins / spins) * 100,
    freeRate: spins / Math.max(bonuses, 1),
    avgFreePay: freeReturned / Math.max(bonuses, 1) / bet,
    maxWinX: maxWin / bet,
  };
}

// ── Deterministic QA scenarios ───────────────────────────────────────────────
// Nothing here rigs normal play. Because a spin is a pure function of
// (serverSeed, clientSeed, nonce), searching for the first nonce that produces
// each interesting outcome gives QA a reproducible script: set the client seed
// on the account, spin to the listed nonce, and the same thing happens every
// time, on any environment, through the ordinary endpoint.
//
// The list covers every scenario the brief asks QA to be able to reach on
// demand: no win, a single 8-symbol win, several symbols paying at once, a
// three-tumble cascade, multiplier collection, a four-scatter trigger, a
// retrigger, a 100x multiplier and each celebration tier.

type Spin = ReturnType<typeof verifySpin>;

const SCENARIOS: { name: string; hit: (s: Spin) => boolean }[] = [
  { name: 'a plain loss', hit: (s) => s.grandTotal === 0 },
  {
    name: 'one 8-symbol win only',
    hit: (s) =>
      !s.freeTriggered &&
      s.frames.filter((f) => f.wins.length > 0).length === 1 &&
      s.frames[0]!.wins.length === 1 &&
      s.frames[0]!.wins[0]!.count === 8,
  },
  {
    name: 'two symbols paying at once',
    hit: (s) => !s.freeTriggered && s.frames.some((f) => f.wins.length >= 2),
  },
  {
    name: 'a 3+ tumble cascade',
    hit: (s) => !s.freeTriggered && s.frames.filter((f) => f.wins.length > 0).length >= 3,
  },
  {
    name: 'one multiplier on a win',
    hit: (s) => !s.freeTriggered && s.baseWin > 0 && s.baseMultiplier > 0,
  },
  {
    name: 'three multipliers adding up',
    hit: (s) =>
      !s.freeTriggered &&
      s.baseWin > 0 &&
      (s.frames.find((f) => f.sequenceTotal !== undefined)?.multCells.length ?? 0) >= 3,
  },
  { name: 'a 100x+ base multiplier', hit: (s) => !s.freeTriggered && s.baseMultiplier >= 100 },
  { name: 'a four-scatter bonus trigger', hit: (s) => s.freeTriggered },
  { name: 'a bonus retrigger (+5 spins)', hit: (s) => s.freeRetriggers > 0 },
  { name: 'a bonus meter above 50x', hit: (s) => s.freeMultiplier >= 50 },
  { name: 'NICE_WIN', hit: (s) => s.tier === 'NICE_WIN' },
  { name: 'BIG_WIN', hit: (s) => s.tier === 'BIG_WIN' },
  { name: 'MEGA_WIN', hit: (s) => s.tier === 'MEGA_WIN' },
  { name: 'EPIC_WIN', hit: (s) => s.tier === 'EPIC_WIN' },
];

function scenarios(bet: number, limit: number) {
  const serverSeed = 'olympus-qa-server-seed'.padEnd(64, '0');
  const clientSeed = 'qa';
  const pending = new Map(SCENARIOS.map((sc) => [sc.name, sc]));
  const found = new Map<string, { nonce: number; total: number }>();

  for (let nonce = 0; nonce < limit && pending.size > 0; nonce++) {
    const spin = verifySpin(serverSeed, clientSeed, nonce, bet);
    for (const [name, sc] of pending) {
      if (sc.hit(spin)) {
        found.set(name, { nonce, total: spin.grandTotal });
        pending.delete(name);
      }
    }
  }

  console.log(
    `\n  QA scenarios — server seed "${serverSeed.slice(0, 22)}…", client seed "qa", bet ${bet}`,
  );
  for (const sc of SCENARIOS) {
    const f = found.get(sc.name);
    console.log(
      f
        ? `    nonce ${String(f.nonce).padStart(6)}  ${sc.name.padEnd(30)} pays ${f.total}`
        : `    ${'—'.padStart(12)}  ${sc.name.padEnd(30)} not seen in ${limit} spins`,
    );
  }
}

function main() {
  const { spins, bet, seeds } = parseArgs(process.argv.slice(2));

  console.log(
    `\n  بوابات أوليمبوس — Gates of Olympus\n` +
      `  ${spins.toLocaleString()} spins × ${seeds} seed(s) at ${bet} coins ` +
      `(win cap ${MAX_WIN_MULTIPLE}x)\n`,
  );

  const runs: Run[] = [];
  for (let i = 0; i < seeds; i++) {
    // Fixed, boring seeds so a run is reproducible and two people comparing
    // numbers are comparing the same thing.
    const seed = `olympus-sim-seed-${i}`.padEnd(64, '0');
    const started = Date.now();
    const run = simulate(seed, spins, bet);
    runs.push(run);
    console.log(
      `  seed ${i}  RTP ${run.rtp.toFixed(2)}%` +
        `   base ${run.baseRtp.toFixed(2)}%` +
        `   free ${run.freeRtp.toFixed(2)}%` +
        `   hit ${run.hitRate.toFixed(2)}%` +
        `   bonus 1 in ${Math.round(run.freeRate)}` +
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
      `\n  base / free     ${mean((r) => r.baseRtp).toFixed(2)}% / ${mean((r) => r.freeRtp).toFixed(2)}%` +
      `\n  hit rate        ${mean((r) => r.hitRate).toFixed(2)}%` +
      `\n  mult-paid spins ${mean((r) => r.multRate).toFixed(2)}%` +
      `\n  bonus rate      1 in ${Math.round(mean((r) => r.freeRate))}` +
      `\n  avg bonus pay   ${mean((r) => r.avgFreePay).toFixed(1)}x bet` +
      `\n  cap cost        ${mean((r) => r.cappedRtp).toFixed(3)}% RTP over ${runs.reduce((a, r) => a + r.capHits, 0)} capped spin(s)`,
  );

  scenarios(bet, 40_000);

  if (rtp >= 100) {
    console.error('\n  ✗ RTP is at or above 100% — the game loses coins on every spin.\n');
    process.exitCode = 1;
  } else {
    console.log('');
  }
}

main();
