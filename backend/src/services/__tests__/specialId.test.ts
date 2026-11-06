import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

// Prisma model delegates are proxy-backed; stub the module before loading the
// service instead of using t.mock.method on their property descriptors.
const db: any = {};
const filename = require.resolve(resolve(__dirname, '../../utils/prisma'));
require.cache[filename] = { id: filename, filename, loaded: true, exports: { __esModule: true, default: db } } as any;
const { buyStoreProduct, grantSpecialId, revokeSpecialId, sendSpecialId, sweepExpiredSpecialIds }:
  typeof import('../storeLists.service') = require('../storeLists.service');

// Exercise the public service operations with a transaction double. Database
// locking/partial unique indexes still require integration validation in Postgres.
function fixture() {
  let state: any = {
    users: [{ id: 1, displayId: 100001, coinsBalance: 1000 }, { id: 2, displayId: 100002, coinsBalance: 0 }],
    products: [{ id: 10, kind: 'special_id', name: 'Special ID', specialDisplayId: 7777,
      priceCoins: 100, durationDays: 3, stock: 1, isAvailable: true }],
    holdings: [], orders: [], history: [], ledger: [], audits: [], notifications: [],
  };
  const matches = (row: any, where: any): boolean => Object.entries(where || {}).every(([key, value]: any) => {
    if (key === 'OR') return value.some((clause: any) => matches(row, clause));
    if (value && typeof value === 'object' && 'lt' in value) return row[key] != null && +new Date(row[key]) < +value.lt;
    return row[key] === value;
  });
  const model = (name: string) => ({
    findUnique: async ({ where }: any) => state[name].find((r: any) => matches(r, where)) ?? null,
    findFirst: async ({ where }: any) => state[name].find((r: any) => matches(r, where)) ?? null,
    findMany: async ({ where }: any) => state[name].filter((r: any) => matches(r, where)),
    create: async ({ data }: any) => {
      const row = { id: state[name].length + 1, ...(name === 'holdings' ? { status: 'active' } : {}), ...data };
      state[name].push(row);
      return { ...row };
    },
    update: async ({ where, data }: any) => {
      const row = state[name].find((r: any) => matches(r, where));
      assert.ok(row);
      for (const [key, value] of Object.entries(data) as any) {
        row[key] = value && typeof value === 'object' && 'decrement' in value ? row[key] - value.decrement : value;
      }
      return { ...row };
    },
  });
  const tx: any = {
    user: { ...model('users'), updateMany: async ({ where, data }: any) => {
      const user = state.users.find((u: any) => u.id === where.id && u.coinsBalance >= where.coinsBalance.gte);
      if (!user) return { count: 0 };
      user.coinsBalance -= data.coinsBalance.decrement;
      return { count: 1 };
    } },
    userSpecialId: model('holdings'), storeProduct: model('products'), storeOrder: model('orders'),
    displayIdHistory: model('history'), transaction: model('ledger'), adminAuditLog: model('audits'), notification: model('notifications'),
    $queryRaw: async (query: any) => String(query.strings?.join('')).includes('store_products')
      ? state.products.filter((p: any) => p.id === query.values[0]) : [],
  };
  Object.assign(db, tx, {
    $transaction: async (work: any) => {
      const before = structuredClone(state);
      try { return await work(tx); } catch (e) { state = before; throw e; }
    },
  });
  return { get state() { return state; } };
}

test('grant and revoke restore original ID and record history and audit', async () => {
  const f = fixture();
  await grantSpecialId(99, 2, 7777, null);
  assert.equal(f.state.users[1].displayId, 7777);
  assert.equal(f.state.holdings[0].originalDisplayId, 100002);
  await revokeSpecialId(99, 2);
  assert.equal(f.state.users[1].displayId, 100002);
  assert.equal(f.state.holdings[0].status, 'revoked');
  assert.equal(f.state.history.length, 2);
  assert.equal(f.state.audits.length, 2);
});

test('expiry restores original ID, leaves permanent IDs alone, and notifies once', async () => {
  const f = fixture();
  await grantSpecialId(99, 2, 7777, 1);
  await grantSpecialId(99, 1, 8888, null);
  await sweepExpiredSpecialIds(new Date(Date.now() + 2 * 86_400_000));
  await sweepExpiredSpecialIds(new Date(Date.now() + 2 * 86_400_000));
  assert.equal(f.state.users[1].displayId, 100002);
  assert.equal(f.state.users[0].displayId, 8888);
  assert.equal(f.state.holdings[0].status, 'expired');
  assert.equal(f.state.notifications.length, 1);
  assert.equal(f.state.notifications[0].userId, 2);
});

