import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { makeDb } from './fakeDb';
import {
  CpError,
  assertCpUnlocked,
  computeCpLevel,
  confirmCpUnlock,
  getCpUnlockStatus,
  readCpSettings,
  resolveCpUnlockPolicy,
} from '../../services/cpUnlock.service';

/**
 * صلاحيات فتح CP — the server-side permission check, the quoted fee, the
 * atomic deduction and the insufficient-balance path. Runs against the
 * in-memory fake; no database needed.
 */

let db: ReturnType<typeof makeDb>;

const ALICE = 10; // 500 coins
const BOB = 11; // 40 coins
const ADMIN = 1;

beforeEach(() => {
  db = makeDb();
  db.seed('user', [
    { id: ADMIN, name: 'admin', displayId: 100001, coinsBalance: 0, isAdmin: true },
    { id: ALICE, name: 'alice', displayId: 100010, coinsBalance: 500 },
    { id: BOB, name: 'bob', displayId: 100011, coinsBalance: 40 },
  ]);
});

const setPolicy = (mode: 'free' | 'fee', fee = 0) =>
  db.seed('appSetting', [
    { key: 'cp_unlock_mode', value: mode },
    { key: 'cp_unlock_fee_coins', value: String(fee) },
  ]);

describe('policy resolution (server-side)', () => {
  test('default (no settings, no grant) is free — today\'s behaviour', async () => {
    const p = await resolveCpUnlockPolicy(ALICE, db);
    assert.equal(p.mode, 'free');
    assert.equal(p.feeCoins, 0);
    assert.equal(p.policySource, 'system');
  });

  test('system fee policy applies to a user without a grant', async () => {
    setPolicy('fee', 300);
    const p = await resolveCpUnlockPolicy(ALICE, db);
    assert.deepEqual([p.mode, p.feeCoins, p.policySource], ['fee', 300, 'system']);
  });

  test('a FREE grant overrides a system fee ("فتح CP مجانًا")', async () => {
    setPolicy('fee', 300);
    db.seed('cpUnlockGrant', [{ userId: ALICE, mode: 'FREE', feeCoins: 0, grantedById: ADMIN }]);
    const p = await resolveCpUnlockPolicy(ALICE, db);
    assert.deepEqual([p.mode, p.feeCoins, p.policySource], ['free', 0, 'grant']);
  });

  test('a FEE grant overrides a free system policy with its own price ("فتح CP برسوم")', async () => {
    setPolicy('free');
    db.seed('cpUnlockGrant', [{ userId: ALICE, mode: 'FEE', feeCoins: 120, grantedById: ADMIN }]);
    const p = await resolveCpUnlockPolicy(ALICE, db);
    assert.deepEqual([p.mode, p.feeCoins, p.policySource], ['fee', 120, 'grant']);
    // the grant is per user: Bob still sees the system policy
    const pb = await resolveCpUnlockPolicy(BOB, db);
    assert.deepEqual([pb.mode, pb.feeCoins, pb.policySource], ['free', 0, 'system']);
  });

  test('settings parsing clamps garbage to safe defaults', async () => {
    db.seed('appSetting', [
      { key: 'cp_unlock_mode', value: 'FEE' },
      { key: 'cp_unlock_fee_coins', value: '-5' },
      { key: 'cp_level_max', value: 'abc' },
    ]);
    const s = await readCpSettings(db);
    assert.equal(s.unlockMode, 'fee');
    assert.equal(s.unlockFeeCoins, 0);
    assert.equal(s.levelMax, 5);
  });
});

describe('fee shown before confirmation', () => {
  test('status quotes the fee, the balance and the shortfall without deducting', async () => {
    setPolicy('fee', 300);
    const s = await getCpUnlockStatus(BOB, db);
    assert.equal(s.unlocked, false);
    assert.equal(s.feeCoins, 300);
    assert.equal(s.balance, 40);
    assert.equal(s.shortfall, 260);
    const bob = await db.user.findUnique({ where: { id: BOB } });
    assert.equal(bob.coinsBalance, 40, 'nothing deducted by a status read');
  });

  test('status for an unlocked user quotes no fee', async () => {
    setPolicy('fee', 300);
    db.seed('cpUnlock', [{ userId: ALICE, paidCoins: 0, source: 'legacy' }]);
    const s = await getCpUnlockStatus(ALICE, db);
    assert.equal(s.unlocked, true);
    assert.equal(s.feeCoins, 0);
    assert.equal(s.unlockSource, 'legacy');
  });
});

