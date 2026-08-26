import { OAuth2Client } from 'google-auth-library';
import prisma from '../utils/prisma';

// Closed-testing enrolment for SamaFox.
//
// A visitor on the Al Mobarmg store page gives us a Gmail address; that address
// has to end up on the Play Console **email list** selected on SamaFox's closed
// track, after which the normal Play listing installs for them with no extra
// tap. Google exposes no API for those lists, so the write is performed by the
// operator's `beta-sync` daemon (a logged-in Play Console in headless Chrome).
//
// Everything here is therefore queue mechanics: store the address, hand the
// daemon whatever is still unsynced, and record what came back.

// Play stores Gmail addresses canonicalised — dots and +tags stripped — so
// `a.b@gmail.com` and `ab@gmail.com` are ONE Play identity. Rows are keyed by
// this form so a person who types their address differently on a second visit
// updates their row instead of opening a second one that can never resolve
// independently. Non-Gmail domains are only lowercased.
//
// (The daemon canonicalises for the same reason on its side: a raw-string
// read-back of the console never matches what Play wrote, which once had it
// retrying one address 780 times in an evening with the queue stuck behind it.)
export function canonEmail(raw: string): string {
  const email = raw.trim().toLowerCase();
  const at = email.lastIndexOf('@');
  if (at < 0) return email;
  const domain = email.slice(at + 1);
  let local = email.slice(0, at);
  if (domain === 'gmail.com' || domain === 'googlemail.com') {
    local = (local.split('+')[0] ?? local).replace(/\./g, '');
  }
  return `${local}@${domain}`;
}

// Play refused the address (it is not a Google account). Terminal: such a row
// must leave the queue, or the daemon retries it forever and every signup
// behind it waits on a sync that can never land.
export const BETA_REJECTED_MARKER = 'not_a_google_account';

const HEARTBEAT_KEY = 'beta_sync_last_poll';
// The daemon polls every few seconds, so silence this long means it is gone
// (PC asleep, task stopped) — not a slow round-trip.
const OFFLINE_MS = 90 * 1000;

let oauthClient: OAuth2Client | null = null;

export interface EnrollIdentity {
  email: string;
  /** Google "sub" claim when the signup came through the account picker. */
  sub?: string;
}

// Verifies a Google Identity Services ID token server-side. The email from the
// client is never trusted — only what Google signed.
export async function verifyGoogleIdToken(idToken: string): Promise<Required<EnrollIdentity>> {
  const clientId = process.env.GOOGLE_OAUTH_CLIENT_ID?.trim();
  if (!clientId) {
    throw Object.assign(new Error('beta signup is not configured'), { statusCode: 503 });
  }
  if (!oauthClient) oauthClient = new OAuth2Client(clientId);

  let payload;
  try {
    const ticket = await oauthClient.verifyIdToken({ idToken, audience: clientId });
    payload = ticket.getPayload();
  } catch {
    throw Object.assign(new Error('could not verify the Google account'), { statusCode: 401 });
  }
  if (!payload?.sub || !payload.email) {
    throw Object.assign(new Error('could not read the Google account email'), { statusCode: 401 });
  }
  if (payload.email_verified === false) {
    throw Object.assign(new Error('this Google email is not verified'), { statusCode: 422 });
  }
  return { email: payload.email.toLowerCase(), sub: payload.sub };
}

export interface EnrollOutcome {
  status: string;
  alreadyEnrolled: boolean;
  playSynced: boolean;
  /** The stored (canonical) address — what the status endpoint is keyed by. */
  email: string;
}

// Stores the tester and puts them in the daemon's queue. Idempotent by email
// (and by Google subject when we have one).
//
// A repeat signup ALWAYS re-queues, even when the row says `playSynced`: the
// list is also edited by hand in the console, so a stored `true` is not proof
// the address is still on it. The daemon skips the write when it finds the
// address already there, so re-checking costs nothing and self-heals.
export async function enrollTester(
  user: EnrollIdentity,
  source?: string,
): Promise<EnrollOutcome> {
  const email = canonEmail(user.email);

  // Build the OR conditionally — `{ googleSub: undefined }` would match every row.
  const or: { email?: string; googleSub?: string }[] = [{ email }];
  if (user.sub) or.push({ googleSub: user.sub });
  const existing = await prisma.betaTester.findFirst({ where: { OR: or } });

  if (existing) {
    // Someone signing up again is asking for access now, so a dropped row must
    // return to the queue — the daemon ignores dropped rows, which would
    // otherwise leave them waiting forever.
    const status = existing.status === 'dropped' ? 'invited' : existing.status;
    await prisma.betaTester.update({
      where: { id: existing.id },
      data: {
        status,
        playSynced: false,
        // Clear a stale failure so the row is eligible again, but never clear a
        // refusal: that address can only fail the same way a second time.
        playError: existing.playError === BETA_REJECTED_MARKER ? BETA_REJECTED_MARKER : null,
        lastCheckedAt: new Date(),
        // A plain-email signup may later come back through the account picker —
        // keep the verified subject once we learn it.
        ...(user.sub && !existing.googleSub ? { googleSub: user.sub } : {}),
      },
    });
    return {
      email,
      status,
      alreadyEnrolled: true,
      playSynced: existing.playError === BETA_REJECTED_MARKER ? false : existing.playSynced,
    };
  }

  await prisma.betaTester.create({
    data: {
      email,
      googleSub: user.sub ?? null,
      source: source ?? 'almobarmg-store',
      status: 'invited',
      playSynced: false,
      lastCheckedAt: new Date(),
    },
  });
  return { email, status: 'invited', alreadyEnrolled: false, playSynced: false };
}

// Stamped on every daemon poll. A failed stamp must never fail the poll itself:
// that turns a dropped DB connection into the daemon hammering an erroring
// endpoint instead of syncing signups.
export async function betaSyncHeartbeat(): Promise<void> {
  try {
    const value = new Date().toISOString();
    await prisma.appSetting.upsert({
      where: { key: HEARTBEAT_KEY },
      update: { value },
      create: { key: HEARTBEAT_KEY, value },
    });
  } catch (e) {
    console.warn('beta: heartbeat stamp failed', e);
  }
}

// True when the daemon has not polled recently — the page then says so up front
// instead of spinning through a wait that cannot succeed.
export async function isBetaSyncOffline(): Promise<boolean> {
  try {
    const row = await prisma.appSetting.findUnique({ where: { key: HEARTBEAT_KEY } });
    const last = row ? Date.parse(row.value) : NaN;
    return !Number.isFinite(last) || Date.now() - last > OFFLINE_MS;
  } catch {
    // Unknown is not "online": claiming the worker is up when we cannot tell
    // would hide the outage from the very page that needs to explain it.
    return true;
  }
}
