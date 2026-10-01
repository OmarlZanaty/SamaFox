// The freeze only works if EVERY coin spend passes through it. This holds the
// wiring: the real Prisma client (utils/prisma.ts) runs the guard before a user
// update or updateMany ever reaches the database.
import test from 'node:test';
import assert from 'node:assert/strict';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const cf = require('../coinFreeze');
const seen: any[] = [];
cf.guardCoinDecrement = async (args: any) => {
  seen.push(args);
  throw new cf.CoinsFrozenError('frozen-in-test');
};
// eslint-disable-next-line @typescript-eslint/no-var-requires
const prisma = require('../prisma').default;

test('user.update goes through the coin-freeze guard', async () => {
  await assert.rejects(
    prisma.user.update({ where: { id: 7 }, data: { coinsBalance: { decrement: 10 } } }),
    (e: any) => e.message === 'frozen-in-test',
  );
});

test('user.updateMany goes through the coin-freeze guard', async () => {
  await assert.rejects(
    prisma.user.updateMany({ where: { id: 7, coinsBalance: { gte: 10 } }, data: { coinsBalance: { decrement: 10 } } }),
    (e: any) => e.message === 'frozen-in-test',
  );
  assert.equal(seen[seen.length - 1].data.coinsBalance.decrement, 10);
});
