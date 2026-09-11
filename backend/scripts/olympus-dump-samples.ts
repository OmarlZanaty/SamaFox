/**
 * Dumps a few fully-resolved بوابات أوليمبوس spins to JSON, for the Flutter
 * client's parser test to read.
 *
 * These are fixed nonces on a fixed seed pair — the same ones the simulator
 * reports as its QA scenarios — so the fixture only changes when the game's
 * math deliberately changes, and the Dart test will notice if it does.
 *
 *   npx ts-node --transpile-only scripts/olympus-dump-samples.ts
 */

import fs from 'fs';
import path from 'path';
import { verifySpin } from '../src/services/olympus.service';

const SERVER_SEED = 'olympus-qa-server-seed'.padEnd(64, '0');
const CLIENT_SEED = 'qa';
const BET = 20;

/** One payload per shape the client has to survive. */
const CASES: [string, number][] = [
  ['plain_loss', 0],
  ['three_mults', 236],
  ['bonus_retrigger', 2598],
  ['epic_win', 948],
];

const out: Record<string, unknown> = {
  _meta: { serverSeed: SERVER_SEED, clientSeed: CLIENT_SEED, bet: BET },
};
for (const [name, nonce] of CASES) {
  out[name] = { nonce, spin: verifySpin(SERVER_SEED, CLIENT_SEED, nonce, BET) };
}

const dest = path.join(process.cwd(), '..', 'app', 'test', 'olympus_spin_samples.json');
fs.writeFileSync(dest, JSON.stringify(out, null, 1));
console.log('wrote', dest);
