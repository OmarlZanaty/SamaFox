import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { WHEEL_ORDER, SEGMENTS, assertBalancedTable, parseBetKey, payoutFor, maxPayout, rollFromSeed, returnOf } from '../carWheel.math';
import { invalidateGameConfigCache } from '../gameConfig.service';
import { __resetHalalForTests } from '../halalGames.service';
import { startCarWheelEngine, stopCarWheelEngine, placeBet, undoBet, clearBets, repeatBets, getPublicState, refundOrphans,
  getHistory, __test } from '../carWheel.service';

// ── In-memory carWheel tables ────────────────────────────────
const rounds = new Map<number, any>();
const stakes = new Map<number, any>();
const daily = new Map<string, any>();
let ids = 0;
const match = (row: any, where: any = {}): boolean => Object.entries(where).every(([k, v]: [string, any]) =>
  v && typeof v === 'object' && 'not' in v ? row[k] !== v.not : v && typeof v === 'object' && 'in' in v ? v.in.includes(row[k]) : k === 'stakes' ? [...stakes.values()].some(s => s.roundId === row.id && match(s, v.some)) : row[k] === v);
fakePrisma.carWheelRound = {
  create: async ({ data }: any) => { const row = { id: ++ids, result: null, settledAt: null, ...data }; rounds.set(row.id, row); return row; },
  delete: async ({ where }: any) => rounds.delete(where.id),
  update: async ({ where, data }: any) => Object.assign(rounds.get(where.id), data),
  findMany: async ({ where }: any) => [...rounds.values()].filter(r => match(r, where)),
  aggregate: async () => ({ _max: { id: rounds.size ? Math.max(...rounds.keys()) : null } }),
};
fakePrisma.carWheelStake = {
  create: async ({ data }: any) => { const row = { id: ++ids, status: 'open', createdAt: new Date(), ...data }; stakes.set(row.id, row); return row; },
  findUnique: async ({ where }: any) => stakes.get(where.id) ?? null,
  updateMany: async ({ where, data }: any) => {
    let count = 0;
    for (const s of stakes.values()) if (match(s, where)) { Object.assign(s, data); count++; }
    return { count };
  },
  findMany: async ({ where, include }: any) => [...stakes.values()].filter(s => match(s, where)).reverse()
    .map(s => include ? { ...s, round: rounds.get(s.roundId) } : s),
};
fakePrisma.gameDailyStat = {
  findUnique: async ({ where }: any) => daily.get(`${where.game_day_userId.game}:${where.game_day_userId.userId}`) ?? null,
  upsert: async ({ where, create, update }: any) => {
    const k = `${where.game_day_userId.game}:${where.game_day_userId.userId}`;
    const row = daily.get(k);
    if (!row) daily.set(k, { ...create });
    else { row.net += update.net.increment; row.wagered += update.wagered.increment; row.best = update.best; }
    return daily.get(k);
  },
  findMany: async () => [],
};
const emitted: { event: string; payload: any }[] = [];
const io: any = { to: () => ({ emit: (event: string, payload: any) => emitted.push({ event, payload }) }) };

beforeEach(async () => {
  balances.clear(); accounts.clear(); settings.clear(); ledger.length = 0; economyLedger.length = 0; xpAwards.length = 0;
  rounds.clear(); stakes.clear(); daily.clear(); emitted.length = 0;
  accounts.set('GAME_POOL:carwheel', 100_000_000); accounts.set('PROGRAM', 0);
  balances.set(1, 100_000); balances.set(2, 100_000);
  invalidateGameConfigCache(); __resetHalalForTests();
  await startCarWheelEngine(io);
});
afterEach(() => stopCarWheelEngine());

const round = () => __test.getRound()!;
/** Runs betting → closing → spinning → result and waits for settlement. */
async function playOut() {
  await __test.advance(); // closing
  await __test.advance(); // spinning (rolls)
  const result = round().result!;
  await __test.advance(); // result → settle
  for (let i = 0; i < 50 && !emitted.some(e => e.event === 'carwheel_result'); i++) await new Promise(r => setTimeout(r, 10));
  return result;
}

