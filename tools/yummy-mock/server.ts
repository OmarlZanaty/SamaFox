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
 *   GET /scene/:name  force the next spin: bonus | jackpot | win | auto
 */
import crypto from 'crypto';
import path from 'path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const express = require(path.join(__dirname, '../../backend/node_modules/express'));
import {
  BET_STEPS, PAYLINES, PAYTABLE, JACKPOT_MULTIPLIER, MATH_VERSION, TARGET_RTP,
  RngStream, computeSpin, scoreGrid, validBet, Symbol,
} from '../../backend/src/services/yummy.math';

const PORT = 3100;
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
  enabled: true, minBet: 10, maxBet: 9000, maxWinPerRound: null, dailyMaxWinPerUser: null,
};
const fairness = () => ({ serverSeedHash: hash(serverSeed), clientSeed, nonce });

/** Forced scenes swap in a hand-made grid and rescore it with the real math. */
function forced(bet: number, lines: number) {
  const spin = computeSpin(new RngStream(serverSeed, clientSeed, nonce), bet, lines);
  const fill = (cells: Record<number, Symbol>) =>
    spin.grid.map((s, i) => cells[i] ?? (s === 'bonus' || s === 'jackpot' ? 'lemon' : s));
  let grid = spin.grid;
  if (scene === 'win') grid = fill({ 5: 'cherry', 6: 'cherry', 7: 'wild', 8: 'cherry' });
  if (scene === 'jackpot') grid = fill({ 5: 'jackpot', 6: 'jackpot', 7: 'jackpot' });
  if (scene === 'bonus') grid = fill({ 0: 'bonus', 7: 'bonus', 14: 'bonus' });
  if (scene === 'auto') return spin;
  const wins = scoreGrid(grid, bet, lines);
  const bonusTriggered = grid.filter((s) => s === 'bonus').length >= 3;
  const bonusMultiplier = bonusTriggered ? 5 : 0;
  const bonusPrize = bonusMultiplier * spin.totalBet;
  return { ...spin, grid, wins, bonusTriggered, bonusMultiplier, bonusPrize,
    jackpotTriggered: wins.some((w) => w.symbol === 'jackpot'),
    totalPrize: wins.reduce((a, w) => a + w.amount, 0) + bonusPrize };
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
