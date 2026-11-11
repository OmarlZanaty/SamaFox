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

export { rungDue, rungIncrement, cupLevels } from './roomCupMath';
import { rungDue, rungIncrement, cupLevels } from './roomCupMath';

/** Advisory-lock namespace for room cup payouts (one lock per room). */
const ROOM_CUP_LOCK = 41501;

/** Same host-share amount as roomSupportTotal, bounded to this cup's window. */
export async function perRoomCupSupport(cup: { roomId: number; startsAt: Date; endsAt: Date }, client: any = db): Promise<bigint> {
  const agg = await client.giftTransaction.aggregate({
    where: { roomId: cup.roomId, createdAt: { gte: cup.startsAt, lte: cup.endsAt } },
    _sum: { totalCoins: true },
  });
  return BigInt(agg._sum?.totalCoins ?? 0);
}

export async function evaluatePerRoomCups(roomId: number): Promise<void> {
  try {
    const now = new Date();
    const cups = await db.roomCup.findMany({ where: { roomId, paidAt: null, startsAt: { lte: now }, endsAt: { gt: new Date(now.getTime() - 60000) } } });
    for (const candidate of cups) {
      const granted = await db.$transaction(async (tx: any) => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(${ROOM_CUP_LOCK}::int, ${roomId}::int)`;
        const cup = await tx.roomCup.findUnique({ where: { id: candidate.id } });
        const at = new Date();
        if (!cup || cup.paidAt || cup.startsAt > at || cup.endsAt.getTime() <= at.getTime() - 60000) return null;
        const support = await perRoomCupSupport(cup, tx);
        const room = await tx.room.findUnique({ where: { id: roomId }, select: { ownerId: true } });
        if (!room?.ownerId) return null;
        const levels = cupLevels(cup);
        const rewards = levels.map((l) => l.rewardCoins);
        let coins = 0n;
        for (const [level, l] of levels.entries()) {
          if (support < l.targetCoins) break;
          const add = rungIncrement(rewards, level);
          if (add <= 0n || add > 2147483647n) continue;
          const exists = await tx.roomCupClaim.findFirst({ where: { source: 'cup', refId: cup.id, level } });
          if (exists) continue;
          // Waits under the owner's name in the cup until he collects it.
          await tx.roomCupClaim.create({ data: { roomId, userId: room.ownerId, coins: add, source: 'cup', refId: cup.id, level } });
          coins += add;
        }
        // Every level reached: the cup is done.
        const top = levels[levels.length - 1];
        if (top && support >= top.targetCoins) {
          await tx.roomCup.updateMany({ where: { id: cup.id, paidAt: null }, data: { paidAt: at, paidToUserId: room.ownerId } });
        }
        return coins > 0n ? { userId: room.ownerId, coins: Number(coins) } : null;
      });
      if (granted) await createNotification({
        userId: granted.userId, type: 'room_cup_reward', title: 'مكافأة كأس الغرفة 🏆',
        body: `وصل دعم غرفتك للمستوى المطلوب — مكافأة ${granted.coins} كوينز مستنياك تحت اسمك في كأس الغرفة، اضغط «استلم»`,
        data: { roomId, cupId: candidate.id, coins: granted.coins },
      }).catch(e => console.warn('[roomReward] notification failed:', e));
    }
  } catch (e) { console.warn('[roomReward] evaluatePerRoomCups failed:', (e as Error).message); }
}

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
  // Keep the protected gift caller unchanged; run before hosting checks.
  await evaluatePerRoomCups(roomId);
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

    // Rewards are cumulative per level: each rung pays only what it adds.
    const rewards = rungs.map((r: any) => BigInt(r.rewardCoins ?? 0));
    for (const [index, rung] of rungs.entries()) {
      if (BigInt(Math.floor(total)) < BigInt(rung.thresholdCoins)) continue;

      const coins = Number(rungIncrement(rewards, index));
      if (coins <= 0) continue;

      const paid = await db.$transaction(async (tx: any) => {
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(${ROOM_CUP_LOCK}::int, ${roomId}::int)`;
        const last = await tx.roomCupRewardPayout.findFirst({
          where: { rewardId: rung.id, roomId },
          orderBy: { paidAt: 'desc' },
          select: { paidAt: true },
        });
        if (!rungDue(last?.paidAt, hours)) return false;
        const payout = await tx.roomCupRewardPayout.create({
          data: { rewardId: rung.id, roomId, userId: room.ownerId, coins: BigInt(coins) },
        });
        // Not into the wallet: it waits under the owner's name in the cup
        // until he collects it (client 10/11 19:02).
        await tx.roomCupClaim.create({
          data: { roomId, userId: room.ownerId, coins: BigInt(coins), source: 'rung', refId: payout.id, level: 0 },
        });
        return true;
      });
      if (!paid) continue;

      createNotification({
        userId: room.ownerId,
        type: 'room_cup_reward',
        title: 'مكافأة كأس الغرفة 🏆',
        body: `وصل دعم غرفتك إلى ${rung.thresholdCoins} كوينز — مكافأة ${coins} كوينز مستنياك تحت اسمك في كأس الغرفة، اضغط «استلم»`,
        data: { roomId, coins },
      }).catch((e) => console.warn('[roomReward] notification failed:', e));
    }
  } catch (e) {
    console.warn('[roomReward] evaluateRoomCupRewards failed:', (e as Error).message);
  }
}

