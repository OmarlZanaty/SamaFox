import { test } from 'node:test';
import assert from 'node:assert/strict';

const db: any = {};
const filename = require.resolve('../../utils/prisma');
require.cache[filename] = { id: filename, filename, loaded: true, exports: { __esModule: true, default: db } } as any;
// Do not start the HTTP/socket server through xp.service's notifications import.
const notificationFile = require.resolve('../notification.service');
require.cache[notificationFile] = { id: notificationFile, filename: notificationFile, loaded: true, exports: { createNotification: async () => undefined } } as any;
const { resetEconomyPools, resetLuckyRounds }: typeof import('../economyAdmin.service') = require('../economyAdmin.service');
const { KNOWN_GAMES }: typeof import('../gameConfig.service') = require('../gameConfig.service');
const { gamePoolAccount, PROGRAM_ACCOUNT }: typeof import('../economyAccounts.service') = require('../economyAccounts.service');
const audit = { adminId: 1, reason: 'Clear launch test data' };

function fixture(failAudit = false) {
  let state = {
    accounts: Object.fromEntries([...KNOWN_GAMES.map(g => [gamePoolAccount(g), 123n]), [PROGRAM_ACCOUNT, 5n]]) as Record<string, bigint>,
    lucky: { balance: 456n, totalIn: 500n, totalOut: 44n },
    ledger: [] as any[], audits: [] as any[], pending: 0, open: 0, archived: false,
  };
  const tx: any = {
    $executeRawUnsafe: async () => 0,
    economyAccount: {
      findUnique: async ({ where }: any) => state.accounts[where.key] == null ? null : { balance: state.accounts[where.key] },
      updateMany: async ({ where, data }: any) => {
        if ((state.accounts[where.key] ?? -1n) < where.balance.gte) return { count: 0 };
        state.accounts[where.key] = (state.accounts[where.key] as bigint) - data.balance.decrement;
        return { count: 1 };
      },
      upsert: async ({ where, update, create }: any) => {
        state.accounts[where.key] = state.accounts[where.key] == null ? create.balance : state.accounts[where.key] + update.balance.increment;
        return { balance: state.accounts[where.key] };
      },
    },
    economyLedger: { create: async ({ data }: any) => { state.ledger.push(data); } },
    adminAuditLog: { create: async ({ data }: any) => {
      if (failAudit) throw new Error('Audit unavailable');
      state.audits.push(data);
    } },
    luckyPool: {
      findUnique: async () => ({ ...state.lucky }),
      updateMany: async ({ where, data }: any) => {
        if (where.balance && state.lucky.balance < where.balance.gte) return { count: 0 };
        if (data.balance) {
          state.lucky.balance -= data.balance.decrement;
          state.lucky.totalOut += data.totalOut.increment;
        } else { state.lucky.totalIn = 0n; state.lucky.totalOut = 0n; }
        return { count: 1 };
      },
    },
    luckyRoll: { count: async () => state.pending, updateMany: async () => { state.archived = true; return { count: 2 }; } },
    luckyRound: { count: async () => state.open, updateMany: async () => ({ count: 1 }) },
  };
  const client = { $transaction: async (work: any) => {
    const before = structuredClone(state);
    try { return await work(tx); } catch (e) { state = before; throw e; }
  } };
  return { client, get state() { return state; } };
}

test('all game pools reset to zero with conserved coins and balanced ledger; repeat is a no-op', async () => {
  const f = fixture();
  await resetEconomyPools(KNOWN_GAMES, false, audit, f.client);
  for (const game of KNOWN_GAMES) assert.equal(f.state.accounts[gamePoolAccount(game)], 0n);
  assert.equal(f.state.accounts[PROGRAM_ACCOUNT], 5n + BigInt(KNOWN_GAMES.length) * 123n);
  assert.equal(f.state.ledger.reduce((sum, row) => sum + row.delta, 0n), 0n);
  assert.equal(f.state.ledger.length, KNOWN_GAMES.length * 2);
  await resetEconomyPools(KNOWN_GAMES, false, audit, f.client);
  assert.equal(f.state.ledger.length, KNOWN_GAMES.length * 2);
});

test('lucky reset uses the authoritative pool and books both sides', async () => {
  const f = fixture();
  await resetEconomyPools([], true, audit, f.client);
  assert.equal(f.state.lucky.balance, 0n);
  assert.equal(f.state.accounts[PROGRAM_ACCOUNT], 461n);
  assert.equal(f.state.ledger.length, 2);
  assert.equal(f.state.ledger.reduce((sum, row) => sum + row.delta, 0n), 0n);
});

test('failed audit rolls back balances and ledger', async () => {
  const f = fixture(true);
  await assert.rejects(resetEconomyPools(KNOWN_GAMES, false, audit, f.client), /Audit unavailable/);
  assert.equal(f.state.accounts[PROGRAM_ACCOUNT], 5n);
  assert.equal(f.state.ledger.length, 0);
});

test('history reset preserves balance, clears counters, and rejects active rounds', async () => {
  const f = fixture();
  f.state.open = 1;
  await assert.rejects(resetLuckyRounds(audit, f.client), /Active lucky/);
  assert.equal(f.state.archived, false);
  f.state.open = 0;
  await resetLuckyRounds(audit, f.client);
  assert.equal(f.state.archived, true);
  assert.deepEqual(f.state.lucky, { balance: 456n, totalIn: 0n, totalOut: 0n });
});

test('pending lucky entries, unknown games and empty reasons cannot reset money', async () => {
  const f = fixture();
  f.state.pending = 1;
  await assert.rejects(resetEconomyPools([], true, audit, f.client), /Pending/);
  await assert.rejects(resetEconomyPools(['unknown'], false, audit, f.client), /Unknown/);
  await assert.rejects(resetEconomyPools(KNOWN_GAMES, false, { ...audit, reason: '' }, f.client), /Reason/);
  assert.equal(f.state.ledger.length, 0);
});
