import prisma from '../utils/prisma';
import { createNotification } from './notification.service';
import { BETA_REJECTED_MARKER, isBetaSyncOffline } from './beta.service';
import { FirebaseAppDistAdapter, fadConfigured } from './betaPlay.service';

// Watchdog for the beta-sync daemon.
//
// The daemon runs on the operator's PC, so every hour that PC is asleep is an
// outage — and an audit of the sibling product found signups that waited 9–10
// hours. That, not any refused address, is what users report as "infinite
// loading". Nothing here fixes it (only an always-on host does); all of it is
// mitigation, and each piece exists because the absence of it hurt once:
//
//   1. Detect the outage fast — the daemon's /sync/pending polls ARE the
//      heartbeat, so 90 s of silence already means it is gone.
//   2. Tell the admins once per outage, so someone can wake the PC.
//   3. Give testers stuck past 2 minutes the Firebase App Distribution invite,
//      which is the only channel still working while the daemon is down.

// Once the daemon is offline the email invite is all that is left; the sibling
// product sent it after 10 minutes and that was far too late to be useful.
const FALLBACK_MS = 2 * 60 * 1000;

// This tester has been handed the fallback invite. It is a marker, not a
// failure: `playSynced` deliberately stays false so the daemon still whitelists
// the address properly when it comes back.
export const FAD_SENT_MARKER = 'fad_fallback_sent';

// One alert per outage, not one per sweep — a sleeping PC would otherwise
// notify every admin every minute until morning.
let alertedThisOutage = false;
let fadAdapter: FirebaseAppDistAdapter | null = null;

function fad(): FirebaseAppDistAdapter {
  if (!fadAdapter) fadAdapter = new FirebaseAppDistAdapter();
  return fadAdapter;
}

// Sends the App Distribution invite for one address. Idempotent per tester via
// the marker, and never throws — callers fire it alongside the signup response,
// where a rejected promise would take the response down with it.
export async function sendFallbackInvite(email: string): Promise<void> {
  if (!fadConfigured()) return;
  try {
    const tester = await prisma.betaTester.findUnique({
      where: { email },
      select: { id: true, playSynced: true, playError: true },
    });
    if (!tester || tester.playSynced) return;
    // A refused address can never install either way, and overwriting its
    // refusal marker would put it straight back into the blocking queue.
    if (tester.playError === FAD_SENT_MARKER || tester.playError === BETA_REJECTED_MARKER) return;

    const res = await fad().addTester(email);
    if (!res.synced) {
      console.warn('beta: fallback invite failed', { email, error: res.error });
      return;
    }
    await prisma.betaTester.update({
      where: { id: tester.id },
      data: { playError: FAD_SENT_MARKER, lastCheckedAt: new Date() },
    });
    console.info('beta: fallback invite sent', { email });
  } catch (e) {
    console.warn('beta: fallback invite errored', { email, message: String(e) });
  }
}

// One sweep. Cheap when all is well: it stops at the first check unless there
// is actually something waiting.
export async function betaSyncWatchdog(): Promise<void> {
  const pending = await prisma.betaTester.findMany({
    where: {
      playSynced: false,
      status: { not: 'dropped' },
      // A refused address is not "waiting". Counting it would raise a false
      // outage alarm on a daemon that is running perfectly well.
      OR: [{ playError: null }, { playError: { not: BETA_REJECTED_MARKER } }],
    },
    select: { id: true, email: true, enrolledAt: true, playError: true },
  });
  if (!pending.length) {
    alertedThisOutage = false;
    return;
  }
  if (!(await isBetaSyncOffline())) {
    alertedThisOutage = false;
    return;
  }

  // 1. Alert every admin, once for this outage.
  if (!alertedThisOutage) {
    alertedThisOutage = true;
    const admins = await prisma.user.findMany({
      where: { isAdmin: true },
      select: { id: true },
    });
    for (const admin of admins) {
      try {
        await createNotification({
          userId: admin.id,
          type: 'beta_sync_offline',
          title: '⚠️ مزامنة النسخة التجريبية متوقفة',
          body: `جهاز المزامنة مقفول و${pending.length} تسجيل مستني الإضافة — شغّل الجهاز أو راجع beta-sync`,
          data: { pending: pending.length },
        });
      } catch (e) {
        console.warn('beta watchdog: admin alert failed', { adminId: admin.id, message: String(e) });
      }
    }
    console.warn('beta watchdog: sync offline', { pending: pending.length });
  }

  // 2. Email fallback for whoever has been waiting past the window (once each).
  if (!fadConfigured()) return;
  const cutoff = Date.now() - FALLBACK_MS;
  const stuck = pending.filter(
    (t) => t.enrolledAt.getTime() < cutoff && t.playError !== FAD_SENT_MARKER,
  );
  for (const tester of stuck) {
    const res = await fad().addTester(tester.email);
    if (res.synced) {
      await prisma.betaTester.update({
        where: { id: tester.id },
        data: { playError: FAD_SENT_MARKER, lastCheckedAt: new Date() },
      });
      console.info('beta watchdog: fallback invite sent', { email: tester.email });
    } else {
      console.warn('beta watchdog: fallback invite failed', {
        email: tester.email,
        error: res.error,
      });
    }
  }
}

let timer: NodeJS.Timeout | null = null;

/** Runs the watchdog on boot and every minute after. */
export function startBetaSyncWatchdog(intervalMs = 60 * 1000): void {
  if (timer) return;
  betaSyncWatchdog().catch(() => {});
  timer = setInterval(() => {
    betaSyncWatchdog().catch(() => {});
  }, intervalMs);
  // Never hold the process open for the sake of a watchdog timer.
  timer.unref?.();
}
