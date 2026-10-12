import test, { beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

// إزالة غرفة من الرائج: hidden rooms leave the list (not their owner's) and
// come back when the owner opens them.
const settings = new Map<string, string>();
const rooms = [1, 2, 3].map((id) => ({ id, ownerId: id * 10, createdAt: new Date(2026, 0, id), owner: { displayId: id * 100 } }));
const db: any = {
  appSetting: {
    findUnique: async ({ where }: any) => (settings.has(where.key) ? { key: where.key, value: settings.get(where.key) } : null),
    upsert: async ({ where, update }: any) => { settings.set(where.key, update.value); },
  },
  room: { findMany: async () => rooms.map((r) => ({ ...r })) },
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/socket.service', { getLiveRoomCounts: () => new Map() });
const ranking: typeof import('../roomRanking.service') = require('../roomRanking.service');

beforeEach(() => { settings.clear(); ranking.invalidateHiddenRooms(); ranking.invalidateRoomPins(); });

test('a hidden room is left out of the list for everyone but its owner', async () => {
  await ranking.setHiddenRooms([2]);
  assert.deepEqual((await ranking.rankedRoomIds({}, 0)).ids.sort(), [1, 3]);
  assert.deepEqual((await ranking.rankedRoomIds({}, 0, 99)).ids.sort(), [1, 3]);
  assert.deepEqual((await ranking.rankedRoomIds({}, 0, 20)).ids.sort(), [1, 2, 3]);
});
test('the owner opening it puts it back; unhiding a visible room changes nothing', async () => {
  await ranking.setHiddenRooms([2, 3]);
  assert.equal(await ranking.unhideRoom(2), true);
  assert.equal(await ranking.unhideRoom(2), false);
  assert.deepEqual(await ranking.getHiddenRooms(), [3]);
  assert.deepEqual((await ranking.rankedRoomIds({}, 0)).ids.sort(), [1, 2]);
});
test('a broken setting hides nothing', async () => {
  settings.set(ranking.ROOM_HIDDEN_KEY, '{oops');
  assert.deepEqual(await ranking.getHiddenRooms(), []);
});
