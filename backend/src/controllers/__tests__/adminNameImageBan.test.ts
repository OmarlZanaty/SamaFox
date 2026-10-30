import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

let users: any[];
let names: any[];
let bypass: any[];
let audits: any[];
const db: any = {
  user: {
    findUnique: async ({ where }: any) => users.find(u => Object.entries(where).every(([k, v]) => u[k] === v)) ?? null,
    update: async ({ where, data }: any) => Object.assign(users.find(u => u.id === where.id), data),
  },
  bannedName: { upsert: async ({ where, create }: any) => {
    let row = names.find(r => r.value === where.value);
    if (!row) { row = { id: names.length + 1, ...create }; names.push(row); }
    return row;
  } },
  banBypassUser: { upsert: async ({ where, create }: any) => {
    let row = bypass.find(r => r.userId === where.userId);
    if (!row) { row = { id: bypass.length + 1, ...create }; bypass.push(row); }
    return row;
  } },
  adminAuditLog: { create: async ({ data }: any) => { audits.push(data); } },
  $transaction: async (fn: any) => fn(db),
};
function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
stub('utils/prisma', { __esModule: true, default: db });
const { banUserName, addBanBypass }: typeof import('../adminNameImageBan.controller') = require('../adminNameImageBan.controller');
beforeEach(() => {
  users = [{ id: 7, displayId: 800001, name: 'مُـحَمَّد' }, { id: 8, displayId: 7, name: 'آخر' }];
  names = []; bypass = []; audits = [];
});
async function call(handler: any, body: any = {}, params: any = {}) {
  let status = 200; let result: any;
  const res = { status(n: number) { status = n; return res; }, json(data: any) { result = data; return res; } };
  await handler({ userId: 1, body, params }, res);
  return { status, result };
}
test('name moderation uses internal ID, normalizes, resets and audits without account ban', async () => {
  const response = await call(banUserName, {}, { userId: '7' });
  assert.equal(response.status, 200);
  assert.equal(names[0].value, 'محمد');
  assert.equal(users[0].name, 'مستخدم800001');
  assert.equal(users[1].name, 'آخر');
  assert.equal(users[0].isBanned, undefined);
  assert.equal(audits[0].targetUserId, 7);
  users[0].name = 'محمد';
  await call(banUserName, {}, { userId: '7' });
  assert.equal(names.length, 1);
});
test('bypass entry resolves public ID first and ignores duplicate additions', async () => {
  assert.equal((await call(addBanBypass, { publicId: 7 })).status, 200);
  await call(addBanBypass, { publicId: 7 });
  assert.equal(bypass.length, 1);
  assert.equal(bypass[0].userId, 8);
});
