import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';

function stub(relative: string, exports: any) {
  const filename = require.resolve(resolve(__dirname, '../..', relative));
  require.cache[filename] = { id: filename, filename, loaded: true, exports } as any;
}
let saved: any;
let events: any[];
let socketFails: boolean;
let committed: boolean;
const sender = { id: 1, name: 'مرسل', avatarUrl: null, avatarFrameUrl: null, level: 6 };
const db: any = {
  conversationParticipant: { findUnique: async () => ({ id: 1 }) },
  conversation: { findUnique: async () => ({ userAId: 1, userBId: 2 }), update: async () => {} },
  directMessage: {
    create: async ({ data }: any) => (saved = { id: 3, createdAt: new Date('2026-11-19T12:00:00Z'), ...data, sender }),
    findUnique: async () => saved,
  },
  appSetting: { findUnique: async () => null },
  $transaction: async (fn: any) => { const result = await fn(db); committed = true; return result; },
};
stub('utils/prisma', { __esModule: true, default: db });
stub('utils/blockGuard', { isBlockedBetween: async () => false });
stub('services/dmAccess.service', { checkDmAccess: async () => ({ allowed: true }) });
stub('services/notification.service', { createNotification: async () => {} });
stub('utils/chatBubble', { getChatBubble: async () => ({ bubbleUrl: '/bubble.png', bubbleMeta: { color: 'red' } }) });
stub('services/xp.service', {});
stub('services/socket.service', { emitToUser: (userId: number, event: string, payload: any) => {
  assert.equal(committed, true);
  if (socketFails) throw new Error('socket unavailable');
  events.push({ userId, event, payload });
} });
const { sendMessage }: typeof import('../messages.controller') = require('../messages.controller');
beforeEach(() => { saved = null; events = []; socketFails = false; committed = false; });

async function send(body: any) {
  let status = 200; let payload: any;
  const res: any = { status(n: number) { status = n; return res; }, json(value: any) { payload = value; return res; } };
  await sendMessage({ userId: 1, body: { conversationId: 9, ...body } } as any, res);
  assert.equal(status, 200);
  return payload;
}

test('REST sends the complete message and conversation update only to the recipient after commit', async () => {
  const payload = await send({ text: 'أهلاً' });
  assert.deepEqual(events, [
    { userId: 2, event: 'dm_new_message', payload },
    { userId: 2, event: 'dm_conversation_updated', payload: {
      conversationId: 9, partnerId: 1, lastMessage: 'أهلاً', lastMessageTime: '2026-11-19T12:00:00.000Z',
    } },
  ]);
  assert.deepEqual(Object.keys(payload).sort(), [
    'id', 'conversationId', 'senderId', 'text', 'imageUrl', 'audioUrl', 'type', 'createdAt', 'sender', 'bubbleUrl', 'bubbleMeta',
  ].sort());
});

test('media conversation previews use the expected icons', async () => {
  await send({ imageUrl: '/image.png' });
  assert.equal(events[1].payload.lastMessage, '📷');
  events = [];
  await send({ audioUrl: '/audio.mp3' });
  assert.equal(events[1].payload.lastMessage, '🎤');
  assert.equal(events[0].payload.audioUrl, '/audio.mp3');
});

test('socket errors do not fail a committed REST message', async () => {
  socketFails = true;
  const response = await send({ text: 'أهلاً' });
  assert.equal(response.id, 3);
  assert.equal(committed, true);
});
