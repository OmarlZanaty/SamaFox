import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, balances, ledger, economyLedger, xpAwards, settings, fakePrisma } from './halalStubs';
import { WHEEL_ORDER, SEGMENTS, assertValidTable, parseBetKey, payoutFor, maxPayout, rollFromSeed, rollAmongFromSeed, returnOf, presentationFor, winningCards, payoutForResults } from '../fruitWheelRound.math';
import { invalidateGameConfigCache, getGameSettings, setGameSettings } from '../gameConfig.service';
import { bonusInterval } from '../fruitWheelRound.math';
import { __resetHalalForTests, freePrizePoolBalance, reservedForGame, reservePrize, releasePrize } from '../halalGames.service';
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
  findMany: async ({ where, orderBy, take }: any) => {
    const rows = [...rounds.values()].filter(r => match(r, where));
    if (orderBy?.id) rows.sort((a, b) => orderBy.id === 'desc' ? b.id - a.id : a.id - b.id);
    return rows.slice(0, take ?? rows.length);
  },
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
test('valid table: positive multipliers and natural weights, crown cannot be staked', () => {
  assert.doesNotThrow(assertValidTable);
  assert.deepEqual(WHEEL_ORDER, ['watermelon', 'plum', 'watermelon', 'plum', 'sevens', 'watermelon', 'plum', 'watermelon', 'plum', 'sevens']);
  assert.equal(SEGMENTS.reduce((sum, s) => sum + s.weight, 0), 10000);
  assert.deepEqual(SEGMENTS, [
    { key: 'watermelon', multiplierX10: 20, weight: 4500 },
    { key: 'plum', multiplierX10: 20, weight: 4500 },
    { key: 'sevens', multiplierX10: 80, weight: 1000 },
  ]);
  for (const s of SEGMENTS) {
    assert.ok(s.multiplierX10 > 0);
    assert.equal(returnOf(s.key), s.key === 'sevens' ? .8 : .9);
  }
  for (const bad of ['crown', 'bonus', '777', 'constructor', '__proto__', '', null]) assert.equal(parseBetKey(bad), null);
  assert.equal(maxPayout({ watermelon: 1000, sevens: 100 }), 2000);
  assert.equal(payoutFor({ watermelon: 1000 }, 'watermelon'), 2000);
  assert.equal(payoutFor({ sevens: 100 }, 'sevens'), 800);
  assert.equal(payoutFor({ plum: 101 }, 'plum'), 202);
  assert.equal(payoutFor({ sevens: 101 }, 'sevens'), 808);
  assert.equal(payoutFor({ watermelon: 1000, sevens: 100 }, 'crown'), 0);
});
test('committed seed weights exclude crown and presentation avoids slot nine', () => {
  const counts: Record<string, number> = Object.fromEntries(SEGMENTS.map(s => [s.key, 0]));
  for (let i = 0; i < 200000; i++) counts[rollFromSeed(`seed-${i}`, i)]!++;
  assert.equal(counts.crown, undefined);
  assert.equal(presentationFor('sevens').segment, 4);
  for (const s of SEGMENTS) {
    const expected = 200000 * s.weight / 10000;
    assert.ok(Math.abs(counts[s.key]! - expected) < 6 * Math.sqrt(expected));
    for (let i = 0; i < 100; i++) {
      const p = presentationFor(s.key);
      assert.equal(WHEEL_ORDER[p.segment], s.key);
      assert.ok(p.segment >= 0 && p.segment < 9);
      assert.ok(p.offset >= .15 && p.offset <= .85);
    }
  }
  assert.equal(rollFromSeed('abc', 7), rollFromSeed('abc', 7));
});

