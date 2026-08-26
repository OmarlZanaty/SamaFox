/**
 * One-off: move stranded agency wallets into their owners' wallets.
 *
 * Charging used to be paid out of ChargingAgency.balanceCoins — a pot only an
 * admin could fill. Charges now come out of the AGENT'S OWN wallet
 * (user.coinsBalance), so whatever is still sitting in balanceCoins is money
 * the agent paid for and can no longer spend.
 *
 * This script REPORTS every agency with a non-zero balance and who it would go
 * to. It writes nothing by default — run it, review the output, then re-run
 * with
 *     npx ts-node prisma/drain-agency-balances.ts --apply
 * to credit each owner and zero the agency pot.
 *
 * Safe to re-run: the transfer is guarded on the exact balance it read, so an
 * agency that was already drained (or that changed under it) is skipped rather
 * than paid twice.
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
const APPLY = process.argv.includes('--apply');

async function main() {
  const agencies = await prisma.chargingAgency.findMany({
    where: { balanceCoins: { gt: 0 } },
    select: {
      id: true,
      userId: true,
      agencyName: true,
      type: true,
      status: true,
      balanceCoins: true,
    },
    orderBy: { id: 'asc' },
  });

  if (agencies.length === 0) {
    console.log('No agency holds a non-zero balance. Nothing to move.');
    return;
  }

  // The owner is ChargingAgency.userId, but ownership can be transferred
  // (نقل ملكية الوكالة) — the OWNER member row is the source of truth, so
  // prefer it and fall back to userId.
  const owners = await prisma.agencyMember.findMany({
    where: { agencyId: { in: agencies.map((a) => a.id) }, role: 'OWNER' },
    select: { agencyId: true, userId: true },
  });
  const ownerByAgency = new Map(owners.map((o) => [o.agencyId, o.userId]));

  const rows: { agencyId: number; ownerId: number; amount: number; label: string }[] = [];
  const orphans: string[] = [];

  for (const a of agencies) {
    const ownerId = ownerByAgency.get(a.id) ?? a.userId;
    const owner = await prisma.user.findUnique({
      where: { id: ownerId },
      select: { id: true, name: true, displayId: true },
    });

    const label = `agency #${a.id} "${a.agencyName}" [${a.type}/${a.status}] — ${a.balanceCoins} coins`;

    if (!owner) {
      // Deleted account: nobody to pay. Left untouched for manual handling.
      orphans.push(`${label} → owner ${ownerId} NOT FOUND`);
      continue;
    }

    rows.push({
      agencyId: a.id,
      ownerId: owner.id,
      amount: a.balanceCoins,
      label: `${label} → ${owner.name ?? '?'} (#${owner.displayId ?? owner.id})`,
    });
  }

  const grandTotal = rows.reduce((sum, r) => sum + r.amount, 0);

  console.log(`\n${rows.length} agency wallet(s) to move, ${grandTotal} coins in total:\n`);
  for (const r of rows) console.log(`  ${r.label}`);

  if (orphans.length > 0) {
    console.log(`\n${orphans.length} agency wallet(s) SKIPPED — no owner account:\n`);
    for (const o of orphans) console.log(`  ${o}`);
  }

  if (!APPLY) {
    console.log('\nDry run. Re-run with --apply to move these balances.');
    return;
  }

  console.log('\nMoving…');
  let moved = 0;
  for (const r of rows) {
    await prisma.$transaction(async (tx) => {
      // Guarded on the balance we reported, so a re-run (or a concurrent
      // change) can never credit the same coins twice.
      const drained = await tx.chargingAgency.updateMany({
        where: { id: r.agencyId, balanceCoins: r.amount },
        data: { balanceCoins: 0 },
      });
      if (drained.count === 0) {
        console.log(`  SKIPPED agency ${r.agencyId} — balance changed since the report`);
        return;
      }

      await tx.user.update({
        where: { id: r.ownerId },
        data: { coinsBalance: { increment: r.amount } },
      });

      moved += r.amount;
      console.log(`  moved ${r.amount} from agency ${r.agencyId} to user ${r.ownerId}`);
    });
  }

  console.log(`\nDone. ${moved} coins moved.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
