/**
 * Express 'trust proxy' for this box (see the note in index.ts): only Caddy on
 * loopback may name the client through X-Forwarded-For, unless
 * TRUST_PROXY_HOPS asks for a fixed number of hops.
 */
export function trustProxySetting(env: Record<string, string | undefined>): number | string {
  const hops = Number(env['TRUST_PROXY_HOPS'] ?? 0);
  return Number.isFinite(hops) && hops > 0 ? hops : 'loopback';
}
