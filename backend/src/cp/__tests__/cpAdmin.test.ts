import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { makeDb } from './fakeDb';
import { CpError, resolveCpUnlockPolicy } from '../../services/cpUnlock.service';
import { recordAdminAudit } from '../../services/adminAudit.service';
import {
  adminDeletePair,
  adminLockCp,
  adminUnlockCp,
  adminUpdatePair,
  canUseProfileBackground,
  createBackground,
  deleteBackground,
  getUserCpOverview,
  grantBackground,
  grantCpUnlock,
  listUserBackgrounds,
  revokeBackground,
  revokeCpGrant,
  updateBackground,
  updateCpPolicy,
} from '../../services/cpAdmin.service';

/**
 * لوحة تحكم CP والخلفيات — grants / revokes and their audit rows, backgrounds
 * CRUD / grant / revoke without touching anyone else's ownership, and the
 * guarantees that app-side calls cannot move ownership, coins or CP values.
 * Runs against the in-memory fake; no database needed.
 */

let db: ReturnType<typeof makeDb>;

const ADMIN = 1;
const ALICE = 10; // 500 coins
const BOB = 11; // 40 coins
const CAROL = 12;
const ctx = { adminId: ADMIN, ip: '10.0.0.1' };

const BG_URL = 'https://cdn.example/uploads/sunset.png';
const BG2_URL = 'https://cdn.example/uploads/stars.mp4';

beforeEach(() => {
  db = makeDb();
  db.seed('user', [
    { id: ADMIN, name: 'admin', displayId: 100001, coinsBalance: 0, isAdmin: true },
    { id: ALICE, name: 'alice', displayId: 100010, coinsBalance: 500, profileBgUrl: null },
    { id: BOB, name: 'bob', displayId: 100011, coinsBalance: 40, profileBgUrl: null },
    { id: CAROL, name: 'carol', displayId: 100012, coinsBalance: 0, profileBgUrl: null },
  ]);
});

const audit = (action?: string) => db.rows('adminAuditLog').filter((r) => !action || r.action === action);
const coins = () => db.rows('user').map((u) => [u.id, u.coinsBalance]);

// ---------------------------------------------------------------------------
// CP grants, unlock state, policy, pairs
// ---------------------------------------------------------------------------

describe('CP grants: history and audit', () => {
  test('grant FREE writes the grant, a GRANT history row and a CP_GRANT_FREE audit row', async () => {
    await grantCpUnlock(ALICE, { mode: 'FREE', note: 'vip' }, ctx, db);
    const g = db.rows('cpUnlockGrant');
    assert.equal(g.length, 1);
    assert.deepEqual([g[0]!.userId, g[0]!.mode, g[0]!.feeCoins, g[0]!.grantedById], [ALICE, 'FREE', 0, ADMIN]);
    assert.deepEqual(db.rows('cpUnlockGrantHistory').map((h) => h.action), ['GRANT']);
    const a = audit('CP_GRANT_FREE');
    assert.equal(a.length, 1);
    assert.equal(a[0]!.adminId, ADMIN);
    assert.equal(a[0]!.targetUserId, ALICE);
    assert.equal(a[0]!.ip, '10.0.0.1');
    assert.equal(a[0]!.before, null);
    assert.deepEqual(a[0]!.after, { mode: 'FREE', feeCoins: 0, note: 'vip' });
  });

  test('changing a grant records UPDATE with the previous values in the audit', async () => {
    await grantCpUnlock(ALICE, { mode: 'FREE' }, ctx, db);
    await grantCpUnlock(ALICE, { mode: 'FEE', feeCoins: 120 }, ctx, db);
    assert.equal(db.rows('cpUnlockGrant').length, 1, 'still one live grant per user');
    assert.deepEqual(db.rows('cpUnlockGrantHistory').map((h) => h.action), ['GRANT', 'UPDATE']);
    const a = audit('CP_GRANT_FEE')[0]!;
    assert.deepEqual(a.before, { mode: 'FREE', feeCoins: 0, note: null });
    assert.deepEqual(a.after, { mode: 'FEE', feeCoins: 120, note: null });
  });

  test('granting never touches anyone\'s coins', async () => {
    const before = coins();
    await grantCpUnlock(ALICE, { mode: 'FEE', feeCoins: 120 }, ctx, db);
    assert.deepEqual(coins(), before);
  });

  test('an invalid fee is refused and nothing is written', async () => {
    await assert.rejects(
      () => grantCpUnlock(ALICE, { mode: 'FEE', feeCoins: -5 }, ctx, db),
      (e: any) => e instanceof CpError && e.code === 'INVALID_FEE',
    );
    assert.equal(db.rows('cpUnlockGrant').length, 0);
    assert.equal(audit().length, 0);
  });

  test('revoke deletes the grant, keeps history (REVOKE) and audits the old values', async () => {
    await grantCpUnlock(ALICE, { mode: 'FEE', feeCoins: 120 }, ctx, db);
    await revokeCpGrant(ALICE, ctx, db);
    assert.equal(db.rows('cpUnlockGrant').length, 0);
    assert.deepEqual(db.rows('cpUnlockGrantHistory').map((h) => h.action), ['GRANT', 'REVOKE']);
    const a = audit('CP_GRANT_REVOKE')[0]!;
    assert.deepEqual(a.before, { mode: 'FEE', feeCoins: 120, note: null });
    assert.equal(a.after, null);
    // back on the system policy
    const p = await resolveCpUnlockPolicy(ALICE, db);
    assert.equal(p.policySource, 'system');
  });

  test('revoking a grant that does not exist is a 404 with no audit row', async () => {
    await assert.rejects(
      () => revokeCpGrant(BOB, ctx, db),
      (e: any) => e instanceof CpError && e.status === 404,
    );
    assert.equal(audit().length, 0);
    assert.equal(db.rows('cpUnlockGrantHistory').length, 0);
  });
});

