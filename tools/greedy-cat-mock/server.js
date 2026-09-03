/**
 * Design harness for القط الجشع.
 *
 * The real engine needs Postgres, which this machine does not have, so this
 * stands in for it while the screen's visuals are being worked on. It speaks
 * the exact same wire format as backend/src/services/greedyCat.service.ts —
 * `GET /api/v1/games/greedy/state`, `/ranking`, the bet endpoints and the
 * `greedy_state` broadcast — so the Flutter screen runs against it completely
 * unmodified.
 *
 * It is NOT part of the app or the backend: nothing imports it, it moves no
 * coins, and it exists purely so the screen can be screenshotted in every phase.
 *
 *   node tools/greedy-cat-mock/server.js
 *   GET /scene/:name   force a phase (betting|closing|spinning|result|
 *                      result-win|result-lose|empty), or /scene/auto to cycle
 */
const path = require('path');
const express = require(path.join(__dirname, '../../backend/node_modules/express'));
const { Server } = require(path.join(__dirname, '../../backend/node_modules/socket.io'));
const http = require('http');

const PORT = 3100;

// Mirrors SYMBOLS in the real service, in the same clockwise-from-12 order.
const SYMBOLS = [
  { key: 'chicken', category: 'pizza', multiplier: 45, weight: 10, nameAr: 'دجاجة' },
  { key: 'tomato',  category: 'salad', multiplier: 5,  weight: 90, nameAr: 'طماطم' },
  { key: 'goat',    category: 'pizza', multiplier: 15, weight: 30, nameAr: 'ماعز' },
  { key: 'pepper',  category: 'salad', multiplier: 5,  weight: 90, nameAr: 'فلفل' },
  { key: 'fish',    category: 'pizza', multiplier: 25, weight: 18, nameAr: 'سمكة' },
  { key: 'carrot',  category: 'salad', multiplier: 5,  weight: 90, nameAr: 'جزرة' },
  { key: 'shrimp',  category: 'pizza', multiplier: 10, weight: 45, nameAr: 'روبيان' },
  { key: 'corn',    category: 'salad', multiplier: 5,  weight: 90, nameAr: 'ذرة' },
];
const TOTAL_WEIGHT = SYMBOLS.reduce((s, x) => s + x.weight, 0);
const DENOMINATIONS = [100, 1000, 5000, 20000, 100000, 500000];
const MILESTONES = [500000, 1000000, 2000000, 5000000, 10000000];

const CATEGORIES = {
  salad: SYMBOLS.filter((s) => s.category === 'salad').map((s) => s.key),
  pizza: SYMBOLS.filter((s) => s.category === 'pizza').map((s) => s.key),
};

const LAYOUT = {
  symbols: SYMBOLS,
  categories: CATEGORIES,
  categorySplit: 4,
  denominations: DENOMINATIONS,
  minBet: 100,
  maxBetPerSymbol: 5000000,
  totalWeight: TOTAL_WEIGHT,
  rtp: (SYMBOLS[0].weight * SYMBOLS[0].multiplier) / TOTAL_WEIGHT,
  phases: { betting: 30000, closing: 5000, spinning: 6000, result: 6000 },
  jackpotMilestones: MILESTONES,
};

const NAMES = ['ROSSO', 'نجمة الليل', 'ABU FAHAD', 'ليان', 'MR_TIGER', 'سلطان'];

function rollIndex() {
  let roll = Math.floor(Math.random() * TOTAL_WEIGHT);
  for (let i = 0; i < SYMBOLS.length; i++) {
    roll -= SYMBOLS[i].weight;
    if (roll < 0) return i;
  }
  return 0;
}

let scene = 'auto';
let roundId = 954499;
let balance = 4_820_000;

const state = {
  phase: 'betting',
  msLeft: 30000,
  resultIndex: null,
  bets: {},
  categories: {},
  payout: 0,
  multiplier: 0,
  history: [],
  pot: 412_500,
  reached: 0,
  todayNet: 0,
  todayBest: 0,
};

