import prisma from '../utils/prisma';
import { createNotification } from './notification.service';
import { expiryFromItem } from '../controllers/adminProduct.controller';

/**
 * Automatic rewards for a charging agency that tops ITSELF up (B11).
 *
 * The client's rule: *"لو تخليني احدد من لوحة التحكم الوكاله لما تشحن عدد
 * كوينزات معين احدد مكافأة تروح تلقائي"*. The dashboard configures a ladder of
 * `AgencyChargeReward` rungs — a coins threshold, and coins and/or products to
 * hand over when the agency's cumulative self-charging passes it.
 *
 * Idempotence is the whole game here: a top-up must never pay a rung twice, and
 * a single large top-up that jumps several rungs must pay each of them once.
 * `ChargingAgency.rewardedUpToCoins` is the high-water mark that makes both
 * true — only rungs in `(rewardedUpToCoins, totalCharged]` are paid, and the
 * mark moves up in the same transaction.
 */

export type AgencyChargeRewardResult = {
  rungsPaid: number;
  coinsPaid: number;
  itemsGranted: number;
};

const EMPTY: AgencyChargeRewardResult = { rungsPaid: 0, coinsPaid: 0, itemsGranted: 0 };

/**
 * Record one self-charge of [amount] coins on [agencyId] and pay out whatever
 * reward rungs it crosses.
 *
 * Best-effort by design: a reward misconfiguration must never fail the top-up
 * that triggered it, so everything here is caught and logged.
 */
export async function recordAgencySelfCharge(
  agencyId: number,
  amount: number,
): Promise<AgencyChargeRewardResult> {
  if (!agencyId || !Number.isFinite(amount) || amount <= 0) return EMPTY;

  try {
    // The counter is part of the charge itself, not of the reward — it has to
    // move even when no ladder is configured (B10's "شحنت كام مره لنفسها").
    const agency = await prisma.chargingAgency.update({
      where: { id: agencyId },
      data: {
        selfChargeCount: { increment: 1 },
        totalTopupCoins: { increment: amount },
      },
      select: {
        id: true,
        userId: true,
        agencyName: true,
        totalTopupCoins: true,
        rewardedUpToCoins: true,
      },
    });

    const totalCharged = BigInt(agency.totalTopupCoins);
    const alreadyPaid = BigInt(agency.rewardedUpToCoins ?? 0);
    if (totalCharged <= alreadyPaid) return EMPTY;

    // Rungs this charge crossed: above the high-water mark, at or below the
    // new total. Ordered so a multi-rung jump pays them in ladder order.
    const rungs = await (prisma as any).agencyChargeReward.findMany({
      where: {
        isActive: true,
        OR: [{ agencyId: null }, { agencyId }],
        thresholdCoins: { gt: alreadyPaid, lte: totalCharged },
      },
      orderBy: { thresholdCoins: 'asc' },
    });

    // Move the mark even with no rungs to pay, so the window never re-scans
    // ground already covered.
    await prisma.chargingAgency.update({
      where: { id: agencyId },
      data: { rewardedUpToCoins: totalCharged },
    });

    if (!rungs.length) return EMPTY;

    let coinsPaid = 0;
    let itemsGranted = 0;

    for (const rung of rungs as any[]) {
      const coins = Math.max(0, Math.floor(Number(rung.rewardCoins ?? 0)));
      if (coins > 0) {
        await prisma.user.update({
          where: { id: agency.userId },
          data: { coinsBalance: { increment: coins } },
        });
        coinsPaid += coins;
      }

      const itemIds = [...new Set<string>((rung.rewardItemIds ?? []).filter(Boolean))];
      if (itemIds.length) {
        // Only grant products that still exist — an admin may have deleted one.
        const items = await prisma.item.findMany({
          where: { id: { in: itemIds } },
          select: { id: true, durationDays: true },
        });
        for (const item of items) {
          await prisma.userItem.upsert({
            where: { userId_itemId: { userId: agency.userId, itemId: item.id } },
            update: {},
            create: {
              userId: agency.userId,
              itemId: item.id,
              isActive: false,
              expiresAt: expiryFromItem(item),
            },
          });
          itemsGranted++;
        }
      }
    }

    if (coinsPaid > 0 || itemsGranted > 0) {
      try {
        const parts: string[] = [];
        if (coinsPaid > 0) parts.push(`${coinsPaid} كوينز`);
        if (itemsGranted > 0) parts.push(`${itemsGranted} منتج`);
        await createNotification({
          userId: agency.userId,
          type: 'agency_charge_reward',
          title: 'مكافأة شحن الوكالة 🎁',
          body: `حصلت وكالة ${agency.agencyName} على ${parts.join(' و ')} كمكافأة على الشحن`,
          data: { agencyId, coinsPaid, itemsGranted },
        });
      } catch (e) {
        console.warn('[agencyReward] notification failed:', e);
      }
    }

    return { rungsPaid: rungs.length, coinsPaid, itemsGranted };
  } catch (e) {
    console.warn('[agencyReward] self-charge bookkeeping failed:', (e as Error).message);
    return EMPTY;
  }
}
