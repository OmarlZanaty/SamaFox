// المحظوظ, client rules of 2026-10-05: «خلي المكسب من قيمة الهديه» · «30% للبرنامج
// و70% للاعبين» · «مفيش مكسب من البرنامج نهائي» · a lone player «يكسب من خسارته».
// rollLucky against an in-memory transaction.
import test from 'node:test';
import assert from 'node:assert/strict';
import { LUCKY_DEFAULTS, analyzeTiers, rollLucky, validateTiers, type LuckyConfig } from '../lucky.service';

type Row = Record<string, any>;

/** Apply Prisma-style `{ increment }` / `{ decrement }` / plain values. */
function apply(row: Row, data: Row) {
  for (const [k, v] of Object.entries(data)) {
    if (v && typeof v === 'object' && 'increment' in v) row[k] = row[k] + v.increment;
    else if (v && typeof v === 'object' && 'decrement' in v) row[k] = row[k] - v.decrement;
    else row[k] = v;
  }
  return row;
}

function fakeTx(opts: { pool: bigint; tiers: { multiplier: number; weightBp: number }[] }) {
  const pool: Row = { id: 1, balance: opts.pool, totalIn: 0n, totalOut: 0n };
  const rounds: Row[] = [];
  const rolls: Row[] = [];
  const wins: Row[] = [];
  const tiers = opts.tiers.map((t) => ({ ...t, minPoolCoins: 0n }));
  const tx: any = {
    luckyPool: {
      upsert: async ({ update }: any) => ({ balance: apply(pool, update).balance }),
      findUnique: async () => ({ balance: pool.balance }),
      updateMany: async ({ where, data }: any) => {
        if (pool.balance < where.balance.gte) return { count: 0 };
        apply(pool, data);
        return { count: 1 };
      },
    },
    economyAccount: { upsert: async () => ({ balance: 0n }) },
    economyLedger: { create: async () => ({}) },
    luckyTier: { findMany: async () => tiers },
    luckyRound: {
      findMany: async () => [],
      findFirst: async ({ where }: any) =>
        [...rounds].reverse().find((r) => r.roomId === where.roomId && r.status === 'OPEN') ?? null,
      create: async ({ data }: any) => {
        const r = { id: rounds.length + 1, status: 'OPEN', playerCount: 0, entryCount: 0, totalEntry: 0n, hostShare: 0n, programShare: 0n, prizePool: 0n, totalWin: 0n, ...data };
        rounds.push(r);
        return r;
      },
      update: async ({ where, data }: any) => ({ ...apply(rounds.find((r) => r.id === where.id)!, data) }),
    },
    luckyRoll: {
      findFirst: async ({ where }: any) => rolls.find((r) => r.roundId === where.roundId && r.senderId === where.senderId) ?? null,
      create: async ({ data }: any) => {
        const r = { id: rolls.length + 1, ...data };
        rolls.push(r);
        return { id: r.id };
      },
      findMany: async ({ where }: any) => rolls.filter((r) => r.roundId === where.roundId && r.status === where.status),
      update: async ({ where, data }: any) => apply(rolls.find((r) => r.id === where.id)!, data),
      updateMany: async () => ({ count: 0 }),
      aggregate: async ({ where }: any) => {
        const mine = rolls.filter((r) => r.senderId === where.senderId);
        return { _sum: { poolCoins: mine.reduce((a, r) => a + r.poolCoins, 0), payoutCoins: mine.reduce((a, r) => a + r.payoutCoins, 0) } };
      },
    },
    user: { update: async () => ({}) },
    transaction: { create: async ({ data }: any) => wins.push(data) },
  };
  return { tx, pool, rolls, wins };
}

let seq = 0;
const enter = (tx: any, senderId: number, V: number, cfg: LuckyConfig, roomId = 1) =>
  rollLucky(tx, { giftTxId: `tx${++seq}`, senderId, recipientId: 99, roomId, giftCoins: V, hostCoins: V / 10, cfg });

