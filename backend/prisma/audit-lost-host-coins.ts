/**
 * Audit for the "coins vanished" bug.
 *
 * Until now, giftService decided a recipient was a hosting-agency host with:
 *     where: { userId, agency: { type: 'HOSTING' } }        // no status filter
 * while getMyTarget / convertTarget both additionally require
 *     agency: { status: 'approved' }
 *
 * So a member of a PENDING or REJECTED hosting agency had their gift credit
 * zeroed (the coins never reached their balance) while their target stayed
 * invisible and unconvertible. Those coins reached nobody.
 *
 * This script REPORTS the affected users and the amount each lost. It does not
 * write anything by default — run it, review the output, then re-run with
 *     npx ts-node prisma/audit-lost-host-coins.ts --refund
 * to credit each affected user the 50% they would normally have received.
 *
 * Note: only gifts received while the agency was NOT approved are affected. We
 * cannot know exactly when a status changed (it isn't versioned), so the
 * refund covers users whose agency is STILL not approved — the unambiguous
 * case. Anything else should be handled manually.
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const REFUND = process.argv.includes('--refund');

async function main() {
  // Memberships in hosting agencies that are NOT approved.
  const bad = await prisma.agencyMember.findMany({
    where: { agency: { type: 'HOSTING', status: { not: 'approved' } } },
    include: {
      agency: { select: { id: true, agencyName: true, status: true } },
      user: { select: { id: true, name: true, displayId: true } },
    },
  });

  if (bad.length === 0) {
    console.log('No memberships in non-approved hosting agencies. Nothing to audit.');
    return;
  }

  let grandTotal = 0;
  const rows: { userId: number; label: string; lost: number }[] = [];

  for (const m of bad) {
    const agg = await prisma.giftTransaction.aggregate({
      where: {
        recipientId: m.userId,
        senderId: { not: m.userId },
        createdAt: { gte: m.joinedAt },
      },
      _sum: { totalCoins: true },
    });
    const received = Number(agg._sum.totalCoins ?? 0);
    // They should have been credited half, like any non-agency user.
    const lost = Math.floor(received / 2);
    if (lost <= 0) continue;

    grandTotal += lost;
    rows.push({
      userId: m.userId,
      label: `${m.user.name ?? '?'} (#${m.user.displayId ?? m.userId}) — agency "${m.agency.agencyName}" [${m.agency.status}]`,
      lost,
    });
  }

  if (rows.length === 0) {
    console.log('Affected memberships exist, but none of them received any gifts. Nothing lost.');
    return;
  }

  console.log(`\n${rows.length} user(s) affected, ${grandTotal} coins lost in total:\n`);
  for (const r of rows) console.log(`  ${r.label}\n    owed: ${r.lost} coins`);

  if (!REFUND) {
    console.log('\nDry run. Re-run with --refund to credit these users.');
    return;
  }

  console.log('\nRefunding…');
  for (const r of rows) {
    await prisma.user.update({
      where: { id: r.userId },
      data: { coinsBalance: { increment: r.lost } },
    });
    console.log(`  credited ${r.lost} to user ${r.userId}`);
  }
  console.log(`\nDone. ${grandTotal} coins refunded across ${rows.length} user(s).`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
