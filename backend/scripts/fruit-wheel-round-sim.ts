import { SEGMENTS, rollFromSeed, returnOf, assertBalancedTable } from '../src/services/fruitWheelRound.math';
assertBalancedTable();
const samples = 2_000_000;
const counts: Record<string, number> = Object.fromEntries(SEGMENTS.map(s => [s.key, 0]));
for (let i = 1; i <= samples; i++) counts[rollFromSeed('fruit-wheel-v2-simulation', i)]!++;
console.log(`${samples.toLocaleString('en-US')} committed rounds`);
for (const s of SEGMENTS) {
  if (s.weight === 0) {
    if (counts[s.key] !== 0) throw new Error('Zero-weight outcome was rolled');
    continue;
  }
  const observed = counts[s.key]! / samples;
  const rtp = observed * s.multiplierX10 / 10;
  console.log(`${s.key}: probability ${(observed * 100).toFixed(3)}%, RTP ${(rtp * 100).toFixed(3)}%`);
  if (returnOf(s.key) !== .7 || Math.abs(rtp - .7) > .005) throw new Error('RTP outside tolerance');
}
