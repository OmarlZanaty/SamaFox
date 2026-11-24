// «تعذر إرسال الهدية مجدداً»: parallel «إرسال مجدداً» sends deadlock in Postgres (40P01).
// A deadlock rolls the whole transaction back, so the send must be retried, not failed.
import test from 'node:test';
import assert from 'node:assert/strict';
import { retryTxConflicts, isRetryableTxConflict, DEFAULT_RETRY_ATTEMPTS, serializeByKey, retryDelayMs } from '../giftRetry';

const deadlock = () => new Error(
  'Invalid `prisma.user.update()` invocation: PostgresError { code: "40P01", message: "deadlock detected" }');

test('a deadlock is retried until the send succeeds', async () => {
  let calls = 0;
  const result = await retryTxConflicts(async () => {
    if (++calls < 3) throw deadlock();
    return 'sent';
  });
  assert.equal(result, 'sent');
  assert.equal(calls, 3);
});

test('serialization failures are still retried', async () => {
  let calls = 0;
  const result = await retryTxConflicts(async () => {
    if (++calls < 2) throw Object.assign(new Error('x'), { code: 'P2034' });
    return 'ok';
  });
  assert.equal(result, 'ok');
  assert.ok(isRetryableTxConflict(new Error('could not serialize access')));
});

test('business errors are not retried', async () => {
  let calls = 0;
  const business = new Error('deadlock detected but it is a business error');
  await assert.rejects(retryTxConflicts(async () => { calls++; throw business; }, 6, (e) => e === business));
  assert.equal(calls, 1);
});

test('other errors are not retried', async () => {
  let calls = 0;
  await assert.rejects(retryTxConflicts(async () => { calls++; throw new Error('boom'); }), /boom/);
  assert.equal(calls, 1);
});

test('a deadlock that never clears is surfaced after the attempts run out', async () => {
  let calls = 0;
  await assert.rejects(retryTxConflicts(async () => { calls++; throw deadlock(); }), /deadlock/);
  assert.equal(calls, DEFAULT_RETRY_ATTEMPTS);
});

test('backoff is jittered, exponential and capped', () => {
  assert.ok(retryDelayMs(0, () => 0) >= 10);
  assert.ok(retryDelayMs(20, () => 0.999) <= 600);
  assert.ok(retryDelayMs(5, () => 0.999) > retryDelayMs(1, () => 0.999));
});

test('serializeByKey runs same-key work in order, different keys in parallel', async () => {
  const order: string[] = [];
  const slow = (tag: string, ms: number) => async () => { order.push(tag + ':start'); await new Promise((r) => setTimeout(r, ms)); order.push(tag + ':end'); };
  await Promise.all([serializeByKey('a', slow('a1', 30)), serializeByKey('a', slow('a2', 1)), serializeByKey('b', slow('b1', 5))]);
  assert.ok(order.indexOf('a1:end') < order.indexOf('a2:start'));
  assert.ok(order.indexOf('b1:start') < order.indexOf('a1:end'));
});

test('a failing job does not block the queue', async () => {
  await assert.rejects(serializeByKey('c', async () => { throw new Error('x'); }));
  assert.equal(await serializeByKey('c', async () => 'ok'), 'ok');
});

// L1 concurrency: 40 simultaneous accruals on ONE hot owner row never fail and never lose an increment.
test('commission accrual: concurrent increments on the hot owner row are all applied', async () => {
  const { applyCommissionAccrual } = await import('../agencyCommission');
  const rows = new Map<number, { t: bigint; g: bigint }>([[1, { t: 0n, g: 0n }], [2, { t: 0n, g: 0n }], [3, { t: 0n, g: 0n }]]);
  const locks = new Map<number, Promise<void>>();
  let injected = 0;
  const update = async ({ where, data }: any) => {
    const prev = locks.get(where.id) ?? Promise.resolve();
    let release!: () => void;
    locks.set(where.id, new Promise<void>((r) => { release = r; }));
    await prev;
    await new Promise((r) => setTimeout(r, 1));
    const row = rows.get(where.id)!;
    if (data.commissionTargetCoins) row.t += data.commissionTargetCoins.increment;
    if (data.commissionGeneratedCoins) row.g += data.commissionGeneratedCoins.increment;
    release();
  };
  // The conflict surfaces when the transaction starts (nothing applied yet), as a
  // real aborted transaction leaves no partial state behind.
  const conflict = () => { if (Math.random() < 0.3 && injected++ < 30) throw Object.assign(new Error('write conflict'), { code: 'P2034' }); };
  const db: any = { agencyMember: { update }, $transaction: async (fn: any) => { conflict(); return fn({ agencyMember: { update } }); } };
  await Promise.all(Array.from({ length: 40 }, (_, i) => applyCommissionAccrual({ ownerMemberId: 1, hostMemberId: 2 + (i % 2), amount: 10 }, db)));
  assert.equal(rows.get(1)!.t, 400n);
  assert.equal(rows.get(2)!.g + rows.get(3)!.g, 400n);
});
