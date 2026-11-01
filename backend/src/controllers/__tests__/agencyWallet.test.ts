import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

type Row = Record<string, any>;
let seats: Row[];
let users: Row[];
let agency: Row;
let transactions: Row[];
let transfers: Row[];
let globalFreeze: string;
let vipCalls: number[];
let failLedger = false;

function matches(row: Row, where: Row): boolean {
  return Object.entries(where).every(([key, value]) => {
    const actual = key === 'agency' ? (row.agency ?? agency) : row[key];
    if (value !== null && typeof value === 'object') {
      if ('gte' in value) return actual >= value.gte;
      if ('lte' in value) return actual <= value.lte;
      if ('in' in value) return value.in.includes(actual);
      return matches(actual, value);
    }
    return actual === value;
  });
}

function change(row: Row, data: Row) {
  for (const [key, value] of Object.entries(data)) {
    if (value && typeof value === 'object' && 'increment' in value) row[key] += value.increment;
    else if (value && typeof value === 'object' && 'decrement' in value) row[key] -= value.decrement;
    else row[key] = value;
  }
  return { ...row };
}

function model(rows: () => Row[]) {
  return {
    findFirst: async ({ where, orderBy = [] }: Row) => {
      const row = rows().filter(r => matches(r, where)).sort((a, b) => {
        for (const order of orderBy) {
          const [key, direction] = Object.entries(order)[0]!;
          if (a[key] < b[key]) return direction === 'asc' ? -1 : 1;
          if (a[key] > b[key]) return direction === 'asc' ? 1 : -1;
        }
        return 0;
      })[0];
      return row ? { ...row, agency } : null;
    },
    findUnique: async ({ where }: Row) => rows().find(r => matches(r, where)) ?? null,
    findUniqueOrThrow: async ({ where }: Row) => {
      const row = rows().find(r => matches(r, where));
      assert.ok(row);
      return { ...row };
    },
    findMany: async ({ where }: Row) => rows().filter(r => matches(r, where)),
    updateMany: async ({ where, data }: Row) => {
      const found = rows().filter(r => matches(r, where));
      found.forEach(r => change(r, data));
      return { count: found.length };
    },
    update: async ({ where, data }: Row) => {
      const row = rows().find(r => matches(r, where));
      assert.ok(row);
      return change(row, data);
    },
  };
}

const db = {
  agencyMember: model(() => seats),
  user: model(() => users),
  chargingAgency: model(() => [agency]),
  appSetting: { findUnique: async ({ where }: Row) => {
    assert.equal(where.key, 'charging_wallets_frozen');
    return { value: globalFreeze };
  } },
  agencyBranch: { findUnique: async () => null },
  transaction: { create: async ({ data }: Row) => {
    if (failLedger) throw new Error('ledger unavailable');
    const row = { id: transactions.length + 1, ...data };
    transactions.push(row);
    return row;
  } },
  agencyTransfer: { create: async ({ data }: Row) => {
    const row = { id: transfers.length + 1, ...data };
    transfers.push(row);
    return row;
  } },
  adminAuditLog: { create: async () => ({}) },
  $transaction: async (fn: (tx: any) => Promise<any>) => {
    const before = { seats: seats.map(r => ({ ...r })), users: users.map(r => ({ ...r })), agency: { ...agency }, transactions: [...transactions], transfers: [...transfers] };
    try { return await fn(db); } catch (error) {
      ({ seats, users, agency, transactions, transfers } = before);
      throw error;
    }
  },
};

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('lib/prisma', { prisma: db });
stub('services/vip.service', { evaluateVip: async (id: number) => { vipCalls.push(id); } });
stub('services/agencyReward.service', { recordAgencySelfCharge: async () => {} });
stub('services/notification.service', { createNotification: async () => {} });
stub('services/broadcast.service', {});
stub('services/hostTarget.service', {});
stub('services/targetMovement.service', {});
const { chargingRecipient, agencyTransferCoins, withdrawAgencyWallet, myAgencyBalance, adjustOwnerAgencyWallet }: typeof import('../charging-agency.controller') = require('../charging-agency.controller');
const { sendCoinsToUser }: typeof import('../../agencies/agency.controller') = require('../../agencies/agency.controller');

