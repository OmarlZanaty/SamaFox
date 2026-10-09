import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
// coinFreeze reads settings through this same client, only at call time, so
// the import cycle is harmless.
import { guardCoinDecrement } from './coinFreeze';

const databaseUrl = process.env.DATABASE_URL?.trim();

if (!databaseUrl) {
  throw new Error('DATABASE_URL is not set. Add it to your environment.');
}

const isProd = process.env.NODE_ENV === 'production';

if (!isProd) {
  const isValidScheme =
    databaseUrl.startsWith('file:') ||
    databaseUrl.startsWith('postgresql://') ||
    databaseUrl.startsWith('postgres://');

  if (!isValidScheme) {
    console.warn('Unexpected DATABASE_URL format:', databaseUrl.substring(0, 20));
  }
}

// تجميد الكوينزات: every coin spend in the app is a `coinsBalance: { decrement }`
// on a user row, so the freeze is checked here, once, under all of them —
// gifts, every game, store, VIP, CP, paid DMs, and whatever is added next.
// Applies inside $transaction too. See coinFreeze.ts.
const prisma = new PrismaClient().$extends({
  query: {
    user: {
      async update({ args, query }) {
        await guardCoinDecrement(args);
        return query(args);
      },
      async updateMany({ args, query }) {
        await guardCoinDecrement(args);
        return query(args);
      },
    },
  },
}) as unknown as PrismaClient;

export default prisma;