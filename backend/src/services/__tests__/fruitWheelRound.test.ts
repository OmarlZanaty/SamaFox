import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { WHEEL_ORDER, SEGMENTS, assertBalancedTable, parseBetKey, payoutFor, maxPayout, rollFromSeed, returnOf, presentationFor } from '../fruitWheelRound.math';
import { invalidateGameConfigCache } from '../gameConfig.service';
import { __resetHalalForTests } from '../halalGames.service';
import { startFruitWheelRoundEngine, stopFruitWheelRoundEngine, placeBet, undoBet, clearBets, repeatBets, getPublicState, refundOrphans,
  getHistory, getLayout, PHASE_MS, __test } from '../fruitWheelRound.service';

// ── In-memory carWheel tables ────────────────────────────────
const rounds = new Map<number, any>();
const stakes = new Map<number, any>();
const daily = new Map<string, any>();
let ids = 0;
const match = (row: any, where: any = {}): boolean => Object.entries(where).every(([k, v]: [string, any]) =>
  v && typeof v === 'object' && 'not' in v ? row[k] !== v.not : v && typeof v === 'object' && 'in' in v ? v.in.includes(row[k]) : k === 'stakes' ? [...stakes.values()].some(s => s.roundId === row.id && match(s, v.some)) : row[k] === v);
