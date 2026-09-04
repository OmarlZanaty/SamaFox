/**
 * نيون فورتشن — Neon Fortune RTP simulator.
 *
 * Replays the *shipped* spin math (`computeSpin` + `settleSpin`, the same pure
 * functions the live endpoint and the provably-fair verifier use) over a large
 * number of nonces and reports what the paytable actually returns. Nothing here
 * re-implements the game — move a weight or a payout and the next run measures
 * the new one.
 *
 *   npm run sim:neon-fortune                       # 400k spins, default seeds
 *   npm run sim:neon-fortune -- --spins 1000000    # longer run
 *   npm run sim:neon-fortune -- --bet 1000         # payout rounding at a bigger stake
 *   npm run sim:neon-fortune -- --seeds 5          # more independent seeds
 *
 * Why more than one seed: the Vault of Lights fires about 1 in 1,300 spins and a
 * CITY hit is ~1 in 70 vaults, so a single run can easily draw zero of them. Read
 * the spread across seeds, not any one number.
 *
 * Exits non-zero if total RTP reaches 100%, or if any jackpot pool or reserve
 * ever goes negative — the pools are supposed to be self-funding after the
 * one-time launch seed, and this is what proves it.
 *
 * Importing the service pulls in Prisma, but no query runs — the functions used
 * here are pure, so this never touches the database.
 */

import {
  JACKPOT_TIERS,
  JackpotTier,
  RngStream,
  computeSpin,
  contribute,
  settleSpin,
  simPools,
} from '../src/services/neonFortune.service';

interface Args {
  spins: number;
  bet: number;
  seeds: number;
}

function parseArgs(): Args {
  const argv = process.argv.slice(2);
  const read = (flag: string, fallback: number) => {
    const i = argv.indexOf(flag);
    if (i === -1) return fallback;
    const v = Number(argv[i + 1]);
    return Number.isFinite(v) && v > 0 ? v : fallback;
  };
  return {
    spins: Math.trunc(read('--spins', 400_000)),
    bet: Math.trunc(read('--bet', 100)),
    seeds: Math.trunc(read('--seeds', 3)),
  };
}

interface SeedRun {
  seed: string;
  wagered: number;
  baseReturn: number;
  freeReturn: number;
  vaultReturn: number;
  jackpotReturn: number;
  consolationReturn: number;
  hits: number;
  freeRounds: number;
  vaults: number;
  jackpotHits: Record<JackpotTier, number>;
  contributed: number;
  longestLossStreak: number;
  biggestWin: number;
  poolFloor: number;
}

function runSeed(seedLabel: string, args: Args): SeedRun {
  const pools = simPools();
  const run: SeedRun = {
    seed: seedLabel,
    wagered: 0,
    baseReturn: 0,
    freeReturn: 0,
    vaultReturn: 0,
    jackpotReturn: 0,
    consolationReturn: 0,
    hits: 0,
    freeRounds: 0,
    vaults: 0,
    jackpotHits: { SPARK: 0, GLOW: 0, BEACON: 0, CITY: 0 },
    contributed: 0,
    longestLossStreak: 0,
    biggestWin: 0,
    poolFloor: Infinity,
  };

  let lossStreak = 0;

  for (let nonce = 0; nonce < args.spins; nonce++) {
    const rng = new RngStream(seedLabel, 'sim', nonce);
    const computed = computeSpin(rng, args.bet);
    run.contributed += contribute(pools, args.bet);
    const spin = settleSpin(computed, pools);

    run.wagered += args.bet;
    run.baseReturn += spin.baseWin;
    run.freeReturn += spin.freeSpinsWin;
    run.vaultReturn += spin.vaultWin;

    if (spin.freeSpinsTriggered) run.freeRounds++;
    if (spin.vaultTriggered) {
      run.vaults++;
      const won = spin.vault?.wonTier ?? null;
      if (won) {
        run.jackpotHits[won]++;
        run.jackpotReturn += spin.vaultWin;
      } else {
        run.consolationReturn += spin.vaultWin;
      }
    }

    if (spin.grandTotal > 0) {
      run.hits++;
      lossStreak = 0;
    } else {
      lossStreak++;
      if (lossStreak > run.longestLossStreak) run.longestLossStreak = lossStreak;
    }
    if (spin.grandTotal > run.biggestWin) run.biggestWin = spin.grandTotal;

    for (const tier of JACKPOT_TIERS) {
      run.poolFloor = Math.min(run.poolFloor, pools[tier].pool, pools[tier].reserve);
    }
  }

  return run;
}

const pct = (n: number, d: number) => (d === 0 ? 0 : (n / d) * 100);
const fmt = (n: number) => n.toLocaleString('en-US', { maximumFractionDigits: 2 });

