import prisma from '../utils/prisma';

/**
 * SPEC52 #39 — «🎮 فلان لعب Olympus وكسب 20,000» under the room header.
 *
 * Every game already writes its payout as a `prize` row in game_ledger inside
 * the same transaction that pays the player. This feed reads those rows AFTER
 * they are committed (by id, every 2 s), so an announcement can never describe
 * a win that rolled back, and every game — present and future — is covered
 * without touching its code. Each win is stored once in game_win_events with
 * the room the player was in, and pushed to that room as `game_win` and
 * app-wide as `game_win_broadcast`, even when the player is in no room.
 */
export const GAME_NAMES_AR: Record<string, string> = {
  olympus: 'بوابات أوليمبوس',
  yummy: 'يمي',
  fruitwheel: 'عجلة الفواكه',
  'fruit-wheel': 'عجلة الفواكه',
  carwheel: 'عجلة السيارات',
  roulette: 'الروليت',
  'fruit-jackpot': 'جاكبوت الفواكه',
  aetherfall: 'أثيرفول',
  asterion: 'أستيريون',
  neon_fortune: 'نيون فورتشن',
  'neon-fortune': 'نيون فورتشن',
  plinko: 'بلينكو',
  crash: 'طيّار',
  'crazy-wheel': 'عجلة الحظ',
  'greedy-cat': 'القط الجشع',
  greedy_cat: 'القط الجشع',
};

export const gameNameAr = (game: string) => GAME_NAMES_AR[game] ?? game;

export interface GameWinEventDto {
  id: number;
  userId: number;
  name: string;
  avatarUrl: string | null;
  roomId: number | null;
  gameId: string;
  gameName: string;
  winCoins: number;
  timestamp: string;
}

type Emit = (roomId: number, payload: GameWinEventDto) => void;
type EmitAll = (payload: GameWinEventDto) => void;
type RoomOf = (userId: number) => number | null;

let lastLedgerId = 0;
let timer: NodeJS.Timeout | null = null;
let busy = false;

/** Minimum prize worth a line in the room (tiny wins would flood it). */
const MIN_WIN = Number(process.env.GAME_WIN_STRIP_MIN ?? 100);

export async function pollGameWins(emit: Emit, roomOf: RoomOf, db: any = prisma, emitAll?: EmitAll): Promise<number> {
  if (busy) return 0;
  busy = true;
  try {
    const rows = await db.gameLedger.findMany({
      where: { id: { gt: lastLedgerId }, kind: 'prize' },
      orderBy: { id: 'asc' },
      take: 200,
      select: { id: true, userId: true, game: true, amount: true, createdAt: true },
    });
    if (!rows.length) return 0;
    lastLedgerId = rows[rows.length - 1].id;
    const wins = rows.filter((r: any) => Number(r.amount) >= MIN_WIN);
    if (!wins.length) return 0;
    const users = await db.user.findMany({
      where: { id: { in: [...new Set(wins.map((w: any) => w.userId))] } },
      select: { id: true, name: true, avatarUrl: true },
    });
    const byId = new Map<number, any>(users.map((u: any) => [u.id, u]));
    let n = 0;
    for (const w of wins) {
      const roomId = roomOf(w.userId);
      const row = await db.gameWinEvent
        .create({
          data: {
            ledgerId: w.id,
            userId: w.userId,
            roomId,
            gameId: w.game,
            gameName: gameNameAr(w.game),
            winCoins: Number(w.amount),
            createdAt: w.createdAt,
          },
        })
        .catch(() => null); // unique ledgerId: already announced
      if (!row) continue;
      n++;
      const u = byId.get(w.userId);
      const payload: GameWinEventDto = {
        id: row.id,
        userId: w.userId,
        name: u?.name ?? 'لاعب',
        avatarUrl: u?.avatarUrl ?? null,
        roomId,
        gameId: w.game,
        gameName: row.gameName,
        winCoins: row.winCoins,
        timestamp: new Date(row.createdAt).toISOString(),
      };
      if (roomId != null) emit(roomId, payload);
      emitAll?.(payload);
    }
    return n;
  } catch (e) {
    console.warn('[gameWinFeed] poll failed:', (e as Error).message);
    return 0;
  } finally {
    busy = false;
  }
}

export async function startGameWinFeed(emit: Emit, roomOf: RoomOf, emitAll?: EmitAll) {
  if (timer) return;
  try {
    // Start after what already exists: only new wins are announced.
    const last = await (prisma as any).gameLedger.findFirst({ orderBy: { id: 'desc' }, select: { id: true } });
    lastLedgerId = last?.id ?? 0;
  } catch {
    lastLedgerId = 0;
  }
  timer = setInterval(() => void pollGameWins(emit, roomOf, prisma, emitAll), 2000);
  timer.unref?.();
}

/** Latest wins for a room (or the whole app). */
export async function recentRoomWins(roomId: number | null, limit = 10): Promise<GameWinEventDto[]> {
  const rows = await (prisma as any).gameWinEvent.findMany({
    where: roomId ? { roomId } : {},
    orderBy: { id: 'desc' },
    take: Math.max(1, Math.min(30, limit)),
  });
  const users = rows.length
    ? await prisma.user.findMany({
        where: { id: { in: [...new Set<number>(rows.map((r: any) => r.userId))] } },
        select: { id: true, name: true, avatarUrl: true },
      })
    : [];
  const byId = new Map<number, any>(users.map((u: any) => [u.id, u]));
  return rows.map((r: any) => ({
    id: r.id,
    userId: r.userId,
    name: byId.get(r.userId)?.name ?? 'لاعب',
    avatarUrl: byId.get(r.userId)?.avatarUrl ?? null,
    roomId: r.roomId,
    gameId: r.gameId,
    gameName: r.gameName,
    winCoins: r.winCoins,
    timestamp: new Date(r.createdAt).toISOString(),
  }));
}

export function __resetGameWinFeedForTests() {
  lastLedgerId = 0;
  busy = false;
}
