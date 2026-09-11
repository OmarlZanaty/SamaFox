/**
 * أستيريون — Citadel of Asterion RTP simulator.
 *
 * Replays the *shipped* spin math (`verifySpin`, the same pure function the
 * provably-fair endpoint uses) over a large number of nonces and reports what
 * the paytable actually returns. Nothing here re-implements the game — if the
 * weights, the paytable or the orb table move, this measures the new ones on
 * the next run.
 *
 *   npm run sim:asterion                       # 300k spins, default seeds
 *   npm run sim:asterion -- --spins 1000000    # longer run
 *   npm run sim:asterion -- --bet 1000         # payout rounding at a bigger stake
 *   npm run sim:asterion -- --seeds 5          # more independent seeds
 *
 * Why more than one seed: the Skyfall Trials fire around 1 in 250 spins and
 * carry a multiplier meter that never resets, so a large share of the return
 * arrives through a thin, heavy tail. A single run can land a point or two off
 * purely on how many good trials it drew. Read the spread across seeds, not any
 * one number.
 *
 * Note: importing the service pulls in Prisma, but no query runs — `verifySpin`
 * is pure, so this never touches the database.
 */

import {
  verifySpin,
  MIN_BET,
  MAX_BET,
  MAX_WIN_MULTIPLE,
} from '../src/services/asterion.service';

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
  trialRtp: number;
  /** How much return the MAX_WIN_MULTIPLE ceiling removed, in RTP points. */
  cappedRtp: number;
  capHits: number;
  hitRate: number;
  orbRate: number;
  trialRate: number;
  avgTrialPay: number;
  maxWinX: number;
}

function simulate(seed: string, spins: number, bet: number): Run {
  let returned = 0;
  let baseReturned = 0;
  let trialReturned = 0;
  let uncapped = 0;
  let capHits = 0;
  let wins = 0;
  let orbWins = 0;
  let trials = 0;
  let maxWin = 0;

  for (let nonce = 0; nonce < spins; nonce++) {
    const spin = verifySpin(seed, 'sim', nonce, bet);
    returned += spin.grandTotal;
    baseReturned += spin.baseTotal;
    trialReturned += spin.trialTotal;
    uncapped += spin.uncappedTotal;
    if (spin.capped) capHits++;
    if (spin.grandTotal > 0) wins++;
    if (spin.baseWin > 0 && spin.baseMultiplier > 0) orbWins++;
    if (spin.trialTriggered) trials++;
    if (spin.grandTotal > maxWin) maxWin = spin.grandTotal;
  }

  const staked = spins * bet;
  return {
    seed: seed.slice(0, 8),
    rtp: (returned / staked) * 100,
    baseRtp: (baseReturned / staked) * 100,
    trialRtp: (trialReturned / staked) * 100,
    cappedRtp: ((uncapped - returned) / staked) * 100,
    capHits,
    hitRate: (wins / spins) * 100,
    orbRate: (orbWins / spins) * 100,
    trialRate: spins / Math.max(trials, 1),
    avgTrialPay: trialReturned / Math.max(trials, 1) / bet,
    maxWinX: maxWin / bet,
  };
}

// ── Deterministic QA scenarios ───────────────────────────────────────────────
// Nothing here rigs normal play. Because a spin is a pure function of
// (serverSeed, clientSeed, nonce), searching for the first nonce that produces
// each interesting outcome gives QA a reproducible script: set the client seed
// on the account, spin to the listed nonce, and the same thing happens every
// time, on any environment, through the ordinary endpoint.

type Spin = ReturnType<typeof verifySpin>;

const SCENARIOS: { name: string; hit: (s: Spin) => boolean }[] = [
  { name: 'a plain loss', hit: (s) => s.grandTotal === 0 },
  {
    name: 'one tumble, then nothing',
    hit: (s) => s.frames.filter((f) => f.wins.length > 0).length === 1 && !s.trialTriggered,
  },
  {
    name: 'a 3+ tumble cascade',
    hit: (s) => s.frames.filter((f) => f.wins.length > 0).length >= 3 && !s.trialTriggered,
  },
  { name: 'one orb multiplying a win', hit: (s) => s.baseWin > 0 && s.initialOrbs.length >= 0 && s.baseMultiplier > 0 && !s.trialTriggered },
  {
    name: 'three or more orbs adding up',
    hit: (s) =>
      s.baseWin > 0 &&
      !s.trialTriggered &&
      (s.frames.find((f) => f.sequenceTotal !== undefined)?.orbCells.length ?? 0) >= 3,
  },
  { name: 'a Skyfall Trials trigger', hit: (s) => s.trialTriggered },
  { name: 'a trial retrigger (+5 spins)', hit: (s) => s.trialRetriggers > 0 },
  { name: 'a trial meter above 50x', hit: (s) => s.trialMultiplier >= 50 },
  { name: 'NICE_WIN', hit: (s) => s.tier === 'NICE_WIN' },
  { name: 'GREAT_SURGE', hit: (s) => s.tier === 'GREAT_SURGE' },
  { name: 'EPIC_STORM', hit: (s) => s.tier === 'EPIC_STORM' },
  { name: 'DIVINE_SURGE', hit: (s) => s.tier === 'DIVINE_SURGE' },
];

function scenarios(bet: number, limit: number) {
  const serverSeed = 'asterion-qa-server-seed'.padEnd(64, '0');
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

  console.log(`\n  QA scenarios — server seed "${serverSeed.slice(0, 23)}…", client seed "qa", bet ${bet}`);
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
    `\n  أستيريون — Citadel of Asterion\n` +
      `  ${spins.toLocaleString()} spins × ${seeds} seed(s) at ${bet} coins ` +
      `(win cap ${MAX_WIN_MULTIPLE}x)\n`,
  );

  const runs: Run[] = [];
  for (let i = 0; i < seeds; i++) {
    // Fixed, boring seeds so a run is reproducible and two people comparing
    // numbers are comparing the same thing.
    const seed = `asterion-sim-seed-${i}`.padEnd(64, '0');
    const started = Date.now();
    const run = simulate(seed, spins, bet);
    runs.push(run);
    console.log(
      `  seed ${i}  RTP ${run.rtp.toFixed(2)}%` +
        `   base ${run.baseRtp.toFixed(2)}%` +
        `   trial ${run.trialRtp.toFixed(2)}%` +
        `   hit ${run.hitRate.toFixed(2)}%` +
        `   trial 1 in ${Math.round(run.trialRate)}` +
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
      `\n  base / trial    ${mean((r) => r.baseRtp).toFixed(2)}% / ${mean((r) => r.trialRtp).toFixed(2)}%` +
      `\n  hit rate        ${mean((r) => r.hitRate).toFixed(2)}%` +
      `\n  orb-paid spins  ${mean((r) => r.orbRate).toFixed(2)}%` +
      `\n  trial rate      1 in ${Math.round(mean((r) => r.trialRate))}` +
      `\n  avg trial pay   ${mean((r) => r.avgTrialPay).toFixed(1)}x bet` +
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
