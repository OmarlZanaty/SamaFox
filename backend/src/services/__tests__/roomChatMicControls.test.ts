import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import * as seatLease from '../seatLease';

// Evaluate the real handlers with isolated sockets/DB and no startup timers or services.
// Private maps are exposed only in this test's VM, never in the production API.
function harness() {
  const room = { id: 10, ownerId: 1, maxSeats: 8, isActive: true, chatLocked: false, micRequestRequired: false };
  const blocks = new Set<number>();
  const users = [1, 2, 3, 4].map(id => ({ id, name: `user${id}`, avatarUrl: `/${id}.png`, level: 1 }));
  const emitted: Array<{ target: string; event: string; payload: any }> = [];
  const messages: any[] = [];
  const hidden = new Set<number>();
  const db: any = {
    room: { findUnique: async () => room, update: async ({ data }: any) => Object.assign(room, data) },
    roomChatBlock: {
      findMany: async () => [...blocks].map(userId => ({ userId })),
      upsert: async ({ create }: any) => blocks.add(create.userId),
      deleteMany: async ({ where }: any) => blocks.delete(where.userId),
    },
    roomMember: { findMany: async () => [{ userId: 3, role: 'admin' }], findUnique: async () => null, upsert: async () => ({}) },
    user: {
      findUnique: async ({ where }: any) => users.find(u => u.id === where.id),
      findMany: async ({ where }: any) => where.isSuperAdmin ? [] : users.filter(u => where.id.in.includes(u.id)),
    },
    userItem: { findFirst: async () => null, findMany: async () => [] },
    roomMessage: { create: async ({ data }: any) => { messages.push(data); return { id: 1 }; } },
    roomBan: { findUnique: async () => null },
    roomEntryLog: { create: async () => ({ id: 1 }), update: async () => ({}) },
    giftTransaction: { groupBy: async () => [] },
  };
  const noop = () => {};
  const asyncNoop = async () => {};
  const imports: Record<string, any> = {
    './seatLease': seatLease,
    '../utils/prisma': { __esModule: true, default: db },
    './halalGames.service': { cairoDay: (d = new Date()) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d) },
    './livekitPublishGuard': { liveKitRoomApiFromEnv: noop, createPublishGuard: () => ({ sync: asyncNoop, syncWithin: asyncNoop }) },
    './roomSession.service': { sessionFor: noop, sessionSeat: noop, reconcileRoomSessions: asyncNoop, joinRoomSession: () => ({ id: 'session' }), endRoomSession: noop },
    './gameBroadcast.service': { setGameBroadcastEmitter: noop },
    './gameWinFeed.service': { startGameWinFeed: noop },
    './roomStateSnapshot': { takeSnapshotFile: noop, applySnapshot: noop },
    './vipStyle.service': { nameColorSync: () => null, vipStyleSync: () => ({ nameColor: null, nameGradient: null }) },
    './cpEffect.service': { cpSeatLinks: async () => [] },
    '../controllers/settings.controller': { readSettings: async () => ({}), voiceEngineForRoom: () => 'mesh' },
    './broadcast.service': { startBroadcast: asyncNoop, endBroadcast: asyncNoop },
    './features.service': { isFeatureOn: async (uid: number) => hidden.has(uid), hasFeature: async () => false },
    './roomShare.service': { shareInviter: async () => null },
  };
  const sockets = new Map<string, any>();
  const rooms = new Map<string, Set<string>>();
  let connection: (socket: any) => void = noop;
  const io: any = {
    sockets: { sockets, adapter: { rooms, broadcast: noop } },
    use: noop,
    on: (event: string, fn: any) => { if (event === 'connection') connection = fn; },
    emit: (event: string, payload: any) => emitted.push({ target: '*', event, payload }),
    to: (target: string) => ({ emit: (event: string, payload: any) => emitted.push({ target, event, payload }) }),
    in: (target: string) => ({ fetchSockets: async () => [...(rooms.get(target) ?? [])].map(id => sockets.get(id)) }),
  };
  const source = readFileSync(resolve(__dirname, '../socket.service.ts'), 'utf8') + `
    exports.state = { userCurrentRoom, hiddenInRoom, getSeats, getQueue, micApprovals, roomTopSupporters, cairoDayStart };
  `;
  const compiled = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true } }).outputText;
  const exports: any = {};
  const timers: Array<{ fn: () => any; delay: number }> = [];
  runInNewContext(compiled, {
    exports, require: (id: string) => imports[id] ?? {},
    console: { log: noop, warn: noop, error: (...args: any[]) => { throw new Error(args.map(String).join(' ')); } },
    process: { env: {}, once: noop },
    setTimeout: (fn: () => any, delay: number) => { timers.push({ fn, delay }); return { unref: noop }; },
    clearTimeout: noop, setInterval: () => ({ unref: noop }),
  });
  exports.initializeSocketHandlers(io);
  function connect(uid: number, admitted = true) {
    const handlers = new Map<string, (payload: any) => any>();
    const id = `socket-${sockets.size}`;
    const socket: any = {
      id, userId: uid, connected: true, data: { userId: uid }, rooms: new Set<string>(),
      on: (event: string, fn: any) => handlers.set(event, fn),
      conn: { on: noop },
      emit: (event: string, payload: any) => emitted.push({ target: id, event, payload }),
      join: (target: string) => { socket.rooms.add(target); if (!rooms.has(target)) rooms.set(target, new Set()); rooms.get(target)!.add(id); },
      leave: (target: string) => { socket.rooms.delete(target); rooms.get(target)?.delete(id); },
      to: io.to,
    };
    sockets.set(id, socket);
    connection(socket);
    if (admitted) { socket.join('room:10'); exports.state.userCurrentRoom.set(uid, 10); }
    return { socket, fire: async (event: string, payload: any) => { await handlers.get(event)!(payload); } };
  }
  return { ...exports, io, connect, emitted, messages, room, blocks, hidden, db, timers };
}

