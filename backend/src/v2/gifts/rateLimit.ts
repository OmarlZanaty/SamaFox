import { getRedis } from '../../lib/redis';

interface BucketSpec {
  capacity: number;
  refillPerSec: number;
}

const BUCKETS: Record<string, BucketSpec> = {
  gift_send: { capacity: 30, refillPerSec: 10 },
  admin_write: { capacity: 10, refillPerSec: 5 },
  upload: { capacity: 3, refillPerSec: 0.1 },
};

const TOKEN_BUCKET_LUA = `
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local cost = tonumber(ARGV[4])
local bucket = redis.call('HMGET', key, 'tokens', 'ts')
local tokens = tonumber(bucket[1])
local ts = tonumber(bucket[2])
if tokens == nil then
  tokens = capacity
  ts = now
end
local delta = math.max(0, now - ts)
tokens = math.min(capacity, tokens + delta * refill)
local allowed = 0
if tokens >= cost then
  tokens = tokens - cost
  allowed = 1
end
redis.call('HMSET', key, 'tokens', tokens, 'ts', now)
redis.call('EXPIRE', key, 3600)
return { allowed, tostring(tokens) }
`;

// In-memory fallback when Redis is unavailable.
const memBuckets = new Map<string, { tokens: number; ts: number }>();

function memAllow(key: string, spec: BucketSpec, cost: number): boolean {
  const now = Date.now() / 1000;
  const entry = memBuckets.get(key) ?? { tokens: spec.capacity, ts: now };
  const delta = Math.max(0, now - entry.ts);
  entry.tokens = Math.min(spec.capacity, entry.tokens + delta * spec.refillPerSec);
  entry.ts = now;
  if (entry.tokens >= cost) {
    entry.tokens -= cost;
    memBuckets.set(key, entry);
    return true;
  }
  memBuckets.set(key, entry);
  return false;
}

export async function consumeToken(
  bucketName: keyof typeof BUCKETS,
  subjectId: string | number,
  cost = 1,
): Promise<boolean> {
  const spec = BUCKETS[bucketName];
  if (!spec) throw new Error(`Unknown rate limit bucket: ${bucketName}`);
  const key = `ratelimit:${bucketName}:${subjectId}`;
  const redis = getRedis();
  if (!redis) return memAllow(key, spec, cost);
  try {
    const result = (await redis.eval(
      TOKEN_BUCKET_LUA,
      1,
      key,
      String(spec.capacity),
      String(spec.refillPerSec),
      String(Date.now() / 1000),
      String(cost),
    )) as [number, string];
    return result[0] === 1;
  } catch (err) {
    console.error('[rateLimit] eval failed, falling back to memory:', (err as Error).message);
    return memAllow(key, spec, cost);
  }
}

import type { Request, Response, NextFunction } from 'express';

export function rateLimitMw(bucketName: keyof typeof BUCKETS, getSubject: (req: Request) => string | number | null) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const subject = getSubject(req);
    if (subject == null) return res.status(401).json({ success: false, message: 'Unauthenticated' });
    const ok = await consumeToken(bucketName, subject);
    if (!ok) {
      return res.status(429).json({ success: false, message: 'Rate limit exceeded. Slow down.' });
    }
    return next();
  };
}
