/**
 * Big-win announcements shared by every game: "X just won 52,000 on YUMMY".
 *
 * The socket server registers its emitter at startup; games only call
 * [broadcastGameWin]. Keeping the io handle out of the game services means
 * they (and their tests) never import the socket layer. A short in-memory
 * feed lets a screen that opens later show the latest few straight away.
 */
export interface GameWinBroadcast {
  game: string;
  userId: number;
  name: string;
  avatar: string | null;
  prize: number;
  /** Prize as a multiple of the total stake, one decimal. */
  x: number;
  tier: 'big' | 'mega' | 'jackpot';
  at: string;
}

type Emit = (event: string, payload: unknown) => void;
let emit: Emit | null = null;
const feed: GameWinBroadcast[] = [];
const FEED_SIZE = 20;

export function setGameBroadcastEmitter(fn: Emit | null): void {
  emit = fn;
}

export function broadcastGameWin(win: GameWinBroadcast): void {
  feed.unshift(win);
  feed.splice(FEED_SIZE);
  try {
    emit?.('game_win_broadcast', win);
  } catch (e) {
    // An announcement is decoration; it must never fail a settled round.
    console.warn('[gameBroadcast] emit failed:', (e as Error).message);
  }
}

export function recentGameWins(game?: string): GameWinBroadcast[] {
  return game ? feed.filter((w) => w.game === game) : [...feed];
}

export function __resetGameBroadcastForTests(): void {
  feed.length = 0;
  emit = null;
}
