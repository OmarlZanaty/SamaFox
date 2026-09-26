// Test-only: replace the Prisma client and the XP service (which drags in
// index.ts via notifications) with in-memory fakes, before any engine loads.
import * as path from 'node:path';
export const backend = path.resolve(__dirname, '../../..');
export const balances = new Map<number, number>();
export const ledger: any[] = [];
export const xpAwards: Array<{ userId: number; xp: number }> = [];
export const settings = new Map<string, string>();
/** economy_accounts: PROGRAM and GAME_POOL:<game>. */
export const accounts = new Map<string, number>();
export const economyLedger: any[] = [];
const seeds = new Map<string, any>();
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const n = (v: unknown) => Number(typeof v === 'bigint' ? v : v ?? 0);

function ledgerMatch(r: any, where: any) {
  if (where.day != null && r.day !== where.day) return false;
  if (where.kind != null && r.kind !== where.kind) return false;
  if (where.userId != null && r.userId !== where.userId) return false;
  if (where.game != null) {
    const g = where.game;
    if (typeof g === 'object' && Array.isArray(g.in)) {
      if (!g.in.includes(r.game)) return false;
    } else if (r.game !== g) return false;
  }
  return true;
}

export const fakePrisma: any = {
  appSetting: {
    findUnique: async ({ where }: any) => (settings.has(where.key) ? { key: where.key, value: settings.get(where.key) } : null),
    findMany: async ({ where }: any) =>
      [...settings.entries()].filter(([k]) => !where?.key?.in || where.key.in.includes(k)).map(([key, value]) => ({ key, value })),
    upsert: async ({ where, create }: any) => { settings.set(where.key, create.value); return {}; },
  },
  user: {
    updateMany: async ({ where, data }: any) => {
      await sleep(5);
      const bal = balances.get(where.id) ?? 0;
      if (bal < where.coinsBalance.gte) return { count: 0 };
      balances.set(where.id, bal - data.coinsBalance.decrement);
      return { count: 1 };
    },
    update: async ({ where, data }: any) => {
      const inc = data.coinsBalance?.increment ?? 0;
      const dec = data.coinsBalance?.decrement ?? 0;
      balances.set(where.id, (balances.get(where.id) ?? 0) + inc - dec);
      return { coinsBalance: balances.get(where.id) };
    },
    findUnique: async ({ where }: any) => ({ id: where.id, name: `u${where.id}`, avatarUrl: null, countryCode: 'EG', coinsBalance: balances.get(where.id) ?? 0 }),
  },
  gameLedger: {
    create: async ({ data }: any) => { ledger.push(data); return data; },
    aggregate: async ({ where }: any) => ({
      _sum: { amount: ledger.filter((r) => ledgerMatch(r, where)).reduce((s, r) => s + r.amount, 0) },
    }),
  },
  economyAccount: {
    findUnique: async ({ where }: any) => (accounts.has(where.key) ? { key: where.key, balance: BigInt(accounts.get(where.key)!) } : null),
    upsert: async ({ where, update, create }: any) => {
      const cur = accounts.get(where.key);
      const next =
        cur == null
          ? n(create.balance)
          : cur + n(update.balance?.increment) - n(update.balance?.decrement);
      accounts.set(where.key, next);
      return { key: where.key, balance: BigInt(next) };
    },
    updateMany: async ({ where, data }: any) => {
      const cur = accounts.get(where.key);
      if (cur == null || cur < n(where.balance?.gte)) return { count: 0 };
      accounts.set(where.key, cur - n(data.balance?.decrement) + n(data.balance?.increment));
      return { count: 1 };
    },
  },
  economyLedger: { create: async ({ data }: any) => { economyLedger.push(data); return data; } },
  gameDailyStat: { findMany: async () => [], upsert: async () => ({}) },
  gameFairSeed: {
    findUnique: async ({ where }: any) => seeds.get(where.userId_game.userId + ':' + where.userId_game.game) ?? null,
    create: async ({ data }: any) => { seeds.set(data.userId + ':' + data.game, { ...data }); return data; },
    update: async ({ where, data }: any) => {
      const k = where.userId_game.userId + ':' + where.userId_game.game;
      const row = seeds.get(k);
      for (const [f, v] of Object.entries(data)) row[f] = v && typeof v === 'object' && 'increment' in (v as any) ? row[f] + (v as any).increment : v;
      return { ...row };
    },
  },
  $transaction: async (fn: any) => (typeof fn === 'function' ? fn(fakePrisma) : Promise.all(fn)),
};
const put = (rel: string, exports: any) => {
  const p = require.resolve(path.resolve(__dirname, '../../..', rel));
  require.cache[p] = { id: p, filename: p, loaded: true, exports } as any;
};
put('src/utils/prisma', { __esModule: true, default: fakePrisma });
put('src/services/xp.service', {
  __esModule: true,
  awardUserXP: async (userId: number, xp: number) => { xpAwards.push({ userId, xp }); return { success: true, leveledUp: false }; },
  notifyLevelUp: async () => {},
});
