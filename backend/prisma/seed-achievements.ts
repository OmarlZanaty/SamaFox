import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Starter achievement set for the room profile card's medals row.
 *
 * `metric` must match what checkAchievements(userId, metric, value) is called
 * with; `target` is the threshold at which the medal unlocks. iconUrl points
 * at /uploads/medals/*.png — upload the medal art to that folder on the
 * server (admin dashboard upload or scp) and these light up automatically.
 *
 * Idempotent: re-running updates existing rows (matched by name) rather than
 * duplicating, so it's safe to run after adding new medals.
 */
const ACHIEVEMENTS = [
  { name: 'أول هدية', description: 'أرسلت أول هدية لك', metric: 'gifts_sent', target: 1, icon: 'medal-1-first-gift.png' },
  { name: 'كريم', description: 'أرسلت 100 هدية', metric: 'gifts_sent', target: 100, icon: 'medal-2-generous.png' },
  { name: 'أسطورة العطاء', description: 'أرسلت 1000 هدية', metric: 'gifts_sent', target: 1000, icon: 'medal-3-legend.png' },
  { name: 'عضو VIP', description: 'وصلت إلى VIP 1', metric: 'vip_level', target: 1, icon: 'medal-4-vip1.png' },
  { name: 'VIP ملكي', description: 'وصلت إلى VIP 5', metric: 'vip_level', target: 5, icon: 'medal-5-vip5.png' },
  { name: 'صاعد', description: 'وصلت إلى المستوى 10', metric: 'level', target: 10, icon: 'medal-6-level10.png' },
  { name: 'مشهور', description: 'وصلت إلى 100 متابع', metric: 'followers', target: 100, icon: 'medal-7-followers.png' },
  { name: 'عضو وكالة', description: 'انضممت إلى وكالة', metric: 'agency_joined', target: 1, icon: 'medal-8-agency.png' },
];

async function main() {
  let inserted = 0;
  let updated = 0;

  for (const a of ACHIEVEMENTS) {
    const data = {
      name: a.name,
      description: a.description,
      iconUrl: `/uploads/medals/${a.icon}`,
      metric: a.metric,
      target: a.target,
    };

    const existing = await prisma.achievement.findFirst({ where: { name: a.name } });
    if (existing) {
      await prisma.achievement.update({ where: { id: existing.id }, data });
      updated++;
    } else {
      await prisma.achievement.create({ data });
      inserted++;
    }
  }

  console.log(`Achievements seeded: ${inserted} new, ${updated} updated.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