test('a win pays m × the full gift value, out of the pool', async () => {
  const cfg = { ...LUCKY_DEFAULTS };
  const { tx, pool } = fakeTx({ pool: 1_000_000n, tiers: [{ multiplier: 5, weightBp: 10_000 }] });
  const first = await enter(tx, 1, 1000, cfg);
  assert.equal(first.own.status, 'PENDING', 'two players needed by default');
  const second = await enter(tx, 2, 1000, cfg);
  assert.equal(second.own.multiplier, 5);
  assert.equal(second.own.payoutCoins, 5000, 'x5 on V=1000');
  assert.deepEqual(second.settled.map((s) => s.payoutCoins), [5000, 5000]);
  // In: 70% of 2 × 1000; out: two wins of 5,000.
  assert.equal(pool.balance, 1_000_000n + 1400n - 10_000n);
});

test('the locked floor is never paid out', async () => {
  const cfg = { ...LUCKY_DEFAULTS, poolFloor: 1_000_000 };
  const { tx, pool } = fakeTx({ pool: 1_000_000n, tiers: [{ multiplier: 5, weightBp: 10_000 }] });
  await enter(tx, 1, 1000, cfg);
  const r = await enter(tx, 2, 1000, cfg);
  assert.equal(r.own.multiplier, 0, 'x5 (5,000) > the 1,400 players put in above the floor');
  assert.equal(pool.balance, 1_001_400n);
});

test('a lone player is drawn at once with minPlayers 1, and only wins back his own losses', async () => {
  const cfg = { ...LUCKY_DEFAULTS, minPlayers: 1 };
  const { tx, wins } = fakeTx({ pool: 10_000_000n, tiers: [{ multiplier: 5, weightBp: 10_000 }] });
  // Each 100 puts 70 in the pool; x5 pays 500 → the 8th entry (560) is the first that can win.
  for (let i = 1; i <= 7; i++) {
    const r = await enter(tx, 7, 100, cfg, 92);
    assert.equal(r.own.status, 'SETTLED', `entry ${i} drawn at once`);
    assert.equal(r.own.multiplier, 0, `entry ${i}: ${i * 70} of his own < 500`);
  }
  const eighth = await enter(tx, 7, 100, cfg, 92);
  assert.equal(eighth.own.multiplier, 5);
  assert.equal(eighth.own.payoutCoins, 500);
  // What he won is taken off what he can win next.
  const ninth = await enter(tx, 7, 100, cfg, 92);
  assert.equal(ninth.own.multiplier, 0, '630 − 500 = 130 left of his own');
  assert.equal(wins.length, 1);
});

test('once a second player joins, the round pays from the shared pool', async () => {
  const cfg = { ...LUCKY_DEFAULTS, minPlayers: 1 };
  const { tx } = fakeTx({ pool: 10_000_000n, tiers: [{ multiplier: 5, weightBp: 10_000 }] });
  const alone = await enter(tx, 1, 100, cfg);
  assert.equal(alone.own.multiplier, 0, 'alone: 70 of his own < 500');
  const other = await enter(tx, 2, 100, cfg);
  assert.equal(other.own.multiplier, 5, 'two players: shared pool');
});

test('RTP is E[m]; the proposed table fits the 65% target', () => {
  const table = [
    { multiplier: 5, weightBp: 350 }, { multiplier: 10, weightBp: 150 }, { multiplier: 20, weightBp: 50 },
    { multiplier: 30, weightBp: 15 }, { multiplier: 50, weightBp: 8 }, { multiplier: 100, weightBp: 3 },
    { multiplier: 200, weightBp: 1 }, { multiplier: 300, weightBp: 1 }, { multiplier: 500, weightBp: 1 },
  ];
  const a = analyzeTiers(table, 1000, LUCKY_DEFAULTS);
  assert.ok(Math.abs(a.rtp - 0.64) < 1e-9, String(a.rtp));
  assert.equal(a.totalWeightBp, 579);
  assert.equal(validateTiers(table, LUCKY_DEFAULTS), null);
  // The old table (built for m × 10%) is now far above target and refused.
  const old = [{ multiplier: 5, weightBp: 3500 }, { multiplier: 10, weightBp: 2000 }];
  assert.notEqual(validateTiers(old, LUCKY_DEFAULTS), null);
});
