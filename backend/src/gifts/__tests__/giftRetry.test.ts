// «تعذر إرسال الهدية مجدداً»: parallel «إرسال مجدداً» sends deadlock in Postgres (40P01).
// A deadlock rolls the whole transaction back, so the send must be retried, not failed.
import test from 'node:test';
import assert from 'node:assert/strict';
import { retryTxConflicts, isRetryableTxConflict } from '../giftRetry';

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
  assert.equal(calls, 6);
});