describe('admin opens / closes CP for one user', () => {
  test('open is free, audited once, and idempotent', async () => {
    const before = coins();
    const r1 = await adminUnlockCp(BOB, ctx, db);
    const r2 = await adminUnlockCp(BOB, ctx, db);
    assert.equal(r1.alreadyUnlocked, false);
    assert.equal(r2.alreadyUnlocked, true);
    assert.equal(db.rows('cpUnlock').length, 1);
    assert.equal(db.rows('cpUnlock')[0]!.source, 'admin');
    assert.equal(db.rows('cpUnlock')[0]!.paidCoins, 0);
    assert.equal(audit('CP_UNLOCK_ADMIN').length, 1);
    assert.deepEqual(coins(), before, 'no coins moved');
  });

  test('close removes the unlock but keeps existing pairs; no refund', async () => {
    db.seed('cpUnlock', [{ userId: ALICE, paidCoins: 300, source: 'fee_policy' }]);
    db.seed('cpPair', [{ userAId: ALICE, userBId: BOB, cpValue: 50, giftId: 'g1' }]);
    const before = coins();
    await adminLockCp(ALICE, ctx, db);
    assert.equal(db.rows('cpUnlock').length, 0);
    assert.equal(db.rows('cpPair').length, 1);
    assert.deepEqual(coins(), before);
    assert.equal(audit('CP_LOCK_ADMIN')[0]!.before.paidCoins, 300);
  });
});

describe('system policy', () => {
  test('update writes the settings and audits before/after', async () => {
    await updateCpPolicy({ unlockMode: 'fee', unlockFeeCoins: 250, levelStepCoins: 1000 }, ctx, db);
    const s = Object.fromEntries(db.rows('appSetting').map((r) => [r.key, r.value]));
    assert.equal(s.cp_unlock_mode, 'fee');
    assert.equal(s.cp_unlock_fee_coins, '250');
    assert.equal(s.cp_level_step_coins, '1000');
    const a = audit('CP_POLICY_UPDATE')[0]!;
    assert.equal(a.before.unlockMode, 'free');
    assert.equal(a.after.unlockMode, 'fee');
    assert.equal(a.after.unlockFeeCoins, 250);
  });

  test('an invalid mode is refused before anything is written', async () => {
    await assert.rejects(() => updateCpPolicy({ unlockMode: 'paid' as any, unlockFeeCoins: 5 }, ctx, db), CpError);
    assert.equal(db.rows('appSetting').length, 0);
    assert.equal(audit().length, 0);
  });
});

