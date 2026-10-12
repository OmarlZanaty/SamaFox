/**
 * رصيد التارجت arithmetic, kept free of imports so it can be unit-tested.
 *
 * gifts since joining ± بيع/تبديل/admin adjustments + the owner's commission,
 * floored at zero ONLY at the end. Flooring the adjustment before adding the
 * commission brought a swapped-out commission back on the dashboard
 * (2026-09-30: "حولت الأربعين دولار ومع ذلك فاضل خمسة وتلاتين").
 */
export function targetBalance(
  giftsCoins: number,
  adjustmentCoins: bigint | number | null | undefined,
  commissionCoins: bigint | number | null | undefined,
): number {
  return Math.max(0, giftsCoins + Number(adjustmentCoins ?? 0) + Number(commissionCoins ?? 0));
}

/** A membership that carries target, as far as gift attribution cares. */
export interface TargetSeat {
  id: number;
  joinedAt: Date;
  hosting: boolean;
}

/**
 * Which gifts a seat owns. A user can hold target on several memberships (a
 * وكيل with a hosting AND a charging agency, a فرع who later joined a hosting
 * agency). Each gift must count on exactly ONE of them — counting it on every
 * seat let the same gifts be swapped/sold once per agency (2026-09-30: ~124M
 * coins of phantom target across 10 accounts).
 *
 * Priority: hosting seats first, then earliest joined, then lowest id. A seat
 * owns gifts from its own joinedAt until the earliest joinedAt of any
 * higher-priority seat, so gifts received before a hosting agency was joined
 * stay on the seat that held them at the time. `null` = owns nothing.
 */
export function giftWindow(seats: TargetSeat[], id: number): { from: Date; to: Date | null } | null {
  const order = [...seats].sort(
    (a, b) =>
      Number(b.hosting) - Number(a.hosting) ||
      a.joinedAt.getTime() - b.joinedAt.getTime() ||
      a.id - b.id,
  );
  const idx = order.findIndex((s) => s.id === id);
  const seat = order[idx];
  if (!seat) return null;
  const from = seat.joinedAt;
  let to: Date | null = null;
  for (const s of order.slice(0, idx)) if (!to || s.joinedAt < to) to = s.joinedAt;
  if (to && to <= from) return null;
  return { from, to };
}
