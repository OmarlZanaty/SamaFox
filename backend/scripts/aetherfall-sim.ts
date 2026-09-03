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

// ── Deterministic QA scenarios ───────────────────────────────────────────────
// Nothing here rigs normal play. Because a spin is a pure function of
// (serverSeed, clientSeed, nonce), searching for the first nonce that produces
// each interesting outcome gives QA a reproducible script: set the client seed
// on the account, then spin to the listed nonce and the same thing happens every
// time, on any environment, through the ordinary endpoint.

const SCENARIOS: { name: string; hit: (s: ReturnType<typeof verifySpin>) => boolean }[] = [
  { name: 'a plain loss', hit: (s) => s.grandTotal === 0 },
  { name: 'one tumble, then nothing', hit: (s) => s.frames.filter((f) => f.wins.length > 0).length === 1 && !s.bonusTriggered },
  { name: 'a 3+ tumble cascade', hit: (s) => s.frames.filter((f) => f.wins.length > 0).length >= 3 && !s.bonusTriggered },
  { name: 'an Ember Charge resolution', hit: (s) => s.baseCharge > 0 && s.baseWin > 0 && !s.bonusTriggered },
  { name: 'a Skyfire Vault trigger', hit: (s) => s.bonusTriggered },
  { name: 'a Constellation Lock pinning cells', hit: (s) => s.frames.some((f) => (f.lockedCells?.length ?? 0) > 0) },
  { name: 'a Starburst Tumble', hit: (s) => s.frames.some((f) => f.isStarburst === true) },
  { name: 'BRIGHT_HIT', hit: (s) => s.tier === 'BRIGHT_HIT' },
  { name: 'SKYFIRE_SURGE', hit: (s) => s.tier === 'SKYFIRE_SURGE' },
  { name: 'CELESTIAL_BREAK', hit: (s) => s.tier === 'CELESTIAL_BREAK' },
  { name: 'AETHERFALL', hit: (s) => s.tier === 'AETHERFALL' },
];

function scenarios(bet: number, limit: number) {
  const serverSeed = 'aetherfall-qa-server-seed'.padEnd(64, '0');
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

  console.log(`\nDeterministic QA scenarios — bet ${bet}`);
  console.log(`  server seed : ${serverSeed}`);
  console.log(`  client seed : ${clientSeed}   (set this on the test account)\n`);
  for (const sc of SCENARIOS) {
    const f = found.get(sc.name);
    console.log(
      f
        ? `  nonce ${String(f.nonce).padStart(6)}  ${sc.name.padEnd(34)} pays ${f.total}`
        : `  ${'not found'.padStart(12)}  ${sc.name.padEnd(34)} within ${limit} spins`,
    );
  }
  console.log(
    '\n  Reproduce with:\n' +
      '    POST /api/v1/games/aetherfall/verify\n' +
      `    { "serverSeed": "${serverSeed}",\n` +
      `      "clientSeed": "${clientSeed}", "nonce": <above>, "bet": ${bet} }\n\n` +
      '  That returns the identical fully-resolved spin — same grid, same cascade,\n' +
      '  same payout — every time and on every environment, because a spin is a\n' +
      '  pure function of the seed pair and the nonce.\n\n' +
      '  Note this replays through the verification endpoint, not live play: the\n' +
      '  server seed on a real account is generated server-side and cannot be set,\n' +
      '  which is exactly the property that makes the commitment worth anything.\n' +
      '  Nothing here is a debug path into normal play, and normal play is never\n' +
      '  rigged.\n',
  );
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--scenarios')) {
    const { bet, spins } = parseArgs(argv);
    return scenarios(bet, Math.max(spins, 200_000));
  }

  const { spins, bet, seeds } = parseArgs(argv);

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
