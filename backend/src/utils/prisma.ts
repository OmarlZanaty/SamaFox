import { PrismaClient } from '@prisma/client';

const databaseUrl = process.env.DATABASE_URL?.trim();

if (!databaseUrl) {
  throw new Error('DATABASE_URL is not set. Add it to your environment before starting the server.');
}

if (!databaseUrl.startsWith('file:')) {
  throw new Error(
    `Invalid DATABASE_URL for current Prisma datasource provider (sqlite): "${databaseUrl}". ` +
      'Use a SQLite URL like "file:./dev.db" or update prisma/schema.prisma datasource provider to match your database.',
  );
}

const prisma = new PrismaClient();

export default prisma;
