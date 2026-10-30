import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { GameWinEventDto } from '../gameWinFeed.service';

// Keep the real Prisma client out of these fake-DB tests.
const prismaPath = require.resolve('../../utils/prisma');
const previousPrisma = require.cache[prismaPath];
require.cache[prismaPath] = { id: prismaPath, filename: prismaPath, loaded: true, exports: { __esModule: true, default: {} } } as any;
const { pollGameWins, __resetGameWinFeedForTests, gameNameAr } = require('../gameWinFeed.service') as typeof import('../gameWinFeed.service');
if (previousPrisma) require.cache[prismaPath] = previousPrisma;
else delete require.cache[prismaPath];

for (const roomId of [null, 42]) {
  test(`broadcasts a game win app-wide ${roomId == null ? 'without a room' : 'and to the current room'}`, async () => {
    __resetGameWinFeedForTests();
    const createdAt = new Date('2026-10-30T12:00:00Z');
    const amount = Math.max(1000, Number(process.env.GAME_WIN_STRIP_MIN ?? 100));
    const ledger = { id: 1, userId: 7, game: 'olympus', amount, createdAt };
    const saved: any[] = [];
    const db = {
      gameLedger: {
        findMany: async ({ where }: any) => ledger.id > where.id.gt ? [ledger] : [],
      },
      user: {
        findMany: async () => [{ id: 7, name: 'Winner', avatarUrl: '/winner.png' }],
      },
      gameWinEvent: {
        create: async ({ data }: any) => {
          saved.push(data);
          return { id: 101, ...data };
        },
      },
    };
    const roomEvents: Array<{ roomId: number; payload: GameWinEventDto }> = [];
    const broadcasts: GameWinEventDto[] = [];
    const emit = (rid: number, payload: GameWinEventDto) => { roomEvents.push({ roomId: rid, payload }); };
    const emitAll = (payload: GameWinEventDto) => { broadcasts.push(payload); };
    const roomOf = (userId: number) => {
      assert.equal(userId, 7);
      return roomId;
    };

    assert.equal(await pollGameWins(emit, roomOf, db, emitAll), 1);
    assert.equal(saved.length, 1);
    assert.equal(saved[0].roomId, roomId);
    assert.deepEqual(broadcasts, [{
      id: 101,
      userId: 7,
      name: 'Winner',
      avatarUrl: '/winner.png',
      roomId,
      gameId: 'olympus',
      gameName: gameNameAr('olympus'),
      winCoins: amount,
      timestamp: createdAt.toISOString(),
    }]);
    assert.deepEqual(roomEvents, roomId == null ? [] : [{ roomId, payload: broadcasts[0] }]);
    if (roomId != null) assert.equal(roomEvents[0]!.payload, broadcasts[0]);

    assert.equal(await pollGameWins(emit, roomOf, db, emitAll), 0);
    assert.equal(broadcasts.length, 1, 'the next poll does not announce the same win again');
    assert.equal(roomEvents.length, roomId == null ? 0 : 1);
  });
}
