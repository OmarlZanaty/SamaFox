import crypto from 'crypto';
import prisma from '../utils/prisma';

// ─────────────────────────────────────────────────────────────────────────────
// PROVABLY-FAIR SEED STORE
//
// Shared by بلينكو, نيون فورتشن and أثيرفول, which each used to keep this state
// in their own module-level Map. That made the commitment hollow: a restart or
// a deploy threw away the server seed a player had already been handed the hash
// of, so nothing they had played could be verified afterwards, and the nonce
// went back to zero — which on a fixed seed pair means replaying the same
// results. It also meant the games could never run on more than one process.
//
// The row is the source of truth. A small in-process cache sits in front of it
// for reads, but every mutation goes through the database, and the nonce is
// reserved with an atomic increment so two concurrent spins can never draw the
// same one.
// ─────────────────────────────────────────────────────────────────────────────

export type FairGame = 'plinko' | 'neon_fortune' | 'aetherfall';

export interface SeedState {
  serverSeed: string;
  serverSeedHash: string;
  clientSeed: string;
  nonce: number;
}

const sha256 = (input: string) => crypto.createHash('sha256').update(input).digest('hex');

export function freshServerSeed(): { serverSeed: string; serverSeedHash: string } {
  const serverSeed = crypto.randomBytes(32).toString('hex');
  return { serverSeed, serverSeedHash: sha256(serverSeed) };
}

/** Read-through cache. Only ever holds what the database already has. */
const cache = new Map<string, SeedState>();
const keyOf = (userId: number, game: FairGame) => `${game}:${userId}`;

function remember(userId: number, game: FairGame, state: SeedState): SeedState {
  cache.set(keyOf(userId, game), state);
  return state;
}

/**
 * The player's current seed pair, created on first use.
 *
 * Two requests racing to create the same row is normal (a spin and a fairness
 * read arriving together), so a unique-constraint collision is treated as
 * "someone else just made it" and the existing row wins.
 */
export async function seedsFor(userId: number, game: FairGame): Promise<SeedState> {
  const cached = cache.get(keyOf(userId, game));
  if (cached) return cached;

  const existing = await prisma.gameFairSeed.findUnique({
    where: { userId_game: { userId, game } },
  });
  if (existing) {
    return remember(userId, game, {
      serverSeed: existing.serverSeed,
      serverSeedHash: existing.serverSeedHash,
      clientSeed: existing.clientSeed,
      nonce: existing.nonce,
    });
  }

  const fresh = { ...freshServerSeed(), clientSeed: `u${userId}`, nonce: 0 };
  try {
    await prisma.gameFairSeed.create({ data: { userId, game, ...fresh } });
    return remember(userId, game, fresh);
  } catch {
    const row = await prisma.gameFairSeed.findUnique({
      where: { userId_game: { userId, game } },
    });
    if (!row) throw new Error(`[fairSeeds] could not establish a seed pair for ${game}:${userId}`);
    return remember(userId, game, {
      serverSeed: row.serverSeed,
      serverSeedHash: row.serverSeedHash,
      clientSeed: row.clientSeed,
      nonce: row.nonce,
    });
  }
}

/** What a player is allowed to see: the commitment, their seed, the count. */
export async function getFairness(userId: number, game: FairGame) {
  const s = await seedsFor(userId, game);
  return { serverSeedHash: s.serverSeedHash, clientSeed: s.clientSeed, nonce: s.nonce };
}

export async function setClientSeed(userId: number, game: FairGame, seed: string) {
  const clean = String(seed ?? '').trim().slice(0, 64);
  if (!clean) return { ok: false as const, code: 'BAD_SEED', message: 'البذرة غير صالحة' };

  await seedsFor(userId, game);
  const row = await prisma.gameFairSeed.update({
    where: { userId_game: { userId, game } },
    data: { clientSeed: clean },
  });
  remember(userId, game, {
    serverSeed: row.serverSeed,
    serverSeedHash: row.serverSeedHash,
    clientSeed: row.clientSeed,
    nonce: row.nonce,
  });
  return { ok: true as const, clientSeed: clean };
}

/**
 * Reveal the current server seed and commit to a new one.
 *
 * The revealed seed is what makes past spins checkable, so this is the only way
 * a server seed ever leaves the server. The nonce restarts because the pair it
 * counted against is gone.
 */
export async function rotateServerSeed(userId: number, game: FairGame) {
  const current = await seedsFor(userId, game);
  const revealed = {
    serverSeed: current.serverSeed,
    serverSeedHash: current.serverSeedHash,
    nonce: current.nonce,
  };

  const next = freshServerSeed();
  const row = await prisma.gameFairSeed.update({
    where: { userId_game: { userId, game } },
    data: { ...next, nonce: 0 },
  });
  remember(userId, game, {
    serverSeed: row.serverSeed,
    serverSeedHash: row.serverSeedHash,
    clientSeed: row.clientSeed,
    nonce: row.nonce,
  });

  return { revealed, serverSeedHash: next.serverSeedHash };
}

/**
 * Claim the next nonce for a spin.
 *
 * The increment happens in the database and the row it returns is authoritative,
 * so two spins arriving at once get different nonces even across processes —
 * which matters, because a repeated nonce on the same pair replays a result.
 * The caller receives the nonce it owns.
 */
export async function reserveNonce(
  userId: number,
  game: FairGame,
): Promise<SeedState & { nonce: number }> {
  await seedsFor(userId, game);
  const row = await prisma.gameFairSeed.update({
    where: { userId_game: { userId, game } },
    data: { nonce: { increment: 1 } },
  });
  const state: SeedState = {
    serverSeed: row.serverSeed,
    serverSeedHash: row.serverSeedHash,
    clientSeed: row.clientSeed,
    nonce: row.nonce,
  };
  remember(userId, game, state);
  // The row now holds the *next* nonce; this spin owns the one before it.
  return { ...state, nonce: row.nonce - 1 };
}

/** Testing seam — drops the read cache without touching the database. */
export function __clearFairSeedCache() {
  cache.clear();
}
