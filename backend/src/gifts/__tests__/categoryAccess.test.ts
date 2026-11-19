import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { canOpenCategory, isCategoryLocked, parseCategoryLock } from '../categoryAccess';

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
for (const module of ['gifts/giftEvent', 'gifts/lucky.service', 'utils/coinFreeze',
  'services/notification.service', 'services/xp.service', 'controllers/achievement.controller']) stub(module, {});
stub('utils/prisma', { __esModule: true, default: {} });
const passedGate = new Error('passed category gate');
stub('controllers/settings.controller', { getCpConfig: async () => { throw passedGate; } });
const { sendGiftAtomic, GiftSendError }: typeof import('../giftService') = require('../giftService');

test('locks allow either VIP or public display ID, including ID-only and VIP-zero rules', () => {
  const lock = { minVipLevel: 6, allowedUserIds: [777] };
  assert.equal(canOpenCategory(lock, { vipLevel: 6, displayId: 1 }), true);
  assert.equal(canOpenCategory(lock, { vipLevel: 0, displayId: 777 }), true);
  assert.equal(canOpenCategory(lock, { vipLevel: 5, displayId: 1 }), false);
  assert.equal(canOpenCategory({ minVipLevel: null, allowedUserIds: [777] }, { vipLevel: 100, displayId: 1 }), false);
  assert.equal(isCategoryLocked({ minVipLevel: 0, allowedUserIds: [] }), true);
  assert.equal(canOpenCategory(null, null), true);
  assert.equal(canOpenCategory({ minVipLevel: null, allowedUserIds: [] }, null), true);
});

test('sendGiftAtomic enforces the lock before any debit; missing categories stay open', async () => {
  let category: any = { minVipLevel: 6, allowedUserIds: [777] };
  const sender = { id: 777, vipLevel: 5, displayId: 123 };
  let writes = 0;
  const tx = {
    gift: { findUnique: async () => ({ id: 'gift', category: 'locked', isActive: true }) },
    giftCategory: { findUnique: async () => category },
    user: { findUnique: async () => sender, updateMany: async () => { writes++; } },
  };
  const send = () => sendGiftAtomic({ senderId: 777, recipientId: 2, giftId: 'gift' }, { tx, afterCommit: [], beforeCommit: [] });
  await assert.rejects(send, error => error instanceof GiftSendError && error.code === 'LOCKED_CATEGORY' && error.status === 403);
  assert.equal(writes, 0);
  sender.displayId = 777;
  await assert.rejects(send, error => error === passedGate);
  sender.displayId = 123; sender.vipLevel = 6;
  await assert.rejects(send, error => error === passedGate);
  category = null; sender.vipLevel = 0;
  await assert.rejects(send, error => error === passedGate);
});

test('admin lock fields validate IDs and preserve omitted patch fields', () => {
  assert.deepEqual(parseCategoryLock({ minVipLevel: '', allowedUserIds: '12, 34 12' }), { minVipLevel: null, allowedUserIds: [12, 34] });
  assert.deepEqual(parseCategoryLock({}), {});
  for (const minVipLevel of [-1, 101, 1.5, 'bad']) assert.throws(() => parseCategoryLock({ minVipLevel }));
  for (const allowedUserIds of ['0', '1.5', 'abc', '2147483648', null]) assert.throws(() => parseCategoryLock({ allowedUserIds }));
});
