/**
 * Design harness for عجلة الحظ.
 *
 * The real engine needs Postgres, which this machine does not have, so this
 * stands in for it while the wheel's visuals are being worked on. It speaks the
 * exact same wire format as backend/src/services/crazyWheel.service.ts —
 * `GET /api/v1/games/crazy/state` plus the `crazy_state` socket broadcast — so
 * the Flutter screen runs completely unmodified against it.
 *
 * It is NOT part of the app or the backend: nothing imports it, it moves no
 * coins, and it exists purely so the screen can be screenshotted in every phase.
 *
 *   node tools/crazy-wheel-mock/server.js
 *   GET /scene/:name   force a phase (betting|spinning|result|coinflip|
 *                      cashhunt|pachinko|crazytime), or /scene/auto to cycle
 */
const path = require('path');
const express = require(path.join(__dirname, '../../backend/node_modules/express'));
const { Server } = require(path.join(__dirname, '../../backend/node_modules/socket.io'));
const http = require('http');

const PORT = 3100;
const WHEEL_SIZE = 54;

const BET_SPOTS = ['1', '2', '5', '10', 'coinflip', 'cashhunt', 'pachinko', 'crazytime'];
const COUNTS = { '1': 21, '2': 13, '5': 7, '10': 4, coinflip: 4, cashhunt: 2, pachinko: 2, crazytime: 1 };

function buildWheel() {
  const size = WHEEL_SIZE;
  const ring = new Array(size).fill(null);
  const order = ['crazytime', 'pachinko', 'cashhunt', '10', 'coinflip', '5', '2', '1'];
  let cursor = 0;
  for (const key of order) {
    const count = COUNTS[key];
    const stride = Math.floor(size / count);
    for (let i = 0; i < count; i++) {
      let slot = (cursor + i * stride) % size;
      let guard = 0;
      while (ring[slot] !== null && guard++ < size) slot = (slot + 1) % size;
      ring[slot] = key;
    }
    cursor += 1;
  }
  return ring.map((s) => s ?? '1');
}

const WHEEL = buildWheel();
const rnd = (n) => Math.floor(Math.random() * n);
const pick = (a) => a[rnd(a.length)];

// ── Bonus payloads, same shapes the real service emits ─────
const rollCoinFlip = () => {
  const v = [5, 10, 15, 20, 25, 40, 50, 75, 100];
  const red = pick(v), blue = pick(v);
  const winner = rnd(2) ? 'blue' : 'red';
  return { kind: 'coinflip', red, blue, winner, multiplier: winner === 'red' ? red : blue };
};

const rollCashHunt = () => {
  const bag = [];
  const weights = [[5, 30], [7, 20], [10, 15], [15, 12], [20, 9], [25, 7], [35, 5], [50, 4], [75, 3], [100, 2], [200, 1]];
  for (const [value, count] of weights) for (let i = 0; i < count; i++) bag.push(value);
  while (bag.length < 108) bag.push(5);
  bag.sort(() => Math.random() - 0.5);
  return { kind: 'cashhunt', grid: bag.slice(0, 108), symbols: bag.map(() => rnd(6)) };
};

const rollPachinko = () => {
  const slots = [8, 10, 12, 15, 20, 25, 40, 50, 0, 50, 40, 25, 20, 15, 12, 10, 8];
  const path = Array.from({ length: 16 }, () => (rnd(2) ? 1 : -1));
  const landed = Math.min(16, Math.max(0, Math.round((path.reduce((a, b) => a + b, 0) + 16) / 2)));
  return { kind: 'pachinko', drops: [{ slots, path, landed, value: slots[landed] }], multiplier: slots[landed] || 100 };
};

const rollCrazyTime = () => ({
  kind: 'crazytime',
  spins: [],
  multipliers: { blue: pick([50, 100, 200, 500]), green: pick([50, 100, 200]), yellow: pick([25, 60, 150]) },
});

const rollBonus = (kind) =>
  kind === 'coinflip' ? rollCoinFlip()
  : kind === 'cashhunt' ? rollCashHunt()
  : kind === 'pachinko' ? rollPachinko()
  : rollCrazyTime();

// ── Round state ────────────────────────────────────────────
let round = null;
let timer = null;
let nextId = 1;
let scene = 'auto'; // 'auto' cycles; anything else pins that phase

const history = Array.from({ length: 14 }, (_, i) => {
  const segment = WHEEL[rnd(WHEEL_SIZE)];
  const bonus = !/^\d+$/.test(segment);
  return {
    roundId: i + 1,
    segment,
    topSlot: { spot: pick(BET_SPOTS), multiplier: pick([2, 5, 10, 25, 50]) },
    multiplier: bonus ? pick([25, 50, 100, 200]) : null,
    at: Date.now(),
  };
});

// A populated table makes the bet tiles show realistic totals.
const totals = () =>
  Object.fromEntries(BET_SPOTS.map((s) => [s, { amount: rnd(40) * 5000 + 5000, players: rnd(20) + 1 }]));

const myBets = { '1': 25000, '5': 10000, cashhunt: 5000, crazytime: 5000 };

