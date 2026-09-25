// Loaded before every test file (see "test" in package.json). src/utils/prisma
// refuses to load without DATABASE_URL, even though no test connects to a
// database — they all use in-memory fakes. A dummy URL is enough.
process.env.DATABASE_URL = process.env.DATABASE_URL || 'postgresql://test:test@127.0.0.1:1/test';
