import crypto from 'crypto';
import prisma from '../utils/prisma';
import { GiftSendError, withSerializableRetry } from './giftService';

export interface GiftTransactionContext {
  tx: any;
  afterCommit: Array<() => Promise<unknown>>;
  beforeCommit: Array<() => void>;
}

// Keys are user-scoped, as in the existing middleware. Never purge this ledger.
export const giftOperationId = (senderId: number, key: string) =>
  crypto.createHash('sha256').update(`${senderId}:${key}`).digest('hex');

export function assertGiftReplay(row: any, senderId: number, requestHash: string) {
  if (row.senderId !== senderId || row.requestHash !== requestHash) {
    throw new GiftSendError('IDEMPOTENCY_KEY_REUSED', 'مفتاح الطلب مستخدم لعملية أخرى', 409);
  }
  return row.responseBody;
}

export async function runGiftOperation<T>(
  input: { senderId: number; id: string; requestHash: string },
  work: (context: GiftTransactionContext) => Promise<T>,
  db: any = prisma,
): Promise<{ body: T; replayed: boolean }> {
  const replay = async () => {
    const row = await db.giftOperation.findUnique({ where: { id: input.id } });
    return row ? { body: assertGiftReplay(row, input.senderId, input.requestHash) as T, replayed: true } : null;
  };
  const previous = await replay();
  if (previous) return previous;
  let effects: GiftTransactionContext['afterCommit'] = [];
  try {
    const body = await withSerializableRetry(() => db.$transaction(async (tx: any) => {
      const context: GiftTransactionContext = { tx, afterCommit: [], beforeCommit: [] };
      const body = await work(context);
      await tx.giftOperation.create({
        data: { ...input, responseBody: JSON.parse(JSON.stringify(body, (_k, v) => typeof v === 'bigint' ? v.toString() : v)) },
      });
      // Seat state is process-local. Abort the WHOLE payment if it changed
      // during any database await; a retry resolves a fresh snapshot.
      for (const check of context.beforeCommit) check();
      effects = context.afterCommit;
      return body;
    }, { isolationLevel: 'Serializable', maxWait: 10000, timeout: 60000 }));
    for (const effect of effects) {
      try { await effect(); } catch (e) { console.warn('[gift post-commit]', e); }
    }
    return { body: body as T, replayed: false };
  } catch (e: any) {
    if (e?.code === 'P2002' || e?.code === 'P2034') {
      const committed = await replay();
      if (committed) return committed;
    }
    throw e;
  }
}