function publicState() {
  if (!round) return null;
  const revealed = round.phase !== 'betting';
  return {
    roundId: round.id,
    phase: round.phase,
    endsAt: round.endsAt,
    msLeft: Math.max(0, round.endsAt - Date.now()),
    chipTiers: [1000, 5000, 10000, 50000, 100000],
    betSpots: BET_SPOTS,
    seedHash: 'harness',
    seed: null,
    resultIndex: revealed ? round.resultIndex : null,
    resultSegment: revealed ? round.resultSegment : null,
    topSlot: revealed ? round.topSlot : null,
    bonus:
      round.phase === 'bonus_reveal' || round.phase === 'result'
        ? round.bonus
        : round.phase === 'bonus_pick' && round.bonus
          ? (round.bonus.kind === 'cashhunt'
              ? { kind: 'cashhunt', grid: [], symbols: round.bonus.symbols }
              : { kind: 'crazytime', spins: [], multipliers: { blue: 0, green: 0, yellow: 0 } })
          : null,
    bonusKind: revealed && !/^\d+$/.test(round.resultSegment) ? round.resultSegment : null,
    totals: round.totals,
    playerCount: 37,
    me: {
      bets: myBets,
      pick: round.phase === 'bonus_reveal' ? (round.resultSegment === 'cashhunt' ? 42 : 'green') : null,
      payout: round.phase === 'result' ? 275000 : 0,
      multiplier: round.phase === 'result' ? 11 : 0,
    },
    history,
  };
}

let io = null;
const broadcast = () => io && io.emit('crazy_state', publicState());

function newRound(phase, segmentKey) {
  const index = segmentKey
    ? WHEEL.indexOf(segmentKey)
    : rnd(WHEEL_SIZE);
  const segment = WHEEL[index];
  round = {
    id: nextId++,
    phase,
    endsAt: Date.now() + 20000,
    resultIndex: index,
    resultSegment: segment,
    topSlot: { spot: segment, multiplier: pick([5, 10, 25, 50]) }, // matched, so the frame lights up
    bonus: /^\d+$/.test(segment) ? null : rollBonus(segment),
    totals: totals(),
  };
}

const DURATIONS = { betting: 20000, spinning: 9000, bonus_pick: 10000, bonus_reveal: 8000, result: 7000 };

function schedule(phase) {
  round.phase = phase;
  round.endsAt = Date.now() + DURATIONS[phase];
  broadcast();
  clearTimeout(timer);
  timer = setTimeout(advance, DURATIONS[phase]);
}

function advance() {
  if (scene !== 'auto') {
    // Pinned: keep republishing the same frame so the screen holds still.
    round.endsAt = Date.now() + 60000;
    broadcast();
    timer = setTimeout(advance, 5000);
    return;
  }
  const isBonus = !/^\d+$/.test(round.resultSegment);
  if (round.phase === 'betting') return schedule('spinning');
  if (round.phase === 'spinning') {
    return schedule(isBonus ? (round.resultSegment === 'coinflip' || round.resultSegment === 'pachinko' ? 'bonus_reveal' : 'bonus_pick') : 'result');
  }
  if (round.phase === 'bonus_pick') return schedule('bonus_reveal');
  if (round.phase === 'bonus_reveal') return schedule('result');
  history.push({
    roundId: round.id,
    segment: round.resultSegment,
    topSlot: round.topSlot,
    multiplier: isBonus ? pick([25, 50, 100]) : null,
    at: Date.now(),
  });
  newRound('betting');
  schedule('betting');
}

// ── HTTP ───────────────────────────────────────────────────
const app = express();
app.use(express.json());
// Express 5 rejects a bare '*' route, so preflight is handled inline.
app.use((req, res, next) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', '*');
  res.set('Access-Control-Allow-Methods', '*');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

const layout = {
  wheel: WHEEL,
  colors: {},
  payouts: { '1': 1, '2': 2, '5': 5, '10': 10, coinflip: 0, cashhunt: 0, pachinko: 0, crazytime: 0 },
  betSpots: BET_SPOTS,
  chipTiers: [1000, 5000, 10000, 50000, 100000],
};

app.get('/api/v1/games/crazy/state', (_, res) =>
  res.json({ success: true, state: publicState(), balance: 4820000, layout }));

app.post('/api/v1/games/crazy/:action', (_, res) =>
  res.json({ success: true, bets: myBets, balance: 4820000, pick: 42 }));

/** Pin the screen to one phase so it can be screenshotted. */
app.get('/scene/:name', (req, res) => {
  const name = req.params.name;
  scene = name;
  clearTimeout(timer);
  if (name === 'auto') {
    newRound('betting');
    schedule('betting');
  } else if (['coinflip', 'cashhunt', 'pachinko', 'crazytime'].includes(name)) {
    newRound('bonus_reveal', name);
    round.phase = name === 'cashhunt' || name === 'crazytime' ? 'bonus_pick' : 'bonus_reveal';
    round.endsAt = Date.now() + 60000;
    broadcast();
    timer = setTimeout(advance, 5000);
  } else {
    newRound(name, name === 'result' ? '10' : undefined);
    round.phase = name;
    round.endsAt = Date.now() + 60000;
    broadcast();
    timer = setTimeout(advance, 5000);
  }
  res.json({ ok: true, scene: name, phase: round.phase, segment: round.resultSegment });
});

const server = http.createServer(app);
io = new Server(server, { cors: { origin: '*' } });
io.on('connection', (socket) => {
  socket.emit('crazy_state', publicState());
  socket.on('crazy_join_table', () => socket.emit('crazy_state', publicState()));
});

newRound('betting');
server.listen(PORT, () => {
  console.log(`[crazy-wheel-mock] http://localhost:${PORT}`);
  schedule('betting');
});
