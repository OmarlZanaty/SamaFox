import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import prisma from '../utils/prisma';
import { authMiddleware } from '../middlewares/auth.middleware';
import { adminMiddleware } from '../middlewares/admin.middleware';
import {
  BETA_REJECTED_MARKER,
  betaSyncHeartbeat,
  canonEmail,
  enrollTester,
  isBetaSyncOffline,
  verifyGoogleIdToken,
} from '../services/beta.service';
import { sendFallbackInvite } from '../services/betaWatchdog.service';
import { enrollAdapter } from '../services/betaPlay.service';

const router = Router();

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

// The Play listing the page hands off to once the address is whitelisted.
// `market://` is resolved on the client (Android must open the Store app — a
// closed-test app has no page on play.google.com and the web URL 404s).
const packageName = () => process.env.BETA_PACKAGE_NAME?.trim() || 'com.almobarmg.samafox';
const playUrl = () =>
  process.env.BETA_PLAY_URL?.trim() ||
  `https://play.google.com/store/apps/details?id=${packageName()}`;

// A public, unauthenticated endpoint that writes a row — cap it. Generous
// enough for a family sharing a phone (the modal supports several addresses in
// one sitting), tight enough that it is not a free write primitive.
const enrollLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'محاولات كتيرة، جرّب بعد شوية' },
});

// ── Public: sign up for access ───────────────────────────────────────
// Accepts either a plain `email` or a Google `idToken`. The plain path is the
// universal one: it needs no Google session, so it still works inside the
// WhatsApp/Instagram webviews where Google blocks its own sign-in UI.
router.post('/enroll', enrollLimiter, async (req, res) => {
  try {
    const { idToken, email, source } = (req.body ?? {}) as {
      idToken?: string;
      email?: string;
      source?: string;
    };

    let identity;
    if (typeof idToken === 'string' && idToken.length > 0) {
      identity = await verifyGoogleIdToken(idToken);
    } else if (typeof email === 'string' && EMAIL_RE.test(email.trim())) {
      identity = { email: email.trim().toLowerCase() };
    } else {
      return res.status(400).json({ success: false, message: 'اكتب بريد Gmail صحيح' });
    }

    const outcome = await enrollTester(
      identity,
      typeof source === 'string' ? source.slice(0, 40) : undefined,
    );
    // Tell the page up front when the daemon is down, so it can show the honest
    // "we'll send you the link" copy instead of a spinner that cannot resolve.
    const delayed = !outcome.playSynced && (await isBetaSyncOffline());
    // Queue the email invite in the same breath rather than waiting for the
    // watchdog's next sweep — during an outage it is the only channel left, and
    // arriving minutes late is what made it useless before. Deliberately not
    // awaited: the response must not wait on Firebase.
    if (delayed) void sendFallbackInvite(outcome.email);

    return res.json({
      success: true,
      data: {
        // The canonical address the row is keyed by — the page must poll with
        // this, not with whatever the visitor typed.
        email: outcome.email,
        status: outcome.status,
        alreadyEnrolled: outcome.alreadyEnrolled,
        playSynced: outcome.playSynced,
        delayed,
        playUrl: playUrl(),
        packageName: packageName(),
      },
    });
  } catch (e: any) {
    const status = typeof e?.statusCode === 'number' ? e.statusCode : 500;
    if (status >= 500) console.error('beta enroll error:', e);
    return res
      .status(status)
      .json({ success: false, message: e?.message ?? 'تعذّر التسجيل، حاول تاني' });
  }
});

// ── Public: activation status, polled by the page ────────────────────
// Reveals only whether this address has reached the Play list yet — nothing
// else about the tester.
router.get('/enroll/status', async (req, res) => {
  try {
    const raw = String(req.query.email ?? '').trim();
    if (!EMAIL_RE.test(raw)) {
      return res.status(400).json({ success: false, message: 'بريد غير صحيح' });
    }
    // Canonicalised the same way enrolment stores it, so a visitor polling with
    // the dotted spelling still finds their row.
    const email = canonEmail(raw);
    const tester = await prisma.betaTester.findUnique({
      where: { email },
      select: { playSynced: true, playError: true },
    });
    const synced = tester?.playSynced ?? false;
    // rejected → Play refused the address; the page must explain it and reopen
    // the picker rather than spin until it times out.
    const rejected = !synced && tester?.playError === BETA_REJECTED_MARKER;
    const delayed = !synced && !rejected && !!tester && (await isBetaSyncOffline());

    return res.json({
      success: true,
      data: { registered: !!tester, synced, rejected, delayed, playUrl: playUrl() },
    });
  } catch (e) {
    console.error('beta status error:', e);
    return res.status(500).json({ success: false, message: 'تعذّر قراءة الحالة' });
  }
});

