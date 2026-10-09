// Pure room-cup arithmetic, kept free of imports so it can be unit-tested
// without booting the server.

/**
 * Whether a rung already paid at [lastPaidAt] may pay again now.
 *
 * The support total is a rolling window of [hours] (0 = all-time). A rung used
 * to be payable once per room FOREVER, so after the room's first party the
 * total reset, climbed back past the same rung, and the owner got nothing
 * (2026-10-02: «صاحب الروم بيقول منزلش مكافأة كاس الروم»). Now a rung pays
 * once per window: once [hours] have passed since its last payout, the rolling
 * total holds only gifts made AFTER that payout, so nothing is counted twice.
 */
export function rungDue(lastPaidAt: Date | null | undefined, hours: number, now = new Date()): boolean {
  if (!lastPaidAt) return true;
  if (hours <= 0) return false; // all-time total: each rung pays once per room
  return now.getTime() - lastPaidAt.getTime() >= hours * 60 * 60 * 1000;
}