beforeEach(() => {
  agency = { id: 7, userId: 10, type: 'CHARGING', status: 'approved', walletFrozen: false, totalSentCoins: 0 };
  seats = [
    { id: 1, agencyId: 7, userId: 10, role: 'OWNER', agencyWalletCoins: 100n },
    { id: 2, agencyId: 7, userId: 20, role: 'BRANCH', agencyWalletCoins: 40n },
  ];
  users = [10, 20, 30].map(id => ({ id, coinsBalance: 500, totalRecharge: 0 }));
  transactions = [];
  transfers = [];
  globalFreeze = 'false';
  vipCalls = [];
  failLedger = false;
});

async function call(handler: (req: any, res: any) => Promise<any>, body: Row, userId = 10, params: Row = {}) {
  let status = 200;
  let response: any;
  const res = { status(code: number) { status = code; return res; }, json(data: any) { response = data; return res; } };
  await handler({ userId, body, params, query: {} }, res);
  return { status, body: response };
}

for (const handler of [agencyTransferCoins, sendCoinsToUser]) {
  // «لا استطيع شحن محفظتي لنفسي، المطلوب امكانية الشحن لنفسي علي المحفظه»
  test(`${handler.name}: an agent charging themself fills their own personal wallet`, async () => {
    const result = await call(handler, { userId: 10, toUserId: 10, amount: 25 });
    assert.equal(result.status, 200);
    assert.equal(result.body.wallet ?? result.body.data?.wallet, 'personal');
    assert.equal(seats[0]!.agencyWalletCoins, 75n);
    assert.equal(users[0]!.coinsBalance, 525);
    assert.equal(users[0]!.totalRecharge, 0);
    assert.equal(transactions[0]!.type, 'AGENCY_WALLET_WITHDRAW');
  });

  test(`${handler.name}: sale spends only the seller's agency wallet`, async () => {
    const result = await call(handler, { userId: 30, toUserId: 30, amount: 25 });
    assert.equal(result.status, 200);
    assert.equal(result.body.wallet ?? result.body.data?.wallet, 'personal');
    assert.equal(seats[0]!.agencyWalletCoins, 75n);
    assert.equal(users[0]!.coinsBalance, 500);
    assert.equal(users[2]!.coinsBalance, 525);
    assert.equal(users[2]!.totalRecharge, 25);
    assert.deepEqual(vipCalls, [30]);
    assert.equal(transactions[0]!.type, 'AGENCY_TOPUP');
    assert.equal(transfers[0]!.transactionId, transactions[0]!.id);
  });

  test(`${handler.name}: branch sells from its own seat`, async () => {
    assert.equal((await call(handler, { userId: 30, toUserId: 30, amount: 25 }, 20)).status, 200);
    assert.equal(seats[0]!.agencyWalletCoins, 100n);
    assert.equal(seats[1]!.agencyWalletCoins, 15n);
    assert.equal(users[1]!.coinsBalance, 500);
  });

  test(`${handler.name}: personal funds cannot cover insufficient agency funds`, async () => {
    const result = await call(handler, { userId: 30, toUserId: 30, amount: 101 });
    assert.equal(result.status, 409);
    assert.equal(result.body.message, 'رصيد الوكالة غير كافٍ — المتاح 100 كوينز');
    assert.equal(seats[0]!.agencyWalletCoins, 100n);
    assert.equal(users[0]!.coinsBalance, 500);
    assert.equal(users[2]!.coinsBalance, 500);
    assert.equal(transactions.length, 0);
  });

  for (const freeze of ['agency', 'global']) {
    test(`${handler.name}: refuses ${freeze} freeze`, async () => {
      if (freeze === 'agency') agency.walletFrozen = true;
      else globalFreeze = 'true';
      const result = await call(handler, { userId: 30, toUserId: 30, amount: 25 });
      assert.equal(result.status, 403);
      assert.equal(result.body.message, 'رصيد الوكالة مجمّد من الإدارة');
      assert.equal(seats[0]!.agencyWalletCoins, 100n);
      assert.equal(transactions.length, 0);
    });
  }

  test(`${handler.name}: branch credit automatically uses agency wallet and skips VIP`, async () => {
    const result = await call(handler, { userId: 20, toUserId: 20, amount: 25 });
    assert.equal(result.status, 200);
    assert.equal(result.body.wallet ?? result.body.data?.wallet, 'agency');
    assert.deepEqual(seats.map(r => r.agencyWalletCoins), [75n, 65n]);
    assert.deepEqual(users.map(r => r.coinsBalance), [500, 500, 500]);
    assert.deepEqual(users.map(r => r.totalRecharge), [0, 0, 0]);
    assert.deepEqual(vipCalls, []);
    assert.equal(transactions[0]!.type, 'AGENCY_WALLET_TRANSFER');
  });

  test(`${handler.name}: non-agent agency request falls back to personal`, async () => {
    const result = await call(handler, { userId: 30, toUserId: 30, amount: 25, wallet: 'agency' });
    assert.equal(result.status, 200);
    assert.equal(result.body.wallet ?? result.body.data?.wallet, 'personal');
    assert.equal(users[2]!.coinsBalance, 525);
    assert.equal(users[2]!.totalRecharge, 25);
    assert.equal(seats[0]!.agencyWalletCoins, 75n);
    assert.deepEqual(vipCalls, [30]);
  });

  for (const role of ['OWNER', 'BRANCH']) {
    test(`${handler.name}: credits another agency's ${role} wallet`, async () => {
      seats.push({ id: 3, agencyId: 8, userId: 30, role, agencyWalletCoins: 0n,
        agency: { id: 8, type: 'CHARGING', status: 'approved' } });
      const result = await call(handler, { userId: 30, toUserId: 30, amount: 25, wallet: 'personal' });
      assert.equal(result.status, 200);
      assert.equal(result.body.wallet ?? result.body.data?.wallet, 'agency');
      assert.equal(seats[2]!.agencyWalletCoins, 25n);
      assert.equal(users[2]!.coinsBalance, 500);
      assert.equal(users[2]!.totalRecharge, 0);
      assert.deepEqual(vipCalls, []);
    });
  }


  for (const wallet of ['personal', 'agency', 'invalid', null, 42, { destination: 'personal' }]) {
    test(`${handler.name}: ignores wallet ${JSON.stringify(wallet)} for charging agents`, async () => {
      const result = await call(handler, { userId: 20, toUserId: 20, amount: 25, wallet });
      assert.equal(result.status, 200);
      assert.equal(result.body.wallet ?? result.body.data?.wallet, 'agency');
      assert.deepEqual(seats.map(r => r.agencyWalletCoins), [75n, 65n]);
      assert.equal(users[1]!.coinsBalance, 500);
      assert.equal(users[1]!.totalRecharge, 0);
      assert.deepEqual(vipCalls, []);
      assert.equal(transactions[0]!.type, 'AGENCY_WALLET_TRANSFER');
      assert.equal(transfers[0]!.note.startsWith('agency:'), true);
    });

    test(`${handler.name}: ignores wallet ${JSON.stringify(wallet)} for non-agents`, async () => {
      const result = await call(handler, { userId: 30, toUserId: 30, amount: 25, wallet });
      assert.equal(result.status, 200);
      assert.equal(result.body.wallet ?? result.body.data?.wallet, 'personal');
      assert.equal(seats[0]!.agencyWalletCoins, 75n);
      assert.equal(users[2]!.coinsBalance, 525);
      assert.equal(users[2]!.totalRecharge, 25);
      assert.deepEqual(vipCalls, [30]);
      assert.equal(transactions[0]!.type, 'AGENCY_TOPUP');
    });
  }
}