// Seed a plausible table so screenshots are never of an empty board.
for (let i = 0; i < 12; i++) {
  const s = SYMBOLS[rollIndex()];
  state.history.push({ roundId: roundId - 12 + i, symbol: s.key, multiplier: s.multiplier });
}

function totals() {
  const out = {};
  for (const s of SYMBOLS) {
    // A believable spread of other players' money, heaviest on the cheap veg.
    const base = s.multiplier === 5 ? 120000 : s.multiplier <= 15 ? 60000 : 18000;
    out[s.key] = {
      amount: Math.round(base * (0.5 + Math.random())),
      players: 2 + Math.floor(Math.random() * 9),
    };
  }
  return out;
}

let currentTotals = totals();

function hottest(t) {
  let best = null;
  let amount = 0;
  for (const s of SYMBOLS) {
    if (t[s.key].amount > amount) {
      amount = t[s.key].amount;
      best = s.key;
    }
  }
  return best;
}

function publicState() {
  const preResult = state.phase === 'betting' || state.phase === 'closing';
  const staked = Object.values(state.bets).reduce((a, b) => a + b, 0);
  return {
    roundId,
    phase: state.phase,
    endsAt: Date.now() + state.msLeft,
    msLeft: state.msLeft,
    seedHash: 'a'.repeat(64),
    seed: state.phase === 'result' ? 'b'.repeat(32) : null,
    resultIndex: preResult ? null : state.resultIndex,
    resultSymbol: preResult ? null : SYMBOLS[state.resultIndex ?? 0].key,
    totals: currentTotals,
    hot: hottest(currentTotals),
    playerCount: 37,
    jackpot: { pot: state.pot, milestones: MILESTONES, reached: state.reached },
    me: {
      bets: state.bets,
      categories: state.categories,
      staked,
      payout: state.phase === 'result' ? state.payout : 0,
      multiplier: state.phase === 'result' ? state.multiplier : 0,
    },
    today: { net: state.todayNet, best: state.todayBest },
    history: state.history.slice(-15),
  };
}

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', '*');
  res.header('Access-Control-Allow-Methods', '*');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

app.get('/api/v1/games/greedy/state', (_req, res) => {
  res.json({ success: true, state: publicState(), balance, countryCode: 'SA', layout: LAYOUT });
});

app.post('/api/v1/games/greedy/bet', (req, res) => {
  const { target, amount } = req.body || {};
  if (state.phase !== 'betting') {
    return res.status(400).json({ success: false, code: 'BETTING_CLOSED', message: 'أُغلق باب الاختيار' });
  }
  if (amount > balance) {
    return res.status(400).json({ success: false, code: 'INSUFFICIENT_COINS', message: 'رصيدك لا يكفي' });
  }
  const additions = CATEGORIES[target]
    ? Object.fromEntries(CATEGORIES[target].map((k, i, a) =>
        [k, i === a.length - 1 ? amount - Math.floor(amount / 4) * 3 : Math.floor(amount / 4)]))
    : { [target]: amount };
  for (const [k, v] of Object.entries(additions)) state.bets[k] = (state.bets[k] || 0) + v;
  if (CATEGORIES[target]) state.categories[target] = (state.categories[target] || 0) + amount;
  balance -= amount;
  state.pot += amount;
  broadcast();
  res.json({ success: true, bets: state.bets, categories: state.categories, balance });
});

app.post('/api/v1/games/greedy/clear', (_req, res) => {
  const total = Object.values(state.bets).reduce((a, b) => a + b, 0);
  balance += total;
  state.pot = Math.max(0, state.pot - total);
  state.bets = {};
  state.categories = {};
  broadcast();
  res.json({ success: true, bets: {}, categories: {}, balance });
});

app.post('/api/v1/games/greedy/repeat', (_req, res) => {
  res.json({ success: true, bets: state.bets, categories: state.categories, balance });
});

