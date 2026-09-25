import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { makeDb } from './fakeDb';
import { CpError } from '../../services/cpUnlock.service';
import {
  cpPointsFor,
  isCpGift,
  pinFeaturedIfUnset,
  reassignFeaturedAfterRemoval,
  recordCpGiftValue,
  releaseCpGiftEvent,
  reserveCpGiftEvent,
} from '../../services/cpGift.service';
import { adminDeletePair, getUserCpOverview, updateCpGift } from '../../services/cpAdmin.service';

/**
 * هدايا CP ← مستوى CP, and "مستخدم CP الظاهر" never replaced by the newest
 * pair. Runs against the in-memory fake; no database needed.
 */

let db: ReturnType<typeof makeDb>;

const ADMIN = 1;
const A = 10;
const B = 11;
const C = 12;
const ctx = { adminId: ADMIN, ip: '10.0.0.1' };

beforeEach(() => {
  db = makeDb();
  db.seed('user', [
    { id: ADMIN, name: 'admin', displayId: 100001, cpFeaturedPartnerId: null },
    { id: A, name: 'A', displayId: 100010, cpFeaturedPartnerId: null },
    { id: B, name: 'B', displayId: 100011, cpFeaturedPartnerId: null },
    { id: C, name: 'C', displayId: 100012, cpFeaturedPartnerId: null },
  ]);
  db.seed('gift', [
    { id: 'ring', name: 'Ring', nameAr: 'خاتم', category: 'cp', isActive: true, coinCost: 1000, cpLevelPoints: 250 },
    { id: 'rose', name: 'Rose', nameAr: 'وردة', category: 'cp', isActive: true, coinCost: 100, cpLevelPoints: null },
    { id: 'car', name: 'Car', category: 'luxury', isActive: true, coinCost: 5000, cpLevelPoints: null },
  ]);
});

const featured = (id: number) => db.rows('user').find((u) => u.id === id)!.cpFeaturedPartnerId;
const pair = (id: number) => db.rows('cpPair').find((p) => p.id === id)!;

// ---------------------------------------------------------------------------

describe('which gifts raise CP, and by how much', () => {
  test('only an active gift in the cp list counts', () => {
    assert.equal(isCpGift({ coinCost: 1, category: 'cp', isActive: true }), true);
    assert.equal(isCpGift({ coinCost: 1, category: 'CP', isActive: true }), true);
    assert.equal(isCpGift({ coinCost: 1, category: 'cp', isActive: false }), false, 'disabled in the dashboard');
    assert.equal(isCpGift({ coinCost: 1, category: 'luxury', isActive: true }), false);
    assert.equal(isCpGift(null), false);
  });

  test('the gift\'s own "رفع مستوى CP" × quantity; unset falls back to its price', () => {
    assert.equal(cpPointsFor({ coinCost: 1000, cpLevelPoints: 250 }, 3), 750);
    assert.equal(cpPointsFor({ coinCost: 100, cpLevelPoints: null }, 2), 200);
    assert.equal(cpPointsFor({ coinCost: 100, cpLevelPoints: 0 }, 5), 0, '0 = the gift raises nothing');
    assert.equal(cpPointsFor({ coinCost: 100 }, 0), 100, 'quantity is at least 1');
  });
});

