/**
 * Grants admin-dashboard access to an existing account.
 *
 * The dashboard only accepts email+password logins from users with isAdmin=true;
 * accounts created through Google sign-in have no password at all, so a
 * dedicated dashboard account has to be flagged here.
 *
 * Usage:  npx ts-node prisma/grant-admin.ts <email> [--super]
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error('usage: ts-node prisma/grant-admin.ts <email> [--super]');
    process.exit(1);
  }
  const isSuper = process.argv.includes('--super');

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    console.error(`No user with email ${email}`);
    process.exit(1);
  }

  const updated = await prisma.user.update({
    where: { email },
    data: { isAdmin: true, ...(isSuper && { isSuperAdmin: true }) },
  });
  console.log(`granted: id=${updated.id} ${updated.email} isAdmin=${updated.isAdmin} isSuperAdmin=${updated.isSuperAdmin}`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
