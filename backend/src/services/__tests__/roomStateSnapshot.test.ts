import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import os from 'os';
import path from 'path';
import {
  applySnapshot,
  buildSnapshot,
  takeSnapshotFile,
  writeSnapshotFile,
  SNAPSHOT_MAX_AGE_MS,
  type RoomStateMaps,
} from '../roomStateSnapshot';

function emptyMaps(): RoomStateMaps {
  return {
    roomSeats: new Map(),
    roomMuted: new Map(),
    roomLockedSeats: new Map(),
    roomAdminMutedSeats: new Map(),
    roomMicQueue: new Map(),
    userCurrentRoom: new Map(),
    hiddenInRoom: new Map(),
  };
}

function liveRoom87(): RoomStateMaps {
  const m = emptyMaps();
  m.userCurrentRoom.set(456, 87).set(335, 87).set(7, 87).set(900, 87).set(12, 60);
  m.roomSeats.set(87, new Map([[12, 456], [1, 335], [2, 7]]));
  m.roomMuted.set(87, new Map([[456, false], [335, true], [7, false], [900, true]]));
  m.roomLockedSeats.set(87, new Set([5]));
  m.roomAdminMutedSeats.set(87, new Set([6]));
  m.roomMicQueue.set(87, [900]);
  m.hiddenInRoom.set(87, new Set([900]));
  return m;
}

test('a restart keeps who sits where and whether their mic is open', () => {
  const snap = JSON.parse(JSON.stringify(buildSnapshot(liveRoom87(), 1_000)));
  const m = emptyMaps();
  const out = applySnapshot(snap, m, 1_000 + 30_000);

  assert.deepEqual(out?.seats, 3);
  assert.deepEqual(new Set(out?.users), new Set([456, 335, 7, 900, 12]));
  assert.deepEqual(Array.from(m.roomSeats.get(87)!.entries()).sort(), [[1, 335], [12, 456], [2, 7]].sort());
  // 100455 (id 456) was unmuted before the deploy and stays unmuted after it.
  assert.equal(m.roomMuted.get(87)!.get(456), false);
  assert.equal(m.roomMuted.get(87)!.get(335), true);
  assert.equal(m.roomMuted.get(87)!.has(900), false, 'no mute flag for someone off the mic');
  assert.deepEqual([...m.roomLockedSeats.get(87)!], [5]);
  assert.deepEqual([...m.roomAdminMutedSeats.get(87)!], [6]);
  assert.deepEqual(m.roomMicQueue.get(87), [900]);
  assert.equal(m.userCurrentRoom.get(12), 60);
  assert.ok(m.hiddenInRoom.get(87)!.has(900), 'a hidden entry stays hidden');
});

test('a stale or foreign snapshot restores nothing', () => {
  const snap = buildSnapshot(liveRoom87(), 1_000);
  assert.equal(applySnapshot(snap, emptyMaps(), 1_000 + SNAPSHOT_MAX_AGE_MS + 1), null);
  assert.equal(applySnapshot({ ...snap, v: 99 }, emptyMaps(), 1_000), null);
  assert.equal(applySnapshot(null, emptyMaps(), 1_000), null);
  assert.equal(applySnapshot('garbage', emptyMaps(), 1_000), null);
});

test('bad rows are skipped, never a seat for someone in another room or a double seat', () => {
  const m = emptyMaps();
  applySnapshot(
    {
      v: 1,
      at: 1_000,
      users: [[1, 10, false], [2, 20, false], ['x', 10, false], [3, 10, false]],
      rooms: [
        {
          rid: 10,
          seats: [[1, 1], [2, 2], [3, 1], [1, 3], [-4, 3], [4, 3]],
          muted: [[1, false]],
          locked: [0, 'a', 2],
          adminMuted: [],
          queue: [2, 3],
        },
        null,
      ],
    },
    m,
    1_000,
  );
  assert.deepEqual(Array.from(m.roomSeats.get(10)!.entries()), [[1, 1], [4, 3]]);
  assert.equal(m.roomMuted.get(10)!.get(1), false);
  assert.equal(m.roomMuted.get(10)!.get(3), true, 'no flag → muted, as a new seat');
  assert.deepEqual([...m.roomLockedSeats.get(10)!], [2]);
  assert.deepEqual(m.roomMicQueue.get(10), [3]);
});

test('the file is written atomically and read only once', () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'roomsnap-')), 'state.json');
  const snap = buildSnapshot(liveRoom87(), 5);
  writeSnapshotFile(snap, file);
  assert.deepEqual(takeSnapshotFile(file), JSON.parse(JSON.stringify(snap)));
  assert.equal(takeSnapshotFile(file), null);
});
