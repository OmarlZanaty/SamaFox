import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
let user: any;
let cap: number | null = 6;
const db: any = {
  roomSession: { deleteMany: async () => ({ count: 0 }) },
  userItem: { findMany: async () => [], deleteMany: async () => ({ count: 0 }) },
  room: { updateMany: async () => ({ count: 0 }) },
  user: {
    findMany: async () => [user],
    findUnique: async () => ({ ...user }),
    update: async ({ data }: any) => Object.assign(user, data),
  },
  vipLevelConfig: { findMany: async () => [], aggregate: async () => ({ _max: { level: cap } }) },
  temporaryEntitlement: { findMany: async () => [] },
  $transaction: async (fn: any) => fn(db),
};
stub('utils/prisma', { __esModule: true, default: db });
stub('services/notification.service', { createNotification: async () => {} });
const { sweepExpired } = require('../expiry.service');

test('a lapsed timed VIP above the cap falls back to the recharge-earned level, not stays permanent', async () => {
  user = { id: 1, vipLevel: 30, totalRecharge: 600_000, vipExpiresAt: new Date(1000) };
  await sweepExpired(new Date(5000));
  assert.equal(user.vipLevel, 1);
  assert.equal(user.vipExpiresAt, null);
});

test('a lapsed VIP is never left above the top configured tier, even with huge recharge', async () => {
  user = { id: 1, vipLevel: 30, totalRecharge: 1e12, vipExpiresAt: new Date(1000) };
  await sweepExpired(new Date(5000));
  assert.equal(user.vipLevel, 6);
});