test('withdraw moves the caller seat wallet to personal without recharge/VIP', async () => {
  const result = await call(withdrawAgencyWallet, { amount: 25, agencyId: 7, wallet: 'agency' }, 20);
  assert.equal(result.status, 200);
  assert.equal(result.body.agencyWalletCoins, '15');
  assert.equal(result.body.personalCoins, '525');
  assert.equal(seats[0]!.agencyWalletCoins, 100n);
  assert.equal(users[1]!.totalRecharge, 0);
  assert.deepEqual(vipCalls, []);
  assert.equal(transactions[0]!.type, 'AGENCY_WALLET_WITHDRAW');
});

test('withdraw refuses insufficient funds and another agency', async () => {
  assert.equal((await call(withdrawAgencyWallet, { amount: 101 })).status, 409);
  assert.equal((await call(withdrawAgencyWallet, { amount: 25, agencyId: 8 })).status, 403);
  assert.equal(seats[0]!.agencyWalletCoins, 100n);
});

for (const freeze of ['agency', 'global']) {
  test(`withdraw refuses ${freeze} freeze`, async () => {
    if (freeze === 'agency') agency.walletFrozen = true;
    else globalFreeze = 'true';
    assert.equal((await call(withdrawAgencyWallet, { amount: 25 })).status, 403);
    assert.equal(seats[0]!.agencyWalletCoins, 100n);
    assert.equal(users[0]!.coinsBalance, 500);
  });
}