const payloads = (h: any, event: string) => h.emitted.filter((e: any) => e.event === event).map((e: any) => e.payload);

test('presence counts distinct connected listeners and speakers, excluding hidden/stale/foreign sockets', () => {
  const h = harness();
  h.connect(1); h.connect(1); h.connect(2); h.connect(3);
  const stale = h.connect(4);
  stale.socket.connected = false;
  h.state.hiddenInRoom.set(10, new Set([2]));
  h.state.getSeats(10).set(1, 1);
  assert.equal(h.visibleRoomCount(10), 2);
  assert.equal(h.getLiveRoomCounts().get(10), 2);
  h.state.userCurrentRoom.set(3, 20);
  assert.equal(h.visibleRoomCount(10), 1);
});

test('hidden join sends private state without a room broadcast or visible count change', async () => {
  const h = harness(); h.connect(1);
  const entrant = h.connect(2, false); h.hidden.add(2);
  h.emitted.length = 0;
  await entrant.fire('join_room', { roomId: 10 });
  assert.equal(h.visibleRoomCount(10), 1);
  assert.equal(h.emitted.filter((e: any) => e.target === 'room:10').length, 0);
  const state = payloads(h, 'room_seats_state')[0];
  assert.equal(state.chatLocked, false);
  assert.equal(state.micRequestRequired, false);
  assert.equal(state.chatBlockedUserIds.length, 0);
  assert.equal(state.topSupporters.length, 0);
  assert.equal(payloads(h, 'room_users')[0].users.length, 1);
});

test('chat lock rejects members, exempts owner/admin; per-user block survives unlock', async () => {
  const h = harness(); const owner = h.connect(1); const member = h.connect(2); const admin = h.connect(3);
  await member.fire('room_set_chat_lock', { roomId: 10, locked: true });
  assert.equal(h.room.chatLocked, false);
  await owner.fire('room_set_chat_lock', { roomId: 10, locked: true });
  await member.fire('send_message', { roomId: 10, message: 'hello' });
  assert.equal(payloads(h, 'room_message_rejected').at(-1).code, 'CHAT_LOCKED');
  assert.equal(h.messages.length, 0);
  await owner.fire('send_message', { roomId: 10, message: 'owner' });
  await admin.fire('send_message', { roomId: 10, message: 'admin' });
  assert.equal(h.messages.length, 2);
  await admin.fire('room_chat_block', { roomId: 10, userId: 2, blocked: true });
  await owner.fire('room_set_chat_lock', { roomId: 10, locked: false });
  await member.fire('send_message', { roomId: 10, message: 'blocked' });
  assert.equal(payloads(h, 'room_message_rejected').at(-1).code, 'CHAT_BLOCKED');
  await admin.fire('room_chat_block', { roomId: 10, userId: 2, blocked: false });
  await member.fire('send_message', { roomId: 10, message: 'allowed' });
  assert.equal(h.messages.length, 3);
});