test('table config publishes restored multipliers and compatible wheel indices', async () => {
  const layout = await getLayout();
  assert.deepEqual(layout.multipliers, { watermelon: 2, sevens: 8, plum: 2 });
  assert.deepEqual(layout.wheel, WHEEL_ORDER);
  assert.equal(layout.maxPerKey, null);
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
  await setGameSettings('fruitwheel', { maxBet: 1_000_000 });
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
test('unfunded cards are excluded and stakes still split 30/70', async () => {
  accounts.set('GAME_POOL:fruitwheel', 0);
  await placeBet(1, 'watermelon', 1000);
  await placeBet(1, 'sevens', 100);
  assert.equal(round().players.get(1)!.reserved, 0);
  await playOut();
  assert.equal(round().result, 'plum');
  assert.equal(accounts.get('PROGRAM'), 330);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 770);
  assert.equal(getPublicState(1)!.me!.payout, 0);
});

test('77 pays 8 times from pool and history records actual payment', async () => {
  await placeBet(1, 'sevens', 1000);
  await __test.advance(); await __test.advance();
  round().result = 'sevens';
  await __test.advance();
  assert.equal(getPublicState(1)!.me!.payout, 8000);
  assert.equal(balances.get(1), 107000);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 100000000 + 700 - 8000);
  assert.equal((await getHistory(1))[0]!.prize, 8000);
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
test('empty pool accepts bets and a late charge is refunded', async () => {
  accounts.set('GAME_POOL:fruitwheel', 0);
  assert.equal((await placeBet(1, 'sevens', 100)).ok, true);
  await clearBets(1);
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

async function configureBonus(patch: Record<string, unknown> = {}) {
  await setGameSettings('fruitwheel', { bonusEveryRounds: 2, bonusMaxRounds: 2, ...patch });
  // Settings are snapshotted when a round starts, not changed during betting.
  stopFruitWheelRoundEngine();
  await startFruitWheelRoundEngine(io);
}

async function nextBonusRound(patch: Record<string, unknown> = {}) {
  await configureBonus(patch);
  await placeBet(1, 'plum', 100);
  await playOut();
  await __test.advance();
  assert.equal(getPublicState()!.roundsToBonus, 0);
}

test('bonus interval defaults to 13, supports fixed overrides and preserves explicit ranges', () => {
  assert.deepEqual(bonusInterval({}), { bonusEveryRounds: 13, bonusMaxRounds: 13 });
  assert.deepEqual(bonusInterval({ bonusEveryRounds: null, bonusMaxRounds: null }),
    { bonusEveryRounds: 13, bonusMaxRounds: 13 });
  assert.deepEqual(bonusInterval({ bonusEveryRounds: 5 }), { bonusEveryRounds: 5, bonusMaxRounds: 5 });
  assert.deepEqual(bonusInterval({ bonusEveryRounds: 20, bonusMaxRounds: 90 }),
    { bonusEveryRounds: 20, bonusMaxRounds: 90 });
});

for (const kind of ['double', 'triple'] as const) test(`default ${kind} bonus is due on occupied rounds 13 and 26 across players`, async () => {
  accounts.set('GAME_POOL:fruitwheel', kind === 'double' ? 10_000_000 : 100_000_000);
  assert.equal(getPublicState()!.bonusEveryRounds, 13);
  await playOut(); await __test.advance(); // Empty rounds do not advance the counter.
  for (let occupied = 1; occupied <= 26; occupied++) {
    assert.equal(getPublicState()!.roundsToBonus, 12 - ((occupied - 1) % 13));
    // Alternating players share the same table counter.
    const userId = occupied % 2 + 1;
    const cards = kind === 'double'
      ? winningCards(round().seed, round().number, 'sevens', 'double')
      : ['watermelon', 'plum'];
    for (const card of cards) {
      assert.equal((await placeBet(userId, card, 100)).ok, true);
    }
    await playOut();
    assert.equal(round().bonus, occupied % 13 === 0 ? kind : null);
    // Double pays 100 * 8 + 100 * 2; triple pays both staked fruits at 100 * 2 each.
    if (occupied % 13 === 0) assert.equal(getPublicState(userId)!.me!.payout, kind === 'double' ? 1000 : 400);
    await __test.advance();
  }
  assert.equal(getPublicState()!.roundsToBonus, 12);
});

test('engine honors stored fixed and ranged overrides', async () => {
  await configureBonus({ bonusEveryRounds: 5, bonusMaxRounds: 5 });
  assert.equal(getPublicState()!.bonusEveryRounds, 5);
  assert.equal(getPublicState()!.roundsToBonus, 4);
  await configureBonus({ bonusEveryRounds: 20, bonusMaxRounds: 90 });
  assert.equal(getPublicState()!.bonusEveryRounds, 20);
  assert.equal(getPublicState()!.roundsToBonus, null);
  assert.ok(round().roundsToBonus >= 19 && round().roundsToBonus <= 89);
});

test('bonus settings default, clear to defaults, and reject invalid values', async () => {
  const defaults = await getGameSettings('fruitwheel');
  assert.equal(defaults.bonusEnabled, true);
  assert.equal(defaults.bonusEveryRounds, 20);
  assert.equal(defaults.bonusMaxRounds, 90);
  assert.equal(defaults.tripleMinPool, 15_000_000);
  for (const patch of [
    { bonusEveryRounds: 1 }, { bonusEveryRounds: 1001 }, { bonusEveryRounds: 2.5 },
    { bonusEveryRounds: '20' }, { tripleMinPool: -1 }, { tripleMinPool: Infinity },
    { tripleMinPool: '10' }, { bonusEnabled: 'false' },
    { bonusMaxRounds: 1001 }, { bonusEveryRounds: 50, bonusMaxRounds: 30 },
  ]) await assert.rejects(setGameSettings('fruitwheel', patch as any));
  await setGameSettings('fruitwheel', { bonusEnabled: false, bonusEveryRounds: 1000, bonusMaxRounds: 1000, tripleMinPool: 0 });
  await setGameSettings('fruitwheel', { bonusEnabled: null, bonusEveryRounds: null, bonusMaxRounds: null, tripleMinPool: null });
  assert.deepEqual(await getGameSettings('fruitwheel'), defaults);
});

test('Nth occupied round is bonus; empty and cleared rounds do not count; reset after bonus and boot', async () => {
  await configureBonus({ bonusEveryRounds: 3, bonusMaxRounds: 3 });
  assert.equal(getPublicState()!.roundsToBonus, 2);
  await placeBet(1, 'plum', 100); await clearBets(1);
  await playOut(); await __test.advance();
  assert.equal(getPublicState()!.roundsToBonus, 2);
  for (let i = 0; i < 2; i++) {
    await placeBet(1, 'plum', 100); await playOut();
    assert.equal(round().bonus, null);
    await __test.advance();
  }
  assert.equal(getPublicState()!.roundsToBonus, 0);
  await playOut(); await __test.advance(); // empty due round doesn't consume bonus
  assert.equal(getPublicState()!.roundsToBonus, 0);
  await placeBet(1, 'plum', 100); await playOut();
  assert.equal(round().bonus, 'triple');
  await __test.advance();
  assert.equal(getPublicState()!.roundsToBonus, 2);
  await placeBet(1, 'plum', 100); await playOut();
  stopFruitWheelRoundEngine(); await startFruitWheelRoundEngine(io);
  assert.equal(getPublicState()!.roundsToBonus, 2);
});

test('double uses the specified SHA-256 salt and always starts with sevens', () => {
  const crypto = require('node:crypto');
  const selections = new Set<string>();
  for (let i = 0; i < 40; i++) {
    const rolled = rollFromSeed(`bonus-${i}`, i);
    const primary = rolled;
    const others = ['watermelon', 'plum'];
    const hash = crypto.createHash('sha256').update(`bonus-${i}:${i}:bonus`).digest('hex');
    const expected = ['sevens', others[Number(BigInt(`0x${hash}`) % 2n)]];
    const cards = winningCards(`bonus-${i}`, i, primary, 'double');
    assert.deepEqual(cards, expected);
    selections.add(cards[1]!);
    assert.deepEqual(new Set(winningCards(`bonus-${i}`, i, primary, 'triple')), new Set(['watermelon', 'plum', 'sevens']));
  }
  assert.equal(selections.size, 2);
});

for (const atThreshold of [false, true]) test(`triple threshold uses free pool including other reservations (${atThreshold})`, async () => {
  await nextBonusRound();
  await placeBet(1, 'plum', 1000);
  const held = await reservePrize(2, 'fruitwheel', 10000, 10000);
  assert.equal(held.ok, true);
  await __test.advance(); // split stakes first
  const free = await freePrizePoolBalance('fruitwheel');
  assert.equal(free, accounts.get('GAME_POOL:fruitwheel')! - reservedForGame('fruitwheel'));
  round().bonusSettings.tripleMinPool = free + (atThreshold ? 0 : 1);
  await __test.advance();
  assert.equal(round().bonus, atThreshold ? 'triple' : 'double');
  if (held.ok) releasePrize(held.token);
  await __test.advance();
});

for (const kind of ['double', 'triple'] as const) test(`${kind} pays both winning cards and preserves state, event, DB and history`, async () => {
  await nextBonusRound({ tripleMinPool: kind === 'double' ? 1_000_000_000 : 0 });
  const primary = kind === 'double' ? 'sevens' : rollFromSeed(round().seed, round().number);
  const cards = winningCards(round().seed, round().number, primary, kind);
  for (const card of cards.slice(0, 2)) assert.equal((await placeBet(1, card, 1000)).ok, true);
  const bets = { ...round().players.get(1)!.stakes };
  const before = balances.get(1)!;
  await playOut();
  const expected = payoutForResults(bets, cards);
  assert.equal(round().bonus, kind);
  assert.equal(round().result, primary);
  assert.notEqual(round().result, 'crown');
  assert.equal(WHEEL_ORDER[round().segment!], primary);
  assert.ok(!cards.includes('crown'));
  assert.equal(balances.get(1), before + expected);
  assert.equal(getPublicState(1)!.me!.payout, expected);
  assert.equal(round().winners[0]!.payout, expected);
  assert.deepEqual(getPublicState()!.results, cards);
  assert.deepEqual(getPublicState()!.history.slice(-1), [primary]);
  assert.deepEqual(getPublicState()!.historyRows.slice(-1)[0]!.results, cards);
  const event = emitted.filter(e => e.event === 'fruitwheel_result').slice(-1)[0]!.payload;
  assert.equal(event.bonus, kind); assert.deepEqual(event.results, cards);
  const row = rounds.get(round().dbId!);
  assert.equal(row.result, primary); assert.deepEqual(JSON.parse(row.bonus), cards);
  const history = (await getHistory(1)).find(h => h.round === row.id)!;
  assert.equal(history.prize, expected); assert.equal(history.bonus, kind); assert.deepEqual(history.results, cards);
  assert.equal(reservedForGame('fruitwheel'), 0);
  stopFruitWheelRoundEngine(); await startFruitWheelRoundEngine(io);
  assert.deepEqual(getPublicState()!.historyRows.slice(-1)[0]!.results, cards);
});

for (const fallback of ['double', 'plain'] as const) test(`unfunded bonus downgrades to ${fallback}`, async () => {
  await nextBonusRound({ tripleMinPool: 0 });
  const double = winningCards(round().seed, round().number, 'sevens', 'double');
  const excluded = ['watermelon', 'plum'].find(c => !double.includes(c))!;
  await placeBet(1, double[1]!, 1000);
  await placeBet(2, fallback === 'double' ? excluded : double[1]!, 1000);
  await __test.advance();
  accounts.set('GAME_POOL:fruitwheel', 2000);
  await __test.advance();
  assert.equal(round().bonus, fallback === 'double' ? 'double' : null);
  if (fallback === 'double') assert.deepEqual(round().results, double);
  else assert.equal(round().results.length, 1);
  await __test.advance();
  const paid = [...round().players.values()].reduce((n, p) => n + p.payout, 0);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 2000 - paid);
  assert.equal(reservedForGame('fruitwheel'), 0);
  await __test.advance(); assert.equal(getPublicState()!.roundsToBonus, 1);
});

test('bonus disabled never adds winners and plain history has additive defaults', async () => {
  await configureBonus({ bonusEnabled: false });
  for (let i = 0; i < 5; i++) {
    await placeBet(1, 'plum', 100); await playOut();
    assert.equal(round().bonus, null);
    assert.deepEqual(getPublicState()!.results, [round().result]);
    assert.equal(getPublicState()!.bonusEnabled, false);
    await __test.advance();
  }
  for (const row of await getHistory(1)) {
    assert.equal(row.bonus, null); assert.deepEqual(row.results, [row.result]);
  }
});

test('bonus keeps round payout caps and reports the actual credited amount everywhere', async () => {
  await nextBonusRound({ tripleMinPool: 0, maxWinPerRound: 500 });
  await placeBet(1, 'watermelon', 1000);
  await placeBet(1, 'plum', 1000);
  await playOut();
  assert.equal(round().bonus, 'triple');
  assert.equal(getPublicState(1)!.me!.payout, 500);
  assert.equal(round().winners[0]!.payout, 500);
  assert.equal((await getHistory(1))[0]!.prize, 500);
  assert.equal(daily.get('fruitwheel:1').wagered, 2100);
  assert.equal(reservedForGame('fruitwheel'), 0);
});

test('a pool read error cannot stop the table or announce an unfunded bonus', async () => {
  await nextBonusRound({ tripleMinPool: 0 });
  await placeBet(1, 'plum', 1000);
  await __test.advance();
  const read = fakePrisma.economyAccount.findUnique;
  fakePrisma.economyAccount.findUnique = async () => { throw new Error('pool unavailable'); };
  try {
    await __test.advance();
    assert.equal(round().phase, 'spinning');
    assert.equal(round().bonus, null);
  } finally { fakePrisma.economyAccount.findUnique = read; }
  await __test.advance();
  assert.equal(reservedForGame('fruitwheel'), 0);
});

test('restricted draws are deterministic and retain relative weights', () => {
  let sevens = 0;
  for (let i = 0; i < 10000; i++) {
    const result = rollAmongFromSeed(`allowed-${i}`, i, ['plum', 'sevens']);
    assert.ok(['plum', 'sevens'].includes(result));
    assert.equal(result, rollAmongFromSeed(`allowed-${i}`, i, ['sevens', 'plum']));
    if (result === 'sevens') sevens++;
  }
  assert.ok(Math.abs(sevens / 10000 - 1000 / 5500) < .03);
  assert.throws(() => rollAmongFromSeed('seed', 1, []));
});

test('null maxBet accepts chips and repeats above a million with an empty pool', async () => {
  await setGameSettings('fruitwheel', { maxBet: null });
  balances.set(1, 5_000_000);
  accounts.set('GAME_POOL:fruitwheel', 0);
  for (let i = 0; i < 11; i++) assert.equal((await placeBet(1, 'sevens', 100000)).ok, true);
  assert.equal(getPublicState(1)!.me!.staked, 1_100_000);
  __test.lastStakes.set(1, { sevens: 1_100_000 });
  assert.equal((await repeatBets(1)).ok, true);
  assert.equal(balances.get(1), 2_800_000);
  assert.equal(reservedForGame('fruitwheel'), 0);
});

for (const tied of [false, true]) test(`unfunded fallback uses minimum payout and pays pro-rata (${tied})`, async () => {
  await placeBet(1, 'watermelon', 100);
  await placeBet(2, 'watermelon', 1000);
  await placeBet(1, 'plum', 1000);
  await placeBet(2, 'plum', tied ? 100 : 1000);
  balances.set(3, 10000);
  await placeBet(3, 'sevens', 1000);
  await __test.advance();
  accounts.set('GAME_POOL:fruitwheel', 1100);
  const program = accounts.get('PROGRAM');
  await __test.advance();
  const expected = rollAmongFromSeed(round().seed, round().number, tied ? ['watermelon', 'plum'] : ['watermelon']);
  assert.equal(round().result, expected);
  await __test.advance();
  for (const p of round().players.values()) assert.equal(p.payout, payoutFor(p.stakes, expected) / 2);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 0);
  assert.equal(accounts.get('PROGRAM'), program);
});

test('legacy crown history still renders', async () => {
  await placeBet(1, 'plum', 100);
  await playOut();
  const row = rounds.get(round().dbId!);
  row.result = 'crown'; row.bonus = null;
  const history = await getHistory(1);
  assert.equal(history[0]!.result, 'crown');
  assert.deepEqual(history[0]!.results, ['crown']);
});

test('eligibility includes this round holds but excludes other reservations', async () => {
  await placeBet(1, 'watermelon', 1000);
  await placeBet(1, 'plum', 1000);
  await placeBet(2, 'sevens', 1000);
  await __test.advance();
  accounts.set('GAME_POOL:fruitwheel', 10000);
  const own = await reservePrize(1, 'fruitwheel', 2000, 2000);
  const other = await reservePrize(3, 'fruitwheel', 8000, 1000);
  assert.ok(own.ok && other.ok);
  const player = round().players.get(1)!;
  player.tokens.push(own.token); player.reserved = own.cap;
  assert.equal(await freePrizePoolBalance('fruitwheel'), 0);
  await __test.advance();
  assert.equal(round().result, rollAmongFromSeed(round().seed, round().number, ['watermelon', 'plum']));
  await __test.advance();
  assert.equal(player.payout, 2000);
  assert.equal(accounts.get('GAME_POOL:fruitwheel'), 8000);
  releasePrize(other.token);
});

test('empty rounds use the plain weighted draw', async () => {
  accounts.set('GAME_POOL:fruitwheel', 0);
  const expected = rollFromSeed(round().seed, round().number);
  await playOut();
  assert.equal(round().result, expected);
});
