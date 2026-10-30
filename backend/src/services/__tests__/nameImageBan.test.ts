import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

const db = {
  banBypassUser: { findUnique: async ({ where }: any) => where.userId === 42 ? { userId: 42 } : null },
  bannedName: { findUnique: async ({ where }: any) => where.value === 'محمد test' ? { id: 1 } : null },
};
const filename = require.resolve(resolve(__dirname, '../../utils/prisma'));
require.cache[filename] = { id: filename, filename, loaded: true, exports: { __esModule: true, default: db } } as any;
const { normalizeBannedName, isNameBanned, sha256 }: typeof import('../nameImageBan.service') = require('../nameImageBan.service');

test('normalizes diacritics, tatweel, Latin case and whitespace', () => {
  assert.equal(normalizeBannedName('  مُـحَمَّدٰ  \t TEST\n'), 'محمد test');
  assert.equal(normalizeBannedName('A\u065fB\u0670C'), 'abc');
});
test('a banned name is rejected for everyone except bypass users', async () => {
  assert.equal(await isNameBanned('مُـحَمَّد TEST', 7), true);
  assert.equal(await isNameBanned('محمد test'), true);
  assert.equal(await isNameBanned('محمد test', 42), false);
  assert.equal(await isNameBanned('اسم آخر', 7), false);
});
test('sha256 hashes the bytes as lowercase hex', () => {
  assert.equal(sha256(Buffer.from('abc')), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});
