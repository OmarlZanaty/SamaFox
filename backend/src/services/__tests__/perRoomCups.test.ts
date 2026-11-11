import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

let cup: any;
let gifts: any[];
let balance: number;
let ledger: any[];
let notifications: any[];
let claims: any[];
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
  roomCupClaim: {
    findFirst: async ({ where }: any) => claims.find(c => c.source === where.source && c.refId === where.refId && c.level === where.level) ?? null,
    create: async ({ data }: any) => {
      // The unique (source, refId, level) index.
      if (claims.some(c => c.source === data.source && c.refId === data.refId && c.level === data.level)) throw new Error('unique');
      const row = { id: claims.length + 1, claimedAt: null, ...data }; claims.push(row); return row;
    },
    findMany: async ({ where }: any) => claims.filter(c => c.userId === where.userId && c.roomId === where.roomId && c.claimedAt === null),
    findUnique: async ({ where }: any) => claims.find(c => c.id === where.id) ?? null,
    updateMany: async ({ where, data }: any) => {
      const c = claims.find(x => x.id === where.id && x.claimedAt === where.claimedAt);
      if (!c) return { count: 0 };
      Object.assign(c, data); return { count: 1 };
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
const { evaluatePerRoomCups, claimRoomCupReward, pendingRoomCupClaims }: typeof import('../roomReward.service') = require('../roomReward.service');
beforeEach(() => {
  cup = { id: 1, roomId: 5, targetCoins: 100n, ownerRewardCoins: 20n, levels: [], startsAt: new Date(Date.now() - 3600000), endsAt: new Date(Date.now() + 3600000), paidAt: null };
  gifts = [{ roomId: 5, totalCoins: 100, createdAt: new Date() }];
  balance = 0; ledger = []; notifications = []; claims = []; ownerId = 99;
});
const pendingCoins = () => claims.filter(c => !c.claimedAt).reduce((n, c) => n + Number(c.coins), 0);

test("reaching the cup leaves ONE reward under the owner's name, not in his wallet", async () => {
  await evaluatePerRoomCups(5);
  await evaluatePerRoomCups(5);
  assert.equal(balance, 0);
  assert.equal(claims.length, 1);
  assert.equal(pendingCoins(), 20);
  assert.equal(claims[0].userId, 99);
  assert.equal(cup.paidToUserId, 99);
  assert.equal(notifications.length, 1);
});
test('«استلم» pays the owner once and records it', async () => {
  await evaluatePerRoomCups(5);
  const offer = (await pendingRoomCupClaims(99, 5))[0]!;
  assert.equal(offer.coins, '20');
  assert.deepEqual(await claimRoomCupReward(99, offer.claimId), { coins: 20, roomId: 5 });
  await assert.rejects(claimRoomCupReward(99, offer.claimId), /بالفعل/);
  await assert.rejects(claimRoomCupReward(7, offer.claimId), /غير متاحة/);
  assert.equal(balance, 20);
  assert.equal(ledger.length, 1);
  assert.equal(ledger[0].type, 'ROOM_CUP_BY_ID_REWARD');
  assert.ok(claims[0].claimedAt instanceof Date);
});
test('several levels: each pays only what it adds, the cup closes at the top one', async () => {
  cup.levels = [{ targetCoins: '300', rewardCoins: '50' }, { targetCoins: '100', rewardCoins: '20' }];
  gifts[0].totalCoins = 150;
  await evaluatePerRoomCups(5);
  assert.equal(pendingCoins(), 20);
  assert.equal(cup.paidAt, null);
  gifts.push({ roomId: 5, totalCoins: 200, createdAt: new Date() });
  await evaluatePerRoomCups(5);
  assert.equal(pendingCoins(), 50); // 20 + 30, the top level's total
  assert.equal(claims.length, 2);
  assert.ok(cup.paidAt instanceof Date);
});
test('does not pay below target or count gifts outside the cup period or room', async () => {
  gifts[0].totalCoins = 99;
  gifts.push({ roomId: 5, totalCoins: 1000, createdAt: new Date(cup.startsAt.getTime() - 1) }, { roomId: 6, totalCoins: 1000, createdAt: new Date() });
  await evaluatePerRoomCups(5);
  assert.equal(claims.length, 0); assert.equal(cup.paidAt, null);
});
test('overlapping evaluations grant the reward once', async () => {
  await Promise.all([evaluatePerRoomCups(5), evaluatePerRoomCups(5)]);
  assert.equal(claims.length, 1);
  assert.equal(pendingCoins(), 20);
});
test('does not pay before start or more than a minute after end', async () => {
  cup.startsAt = new Date(Date.now() + 60000);
  await evaluatePerRoomCups(5);
  cup.startsAt = new Date(Date.now() - 3600000);
  cup.endsAt = new Date(Date.now() - 61000);
  await evaluatePerRoomCups(5);
  assert.equal(claims.length, 0);
});
test('allows the one minute grace period and counts only gifts within the window', async () => {
  cup.endsAt = new Date(Date.now() - 10000);
  gifts[0].createdAt = new Date(cup.endsAt.getTime() - 1);
  await evaluatePerRoomCups(5);
  assert.equal(pendingCoins(), 20);
});