function main() {
  const args = parseArgs();
  console.log('نيون فورتشن — Neon Fortune RTP simulation');
  console.log(`spins/seed: ${fmt(args.spins)}   bet: ${fmt(args.bet)}   seeds: ${args.seeds}\n`);

  const runs: SeedRun[] = [];
  for (let i = 0; i < args.seeds; i++) {
    const label = `seed-${i + 1}`;
    process.stdout.write(`  running ${label}… `);
    const run = runSeed(label, args);
    runs.push(run);
    const total = run.baseReturn + run.freeReturn + run.vaultReturn;
    console.log(`${pct(total, run.wagered).toFixed(2)}%`);
  }

  const sum = <K extends keyof SeedRun>(key: K) =>
    runs.reduce((a, r) => a + (r[key] as number), 0);

  const wagered = sum('wagered');
  const baseReturn = sum('baseReturn');
  const freeReturn = sum('freeReturn');
  const vaultReturn = sum('vaultReturn');
  const jackpotReturn = sum('jackpotReturn');
  const consolationReturn = sum('consolationReturn');
  const totalReturn = baseReturn + freeReturn + vaultReturn;
  const spinsTotal = args.spins * args.seeds;

  const contributed = sum('contributed');
  // Long-run, every contributed coin leaves the pools again, so the steady-state
  // jackpot return *is* the contribution rate. A finite run reads higher than
  // that while the one-time launch seed is still being won out.
  const steadyReturn = baseReturn + freeReturn + consolationReturn + contributed;
  const rtps = runs.map((r) => pct(r.baseReturn + r.freeReturn + r.vaultReturn, r.wagered));
  const poolFloor = Math.min(...runs.map((r) => r.poolFloor));

  console.log('\n── Return ──────────────────────────────────────────────');
  console.log(`  base game            ${pct(baseReturn, wagered).toFixed(2)}%`);
  console.log(`  Skyline Rush         ${pct(freeReturn, wagered).toFixed(2)}%`);
  console.log(`  Vault jackpots       ${pct(jackpotReturn, wagered).toFixed(2)}%`);
  console.log(`  Vault consolation    ${pct(consolationReturn, wagered).toFixed(2)}%`);
  console.log(`  ─────────────────────────────`);
  console.log(`  TOTAL RTP (measured) ${pct(totalReturn, wagered).toFixed(2)}%   (house edge ${(100 - pct(totalReturn, wagered)).toFixed(2)}%)`);
  console.log(`  seed spread          ${Math.min(...rtps).toFixed(2)}% – ${Math.max(...rtps).toFixed(2)}%`);
  console.log(`  jackpot contribution ${pct(contributed, wagered).toFixed(2)}%  (what the pools take in)`);
  console.log(`  STEADY-STATE RTP     ${pct(steadyReturn, wagered).toFixed(2)}%   (house edge ${(100 - pct(steadyReturn, wagered)).toFixed(2)}%)`);
  console.log(`  ↑ the honest long-run number: measured RTP above still contains the one-time launch seed.`);

  console.log('\n── Shape ───────────────────────────────────────────────');
  console.log(`  hit rate             ${pct(sum('hits'), spinsTotal).toFixed(2)}%`);
  console.log(`  average win          ${fmt(totalReturn / spinsTotal)} coins per spin (bet ${fmt(args.bet)})`);
  console.log(`  Skyline Rush         1 in ${fmt(spinsTotal / Math.max(1, sum('freeRounds')))} spins`);
  console.log(`  Vault of Lights      1 in ${fmt(spinsTotal / Math.max(1, sum('vaults')))} spins`);
  for (const tier of JACKPOT_TIERS) {
    const hits = runs.reduce((a, r) => a + r.jackpotHits[tier], 0);
    console.log(
      `  ${tier.padEnd(20)} ${hits === 0 ? 'not hit in this run' : `1 in ${fmt(spinsTotal / hits)} spins (${hits} hits)`}`,
    );
  }
  console.log(`  longest loss streak  ${Math.max(...runs.map((r) => r.longestLossStreak))} spins`);
  console.log(`  biggest single spin  ${fmt(Math.max(...runs.map((r) => r.biggestWin)))} coins (${fmt(Math.max(...runs.map((r) => r.biggestWin)) / args.bet)}× bet)`);
  console.log(`  lowest pool/reserve  ${fmt(poolFloor)} coins`);

  let failed = false;
  const rtp = pct(steadyReturn, wagered);
  if (rtp >= 100) {
    console.error(`\n✗ FAIL: RTP is ${rtp.toFixed(2)}% — the game pays out more than it takes in.`);
    failed = true;
  }
  if (poolFloor < 0) {
    console.error(`\n✗ FAIL: a jackpot pool or reserve went negative (${fmt(poolFloor)}) — the pools are not self-funding.`);
    failed = true;
  }
  if (!failed) {
    console.log(`\n✓ PASS: RTP ${rtp.toFixed(2)}%, pools stayed solvent.`);
  }
  process.exit(failed ? 1 : 0);
}

main();
