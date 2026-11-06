import prisma from '../utils/prisma';
import { KNOWN_GAMES, getGameSettings, naturalMaxMultiplier } from './gameConfig.service';
import { PROGRAM_ACCOUNT, creditAccount, debitAccount, gamePoolAccount, normalizeGameKey, readBalance } from './economyAccounts.service';
import { reservedForGame } from './halalGames.service';
import { recordAdminAuditStrict as recordAdminAudit, type AdminAuditInput } from './adminAudit.service';

const db = prisma as any;

/**
 * «إدارة اقتصاد الألعاب» and «Lucky Management» numbers (2026-09-26).
 * Every figure is computed from the ledgers (game_ledger, economy_ledger,
 * lucky_rolls/lucky_rounds) — nothing is stored twice.
 */

const num = (v: unknown) => (v == null ? 0 : Number(v));

export function parseRange(from?: unknown, to?: unknown) {
  const now = new Date();
  const f = from ? new Date(String(from)) : new Date(now.getTime() - 30 * 86_400_000);
  const t = to ? new Date(String(to)) : now;
  return {
    from: Number.isFinite(f.getTime()) ? f : new Date(now.getTime() - 30 * 86_400_000),
    to: Number.isFinite(t.getTime()) ? t : now,
  };
}

export async function gameEconomyReport(from: Date, to: Date) {
  const rows: any[] = await db.$queryRawUnsafe(
    `SELECT game,
       COALESCE(SUM(CASE WHEN kind='stake' THEN amount END),0)::bigint                         AS bets,
       COALESCE(SUM(CASE WHEN kind='refund' THEN amount END),0)::bigint                        AS refunds,
       COALESCE(SUM(CASE WHEN kind='prize' THEN amount END),0)::bigint                         AS payouts,
       COALESCE(SUM(CASE WHEN kind IN ('stake','refund') THEN "programShare" END),0)::bigint   AS program,
       COALESCE(SUM(CASE WHEN kind IN ('stake','refund') THEN "poolShare" END),0)::bigint      AS pool,
       COUNT(*) FILTER (WHERE kind='stake')::int                                               AS rounds,
       COUNT(DISTINCT "userId") FILTER (WHERE kind='stake')::int                               AS players,
       COALESCE(MAX(amount) FILTER (WHERE kind='prize'),0)::bigint                             AS highest,
       COALESCE(AVG(amount) FILTER (WHERE kind='prize' AND amount>0),0)::float                 AS avgwin,
       COUNT(*) FILTER (WHERE kind='prize' AND amount>0)::int                                  AS wins,
       COUNT(*) FILTER (WHERE capped)::int                                                     AS capped
     FROM game_ledger
     WHERE "createdAt" >= $1 AND "createdAt" < $2
     GROUP BY game`,
    from,
    to,
  );
  const byGame = new Map<string, any>();
  for (const r of rows) {
    const k = normalizeGameKey(r.game);
    const cur = byGame.get(k);
    if (!cur) byGame.set(k, { ...r, game: k });
    else {
      for (const f of ['bets', 'refunds', 'payouts', 'program', 'pool', 'rounds', 'players', 'wins', 'capped']) cur[f] = num(cur[f]) + num(r[f]);
      cur.highest = Math.max(num(cur.highest), num(r.highest));
    }
  }

  const funding: any[] = await db.$queryRawUnsafe(
    `SELECT account, COALESCE(SUM(delta),0)::bigint AS funded
       FROM economy_ledger
      WHERE kind='POOL_FUNDING' AND account LIKE 'GAME_POOL:%' AND "createdAt" >= $1 AND "createdAt" < $2
      GROUP BY account`,
    from,
    to,
  );
  const fundedBy = new Map(funding.map((f) => [String(f.account).replace('GAME_POOL:', ''), num(f.funded)]));

  const games = await Promise.all(
    (KNOWN_GAMES as readonly string[]).map(async (game) => {
      const r = byGame.get(game) ?? {};
      const settings = await getGameSettings(game);
      const bets = num(r.bets) + num(r.refunds); // refunds are stored negative
      const payouts = num(r.payouts);
      const rounds = num(r.rounds);
      const wins = num(r.wins);
      const program = num(r.program);
      const pool = num(r.pool);
      const poolBalance = num(await readBalance(prisma, gamePoolAccount(game)));
      const funded = fundedBy.get(game) ?? 0;
      return {
        game,
        settings,
        naturalMaxMultiplier: naturalMaxMultiplier(game),
        totalBets: bets,
        totalPayouts: payouts,
        programShare: program,
        playerPrizePool: pool,
        netResult: bets - payouts,
        rounds,
        players: num(r.players),
        highestWin: num(r.highest),
        averageWin: Math.round(num(r.avgwin)),
        rtpActual: bets > 0 ? payouts / bets : null,
        rtpTarget: settings.rtpTargetBp != null ? settings.rtpTargetBp / 10_000 : null,
        lossRatio: rounds > 0 ? 1 - wins / rounds : null,
        profitLoss: program - funded,
        cappedPayouts: num(r.capped),
        poolBalance,
        poolReserved: reservedForGame(game),
        poolFundedInRange: funded,
      };
    }),
  );

  const sum = (f: string) => games.reduce((a, g: any) => a + num(g[f]), 0);
  return {
    range: { from, to },
    games,
    totals: {
      totalBets: sum('totalBets'),
      totalPayouts: sum('totalPayouts'),
      programShare: sum('programShare'),
      playerPrizePool: sum('playerPrizePool'),
      netResult: sum('netResult'),
      rounds: sum('rounds'),
      poolBalance: sum('poolBalance'),
      programAccount: num(await readBalance(prisma, PROGRAM_ACCOUNT)),
    },
  };
}

