// «بالنسبه لوكيل الشحن لو اشتري تارجيت وحب يبدله زي ما احنا بنص القيمه لكن ينزل
// في رصيد وكالة الشحن وليس المحفظه»
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: {} });
stub('lib/prisma', { prisma: {} });
stub('services/notification.service', { createNotification: async () => {} });
for (const name of ['vip', 'agencyReward', 'broadcast', 'hostTarget', 'targetMovement']) stub(`services/${name}.service`, {});
const { creditTargetSwap, ChargingWalletFrozenError }: typeof import('../agency.controller') = require('../agency.controller');

type Row = Record<string, any>;
function fakeTx(opts: { seat?: Row; frozen?: boolean }) {
  const user: Row = { id: 7, coinsBalance: 1000 };
  const ledger: Row[] = [];
  const seat = opts.seat ? { ...opts.seat } : null;
  const tx: any = {
    agencyMember: {
      findFirst: async ({ where }: Row) => {
        assert.deepEqual(where.agency, { type: 'CHARGING', status: 'approved' });
        return seat && seat.userId === where.userId ? seat : null;
      },
      update: async ({ data }: Row) => { seat!.agencyWalletCoins += data.agencyWalletCoins.increment; return seat; },
    },
    appSetting: { findUnique: async () => ({ value: opts.frozen ? 'true' : '' }) },
    chargingAgency: { findUnique: async () => ({ walletFrozen: false }) },
    transaction: { create: async ({ data }: Row) => ledger.push(data) },
    user: {
      update: async ({ data }: Row) => { user.coinsBalance += data.coinsBalance.increment; return user; },
      findUniqueOrThrow: async () => user,
    },
  };
  return { tx, user, ledger, seat };
}

test('a charging agent swaps into his agency wallet, not his personal wallet', async () => {
  const { tx, user, ledger, seat } = fakeTx({ seat: { id: 3, userId: 7, agencyId: 9, role: 'OWNER', agencyWalletCoins: 500n } });
  const r = await creditTargetSwap(tx, 7, 400);
  assert.equal(r.agencyWalletCoins, '900');
  assert.equal(seat!.agencyWalletCoins, 900n);
  assert.equal(user.coinsBalance, 1000, 'personal wallet untouched');
  assert.equal(ledger[0]!.type, 'AGENCY_WALLET_TARGET_CONVERT');
  assert.equal(ledger[0]!.agencyId, 9);
});

test('anyone else still gets the coins on the personal wallet', async () => {
  const { tx, user, ledger } = fakeTx({});
  const r = await creditTargetSwap(tx, 7, 400);
  assert.equal(r.agencyWalletCoins, null);
  assert.equal(user.coinsBalance, 1400);
  assert.equal(ledger.length, 0);
});

test('frozen charging wallets refuse the swap', async () => {
  const { tx, user } = fakeTx({ seat: { id: 3, userId: 7, agencyId: 9, role: 'BRANCH', agencyWalletCoins: 0n }, frozen: true });
  await assert.rejects(creditTargetSwap(tx, 7, 400), ChargingWalletFrozenError);
  assert.equal(user.coinsBalance, 1000);
});
