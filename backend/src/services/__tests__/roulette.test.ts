import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { WHEEL_ORDER, RED, colorOf, parseBetKey, payoutFor, maxPayout, rollFromSeed, MULTIPLIERS, returnOf, BetType } from '../roulette.math';
import { invalidateGameConfigCache } from '../gameConfig.service';
import { __resetHalalForTests } from '../halalGames.service';
import { startRouletteEngine, stopRouletteEngine, placeBet, undoBet, clearBets, repeatBets, getPublicState, refundOrphans,
  getHistory, __test } from '../roulette.service';

// ── In-memory roulette tables ────────────────────────────────
const rounds = new Map<number, any>();
const stakes = new Map<number, any>();
const daily = new Map<string, any>();
let ids = 0;
const match = (row: any, where: any = {}) => Object.entries(where).every(([k, v]: [string, any]) =>
  v && typeof v === 'object' && 'not' in v ? row[k] !== v.not : row[k] === v);
fakePrisma.rouletteRound = {
  create: async ({ data }: any) => { const row = { id: ++ids, result: null, settledAt: null, ...data }; rounds.set(row.id, row); return row; },
  delete: async ({ where }: any) => rounds.delete(where.id),
  update: async ({ where, data }: any) => Object.assign(rounds.get(where.id), data),
  findMany: async ({ where }: any) => [...rounds.values()].filter(r => match(r, where)),
  aggregate: async () => ({ _max: { id: rounds.size ? Math.max(...rounds.keys()) : null } }),
};
fakePrisma.rouletteStake = {
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
  accounts.set('GAME_POOL:roulette', 100_000_000); accounts.set('PROGRAM', 0);
  balances.set(1, 100_000); balances.set(2, 100_000);
  invalidateGameConfigCache(); __resetHalalForTests();
  await startRouletteEngine(io);
});
afterEach(() => stopRouletteEngine());

const round = () => __test.getRound()!;
/** Runs betting → closing → spinning → result and waits for settlement. */
async function playOut() {
  __test.advance(); // closing
  __test.advance(); // spinning (rolls)
  const result = round().result!;
  __test.advance(); // result → settle
  for (let i = 0; i < 50 && !emitted.some(e => e.event === 'roulette_result'); i++) await new Promise(r => setTimeout(r, 10));
  return result;
}

// ── Maths ────────────────────────────────────────────────────
test('European single-zero wheel: 37 pockets, standard order, no 00', () => {
  assert.equal(WHEEL_ORDER.length, 37);
  assert.deepEqual([...WHEEL_ORDER].sort((a, b) => a - b), Array.from({ length: 37 }, (_, i) => i));
  assert.deepEqual(WHEEL_ORDER.slice(0, 5), [0, 32, 15, 19, 4]);
  assert.equal(RED.size, 18);
  assert.equal(colorOf(0), 'green'); assert.equal(colorOf(32), 'red'); assert.equal(colorOf(15), 'black');
  // Colours alternate around the wheel after the zero.
  for (let i = 1; i < 36; i++) assert.notEqual(colorOf(WHEEL_ORDER[i]!), colorOf(WHEEL_ORDER[i + 1]!));
});
test('bet keys map to real table positions only', () => {
  assert.deepEqual(parseBetKey('n:17')!.numbers, [17]);
  assert.deepEqual(parseBetKey('split:17-20')!.numbers, [17, 20]);
  assert.deepEqual(parseBetKey('split:0-2')!.numbers, [0, 2]);
  assert.deepEqual(parseBetKey('street:16')!.numbers, [16, 17, 18]);
  assert.deepEqual(parseBetKey('corner:16-17-19-20')!.numbers, [16, 17, 19, 20]);
  assert.deepEqual(parseBetKey('six:31')!.numbers, [31, 32, 33, 34, 35, 36]);
  assert.deepEqual(parseBetKey('ff')!.numbers, [0, 1, 2, 3]);
  assert.equal(parseBetKey('column1')!.numbers.length, 12);
  for (const bad of ['n:37', 'n:-1', 'split:3-4', 'split:17-19', 'split:20-17', 'street:2', 'six:34', 'corner:3-4-6-7',
    'corner:16-17-19-21', 'n:1.5', 'banana', 'n:', '', 'split:0-4', 7]) assert.equal(parseBetKey(bad), null, String(bad));
});
test('payouts include the stake and match the table; zero loses every outside bet', () => {
  assert.equal(payoutFor({ 'n:17': 100 }, 17), 2600);
  assert.equal(payoutFor({ 'split:17-20': 100 }, 20), 1300);
  assert.equal(payoutFor({ 'street:16': 100 }, 18), 860);
  assert.equal(payoutFor({ 'corner:16-17-19-20': 100 }, 19), 650);
  assert.equal(payoutFor({ 'six:1': 100 }, 6), 430);
  assert.equal(payoutFor({ red: 500 }, 1), 700); // integer maths: 1.4 × 500 is exactly 700
  assert.equal(payoutFor({ black: 500 }, 1), 0);
  assert.equal(payoutFor({ odd: 100, even: 100 }, 8), 140);
  assert.equal(payoutFor({ dozen2: 1000 }, 13), 2100);
  assert.equal(payoutFor({ column3: 100 }, 36), 210);
  const outside = { red: 100, black: 100, odd: 100, even: 100, low: 100, high: 100, dozen1: 100, dozen2: 100, dozen3: 100,
    column1: 100, column2: 100, column3: 100 };
  assert.equal(payoutFor(outside, 0), 0);
  assert.equal(payoutFor({ ...outside, 'n:0': 100 }, 0), 2600);
  assert.equal(payoutFor({ ff: 100 }, 0), 650);
});
test('every bet returns under the 75% the prize pool receives', () => {
  const coverage: Record<BetType, number> = { straight: 1, split: 2, street: 3, corner: 4, sixLine: 6, firstFour: 4,
    red: 18, black: 18, odd: 18, even: 18, low: 18, high: 18, dozen1: 12, dozen2: 12, dozen3: 12, column1: 12, column2: 12, column3: 12 };
  for (const type of Object.keys(MULTIPLIERS) as BetType[]) {
    const r = returnOf(type, coverage[type]);
    assert.ok(r > 0.66 && r < 0.75, `${type} ${r}`);
  }
  assert.equal(maxPayout({ 'n:5': 100, red: 1000 }), 2600 + 1400);
});
test('the committed seed decides the pocket, uniformly', () => {
  assert.equal(rollFromSeed('abc', 7), rollFromSeed('abc', 7));
  const counts = new Array(37).fill(0);
  for (let i = 0; i < 37_000; i++) counts[rollFromSeed('seed', i)]++;
  for (const c of counts) assert.ok(c > 820 && c < 1180, String(c));
});