/**
 * Move coins from the PROGRAM account into a game's prize pool — the only way
 * a pool is ever topped up other than by stakes. The program account may go
 * negative (it is bookkeeping of the platform's own share); the pool never.
 */
export async function fundGamePool(game: string, amount: number, adminId: number) {
  const n = Math.floor(Number(amount));
  if (!Number.isFinite(n) || n <= 0) throw new Error('amount must be > 0');
  const key = normalizeGameKey(game);
  return db.$transaction(async (tx: any) => {
    await debitAccount(tx, PROGRAM_ACCOUNT, n, { kind: 'POOL_FUNDING', refType: 'game', refId: key, userId: adminId }, { allowNegative: true });
    const after = await creditAccount(tx, gamePoolAccount(key), n, { kind: 'POOL_FUNDING', refType: 'game', refId: key, userId: adminId });
    return { game: key, poolBalance: Number(after) };
  });
}

export async function fundLuckyPool(amount: number, adminId: number) {
  const n = Math.floor(Number(amount));
  if (!Number.isFinite(n) || n <= 0) throw new Error('amount must be > 0');
  return db.$transaction(async (tx: any) => {
    await debitAccount(tx, PROGRAM_ACCOUNT, n, { kind: 'POOL_FUNDING', refType: 'lucky', refId: 'lucky_pool', userId: adminId }, { allowNegative: true });
    const row = await tx.luckyPool.upsert({
      where: { id: 1 },
      update: { balance: { increment: BigInt(n) }, totalIn: { increment: BigInt(n) } },
      create: { id: 1, balance: BigInt(n), totalIn: BigInt(n) },
    });
    return { poolBalance: Number(row.balance) };
  });
}

type ResetAudit = Pick<AdminAuditInput, 'adminId' | 'reason' | 'ip' | 'sessionId' | 'userAgent' | 'device'>;

export class EconomyResetError extends Error {}

