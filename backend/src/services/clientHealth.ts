import fs from 'fs';
import readline from 'readline';

// The numbers the 9 Oct investigation had to dig out of the client logs by
// hand — OS kills, forced logouts, lost connections, memory — per day and app
// version, so the effect of each release can be read off one table.

type Json = Record<string, unknown>;

export type HealthRow = {
  day: string; // UTC date
  app: string;
  sessions: number;
  users: number;
  kills: { lowMemory: number; anr: number; signaled: number; unclean: number; other: number };
  uncaughtErrors: number;
  forcedLogouts: number;
  hostLookupFails: number;
  socketDrops: number;
  memSamples: number;
  rssMedian: number | null;
  rssP90: number | null;
  gfxMedian: number | null;
  gfxP90: number | null;
};

type Acc = Omit<HealthRow, 'sessions' | 'users' | 'rssMedian' | 'rssP90' | 'gfxMedian' | 'gfxP90'> & {
  sessionSet: Set<string>;
  userSet: Set<number>;
  rss: number[];
  gfx: number[];
};

const MEM = /^mem rss=(\d+)MB .*\bgfx=(\d+)/;

function quantile(sorted: number[], q: number): number | null {
  if (sorted.length === 0) return null;
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * q))]!;
}

export class ClientHealth {
  private rows = new Map<string, Acc>();
  constructor(private readonly since: number) {}

  private acc(day: string, app: string): Acc {
    const key = `${day}|${app}`;
    let a = this.rows.get(key);
    if (!a) {
      a = {
        day,
        app,
        kills: { lowMemory: 0, anr: 0, signaled: 0, unclean: 0, other: 0 },
        uncaughtErrors: 0,
        forcedLogouts: 0,
        hostLookupFails: 0,
        socketDrops: 0,
        memSamples: 0,
        sessionSet: new Set(),
        userSet: new Set(),
        rss: [],
        gfx: [],
      };
      this.rows.set(key, a);
    }
    return a;
  }

  /** One line of logs/client-events.log. */
  addEvent(e: Json): void {
    const rx = Date.parse(String(e.rx ?? e.t ?? ''));
    if (!(rx >= this.since)) return;
    const a = this.acc(new Date(rx).toISOString().slice(0, 10), String(e.app ?? '?'));
    if (typeof e.session === 'string') a.sessionSet.add(e.session);
    if (typeof e.userId === 'number') a.userSet.add(e.userId);
    const msg = String(e.msg ?? '');
    if (e.level === 'error' && e.kind !== 'log') a.uncaughtErrors++;
    if (msg.startsWith('Token refresh failed')) a.forcedLogouts++;
    if (msg.includes('Failed host lookup')) a.hostLookupFails++;
    if (e.kind === 'socket' && msg.startsWith('disconnected')) a.socketDrops++;
    const mem = MEM.exec(msg);
    if (mem) {
      a.memSamples++;
      a.rss.push(Number(mem[1]));
      a.gfx.push(Number(mem[2]));
    }
  }

  /** One line of logs/client-reports.log (crashes and OS kills). */
  addReport(r: Json): void {
    const rx = Date.parse(String(r.receivedAt ?? ''));
    if (!(rx >= this.since) || r.kind !== 'processKilled') return;
    const a = this.acc(new Date(rx).toISOString().slice(0, 10), String(r.appVersion ?? '?'));
    const message = String(r.message ?? '');
    if (message.includes('LOW_MEMORY')) a.kills.lowMemory++;
    else if (message.includes('ANR')) a.kills.anr++;
    else if (message.includes('SIGNALED')) a.kills.signaled++;
    else if (message.includes('without a clean shutdown')) a.kills.unclean++;
    else if (!message.includes('USER_REQUESTED')) a.kills.other++;
  }

  result(): HealthRow[] {
    return [...this.rows.values()]
      .map((a) => {
        const rss = [...a.rss].sort((x, y) => x - y);
        const gfx = [...a.gfx].sort((x, y) => x - y);
        const { sessionSet, userSet, rss: _r, gfx: _g, ...rest } = a;
        return {
          ...rest,
          sessions: sessionSet.size,
          users: userSet.size,
          rssMedian: quantile(rss, 0.5),
          rssP90: quantile(rss, 0.9),
          gfxMedian: quantile(gfx, 0.5),
          gfxP90: quantile(gfx, 0.9),
        };
      })
      .sort((x, y) => (x.day === y.day ? y.sessions - x.sessions : y.day.localeCompare(x.day)));
  }
}

async function eachJsonLine(file: string, since: number, fn: (j: Json) => void): Promise<void> {
  try {
    if (fs.statSync(file).mtimeMs < since) return; // rotated out before the window
  } catch {
    return;
  }
  const lines = readline.createInterface({ input: fs.createReadStream(file, 'utf8'), crlfDelay: Infinity });
  for await (const line of lines) {
    if (!line) continue;
    try {
      fn(JSON.parse(line) as Json);
    } catch {
      /* a line cut by rotation or a crash */
    }
  }
}

/** Reads the live and the rotated log of each kind. */
export async function readClientHealth(
  files: { events: string; reports: string },
  since: number,
): Promise<HealthRow[]> {
  const h = new ClientHealth(since);
  for (const f of [`${files.events}.1`, files.events]) await eachJsonLine(f, since, (e) => h.addEvent(e));
  for (const f of [`${files.reports}.1`, files.reports]) await eachJsonLine(f, since, (r) => h.addReport(r));
  return h.result();
}
