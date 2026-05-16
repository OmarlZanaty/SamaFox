import { getRedis } from '../../lib/redis';

const VERSION_KEY = 'gifts:catalog:version';
const CACHE_KEY = (v: number) => `gifts:catalog:v${v}`;
const CACHE_TTL_SEC = 60;

let memVersion = 1;
let memCache: { version: number; expires: number; payload: string } | null = null;

export async function getCatalogVersion(): Promise<number> {
  const redis = getRedis();
  if (!redis) return memVersion;
  try {
    const v = await redis.get(VERSION_KEY);
    if (v == null) {
      await redis.set(VERSION_KEY, '1');
      return 1;
    }
    return Number(v) || 1;
  } catch {
    return memVersion;
  }
}

export async function bumpCatalogVersion(): Promise<number> {
  memVersion += 1;
  const redis = getRedis();
  if (!redis) return memVersion;
  try {
    const v = await redis.incr(VERSION_KEY);
    return v;
  } catch {
    return memVersion;
  }
}

export async function readCatalogCache(): Promise<{ version: number; payload: string } | null> {
  const redis = getRedis();
  const version = await getCatalogVersion();
  if (!redis) {
    if (memCache && memCache.version === version && memCache.expires > Date.now()) {
      return { version: memCache.version, payload: memCache.payload };
    }
    return null;
  }
  try {
    const payload = await redis.get(CACHE_KEY(version));
    if (!payload) return null;
    return { version, payload };
  } catch {
    return null;
  }
}

export async function writeCatalogCache(version: number, payload: string): Promise<void> {
  const redis = getRedis();
  if (!redis) {
    memCache = { version, payload, expires: Date.now() + CACHE_TTL_SEC * 1000 };
    return;
  }
  try {
    await redis.set(CACHE_KEY(version), payload, 'EX', CACHE_TTL_SEC);
  } catch {
    memCache = { version, payload, expires: Date.now() + CACHE_TTL_SEC * 1000 };
  }
}
