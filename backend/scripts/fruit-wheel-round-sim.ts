import { SEGMENTS, TOTAL_WEIGHT, rollFromSeed, returnOf, assertBalancedTable } from '../src/services/fruitWheelRound.math';
assertBalancedTable();
const samples = 2_000_000;
const counts: Record<string, number> = Object.fromEntries(SEGMENTS.map(s => [s.key, 0]));
for (let i = 1; i <= samples; i++) counts[rollFromSeed('fruit-wheel-v2-simulation', i)]!++;
console.log(`${samples.toLocaleString('en-US')} committed rounds`);
for (const s of SEGMENTS) {
  const observed = counts[s.key]! / samples;
  const expected = s.weight / TOTAL_WEIGHT;
  const rtp = observed * s.multiplierX10 / 10;
  console.log(`${s.key}: probability ${(observed * 100).toFixed(3)}%, RTP ${(rtp * 100).toFixed(3)}%`);
  if (Math.abs(observed - expected) > .002) throw new Error(`${s.key}: probability outside tolerance`);
  if (s.key === 'crown') {
    if (counts.crown === 0 || rtp !== 0) throw new Error('Crown must be reachable and pay nothing');
    continue;
  }
  if (returnOf(s.key) !== .7 || Math.abs(rtp - .7) > .005) throw new Error('RTP outside tolerance');
}
