import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { ClientHealth, readClientHealth } from '../clientHealth';

const since = Date.parse('2026-10-08T00:00:00Z');
const ev = (o: Record<string, unknown>) => ({
  rx: '2026-10-08T12:00:00Z',
  app: '1.0.47+2055',
  level: 'info',
  kind: 'crumb',
  ...o,
});
const kill = (message: string) => ({
  receivedAt: '2026-10-08T13:00:00Z',
  appVersion: '1.0.47+2055',
  kind: 'processKilled',
  message,
});

test('counts kills, logouts, drops and memory per day and version', () => {
  const h = new ClientHealth(since);
  h.addEvent(ev({ session: 's1', userId: 1, msg: 'mem rss=600MB pss=500 java=10 native=30 gfx=500 code=20' }));
  h.addEvent(ev({ session: 's1', userId: 1, msg: 'mem rss=1200MB pss=900 java=10 native=30 gfx=900 code=20' }));
  h.addEvent(ev({ session: 's2', userId: 2, kind: 'socket', level: 'warn', msg: 'disconnected: ping timeout' }));
  h.addEvent(ev({ session: 's2', userId: 2, kind: 'log', level: 'error', msg: 'Token refresh failed: DioException [bad response]' }));
  h.addEvent(ev({ session: 's2', userId: 2, kind: 'socket', level: 'warn', msg: "connect error: SocketException: Failed host lookup: 'x'" }));
  h.addEvent(ev({ session: 's3', userId: 3, kind: 'uncaught', level: 'error', msg: 'Null check operator used on a null value' }));
  h.addEvent(ev({ rx: '2026-10-01T00:00:00Z', session: 'old', msg: 'before the window' }));
  h.addEvent(ev({ app: '1.0.50+2058', session: 's9', userId: 9, msg: 'app start' }));
  h.addReport(kill('exit LOW_MEMORY while foreground'));
  h.addReport(kill('exit ANR'));
  h.addReport(kill('exit USER_REQUESTED while background'));
  h.addReport(kill('previous session ended without a clean shutdown (OS kill or crash)'));
  h.addReport({ ...kill(''), kind: 'FlutterError' });

  const rows = h.result();
  assert.equal(rows.length, 2);
  const row = rows.find((x) => x.app === '1.0.47+2055')!;
  assert.equal(row.day, '2026-10-08');
  assert.equal(row.sessions, 3);
  assert.equal(row.users, 3);
  assert.deepEqual(row.kills, { lowMemory: 1, anr: 1, signaled: 0, unclean: 1, other: 0 });
  assert.equal(row.forcedLogouts, 1);
  assert.equal(row.socketDrops, 1);
  assert.equal(row.hostLookupFails, 1);
  assert.equal(row.uncaughtErrors, 1, 'logged errors are not crashes');
  assert.equal(row.memSamples, 2);
  assert.equal(row.rssMedian, 1200);
  assert.equal(row.gfxP90, 900);
  assert.equal(rows[0]!.app, '1.0.47+2055', 'busiest version first within a day');
});

test('reads the rotated and the live log, skipping cut lines', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'health-'));
  const events = path.join(dir, 'client-events.log');
  const reports = path.join(dir, 'client-reports.log');
  fs.writeFileSync(`${events}.1`, JSON.stringify(ev({ session: 'a' })) + '\n{"cut mid-');
  fs.writeFileSync(events, JSON.stringify(ev({ session: 'b' })) + '\n');
  fs.writeFileSync(reports, JSON.stringify(kill('exit LOW_MEMORY')) + '\n');
  const rows = await readClientHealth({ events, reports }, since);
  assert.equal(rows[0]!.sessions, 2);
  assert.equal(rows[0]!.kills.lowMemory, 1);
});