test('invalid amounts are rejected before any debit', async () => {
  for (const amount of [-1, 0, 1.5, 'NaN', Infinity, 2_147_483_648]) {
    assert.equal((await call(withdrawAgencyWallet, { amount })).status, 400);
  }
  assert.equal(seats[0]!.agencyWalletCoins, 100n);
});

test('a later debit cannot spend coins already sold', async () => {
  assert.equal((await call(agencyTransferCoins, { toUserId: 30, amount: 75 })).status, 200);
  assert.equal((await call(withdrawAgencyWallet, { amount: 50 })).status, 409);
  assert.equal(seats[0]!.agencyWalletCoins, 25n);
  assert.equal(users[0]!.coinsBalance, 500);
  assert.equal(transactions.length, 1);
});

test('overflow or ledger failure rolls back the debit', async () => {
  users[0]!.coinsBalance = 2_147_483_647;
  assert.equal((await call(withdrawAgencyWallet, { amount: 25 })).status, 400);
  assert.equal(seats[0]!.agencyWalletCoins, 100n);
  failLedger = true;
  assert.equal((await call(agencyTransferCoins, { toUserId: 30, amount: 25 })).status, 500);
  assert.equal(seats[0]!.agencyWalletCoins, 100n);
  assert.equal(users[2]!.coinsBalance, 500);
});

test('balance exposes both wallets and the effective freeze', async () => {
  globalFreeze = 'true';
  const result = await call(myAgencyBalance, {});
  assert.equal(result.body.agencyWalletCoins, '100');
  assert.equal(result.body.personalCoins, '500');
  assert.equal(result.body.balanceCoins, '100');
  assert.equal(result.body.frozen, true);
});

test('admin topup credits the owner seat even when frozen', async () => {
  agency.walletFrozen = true;
  globalFreeze = 'true';
  await db.$transaction(tx => adjustOwnerAgencyWallet(tx, 7, 25, 99));
  assert.equal(seats[0]!.agencyWalletCoins, 125n);
  assert.equal(users[0]!.coinsBalance, 500);
  assert.equal(users[0]!.totalRecharge, 0);
  assert.equal(transactions[0]!.type, 'AGENCY_WALLET_ADJUST');
});

test('admin withdraw debits the owner seat and never goes below zero', async () => {
  const before = seats[0]!.agencyWalletCoins;
  await db.$transaction(tx => adjustOwnerAgencyWallet(tx, 7, -25, 99));
  assert.equal(seats[0]!.agencyWalletCoins, before - 25n);
  await assert.rejects(db.$transaction(tx => adjustOwnerAgencyWallet(tx, 7, -(Number(before) + 1), 99)), { status: 409 });
  assert.equal(seats[0]!.agencyWalletCoins, before - 25n);
});

test('recipient eligibility filters role, agency type and approval', async () => {
  for (const [role, type, status, expected] of [
    ['OWNER', 'CHARGING', 'approved', true], ['BRANCH', 'CHARGING', 'approved', true],
    ['MEMBER', 'CHARGING', 'approved', false], ['OWNER', 'HOSTING', 'approved', false],
    ['OWNER', 'CHARGING', 'pending', false], ['OWNER', 'CHARGING', 'rejected', false],
  ] as const) {
    seats[1] = { id: 2, agencyId: 8, userId: 20, role, agencyWalletCoins: 0n, agency: { type, status } };
    assert.deepEqual((await call(chargingRecipient, {}, 10, { userId: 20 })).body, { isChargingAgent: expected });
    const result = await call(agencyTransferCoins, { toUserId: 20, amount: 1, wallet: 'personal' });
    assert.equal(result.status, 200);
    assert.equal(result.body.wallet, expected ? 'agency' : 'personal');
  }
  assert.equal((await call(chargingRecipient, {}, 10, { userId: 'bad' })).status, 400);
  assert.deepEqual((await call(chargingRecipient, {}, 10, { userId: 999 })).body, { isChargingAgent: false });
});

test('recipient selection prefers OWNER then oldest seat', async () => {
  for (const [id, role, joinedAt] of [[3, 'BRANCH', 1], [4, 'OWNER', 3], [5, 'OWNER', 2]] as const) {
    seats.push({ id, agencyId: id + 10, userId: 30, role, joinedAt, agencyWalletCoins: 0n,
      agency: { type: 'CHARGING', status: 'approved' } });
  }
  const result = await call(agencyTransferCoins, { toUserId: 30, amount: 25, wallet: 'personal' });
  assert.equal(result.body.wallet, 'agency');
  assert.deepEqual(seats.slice(2).map(r => r.agencyWalletCoins), [0n, 0n, 25n]);
});