describe('pairs', () => {
  beforeEach(() => {
    db.seed('cpPair', [
      { id: 7, userAId: ALICE, userBId: BOB, cpValue: 100, levelOverride: null, giftId: 'g1', createdAt: new Date() },
      { id: 8, userAId: ALICE, userBId: CAROL, cpValue: 0, levelOverride: null, giftId: 'g1', createdAt: new Date() },
    ]);
  });

  test('editing one pair changes only that pair and is audited', async () => {
    await adminUpdatePair(7, { cpValue: 900, levelOverride: 4 }, ctx, db);
    const [p7, p8] = [db.rows('cpPair').find((p) => p.id === 7)!, db.rows('cpPair').find((p) => p.id === 8)!];
    assert.deepEqual([p7.cpValue, p7.levelOverride], [900, 4]);
    assert.deepEqual([p8.cpValue, p8.levelOverride], [0, null]);
    const a = audit('CP_PAIR_UPDATE')[0]!;
    assert.deepEqual([a.before.cpValue, a.after.cpValue, a.after.levelOverride], [100, 900, 4]);
  });

  test('a negative value is refused', async () => {
    await assert.rejects(() => adminUpdatePair(7, { cpValue: -1 }, ctx, db), CpError);
    assert.equal(db.rows('cpPair').find((p) => p.id === 7)!.cpValue, 100);
  });

  test('dissolving one pair leaves the other and is audited', async () => {
    await adminDeletePair(7, ctx, db);
    assert.deepEqual(db.rows('cpPair').map((p) => p.id), [8]);
    assert.equal(audit('CP_PAIR_DELETE')[0]!.before.userBId, BOB);
  });

  test('overview reports the server level and the pinned level', async () => {
    await adminUpdatePair(7, { levelOverride: 3 }, ctx, db);
    const o = await getUserCpOverview(ALICE, db);
    const p7 = o.pairs.find((p: any) => p.pairId === 7)!;
    assert.equal(p7.level, 3);
    assert.equal(p7.levelBasis, 'override');
    assert.equal(o.pairs.length, 2);
  });
});

describe('audit writer', () => {
  test('a failing audit write never breaks the admin action', async () => {
    const broken = { adminAuditLog: { create: async () => { throw new Error('db down'); } } };
    const origError = console.error;
    console.error = () => {};
    try {
      await assert.doesNotReject(() => recordAdminAudit({ adminId: ADMIN, action: 'CP_GRANT_FREE' }, broken));
    } finally {
      console.error = origError;
    }
  });
});

// ---------------------------------------------------------------------------
// Backgrounds
// ---------------------------------------------------------------------------

const seedBackgrounds = () => {
  db.seed('item', [
    { id: 'bgA', name: 'Sunset', type: 'PROFILE_BACKGROUND', assetUrl: BG_URL, priceCoins: 500, isPurchasable: true, durationDays: null },
    { id: 'bgB', name: 'Stars', type: 'PROFILE_BACKGROUND', assetUrl: BG2_URL, priceCoins: 200, isPurchasable: true, durationDays: 30 },
    { id: 'frame1', name: 'Gold frame', type: 'FRAME', assetUrl: 'https://cdn.example/f.png', priceCoins: 100, isPurchasable: true, durationDays: null },
  ]);
};

describe('backgrounds: create / update', () => {
  test('create: "free" forces price 0 and the row is audited', async () => {
    const bg = await createBackground({ name: 'Ocean', assetUrl: 'u', priceCoins: 999, isFree: true }, ctx, db);
    assert.equal(bg.priceCoins, 0);
    assert.equal(bg.isFree, true);
    assert.equal(db.rows('item')[0]!.type, 'PROFILE_BACKGROUND');
    assert.equal(audit('BG_CREATE').length, 1);
  });

  test('create without a name is refused', async () => {
    await assert.rejects(() => createBackground({ name: '  ', assetUrl: 'u' }, ctx, db), CpError);
    assert.equal(db.rows('item').length, 0);
  });

  test('update changes price and duration, audits before/after', async () => {
    seedBackgrounds();
    await updateBackground('bgA', { priceCoins: 750, durationDays: 7 }, ctx, db);
    const a = db.rows('item').find((i) => i.id === 'bgA')!;
    assert.deepEqual([a.priceCoins, a.durationDays], [750, 7]);
    const log = audit('BG_UPDATE')[0]!;
    assert.deepEqual([log.before.priceCoins, log.after.priceCoins], [500, 750]);
  });

  test('update refuses an item that is not a background', async () => {
    seedBackgrounds();
    await assert.rejects(
      () => updateBackground('frame1', { priceCoins: 1 }, ctx, db),
      (e: any) => e instanceof CpError && e.status === 404,
    );
    assert.equal(db.rows('item').find((i) => i.id === 'frame1')!.priceCoins, 100);
  });
});

