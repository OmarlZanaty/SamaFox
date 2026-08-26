import { GoogleAuth } from 'google-auth-library';

// Enrol port for closed testing.
//
// The address that actually matters is the one on the Play Console **email
// list**, and Google exposes no API for those lists — the operator's beta-sync
// daemon writes them through a logged-in browser. So in production this port is
// deliberately a no-op: `BETA_ENROLL_ADAPTER=noop` means "the daemon does the
// work", and the backend's only job is to keep the queue.
//
// The one live adapter is Firebase App Distribution, and it is NOT a second way
// onto the Play list — it is a separate channel that emails an install link.
// It exists solely as the outage fallback for when the daemon is down (see
// betaWatchdog.service). It does not count toward Play's 12-tester gate, which
// is why it is never the primary path.

export interface EnrollResult {
  /** true if the address is now on the adapter's tester channel. */
  synced: boolean;
  /** Human-readable failure, stored on the row for the admin to look at. */
  error?: string;
}

export interface EnrollAdapter {
  readonly kind: 'noop' | 'firebase';
  addTester(email: string): Promise<EnrollResult>;
}

const CLOUD_PLATFORM_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';

const fadProjectNumber = () => process.env.BETA_FAD_PROJECT_NUMBER?.trim() || '';
const fadGroup = () => process.env.BETA_FAD_GROUP?.trim() || 'web-testers';

// Builds credentials from either a service-account key file or the inline
// FIREBASE_* pair the rest of the deploy already carries. Returns null when
// neither is configured, so the caller can degrade instead of throwing.
function fadCredentials(): ConstructorParameters<typeof GoogleAuth>[0] | null {
  const keyFile = process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim();
  if (keyFile) return { scopes: [CLOUD_PLATFORM_SCOPE], keyFile };

  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
  // .env files carry the PEM with literal \n; GoogleAuth needs real newlines.
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n').trim();
  if (clientEmail && privateKey) {
    return {
      scopes: [CLOUD_PLATFORM_SCOPE],
      credentials: { client_email: clientEmail, private_key: privateKey },
    };
  }
  return null;
}

/** True when the fallback channel has everything it needs to send an invite. */
export function fadConfigured(): boolean {
  return !!fadProjectNumber() && !!fadCredentials();
}

// A single batchJoin both creates the tester (createMissingTesters) and joins
// the group; because a release is already distributed to that group, Firebase
// emails the install invite immediately.
export class FirebaseAppDistAdapter implements EnrollAdapter {
  readonly kind = 'firebase' as const;
  private auth: GoogleAuth | null;

  constructor() {
    const opts = fadCredentials();
    this.auth = opts ? new GoogleAuth(opts) : null;
  }

  async addTester(email: string): Promise<EnrollResult> {
    const project = fadProjectNumber();
    if (!this.auth || !project) {
      return { synced: false, error: 'fad_not_configured' };
    }
    const url =
      `https://firebaseappdistribution.googleapis.com/v1/projects/${project}` +
      `/groups/${encodeURIComponent(fadGroup())}:batchJoin`;
    try {
      const client = await this.auth.getClient();
      await client.request({
        url,
        method: 'POST',
        data: { emails: [email], createMissingTesters: true },
      });
      return { synced: true };
    } catch (err: unknown) {
      const message = extractError(err);
      console.warn('beta: Firebase App Distribution add failed', { email, message });
      return { synced: false, error: message };
    }
  }
}

// Stores the tester and nothing else — the beta-sync daemon picks the row up
// from /sync/pending and does the Play Console write. This is the production
// adapter.
class NoopAdapter implements EnrollAdapter {
  readonly kind = 'noop' as const;
  async addTester(): Promise<EnrollResult> {
    return { synced: false, error: 'pending_manual' };
  }
}

function extractError(err: unknown): string {
  const e = err as {
    response?: { data?: { error?: { message?: string } } };
    message?: string;
  };
  return e?.response?.data?.error?.message ?? e?.message ?? 'unknown error';
}

let cached: EnrollAdapter | null = null;

// Returns the configured adapter (memoized). A `firebase` selection with
// missing credentials degrades to noop with a log line rather than throwing on
// every single signup — a half-configured deploy must still take signups.
export function enrollAdapter(): EnrollAdapter {
  if (cached) return cached;
  if (process.env.BETA_ENROLL_ADAPTER?.trim() === 'firebase') {
    if (fadConfigured()) {
      cached = new FirebaseAppDistAdapter();
    } else {
      console.warn(
        'beta: BETA_ENROLL_ADAPTER=firebase but project number/credentials missing — using noop',
      );
      cached = new NoopAdapter();
    }
  } else {
    cached = new NoopAdapter();
  }
  return cached;
}