describe('recording a CP gift: logged, and never counted twice', () => {
  beforeEach(() => db.seed('cpPair', [{ id: 5, userAId: A, userBId: B, cpValue: 1000, giftId: 'ring' }]));
  const base = { pairId: 5, senderId: A, recipientId: B, giftId: 'ring', quantity: 2, source: 'partner_gift' as const };

  test('adds the points to the pair and stores the value it produced', async () => {
    const r = await recordCpGiftValue({ ...base, points: 500, giftTransactionId: 'gt-1' }, db);
    assert.equal(r.counted, true);
    assert.equal(r.cpValue, 1500);
    assert.equal(pair(5).cpValue, 1500);
    const e = db.rows('cpValueEvent');
    assert.equal(e.length, 1);
    assert.deepEqual([e[0]!.points, e[0]!.cpValueAfter, e[0]!.giftTransactionId, e[0]!.quantity], [500, 1500, 'gt-1', 2]);
  });

  test('the same gift transaction a second time adds nothing', async () => {
    await recordCpGiftValue({ ...base, points: 500, giftTransactionId: 'gt-1' }, db);
    const again = await recordCpGiftValue({ ...base, points: 500, giftTransactionId: 'gt-1' }, db);
    assert.equal(again.counted, false);
    assert.equal(pair(5).cpValue, 1500);
    assert.equal(db.rows('cpValueEvent').length, 1);
  });

  test('a resent request is caught BEFORE charging: 409 while running, the first result once done', async () => {
    const first = await reserveCpGiftEvent({ ...base, requestKey: 'tap-1' }, db);
    assert.ok(first.event, 'claimed');
    await assert.rejects(
      () => reserveCpGiftEvent({ ...base, requestKey: 'tap-1' }, db),
      (e: any) => e instanceof CpError && e.code === 'DUPLICATE_REQUEST' && e.status === 409,
    );
    await recordCpGiftValue({ ...base, points: 500, giftTransactionId: 'gt-9', eventId: first.event.id }, db);
    const resend = await reserveCpGiftEvent({ ...base, requestKey: 'tap-1' }, db);
    assert.equal(resend.duplicate.giftTransactionId, 'gt-9');
    assert.equal(pair(5).cpValue, 1500, 'counted once');
    assert.equal(db.rows('cpValueEvent').length, 1, 'the claim became the log row');
  });

  test('a failed send releases the claim so a real retry can go through', async () => {
    const first = await reserveCpGiftEvent({ ...base, requestKey: 'tap-2' }, db);
    await releaseCpGiftEvent(first.event.id, db);
    const retry = await reserveCpGiftEvent({ ...base, requestKey: 'tap-2' }, db);
    assert.ok(retry.event);
  });

  test('a different tap (key) by the same sender is a new gift', async () => {
    await reserveCpGiftEvent({ ...base, requestKey: 'tap-a' }, db);
    const b = await reserveCpGiftEvent({ ...base, requestKey: 'tap-b' }, db);
    assert.ok(b.event);
  });

  test('no key (older app) claims nothing; the gift is still counted once', async () => {
    const r = await reserveCpGiftEvent({ ...base, requestKey: null }, db);
    assert.equal(r.event, null);
    assert.equal(r.duplicate, null);
    assert.equal(db.rows('cpValueEvent').length, 0);
  });
});

// ---------------------------------------------------------------------------