test('send charges sender and gives only recipient the ID; retries do not debit again', async () => {
  const f = fixture();
  const input = { productId: 10, toUserId: 2 };
  const first = await sendSpecialId(1, input, 'gift-one');
  const retry = await sendSpecialId(1, input, 'gift-one');
  assert.equal(retry.id, first.id);
  assert.equal(f.state.users[0].displayId, 100001);
  assert.equal(f.state.users[0].coinsBalance, 900);
  assert.equal(f.state.users[1].displayId, 7777);
  assert.equal(f.state.users[1].coinsBalance, 0);
  assert.equal(f.state.holdings[0].source, 'gift');
  assert.equal(f.state.holdings[0].originalDisplayId, 100002);
  assert.equal(f.state.ledger.length, 1);
  assert.equal(f.state.notifications.length, 1);
  await assert.rejects(buyStoreProduct(1, 10, 'gift-one'), { code: 'KEY_REUSED' });
});

test('duplicate special ID and reserved original ID are refused', async () => {
  const f = fixture();
  await grantSpecialId(99, 2, 7777, null);
  await assert.rejects(grantSpecialId(99, 1, 7777, null), { code: 'ID_TAKEN' });
  await assert.rejects(grantSpecialId(99, 1, 100002, null), { code: 'ID_TAKEN' });
  assert.equal(f.state.holdings.length, 1);
});

test('recipient with active ID is refused without charging sender', async () => {
  const f = fixture();
  await grantSpecialId(99, 2, 8888, null);
  await assert.rejects(sendSpecialId(1, { productId: 10, toUserId: 2 }, 'active-recipient'), { code: 'ACTIVE_SPECIAL_ID' });
  assert.equal(f.state.users[0].coinsBalance, 1000);
  assert.equal(f.state.orders.length, 0);
});

test('rebuy extends rental despite sold-out stock and preserves original ID', async () => {
  const f = fixture();
  await buyStoreProduct(1, 10, 'buy-one');
  const firstExpiry = +f.state.holdings[0].expiresAt;
  await buyStoreProduct(1, 10, 'buy-two');
  assert.equal(+f.state.holdings[0].expiresAt, firstExpiry + 3 * 86_400_000);
  assert.equal(f.state.holdings.length, 1);
  assert.equal(f.state.holdings[0].originalDisplayId, 100001);
  assert.equal(f.state.users[0].coinsBalance, 800);
  assert.equal(f.state.products[0].stock, 0);
  await revokeSpecialId(99, 1);
  assert.equal(f.state.users[0].displayId, 100001);
});

test('insufficient funds rolls back recipient ID, holding, order, history and stock', async () => {
  const f = fixture();
  f.state.users[0].coinsBalance = 0;
  await assert.rejects(sendSpecialId(1, { productId: 10, toUserId: 2 }, 'no-money'), { code: 'INSUFFICIENT' });
  assert.equal(f.state.users[1].displayId, 100002);
  assert.equal(f.state.holdings.length, 0);
  assert.equal(f.state.orders.length, 0);
  assert.equal(f.state.history.length, 0);
  assert.equal(f.state.ledger.length, 0);
  assert.equal(f.state.products[0].stock, 1);
});

test('order selector checks sender ownership; self gifts and invalid durations are rejected', async () => {
  const f = fixture();
  f.state.orders.push({ id: 20, userId: 2, productId: 10 });
  await assert.rejects(sendSpecialId(1, { orderId: 20, toUserId: 2 }, 'foreign-order'), { code: 'NOT_FOUND' });
  await assert.rejects(sendSpecialId(1, { productId: 10, toUserId: 1 }, 'self'), { code: 'SELF_GIFT' });
  await assert.rejects(grantSpecialId(99, 2, 7777, -1), { code: 'INVALID_INPUT' });
  f.state.orders[0].userId = 1;
  await sendSpecialId(1, { orderId: 20, toUserId: 2 }, 'own-order');
  assert.equal(f.state.users[1].displayId, 7777);
});

test('null original ID is restored without losing history', async () => {
  const f = fixture();
  f.state.users[1].displayId = null;
  await grantSpecialId(99, 2, 7777, null);
  await revokeSpecialId(99, 2);
  assert.equal(f.state.users[1].displayId, null);
  assert.equal(f.state.history[1].newId, null);
});