/**
 * A15b — how much [userId] has gifted, for supporter-reward eligibility.
 * Scoped to a room when the rung names one. SPEC52 #9 — self-gifts count.
 */
async function supporterGifted(userId: number, roomId: number | null): Promise<number> {
  const agg = await db.giftTransaction.aggregate({
    where: {
      senderId: userId,
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

/** One room-cup reward still waiting under the owner's name. */
export interface RoomCupClaimOffer {
  claimId: number;
  coins: string;
  source: string;
  level: number;
  createdAt: Date;
}

/** Rewards [userId] has been granted in [roomId] and not collected yet. */
export async function pendingRoomCupClaims(userId: number, roomId: number): Promise<RoomCupClaimOffer[]> {
  const rows = await db.roomCupClaim.findMany({
    where: { userId, roomId, claimedAt: null },
    orderBy: { createdAt: 'asc' },
    take: 50,
  });
  return rows.map((r: any) => ({ claimId: r.id, coins: String(r.coins), source: r.source, level: r.level, createdAt: r.createdAt }));
}

/** The owner pressed «استلم» under his name in the cup. Pays once. */
export async function claimRoomCupReward(userId: number, claimId: number): Promise<{ coins: number; roomId: number }> {
  return db.$transaction(async (tx: any) => {
    const claim = await tx.roomCupClaim.findUnique({ where: { id: claimId } });
    if (!claim || claim.userId !== userId) throw new SupporterRewardError(404, 'المكافأة غير متاحة');
    const coins = Number(claim.coins);
    if (!Number.isSafeInteger(coins) || coins <= 0 || coins > 2147483647) throw new SupporterRewardError(400, 'قيمة المكافأة غير صالحة');
    const taken = await tx.roomCupClaim.updateMany({ where: { id: claimId, claimedAt: null }, data: { claimedAt: new Date() } });
    if (taken.count !== 1) throw new SupporterRewardError(409, 'استلمت هذه المكافأة بالفعل');
    await tx.user.update({ where: { id: userId }, data: { coinsBalance: { increment: coins } } });
    await tx.transaction.create({ data: {
      userId, type: claim.source === 'cup' ? 'ROOM_CUP_BY_ID_REWARD' : 'ROOM_CUP_REWARD',
      amountCoins: coins, status: 'completed', externalId: `room-cup-claim:${claim.id}`,
    } });
    return { coins, roomId: claim.roomId };
  });
}

