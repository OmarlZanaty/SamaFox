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

/**
 * What crossing rung [index] adds, given every rung's reward in threshold order.
 *
 * Each rung's reward is the TOTAL the owner should hold at that level, not an
 * extra on top: «دعم مليون مكافأة 30 الف، دعم 2 مليون مكافأة 60 الف» means 60k
 * at 2M, not 30k + 60k = 90k (client 2026-11-10 19:02). So a rung pays only
 * the difference over the best lower rung; a rung worth no more pays nothing.
 */
export function rungIncrement(rewards: readonly bigint[], index: number): bigint {
  let below = 0n;
  for (const r of rewards.slice(0, index)) if (r > below) below = r;
  const diff = (rewards[index] ?? 0n) - below;
  return diff > 0n ? diff : 0n;
}

export interface CupLevel { targetCoins: bigint; rewardCoins: bigint }

/**
 * كأس الغرفة بالـ ID levels, lowest target first. [levels] is the stored JSON
 * ([{ targetCoins, rewardCoins }]); bad rows are dropped. With no usable level
 * the cup is its single legacy target/reward (client 10/11 19:02: «محدد
 * بمستوى واحد فقط، المطلوب أحدده بأكتر من مستوى»).
 */
export function cupLevels(cup: { levels?: unknown; targetCoins: unknown; ownerRewardCoins: unknown }): CupLevel[] {
  const out: CupLevel[] = [];
  const raw = Array.isArray(cup.levels) ? cup.levels : [];
  for (const l of raw) {
    try {
      const t = BigInt(String((l as any)?.targetCoins));
      const r = BigInt(String((l as any)?.rewardCoins));
      if (t > 0n && r >= 0n) out.push({ targetCoins: t, rewardCoins: r });
    } catch { /* skip a malformed level */ }
  }
  if (out.length === 0) {
    return [{ targetCoins: BigInt(String(cup.targetCoins)), rewardCoins: BigInt(String(cup.ownerRewardCoins)) }];
  }
  return out.sort((a, b) => (a.targetCoins < b.targetCoins ? -1 : a.targetCoins > b.targetCoins ? 1 : 0));
}

