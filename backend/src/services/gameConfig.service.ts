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
  // ── اقتصاد الألعاب (2026-09-26) — all enforced in halalGames.service ──
  /** No single round pays more than this. null = no round cap (pool still limits). */
  maxWinPerRound: number | null;
  /** Per player, per Cairo day, for this game. null = no daily cap. */
  dailyMaxWinPerUser: number | null;
  /** No round pays more than stake × this. null = the game's natural maximum. */
  maxPayoutRatio: number | null;
  /** The RTP the owner wants, in basis points (7500 = 75%). Monitoring target. */
  rtpTargetBp: number | null;
  /** The program's cut of every stake, in basis points; the rest feeds the pool. */
  programShareBp: number;
}

export type GameConfigMap = Record<string, GameSettings>;

/** Games the panel knows about. The id is the URL segment used by game.routes. */
export const KNOWN_GAMES = [
  'crash',
  'plinko',
  'crazy-wheel',
  'greedy-cat',
  'neon-fortune',
  'yummy',
  'aetherfall',
  'asterion',
  'olympus',
  'boxing',
  'dice',
  'wheel',
] as const;

const DEFAULTS: GameSettings = {
  enabled: true,
  minBet: null,
  maxBet: null,
  maxWinPerRound: 1_000_000,
  dailyMaxWinPerUser: 5_000_000,
  maxPayoutRatio: null,
  rtpTargetBp: 7000,
  programShareBp: 2500,
};

/** The share the client asked for: 25% program / 75% players' prize pool. */
export const DEFAULT_PROGRAM_SHARE_BP = 2500;

/**
 * The largest multiple of the stake each game can legitimately pay — what
 * `maxPayoutRatio` falls back to, and the lower bound the dashboard warns about
 * (a ratio under it cuts real wins). Mirrors the reservation multiples the
 * engines already use.
 */
const NATURAL_MAX_MULTIPLIER: Record<string, number> = {
  crash: Number(process.env.CRASH_MAX_MULTIPLIER ?? 100),
  plinko: 1000,
  'crazy-wheel': 500,
  'greedy-cat': 45,
  'neon-fortune': 1000,
  yummy: 1010,
  aetherfall: 1000,
  asterion: 1000,
  olympus: 1000,
  boxing: 1,
  dice: 1,
  wheel: 1,
};

export function naturalMaxMultiplier(game: string): number | null {
  return NATURAL_MAX_MULTIPLIER[game] ?? null;
}

/**
 * Reject settings that make no sense before they are stored. Returns the
 * reason in Arabic for the dashboard, or null when the settings are sound.
 */
export function validateGameSettings(game: string, s: GameSettings): string | null {
  const nonNeg = (v: number | null) => v == null || (Number.isFinite(v) && v >= 0);
  if (!nonNeg(s.minBet) || !nonNeg(s.maxBet)) return 'قيم الرهان يجب أن تكون صفر أو أكثر';
  if (s.minBet != null && s.maxBet != null && s.minBet > s.maxBet) return 'أقل رهان أكبر من أعلى رهان';
  if (!nonNeg(s.maxWinPerRound) || !nonNeg(s.dailyMaxWinPerUser)) return 'حدود المكسب يجب أن تكون صفر أو أكثر';
  if (s.maxWinPerRound != null && s.dailyMaxWinPerUser != null && s.maxWinPerRound > s.dailyMaxWinPerUser) {
    return 'أقصى مكسب للجولة أكبر من أقصى مكسب يومي';
  }
  if (s.maxPayoutRatio != null && (!Number.isFinite(s.maxPayoutRatio) || s.maxPayoutRatio < 1)) {
    return 'أقصى نسبة دفع يجب أن تكون 1 أو أكثر';
  }
  if (!Number.isInteger(s.programShareBp) || s.programShareBp < 0 || s.programShareBp > 10_000) {
    return 'حصة البرنامج بين 0% و 100%';
  }
  if (s.rtpTargetBp != null) {
    if (!Number.isInteger(s.rtpTargetBp) || s.rtpTargetBp < 0 || s.rtpTargetBp > 10_000) return 'RTP بين 0% و 100%';
    // The pool only receives (100% − program share) of every stake; a target
    // above that drains it.
    if (s.rtpTargetBp > 10_000 - s.programShareBp) {
      return `RTP المستهدف (${s.rtpTargetBp / 100}%) أعلى من نصيب صندوق اللاعبين (${(10_000 - s.programShareBp) / 100}%)`;
    }
  }
  return null;
}

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

export class GameSettingsError extends Error {}

export async function setGameSettings(
  game: string,
  patch: Partial<GameSettings>,
): Promise<GameSettings> {
  invalidateGameConfigCache();
  const map = await getGameConfig();
  const next: GameSettings = { ...DEFAULTS, ...(map[game] ?? {}), ...patch };
  const invalid = validateGameSettings(game, next);
  if (invalid) throw new GameSettingsError(invalid);
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
