import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

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

const prisma = new PrismaClient();

export default prisma;