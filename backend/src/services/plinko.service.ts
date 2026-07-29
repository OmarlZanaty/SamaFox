import crypto from 'crypto';
import prisma from '../utils/prisma';

// ─────────────────────────────────────────────────────────────────────────────
// بلينكو — PLINKO
//
// Unlike عجلة الحظ and طيّار there is no shared round engine here: every drop is
// a self-contained bet resolved the moment the player asks for it. The server
// decides the path, the slot and the payout; the client only animates a result
// that has already been settled.
// ─────────────────────────────────────────────────────────────────────────────

export type RiskLevel = 'low' | 'medium' | 'high';

export const MIN_ROWS = 8;
export const MAX_ROWS = 16;

/** Chips a player may stake on a single ball. */
export const MIN_BET = 10;
export const MAX_BET = 50_000;

/** How many results the history bar keeps. */
const HISTORY_LIMIT = 30;

// ── Multiplier tables ────────────────────────────────────────────────────────
// One row per board size (8..16 rows → 9..17 slots). Every table is symmetric
// and is weighted by the binomial distribution so the house keeps ~1%: the
// middle slots pay under 1x and are overwhelmingly the most likely landing
// spots, which is what funds the rare edge hits.

const LOW: Record<number, number[]> = {
  8: [5.6, 2.1, 1.1, 1, 0.5, 1, 1.1, 2.1, 5.6],
  9: [5.6, 2, 1.6, 1, 0.7, 0.7, 1, 1.6, 2, 5.6],
  10: [8.9, 3, 1.4, 1.1, 1, 0.5, 1, 1.1, 1.4, 3, 8.9],
  11: [8.4, 3, 1.9, 1.3, 1, 0.7, 0.7, 1, 1.3, 1.9, 3, 8.4],
  12: [10, 3, 1.6, 1.4, 1.1, 1, 0.5, 1, 1.1, 1.4, 1.6, 3, 10],
  13: [8.1, 4, 3, 1.9, 1.2, 0.9, 0.7, 0.7, 0.9, 1.2, 1.9, 3, 4, 8.1],
  14: [7.1, 4, 1.9, 1.4, 1.3, 1.1, 1, 0.5, 1, 1.1, 1.3, 1.4, 1.9, 4, 7.1],
  15: [15, 8, 3, 2, 1.5, 1.1, 1, 0.7, 0.7, 1, 1.1, 1.5, 2, 3, 8, 15],
  16: [16, 9, 2, 1.4, 1.4, 1.2, 1.1, 1, 0.5, 1, 1.1, 1.2, 1.4, 1.4, 2, 9, 16],
};

const MEDIUM: Record<number, number[]> = {
  8: [13, 3, 1.3, 0.7, 0.4, 0.7, 1.3, 3, 13],
  9: [18, 4, 1.7, 0.9, 0.5, 0.5, 0.9, 1.7, 4, 18],
  10: [22, 5, 2, 1.4, 0.6, 0.4, 0.6, 1.4, 2, 5, 22],
  11: [24, 6, 3, 1.8, 0.7, 0.5, 0.5, 0.7, 1.8, 3, 6, 24],
  12: [33, 11, 4, 2, 1.1, 0.6, 0.3, 0.6, 1.1, 2, 4, 11, 33],
  13: [43, 13, 6, 3, 1.3, 0.7, 0.4, 0.4, 0.7, 1.3, 3, 6, 13, 43],
  14: [58, 15, 7, 4, 1.9, 1, 0.5, 0.2, 0.5, 1, 1.9, 4, 7, 15, 58],
  15: [88, 18, 11, 5, 3, 1.3, 0.5, 0.3, 0.3, 0.5, 1.3, 3, 5, 11, 18, 88],
  16: [110, 41, 10, 5, 3, 1.5, 1, 0.5, 0.3, 0.5, 1, 1.5, 3, 5, 10, 41, 110],
};

