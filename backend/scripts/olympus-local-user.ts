/**
 * Creates a throwaway player and prints a bearer token, for local end-to-end
 * testing of بوابات أوليمبوس against a real running API.
 *
 *   npx ts-node --transpile-only scripts/olympus-local-user.ts
 *
 * Development only. It mints a token directly rather than going through the
 * login flow, so no password or provider account is needed.
 */

import jwt from 'jsonwebtoken';
import prisma from '../src/utils/prisma';

const COINS = 500_000;

async function main() {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET is not set');

  const email = 'olympus-local@example.invalid';
  const existing = await prisma.user.findUnique({ where: { email } });

  const user = existing
    ? await prisma.user.update({
        where: { id: existing.id },
        data: { coinsBalance: COINS },
      })
    : await prisma.user.create({
        data: { name: 'Olympus Tester', email, coinsBalance: COINS },
      });

  const token = jwt.sign({ userId: user.id }, secret, { expiresIn: '24h' });
  console.log(JSON.stringify({ userId: user.id, coins: user.coinsBalance, token }));
}

main()
  .catch((e) => {
    console.error(e.message);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