/** All balances and audit rows commit together. Locks serialize funding and resets. */
export async function resetEconomyPools(games: readonly string[], lucky: boolean, audit: ResetAudit, client = db) {
  if (!audit.reason || audit.reason.trim().length < 3) throw new EconomyResetError('Reason required / السبب مطلوب');
  const keys = [...new Set(games.map(normalizeGameKey))].sort();
  if (keys.some(key => !(KNOWN_GAMES as readonly string[]).includes(key))) throw new EconomyResetError('Unknown game / لعبة غير معروفة');
  return client.$transaction(async (tx: any) => {
    await tx.$executeRawUnsafe('LOCK TABLE economy_accounts, lucky_pool, lucky_rounds, lucky_rolls IN SHARE ROW EXCLUSIVE MODE');
    if (keys.some(key => reservedForGame(key) > 0)) throw new EconomyResetError('Active game reservations / توجد مبالغ محجوزة للعب');
    if (lucky && await tx.luckyRoll.count({ where: { status: 'PENDING' } })) throw new EconomyResetError('Pending lucky entries / توجد مشاركات محظوظ معلقة');
    const pools = [];
    for (const key of keys) {
      const account = gamePoolAccount(key);
      const before = (await readBalance(tx, account)) ?? 0n;
      if (before < 0n) throw new EconomyResetError('Negative pool / رصيد الصندوق سالب');
      const movement = { kind: 'POOL_RESET', refType: 'game', refId: key, userId: audit.adminId };
      const after = await debitAccount(tx, account, before, movement);
      if (after === null || after !== 0n) throw new EconomyResetError('Pool changed / تغير رصيد الصندوق');
      await creditAccount(tx, PROGRAM_ACCOUNT, before, movement);
      const out = { game: key, poolBalance: '0', transferred: String(before) };
      await recordAdminAudit(tx, { ...audit, action: 'GAME_POOL_RESET', targetType: 'game_pool', targetId: key, before: { poolBalance: before }, after: out });
      pools.push(out);
    }
    if (lucky) {
      const pool = await tx.luckyPool.findUnique({ where: { id: 1 } });
      const before = BigInt(pool?.balance ?? 0);
      if (before < 0n) throw new EconomyResetError('Negative pool / رصيد الصندوق سالب');
      if (before > 0n) {
        const changed = await tx.luckyPool.updateMany({ where: { id: 1, balance: { gte: before } }, data: { balance: { decrement: before }, totalOut: { increment: before } } });
        if (changed.count !== 1) throw new EconomyResetError('Pool changed / تغير رصيد الصندوق');
        // LuckyPool is the authoritative balance, not an EconomyAccount mirror.
        const movement = { kind: 'POOL_RESET', refType: 'lucky', refId: 'lucky_pool', userId: audit.adminId };
        await tx.economyLedger.create({ data: { account: 'LUCKY_POOL', delta: -before, balanceAfter: 0n, ...movement } });
        await creditAccount(tx, PROGRAM_ACCOUNT, before, movement);
      }
      const out = { game: 'lucky', poolBalance: '0', transferred: String(before) };
      await recordAdminAudit(tx, { ...audit, action: 'LUCKY_POOL_RESET', targetType: 'lucky_pool', targetId: '1', before: { poolBalance: before }, after: out });
      pools.push(out);
    }
    return { pools };
  });
}

/** Archive completed history, retaining financial/provably-fair evidence and configuration. */
export async function resetLuckyRounds(audit: ResetAudit, client = db) {
  if (!audit.reason || audit.reason.trim().length < 3) throw new EconomyResetError('Reason required / السبب مطلوب');
  return client.$transaction(async (tx: any) => {
    await tx.$executeRawUnsafe('LOCK TABLE lucky_pool, lucky_rounds, lucky_rolls IN SHARE ROW EXCLUSIVE MODE');
    if (await tx.luckyRoll.count({ where: { status: 'PENDING' } }) || await tx.luckyRound.count({ where: { status: 'OPEN' } })) throw new EconomyResetError('Active lucky rounds / توجد جولات محظوظ نشطة');
    const rolls = await tx.luckyRoll.updateMany({ where: { archived: false }, data: { archived: true } });
    const rounds = await tx.luckyRound.updateMany({ where: { archived: false, status: { not: 'OPEN' } }, data: { archived: true } });
    const pool = await tx.luckyPool.findUnique({ where: { id: 1 } });
    await tx.luckyPool.updateMany({ where: { id: 1 }, data: { totalIn: 0n, totalOut: 0n } });
    const out = { rolls: rolls.count, rounds: rounds.count, totalIn: '0', totalOut: '0' };
    await recordAdminAudit(tx, { ...audit, action: 'LUCKY_ROUNDS_RESET', targetType: 'lucky', targetId: 'history', before: { totalIn: pool?.totalIn ?? 0n, totalOut: pool?.totalOut ?? 0n }, after: out });
    return out;
  });
}

