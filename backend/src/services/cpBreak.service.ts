import prisma from '../utils/prisma';
import { createNotification } from './notification.service';
import { CpError } from './cpUnlock.service';
import { reassignFeaturedAfterRemoval } from './cpGift.service';
import { PROGRAM_ACCOUNT, creditAccount } from './economyAccounts.service';

const db = prisma as any;

/**
 * فك CP — breaking a pair costs a fee (2026-09-26, items 8–9).
 *
 *   Break fee = Program Fee + Partner Fee
 *     Program Fee → the PROGRAM account
 *     Partner Fee → the other partner's balance
 *
 * Which fee applies to the user breaking the pair:
 *   1. their «رسوم CP مخصصة» row, when enabled
 *   2. otherwise the global cp_break_program_fee / cp_break_partner_fee
 * Both default to 0, so until the admin sets a fee breaking stays free, as it
 * always has been.
 *
 * Everything — the checks, the debit, both credits, removing the pair and the
 * log row — happens in ONE transaction; any failure leaves nothing changed.
 */

export const CP_BREAK_KEYS = {
  programFee: 'cp_break_program_fee',
  partnerFee: 'cp_break_partner_fee',
} as const;

const MAX_FEE = 2_000_000_000;

function orderPair(a: number, b: number): [number, number] {
  return a < b ? [a, b] : [b, a];
}

const toFee = (v: unknown) => {
  const n = Math.floor(Number(v));
  return Number.isFinite(n) && n >= 0 ? Math.min(n, MAX_FEE) : 0;
};

export async function getGlobalBreakFees(tx: any = db) {
  const rows: { key: string; value: string }[] = await tx.appSetting.findMany({
    where: { key: { in: Object.values(CP_BREAK_KEYS) } },
  });
  const m = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return { programFee: toFee(m[CP_BREAK_KEYS.programFee]), partnerFee: toFee(m[CP_BREAK_KEYS.partnerFee]) };
}

export async function setGlobalBreakFees(programFee: number, partnerFee: number, tx: any = db) {
  const p = toFee(programFee);
  const q = toFee(partnerFee);
  for (const [key, value] of [
    [CP_BREAK_KEYS.programFee, String(p)],
    [CP_BREAK_KEYS.partnerFee, String(q)],
  ] as const) {
    await tx.appSetting.upsert({ where: { key }, update: { value }, create: { key, value } });
  }
  return { programFee: p, partnerFee: q };
}

export interface BreakQuote {
  programFee: number;
  partnerFee: number;
  totalFee: number;
  feeSource: 'CUSTOM' | 'GLOBAL' | 'FREE';
}

/** The fee `userId` pays to break a pair — custom first, then global. */
export async function quoteBreakFee(userId: number, tx: any = db): Promise<BreakQuote> {
  const custom = await tx.cpBreakCustomFee.findUnique({ where: { userId } });
  if (custom?.enabled) {
    const programFee = Number(custom.programFee);
    const partnerFee = Number(custom.partnerFee);
    return { programFee, partnerFee, totalFee: programFee + partnerFee, feeSource: 'CUSTOM' };
  }
  const g = await getGlobalBreakFees(tx);
  const total = g.programFee + g.partnerFee;
  return { ...g, totalFee: total, feeSource: total > 0 ? 'GLOBAL' : 'FREE' };
}

/** What the app shows before "تأكيد فك الارتباط": the fee and the balance. */
export async function getBreakQuote(userId: number, partnerId: number) {
  if (!Number.isInteger(partnerId) || partnerId <= 0 || partnerId === userId) {
    throw new CpError('BAD_PARTNER', 'شريك غير صالح');
  }
  const [aId, bId] = orderPair(userId, partnerId);
  const [pair, quote, me] = await Promise.all([
    db.cpPair.findUnique({ where: { userAId_userBId: { userAId: aId, userBId: bId } } }),
    quoteBreakFee(userId),
    db.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } }),
  ]);
  if (!pair) throw new CpError('NOT_FOUND', 'لا يوجد ارتباط CP مع هذا المستخدم', 404);
  const balance = Number(me?.coinsBalance ?? 0);
  return { ...quote, balance, shortfall: Math.max(0, quote.totalFee - balance) };
}

/**
 * Break the pair between `userId` and `partnerId`, charging `userId` the
 * applicable fee. Idempotent at the route (Idempotency-Key); here a second
 * attempt simply finds no pair and changes nothing.
 */
