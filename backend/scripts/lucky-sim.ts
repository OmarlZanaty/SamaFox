/**
 * هدايا الحظ — dry run of the pool economics, no database.
 *
 *   npx ts-node scripts/lucky-sim.ts [rolls=100000] [giftCoins=100]
 *
 * Plays the default tier table exactly as lucky.service does (same hash →
 * point → tier walk, same pool-eligibility rule) and prints what the client
 * asked to see: how many senders win, what comes back, and — the hard rule —
 * that the pool never dips below zero and the house never pays.
 */
import crypto from 'crypto';
import {
  analyzeTiers,
  luckyHostCoins,
  multiplierAtPoint,
  rollHash,
  rollPointFromHash,
  LUCKY_HOST_SHARE_DEFAULT_BP,
} from '../src/gifts/lucky.service';

const rolls = Number(process.argv[2] ?? 100_000);
const giftCoins = Number(process.argv[3] ?? 100);

// The table the migration seeds.
const tiers = [
  { multiplier: 5, weightBp: 4000, minPoolCoins: 0n },
  { multiplier: 10, weightBp: 2500, minPoolCoins: 0n },
  { multiplier: 20, weightBp: 800, minPoolCoins: 0n },
  { multiplier: 50, weightBp: 200, minPoolCoins: 5000n },
  { multiplier: 100, weightBp: 35, minPoolCoins: 20000n },
  { multiplier: 200, weightBp: 10, minPoolCoins: 60000n },
  { multiplier: 300, weightBp: 4, minPoolCoins: 120000n },
  { multiplier: 500, weightBp: 1, minPoolCoins: 250000n },
];

const hostShareBp = LUCKY_HOST_SHARE_DEFAULT_BP;
const H = luckyHostCoins(giftCoins, hostShareBp);

console.log('table analysis:', analyzeTiers(tiers, hostShareBp));
console.log(`gift=${giftCoins} host=${H} rolls=${rolls}\n`);

let pool = 0n;
let minPool = 0n;
let totalIn = 0n;
let totalOut = 0n;
const hits = new Map<number, number>();
let wins = 0;
let excludedBig = 0;

for (let i = 0; i < rolls; i++) {
  const toPool = BigInt(giftCoins - H);
  pool += toPool;
  totalIn += toPool;
  const eligible = tiers.filter((t) => pool >= t.minPoolCoins && pool >= BigInt(t.multiplier * H));
  if (eligible.length < tiers.length) excludedBig++;
  const seed = crypto.randomBytes(16).toString('hex');
  const m = multiplierAtPoint(rollPointFromHash(rollHash(seed)), eligible);
  const payout = m * H;
  if (payout > 0) {
    if (pool < BigInt(payout)) throw new Error('INVARIANT BROKEN: pool cannot cover payout');
    pool -= BigInt(payout);
    totalOut += BigInt(payout);
    wins++;
  }
  hits.set(m, (hits.get(m) ?? 0) + 1);
  if (pool < minPool) minPool = pool;
}

const spent = BigInt(rolls * giftCoins);
console.log('outcome        count   share');
for (const m of [0, ...tiers.map((t) => t.multiplier)]) {
  const c = hits.get(m) ?? 0;
  console.log(`${m === 0 ? 'lose ' : '×' + String(m).padEnd(4)}   ${String(c).padStart(8)}   ${((100 * c) / rolls).toFixed(2)}%`);
}
console.log(`
senders spent      ${spent}
hosts received     ${BigInt(rolls * H)}  (${((100 * H) / giftCoins).toFixed(1)}%)
senders won back   ${totalOut}  (${Number((10000n * totalOut) / spent) / 100}%)
pool now           ${pool}  (${Number((10000n * pool) / spent) / 100}% of spend, still owned by players)
pool minimum       ${minPool}  ${minPool >= 0n ? '✔ never negative' : '✖ NEGATIVE'}
win rate           ${((100 * wins) / rolls).toFixed(1)}%
rolls with a tier held back by the pool guard: ${excludedBig}
house paid         0 (by construction: every payout is a pool debit)
`);
