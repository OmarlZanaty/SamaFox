import { Router } from 'express';
import fs from 'fs';
import path from 'path';

/**
 * G2 — direct APK download.
 *
 * The owner asked for this nine times, more than anything else in the chat: the
 * agents needed a link to send people before the Play listing existed.
 *
 * The version is READ OFF THE FILE rather than configured anywhere. A version
 * number typed into a config is how people end up downloading a months-old
 * build and reporting bugs that were fixed weeks ago; here, publishing a new
 * release is a file copy into `public/downloads` and nothing else.
 *
 * Naming convention: `samafox-<version>.apk`, e.g. `samafox-1.0.18.apk`.
 * The newest by modification time wins, so an older file left behind is
 * harmless.
 */
const router = Router();

const downloadsDir = () => path.join(process.cwd(), 'public', 'downloads');

interface Build {
  file: string;
  version: string | null;
  sizeMb: number;
  updatedAt: Date;
}

function latestBuild(): Build | null {
  const dir = downloadsDir();
  let names: string[];
  try {
    names = fs.readdirSync(dir).filter((n) => n.toLowerCase().endsWith('.apk'));
  } catch {
    return null; // directory not created yet — nothing published
  }
  if (names.length === 0) return null;

  const builds: Build[] = names.map((file) => {
    const stat = fs.statSync(path.join(dir, file));
    const m = file.match(/(\d+\.\d+\.\d+(?:\+\d+)?)/);
    return {
      file,
      version: m?.[1] ?? null,
      sizeMb: Math.round((stat.size / (1024 * 1024)) * 10) / 10,
      updatedAt: stat.mtime,
    };
  });

  builds.sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
  // names.length was checked above, so there is always a first element; the
  // explicit ?? null keeps noUncheckedIndexedAccess happy without a cast.
  return builds[0] ?? null;
}

/** What the download page asks for. */
router.get('/latest', (_req, res) => {
  const build = latestBuild();
  if (!build) {
    return res.status(404).json({ success: false, message: 'لم يتم رفع نسخة بعد' });
  }
  return res.json({
    success: true,
    version: build.version,
    sizeMb: build.sizeMb,
    updatedAt: build.updatedAt.toISOString(),
    // Served through the redirect below rather than as a static path, so the
    // link in someone's WhatsApp keeps working across releases.
    url: '/api/v1/app/download',
  });
});

/** The download itself — always the newest build. */
router.get('/download', (_req, res) => {
  const build = latestBuild();
  if (!build) {
    return res.status(404).json({ success: false, message: 'لم يتم رفع نسخة بعد' });
  }
  const full = path.join(downloadsDir(), build.file);

  // `application/vnd.android.package-archive` is what makes Android offer to
  // install rather than open the file as text.
  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', `attachment; filename="${build.file}"`);
  return res.sendFile(full);
});

// ── Client crash / kill reports ───────────────────────────────────────────────
//
// The app had no crash reporting of any kind, so "التطبيق يقفل بعد دقيقة من
// دخول الغرفة" could only be guessed at. CrashReporter on the device catches
// Dart errors and, on the next launch, DETECTS a previous run that the OS killed
// (low-memory kill or a native crash in libwebrtc, neither of which runs any
// Dart code). It posts here.
//
// Deliberately public and unauthenticated: a report about a crash is worth most
// when the crash happened before or during login, and there is nothing here
// worth protecting — it writes to a log file and nothing else. It is also
// deliberately cheap to abuse and boring to abuse: every report is capped, the
// file is rotated, and nothing is ever read back out by the app.
const reportsDir = () => path.join(process.cwd(), 'logs');
const reportsFile = () => path.join(reportsDir(), 'client-reports.log');

/** One report, trimmed to what is readable and useful. */
const MAX_FIELD = 4_000;
const MAX_BREADCRUMBS = 200;
const MAX_LOG_BYTES = 20 * 1024 * 1024; // rotate at 20 MB

function trim(value: unknown, max = MAX_FIELD): string | null {
  if (value == null) return null;
  const s = String(value);
  return s.length > max ? `${s.slice(0, max)}…[trimmed]` : s;
}

