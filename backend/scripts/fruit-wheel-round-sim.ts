import { SEGMENTS, rollFromSeed, returnOf, assertBalancedTable } from '../src/services/fruitWheelRound.math';
assertBalancedTable();
const samples = 2_000_000;
const counts: Record<string, number> = Object.fromEntries(SEGMENTS.map(s => [s.key, 0]));
for (let i = 1; i <= samples; i++) counts[rollFromSeed('fruit-wheel-v2-simulation', i)]!++;
console.log(`${samples.toLocaleString('en-US')} committed rounds`);
for (const s of SEGMENTS) {
  const observed = counts[s.key]! / samples;
  console.log(`${s.key}: probability ${(observed * 100).toFixed(3)}%, RTP ${(observed * s.multiplier * 100).toFixed(3)}%`);
  if (s.key !== 'crown' && Math.abs(observed * s.multiplier - returnOf(s.key)) > .005) throw new Error('RTP outside tolerance');
}