fakePrisma.fruitWheelSharedRound = {
  create: async ({ data }: any) => { const row = { id: ++ids, result: null, settledAt: null, ...data }; rounds.set(row.id, row); return row; },
  delete: async ({ where }: any) => rounds.delete(where.id),
  update: async ({ where, data }: any) => Object.assign(rounds.get(where.id), data),
  findMany: async ({ where }: any) => [...rounds.values()].filter(r => match(r, where)),
  aggregate: async () => ({ _max: { id: rounds.size ? Math.max(...rounds.keys()) : null } }),
};
fakePrisma.fruitWheelStake = {
  create: async ({ data }: any) => { const row = { id: ++ids, payout: 0, status: 'open', createdAt: new Date(), ...data }; stakes.set(row.id, row); return row; },
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
const io: any = { on: () => {}, off: () => {}, to: () => ({ emit: (event: string, payload: any) => emitted.push({ event, payload }) }) };

beforeEach(async () => {
  balances.clear(); accounts.clear(); settings.clear(); ledger.length = 0; economyLedger.length = 0; xpAwards.length = 0;
  rounds.clear(); stakes.clear(); daily.clear(); emitted.length = 0;
  accounts.set('GAME_POOL:fruitwheel', 100_000_000); accounts.set('PROGRAM', 0);
  balances.set(1, 100_000); balances.set(2, 100_000);
  invalidateGameConfigCache(); __resetHalalForTests();
  await startFruitWheelRoundEngine(io);
});
afterEach(() => stopFruitWheelRoundEngine());

const round = () => __test.getRound()!;
/** Runs betting → closing → spinning → result and waits for settlement. */
async function playOut() {
  await __test.advance(); // closing
  await __test.advance(); // spinning (rolls)
  const result = round().result!;
  await __test.advance(); // result → settle
  for (let i = 0; i < 50 && !emitted.some(e => e.event === 'fruitwheel_result'); i++) await new Promise(r => setTimeout(r, 10));
  return result;
}

// ── Maths ────────────────────────────────────────────────────
test('balanced table: each card returns 70%, crown cannot be staked', () => {
  assert.doesNotThrow(assertBalancedTable);
  assert.deepEqual(WHEEL_ORDER, ['watermelon', 'plum', 'watermelon', 'plum', 'sevens', 'watermelon', 'plum', 'watermelon', 'plum', 'crown']);
  assert.equal(SEGMENTS.reduce((sum, s) => sum + s.weight, 0), 10000);
  assert.equal(SEGMENTS.find(s => s.key === 'crown')!.weight, 0);
  for (const s of SEGMENTS) if (s.key !== 'crown') {
    assert.equal(s.multiplierX10 * s.weight, 70000);
    assert.equal(returnOf(s.key), .7);
  }
  for (const bad of ['crown', 'bonus', '777', 'constructor', '__proto__', '', null]) assert.equal(parseBetKey(bad), null);
  assert.equal(maxPayout({ watermelon: 1000, sevens: 100 }), 1600);
  assert.equal(payoutFor({ watermelon: 1000 }, 'watermelon'), 1600);
  assert.equal(payoutFor({ sevens: 100 }, 'sevens'), 560);
  assert.equal(payoutFor({ plum: 101 }, 'plum'), 161);
  assert.equal(payoutFor({ sevens: 101 }, 'sevens'), 565);
  assert.equal(payoutFor({ watermelon: 1000, sevens: 100 }, 'crown'), 0);
});
test('committed seed weights never roll crown and presentation stays in slots 0–8', () => {
  const counts: Record<string, number> = Object.fromEntries(SEGMENTS.map(s => [s.key, 0]));
  for (let i = 0; i < 200000; i++) counts[rollFromSeed(`seed-${i}`, i)]!++;
  assert.equal(counts.crown, 0);
  assert.throws(() => presentationFor('crown'), /Invalid FRUIT WHEEL outcome/);
  for (const s of SEGMENTS) {
    if (s.weight === 0) continue;
    const expected = 200000 * s.weight / 10000;
    assert.ok(Math.abs(counts[s.key]! - expected) < 6 * Math.sqrt(expected));
    for (let i = 0; i < 100; i++) {
      const p = presentationFor(s.key);
      assert.equal(WHEEL_ORDER[p.segment], s.key);
      assert.ok(p.segment >= 0 && p.segment <= 8);
      assert.ok(p.offset >= .15 && p.offset <= .85);
    }
  }
  assert.equal(rollFromSeed('abc', 7), rollFromSeed('abc', 7));
});

test('table config publishes decimal multipliers and compatible wheel indices', async () => {
  const layout = await getLayout();
  assert.deepEqual(layout.multipliers, { watermelon: 1.6, sevens: 5.6, plum: 1.6 });
  assert.deepEqual(layout.wheel, WHEEL_ORDER);
});

// ── The shared round ────────────────────────────────────────
test('a chip is charged once and shows in Total Bet and My total bet', async () => {
  const res: any = await placeBet(1, 'watermelon', 1000);
  assert.equal(res.ok, true);
  assert.equal(balances.get(1), 99_000);
  await placeBet(2, 'plum', 100);
  const state: any = getPublicState(1);
  assert.equal(state.totalBet, 1100);
  assert.equal(state.me.staked, 1000);
  assert.equal(state.totals.watermelon, 1000);
  assert.equal(state.playerCount, 2);
  assert.equal(stakes.size, 2);
});
test('bad chips, bad keys and missing coins move nothing', async () => {
  assert.equal((await placeBet(1, 'n:40', 100) as any).code, 'BAD_TARGET');
  assert.equal((await placeBet(1, 'watermelon', 250) as any).code, 'BAD_AMOUNT');
  balances.set(1, 50);
  assert.equal((await placeBet(1, 'watermelon', 100) as any).code, 'INSUFFICIENT_COINS');
  assert.equal(balances.get(1), 50);
  assert.equal(stakes.size, 0);
});
test('undo takes back only the last chip; clear refunds everything', async () => {
  await placeBet(1, 'watermelon', 1000);
  await placeBet(1, 'plum', 100);
  await placeBet(1, 'plum', 100);
  await undoBet(1);
  assert.equal(balances.get(1), 100_000 - 1100);
  assert.deepEqual((getPublicState(1) as any).me.stakes, { watermelon: 1000, 'plum': 100 });
  await clearBets(1);
  assert.equal(balances.get(1), 100_000);
  assert.equal((getPublicState(1) as any).me.staked, 0);
  assert.ok([...stakes.values()].every(s => s.status === 'refunded'));
});
test('a round settles: winners paid from the pool, chips settled, stakes split, history kept', async () => {
  await placeBet(1, 'watermelon', 1000);
  await placeBet(1, 'plum', 1000);
  const before = balances.get(1)!;
  const result = await playOut();
  const prize = payoutFor({ watermelon: 1000, plum: 1000 }, result);
  assert.equal(balances.get(1), before + prize);
  assert.ok([...stakes.values()].every(s => s.status === 'settled'));
  assert.equal(ledger.filter(r => r.kind === 'stake').reduce((a, r) => a + r.amount, 0), 2000);
  const settled = [...rounds.values()][0];
  assert.equal(settled.result, result);
  assert.equal(settled.totalBet, 2000);
  assert.equal(daily.get('fruitwheel:1').wagered, 2000);
  assert.equal(daily.get('fruitwheel:1').net, prize - 2000);
  const history = await getHistory(1);
  assert.equal(history.length, 1);
  assert.equal(history[0]!.prize, prize);
  assert.deepEqual((getPublicState() as any).history.slice(-1), [result]);
});
test('betting closes: no chips, undo or clear once the wheel is committed', async () => {
  await placeBet(1, 'watermelon', 1000);
  await __test.advance(); // closing
  assert.equal((await placeBet(1, 'watermelon', 100) as any).code, 'BETTING_CLOSED');
  assert.equal((await undoBet(1) as any).code, 'BETTING_CLOSED');
  assert.equal((await clearBets(1) as any).code, 'BETTING_CLOSED');
  assert.equal((getPublicState() as any).result, null); // not revealed before spinning
});
test('REPEAT replays last round all-or-nothing', async () => {
  await placeBet(1, 'watermelon', 10000);
  await placeBet(1, 'plum', 1000);
  await playOut();
  await __test.advance(); // next round
  const res: any = await repeatBets(1);
  assert.equal(res.ok, true);
  assert.deepEqual(res.stakes, { watermelon: 10000, 'plum': 1000 });
  await clearBets(1);
  balances.set(1, 10999);
  assert.equal((await repeatBets(1) as any).code, 'INSUFFICIENT_COINS');
  assert.equal(stakes.size, 4);
});
test('chips left open by a crash are refunded once on boot', async () => {
  await placeBet(1, 'watermelon', 1000);
  await placeBet(2, 'watermelon', 100);
  stopFruitWheelRoundEngine();
  await refundOrphans();
  await refundOrphans();
  assert.equal(balances.get(1), 100_000);
  assert.equal(balances.get(2), 100_000);
});
test('concurrent chips from one player never overdraw', async () => {
  balances.set(1, 1000);
  const out = await Promise.all([placeBet(1, 'watermelon', 1000), placeBet(1, 'plum', 1000), placeBet(1, 'plum', 1000)]);
  assert.equal(out.filter((r: any) => r.ok).length, 1);
  assert.equal(balances.get(1), 0);
});

test('REPEAT validates all segments and the round limit before charging any chip', async () => {
  __test.lastStakes.set(1, { watermelon: 100, sevens: 1_000_000 });
  balances.set(1, 5_000_000);
  await placeBet(1, 'sevens', 100);
  const before = balances.get(1);
  const count = stakes.size;
  assert.equal((await repeatBets(1) as any).code, 'MAX_BET');
  assert.equal(stakes.size, count);
  assert.equal(balances.get(1), before);
  assert.deepEqual(getPublicState(1)!.me!.stakes, { sevens: 100 });
  await clearBets(1);
  __test.lastStakes.set(1, { watermelon: 300, plum: 700 });
  const res = await repeatBets(1);
  assert.equal(res.ok, true);
  assert.equal(getPublicState(1)!.me!.stakes.watermelon, 300);
  assert.equal(getPublicState(1)!.me!.stakes.plum, 700);
});
test('seed hash is committed at betting and seed is revealed only at result', async () => {
  await placeBet(1, 'watermelon', 100);
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

test('third card and concurrent third chip rejected, undo frees the slot', async () => {
  const out = await Promise.all(['watermelon', 'plum', 'sevens'].map(k => placeBet(1, k, 100)));
  assert.equal(out.filter(r => r.ok).length, 2);
  assert.equal((out[2] as any).code, 'MAX_CARDS');
  assert.equal(stakes.size, 2);
  await undoBet(1);
  assert.equal((await placeBet(1, 'sevens', 100)).ok, true);
});
test('dashboard max is per card, including repeat; MIN is 100', async () => {
  settings.set('game_config', JSON.stringify({ fruitwheel: { enabled: true, maxBet: 1000 } }));
  invalidateGameConfigCache();
  assert.equal((await getLayout()).maxPerKey, 1000);
  assert.equal((await placeBet(1, 'watermelon', 1000)).ok, true);
  assert.equal((await placeBet(1, 'sevens', 1000)).ok, true);
  assert.equal(getPublicState(1)!.me!.staked, 2000);
  assert.equal((await placeBet(1, 'sevens', 100) as any).code, 'MAX_BET');
  await clearBets(1);
  __test.lastStakes.set(1, { watermelon: 1000, sevens: 1000 });
  assert.equal((await repeatBets(1)).ok, true);
  assert.equal((await placeBet(2, 'plum', 99) as any).code, 'BAD_AMOUNT');
});
test('repeat union cannot add a third card and charges nothing on rejection', async () => {
  await placeBet(1, 'plum', 100);
  __test.lastStakes.set(1, { watermelon: 1000, sevens: 1000 });
  const before = balances.get(1);
  assert.equal((await repeatBets(1) as any).code, 'MAX_CARDS');
  assert.equal(balances.get(1), before);
  assert.equal(stakes.size, 1);
});
test('reserve real maximum, split 30/70 at close, defensively pay nothing for old crown', async () => {
  await placeBet(1, 'watermelon', 1000);
  await placeBet(1, 'sevens', 100);
  assert.equal(round().players.get(1)!.reserved, 1600);
  await __test.advance();
  assert.equal(accounts.get('PROGRAM'), 330);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 100000770);
  await __test.advance();
  round().result = 'crown';
  await __test.advance();
  assert.equal(getPublicState(1)!.me!.payout, 0);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 100000770);
  assert.equal(balances.get(1), 98900);
});
test('77 pays 5.6 times from pool and history records actual payment', async () => {
  await placeBet(1, 'sevens', 1000);
  await __test.advance(); await __test.advance();
  round().result = 'sevens';
  await __test.advance();
  assert.equal(getPublicState(1)!.me!.payout, 5600);
  assert.equal(balances.get(1), 104600);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 100000000 + 700 - 5600);
  assert.equal((await getHistory(1))[0]!.prize, 5600);
  assert.equal(getPublicState()!.winners[0]!.staked, 1000);
});
test('empty rounds still spin; number advances and history retains ten results', async () => {
  assert.deepEqual(PHASE_MS, { betting: 15000, closing: 1000, spinning: 6000, result: 5000 });
  const first = getPublicState()!.round;
  for (let i = 0; i < 12; i++) {
    assert.equal(getPublicState()!.round, first + i);
    await playOut();
    assert.equal(getPublicState()!.phase, 'result');
    await __test.advance();
  }
  assert.equal(rounds.size, 0);
  assert.equal(getPublicState()!.history.length, 10);
});
test('insufficient pool rejects before charge and a late charge is refunded', async () => {
  accounts.set('GAME_POOL:fruitwheel', 0);
  assert.equal((await placeBet(1, 'sevens', 100) as any).code, 'PRIZE_POOL_LOW');
  assert.equal(balances.get(1), 100000);
  accounts.set('GAME_POOL:fruitwheel', 100000);
  const pending = placeBet(1, 'plum', 1000);
  await __test.advance();
  assert.equal((await pending as any).code, 'BETTING_CLOSED');
  assert.equal(balances.get(1), 100000);
});