export async function breakCpPair(userId: number, partnerId: number) {
  if (!Number.isInteger(partnerId) || partnerId <= 0 || partnerId === userId) {
    throw new CpError('BAD_PARTNER', 'شريك غير صالح');
  }
  const [aId, bId] = orderPair(userId, partnerId);

  const result = await db.$transaction(
    async (tx: any) => {
      // 1–2. The pair exists, and this user is one of its two ends (by
      // construction of the lookup).
      const pair = await tx.cpPair.findUnique({ where: { userAId_userBId: { userAId: aId, userBId: bId } } });
      if (!pair) throw new CpError('NOT_FOUND', 'لا يوجد ارتباط CP مع هذا المستخدم', 404);

      // 3. The fee, read inside the transaction.
      const quote = await quoteBreakFee(userId, tx);

      // 4. Debit, only if the balance covers all of it.
      if (quote.totalFee > 0) {
        const charged = await tx.user.updateMany({
          where: { id: userId, coinsBalance: { gte: quote.totalFee } },
          data: { coinsBalance: { decrement: quote.totalFee } },
        });
        if (charged.count !== 1) {
          const me = await tx.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } });
          const balance = Number(me?.coinsBalance ?? 0);
          throw new CpError(
            'INSUFFICIENT_COINS',
            `رصيدك لا يكفي لفك الارتباط — الرسوم ${quote.totalFee} ورصيدك ${balance}`,
            402,
            { ...quote, balance, shortfall: Math.max(0, quote.totalFee - balance) },
          );
        }
        await tx.transaction.create({
          data: { userId, type: 'CP_BREAK_FEE', amountCoins: -quote.totalFee, status: 'completed', externalId: `cp-break:${pair.id}` },
        });
      }

      // 5. The program's share.
      if (quote.programFee > 0) {
        await creditAccount(tx, PROGRAM_ACCOUNT, quote.programFee, {
          kind: 'CP_BREAK_FEE',
          refType: 'cp_pair',
          refId: pair.id,
          userId,
        });
      }

      // 6. The partner's share.
      if (quote.partnerFee > 0) {
        await tx.user.update({ where: { id: partnerId }, data: { coinsBalance: { increment: quote.partnerFee } } });
        await tx.transaction.create({
          data: {
            userId: partnerId,
            type: 'CP_BREAK_COMPENSATION',
            amountCoins: quote.partnerFee,
            status: 'completed',
            externalId: `cp-break:${pair.id}`,
            senderId: userId,
          },
        });
      }

      // 7. The pair goes.
      await tx.cpPair.delete({ where: { id: pair.id } });

      // 8. The record.
      const log = await tx.cpBreakLog.create({
        data: {
          pairId: pair.id,
          requesterId: userId,
          partnerId,
          programFee: BigInt(quote.programFee),
          partnerFee: BigInt(quote.partnerFee),
          feeSource: quote.feeSource,
          cpValue: Number(pair.cpValue ?? 0),
          pairCreatedAt: pair.createdAt,
        },
      });

      const me = await tx.user.findUnique({ where: { id: userId }, select: { coinsBalance: true } });
      return { pairId: pair.id, logId: log.id, quote, balance: Number(me?.coinsBalance ?? 0) };
    },
    { isolationLevel: 'Serializable', maxWait: 5_000, timeout: 10_000 },
  );

  // After the commit only: the featured partner moves on, the partner is told.
  try {
    await reassignFeaturedAfterRemoval(aId, bId);
  } catch (e) {
    console.warn('[cp-break] featured reassignment failed:', (e as Error).message);
  }
  await createNotification({
    userId: partnerId,
    actorId: userId,
    type: 'cp_removed',
    title: 'تم إلغاء الـ CP',
    body:
      result.quote.partnerFee > 0
        ? `تم إلغاء ارتباط الـ CP ووصلك ${result.quote.partnerFee} كوينز تعويضاً`
        : 'تم إلغاء ارتباط الـ CP',
    data: { partnerId: userId, compensation: result.quote.partnerFee },
  }).catch(() => undefined);

  return { removed: true, ...result };
}

// ── custom per-user fee (admin) ──────────────────────────────

export async function getCustomFee(userId: number) {
  return db.cpBreakCustomFee.findUnique({ where: { userId } });
}

export async function upsertCustomFee(
  userId: number,
  data: { programFee: number; partnerFee: number; enabled: boolean; note?: string | null },
  adminId: number,
  tx: any = db,
) {
  return tx.cpBreakCustomFee.upsert({
    where: { userId },
    update: { programFee: BigInt(toFee(data.programFee)), partnerFee: BigInt(toFee(data.partnerFee)), enabled: Boolean(data.enabled), note: data.note ?? null, updatedBy: adminId },
    create: { userId, programFee: BigInt(toFee(data.programFee)), partnerFee: BigInt(toFee(data.partnerFee)), enabled: Boolean(data.enabled), note: data.note ?? null, updatedBy: adminId },
  });
}
