import { test } from 'node:test';
import assert from 'node:assert/strict';

const settings: Record<string, string> = {};
let user: any;
let thresholds: any[] = [];
const db = {
  appSetting: { findUnique: async ({ where }: any) => ({ value: settings[where.key] }) },
  user: { findUnique: async () => user },
  levelConfig: { findMany: async () => thresholds },
};
const filename = require.resolve('../../utils/prisma');
require.cache[filename] = { id: filename, filename, loaded: true, exports: { __esModule: true, default: db } } as any;
const notificationFile = require.resolve('../../services/notification.service');
require.cache[notificationFile] = { id: notificationFile, filename: notificationFile, loaded: true, exports: { createNotification: async () => undefined } } as any;
const { pictureDenial, getRoomImagePolicy, getMessageImagePolicy }: typeof import('../messages.controller') = require('../messages.controller');

function fixture() {
  for (const key of Object.keys(settings)) delete settings[key];
  settings.gate_image_level_kind = 'supported';
  settings.message_image_min_level = settings.room_image_min_level = '3';
  user = { level: 99, supportedLevel: 99, receivedXp: 399n, vipLevel: 0, vipExpiresAt: null };
  thresholds = [];
}

test('supported gate uses received XP at the threshold, ignoring supporter and stale cached levels', async () => {
  fixture();
  for (const scope of ['room', 'dm'] as const) {
    user.receivedXp = 399n;
    assert.equal((await pictureDenial(1, scope))?.code, 'LEVEL_REQUIRED');
    user.receivedXp = 400n;
    assert.equal(await pictureDenial(1, scope), null);
  }
});

test('supported gate honors dashboard LevelConfig thresholds and supporter default', async () => {
  fixture();
  thresholds = [{ level: 3, threshold: 1000 }];
  user.receivedXp = 999n;
  assert.equal((await pictureDenial(1, 'dm'))?.code, 'LEVEL_REQUIRED');
  user.receivedXp = 1000n;
  assert.equal(await pictureDenial(1, 'dm'), null);
  delete settings.gate_image_level_kind;
  user.receivedXp = 0n;
  assert.equal(await pictureDenial(1, 'dm'), null);
});

test('room and DM policies expose kind and matching denial; expired VIP still denies', async () => {
  fixture();
  for (const handler of [getRoomImagePolicy, getMessageImagePolicy]) {
    let response: any;
    const res: any = { json: (value: any) => { response = value; }, status: () => res };
    await handler({ userId: 1 } as any, res);
    assert.equal(response.data.allowed, false);
    assert.equal(response.data.kind, 'supported');
    assert.equal(response.data.minLevel, 3);
    assert.equal(response.data.minVip, 0);
    assert.ok(response.data.message);
  }
  settings.message_image_min_vip = '1';
  user.receivedXp = 400n;
  user.vipLevel = 5;
  user.vipExpiresAt = new Date(0);
  assert.equal((await pictureDenial(1, 'dm'))?.code, 'VIP_REQUIRED');
});
