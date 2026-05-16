import IORedis, { Redis } from 'ioredis';

let client: Redis | null = null;
let warned = false;

export function getRedis(): Redis | null {
  if (client) return client;
  const url = process.env.REDIS_URL?.trim();
  if (!url) {
    if (!warned) {
      console.warn('[redis] REDIS_URL not set — gift cache and rate limiting will degrade to in-memory fallbacks');
      warned = true;
    }
    return null;
  }
  try {
    client = new IORedis(url, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
      lazyConnect: false,
      retryStrategy(times) {
        return Math.min(times * 200, 5000);
      },
    });
    client.on('error', (err) => {
      console.error('[redis] error:', err.message);
    });
  } catch (err) {
    console.error('[redis] failed to connect:', (err as Error).message);
    client = null;
  }
  return client;
}
