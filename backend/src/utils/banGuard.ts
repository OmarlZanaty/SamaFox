import prisma from './prisma';

/**
 * Single source of truth for "is this account currently banned".
 *
 * Every entry point (REST middleware, token refresh, socket handshake, each
 * login flow) has to agree, otherwise a ban leaks: before this existed only
 * the email/password login checked, so a banned user stayed signed in through
 * their refresh token and kept full API and socket access.
 *
 * Timed bans expire here too. That used to live inside the login handler
 * alone, which meant an expired ban stayed `isBanned: true` in the database —
 * and kept showing as محظور on the dashboard — until the user happened to try
 * a password login.
 */

export type BanState = {
  banned: boolean;
  reason: string | null;
  /** null with `banned: true` means permanent. */
  expiresAt: Date | null;
};

const NOT_BANNED: BanState = { banned: false, reason: null, expiresAt: null };

/**
 * Checking the database on every authenticated request would put a query in
 * front of the whole API, so results are cached briefly. Bans and unbans call
 * [invalidateBanCache], so a ban still takes effect immediately — the TTL only
 * bounds how long a *stale* entry can survive a write we didn't see (another
 * process, or a direct database edit).
 */
const CACHE_TTL_MS = 30_000;

const cache = new Map<number, { state: BanState; at: number }>();

/** Drop a user's cached ban state. Call after any write to their ban fields. */
export function invalidateBanCache(userId: number): void {
  cache.delete(userId);
}

export function clearBanCache(): void {
  cache.clear();
}

/**
 * Current ban state, lifting the ban first if its term has run out.
 *
 * Never throws: if the lookup fails we fail open (treat as not banned) so a
 * database blip can't lock every user out of the app.
 */
export async function getBanState(userId: number): Promise<BanState> {
  if (!userId || userId <= 0) return NOT_BANNED;

  const hit = cache.get(userId);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.state;

  let state = NOT_BANNED;
  try {
    const user = await (prisma as any).user.findUnique({
      where: { id: userId },
      select: { isBanned: true, banReason: true, banExpiresAt: true },
    });

    if (user?.isBanned === true) {
      const expiresAt = user.banExpiresAt ? new Date(user.banExpiresAt) : null;

      if (expiresAt && expiresAt.getTime() <= Date.now()) {
        // Term served — lift it so the dashboard stops showing them as banned.
        await (prisma as any).user.update({
          where: { id: userId },
          data: {
            isBanned: false,
            bannedAt: null,
            banReason: null,
            banExpiresAt: null,
            banSource: null,
          },
        });
      } else {
        state = {
          banned: true,
          reason: user.banReason ?? null,
          expiresAt,
        };
      }
    }
  } catch (e) {
    console.warn('[banGuard] lookup failed, allowing request:', e);
    return NOT_BANNED;
  }

  cache.set(userId, { state, at: Date.now() });
  return state;
}

/** Convenience wrapper for the login flows. */
export async function assertNotBanned(userId: number): Promise<BanState | null> {
  const state = await getBanState(userId);
  return state.banned ? state : null;
}

/**
 * The message shown to a banned user. Includes the end date for timed bans so
 * they aren't left guessing whether it is permanent.
 */
export function banMessage(state: BanState): string {
  const base = state.reason?.trim() || 'تم حظر حسابك';
  if (!state.expiresAt) return `${base} — الحظر دائم`;
  const until = state.expiresAt.toISOString().slice(0, 10);
  return `${base} — ينتهي الحظر في ${until}`;
}
