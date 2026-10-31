// Client 31/10 — dashboard emoji lists: public, VIP-only, and chosen-IDs-only.
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

type Row = Record<string, any>;
let lists: Row[] = [];
const users: Row[] = [
  { id: 1, vipLevel: 0, vipExpiresAt: null },
  { id: 2, vipLevel: 3, vipExpiresAt: null },
  { id: 3, vipLevel: 5, vipExpiresAt: new Date(Date.now() - 1000) },
];
const db = {
  emojiList: { findMany: async () => lists },
  user: { findUnique: async ({ where }: Row) => users.find((u) => u.id === where.id) ?? null },
};
const filename = require.resolve(resolve(__dirname, '../../utils/prisma'));
require.cache[filename] = { id: filename, filename, loaded: true, exports: { __esModule: true, default: db } } as any;
const svc: typeof import('../emoji.service') = require('../emoji.service');

const emoji = (id: number, isActive = true) => ({ id, name: `e${id}`, imageUrl: `/e${id}.gif`, sortOrder: 0, isActive });
function seed() {
  lists = [
    { id: 1, nameAr: 'عام', imageUrl: null, sortOrder: 0, isActive: true, minVip: 0, userIds: [], emojis: [emoji(11), emoji(12, false)] },
    { id: 2, nameAr: 'VIP', imageUrl: null, sortOrder: 1, isActive: true, minVip: 2, userIds: [], emojis: [emoji(21)] },
    { id: 3, nameAr: 'خاص', imageUrl: null, sortOrder: 2, isActive: true, minVip: 0, userIds: [1], emojis: [emoji(31)] },
    { id: 4, nameAr: 'مخفية', imageUrl: null, sortOrder: 3, isActive: false, minVip: 0, userIds: [], emojis: [emoji(41)] },
  ];
  svc.invalidateEmojiLists();
}

test('each user sees only the lists open to him, with hidden emoji left out', async () => {
  seed();
  const ids = async (u: number) => (await svc.emojiListsFor(u)).map((l) => l.id);
  assert.deepEqual(await ids(1), [1, 3]); // no VIP, but on the private list
  assert.deepEqual(await ids(2), [1, 2]); // VIP 3 ≥ 2
  assert.deepEqual(await ids(3), [1]); // VIP 5 expired
  assert.deepEqual((await svc.emojiListsFor(1))[0]!.emojis.map((e) => e.id), [11]);
});

test('sending is checked on the server the same way', async () => {
  seed();
  assert.equal((await svc.customEmojiForSend(1, 31))?.imageUrl, '/e31.gif');
  assert.equal(await svc.customEmojiForSend(2, 31), null);
  assert.ok(await svc.customEmojiForSend(2, 21));
  assert.equal(await svc.customEmojiForSend(1, 21), null);
  assert.equal(await svc.customEmojiForSend(1, 12), null); // hidden emoji
  assert.equal(await svc.customEmojiForSend(1, 41), null); // hidden list
  assert.equal(await svc.customEmojiForSend(1, 999), null);
});

test('a list with both a VIP floor and IDs opens for either', () => {
  const l = { isActive: true, minVip: 4, userIds: [9] };
  assert.equal(svc.canUseEmojiList(l, 9, 0), true);
  assert.equal(svc.canUseEmojiList(l, 8, 4), true);
  assert.equal(svc.canUseEmojiList(l, 8, 3), false);
});