describe('"مستخدم CP الظاهر" — the example from the spec', () => {
  test('A shows B; A later pairs with C → A still shows B', async () => {
    db.seed('cpPair', [{ id: 1, userAId: A, userBId: B, createdAt: new Date('2026-09-01') }]);
    await pinFeaturedIfUnset(A, B, db);
    assert.equal(featured(A), B);
    db.seed('cpPair', [{ id: 2, userAId: A, userBId: C, createdAt: new Date('2026-09-20') }]);
    await pinFeaturedIfUnset(A, C, db);
    assert.equal(featured(A), B, 'the newer pair did not take the spot');
    assert.equal(featured(C), A, 'C had no choice, so C shows A');
  });

  test('an explicit choice is never overwritten by a new pair', async () => {
    db.rows('user').find((u) => u.id === A)!.cpFeaturedPartnerId = C;
    await pinFeaturedIfUnset(A, B, db);
    assert.equal(featured(A), C);
  });

  test('the partners list serves the stored choice to every visitor', async () => {
    db.seed('cpPair', [
      { id: 1, userAId: A, userBId: B, createdAt: new Date('2026-09-01') },
      { id: 2, userAId: A, userBId: C, createdAt: new Date('2026-09-20') },
    ]);
    db.rows('user').find((u) => u.id === A)!.cpFeaturedPartnerId = B;
    const o = await getUserCpOverview(A, db);
    const shown = o.pairs.filter((p: any) => p.featured).map((p: any) => p.partner.id);
    assert.deepEqual(shown, [B], 'B, not the newest pair C');
  });

  test('dissolving the shown pair moves to the newest remaining partner, not to whoever comes next', async () => {
    db.seed('cpPair', [
      { id: 1, userAId: A, userBId: B, createdAt: new Date('2026-09-01') },
      { id: 2, userAId: A, userBId: C, createdAt: new Date('2026-09-20') },
    ]);
    db.rows('user').find((u) => u.id === A)!.cpFeaturedPartnerId = B;
    db.rows('user').find((u) => u.id === B)!.cpFeaturedPartnerId = A;
    await adminDeletePair(1, ctx, db);
    assert.equal(featured(A), C);
    assert.equal(featured(B), null, 'B has no partner left');
  });

  test('a user who shows someone else is untouched by another pair ending', async () => {
    db.seed('cpPair', [{ id: 2, userAId: A, userBId: C }]);
    db.rows('user').find((u) => u.id === A)!.cpFeaturedPartnerId = C;
    db.rows('user').find((u) => u.id === B)!.cpFeaturedPartnerId = ADMIN;
    await reassignFeaturedAfterRemoval(A, B, db);
    assert.equal(featured(A), C);
    assert.equal(featured(B), ADMIN);
  });
});

// ---------------------------------------------------------------------------

describe('dashboard: CP gifts', () => {
  test('"رفع مستوى CP" is set, cleared back to the price, and audited', async () => {
    await updateCpGift('rose', { cpLevelPoints: 40 }, ctx, db);
    assert.equal(db.rows('gift').find((g) => g.id === 'rose')!.cpLevelPoints, 40);
    await updateCpGift('rose', { cpLevelPoints: '' }, ctx, db);
    assert.equal(db.rows('gift').find((g) => g.id === 'rose')!.cpLevelPoints, null);
    const a = db.rows('adminAuditLog').filter((r) => r.action === 'CP_GIFT_UPDATE');
    assert.deepEqual([a[0]!.before.cpLevelPoints, a[0]!.after.cpLevelPoints], [null, 40]);
  });

  test('a negative amount is refused', async () => {
    await assert.rejects(() => updateCpGift('ring', { cpLevelPoints: -1 }, ctx, db), CpError);
    assert.equal(db.rows('gift').find((g) => g.id === 'ring')!.cpLevelPoints, 250);
  });

  test('enable / disable', async () => {
    await updateCpGift('ring', { isActive: false }, ctx, db);
    assert.equal(db.rows('gift').find((g) => g.id === 'ring')!.isActive, false);
  });

  test('a gift outside the CP list cannot be edited from here', async () => {
    await assert.rejects(
      () => updateCpGift('car', { coinCost: 1 }, ctx, db),
      (e: any) => e instanceof CpError && e.status === 404,
    );
    assert.equal(db.rows('gift').find((g) => g.id === 'car')!.coinCost, 5000);
  });

  test('the user\'s CP data shows the gift log, without in-flight claims', async () => {
    db.seed('cpPair', [{ id: 5, userAId: A, userBId: B, cpValue: 0 }]);
    const base = { pairId: 5, senderId: A, recipientId: B, giftId: 'ring', quantity: 1, source: 'partner_gift' as const };
    await recordCpGiftValue({ ...base, points: 250, giftTransactionId: 'gt-1' }, db);
    await reserveCpGiftEvent({ ...base, requestKey: 'in-flight' }, db);
    const o = await getUserCpOverview(B, db);
    assert.equal(o.cpGiftLog.length, 1);
    assert.equal(o.cpGiftLog[0]!.points, 250);
    assert.equal(o.cpGiftLog[0]!.cpValueAfter, 250);
    assert.equal(o.cpGiftLog[0]!.gift.nameAr, 'خاتم');
    assert.equal(o.cpGiftLog[0]!.sender.id, A);
  });
});
