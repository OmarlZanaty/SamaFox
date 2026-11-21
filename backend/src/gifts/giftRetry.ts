/** Retry policy for gift transactions. Kept dependency-free so it can be unit-tested. */

/**
 * Serialization failures AND Postgres deadlocks (40P01) both roll the whole transaction
 * back, so repeating the send is safe (the gift-operation ledger blocks any double charge).
 * «إرسال مجدداً» fires up to 3 parallel sends from one sender; they lock the same rows in
 * different orders and used to surface as «تعذر إرسال الهدية مجدداً».
 */
export function isRetryableTxConflict(e: any): boolean {
  const msg = String(e?.message ?? '');
  return e?.code === 'P2034' || msg.includes('could not serialize') || msg.includes('40001')
    || msg.includes('40P01') || msg.toLowerCase().includes('deadlock detected');
}

export async function retryTxConflicts<T>(
  fn: () => Promise<T>,
  attempts = 6,
  isBusinessError: (e: unknown) => boolean = () => false,
): Promise<T> {
  let last: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e: any) {
      if (!isRetryableTxConflict(e) || isBusinessError(e)) throw e;
      last = e;
      await new Promise((r) => setTimeout(r, 20 + Math.floor(Math.random() * 60) * (i + 1)));
    }
  }
  throw last;
}