// ── Maths ────────────────────────────────────────────────────
test('table is balanced: every segment returns 73.81%, below the pool share', () => {
  assert.doesNotThrow(assertBalancedTable);
  assert.deepEqual(WHEEL_ORDER, ['aurelia', 'bavaro', 'stellaro', 'ferrarion', 'lambrex', 'voltara', 'porsenna', 'bentara']);
  for (const segment of SEGMENTS) {
    assert.equal(segment.multiplier * segment.weight, 6600);
    assert.equal(returnOf(segment.key), 6600 / 8942);
    assert.ok(returnOf(segment.key) < .75);
    assert.equal(parseBetKey(segment.key), segment);
  }
  for (const key of ['Aurelia', 'AURELIA', '', 'constructor', '__proto__', 0, null]) assert.equal(parseBetKey(key), null);
});
test('each segment pays only its own stake, including the original bet', () => {
  for (const segment of SEGMENTS) {
    assert.equal(payoutFor({ [segment.key]: 100 }, segment.key), 100 * segment.multiplier);
    for (const other of SEGMENTS.filter(s => s !== segment)) assert.equal(payoutFor({ [other.key]: 100 }, segment.key), 0);
  }
  assert.equal(maxPayout({ aurelia: 1000, lambrex: 100 }), 8800);
});
test('committed seeds produce the specified weighted frequencies', () => {
  const counts: Record<string, number> = Object.fromEntries(WHEEL_ORDER.map(k => [k, 0]));
  const samples = 200_000;
  for (let i = 0; i < samples; i++) counts[rollFromSeed('seed', i)]!++;
  for (const s of SEGMENTS) {
    const expected = samples * s.weight / 8942;
    assert.ok(Math.abs(counts[s.key]! - expected) < 6 * Math.sqrt(expected), `${s.key}: ${counts[s.key]} vs ${expected}`);
  }
  assert.equal(rollFromSeed('abc', 7), rollFromSeed('abc', 7));
});

