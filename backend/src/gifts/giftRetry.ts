/** Retry policy for gift transactions. Kept dependency-free so it can be unit-tested. */

/**
 * Serialization failures AND Postgres deadlocks (40P01) both roll the whole transaction
 * back, so repeating the send is safe (the gift-operation ledger blocks any double charge).
 * «إرسال مجدداً» fires up to 3 parallel sends from one sender; they lock the same rows in
 * different orders and used to surface as «تعذر إرسال الهدية مجدداً».
 */
export const DEFAULT_RETRY_ATTEMPTS = 10;

/** Exponential backoff with full jitter: random in [10, min(600, 25 * 2^attempt)] ms. */
export function retryDelayMs(attempt: number, rnd: () => number = Math.random): number {
  const cap = Math.min(600, 25 * 2 ** attempt);
  return 10 + Math.floor(rnd() * (cap - 10));
}

const queues = new Map<string, Promise<unknown>>();

/**
 * In-process FIFO per key: one sender's parallel sends run one after another
 * instead of fighting each other for the same rows. Different keys stay parallel.
 */
export function serializeByKey<T>(key: string, fn: () => Promise<T>): Promise<T> {
  const prev = queues.get(key) ?? Promise.resolve();
  const run = prev.then(fn, fn);
  const tail = run.then(() => undefined, () => undefined);
  queues.set(key, tail);
  tail.then(() => { if (queues.get(key) === tail) queues.delete(key); });
  return run;
}

export function isRetryableTxConflict(e: any): boolean {
  const msg = String(e?.message ?? '');
  return e?.code === 'P2034' || msg.includes('could not serialize') || msg.includes('40001')
    || msg.includes('40P01') || msg.toLowerCase().includes('deadlock detected');
}

export async function retryTxConflicts<T>(
  fn: () => Promise<T>,
  attempts = DEFAULT_RETRY_ATTEMPTS,
  isBusinessError: (e: unknown) => boolean = () => false,
): Promise<T> {
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e: any) {
      if (!isRetryableTxConflict(e) || isBusinessError(e)) throw e;
      last = e;
      // No sleep after the final attempt: it only delays the error (and, under
      // serializeByKey, every queued send of the same sender).
      if (i < attempts - 1) await new Promise((r) => setTimeout(r, retryDelayMs(i)));
    }
  }
  throw last;
}
