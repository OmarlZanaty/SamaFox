import { Router } from 'express';
import fs from 'fs';
import path from 'path';

/**
 * G2 — direct APK download.
 *
 * The owner asked for this nine times, more than anything else in the chat: the
 * agents needed a link to send people before the Play listing existed.
 *
 * The version is READ OFF THE FILE rather than configured anywhere. A version
 * number typed into a config is how people end up downloading a months-old
 * build and reporting bugs that were fixed weeks ago; here, publishing a new
 * release is a file copy into `public/downloads` and nothing else.
 *
 * Naming convention: `samafox-<version>.apk`, e.g. `samafox-1.0.18.apk`.
 * The newest by modification time wins, so an older file left behind is
 * harmless.
 */
const router = Router();

const downloadsDir = () => path.join(process.cwd(), 'public', 'downloads');

interface Build {
  file: string;
  version: string | null;
  sizeMb: number;
  updatedAt: Date;
}

function latestBuild(): Build | null {
  const dir = downloadsDir();
  let names: string[];
  try {
    names = fs.readdirSync(dir).filter((n) => n.toLowerCase().endsWith('.apk'));
  } catch {
    return null; // directory not created yet — nothing published
  }
  if (names.length === 0) return null;

  const builds: Build[] = names.map((file) => {
    const stat = fs.statSync(path.join(dir, file));
    const m = file.match(/(\d+\.\d+\.\d+(?:\+\d+)?)/);
    return {
      file,
      version: m?.[1] ?? null,
      sizeMb: Math.round((stat.size / (1024 * 1024)) * 10) / 10,
      updatedAt: stat.mtime,
    };
  });

  builds.sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
  // names.length was checked above, so there is always a first element; the
  // explicit ?? null keeps noUncheckedIndexedAccess happy without a cast.
  return builds[0] ?? null;
}

/** What the download page asks for. */
router.get('/latest', (_req, res) => {
  const build = latestBuild();
  if (!build) {
    return res.status(404).json({ success: false, message: 'لم يتم رفع نسخة بعد' });
  }
  return res.json({
    success: true,
    version: build.version,
    sizeMb: build.sizeMb,
    updatedAt: build.updatedAt.toISOString(),
    // Served through the redirect below rather than as a static path, so the
    // link in someone's WhatsApp keeps working across releases.
    url: '/api/v1/app/download',
  });
});

/** The download itself — always the newest build. */
router.get('/download', (_req, res) => {
  const build = latestBuild();
  if (!build) {
    return res.status(404).json({ success: false, message: 'لم يتم رفع نسخة بعد' });
  }
  const full = path.join(downloadsDir(), build.file);

  // `application/vnd.android.package-archive` is what makes Android offer to
  // install rather than open the file as text.
  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', `attachment; filename="${build.file}"`);
  return res.sendFile(full);
});

export default router;