// ── The shared round ────────────────────────────────────────
test('a chip is charged once and shows in Total Bet and My total bet', async () => {
  const res: any = await placeBet(1, 'aurelia', 1000);
  assert.equal(res.ok, true);
  assert.equal(balances.get(1), 99_000);
  await placeBet(2, 'porsenna', 100);
  const state: any = getPublicState(1);
  assert.equal(state.totalBet, 1100);
  assert.equal(state.me.staked, 1000);
  assert.equal(state.totals.aurelia, 1000);
  assert.equal(state.playerCount, 2);
  assert.equal(stakes.size, 2);
});
test('bad chips, bad keys and missing coins move nothing', async () => {
  assert.equal((await placeBet(1, 'n:40', 100) as any).code, 'BAD_TARGET');
  assert.equal((await placeBet(1, 'aurelia', 250) as any).code, 'BAD_AMOUNT');
  balances.set(1, 50);
  assert.equal((await placeBet(1, 'aurelia', 100) as any).code, 'INSUFFICIENT_COINS');
  assert.equal(balances.get(1), 50);
  assert.equal(stakes.size, 0);
});
test('undo takes back only the last chip; clear refunds everything', async () => {
  await placeBet(1, 'aurelia', 1000);
  await placeBet(1, 'porsenna', 100);
  await placeBet(1, 'porsenna', 100);
  await undoBet(1);
  assert.equal(balances.get(1), 100_000 - 1100);
  assert.deepEqual((getPublicState(1) as any).me.stakes, { aurelia: 1000, 'porsenna': 100 });
  await clearBets(1);
  assert.equal(balances.get(1), 100_000);
  assert.equal((getPublicState(1) as any).me.staked, 0);
  assert.ok([...stakes.values()].every(s => s.status === 'refunded'));
});
test('a round settles: winners paid from the pool, chips settled, stakes split, history kept', async () => {
  await placeBet(1, 'aurelia', 1000);
  await placeBet(1, 'bavaro', 1000);
  await placeBet(1, 'lambrex', 100);
  const before = balances.get(1)!;
  const result = await playOut();
  const prize = payoutFor({ aurelia: 1000, bavaro: 1000, 'lambrex': 100 }, result);
  assert.equal(balances.get(1), before + prize);
  assert.ok([...stakes.values()].every(s => s.status === 'settled'));
  assert.equal(ledger.filter(r => r.kind === 'stake').reduce((a, r) => a + r.amount, 0), 2100);
  const settled = [...rounds.values()][0];
  assert.equal(settled.result, result);
  assert.equal(settled.totalBet, 2100);
  assert.equal(daily.get('carwheel:1').wagered, 2100);
  assert.equal(daily.get('carwheel:1').net, prize - 2100);
  const history = await getHistory(1);
  assert.equal(history.length, 1);
  assert.equal(history[0]!.prize, prize);
  assert.deepEqual((getPublicState() as any).history.slice(-1), [result]);
});
test('betting closes: no chips, undo or clear once the wheel is committed', async () => {
  await placeBet(1, 'aurelia', 1000);
  await __test.advance(); // closing
  assert.equal((await placeBet(1, 'aurelia', 100) as any).code, 'BETTING_CLOSED');
  assert.equal((await undoBet(1) as any).code, 'BETTING_CLOSED');
  assert.equal((await clearBets(1) as any).code, 'BETTING_CLOSED');
  assert.equal((getPublicState() as any).result, null); // not revealed before spinning
});
test('REPEAT replays last round all-or-nothing', async () => {
  await placeBet(1, 'bentara', 10000);
  await placeBet(1, 'porsenna', 1000);
  await playOut();
  await __test.advance(); // next round
  const res: any = await repeatBets(1);
  assert.equal(res.ok, true);
  assert.deepEqual(res.stakes, { bentara: 10000, 'porsenna': 1000 });
  await clearBets(1);
  balances.set(1, 10999);
  assert.equal((await repeatBets(1) as any).code, 'INSUFFICIENT_COINS');
  assert.equal(stakes.size, 4);
});
test('chips left open by a crash are refunded once on boot', async () => {
  await placeBet(1, 'aurelia', 1000);
  await placeBet(2, 'voltara', 100);
  stopCarWheelEngine();
  await refundOrphans();
  await refundOrphans();
  assert.equal(balances.get(1), 100_000);
  assert.equal(balances.get(2), 100_000);
});
test('concurrent chips from one player never overdraw', async () => {
  balances.set(1, 1000);
  const out = await Promise.all([placeBet(1, 'aurelia', 1000), placeBet(1, 'bavaro', 1000), placeBet(1, 'stellaro', 1000)]);
  assert.equal(out.filter((r: any) => r.ok).length, 1);
  assert.equal(balances.get(1), 0);
});

test('REPEAT validates all segments and the round limit before charging any chip', async () => {
  __test.lastStakes.set(1, { aurelia: 100, lambrex: 1_000_000 });
  balances.set(1, 5_000_000);
  await placeBet(1, 'lambrex', 100);
  const before = balances.get(1);
  const count = stakes.size;
  assert.equal((await repeatBets(1) as any).code, 'MAX_BET');
  assert.equal(stakes.size, count);
  assert.equal(balances.get(1), before);
  assert.deepEqual(getPublicState(1)!.me!.stakes, { lambrex: 100 });
  __test.lastStakes.set(1, { aurelia: 300, porsenna: 700 });
  const res = await repeatBets(1);
  assert.equal(res.ok, true);
  assert.equal(getPublicState(1)!.me!.stakes.aurelia, 300);
  assert.equal(getPublicState(1)!.me!.stakes.porsenna, 700);
});
test('seed hash is committed at betting and seed is revealed only at result', async () => {
  await placeBet(1, 'aurelia', 100);
  const hash = getPublicState()!.seedHash;
  assert.equal(getPublicState()!.seed, null);
  await __test.advance();
  assert.equal(getPublicState()!.result, null);
  await __test.advance();
  assert.equal(typeof getPublicState()!.result, 'string');
  assert.equal(getPublicState()!.seed, null);
  await __test.advance();
  assert.equal(getPublicState()!.seedHash, hash);
  assert.equal(getPublicState()!.seed, round().seed);
});
