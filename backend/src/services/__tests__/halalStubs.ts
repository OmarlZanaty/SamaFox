// Test-only: replace the Prisma client and the XP service (which drags in
// index.ts via notifications) with in-memory fakes, before any engine loads.
import * as path from 'node:path';
export const backend = path.resolve(__dirname, '../../..');
export const balances = new Map<number, number>();
export const ledger: any[] = [];
export const xpAwards: Array<{ userId: number; xp: number }> = [];
export const settings = new Map<string, string>();
const seeds = new Map<string, any>();
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
export const fakePrisma: any = {
  appSetting: {
    findUnique: async ({ where }: any) => (settings.has(where.key) ? { key: where.key, value: settings.get(where.key) } : null),
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
      _sum: { amount: ledger.filter((r) => r.day === where.day && r.kind === where.kind && (where.userId == null || r.userId === where.userId)).reduce((s, r) => s + r.amount, 0) },
    }),
  },
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
