import { Request, Response, NextFunction, RequestHandler } from 'express';
import prisma from '../utils/prisma';

const db = prisma as any;

/**
 * F4 — حظر الجهاز / الشبكة.
 *
 * An account ban is trivially defeated by registering again, which is why the
 * client asked twice for a ban that sticks to the DEVICE or the IP. This runs
 * in FRONT of every way in (register / login / google / facebook), so a banned
 * handset cannot make itself a fresh account either.
 *
 * The device id comes from the request body — the app already sends one for
 * guest login (`deviceId`) — or from an `x-device-id` header. Neither is
 * trustworthy on a rooted phone, which is exactly why the IP is checked as
 * well: defeating both takes a new device AND a new network.
 */

/**
 * IPs that are OUR servers, not a user: the old AWS box still relays every
 * request from apps built against it (47 users showed it as their IP), plus the
 * Hetzner box and loopback. Banning one would lock out everyone behind it, so
 * they can never be banned and never match a ban.
 */
const PROTECTED_IPS = new Set([
  '63.179.163.62',
  '46.224.129.250',
  '127.0.0.1',
  '::1',
  '::ffff:127.0.0.1',
]);

export function isProtectedIp(ip: string): boolean {
  return PROTECTED_IPS.has(ip.trim());
}

/** Best-effort client IP, honouring the proxy header AWS/nginx sets. */
export function clientIp(req: Request): string | null {
  const fwd = req.headers['x-forwarded-for'];
  const raw = Array.isArray(fwd) ? fwd[0] : fwd;
  const first = raw?.split(',')[0]?.trim();
  return first || req.socket?.remoteAddress || null;
}

/**
 * Apps up to 1.0.34 sent Android's Build.ID ("AP3A.240905.015.A2") as the
 * device id. That is the FIRMWARE build, shared by every phone of the same
 * model and update, so a ban on it locked out strangers. Real ids — ANDROID_ID
 * (16 hex) and iOS identifierForVendor (UUID) — never contain a dot; a build id
 * always does.
 */
export function isSharedBuildId(value: string): boolean {
  return value.includes('.');
}

export function clientDeviceId(req: Request): string | null {
  const hdr = req.headers['x-device-id'];
  const fromHeader = Array.isArray(hdr) ? hdr[0] : hdr;
  const fromBody = (req.body as any)?.deviceId;
  const value = String(fromHeader ?? fromBody ?? '').trim();
  if (!value || isSharedBuildId(value)) return null;
  return value;
}

export type DeviceBanState = { banned: boolean; reason: string | null; expiresAt: Date | null };

const NOT_BANNED: DeviceBanState = { banned: false, reason: null, expiresAt: null };

/**
 * Is this device or IP banned right now? Expired rows are deleted as they are
 * found, so a lapsed ban stops showing on the dashboard without a sweeper job.
 */
export async function checkDeviceBan(
  deviceId: string | null,
  ipAddress: string | null,
): Promise<DeviceBanState> {
  if (!deviceId && !ipAddress) return NOT_BANNED;
  try {
    const row = await db.deviceBan.findFirst({
      where: {
        OR: [...(deviceId ? [{ deviceId }] : []), ...(ipAddress ? [{ ipAddress }] : [])],
      },
    });
    if (!row) return NOT_BANNED;

    if (row.expiresAt && row.expiresAt.getTime() <= Date.now()) {
      await db.deviceBan.delete({ where: { id: row.id } }).catch(() => {});
      return NOT_BANNED;
    }
    return { banned: true, reason: row.reason ?? null, expiresAt: row.expiresAt ?? null };
  } catch (e) {
    // Fail OPEN. A lookup failure must never lock the whole user base out of
    // the app; an account ban is still enforced separately by banGuard.
    console.warn('[deviceBan] lookup failed, allowing:', (e as Error).message);
    return NOT_BANNED;
  }
}

export const deviceBanMiddleware: RequestHandler = async (
  req: Request,
  res: Response,
  next: NextFunction,
) => {
  const ip = clientIp(req);
  const state = await checkDeviceBan(clientDeviceId(req), ip && !isProtectedIp(ip) ? ip : null);
  if (!state.banned) return next();

  return res.status(403).json({
    success: false,
    code: 'DEVICE_BANNED',
    message: state.expiresAt
      ? `هذا الجهاز محظور حتى ${state.expiresAt.toISOString()}`
      : 'هذا الجهاز محظور من استخدام التطبيق',
    reason: state.reason,
    expiresAt: state.expiresAt,
  });
};