router.post('/client-report', (req, res) => {
  try {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const previous = (body.previousSession ?? {}) as Record<string, unknown>;

    const rawCrumbs = Array.isArray(body.breadcrumbs)
      ? body.breadcrumbs
      : Array.isArray(previous.breadcrumbs)
        ? previous.breadcrumbs
        : [];

    const entry = {
      receivedAt: new Date().toISOString(),
      ip: req.ip,
      kind: trim(body.kind, 64) ?? 'unknown',
      message: trim(body.message),
      library: trim(body.library, 200),
      stack: trim(body.stack, 8_000),
      at: trim(body.at, 64),
      appVersion: trim(body.appVersion ?? previous.appVersion, 64),
      platform: trim(body.platform ?? previous.platform, 200),
      rssMb: Number(body.rssMb ?? previous.rssMb) || null,
      peakRssMb: Number(body.peakRssMb ?? previous.peakRssMb) || null,
      peakRssAt: trim(body.peakRssAt ?? previous.peakRssAt, 64),
      breadcrumbs: rawCrumbs
        .slice(-MAX_BREADCRUMBS)
        .map((c: unknown) => trim(c, 300)),
    };

    // The console line is what shows up in `pm2 logs`; the file is what survives
    // a restart and can be read a day later.
    console.error('[client-report]', {
      kind: entry.kind,
      appVersion: entry.appVersion,
      peakRssMb: entry.peakRssMb,
      message: entry.message?.slice(0, 200),
    });

    fs.mkdirSync(reportsDir(), { recursive: true });
    const file = reportsFile();
    try {
      if (fs.statSync(file).size > MAX_LOG_BYTES) {
        fs.renameSync(file, `${file}.1`);
      }
    } catch {
      // No file yet, or it cannot be stat'ed — appending will create it.
    }
    fs.appendFileSync(file, JSON.stringify(entry) + '\n', 'utf8');

    return res.json({ success: true });
  } catch (e) {
    // A failure to record a crash must never become a second crash.
    console.warn('[client-report] failed:', (e as Error).message);
    return res.json({ success: false });
  }
});

// ── Live client event log ─────────────────────────────────────────────────────
//
// What the app is DOING while it runs, not only how it died: room entered,
// voice engine connected, microphone re-acquired, socket dropped, token
// refreshed, a handled error. Batched on the device and posted every ~30s (or
// at once for an error). Each batch becomes one line per event in
// logs/client-events.log, which the dashboard's log page reads.
//
// Same posture as client-report: public, capped, rotated, write-only.
const eventsFile = () => path.join(reportsDir(), 'client-events.log');
const MAX_EVENTS_PER_BATCH = 100;
const MAX_EVENT_LOG_BYTES = 50 * 1024 * 1024;

export interface ClientEventLine {
  t: string;           // device time, ISO
  rx: string;          // server receive time, ISO
  level: string;       // error | warn | info
  kind: string;        // short tag: room, voice, socket, auth, mic, log, crumb
  msg: string;
  userId: number | null;
  room: number | null;
  app: string | null;
  device: string | null;
  session: string | null;
  data: unknown;
}

router.post('/client-events', (req, res) => {
  try {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const events = Array.isArray(body.events) ? body.events.slice(-MAX_EVENTS_PER_BATCH) : [];
    if (events.length === 0) return res.json({ success: true, accepted: 0 });

    const userId = Number(body.userId) || null;
    const app = trim(body.appVersion, 64);
    const device = trim(body.device, 120);
    const session = trim(body.session, 40);
    const rx = new Date().toISOString();

    const lines: string[] = [];
    for (const raw of events) {
      if (!raw || typeof raw !== 'object') continue;
      const e = raw as Record<string, unknown>;
      const line: ClientEventLine = {
        t: trim(e.t, 40) ?? rx,
        rx,
        level: ['error', 'warn', 'info'].includes(String(e.level)) ? String(e.level) : 'info',
        kind: trim(e.kind, 24) ?? 'log',
        msg: trim(e.msg, 600) ?? '',
        userId,
        room: Number(e.room) || null,
        app,
        device,
        session,
        data: e.data === undefined ? undefined : JSON.parse(trim(JSON.stringify(e.data), 2_000) ?? 'null'),
      };
      lines.push(JSON.stringify(line));
    }

    fs.mkdirSync(reportsDir(), { recursive: true });
    const file = eventsFile();
    try {
      if (fs.statSync(file).size > MAX_EVENT_LOG_BYTES) fs.renameSync(file, `${file}.1`);
    } catch {
      // first write
    }
    fs.appendFileSync(file, lines.join('\n') + '\n', 'utf8');

    // Errors also go to the console so `pm2 logs` shows them as they land.
    for (const l of lines) {
      if (l.includes('"level":"error"')) console.error('[client-event]', l.slice(0, 300));
    }
    return res.json({ success: true, accepted: lines.length });
  } catch (e) {
    console.warn('[client-events] failed:', (e as Error).message);
    return res.json({ success: false });
  }
});

/**
 * Read the newest lines of a JSONL log without loading the whole file: only
 * the last [maxBytes] are read, then split on newlines.
 */
export function tailJsonl(file: string, maxBytes = 8 * 1024 * 1024): Record<string, unknown>[] {
  let fd: number | null = null;
  try {
    const stat = fs.statSync(file);
    const start = Math.max(0, stat.size - maxBytes);
    const length = stat.size - start;
    const buf = Buffer.alloc(length);
    fd = fs.openSync(file, 'r');
    fs.readSync(fd, buf, 0, length, start);
    const text = buf.toString('utf8');
    const lines = text.split('\n');
    if (start > 0) lines.shift(); // first line is cut mid-way
    const out: Record<string, unknown>[] = [];
    for (const l of lines) {
      if (!l) continue;
      try {
        out.push(JSON.parse(l));
      } catch {
        // a partial or corrupt line; skip it
      }
    }
    return out;
  } catch {
    return [];
  } finally {
    if (fd !== null) fs.closeSync(fd);
  }
}

export const clientLogFiles = { events: eventsFile, reports: reportsFile };

export default router;