test('a charge in flight at close is refunded before stake grants', async () => {
  const original = fakePrisma.user.updateMany;
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>(resolve => { entered = resolve; });
  const gate = new Promise<void>(resolve => { release = resolve; });
  fakePrisma.user.updateMany = async (args: any) => { entered(); await gate; return original(args); };
  try {
    const bet = placeBet(1, 'sevens', 1000);
    await started;
    const closing = __test.advance();
    release();
    assert.equal((await bet as any).code, 'BETTING_CLOSED');
    await closing;
    assert.equal(balances.get(1), 100000);
    assert.ok([...stakes.values()].every(s => s.status === 'refunded'));
    assert.equal(ledger.filter(r => r.kind === 'stake').length, 0);
  } finally { release(); fakePrisma.user.updateMany = original; }
});
test('concurrent first players share one row and the public round stays stable', async () => {
  await playOut(); await __test.advance(); // one idle round before the first real stake
  const number = getPublicState()!.round;
  const out = await Promise.all([placeBet(1, 'plum', 100), placeBet(2, 'sevens', 100)]);
  assert.ok(out.every(r => r.ok));
  assert.equal(rounds.size, 1);
  assert.equal(round().dbId, number);
  assert.equal(getPublicState()!.round, number);
  assert.equal(getPublicState()!.me, null);
  assert.equal(new Set([...stakes.values()].map(c => c.roundId)).size, 1);
});
test('history and winners show actual capped pool payment', async () => {
  settings.set('game_config', JSON.stringify({ fruitwheel: { enabled: true, maxWinPerRound: 500 } }));
  invalidateGameConfigCache();
  await placeBet(1, 'sevens', 1000);
  await __test.advance(); await __test.advance(); round().result = 'sevens';
  await __test.advance();
  assert.equal(getPublicState(1)!.me!.payout, 500);
  assert.equal((await getHistory(1))[0]!.prize, 500);
});
