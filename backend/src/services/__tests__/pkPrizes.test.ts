import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

let state: any;
let events: any[];
const db: any = {
  $transaction: async (work: any) => {
    const before = structuredClone(state);
    try { return await work(db); } catch (error) { state = before; throw error; }
  },
  pkBattle: {
    findUnique: async () => ({ ...state.pk }),
    updateMany: async ({ where, data }: any) => {
      if (state.pk.status !== where.status) return { count: 0 };
      Object.assign(state.pk, data); return { count: 1 };
    },
    update: async ({ data }: any) => Object.assign(state.pk, data),
  },
  pkRoomLock: { deleteMany: async () => ({}), findUnique: async () => ({ pk: state.pk }) },
  pkPrizeBox: {
    create: async ({ data }: any) => (state.box = data),
    findUnique: async () => state.box,
  },
  pkClaim: {
    findUnique: async ({ where }: any) => state.claims.find((c: any) => c.pkId === where.pkId_userId.pkId && c.userId === where.pkId_userId.userId),
    create: async ({ data }: any) => { state.claims.push(data); return data; },
  },
  user: {
    findUniqueOrThrow: async ({ where }: any) => ({ coinsBalance: state.users[where.id] || 0, name: 'Winner', avatarUrl: 'avatar.png' }),
    update: async ({ where, data }: any) => { state.users[where.id] = (state.users[where.id] || 0) + data.coinsBalance.increment; },
  },
  userItem: {
    findUnique: async () => null,
    upsert: async ({ create }: any) => { state.items.push(create); return create; },
  },
  economyAccount: {
    findUnique: async ({ where }: any) => ({ balance: state.accounts[where.key] || 0n }),
    updateMany: async ({ where, data }: any) => {
      assert.equal(where.balance.gte, data.balance.decrement);
      if ((state.accounts[where.key] || 0n) < where.balance.gte) return { count: 0 };
      state.accounts[where.key] -= data.balance.decrement; return { count: 1 };
    },
    upsert: async ({ where, update }: any) => {
      state.accounts[where.key] = (state.accounts[where.key] || 0n) + update.balance.increment;
      return { balance: state.accounts[where.key] };
    },
  },
  economyLedger: { create: async ({ data }: any) => { state.ledger.push(data); } },
  roomGiftJob: { findUnique: async () => ({ processedAt: null }), update: async () => ({}) },
  giftTransaction: { findUnique: async () => state.gift },
  $executeRawUnsafe: async () => 1,
  rocketEvent: { updateMany: async () => ({}), findFirst: async () => null },
  rocketConfig: { findFirst: async () => null },
  pkContribution: { findUnique: async () => null, create: async ({ data }: any) => { state.contributions.push(data); } },
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/adminAudit.service', { recordAdminAuditStrict: async (_tx: any, data: any) => { state.audits.push(data); } });
stub('services/socket.service', {
  emitGlobal: (event: string, payload: any) => events.push({ event, payload }),
  emitToRoomAndUsers: (roomId: number, _users: any, event: string, payload: any) => events.push({ roomId, event, payload }),
});
const { finishPk, claimPk, processRoomGift }: typeof import('../roomEvents.service') = require('../roomEvents.service');
beforeEach(() => {
  state = {
    pk: { id: 'pk', status: 'ACTIVE', room1Id: 1, room2Id: 2, sideAUserId: 10, sideBUserId: 20,
      room1Score: 60, room2Score: 40, endsAt: new Date(Date.now() - 1000),
      configSnapshot: { minTotalCoins: '100', rewards: { winner: { type: 'both', coins: 50, itemId: 'product', quantity: 1, weight: 1 } },
        viewerGiftCoins: 5, viewerGiftItem: { type: 'item', itemId: 'viewer-product', quantity: 1, weight: 1 } } },
    accounts: { 'PK_ESCROW:pk': 50n, PK_POOL: 100n }, users: {}, claims: [], items: [], ledger: [], audits: [], contributions: [], box: null,
  };
  events = [];
});
const conflict = (e: any) => e.status === 409;
test('below threshold shows winner locally, grants nothing and returns escrow', async () => {
  state.pk.room2Score = 39;
  const result = await finishPk('pk');
  assert.equal(result.winner, 'A'); assert.equal(result.prizeEligible, false);
  assert.deepEqual(state.users, {}); assert.deepEqual(state.items, []); assert.equal(state.box, null);
  assert.equal(state.accounts.PK_POOL, 150n);
  assert.deepEqual(events.map(e => e.event), ['pk_result', 'pk_result']);
  await assert.rejects(claimPk('pk', 30), conflict);
});
test('at threshold pays both winner prizes, broadcasts a ten minute box and pays a viewer once', async () => {
  const now = Date.now();
  const result = await finishPk('pk');
  assert.equal(result.prizeEligible, true); assert.equal(state.users[10], 50);
  assert.equal(state.items[0].itemId, 'product');
  assert.ok(state.box.expiresAt.getTime() >= now + 600000);
  assert.equal(events[0].event, 'pk_prize');
  assert.deepEqual(events[0].payload.roomIds, [1, 2]);
  assert.equal(events[0].payload.winnerName, 'Winner');
  const reward = await claimPk('pk', 30);
  assert.equal(reward.rewards[0].coins, 5); assert.equal(state.users[30], 5);
  assert.equal(state.items[1].itemId, 'viewer-product'); assert.equal(state.claims.length, 1);
  assert.equal(state.accounts.PK_POOL, 95n);
  assert.ok(state.ledger.some((l: any) => l.account === 'PK_POOL' && l.delta === -5n));
  assert.equal(await finishPk('pk'), null);
});
test('duplicate claim is a conflict without another debit or entitlement', async () => {
  await finishPk('pk'); await claimPk('pk', 30);
  await assert.rejects(claimPk('pk', 30), conflict);
  assert.equal(state.users[30], 5); assert.equal(state.accounts.PK_POOL, 95n);
  assert.equal(state.claims.length, 1); assert.equal(state.items.length, 2);
});
test('winner, expired box and depleted pool cannot claim', async () => {
  await finishPk('pk');
  await assert.rejects(claimPk('pk', 10), conflict);
  state.accounts.PK_POOL = 0n;
  await assert.rejects(claimPk('pk', 30), conflict);
  assert.equal(state.claims.length, 0); assert.equal(state.users[30], undefined);
  state.box.expiresAt = new Date(Date.now() - 1);
  await assert.rejects(claimPk('pk', 30), conflict);
});
test('ROOM gifts to unrelated recipients score by room and retain the gift filter', async () => {
  state.pk.type = 'ROOM'; state.pk.startedAt = new Date(Date.now() - 10000); state.pk.endsAt = new Date(Date.now() + 10000);
  state.pk.configSnapshot.countedGiftIds = ['gift']; state.pk.configSnapshot.pointsPerCoin = 2;
  state.gift = { roomId: 2, recipientId: 99, giftId: 'gift', paidCoins: 5, createdAt: new Date() };
  await processRoomGift('gift-1'); assert.equal(state.pk.room2Score, 50);
  assert.equal(state.contributions[0].side, 'B');
  state.gift.giftId = 'excluded'; await processRoomGift('gift-2');
  assert.equal(state.pk.room2Score, 50); assert.equal(state.contributions.length, 1);
});
test('inside one room a gift counts for the side whose player received it, not the opener', async () => {
  Object.assign(state.pk, { type: 'ROOM', room1Id: 1, room2Id: 1, sideAUserId: 10, sideBUserId: 20, room1Score: 0, room2Score: 0 });
  state.pk.startedAt = new Date(Date.now() - 10000); state.pk.endsAt = new Date(Date.now() + 10000);
  state.pk.configSnapshot.countedGiftIds = []; state.pk.configSnapshot.pointsPerCoin = 1;
  state.contributions.length = 0;
  state.gift = { roomId: 1, recipientId: 20, giftId: 'gift', paidCoins: 7, createdAt: new Date() };
  await processRoomGift('gift-b'); assert.equal(state.pk.room2Score, 7); assert.equal(state.pk.room1Score, 0);
  assert.equal(state.contributions.at(-1).side, 'B');
});
