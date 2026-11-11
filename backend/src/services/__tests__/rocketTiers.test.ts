import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

let state: any;
let events: any[];
const db: any = {
  $transaction: async (work: any) => work(db),
  $executeRawUnsafe: async () => 1,
  roomGiftJob: { findUnique: async () => ({ processedAt: null }), update: async () => ({}) },
  giftTransaction: { findUnique: async () => state.gift },
  rocketConfig: { findFirst: async () => state.cfg },
  rocketEvent: {
    updateMany: async ({ where, data }: any) => {
      const e = state.events.find((x: any) => x.id === where.id && x.status === where.status);
      if (!e) return { count: 0 };
      Object.assign(e, data); return { count: 1 };
    },
    findFirst: async ({ where }: any) => {
      const list = state.events.filter((e: any) => e.roomId === where.roomId && (!where.status || e.status === where.status));
      return list.length ? { ...list[list.length - 1] } : null;
    },
    create: async ({ data }: any) => {
      const e = { id: `e${state.events.length + 1}`, status: 'ACTIVE', currentCoins: 0, ...data };
      state.events.push(e); return { ...e };
    },
    update: async ({ where, data }: any) => {
      const e = state.events.find((x: any) => x.id === where.id);
      Object.assign(e, data); return { ...e };
    },
  },
  rocketContribution: {
    findUnique: async () => null,
    create: async ({ data }: any) => { state.contributions.push(data); },
    groupBy: async ({ where }: any) => {
      const m = new Map<number, number>();
      for (const c of state.contributions.filter((c: any) => c.eventId === where.eventId)) m.set(c.userId, (m.get(c.userId) ?? 0) + c.coins);
      return [...m].map(([userId, coins]) => ({ userId, _sum: { coins } }));
    },
  },
  rocketTopPrize: {
    create: async ({ data }: any) => { const r = { id: state.top.length + 1, claimedAt: null, createdAt: new Date(), ...data }; state.top.push(r); return r; },
    findMany: async ({ where }: any) => state.top.filter((t: any) => t.userId === where.userId && t.claimedAt === null),
    findUnique: async ({ where }: any) => state.top.find((t: any) => t.id === where.id) ?? null,
    updateMany: async ({ where }: any) => {
      const t = state.top.find((x: any) => x.id === where.id && x.claimedAt === null);
      if (!t) return { count: 0 };
      t.claimedAt = new Date(); return { count: 1 };
    },
  },
  pkRoomLock: { findUnique: async () => null },
  room: { findUnique: async () => ({ name: 'Room' }) },
  user: {
    findMany: async ({ where }: any) => where.id.in.map((id: number) => ({ id, name: `U${id}`, avatarUrl: `a${id}.png` })),
    findUniqueOrThrow: async ({ where }: any) => ({ coinsBalance: state.users[where.id] || 0 }),
    update: async ({ where, data }: any) => { state.users[where.id] = (state.users[where.id] || 0) + data.coinsBalance.increment; },
  },
  economyAccount: {
    findUnique: async ({ where }: any) => ({ balance: state.accounts[where.key] || 0n }),
    updateMany: async ({ where, data }: any) => {
      if ((state.accounts[where.key] || 0n) < where.balance.gte) return { count: 0 };
      state.accounts[where.key] -= data.balance.decrement; return { count: 1 };
    },
    upsert: async ({ where, update }: any) => {
      state.accounts[where.key] = (state.accounts[where.key] || 0n) + update.balance.increment;
      return { balance: state.accounts[where.key] };
    },
  },
  economyLedger: { create: async () => ({}) },
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/adminAudit.service', { recordAdminAuditStrict: async () => {} });
stub('services/notification.service', { createNotification: async (n: any) => { state.notes.push(n); } });
stub('services/socket.service', {
  emitGlobal: (event: string, payload: any) => events.push({ event, payload }),
  emitToRoomAndUsers: () => {},
});
const { processRoomGift, claimRocketTopPrize, pendingRocketTopPrizes }: typeof import('../roomEvents.service') = require('../roomEvents.service');
const coins = (n: number) => [{ type: 'coins', coins: n, quantity: 1, weight: 1 }];
beforeEach(() => {
  state = {
    cfg: { isActive: true, targetCoins: 999, roomCupPercent: 10000, durationMinutes: 30, rewards: [], claimWindowSeconds: 90,
      tiers: [{ targetCoins: 100, topRewards: [coins(30), coins(20), coins(10)] }, { targetCoins: 300, topRewards: [coins(90)] }] },
    events: [], contributions: [], top: [], users: {}, notes: [], accounts: { ROCKET_POOL: 1000n },
  };
  events = [];
});
const send = async (senderId: number, paid: number) => {
  state.gift = { roomId: 7, senderId, giftId: 'g', paidCoins: paid, createdAt: new Date() };
  await processRoomGift(`gift-${Math.random()}`);
};
test('tier 1 launches at its target, its top 3 get held prizes, launcher is in the global event', async () => {
  await send(1, 50); await send(2, 30); await send(3, 10); await send(4, 5); await send(2, 40);
  assert.equal(state.events[0].status, 'LAUNCHED');
  const launch = events.find(e => e.event === 'rocket_launched').payload;
  assert.equal(launch.launcher.id, 2); assert.equal(launch.launcher.name, 'U2');
  assert.equal(launch.tierNumber, 1); assert.equal(launch.tiersCount, 2);
  assert.deepEqual(launch.topSupporters.map((t: any) => t.userId), [2, 1, 3]);
  assert.equal(state.notes.length, 3);
  assert.equal(state.users[2], undefined); // held, not paid
  const [mine] = await pendingRocketTopPrizes(2);
  assert.equal(mine!.rank, 1);
  const r = await claimRocketTopPrize(mine!.id, 2);
  assert.equal(r.rank, 1); assert.equal(state.users[2], 30);
  await assert.rejects(claimRocketTopPrize(mine!.id, 2), /بالفعل/);
  await assert.rejects(claimRocketTopPrize(2, 2), /غير متاحة/);
});
test('the next rocket is the next tier, then it starts over', async () => {
  await send(1, 100);
  await send(1, 1);
  assert.equal(state.events[1].tier, 1); assert.equal(state.events[1].targetCoins, 300);
  await send(1, 299);
  assert.equal(state.events[1].status, 'LAUNCHED');
  await send(1, 1);
  assert.equal(state.events[2].tier, 0); assert.equal(state.events[2].targetCoins, 100);
});
