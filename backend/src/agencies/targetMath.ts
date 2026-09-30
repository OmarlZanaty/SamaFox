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
