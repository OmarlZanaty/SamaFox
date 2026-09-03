/**
 * القط الجشع — behavioural checks for the daily board's database paths.
 *
 *   npm run check:greedy
 *
 * `sim:greedy` answers "does the money add up over half a million rounds". This
 * answers "does the board survive a restart, and does the ranking query say
 * what the ranking card shows" — the parts that only exist because
 * `game_daily_stats` was added, and that a Monte-Carlo run cannot touch.
 *
 * There is no Postgres in CI or on a dev laptop here, so this stubs
 * `src/utils/prisma` with a small in-memory stand-in before the service is
 * loaded. That means it verifies the *shape and semantics* of the queries the
 * service issues — the compound unique key, the filters, the ordering, the
 * cache/DB reconciliation — but not that Postgres accepts them. The migration
 * SQL is checked against `prisma migrate diff` output instead.
 *
 * Exits non-zero on the first failed check.
 */

const path = require('path');

// ── In-memory Prisma stand-in ───────────────────────────────
interface StatRow {
  id: string;
  game: string;
  day: string;
  userId: number;
  net: number;
  wagered: number;
  best: number;
  countryCode: string | null;
}

const stats: StatRow[] = [];
const users = new Map<number, { name: string; avatarUrl: string | null; countryCode: string | null; coinsBalance: number }>();

let upsertCount = 0;

function matches(row: StatRow, where: any): boolean {
  if (where.game !== undefined && row.game !== where.game) return false;
  if (where.day !== undefined && row.day !== where.day) return false;
  if (where.userId !== undefined && row.userId !== where.userId) return false;
  if (where.countryCode !== undefined && row.countryCode !== where.countryCode) return false;
  if (where.net?.gt !== undefined && !(row.net > where.net.gt)) return false;
  return true;
}

const fakePrisma = {
  gameDailyStat: {
    async findMany({ where = {}, orderBy, take, include }: any) {
      let rows = stats.filter((r) => matches(r, where));
      if (orderBy?.net === 'desc') rows = [...rows].sort((a, b) => b.net - a.net);
      if (typeof take === 'number') rows = rows.slice(0, take);
      if (include?.user) {
        return rows.map((r) => ({ ...r, user: users.get(r.userId) ?? null }));
      }
      return rows;
    },
    async upsert({ where, create, update }: any) {
      upsertCount++;
      const key = where.game_day_userId;
      if (!key) throw new Error('upsert must use the game_day_userId compound key');
      const existing = stats.find(
        (r) => r.game === key.game && r.day === key.day && r.userId === key.userId,
      );
      if (existing) {
        Object.assign(existing, update);
        return existing;
      }
      const row: StatRow = { id: `s${stats.length + 1}`, ...create };
      stats.push(row);
      return row;
    },
  },
  user: {
    async findUnique({ where }: any) {
      return users.get(where.id) ?? null;
    },
    async update({ where, data }: any) {
      const u = users.get(where.id);
      if (u && data.coinsBalance?.increment) u.coinsBalance += data.coinsBalance.increment;
      if (u && data.coinsBalance?.decrement) u.coinsBalance -= data.coinsBalance.decrement;
      return u;
    },
    async updateMany({ where, data }: any) {
      const u = users.get(where.id);
      const need = where.coinsBalance?.gte ?? 0;
      if (!u || u.coinsBalance < need) return { count: 0 };
      if (data.coinsBalance?.decrement) u.coinsBalance -= data.coinsBalance.decrement;
      return { count: 1 };
    },
  },
};

// Install the stub before the service is required, so its module-level
// `import prisma from '../utils/prisma'` resolves to this.
const prismaPath = require.resolve(path.join(__dirname, '../src/utils/prisma'));
require.cache[prismaPath] = {
  id: prismaPath,
  filename: prismaPath,
  loaded: true,
  exports: { __esModule: true, default: fakePrisma },
} as any;

// eslint-disable-next-line @typescript-eslint/no-var-requires
const service = require('../src/services/greedyCat.service');

// ── Harness ─────────────────────────────────────────────────
let failures = 0;