// ── Sync daemon (infra/beta-sync on the operator's PC) ───────────────
// Shared-secret auth. An unconfigured or wrong key 404s rather than 401s: these
// paths should not advertise that they exist.
function syncKeyOk(req: { headers: Record<string, any> }): boolean {
  const configured = process.env.BETA_SYNC_KEY?.trim();
  return !!configured && req.headers['x-sync-key'] === configured;
}

router.get('/sync/pending', async (req, res) => {
  if (!syncKeyOk(req)) return res.status(404).json({ success: false, message: 'not found' });
  try {
    // The poll itself is the heartbeat.
    await betaSyncHeartbeat();
    const testers = await prisma.betaTester.findMany({
      where: {
        playSynced: false,
        status: { not: 'dropped' },
        // Refused addresses are terminal — leaving them in would block the
        // queue behind them forever.
        OR: [{ playError: null }, { playError: { not: BETA_REJECTED_MARKER } }],
      },
      select: { id: true, email: true },
      orderBy: { enrolledAt: 'asc' },
      take: 100,
    });
    return res.json({ testers });
  } catch (e) {
    console.error('beta sync/pending error:', e);
    return res.status(500).json({ success: false, message: 'failed' });
  }
});

router.post('/sync/done', async (req, res) => {
  if (!syncKeyOk(req)) return res.status(404).json({ success: false, message: 'not found' });
  try {
    const ids = (req.body?.ids ?? []) as unknown;
    if (!Array.isArray(ids) || ids.length === 0 || ids.length > 100) {
      return res.status(400).json({ success: false, message: 'ids required' });
    }
    const updated = await prisma.betaTester.updateMany({
      where: { id: { in: ids.map(String) } },
      data: { playSynced: true, playError: null, lastCheckedAt: new Date() },
    });
    return res.json({ updated: updated.count });
  } catch (e) {
    console.error('beta sync/done error:', e);
    return res.status(500).json({ success: false, message: 'failed' });
  }
});

// The daemon gave up on this address. Park it so the queue moves on.
//
// `refused: true` means PLAY rejected the address — permanent, and the only
// case that earns BETA_REJECTED_MARKER (which `enrollTester` deliberately never
// clears, and which the storefront shows as "that isn't a Google account").
// Anything else is the DAEMON failing to drive the console — a broken selector,
// a frozen tab, an expired session. Those are our outages, they end, and the
// address is perfectly valid: recording them under the refusal marker told
// real users their own Gmail was not a Google account and burned the row
// forever, because no retry path clears that flag.
//
// An older daemon sends no `refused` field at all. Treat that as NOT refused:
// wrongly retrying a genuinely bad address costs one queue cycle, while
// wrongly refusing a good one costs that tester the product.
router.post('/sync/failed', async (req, res) => {
  if (!syncKeyOk(req)) return res.status(404).json({ success: false, message: 'not found' });
  try {
    const id = String(req.body?.id ?? '');
    if (!id) return res.status(400).json({ success: false, message: 'id required' });
    const refused = req.body?.refused === true;
    const reason = String(req.body?.reason ?? '').slice(0, 200);
    await prisma.betaTester.update({
      where: { id },
      data: {
        playError: refused ? BETA_REJECTED_MARKER : reason || 'sync failed',
        lastCheckedAt: new Date(),
      },
    });
    return res.json({ ok: true });
  } catch (e) {
    console.error('beta sync/failed error:', e);
    return res.status(500).json({ success: false, message: 'failed' });
  }
});

