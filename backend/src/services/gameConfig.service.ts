import prisma from '../utils/prisma';

const db = prisma as any;

/**
 * G3(d) — لوحة تحكم الألعاب: تشغيل/إيقاف وحدود الرهان.
 *
 * Every game service carries its own MIN_BET / MAX_BET module constants, some
 * overridable by an env var that only takes effect on a restart. Neither is
 * something the owner can change from لوحة التحكم, and there was no way at all
 * to take a game offline.
 *
 * Rather than thread a settings lookup through seven services and their
 * simulators, the config is enforced at the ROUTE boundary: one guard in front
 * of the play endpoints. That keeps each game's own maths — and the RTP
 * simulations that prove it — completely untouched, while still giving the
 * dashboard real control over whether a game runs and for how much.
 *
 * Stored in AppSetting as one JSON row so it ships without a migration.
 */

const KEY = 'game_config';

export interface GameSettings {
  /** false takes the game offline; the app is told why. */
  enabled: boolean;
  /** null = fall back to the game's own built-in limit. */
  minBet: number | null;
  maxBet: number | null;
}

export type GameConfigMap = Record<string, GameSettings>;

/** Games the panel knows about. The id is the URL segment used by game.routes. */
export const KNOWN_GAMES = [
  'crash',
  'plinko',
  'crazy-wheel',
  'greedy-cat',
  'neon-fortune',
  'aetherfall',
  'asterion',
  'olympus',
  'boxing',
  'dice',
  'wheel',
] as const;

const DEFAULTS: GameSettings = { enabled: true, minBet: null, maxBet: null };

// A settings read on every bet would put a query in front of the hot path, so
// the map is cached briefly. Writes clear it, which is what makes a dashboard
// change take effect immediately; the TTL only bounds how long a stale entry
// can survive a write made by ANOTHER process.
const CACHE_TTL_MS = 15_000;
let cache: { map: GameConfigMap; at: number } | null = null;

export function invalidateGameConfigCache(): void {
  cache = null;
}

export async function getGameConfig(): Promise<GameConfigMap> {
  if (cache && Date.now() - cache.at < CACHE_TTL_MS) return cache.map;
  let map: GameConfigMap = {};
  try {
    const row = await db.appSetting.findUnique({ where: { key: KEY } });
    if (row?.value) map = JSON.parse(row.value) as GameConfigMap;
  } catch (e) {
    // Fail OPEN — a malformed row or a database blip must never take every
    // game offline. Defaults mean "enabled, use the built-in limits".
    console.warn('[gameConfig] read failed, using defaults:', (e as Error).message);
    map = {};
  }
  cache = { map, at: Date.now() };
  return map;
}

export async function getGameSettings(game: string): Promise<GameSettings> {
  const map = await getGameConfig();
  return { ...DEFAULTS, ...(map[game] ?? {}) };
}

export async function setGameSettings(
  game: string,
  patch: Partial<GameSettings>,
): Promise<GameSettings> {
  const map = await getGameConfig();
  const next: GameSettings = { ...DEFAULTS, ...(map[game] ?? {}), ...patch };
  const merged: GameConfigMap = { ...map, [game]: next };

  const value = JSON.stringify(merged);
  await db.appSetting.upsert({
    where: { key: KEY },
    update: { value },
    create: { key: KEY, value },
  });
  invalidateGameConfigCache();
  return next;
}

export type GameGuardResult =
  | { ok: true }
  | { ok: false; status: number; code: string; message: string };

/**
 * Is this game playable at this stake right now?
 *
 * Limits are only applied when the admin actually set one — a null means "the
 * game's own constant still governs", so an unconfigured panel changes nothing
 * about how anything already behaves.
 */
export async function checkGamePlayable(
  game: string,
  bet?: number | null,
): Promise<GameGuardResult> {
  const cfg = await getGameSettings(game);

  if (!cfg.enabled) {
    return {
      ok: false,
      status: 403,
      code: 'GAME_DISABLED',
      message: 'هذه اللعبة متوقفة حالياً من الإدارة',
    };
  }

  if (bet != null && Number.isFinite(bet)) {
    if (cfg.minBet != null && bet < cfg.minBet) {
      return {
        ok: false,
        status: 400,
        code: 'BET_TOO_LOW',
        message: `أقل رهان في هذه اللعبة ${cfg.minBet} كوينز`,
      };
    }
    if (cfg.maxBet != null && bet > cfg.maxBet) {
      return {
        ok: false,
        status: 400,
        code: 'BET_TOO_HIGH',
        message: `أعلى رهان في هذه اللعبة ${cfg.maxBet} كوينز`,
      };
    }
  }

  return { ok: true };
}

/**
 * Express guard for a game's play endpoints.
 *
 * The stake is read from whichever field that game happens to use — the
 * services were written independently and never agreed on a name.
 */
export function gameGuard(game: string) {
  return async (req: any, res: any, next: any) => {
    try {
      const body = req.body ?? {};
      const raw = body.amount ?? body.bet ?? body.betAmount ?? body.stake ?? null;
      const bet = raw == null ? null : Number(raw);
      const verdict = await checkGamePlayable(game, bet);
      if (verdict.ok) return next();
      return res
        .status(verdict.status)
        .json({ success: false, code: verdict.code, message: verdict.message });
    } catch (e) {
      // Never let the guard itself break a game.
      console.warn('[gameConfig] guard error, allowing:', (e as Error).message);
      return next();
    }
  };
}