// ── The shared round ────────────────────────────────────────
test('a chip is charged once and shows in Total Bet and My total bet', async () => {
  const res: any = await placeBet(1, 'red', 1000);
  assert.equal(res.ok, true);
  assert.equal(balances.get(1), 99_000);
  await placeBet(2, 'n:7', 500);
  const state: any = getPublicState(1);
  assert.equal(state.totalBet, 1500);
  assert.equal(state.me.staked, 1000);
  assert.equal(state.totals.red, 1000);
  assert.equal(state.playerCount, 2);
  assert.equal(stakes.size, 2);
});
test('bad chips, bad keys and missing coins move nothing', async () => {
  assert.equal((await placeBet(1, 'n:40', 100) as any).code, 'BAD_TARGET');
  assert.equal((await placeBet(1, 'red', 250) as any).code, 'BAD_AMOUNT');
  balances.set(1, 50);
  assert.equal((await placeBet(1, 'red', 100) as any).code, 'INSUFFICIENT_COINS');
  assert.equal(balances.get(1), 50);
  assert.equal(stakes.size, 0);
});
test('undo takes back only the last chip; clear refunds everything', async () => {
  await placeBet(1, 'red', 1000);
  await placeBet(1, 'n:7', 500);
  await placeBet(1, 'n:7', 100);
  await undoBet(1);
  assert.equal(balances.get(1), 100_000 - 1500);
  assert.deepEqual((getPublicState(1) as any).me.stakes, { red: 1000, 'n:7': 500 });
  await clearBets(1);
  assert.equal(balances.get(1), 100_000);
  assert.equal((getPublicState(1) as any).me.staked, 0);
  assert.ok([...stakes.values()].every(s => s.status === 'refunded'));
});
test('a round settles: winners paid from the pool, chips settled, stakes split, history kept', async () => {
  await placeBet(1, 'red', 1000);
  await placeBet(1, 'black', 1000);
  await placeBet(1, 'n:0', 100);
  const before = balances.get(1)!;
  const result = await playOut();
  const prize = payoutFor({ red: 1000, black: 1000, 'n:0': 100 }, result);
  assert.equal(balances.get(1), before + prize);
  assert.ok([...stakes.values()].every(s => s.status === 'settled'));
  assert.equal(ledger.filter(r => r.kind === 'stake').reduce((a, r) => a + r.amount, 0), 2100);
  const settled = [...rounds.values()][0];
  assert.equal(settled.result, result);
  assert.equal(settled.totalBet, 2100);
  assert.equal(daily.get('roulette:1').wagered, 2100);
  assert.equal(daily.get('roulette:1').net, prize - 2100);
  const history = await getHistory(1);
  assert.equal(history.length, 1);
  assert.equal(history[0]!.prize, prize);
  assert.deepEqual((getPublicState() as any).history.slice(-1), [result]);
});
test('betting closes: no chips, undo or clear once the wheel is committed', async () => {
  await placeBet(1, 'red', 1000);
  __test.advance(); // closing
  assert.equal((await placeBet(1, 'red', 100) as any).code, 'BETTING_CLOSED');
  assert.equal((await undoBet(1) as any).code, 'BETTING_CLOSED');
  assert.equal((await clearBets(1) as any).code, 'BETTING_CLOSED');
  assert.equal((getPublicState() as any).result, null); // not revealed before spinning
});
test('REPEAT replays last round all-or-nothing', async () => {
  await placeBet(1, 'dozen1', 5000);
  await placeBet(1, 'n:7', 1000);
  await playOut();
  __test.advance(); // next round
  const res: any = await repeatBets(1);
  assert.equal(res.ok, true);
  assert.deepEqual(res.stakes, { dozen1: 5000, 'n:7': 1000 });
  await clearBets(1);
  balances.set(1, 5999);
  assert.equal((await repeatBets(1) as any).code, 'INSUFFICIENT_COINS');
  assert.equal(stakes.size, 4);
});
test('chips left open by a crash are refunded once on boot', async () => {
  await placeBet(1, 'red', 1000);
  await placeBet(2, 'n:3', 500);
  stopRouletteEngine();
  await refundOrphans();
  await refundOrphans();
  assert.equal(balances.get(1), 100_000);
  assert.equal(balances.get(2), 100_000);
});
test('concurrent chips from one player never overdraw', async () => {
  balances.set(1, 1000);
  const out = await Promise.all([placeBet(1, 'red', 1000), placeBet(1, 'black', 1000), placeBet(1, 'n:1', 1000)]);
  assert.equal(out.filter((r: any) => r.ok).length, 1);
  assert.equal(balances.get(1), 0);
});