describe('backgrounds: grant / revoke touch only the addressed user', () => {
  beforeEach(() => {
    seedBackgrounds();
    db.seed('userItem', [
      { userId: BOB, itemId: 'bgA', expiresAt: null, isActive: true, acquiredAt: new Date() },
      { userId: CAROL, itemId: 'bgA', expiresAt: null, isActive: true, acquiredAt: new Date() },
      { userId: CAROL, itemId: 'frame1', expiresAt: null, isActive: true, acquiredAt: new Date() },
    ]);
    // Bob and Carol both have Sunset on their page.
    db.rows('user').find((u) => u.id === BOB)!.profileBgUrl = BG_URL;
    db.rows('user').find((u) => u.id === CAROL)!.profileBgUrl = BG_URL;
  });

  const owns = (userId: number, itemId: string) => db.rows('userItem').some((r) => r.userId === userId && r.itemId === itemId);

  test('grant creates exactly one row for the target, charges nothing', async () => {
    const before = coins();
    await grantBackground('bgA', ALICE, ctx, db);
    assert.ok(owns(ALICE, 'bgA'));
    assert.equal(db.rows('userItem').length, 4);
    assert.deepEqual(coins(), before);
    const a = audit('BG_GRANT')[0]!;
    assert.equal(a.targetUserId, ALICE);
    assert.equal(a.targetId, 'bgA');
  });

  test('re-granting a permanent background is refused (409)', async () => {
    await assert.rejects(
      () => grantBackground('bgA', BOB, ctx, db),
      (e: any) => e instanceof CpError && e.code === 'ALREADY_OWNED' && e.status === 409,
    );
  });

  test('re-granting a timed background extends it', async () => {
    const first = await grantBackground('bgB', ALICE, ctx, db);
    const second = await grantBackground('bgB', ALICE, ctx, db);
    const days = (new Date(second.expiresAt).getTime() - new Date(first.expiresAt).getTime()) / 86_400_000;
    assert.ok(Math.abs(days - 30) < 0.01, `extended by ~30 days, got ${days}`);
    assert.equal(db.rows('userItem').filter((r) => r.userId === ALICE).length, 1);
  });

  test('revoke removes ONE user\'s copy, un-equips only him, and keeps the reason', async () => {
    await revokeBackground('bgA', BOB, ctx, db, 'chargeback');
    assert.equal(owns(BOB, 'bgA'), false);
    assert.equal(owns(CAROL, 'bgA'), true, "Carol's copy is untouched");
    assert.equal(owns(CAROL, 'frame1'), true);
    assert.equal(db.rows('user').find((u) => u.id === BOB)!.profileBgUrl, null);
    assert.equal(db.rows('user').find((u) => u.id === CAROL)!.profileBgUrl, BG_URL, "Carol's page is untouched");
    const a = audit('BG_REVOKE')[0]!;
    assert.equal(a.targetUserId, BOB);
    assert.deepEqual(a.after, { reason: 'chargeback' });
  });

  test('revoking something the user does not own is a 404 and changes nothing', async () => {
    const before = db.rows('userItem').length;
    await assert.rejects(
      () => revokeBackground('bgB', BOB, ctx, db),
      (e: any) => e instanceof CpError && e.status === 404,
    );
    assert.equal(db.rows('userItem').length, before);
    assert.equal(audit().length, 0);
  });

  test('the per-user list marks the equipped background', async () => {
    const out = await listUserBackgrounds(BOB, db);
    assert.equal(out.backgrounds.length, 1, 'only backgrounds, not frames');
    assert.equal(out.backgrounds[0]!.equipped, true);
  });

  test('delete removes every copy of THAT background only, and audits the owner count', async () => {
    await deleteBackground('bgA', ctx, db);
    assert.equal(db.rows('item').some((i) => i.id === 'bgA'), false);
    assert.equal(db.rows('userItem').some((r) => r.itemId === 'bgA'), false);
    assert.equal(owns(CAROL, 'frame1'), true, 'other products untouched');
    assert.equal(db.rows('user').find((u) => u.id === BOB)!.profileBgUrl, null);
    assert.equal(audit('BG_DELETE')[0]!.before.ownerCount, 2);
  });
});