test('request mode blocks take_seat until approval; rejection requires another request', async () => {
  const h = harness(); const owner = h.connect(1); const member = h.connect(2);
  await owner.fire('room_set_mic_request_mode', { roomId: 10, required: true });
  await member.fire('take_seat', { roomId: 10, seatNumber: 1 });
  assert.equal(payloads(h, 'seat_error').at(-1).code, 'MIC_REQUEST_REQUIRED');
  assert.equal(h.state.getSeats(10).size, 0);
  await member.fire('request_mic', { roomId: 10 });
  await new Promise(r => setImmediate(r)); // the queue broadcast resolves names asynchronously
  assert.equal(payloads(h, 'mic_queue_updated').at(-1).entries[0].name, 'user2');
  await owner.fire('reject_mic', { roomId: 10, userId: 2 });
  await owner.fire('approve_mic', { roomId: 10, userId: 2 });
  assert.equal(h.state.getSeats(10).size, 0);
  await member.fire('request_mic', { roomId: 10 });
  await owner.fire('approve_mic', { roomId: 10, userId: 2 });
  assert.equal(h.state.getSeats(10).get(1), 2);
  h.state.getSeats(10).delete(1);
  await member.fire('take_seat', { roomId: 10, seatNumber: 1 });
  assert.equal(h.state.getSeats(10).size, 0, 'approval was consumed');
});

test('approval with no available seat grants one later take_seat', async () => {
  const h = harness(); const owner = h.connect(1); const member = h.connect(2);
  h.room.micRequestRequired = true; h.room.maxSeats = 1;
  h.state.getSeats(10).set(1, 1);
  await member.fire('request_mic', { roomId: 10 });
  await owner.fire('approve_mic', { roomId: 10, userId: 2 });
  h.state.getSeats(10).delete(1);
  await member.fire('take_seat', { roomId: 10, seatNumber: 1 });
  assert.equal(h.state.getSeats(10).get(1), 2);
  assert.equal(h.state.micApprovals.get(10).has(2), false);
});

test('only an accepted invitation bypasses request mode, once', async () => {
  const h = harness(); const owner = h.connect(1); const member = h.connect(2);
  h.room.micRequestRequired = true;
  await owner.fire('invite_to_seat', { roomId: 10, targetUserId: 2, seatNumber: 2 });
  const inviteId = payloads(h, 'seat_invite').at(-1).inviteId;
  await member.fire('take_seat', { roomId: 10, seatNumber: 2 });
  assert.equal(h.state.getSeats(10).size, 0, 'pending invitation is not consent');
  await member.fire('seat_invite_response', { inviteId, accept: true });
  assert.equal(h.state.getSeats(10).get(2), 2);
  h.state.getSeats(10).delete(2);
  await member.fire('take_seat', { roomId: 10, seatNumber: 2 });
  assert.equal(h.state.getSeats(10).size, 0);
});

test('supporters aggregate Cairo-day sender spending, including hidden senders', async () => {
  const h = harness(); h.state.hiddenInRoom.set(10, new Set([2]));
  let query: any;
  h.db.giftTransaction.groupBy = async (args: any) => { query = args; return [{ senderId: 2, _sum: { paidCoins: 500 } }]; };
  const items = await h.state.roomTopSupporters(10);
  assert.equal(items[0].userId, 2);
  assert.equal(items[0].amount, 500);
  assert.equal(query.take, 2);
  assert.equal(query.by[0], 'senderId');
  assert.equal(query.where.roomId, 10);
  assert.equal(h.state.cairoDayStart(new Date('2026-01-10T12:00:00Z')).toISOString(), '2026-01-09T22:00:00.000Z');
});
