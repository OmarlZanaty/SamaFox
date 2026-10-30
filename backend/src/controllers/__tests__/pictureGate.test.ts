// «الصور في الرسايل … تكون محكومه ب lv معين احدده من لوحة التحكم» ·
// «الصور في الرسايل مخصصه ل vip معين مش شغاله»
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

type Row = Record<string, any>;
let settings: Record<string, string> = {};
let user: Row = {};
const db = {
  appSetting: { findUnique: async ({ where }: Row) => (where.key in settings ? { value: settings[where.key] } : null) },
  user: { findUnique: async () => user },
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
stub('services/notification.service', { createNotification: async () => {} });
const { pictureDenial }: typeof import('../messages.controller') = require('../messages.controller');

const day = 24 * 3600 * 1000;

test('no bars set: everyone may send', async () => {
  settings = {};
  user = { vipLevel: 0, vipExpiresAt: null, level: 1 };
  assert.equal(await pictureDenial(1, 'dm'), null);
});

test('an expired VIP no longer clears the VIP bar', async () => {
  settings = { message_image_min_vip: '3' };
  user = { vipLevel: 5, vipExpiresAt: new Date(Date.now() - day), level: 50 };
  assert.equal((await pictureDenial(1, 'dm'))?.code, 'VIP_REQUIRED');
  user = { ...user, vipExpiresAt: new Date(Date.now() + day) };
  assert.equal(await pictureDenial(1, 'dm'), null);
});

test('the level bar applies per scope', async () => {
  settings = { room_image_min_level: '20' };
  user = { vipLevel: 0, vipExpiresAt: null, level: 10 };
  const r = await pictureDenial(1, 'room');
  assert.equal(r?.code, 'LEVEL_REQUIRED');
  assert.match(r!.message, /ليفل 20/);
  assert.equal(await pictureDenial(1, 'dm'), null, 'the DM bar is separate');
  user = { ...user, level: 20 };
  assert.equal(await pictureDenial(1, 'room'), null);
});