// ---------------------------------------------------------------------------
// App-side calls cannot change ownership, coins or CP values
// ---------------------------------------------------------------------------

describe('app side: PUT /users/me cannot paint a store background it does not own', () => {
  beforeEach(() => {
    seedBackgrounds();
  });

  test('own uploaded picture (not a store asset) is allowed', async () => {
    assert.equal(await canUseProfileBackground(ALICE, 'https://cdn.example/uploads/my-selfie.jpg', db), true);
  });

  test('clearing the background is allowed', async () => {
    assert.equal(await canUseProfileBackground(ALICE, '', db), true);
  });

  test('a store background he does not own is refused', async () => {
    assert.equal(await canUseProfileBackground(ALICE, BG_URL, db), false);
  });

  test('a store background he owns is allowed; an expired one is not', async () => {
    db.seed('userItem', [
      { userId: ALICE, itemId: 'bgA', expiresAt: null, isActive: true },
      { userId: BOB, itemId: 'bgB', expiresAt: new Date(Date.now() - 86_400_000), isActive: true },
    ]);
    assert.equal(await canUseProfileBackground(ALICE, BG_URL, db), true);
    assert.equal(await canUseProfileBackground(BOB, BG2_URL, db), false);
  });
});

describe('app side: the /cp API surface', () => {
  // Read as text: loading the router pulls in the auth stack (native bcrypt),
  // which is not needed to prove what the app is allowed to call.
  const src = readFileSync(join(__dirname, '../../routes/cp.routes.ts'), 'utf8');
  const routes = [...src.matchAll(/router\.(get|post|patch|put|delete)\(\s*'([^']+)'/g)].map((m) => `${m[1]!.toUpperCase()} ${m[2]}`);

  test('exactly the documented endpoints exist — a new write route must be reviewed here', () => {
    assert.deepEqual(routes.sort(), [
      'DELETE /partners/:userId',
      'DELETE /requests/:id',
      'GET /partners',
      'GET /partners/:userId',
      'GET /requests/pending',
      'GET /unlock/status',
      'PATCH /featured',
      'POST /requests',
      'POST /requests/:id/accept',
      'POST /requests/:id/reject',
      'POST /unlock/confirm',
    ].sort());
  });

  test('no handler reads a coin amount, a CP value, a level or an owner from the request', () => {
    // The only client inputs are the invitation (recipient, gift, quantity,
    // room) and the featured partner id. Prices and fees come from the DB.
    const bodyFields = [...src.matchAll(/const \{([^}]*)\} = req\.body/g)]
      .flatMap((m) => (m[1] ?? '').split(','))
      .map((s) => s.trim())
      .filter(Boolean);
    assert.deepEqual(bodyFields.sort(), ['giftId', 'quantity', 'recipientId', 'roomId']);
    for (const forbidden of ['cpValue', 'levelOverride', 'coinsBalance', 'feeCoins', 'userItem', 'priceCoins']) {
      assert.ok(!new RegExp(`req\\.body[^\\n]*${forbidden}`).test(src), `cp.routes must not read ${forbidden} from the body`);
    }
  });

  test('POST /unlock/confirm takes nothing from the client — the fee is the server\'s quote', () => {
    const handler = src.slice(src.indexOf("router.post('/unlock/confirm'"), src.indexOf("router.patch('/featured'"));
    assert.ok(handler.includes('confirmCpUnlock(userId)'));
    assert.ok(!handler.includes('req.body'));
  });
});
