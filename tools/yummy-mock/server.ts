/**
 * Browser harness for YUMMY.
 *
 * The real service needs Postgres, which this machine does not have. This
 * stands in for it with the REAL server math (backend/src/services/yummy.math.ts)
 * and the same wire format as yummy.controller.ts, so the Flutter screen runs
 * against it unmodified. Balance and history live in memory only.
 *
 * Not part of the app or the backend: nothing imports it and it moves no coins.
 *
 *   cd backend && npx ts-node --transpile-only ../tools/yummy-mock/server.ts
 *   GET /scene/:name  force the next spin: win | tumble | bonus | jackpot | mega | auto
 */
import crypto from 'crypto';
import path from 'path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const express = require(path.join(__dirname, '../../backend/node_modules/express'));
import {
  BET_STEPS, PAYLINES, PAYTABLE, JACKPOT_MULTIPLIER, MATH_VERSION, TARGET_RTP, MAX_MULTIPLIER,
  TUMBLE_MULTIPLIERS, FREE_SPIN_AWARDS, EXPANDING_REELS, SYMBOLS, WEIGHTS,
  Rng, RngStream, computeSpin, validBet, Symbol,
} from '../../backend/src/services/yummy.math';

const PORT = Number(process.argv[process.argv.indexOf('--port') + 1]) || 3100;
let balance = 500_000;
let scene = 'auto';
let serverSeed = crypto.randomBytes(32).toString('hex');
let clientSeed = 'browser-test';
let nonce = 0;
const history: object[] = [];
const hash = (s: string) => crypto.createHash('sha256').update(s).digest('hex');

const layout = {
  betSteps: BET_STEPS, minLines: 1, maxLines: 9, paylines: PAYLINES, paytable: PAYTABLE,
  jackpotMultiplier: JACKPOT_MULTIPLIER, mathVersion: MATH_VERSION, mathRtp: TARGET_RTP,
  tumbleMultipliers: TUMBLE_MULTIPLIERS, freeSpinAwards: FREE_SPIN_AWARDS, expandingReels: EXPANDING_REELS,
  maxMultiplier: MAX_MULTIPLIER, enabled: true, minBet: 10, maxBet: 9000, maxWinPerRound: null, dailyMaxWinPerUser: null,
};
const fairness = () => ({ serverSeedHash: hash(serverSeed), clientSeed, nonce });

/** The float that makes the weighted strip draw [symbol]. */
function floatFor(symbol: Symbol) {
  const total = WEIGHTS.reduce((a, b) => a + b, 0);
  let before = 0;
  for (let i = 0; i < SYMBOLS.length; i++) {
    if (SYMBOLS[i] === symbol) return (before + WEIGHTS[i]! / 2) / total;
    before += WEIGHTS[i]!;
  }
  return 0;
}
/** Feeds [script] draws first, then the real HMAC stream, through the REAL math. */
const scripted = (script: Symbol[], rest: Rng): Rng => {
  let i = 0;
  return { nextFloat: () => (i < script.length ? floatFor(script[i++]!) : rest.nextFloat()) };
};
const row = (...s: Symbol[]) => s;
const SCENES: Record<string, Symbol[]> = {
  // Cherry line through a WILD on the middle row.
  win: [...row('lemon', 'orange', 'grapes', 'candy', 'strawberry'), ...row('cherry', 'cherry', 'wild', 'cherry', 'lemon'),
    ...row('orange', 'grapes', 'lemon', 'diamond', 'watermelon')],
  // Middle-row lemons pop; the scripted refills then complete the top row twice more.
  tumble: [...row('grapes', 'candy', 'orange', 'diamond', 'watermelon'),
    ...row('lemon', 'lemon', 'lemon', 'lemon', 'grapes'), ...row('orange', 'watermelon', 'candy', 'orange', 'diamond'),
    ...row('strawberry', 'strawberry', 'strawberry', 'strawberry'),
    ...row('watermelon', 'watermelon', 'watermelon', 'watermelon')],
  // Three BONUS → 8 free spins; the first free spin lands an expanding WILD.
  bonus: [...row('bonus', 'lemon', 'grapes', 'candy', 'strawberry'), ...row('orange', 'cherry', 'bonus', 'diamond', 'lemon'),
    ...row('watermelon', 'grapes', 'orange', 'lemon', 'bonus'),
    ...row('grapes', 'grapes', 'wild', 'lemon', 'orange'), ...row('cherry', 'grapes', 'candy', 'diamond', 'strawberry'),
    ...row('lemon', 'orange', 'watermelon', 'cherry', 'candy')],
  jackpot: [...row('lemon', 'orange', 'grapes', 'candy', 'strawberry'), ...row('jackpot', 'jackpot', 'jackpot', 'jackpot', 'lemon'),
    ...row('orange', 'grapes', 'lemon', 'diamond', 'watermelon')],
  mega: [...row('diamond', 'wild', 'diamond', 'diamond', 'diamond'), ...row('wild', 'diamond', 'wild', 'diamond', 'wild'),
    ...row('diamond', 'diamond', 'diamond', 'wild', 'diamond')],
};

