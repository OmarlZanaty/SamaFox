import prisma from '../utils/prisma';
import { createNotification } from './notification.service';

const db = prisma as any;

/**
 * A14 + A15 — إجمالي دعم الروم، ومكافآت الكأس والداعمين.
 *
 * A14 asks for the total coins thrown in a room, abbreviated (k/m), shown under
 * the room cup in every room, and reset after a period the admin sets from
 * لوحة التحكم. The reset is a rolling WINDOW rather than a stored counter that
 * something has to zero on a timer: a cron that resets counters can be missed,
 * run twice, or race a gift landing mid-reset, and any of those show the client
 * a wrong number. Summing `gift_transactions` over the last N hours is exact by
 * construction, never drifts, and needs no scheduled job — and the table is
 * already indexed on `[roomId, createdAt]`, which is precisely this query.
 */

/** Dashboard key holding the window length, in hours. 0 / unset = all-time. */
export const ROOM_SUPPORT_WINDOW_KEY = 'room_support_reset_hours';

export async function getRoomSupportWindowHours(): Promise<number> {
  try {
    const row = await db.appSetting.findUnique({ where: { key: ROOM_SUPPORT_WINDOW_KEY } });
    const n = Number(row?.value);
    return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  } catch (e) {
    // A settings blip must not blank the number out — fall back to all-time.
    console.warn('[roomReward] window lookup failed:', (e as Error).message);
    return 0;
  }
}

export async function setRoomSupportWindowHours(hours: number): Promise<number> {
  const value = String(Math.max(0, Math.floor(hours)));
  await db.appSetting.upsert({
    where: { key: ROOM_SUPPORT_WINDOW_KEY },
    update: { value },
    create: { key: ROOM_SUPPORT_WINDOW_KEY, value },
  });
  return Number(value);
}

/** Total coins gifted inside [roomId] within the configured window. */
export async function roomSupportTotal(roomId: number): Promise<number> {
  const hours = await getRoomSupportWindowHours();
  const agg = await db.giftTransaction.aggregate({
    where: {
      roomId,
      ...(hours > 0
        ? { createdAt: { gte: new Date(Date.now() - hours * 60 * 60 * 1000) } }
        : {}),
    },
    _sum: { totalCoins: true },
  });
  return Number(agg._sum?.totalCoins ?? 0);
}

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

/** Advisory-lock namespace for room cup payouts (one lock per room). */
const ROOM_CUP_LOCK = 41501;

/**
 * A15a — pay the room owner any كأس الروم rung this room has now crossed.
 *
 * Restricted to hosting agencies ("خاص بوكالة المضيفين فقط"), so an owner who
 * is not an approved hosting-agency member earns nothing here.
 *
 * Best-effort by design: a reward misconfiguration must never fail the gift
 * that triggered it. Two gifts landing at once are serialised on a per-room
 * advisory lock, so a rung is never paid twice for one window.
 */
