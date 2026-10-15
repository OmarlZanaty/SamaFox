import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TrackType } from 'livekit-server-sdk';
import { createPublishGuard, type LiveKitRoomApi } from '../livekitPublishGuard';

type P = { identity: string; canPublish?: boolean; audio?: boolean };

function fakeApi(rooms: Record<string, P[]>) {
  const updates: Array<{ room: string; identity: string; canPublish: boolean }> = [];
  const api: LiveKitRoomApi = {
    async listRooms() {
      return Object.keys(rooms).map((name) => ({ name }));
    },
    async listParticipants(room) {
      if (!rooms[room]) throw new Error('requested room does not exist');
      return rooms[room].map((p) => ({
        identity: p.identity,
        permission: p.canPublish === undefined ? undefined : { canPublish: p.canPublish },
        tracks: p.audio ? [{ type: TrackType.AUDIO }] : [],
      })) as any;
    },
    async updateParticipant(room, identity, { permission }) {
      updates.push({ room, identity, canPublish: permission.canPublish });
      const p = rooms[room]!.find((x) => x.identity === identity)!;
      p.canPublish = permission.canPublish;
      if (!permission.canPublish) p.audio = false;
      assert.equal(permission.canSubscribe, true);
      assert.equal(permission.canPublishData, false);
      return {};
    },
  };
  return { api, updates };
}

function guardFor(api: LiveKitRoomApi, seats: Record<number, number[]>, livekit = true) {
  return createPublishGuard({
    api,
    seatedUserIds: (rid) => new Set(seats[rid] ?? []),
    isLiveKitRoom: () => livekit,
    log: () => {},
  });
}

test('an unseated user publishing audio loses canPublish', async () => {
  const { api, updates } = fakeApi({
    'room-7': [
      { identity: '1', canPublish: true, audio: true }, // seated speaker
      { identity: '666', canPublish: true, audio: true }, // talking, no seat
      { identity: '9', canPublish: true, audio: false }, // plain listener
    ],
  });
  await guardFor(api, { 7: [1] }).sync(7);
  assert.deepEqual(updates, [{ room: 'room-7', identity: '666', canPublish: false }]);
});

test('a seated user who lost canPublish gets it back', async () => {
  const { api, updates } = fakeApi({ 'room-7': [{ identity: '5', canPublish: false }] });
  await guardFor(api, { 7: [5] }).sync(7);
  assert.deepEqual(updates, [{ room: 'room-7', identity: '5', canPublish: true }]);
});

test('listeners and mesh rooms are left alone', async () => {
  const { api, updates } = fakeApi({ 'room-7': [{ identity: '9', canPublish: true }, { identity: '3', audio: true }] });
  await guardFor(api, { 7: [] }, false).sync(7);
  assert.deepEqual(updates, []);
});

test('a room missing on the SFU is not an error', async () => {
  const { api, updates } = fakeApi({});
  await guardFor(api, { 7: [1] }).sync(7);
  assert.deepEqual(updates, []);
});

test('seat state is read when the sync runs, not when it is queued', async () => {
  const { api, updates } = fakeApi({ 'room-7': [{ identity: '4', canPublish: true, audio: true }] });
  const seats: Record<number, number[]> = { 7: [] };
  const guard = guardFor(api, seats);
  const first = guard.sync(7);
  const second = guard.sync(7);
  seats[7] = [4]; // took a seat before either ran
  await Promise.all([first, second]);
  assert.deepEqual(updates, []);
});

test('sweep covers every room-<id> on the SFU', async () => {
  const { api, updates } = fakeApi({
    'room-1': [{ identity: '10', canPublish: true, audio: true }],
    'room-2': [{ identity: '20', canPublish: true, audio: true }],
    'other': [{ identity: '30', canPublish: true, audio: true }],
  });
  await guardFor(api, { 1: [10] }).sweep();
  assert.deepEqual(updates, [{ room: 'room-2', identity: '20', canPublish: false }]);
});

test('no API configured: nothing happens', async () => {
  const guard = createPublishGuard({ api: null, seatedUserIds: () => new Set(), isLiveKitRoom: () => true });
  await guard.sync(1);
  await guard.sweep();
});
