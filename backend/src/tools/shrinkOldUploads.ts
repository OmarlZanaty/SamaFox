// One-off: shrink oversized images already in uploads/ (see utils/shrinkUploads).
//
//   node dist/tools/shrinkOldUploads.js            # dry run: lists what would change
//   node dist/tools/shrinkOldUploads.js --apply    # resizes in place
//
// Back the folder up first; the files are rewritten under their own names.
import path from 'path';
import prisma from '../utils/prisma';
import { planShrink, shrinkInPlace, uploadName } from '../utils/shrinkUploads';

async function main() {
  const apply = process.argv.includes('--apply');
  const dir = path.join(__dirname, '../../uploads');
  const users = await prisma.user.findMany({
    where: { avatarUrl: { contains: '/uploads/' } },
    select: { avatarUrl: true },
  });
  const avatars = new Set(users.map((u) => uploadName(u.avatarUrl)).filter((n): n is string => !!n));
  const plans = await planShrink(dir, avatars);
  let saved = 0;
  for (const plan of plans) {
    const name = path.basename(plan.file);
    if (!apply) {
      console.log(`would shrink ${name} ${plan.width}x${plan.height} -> ${plan.maxSide}`);
      continue;
    }
    try {
      const [before, after] = await shrinkInPlace(plan);
      saved += before - after;
      console.log(`shrunk ${name} ${plan.width}x${plan.height} -> ${plan.maxSide} (${before} -> ${after} bytes)`);
    } catch (e) {
      console.warn(`skipped ${name}: ${(e as Error).message}`);
    }
  }
  console.log(`${plans.length} oversized (${avatars.size} avatar files known)${apply ? `, ${Math.round(saved / 1024)} KB saved` : ' — dry run'}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