function forced(bet: number, lines: number) {
  const stream = new RngStream(serverSeed, clientSeed, nonce);
  return computeSpin(SCENES[scene] ? scripted(SCENES[scene]!, stream) : stream, bet, lines);
}

const app = express();
app.use(express.json());
app.use((req: any, res: any, next: any) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', '*');
  res.header('Access-Control-Allow-Methods', '*');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});
const api = '/api/v1/games/yummy';
app.get(`${api}/state`, (_q: any, r: any) => r.json({ success: true, layout, balance, history, fairness: fairness() }));
app.get(`${api}/history`, (_q: any, r: any) => r.json({ success: true, history }));
app.get(`${api}/fair`, (_q: any, r: any) => r.json({ success: true, fairness: fairness() }));
app.post(`${api}/seed`, (q: any, r: any) => {
  clientSeed = String(q.body?.clientSeed ?? '').trim().slice(0, 64) || clientSeed;
  r.json({ success: true, fairness: fairness() });
});
app.post(`${api}/seed/rotate`, (_q: any, r: any) => {
  const revealed = { serverSeed, serverSeedHash: hash(serverSeed), clientSeed, nonce };
  serverSeed = crypto.randomBytes(32).toString('hex');
  nonce = 0;
  r.json({ success: true, revealed, serverSeedHash: hash(serverSeed) });
});
app.post(`${api}/verify`, (q: any, r: any) => {
  const b = q.body ?? {};
  r.json({ success: true, spin: { ...computeSpin(new RngStream(b.serverSeed, b.clientSeed, b.nonce), b.betPerLine, b.activeLines), serverSeedHash: hash(b.serverSeed) } });
});
app.post(`${api}/spin`, (q: any, r: any) => {
  const bet = q.body?.betPerLine, lines = q.body?.activeLines;
  if (!validBet(bet, lines)) return r.status(400).json({ success: false, code: 'BAD_BET' });
  if (balance < bet * lines) return r.status(400).json({ success: false, code: 'INSUFFICIENT' });
  const spin = forced(bet, lines);
  scene = 'auto';
  balance += spin.totalPrize - spin.totalBet;
  const round = { id: history.length + 1, at: new Date().toISOString(),
    spin: { ...spin, requestedPrize: spin.totalPrize, capped: false }, balance,
    serverSeedHash: hash(serverSeed), clientSeed, nonce: nonce++ };
  history.unshift(round);
  history.splice(50);
  setTimeout(() => r.json({ success: true, ...round }), 250);
});
app.get('/scene/:name', (q: any, r: any) => { scene = q.params.name; r.json({ scene }); });
app.get('/balance/:n', (q: any, r: any) => { balance = Number(q.params.n); r.json({ balance }); });
app.listen(PORT, () => console.log(`yummy mock on :${PORT}`));