function check(label: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`  PASS  ${label}`);
  } else {
    failures++;
    console.error(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function seedUser(id: number, name: string, country: string | null, coins = 1_000_000) {
  users.set(id, { name, avatarUrl: null, countryCode: country, coinsBalance: coins });
}

function seedStat(userId: number, net: number, country: string | null, best = net) {
  stats.push({
    id: `seed${userId}`,
    game: 'greedy',
    day: today(),
    userId,
    net,
    wagered: Math.abs(net) * 2,
    best,
    countryCode: country,
  });
}

const fakeIo = { to: () => ({ emit: () => {} }) };

async function main() {
  console.log('القط الجشع — daily board checks\n');

  seedUser(1, 'ROSSO', 'SA');
  seedUser(2, 'ليان', 'SA');
  seedUser(3, 'MR_TIGER', 'EG');
  seedUser(4, 'خاسر', 'SA');

  // Yesterday's rows must never leak into today's board.
  stats.push({
    id: 'old', game: 'greedy', day: '2000-01-01', userId: 1,
    net: 99_999_999, wagered: 0, best: 0, countryCode: 'SA',
  });
  // Another game's rows must not either — that is what `game` is for.
  stats.push({
    id: 'other', game: 'crazy', day: today(), userId: 1,
    net: 88_888_888, wagered: 0, best: 0, countryCode: 'SA',
  });

  seedStat(1, 500_000, 'SA');
  seedStat(2, 250_000, 'SA');
  seedStat(3, 900_000, 'EG');
  seedStat(4, -40_000, 'SA');

  // ── 1. Ranking ────────────────────────────────────────────
  console.log('ranking');
  const global = await service.getRanking(null);
  check('orders by net descending', global[0]?.userId === 3 && global[1]?.userId === 1,
    `got ${global.map((r: any) => r.userId).join(',')}`);
  check('ranks are 1-based and sequential',
    global.every((r: any, i: number) => r.rank === i + 1));
  check('joins the user for name and avatar', global[0]?.name === 'MR_TIGER');
  check('excludes players who are down on the day',
    !global.some((r: any) => r.userId === 4));
  check('excludes other days', !global.some((r: any) => r.score === 99_999_999));
  check('excludes other games', !global.some((r: any) => r.score === 88_888_888));

  const region = await service.getRanking('SA');
  check('regional board filters by country',
    region.length === 2 && region.every((r: any) => r.countryCode === 'SA'),
    `got ${region.length} row(s)`);
  check('regional board keeps its own ordering', region[0]?.userId === 1);

  const capped = await service.getRanking(null, 1);
  check('honours the row limit', capped.length === 1);

  // ── 2. Hydration across a restart ─────────────────────────
  console.log('\nhydration');
  service.startGreedyCatEngine(fakeIo);
  // hydrateDaily is fire-and-forget; let its microtasks drain.
  await new Promise((r) => setTimeout(r, 30));

  const state = service.getPublicState(1);
  check('a restart restores the player\'s running total from the table',
    state?.today?.net === 500_000, `got ${state?.today?.net}`);
  check('a restart restores their record too',
    state?.today?.best === 500_000, `got ${state?.today?.best}`);
  const cold = service.getPublicState(999);
  check('an unknown player reads zero, not undefined',
    cold?.today?.net === 0 && cold?.today?.best === 0);

  // ── 3. Bet-time writes stay in the cache ──────────────────
  console.log('\nbetting');
  const before = upsertCount;
  const bet = await service.placeBet(1, 'tomato', 5_000);
  check('a bet is accepted', bet.ok === true, bet.message);
  check('a bet does not hit the stats table',
    upsertCount === before,
    `${upsertCount - before} write(s) — bets are meant to write through at settlement only`);
  check('the balance was actually charged', users.get(1)!.coinsBalance === 995_000);

  const cleared = await service.clearBets(1);
  check('clearing refunds', cleared.ok === true && users.get(1)!.coinsBalance === 1_000_000);
  check('clearing does not hit the stats table either', upsertCount === before);

  service.stopGreedyCatEngine();

  // ── 4. Category split still holds ─────────────────────────
  console.log('\ncategory split');
  service.startGreedyCatEngine(fakeIo);
  await new Promise((r) => setTimeout(r, 30));
  const cat = await service.placeBet(2, 'salad', 400);
  const saladKeys = service.CATEGORIES.salad;
  const split = saladKeys.map((k: string) => cat.bets[k]);
  check('a category stake divides evenly across its four symbols',
    split.every((v: number) => v === 100), `got ${split.join(',')}`);
  check('the split sums to the stake',
    split.reduce((a: number, b: number) => a + b, 0) === 400);
  const odd = await service.placeBet(2, 'salad', 402);
  check('a category stake that will not divide by four is rejected', odd.ok === false);
  service.stopGreedyCatEngine();

  // ── 5. Settlement write-through (opt-in: costs a full round) ──
  // A round is betting 30s + closing 5s + spinning 6s before `settle` runs, so
  // this is behind a flag rather than in the default run.
  if (process.argv.includes('--settle')) {
    console.log('');
    console.log('settlement write-through (waiting out a full round, ~50s)');
    service.startGreedyCatEngine(fakeIo);
    await new Promise((r) => setTimeout(r, 30));

    seedUser(5, 'مستقر', 'SA', 500_000);
    const staked = 20_000;
    await service.placeBet(5, 'fish', staked);
    const writesBefore = upsertCount;

    // Betting 30s + closing 5s + spinning 6s, plus a margin.
    await new Promise((r) => setTimeout(r, 45_000));

    const after = service.getPublicState(5);
    const persisted = stats.find((r) => r.userId === 5 && r.day === today() && r.game === 'greedy');

    check('settlement writes the player through to the table', persisted !== undefined);
    check('exactly one write per player per round',
      upsertCount - writesBefore === 1, `got ${upsertCount - writesBefore}`);
    check('the persisted net matches what the screen is showing',
      persisted?.net === after?.today?.net,
      `table ${persisted?.net} vs state ${after?.today?.net}`);
    check('the persisted row carries the country for the regional board',
      persisted?.countryCode === 'SA');
    // Win or lose, the row must exist — losers move the board too, and an
    // early `continue` for them was exactly the bug this guards against.
    const won = (persisted?.best ?? 0) > 0;
    check(`a ${won ? 'winning' : 'losing'} round is persisted`, persisted !== undefined);
    check('a losing round records no record payout',
      won || persisted?.best === 0, `best was ${persisted?.best}`);
    check('a losing round nets exactly the stake back out',
      won || persisted?.net === -staked, `net was ${persisted?.net}`);
    check('wagered accumulated from bet time survives the write-through',
      persisted?.wagered === staked, `got ${persisted?.wagered}`);

    service.stopGreedyCatEngine();
  } else {
    console.log('');
    console.log('settlement write-through: SKIPPED (pass --settle to run it, ~50s)');
  }

  console.log(
    failures === 0
      ? '\nAll checks passed.'
      : `\n${failures} check(s) FAILED.`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
