import crypto from 'crypto';
import prisma from '../utils/prisma';
import { grantStakeValue, releasePrize, reservePrize, settlePrize } from './halalGames.service';
import {
  getFairness as fairGetFairness,
  reserveNonce,
  rotateServerSeed as fairRotateServerSeed,
  setClientSeed as fairSetClientSeed,
} from './fairSeeds';

const GAME = 'plinko' as const;


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
// and weighted by the binomial distribution. These are the ORIGINAL ~99%
// tables; what is actually played is `scaledTable` below, which brings each
// one down to TARGET_RTP. The client draws the board from getLayout(), so the
// numbers a player sees are always exactly the numbers that pay.

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

const BASE_TABLES: Record<RiskLevel, Record<number, number[]>> = {
  low: LOW,
  medium: MEDIUM,
  high: HIGH,
};

/**
 * الصعوبة — the prize return each table is scaled to (was ~99%). Scaling every
 * slot by one factor keeps the board's shape; the player simply wins less.
 */
export const TARGET_RTP = Number(process.env.PLINKO_TARGET_RTP ?? 0.8);

/** P(landing in slot k) on an n-row board: C(n,k) / 2^n. */
export function slotOdds(rows: number): number[] {
  const out: number[] = [];
  let c = 1;
  for (let k = 0; k <= rows; k++) {
    out.push(c / 2 ** rows);
    c = (c * (rows - k)) / (k + 1);
  }
  return out;
}

export const tableRtp = (table: number[]) => {
  const odds = slotOdds(table.length - 1);
  return table.reduce((sum, m, k) => sum + m * odds[k]!, 0);
};

/**
 * Round DOWN to what the app can show: one decimal under 10x, whole numbers
 * from 10x (plinko_screen.dart `_fmt`). Anything else would put a figure on
 * the board that is not the figure paid. Never below 0.1x.
 */
const displayable = (v: number) =>
  v >= 10 ? Math.floor(v + 1e-9) : Math.max(0.1, Math.floor(v * 10 + 1e-9) / 10);

/** The largest single scale factor whose rounded table stays within target. */
function scaledTable(base: number[]): number[] {
  const apply = (f: number) => base.map((m) => displayable(m * f));
  let lo = 0;
  let hi = 1;
  if (tableRtp(apply(1)) <= TARGET_RTP) return apply(1);
  for (let i = 0; i < 50; i++) {
    const mid = (lo + hi) / 2;
    if (tableRtp(apply(mid)) <= TARGET_RTP) lo = mid;
    else hi = mid;
  }
  return apply(lo);
}

const TABLES: Record<RiskLevel, Record<number, number[]>> = { low: {}, medium: {}, high: {} };
for (const risk of ['low', 'medium', 'high'] as RiskLevel[]) {
  for (const [rows, table] of Object.entries(BASE_TABLES[risk])) {
    TABLES[risk][Number(rows)] = scaledTable(table);
  }
}

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

export const getFairness = (userId: number) => fairGetFairness(userId, GAME);
export const setClientSeed = (userId: number, seed: string) =>
  fairSetClientSeed(userId, GAME, seed);
/**
 * Rotates the server seed and reveals the retired one so the player can verify
 * everything they played under it.
 */
export const rotateServerSeed = (userId: number) => fairRotateServerSeed(userId, GAME);

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

  // The biggest prize this board can pay is promised before the coins move.
  const table = multipliersFor(risk, rows);
  const reserved = await reservePrize(userId, GAME, bet * Math.max(...table));
  if (!reserved.ok) return { ok: false as const, code: reserved.code, message: reserved.message };

  // Charge first, and only if the balance actually covers it — updateMany with a
  // gte guard makes the debit atomic, so parallel drops cannot overdraw.
  const charged = await prisma.user.updateMany({
    where: { id: userId, coinsBalance: { gte: bet } },
    data: { coinsBalance: { decrement: bet } },
  });
  if (charged.count === 0) {
    releasePrize(reserved.token);
    return { ok: false as const, code: 'INSUFFICIENT', message: 'رصيدك لا يكفي' };
  }

  // Reserved from the database, so two plays racing cannot draw the same nonce
  // and a restart cannot hand one out twice.
  let s: Awaited<ReturnType<typeof reserveNonce>>;
  try {
    s = await reserveNonce(userId, GAME);
  } catch (err) {
    releasePrize(reserved.token);
    await prisma.user.update({ where: { id: userId }, data: { coinsBalance: { increment: bet } } });
    console.error('[plinko] nonce reservation failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'DROP_FAILED', message: 'تعذر إسقاط الكرة' };
  }
  const nonce = s.nonce;

  // The stake is final: deliver the XP it bought before the ball is dropped.
  await grantStakeValue(userId, GAME, bet, `${userId}:${nonce}`);

  let slot: number;
  let directions: number[];
  let multiplier: number;
  let payout: number;

  try {
    ({ directions, slot } = derivePath(s.serverSeed, s.clientSeed, nonce, rows));
    multiplier = table[slot]!;
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
    releasePrize(reserved.token);
    console.error('[plinko] drop failed, bet refunded', { userId, bet, err });
    return { ok: false as const, code: 'DROP_FAILED', message: 'تعذر إسقاط الكرة' };
  }

  // The landing slot's multiplier is a prize from the fund.
  settlePrize(reserved.token, userId, GAME, payout, `${userId}:${nonce}`);

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