app.get('/api/v1/games/greedy/history', (_req, res) =>
  res.json({ success: true, history: state.history }));

app.get('/api/v1/games/greedy/ranking', (req, res) => {
  const scope = String(req.query.scope || 'global');
  const rows = NAMES.slice(0, scope === 'region' ? 4 : 6).map((name, i) => ({
    rank: i + 1,
    userId: 100 + i,
    name,
    avatarUrl: null,
    countryCode: 'SA',
    score: Math.round(89400500 / (i + 1.7)),
  }));
  res.json({ success: true, scope, ranking: rows });
});

app.get('/scene/:name', (req, res) => {
  scene = req.params.name;
  applyScene();
  broadcast();
  res.json({ ok: true, scene, phase: state.phase });
});

function applyScene() {
  const winner = rollIndex();
  if (scene === 'betting' || scene === 'empty') {
    state.phase = 'betting';
    state.msLeft = 21000;
    state.resultIndex = null;
    state.payout = 0;
    if (scene === 'empty') {
      state.bets = {};
      state.categories = {};
    } else {
      state.bets = { tomato: 5000, fish: 20000, corn: 1000 };
      state.categories = {};
    }
  } else if (scene === 'closing') {
    state.phase = 'closing';
    state.msLeft = 3000;
    state.resultIndex = null;
  } else if (scene === 'spinning') {
    state.phase = 'spinning';
    state.msLeft = 6000;
    state.resultIndex = winner;
  } else if (scene === 'result-win') {
    state.phase = 'result';
    state.msLeft = 6000;
    state.resultIndex = 4; // fish, 25x
    state.bets = { fish: 20000, tomato: 5000 };
    state.payout = 500000;
    state.multiplier = 25;
    state.todayNet = 475000;
    state.todayBest = 500000;
  } else if (scene === 'result-lose' || scene === 'result') {
    state.phase = 'result';
    state.msLeft = 6000;
    state.resultIndex = 0; // chicken, 45x
    state.bets = { tomato: 5000, corn: 1000 };
    state.payout = 0;
    state.multiplier = 0;
    state.todayNet = -6000;
  }
}

// ── Auto cycle ──────────────────────────────────────────────
function tick() {
  if (scene !== 'auto') return;
  state.msLeft -= 250;
  if (state.msLeft > 0) return;

  if (state.phase === 'betting') {
    state.phase = 'closing';
    state.msLeft = 5000;
  } else if (state.phase === 'closing') {
    state.phase = 'spinning';
    state.msLeft = 6000;
    state.resultIndex = rollIndex();
  } else if (state.phase === 'spinning') {
    state.phase = 'result';
    state.msLeft = 6000;
    const s = SYMBOLS[state.resultIndex];
    const on = state.bets[s.key] || 0;
    state.payout = on * s.multiplier;
    state.multiplier = on > 0 ? s.multiplier : 0;
    const staked = Object.values(state.bets).reduce((a, b) => a + b, 0);
    balance += state.payout;
    state.todayNet += state.payout - staked;
    if (state.payout > state.todayBest) state.todayBest = state.payout;
    state.history.push({ roundId, symbol: s.key, multiplier: s.multiplier });
  } else {
    roundId += 1;
    state.phase = 'betting';
    state.msLeft = 30000;
    state.resultIndex = null;
    state.bets = {};
    state.categories = {};
    state.payout = 0;
    currentTotals = totals();
  }
  broadcast();
}

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });
io.on('connection', (socket) => {
  socket.on('greedy_join_table', () => socket.emit('greedy_state', publicState()));
});

function broadcast() {
  io.emit('greedy_state', publicState());
}

setInterval(tick, 250);
setInterval(() => { if (scene === 'auto') broadcast(); }, 1000);

server.listen(PORT, () => {
  console.log(`[greedy-cat-mock] http://localhost:${PORT}  scene=${scene}`);
  console.log('  GET /scene/{auto|empty|betting|closing|spinning|result-win|result-lose}');
});