// ── Admin: dashboard counts ──────────────────────────────────────────
// `notSynced` is the number that matters day to day: it is the queue depth the
// daemon still owes, and a number that stops falling means the daemon is stuck.
router.get('/status', authMiddleware, adminMiddleware, async (_req, res) => {
  try {
    const grouped = await prisma.betaTester.groupBy({
      by: ['status'],
      _count: { _all: true },
    });
    const count = (s: string) => grouped.find((g) => g.status === s)?._count._all ?? 0;

    const invited = count('invited');
    const optedIn = count('opted_in');
    const installed = count('installed');
    const dropped = count('dropped');
    const [notSynced, rejected] = await Promise.all([
      prisma.betaTester.count({ where: { playSynced: false, status: { not: 'dropped' } } }),
      prisma.betaTester.count({ where: { playError: BETA_REJECTED_MARKER } }),
    ]);
    const active = invited + optedIn + installed;

    return res.json({
      success: true,
      data: {
        invited,
        optedIn,
        installed,
        dropped,
        active,
        notSynced,
        rejected,
        // Google needs 12 testers on a closed track before production release.
        healthy: active >= 12,
        adapter: enrollAdapter().kind,
        syncOffline: await isBetaSyncOffline(),
      },
    });
  } catch (e) {
    console.error('beta status(admin) error:', e);
    return res.status(500).json({ success: false, message: 'تعذّر قراءة الحالة' });
  }
});

// ── Admin: list testers ──────────────────────────────────────────────
router.get('/testers', authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const status = String(req.query.status ?? '').trim();
    const notSynced = String(req.query.notSynced ?? '') === 'true';
    const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 500);

    const where: any = {};
    if (['invited', 'opted_in', 'installed', 'dropped'].includes(status)) where.status = status;
    if (notSynced) where.playSynced = false;

    const testers = await prisma.betaTester.findMany({
      where,
      orderBy: { enrolledAt: 'desc' },
      take: limit,
    });
    return res.json({ success: true, data: { testers, total: testers.length } });
  } catch (e) {
    console.error('beta testers(admin) error:', e);
    return res.status(500).json({ success: false, message: 'تعذّر قراءة القائمة' });
  }
});

// ── Admin: move a tester between lifecycle states ────────────────────
// `installed` is never detected automatically — no Play API reports it — so it
// is set here after a manual check.
router.patch('/testers/:id', authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const status = String(req.body?.status ?? '');
    if (!['invited', 'opted_in', 'installed', 'dropped'].includes(status)) {
      return res.status(400).json({ success: false, message: 'حالة غير معروفة' });
    }
    await prisma.betaTester.update({
      where: { id: String(req.params.id) },
      data: { status: status as any, lastCheckedAt: new Date() },
    });
    return res.json({ success: true });
  } catch (e) {
    console.error('beta patch tester(admin) error:', e);
    return res.status(500).json({ success: false, message: 'تعذّر التحديث' });
  }
});

// ── Admin: put a tester back in the daemon's queue ───────────────────
// Under the noop adapter (production) there is nothing to "retry" server-side —
// the daemon owns the write. Retrying therefore means clearing the terminal
// marker so the row becomes eligible again, which is exactly what is needed
// after fixing an address by hand in Play Console.
router.post('/testers/:id/retry-sync', authMiddleware, adminMiddleware, async (req, res) => {
  try {
    const id = String(req.params.id);
    const existing = await prisma.betaTester.findUnique({
      where: { id },
      select: { email: true, status: true },
    });
    if (!existing) return res.status(404).json({ success: false, message: 'غير موجود' });

    await prisma.betaTester.update({
      where: { id },
      data: {
        playSynced: false,
        playError: null,
        // A dropped row is invisible to /sync/pending, so requeuing one without
        // reviving it would silently do nothing. Any other state is left alone —
        // requeuing an `installed` tester must not demote them.
        ...(existing.status === 'dropped' ? { status: 'invited' as const } : {}),
        lastCheckedAt: new Date(),
      },
    });
    return res.json({ success: true, data: { email: existing.email, requeued: true } });
  } catch (e) {
    console.error('beta retry-sync(admin) error:', e);
    return res.status(500).json({ success: false, message: 'تعذّرت إعادة المحاولة' });
  }
});

export default router;
