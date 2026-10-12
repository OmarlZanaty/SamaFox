import type { Prisma } from '@prisma/client';
import prisma from '../utils/prisma';

/**
 * Non-user balances (2026-09-26).
 *
 *   PROGRAM            the platform's share: 25% of game stakes, the program
 *                      part of every lucky gift, the program part of a CP break
 *   GAME_POOL:<game>   each game's prize pool: 75% of its stakes, and the only
 *                      money its prizes are ever paid from
 *
 * Every movement writes an economy_ledger row with the balance it left behind,
 * inside the caller's transaction, so the account and its history can never
 * disagree.
 */

export const PROGRAM_ACCOUNT = 'PROGRAM';
export const gamePoolAccount = (game: string) => `GAME_POOL:${normalizeGameKey(game)}`;

/** Ledger/engine keys and dashboard keys differ for one game ('neon_fortune'). */
export function normalizeGameKey(game: string): string {
  return String(game).trim().toLowerCase().replace(/_/g, '-');
}

type Tx = Prisma.TransactionClient | typeof prisma;

export interface Movement {
  kind: string;
  refType?: string | null;
  refId?: string | number | null;
  userId?: number | null;
}

/** Add to an account (creating it on first use). Returns the new balance. */
export async function creditAccount(tx: Tx, account: string, amount: number | bigint, m: Movement): Promise<bigint> {
  const delta = BigInt(amount);
  if (delta <= 0n) return (await readBalance(tx, account)) ?? 0n;
  const row = await (tx as any).economyAccount.upsert({
    where: { key: account },
    update: { balance: { increment: delta }, totalIn: { increment: delta } },
    create: { key: account, balance: delta, totalIn: delta },
    select: { balance: true },
  });
  await writeLedger(tx, account, delta, row.balance, m);
  return row.balance as bigint;
}

/**
 * Take from an account. With `allowNegative: false` (the default) the debit is
 * conditional — it happens only if the balance covers it — and the function
 * returns null when it does not, touching nothing.
 */
export async function debitAccount(
  tx: Tx,
  account: string,
  amount: number | bigint,
  m: Movement,
  opts: { allowNegative?: boolean } = {},
): Promise<bigint | null> {
  const delta = BigInt(amount);
  if (delta <= 0n) return (await readBalance(tx, account)) ?? 0n;
  const t = tx as any;
  if (opts.allowNegative) {
    const row = await t.economyAccount.upsert({
      where: { key: account },
      update: { balance: { decrement: delta }, totalOut: { increment: delta } },
      create: { key: account, balance: -delta, totalOut: delta },
      select: { balance: true },
    });
    await writeLedger(tx, account, -delta, row.balance, m);
    return row.balance as bigint;
  }
  const r = await t.economyAccount.updateMany({
    where: { key: account, balance: { gte: delta } },
    data: { balance: { decrement: delta }, totalOut: { increment: delta } },
  });
  if (r.count !== 1) return null;
  const after = (await readBalance(tx, account)) ?? 0n;
  await writeLedger(tx, account, -delta, after, m);
  return after;
}

export async function readBalance(tx: Tx, account: string): Promise<bigint | null> {
  const row = await (tx as any).economyAccount.findUnique({ where: { key: account }, select: { balance: true } });
  return row ? (row.balance as bigint) : null;
}

async function writeLedger(tx: Tx, account: string, delta: bigint, balanceAfter: bigint, m: Movement) {
  await (tx as any).economyLedger.create({
    data: {
      account,
      delta,
      balanceAfter,
      kind: m.kind,
      refType: m.refType ?? null,
      refId: m.refId == null ? null : String(m.refId),
      userId: m.userId ?? null,
    },
  });
}

/** Basis-point share of an amount, floored. 2500 bp of 1000 = 250. */
export function bpShare(amount: number, bp: number): number {
  return Math.floor((Math.max(0, amount) * Math.max(0, bp)) / 10_000);
}