const HIGH: Record<number, number[]> = {
  8: [29, 4, 1.5, 0.3, 0.2, 0.3, 1.5, 4, 29],
  9: [43, 7, 2, 0.6, 0.2, 0.2, 0.6, 2, 7, 43],
  10: [76, 10, 3, 0.9, 0.3, 0.2, 0.3, 0.9, 3, 10, 76],
  11: [120, 14, 5.2, 1.4, 0.4, 0.2, 0.2, 0.4, 1.4, 5.2, 14, 120],
  12: [170, 24, 8.1, 2, 0.7, 0.2, 0.2, 0.2, 0.7, 2, 8.1, 24, 170],
  13: [260, 37, 11, 4, 1, 0.2, 0.2, 0.2, 0.2, 1, 4, 11, 37, 260],
  14: [420, 56, 18, 5, 1.9, 0.3, 0.2, 0.2, 0.2, 0.3, 1.9, 5, 18, 56, 420],
  15: [620, 83, 27, 8, 3, 0.5, 0.2, 0.2, 0.2, 0.2, 0.5, 3, 8, 27, 83, 620],
  16: [1000, 130, 26, 9, 4, 2, 0.2, 0.2, 0.2, 0.2, 0.2, 2, 4, 9, 26, 130, 1000],
};

const TABLES: Record<RiskLevel, Record<number, number[]>> = {
  low: LOW,
  medium: MEDIUM,
  high: HIGH,
};

export function multipliersFor(risk: RiskLevel, rows: number): number[] {
  return TABLES[risk][rows] ?? TABLES[risk][MAX_ROWS]!;
}

/** Every table the client needs to draw a board before the first drop. */
export function getLayout() {
  const tables: Record<string, Record<number, number[]>> = {};
  for (const risk of ['low', 'medium', 'high'] as RiskLevel[]) {
    tables[risk] = {};
    for (let rows = MIN_ROWS; rows <= MAX_ROWS; rows++) {
      tables[risk][rows] = multipliersFor(risk, rows);
    }
  }
  return { minRows: MIN_ROWS, maxRows: MAX_ROWS, minBet: MIN_BET, maxBet: MAX_BET, tables };
}

// ── Provably fair ────────────────────────────────────────────────────────────
// Same contract as طيّار: the player holds the hash of the active server seed,
// picks their own client seed, and every drop bumps a per-player nonce. Given
// (serverSeed, clientSeed, nonce) anyone can recompute the exact path.

const sha256 = (input: string) => crypto.createHash('sha256').update(input).digest('hex');

interface SeedState {
  serverSeed: string;
  serverSeedHash: string;
  clientSeed: string;
  nonce: number;
}

const seeds = new Map<number, SeedState>();

function freshServerSeed(): { serverSeed: string; serverSeedHash: string } {
  const serverSeed = crypto.randomBytes(32).toString('hex');
  return { serverSeed, serverSeedHash: sha256(serverSeed) };
}

function seedsFor(userId: number): SeedState {
  let s = seeds.get(userId);
  if (!s) {
    s = { ...freshServerSeed(), clientSeed: `u${userId}`, nonce: 0 };
    seeds.set(userId, s);
  }
  return s;
}

export function getFairness(userId: number) {
  const s = seedsFor(userId);
  return { serverSeedHash: s.serverSeedHash, clientSeed: s.clientSeed, nonce: s.nonce };
}

export function setClientSeed(userId: number, seed: string) {
  const clean = String(seed ?? '').trim().slice(0, 64);
  if (!clean) return { ok: false as const, code: 'BAD_SEED', message: 'البذرة غير صالحة' };
  const s = seedsFor(userId);
  s.clientSeed = clean;
  return { ok: true as const, clientSeed: clean };
}

/**
 * Rotates the server seed and reveals the retired one so the player can verify
 * every drop they made under it.
 */
export function rotateServerSeed(userId: number) {
  const s = seedsFor(userId);
  const revealed = { serverSeed: s.serverSeed, serverSeedHash: s.serverSeedHash, nonce: s.nonce };
  const next = freshServerSeed();
  s.serverSeed = next.serverSeed;
  s.serverSeedHash = next.serverSeedHash;
  s.nonce = 0;
  return { revealed, serverSeedHash: next.serverSeedHash };
}

/**
 * Derives the ball path. One HMAC byte per row: even → left, odd → right, which
 * is a fair coin per peg and therefore a binomial landing distribution.
 * Returns the directions (0 = left, 1 = right) and the resulting slot index.
 */
