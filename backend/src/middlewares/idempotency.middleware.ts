import crypto from 'crypto';
import type { NextFunction, Request, Response } from 'express';
import prisma from '../utils/prisma';

const db = prisma as any;

/**
 * Idempotency for every endpoint that moves coins (2026-09-26, item 21).
 *
 * The app sends a fresh UUID per user action in `Idempotency-Key` (or
 * `X-Request-Id`, or `requestId` in the body). A retry of that action — a weak
 * connection resending the POST, Dio retrying, the user tapping again before
 * the answer came back — carries the SAME key, and gets the stored response of
 * the first attempt instead of running the operation twice.
 *
 *   first request      → row inserted as 'processing', handler runs, the
 *                        response it sends is stored, row → 'done'
 *   retry, done        → the stored status + body, header Idempotent-Replayed
 *   retry, in progress → 409 REQUEST_IN_PROGRESS (the first one is still
 *                        running; the app retries in a moment)
 *   same key, different request → 422 IDEMPOTENCY_KEY_REUSED
 *
 * The insert is the lock: (userId, key) is unique, so two copies racing in
 * parallel cannot both get through. Every response is stored, errors included —
 * a 5xx replayed is harmless, a 5xx that let the operation run again after it
 * had in fact committed is not.
 *
 * No key → the request runs exactly as before, so app builds that predate this
 * keep working (item 23).
 */

const KEY_MAX = 128;
const IN_PROGRESS_MESSAGE = 'العملية قيد التنفيذ — انتظر لحظة';

function readKey(req: Request): string | null {
  const h = (req.headers['idempotency-key'] ?? req.headers['x-request-id']) as string | undefined;
  const b = (req.body as any)?.requestId ?? (req.body as any)?.idempotencyKey;
  const raw = h ?? b;
  if (raw == null) return null;
  const key = String(raw).trim();
  if (!key) return null;
  return key.slice(0, KEY_MAX);
}

function hashRequest(req: Request, scope: string): string {
  const body = { ...(req.body ?? {}) } as Record<string, unknown>;
  delete body.requestId;
  delete body.idempotencyKey;
  return crypto
    .createHash('sha256')
    .update(`${scope}|${req.method}|${req.baseUrl}${req.path}|${JSON.stringify(body)}`)
    .digest('hex');
}

export function idempotent(scope: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const userId = (req as any).userId as number | undefined;
    const key = readKey(req);
    if (!userId || !key) return next();

    const requestHash = hashRequest(req, scope);

    try {
      await db.idempotencyKey.create({ data: { userId, key, scope, requestHash } });
    } catch (e: any) {
      if (e?.code !== 'P2002') {
        // The table being unreachable must not take payments down with it —
        // but it must not silently drop the protection either. Refuse.
        console.error('[idempotency] insert failed', { scope, userId, e: e?.message });
        return res.status(503).json({ success: false, code: 'IDEMPOTENCY_UNAVAILABLE', message: 'حاول مرة أخرى' });
      }
      const row = await db.idempotencyKey.findUnique({ where: { userId_key: { userId, key } } });
      if (!row) return res.status(409).json({ success: false, code: 'REQUEST_IN_PROGRESS', message: IN_PROGRESS_MESSAGE });
      if (row.requestHash !== requestHash || row.scope !== scope) {
        return res.status(422).json({
          success: false,
          code: 'IDEMPOTENCY_KEY_REUSED',
          message: 'هذا الطلب استُخدم مفتاحه لعملية أخرى',
        });
      }
      if (row.status === 'done' && row.responseStatus != null) {
        res.setHeader('Idempotent-Replayed', 'true');
        return res.status(row.responseStatus).json(row.responseBody ?? {});
      }
      return res.status(409).json({ success: false, code: 'REQUEST_IN_PROGRESS', message: IN_PROGRESS_MESSAGE });
    }

    // Capture whatever the handler answers and store it against the key —
    // BEFORE the answer leaves, so a retry that follows the answer can never
    // find the key still "in progress".
    const originalJson = res.json.bind(res);
    let stored = false;
    (res as any).json = (body: unknown) => {
      if (stored) return originalJson(body);
      stored = true;
      db.idempotencyKey
        .update({
          where: { userId_key: { userId, key } },
          data: {
            status: 'done',
            responseStatus: res.statusCode,
            responseBody: JSON.parse(JSON.stringify(body ?? {}, (_k, v) => (typeof v === 'bigint' ? v.toString() : v))),
            completedAt: new Date(),
          },
        })
        .catch((err: Error) => console.error('[idempotency] store failed', { scope, userId, err: err.message }))
        .finally(() => originalJson(body));
      return res;
    };
    return next();
  };
}

/** Housekeeping: keys older than `days` can no longer be a retry. */
export async function purgeOldIdempotencyKeys(days = 3): Promise<number> {
  const cutoff = new Date(Date.now() - days * 86_400_000);
  const r = await db.idempotencyKey.deleteMany({ where: { createdAt: { lt: cutoff } } });
  return r.count ?? 0;
}