// ── Lucky ────────────────────────────────────────────────────

export async function luckyReport(from: Date, to: Date) {
  const [agg] = (await db.$queryRawUnsafe(
    `SELECT COUNT(*)::int AS entries,
            COUNT(DISTINCT "senderId")::int AS players,
            COALESCE(SUM("giftCoins"),0)::bigint AS "totalEntry",
            COALESCE(SUM("hostCoins"),0)::bigint AS "hostShare",
            COALESCE(SUM("programCoins"),0)::bigint AS "programShare",
            COALESCE(SUM("poolCoins"),0)::bigint AS "prizePool",
            COALESCE(SUM("payoutCoins"),0)::bigint AS "totalWin",
            COALESCE(MAX("payoutCoins"),0)::bigint AS "highestWin",
            COUNT(*) FILTER (WHERE multiplier>0)::int AS wins,
            COUNT(*) FILTER (WHERE status='PENDING')::int AS pending,
            COUNT(*) FILTER (WHERE status='NO_COMPETITION')::int AS "noCompetition"
       FROM lucky_rolls WHERE archived = false AND "createdAt" >= $1 AND "createdAt" < $2`,
    from,
    to,
  )) as any[];
  const byMult: any[] = await db.$queryRawUnsafe(
    `SELECT multiplier, COUNT(*)::int AS n, COALESCE(SUM("payoutCoins"),0)::bigint AS paid
       FROM lucky_rolls WHERE archived = false AND "createdAt" >= $1 AND "createdAt" < $2 AND status='SETTLED'
      GROUP BY multiplier ORDER BY multiplier`,
    from,
    to,
  );
  const rounds: any[] = await db.$queryRawUnsafe(
    `SELECT status, COUNT(*)::int AS n FROM lucky_rounds WHERE archived = false AND "startedAt" >= $1 AND "startedAt" < $2 GROUP BY status`,
    from,
    to,
  );
  const totalEntry = num(agg?.totalEntry);
  return {
    range: { from, to },
    entries: num(agg?.entries),
    players: num(agg?.players),
    totalEntry,
    hostShare: num(agg?.hostShare),
    programShare: num(agg?.programShare),
    prizePool: num(agg?.prizePool),
    totalWin: num(agg?.totalWin),
    highestWin: num(agg?.highestWin),
    wins: num(agg?.wins),
    pending: num(agg?.pending),
    noCompetition: num(agg?.noCompetition),
    rtpActual: totalEntry > 0 ? num(agg?.totalWin) / totalEntry : null,
    byMultiplier: byMult.map((m) => ({ multiplier: num(m.multiplier), count: num(m.n), paid: num(m.paid) })),
    rounds: Object.fromEntries(rounds.map((r) => [r.status, num(r.n)])),
  };
}