describe('confirm: atomic deduction', () => {
  test('fee is deducted once, a CP_UNLOCK_FEE transaction is written, unlock recorded', async () => {
    setPolicy('fee', 300);
    const r = await confirmCpUnlock(ALICE, db);
    assert.equal(r.alreadyUnlocked, false);
    assert.equal(r.paidCoins, 300);
    assert.equal(r.balance, 200);
    assert.equal(r.source, 'fee_policy');
    const alice = await db.user.findUnique({ where: { id: ALICE } });
    assert.equal(alice.coinsBalance, 200);
    const trx = db.rows('transaction');
    assert.equal(trx.length, 1);
    const t = trx[0]!;
    assert.equal(t.type, 'CP_UNLOCK_FEE');
    assert.equal(t.amountCoins, -300);
    assert.equal(t.status, 'completed');
    const unlock = await db.cpUnlock.findUnique({ where: { userId: ALICE } });
    assert.equal(unlock.paidCoins, 300);
    assert.equal(unlock.transactionId, t.id);
  });

  test('a second confirm (double tap) is idempotent and charges nothing', async () => {
    setPolicy('fee', 300);
    await confirmCpUnlock(ALICE, db);
    const again = await confirmCpUnlock(ALICE, db);
    assert.equal(again.alreadyUnlocked, true);
    const alice = await db.user.findUnique({ where: { id: ALICE } });
    assert.equal(alice.coinsBalance, 200);
    assert.equal(db.rows('transaction').length, 1);
  });

  test('insufficient balance: 402 with the shortfall, NOTHING deducted or recorded', async () => {
    setPolicy('fee', 300);
    await assert.rejects(
      () => confirmCpUnlock(BOB, db),
      (e: any) => {
        assert.ok(e instanceof CpError);
        assert.equal(e.code, 'INSUFFICIENT_COINS');
        assert.equal(e.status, 402);
        assert.equal(e.data?.shortfall, 260);
        assert.equal(e.data?.feeCoins, 300);
        return true;
      },
    );
    const bob = await db.user.findUnique({ where: { id: BOB } });
    assert.equal(bob.coinsBalance, 40);
    assert.equal(db.rows('transaction').length, 0);
    assert.equal(db.rows('cpUnlock').length, 0);
  });

  test('free policy: confirm records the unlock at zero cost', async () => {
    setPolicy('free');
    const r = await confirmCpUnlock(BOB, db);
    assert.equal(r.paidCoins, 0);
    assert.equal(r.source, 'free_policy');
    assert.equal(db.rows('transaction').length, 0);
  });

  test('FEE grant uses the grant price and records who granted it', async () => {
    setPolicy('free');
    db.seed('cpUnlockGrant', [{ userId: ALICE, mode: 'FEE', feeCoins: 120, grantedById: ADMIN }]);
    const r = await confirmCpUnlock(ALICE, db);
    assert.equal(r.paidCoins, 120);
    assert.equal(r.source, 'grant_fee');
    const unlock = await db.cpUnlock.findUnique({ where: { userId: ALICE } });
    assert.equal(unlock.grantedById, ADMIN);
  });
});

describe('the gate on POST /cp/requests', () => {
  test('free: passes and auto-records the unlock (old app builds keep working)', async () => {
    setPolicy('free');
    await assertCpUnlocked(BOB, db);
    assert.equal(db.rows('cpUnlock').length, 1);
    assert.equal(db.rows('cpUnlock')[0]?.source, 'free_policy');
  });

  test('fee, not yet paid: 403 CP_LOCKED carrying the fee — nothing deducted', async () => {
    setPolicy('fee', 300);
    await assert.rejects(
      () => assertCpUnlocked(ALICE, db),
      (e: any) => e instanceof CpError && e.code === 'CP_LOCKED' && e.status === 403 && e.data?.feeCoins === 300,
    );
    const alice = await db.user.findUnique({ where: { id: ALICE } });
    assert.equal(alice.coinsBalance, 500);
  });

  test('fee, already paid: passes', async () => {
    setPolicy('fee', 300);
    await confirmCpUnlock(ALICE, db);
    await assertCpUnlocked(ALICE, db);
  });

  test('a locked user with a FREE grant passes', async () => {
    setPolicy('fee', 300);
    db.seed('cpUnlockGrant', [{ userId: BOB, mode: 'FREE', feeCoins: 0, grantedById: ADMIN }]);
    await assertCpUnlocked(BOB, db);
    assert.equal(db.rows('cpUnlock')[0]?.source, 'grant_free');
  });
});

describe('CP level', () => {
  const cfg = { unlockMode: 'free' as const, unlockFeeCoins: 0, levelStepCoins: 0, levelMax: 5, levelNames: ['a', 'b', 'c', 'd', 'e'] };
  const day = 86_400_000;

  test('step 0 keeps the legacy days ladder (no level moves on deploy)', () => {
    const now = Date.now();
    assert.equal(computeCpLevel({ cpValue: 999999, createdAt: new Date(now) }, cfg, now).level, 1);
    assert.equal(computeCpLevel({ cpValue: 0, createdAt: new Date(now - 8 * day) }, cfg, now).level, 2);
    assert.equal(computeCpLevel({ cpValue: 0, createdAt: new Date(now - 400 * day) }, cfg, now).level, 5);
    assert.equal(computeCpLevel({ cpValue: 0, createdAt: new Date(now - 400 * day) }, cfg, now).basis, 'days');
  });

  test('"قيمة رفع مستوى CP": level = 1 + floor(value / step), capped', () => {
    const c = { ...cfg, levelStepCoins: 1000 };
    const now = Date.now();
    const r = computeCpLevel({ cpValue: 2500, createdAt: new Date(now) }, c, now);
    assert.equal(r.level, 3);
    assert.equal(r.levelName, 'c');
    assert.equal(r.nextLevelAt, 3000);
    assert.equal(r.basis, 'coins');
    assert.equal(computeCpLevel({ cpValue: 99_000, createdAt: new Date(now) }, c, now).level, 5);
  });

  test('admin override pins the level', () => {
    const c = { ...cfg, levelStepCoins: 1000 };
    const r = computeCpLevel({ cpValue: 0, createdAt: new Date(), levelOverride: 4 }, c);
    assert.equal(r.level, 4);
    assert.equal(r.basis, 'override');
  });
});