export function derivePath(serverSeed: string, clientSeed: string, nonce: number, rows: number) {
  const directions: number[] = [];
  let slot = 0;

  // 32 bytes per HMAC is plenty for 16 rows, but loop anyway so the scheme
  // stays correct if MAX_ROWS ever grows past a single digest.
  let cursor = 0;
  let digest = crypto.createHmac('sha256', serverSeed).update(`${clientSeed}:${nonce}:0`).digest();

  for (let row = 0; row < rows; row++) {
    if (cursor >= digest.length) {
      digest = crypto
        .createHmac('sha256', serverSeed)
        .update(`${clientSeed}:${nonce}:${Math.floor(row / 32)}`)
        .digest();
      cursor = 0;
    }
    const dir = digest[cursor++]! & 1;
    directions.push(dir);
    slot += dir;
  }

  return { directions, slot };
}

/** Verification helper: recompute a drop from revealed seeds. */
export function verifyDrop(
  serverSeed: string,
  clientSeed: string,
  nonce: number,
  rows: number,
  risk: RiskLevel,
) {
  const { directions, slot } = derivePath(serverSeed, clientSeed, nonce, rows);
  return { directions, slot, multiplier: multipliersFor(risk, rows)[slot] };
}

// ── History ──────────────────────────────────────────────────────────────────

export interface DropRecord {
  nonce: number;
  risk: RiskLevel;
  rows: number;
  slot: number;
  multiplier: number;
  bet: number;
  payout: number;
  at: number;
}

const history = new Map<number, DropRecord[]>();

export function getHistory(userId: number): DropRecord[] {
  return history.get(userId) ?? [];
}

function remember(userId: number, record: DropRecord) {
  const list = history.get(userId) ?? [];
  list.unshift(record);
  if (list.length > HISTORY_LIMIT) list.length = HISTORY_LIMIT;
  history.set(userId, list);
}

// ── Dropping a ball ──────────────────────────────────────────────────────────

function normaliseRisk(value: unknown): RiskLevel | null {
  return value === 'low' || value === 'medium' || value === 'high' ? value : null;
}

export async function dropBall(userId: number, rawRisk: unknown, rawRows: unknown, rawBet: unknown) {
  const risk = normaliseRisk(rawRisk);
  if (!risk) return { ok: false as const, code: 'BAD_RISK', message: 'مستوى المخاطرة غير صالح' };

  const rows = Math.trunc(Number(rawRows));
  if (!Number.isFinite(rows) || rows < MIN_ROWS || rows > MAX_ROWS) {
    return { ok: false as const, code: 'BAD_ROWS', message: `عدد الصفوف بين ${MIN_ROWS} و ${MAX_ROWS}` };
  }

  const bet = Math.trunc(Number(rawBet));
  if (!Number.isFinite(bet) || bet < MIN_BET || bet > MAX_BET) {
    return {
      ok: false as const,
      code: 'BAD_BET',
      message: `الرهان بين ${MIN_BET} و ${MAX_BET} عملة`,
    };
  }

  // Charge first, and only if the balance actually covers it — updateMany with a
  // gte guard makes the debit atomic, so parallel drops cannot overdraw.
  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: bet } },
    data: { coinsBalance: { decrement: bet } },
  });
  if (charged.count === 0) {
    return { ok: false as const, code: 'INSUFFICIENT', message: 'رصيدك لا يكفي' };
  }

  const s = seedsFor(userId);
  const nonce = s.nonce++;

  let slot: number;
  let directions: number[];
  let multiplier: number;
  let payout: number;

  try {
    ({ directions, slot } = derivePath(s.serverSeed, s.clientSeed, nonce, rows));
    multiplier = multipliersFor(risk, rows)[slot]!;
    payout = Math.floor(bet * multiplier);

    if (payout > 0) {
      await prisma.user.update({
        where: { id: userId },
        data: { coinsBalance: { increment: payout } },
      });
    }
  } catch (err) {
    // Never keep the stake if we failed to resolve the drop.
    await prisma.user.update({
      where: { id: userId },
      data: { coinsBalance: { increment: bet } },
    });
    console.error('[plinko] drop failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'DROP_FAILED', message: 'تعذر إسقاط الكرة' };
  }

  const record: DropRecord = {
    nonce,
    risk,
    rows,
    slot,
    multiplier,
    bet,
    payout,
    at: Date.now(),
  };
  remember(userId, record);

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { coinsBalance: true },
  });

  return {
    ok: true as const,
    drop: { ...record, directions },
    balance: user?.coinsBalance ?? 0,
    serverSeedHash: s.serverSeedHash,
    clientSeed: s.clientSeed,
  };
}
