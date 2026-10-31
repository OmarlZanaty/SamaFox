// «مفيش حاجة اسمها غرفه تتكرر، كل حساب ليه غرفه واحده حتي لو اتفتحت 100 مره»
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

type Row = Record<string, any>;
let rooms: Row[] = [];
const db = {
  room: {
    findFirst: async ({ where }: Row) =>
      rooms.filter(r => r.ownerId === where.ownerId && r.roomType === where.roomType)
        .sort((a, b) => Number(b.isActive) - Number(a.isActive) || b.id - a.id)[0] ?? null,
    update: async ({ where, data }: Row) => Object.assign(rooms.find(r => r.id === where.id)!, data),
    create: async ({ data }: Row) => {
      const room = { id: rooms.length + 1, roomType: 'USER', createdAt: new Date(), ...data };
      rooms.push(room);
      return room;
    },
  },
  roomMember: { create: async () => ({}) },
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/notification.service', { createNotification: async () => {} });
const { createRoom }: typeof import('../room.controller') = require('../room.controller');

async function call(userId: number, body: Row) {
  let status = 0;
  let json: Row = {};
  const res: any = { status: (s: number) => { status = s; return res; }, json: (j: Row) => { json = j; return res; } };
  await createRoom({ userId, body } as any, res);
  return { status, json };
}

test('a second create reopens the account\'s room under the new name', async () => {
  rooms = [];
  const first = await call(7, { name: 'فهد' });
  assert.equal(first.status, 201);
  const again = await call(7, { name: 'فهد 2' });
  assert.equal(again.status, 200);
  assert.equal(again.json.id, first.json.id);
  assert.equal(rooms.length, 1);
  assert.equal(rooms[0]!.name, 'فهد 2');
});

test('a closed room is reopened rather than duplicated; a locked name stays', async () => {
  rooms = [{ id: 1, ownerId: 9, roomType: 'USER', isActive: false, name: 'old', nameLocked: true, createdAt: new Date() }];
  const r = await call(9, { name: 'new' });
  assert.equal(r.status, 200);
  assert.equal(rooms.length, 1);
  assert.deepEqual([rooms[0]!.isActive, rooms[0]!.name], [true, 'old']);
});

test('another account still gets its own room', async () => {
  rooms = [{ id: 1, ownerId: 9, roomType: 'USER', isActive: true, name: 'a', createdAt: new Date() }];
  const r = await call(10, { name: 'b' });
  assert.equal(r.status, 201);
  assert.equal(rooms.length, 2);
});
