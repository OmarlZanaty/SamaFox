// تجميد الكوينزات — «محدش يعرف يستخدم الكوينزات في اي شي، افك التجميد يرجع
// كما كان، وكمان اجمد مستخدم بالايدي لوحده».
import test from 'node:test';
import assert from 'node:assert/strict';
import * as path from 'node:path';

const settings = new Map<string, string>();
const fakePrisma: any = {
  appSetting: {
    findMany: async ({ where }: any) =>
      [...settings.entries()]
        .filter(([k]) => !where?.key?.in || where.key.in.includes(k))
        .map(([key, value]) => ({ key, value })),
    upsert: async ({ where, create }: any) => {
      settings.set(where.key, create.value);
      return {};
    },
  },
};
const prismaPath = require.resolve(path.resolve(__dirname, '../prisma'));
require.cache[prismaPath] = {
  id: prismaPath, filename: prismaPath, loaded: true,
  exports: { __esModule: true, default: fakePrisma },
} as any;

// eslint-disable-next-line @typescript-eslint/no-var-requires
const cf = require('../coinFreeze') as typeof import('../coinFreeze');

const spend = (userId: number, amount: number | bigint = 100) => ({
  where: { id: userId, coinsBalance: { gte: 100 } },
  data: { coinsBalance: { decrement: amount } },
});

test.beforeEach(async () => {
  settings.clear();
  await cf.setCoinsGloballyFrozen(false); // also clears the cache
  settings.clear();
});

test('nothing is frozen until the owner freezes it', async () => {
  await assert.doesNotReject(cf.guardCoinDecrement(spend(7)));
});

test('the global freeze stops every spend, and unfreezing restores it', async () => {
  await cf.setCoinsGloballyFrozen(true);
  await assert.rejects(cf.guardCoinDecrement(spend(7)), (e: any) => e.code === 'COINS_FROZEN' && e.status === 403);
  await assert.rejects(cf.guardCoinDecrement(spend(8, BigInt(5))));
  await cf.setCoinsGloballyFrozen(false);
  await assert.doesNotReject(cf.guardCoinDecrement(spend(7)));
});

test('one account frozen by id; the others spend normally', async () => {
  await cf.setUserCoinsFrozen(7, true);
  await assert.rejects(cf.guardCoinDecrement(spend(7)), (e: any) => e.message === cf.COINS_FROZEN_MESSAGE);
  await assert.doesNotReject(cf.guardCoinDecrement(spend(8)));
  await cf.setUserCoinsFrozen(7, false);
  await assert.doesNotReject(cf.guardCoinDecrement(spend(7)));
});

test('a personal freeze outlives lifting the global one', async () => {
  await cf.setCoinsGloballyFrozen(true);
  await cf.setUserCoinsFrozen(7, true);
  await cf.setCoinsGloballyFrozen(false);
  await assert.rejects(cf.guardCoinDecrement(spend(7)));
  await assert.doesNotReject(cf.guardCoinDecrement(spend(8)));
});

test('receiving coins is never blocked — only taking them out', async () => {
  await cf.setCoinsGloballyFrozen(true);
  await assert.doesNotReject(cf.guardCoinDecrement({ where: { id: 7 }, data: { coinsBalance: { increment: 50 } } }));
  // A negative decrement is an increment (charging-agency adjustments use it).
  await assert.doesNotReject(cf.guardCoinDecrement({ where: { id: 7 }, data: { coinsBalance: { decrement: -50 } } }));
  await assert.doesNotReject(cf.guardCoinDecrement({ where: { id: 7 }, data: { name: 'x' } }));
});

test('an admin removing coins is not the user spending', async () => {
  await cf.setUserCoinsFrozen(7, true);
  await cf.setCoinsGloballyFrozen(true);
  await assert.doesNotReject(cf.runWithCoinFreezeBypass('all', async () => cf.guardCoinDecrement(spend(7))));
});

test('a charging agent can still sell under the global freeze, but not when frozen himself', async () => {
  await cf.setCoinsGloballyFrozen(true);
  await assert.doesNotReject(cf.runWithCoinFreezeBypass('global', async () => cf.guardCoinDecrement(spend(9))));
  await cf.setUserCoinsFrozen(9, true);
  await assert.rejects(cf.runWithCoinFreezeBypass('global', async () => cf.guardCoinDecrement(spend(9))));
});

test('the frozen user is told why, whatever error the route would have sent', async () => {
  await cf.setUserCoinsFrozen(7, true);
  let status = 0;
  let body: any = null;
  const res: any = {
    statusCode: 200,
    status(c: number) { this.statusCode = c; status = c; return this; },
    json(b: any) { body = b; return this; },
  };
  await new Promise<void>((done) => {
    cf.coinFreezeResponses({} as any, res, async () => {
      try { await cf.guardCoinDecrement(spend(7)); } catch { /* the route swallows it */ }
      res.status(500).json({ message: 'Internal error' });
      done();
    });
  });
  assert.equal(status, 403);
  assert.equal(body.code, 'COINS_FROZEN');
  assert.equal(body.message, cf.COINS_FROZEN_MESSAGE);
});

test('a normal error in an unfrozen request is left alone', async () => {
  let body: any = null;
  const res: any = {
    statusCode: 200,
    status(c: number) { this.statusCode = c; return this; },
    json(b: any) { body = b; return this; },
  };
  await new Promise<void>((done) => {
    cf.coinFreezeResponses({} as any, res, async () => {
      await cf.guardCoinDecrement(spend(7));
      res.status(402).json({ message: 'Insufficient balance' });
      done();
    });
  });
  assert.equal(body.message, 'Insufficient balance');
});