export async function evaluateRoomCupRewards(roomId: number): Promise<void> {
  try {
    const rungs = await db.roomCupReward.findMany({
      where: { isActive: true },
      orderBy: { thresholdCoins: 'asc' },
    });
    if (rungs.length === 0) return;

    const room = await db.room.findUnique({
      where: { id: roomId },
      select: { id: true, ownerId: true, name: true },
    });
    if (!room?.ownerId) return;

    // وكالة المضيفين only.
    const hosting = await db.agencyMember.findFirst({
      where: { userId: room.ownerId, agency: { type: 'HOSTING', status: 'approved' } },
      select: { id: true },
    });
    if (!hosting) return;

    const hours = await getRoomSupportWindowHours();
    const total = await roomSupportTotal(roomId);

    for (const rung of rungs) {
      if (BigInt(Math.floor(total)) < BigInt(rung.thresholdCoins)) continue;

      const coins = Number(rung.rewardCoins ?? 0);
      if (coins <= 0) continue;

      const paid = await db.$transaction(async (tx: any) => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(${ROOM_CUP_LOCK}::int, ${roomId}::int)`;
        const last = await tx.roomCupRewardPayout.findFirst({
          where: { rewardId: rung.id, roomId },
          orderBy: { paidAt: 'desc' },
          select: { paidAt: true },
        });
        if (!rungDue(last?.paidAt, hours)) return false;
        await tx.roomCupRewardPayout.create({
          data: { rewardId: rung.id, roomId, userId: room.ownerId, coins: BigInt(coins) },
        });
        await tx.user.update({
          where: { id: room.ownerId },
          data: { coinsBalance: { increment: coins } },
        });
        return true;
      });
      if (!paid) continue;

      createNotification({
        userId: room.ownerId,
        type: 'room_cup_reward',
        title: 'مكافأة كأس الغرفة 🏆',
        body: `تهانينا! وصل دعم غرفتك إلى ${rung.thresholdCoins} كوينز فحصلت على ${coins} كوينز`,
        data: { roomId, coins },
      }).catch((e) => console.warn('[roomReward] notification failed:', e));
    }
  } catch (e) {
    console.warn('[roomReward] evaluateRoomCupRewards failed:', (e as Error).message);
  }
}

/**
 * A15b — how much [userId] has gifted, for supporter-reward eligibility.
 * Scoped to a room when the rung names one. Self-gifts never count.
 */
async function supporterGifted(userId: number, roomId: number | null): Promise<number> {
  const agg = await db.giftTransaction.aggregate({
    where: {
      senderId: userId,
      NOT: { recipientId: userId },
      ...(roomId != null ? { roomId } : {}),
    },
    _sum: { totalCoins: true },
  });
  return Number(agg._sum?.totalCoins ?? 0);
}

export interface SupporterRewardOffer {
  rewardId: number;
  targetCoins: string;
  rewardCoins: string;
  gifted: number;
}

/**
 * Rungs [userId] has earned in [roomId] and not yet claimed — this is what puts
 * the "مكافأة لك" square next to their name in كأس الروم.
 */
export async function pendingSupporterRewards(
  userId: number,
  roomId: number | null,
): Promise<SupporterRewardOffer[]> {
  const rungs = await db.supporterReward.findMany({
    where: { isActive: true, OR: [{ roomId: null }, ...(roomId != null ? [{ roomId }] : [])] },
    orderBy: { targetCoins: 'asc' },
  });
  if (rungs.length === 0) return [];

  const claimed = new Set<number>(
    (
      await db.supporterRewardClaim.findMany({
        where: { userId, rewardId: { in: rungs.map((r: any) => r.id) } },
        select: { rewardId: true },
      })
    ).map((c: any) => c.rewardId),
  );

  const out: SupporterRewardOffer[] = [];
  for (const rung of rungs) {
    if (claimed.has(rung.id)) continue;
    const gifted = await supporterGifted(userId, rung.roomId ?? null);
    if (BigInt(Math.floor(gifted)) < BigInt(rung.targetCoins)) continue;
    out.push({
      rewardId: rung.id,
      targetCoins: String(rung.targetCoins),
      rewardCoins: String(rung.rewardCoins),
      gifted,
    });
  }
  return out;
}

export class SupporterRewardError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** The supporter pressed "مكافأة لك". Pays once, then never again. */
export async function claimSupporterReward(
  userId: number,
  rewardId: number,
): Promise<{ coins: number }> {
  const rung = await db.supporterReward.findUnique({ where: { id: rewardId } });
  if (!rung || !rung.isActive) throw new SupporterRewardError(404, 'المكافأة غير متاحة');

  const gifted = await supporterGifted(userId, rung.roomId ?? null);
  if (BigInt(Math.floor(gifted)) < BigInt(rung.targetCoins)) {
    throw new SupporterRewardError(400, 'لم تكمل الدعم المطلوب لهذه المكافأة بعد');
  }

  const coins = Number(rung.rewardCoins ?? 0);
  if (coins <= 0) throw new SupporterRewardError(400, 'قيمة المكافأة غير صالحة');

  try {
    // Same pattern as the room cup: the unique (rewardId, userId) index is the
    // lock, so a double-tap cannot pay twice.
    await db.supporterRewardClaim.create({
      data: { rewardId, userId, roomId: rung.roomId ?? null, coins: BigInt(coins) },
    });
  } catch {
    throw new SupporterRewardError(409, 'حصلت على هذه المكافأة بالفعل');
  }

  await db.user.update({ where: { id: userId }, data: { coinsBalance: { increment: coins } } });

  createNotification({
    userId,
    type: 'supporter_reward',
    title: 'مكافأة الداعمين 🎁',
    body: `تم إضافة ${coins} كوينز إلى محفظتك`,
    data: { rewardId, coins },
  }).catch((e) => console.warn('[roomReward] notification failed:', e));

  return { coins };
}