/** «سجل المحظوظ» — searchable by player ID, room, date and round. */
export async function luckyLog(q: {
  userId?: number | null;
  roomId?: number | null;
  roundCode?: string | null;
  from?: Date | null;
  to?: Date | null;
  page?: number;
  pageSize?: number;
}) {
  const where: any = { archived: false };
  if (q.userId) where.senderId = q.userId;
  if (q.roomId) where.roomId = q.roomId;
  if (q.from || q.to) where.createdAt = { ...(q.from ? { gte: q.from } : {}), ...(q.to ? { lt: q.to } : {}) };
  if (q.roundCode) {
    const round = await db.luckyRound.findUnique({ where: { code: q.roundCode.trim().toUpperCase() }, select: { id: true } });
    where.roundId = round?.id ?? -1;
  }
  const pageSize = Math.min(200, Math.max(1, q.pageSize ?? 50));
  const page = Math.max(1, q.page ?? 1);
  const [total, rows] = await Promise.all([
    db.luckyRoll.count({ where }),
    db.luckyRoll.findMany({ where, orderBy: { id: 'desc' }, skip: (page - 1) * pageSize, take: pageSize }),
  ]);
  const roundIds = [...new Set(rows.map((r: any) => r.roundId).filter((x: any) => x != null))];
  const userIds = [...new Set(rows.flatMap((r: any) => [r.senderId, r.recipientId]))];
  const roomIds = [...new Set(rows.map((r: any) => r.roomId).filter((x: any) => x != null))];
  const [rounds, users, rooms] = await Promise.all([
    roundIds.length ? db.luckyRound.findMany({ where: { id: { in: roundIds } }, select: { id: true, code: true, playerCount: true, status: true } }) : [],
    userIds.length ? db.user.findMany({ where: { id: { in: userIds } }, select: { id: true, name: true, displayId: true, avatarUrl: true } }) : [],
    roomIds.length ? db.room.findMany({ where: { id: { in: roomIds } }, select: { id: true, name: true } }) : [],
  ]);
  const rById = new Map(rounds.map((r: any) => [r.id, r]));
  const uById = new Map(users.map((u: any) => [u.id, u]));
  const roomById = new Map(rooms.map((r: any) => [r.id, r]));
  return {
    total,
    page,
    pageSize,
    rows: rows.map((r: any) => ({
      id: r.id,
      roundCode: r.roundId != null ? (rById.get(r.roundId) as any)?.code ?? null : null,
      roundPlayers: r.roundId != null ? (rById.get(r.roundId) as any)?.playerCount ?? null : null,
      roomId: r.roomId,
      roomName: r.roomId != null ? (roomById.get(r.roomId) as any)?.name ?? null : null,
      player: uById.get(r.senderId) ?? { id: r.senderId },
      host: uById.get(r.recipientId) ?? { id: r.recipientId },
      totalEntry: r.giftCoins,
      hostShare: r.hostCoins,
      programShare: r.programCoins,
      prizePool: r.poolCoins,
      multiplier: r.multiplier,
      win: r.payoutCoins,
      status: r.status,
      createdAt: r.createdAt,
      settledAt: r.settledAt,
    })),
  };
}

// ── Audit log viewer ─────────────────────────────────────────

export async function auditLog(q: { action?: string; adminId?: number; targetUserId?: number; targetType?: string; from?: Date; to?: Date; page?: number }) {
  const where: any = {};
  if (q.targetType) where.targetType = q.targetType;
  if (q.action) where.action = q.action.endsWith('*') ? { startsWith: q.action.slice(0, -1) } : q.action;
  if (q.adminId) where.adminId = q.adminId;
  if (q.targetUserId) where.targetUserId = q.targetUserId;
  if (q.from || q.to) where.createdAt = { ...(q.from ? { gte: q.from } : {}), ...(q.to ? { lt: q.to } : {}) };
  const page = Math.max(1, q.page ?? 1);
  const [total, rows] = await Promise.all([
    db.adminAuditLog.count({ where }),
    db.adminAuditLog.findMany({ where, orderBy: { id: 'desc' }, skip: (page - 1) * 50, take: 50 }),
  ]);
  const ids = [...new Set(rows.flatMap((r: any) => [r.adminId, r.targetUserId]).filter((x: any) => x != null))];
  const users = ids.length ? await db.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true, displayId: true } }) : [];
  const byId = new Map(users.map((u: any) => [u.id, u]));
  return {
    total,
    page,
    rows: rows.map((r: any) => ({
      ...r,
      admin: byId.get(r.adminId) ?? { id: r.adminId },
      targetUser: r.targetUserId != null ? byId.get(r.targetUserId) ?? { id: r.targetUserId } : null,
    })),
  };
}
