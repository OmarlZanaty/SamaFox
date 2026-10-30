import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

let cup: any;
let gifts: any[];
let balance: number;
let ledger: any[];
let notifications: any[];
let ownerId: number;
const db: any = {
  roomCup: {
    findMany: async ({ where }: any) => cup.roomId === where.roomId && !cup.paidAt && cup.startsAt <= where.startsAt.lte && cup.endsAt > where.endsAt.gt ? [{ ...cup }] : [],
    findUnique: async () => ({ ...cup }),
    updateMany: async ({ where, data }: any) => {
      if (cup.id !== where.id || cup.paidAt !== where.paidAt) return { count: 0 };
      Object.assign(cup, data); return { count: 1 };
    },
  },
  giftTransaction: { aggregate: async ({ where, _sum }: any) => {
    assert.deepEqual(_sum, { totalCoins: true });
    return { _sum: { totalCoins: gifts.filter(g => g.roomId === where.roomId && g.createdAt >= where.createdAt.gte && g.createdAt <= where.createdAt.lte).reduce((n, g) => n + g.totalCoins, 0) } };
  } },
  room: { findUnique: async () => ({ ownerId }) },
  user: { update: async ({ where, data }: any) => { assert.equal(where.id, ownerId); balance += data.coinsBalance.increment; } },
  transaction: { create: async ({ data }: any) => { ledger.push(data); } },
  $executeRaw: async () => 1,
  $transaction: async (fn: any) => fn(db),
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/notification.service', { createNotification: async (data: any) => { notifications.push(data); } });
const { evaluatePerRoomCups }: typeof import('../roomReward.service') = require('../roomReward.service');
beforeEach(() => {
  cup = { id: 1, roomId: 5, targetCoins: 100n, ownerRewardCoins: 20n, startsAt: new Date(Date.now() - 3600000), endsAt: new Date(Date.now() + 3600000), paidAt: null };
  gifts = [{ roomId: 5, totalCoins: 100, createdAt: new Date() }];
  balance = 0; ledger = []; notifications = []; ownerId = 99;
});
test('pays the current owner only once across repeated evaluations', async () => {
  await evaluatePerRoomCups(5);
  await evaluatePerRoomCups(5);
  assert.equal(balance, 20);
  assert.equal(cup.paidToUserId, 99);
  assert.equal(ledger.length, 1);
  assert.equal(ledger[0].type, 'ROOM_CUP_BY_ID_REWARD');
  assert.equal(notifications.length, 1);
});
test('does not pay below target or count gifts outside the cup period or room', async () => {
  gifts[0].totalCoins = 99;
  gifts.push({ roomId: 5, totalCoins: 1000, createdAt: new Date(cup.startsAt.getTime() - 1) }, { roomId: 6, totalCoins: 1000, createdAt: new Date() });
  await evaluatePerRoomCups(5);
  assert.equal(balance, 0); assert.equal(cup.paidAt, null);
});
test('conditional claim prevents duplicate credits from overlapping evaluations', async () => {
  await Promise.all([evaluatePerRoomCups(5), evaluatePerRoomCups(5)]);
  assert.equal(balance, 20);
  assert.equal(ledger.length, 1);
});
test('does not pay before start or more than a minute after end', async () => {
  cup.startsAt = new Date(Date.now() + 60000);
  await evaluatePerRoomCups(5);
  cup.startsAt = new Date(Date.now() - 3600000);
  cup.endsAt = new Date(Date.now() - 61000);
  await evaluatePerRoomCups(5);
  assert.equal(balance, 0); assert.equal(ledger.length, 0);
});
test('allows the one minute grace period and counts only gifts within the window', async () => {
  cup.endsAt = new Date(Date.now() - 10000);
  gifts[0].createdAt = new Date(cup.endsAt.getTime() - 1);
  await evaluatePerRoomCups(5);
  assert.equal(balance, 20);
});
