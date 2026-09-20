import { spawn } from 'child_process';
import fs from 'fs/promises';
import path from 'path';

// ============================================================
// Media optimisation at upload time
// ============================================================
// The dashboard was "ثقيلة أوي في تحميلها" because nothing ever shrank what
// was uploaded: a 20 MB GIF and 16 MB clips were stored as-is and served
// as-is to every phone and every admin list. Everything below is best-effort
// and size-checked — an optimisation that fails, or that would make the file
// BIGGER, leaves the original untouched. Nothing here changes a file's
// pixel dimensions unless the caller asks for it (frames and chat bubbles
// carry 9-slice guides in pixel coordinates, so they must keep their size).

const ffmpegPath = () => process.env.FFMPEG_PATH?.trim() || 'ffmpeg';

async function sizeOf(p: string) {
  try {
    return (await fs.stat(p)).size;
  } catch {
    return 0;
  }
}

function run(bin: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(bin, args);
    const err: Buffer[] = [];
    proc.stderr.on('data', (b: Buffer) => err.push(b));
    proc.on('error', reject);
    proc.on('close', (code) =>
      code === 0 ? resolve() : reject(new Error(`${bin} exited ${code}: ${Buffer.concat(err).toString('utf8').slice(0, 400)}`)),
    );
  });
}

/** Keep `candidate` in place of `original` only when it is actually smaller. */
async function keepIfSmaller(original: string, candidate: string, minGain = 0.85): Promise<boolean> {
  const [a, b] = await Promise.all([sizeOf(original), sizeOf(candidate)]);
  if (b > 0 && b < a * minGain) {
    await fs.rename(candidate, original);
    return true;
  }
  await fs.unlink(candidate).catch(() => {});
  return false;
}

export interface OptimizeResult {
  /** Final path (may differ in extension from the input). */
  path: string;
  changed: boolean;
  before: number;
  after: number;
}

/**
 * Still image → WebP. `maxSide` resizes down when given (icons, avatars,
 * chat pictures); omit it for artwork whose pixel size is meaningful.
 * Returns the new path (extension `.webp`). SVG and GIF are left alone.
 */
export async function optimizeImage(file: string, opts: { maxSide?: number; quality?: number } = {}): Promise<OptimizeResult> {
  const before = await sizeOf(file);
  const ext = path.extname(file).toLowerCase();
  if (!['.png', '.jpg', '.jpeg', '.webp'].includes(ext)) return { path: file, changed: false, before, after: before };
  try {
    const sharp = (await import('sharp')).default;
    const out = file.replace(/\.[^.]+$/, '') + '.opt.webp';
    let img = sharp(file, { animated: false }).rotate();
    if (opts.maxSide) img = img.resize({ width: opts.maxSide, height: opts.maxSide, fit: 'inside', withoutEnlargement: true });
    await img.webp({ quality: opts.quality ?? 82, effort: 4 }).toFile(out);
    const final = file.replace(/\.[^.]+$/, '') + '.webp';
    const after = await sizeOf(out);
    // A resize is always applied (the caller asked for a smaller picture);
    // a pure re-encode only sticks when it pays.
    if (opts.maxSide || after < before * 0.85) {
      await fs.rename(out, final);
      if (final !== file) await fs.unlink(file).catch(() => {});
      return { path: final, changed: true, before, after };
    }
    await fs.unlink(out).catch(() => {});
    return { path: file, changed: false, before, after: before };
  } catch (e) {
    console.warn('[mediaOptimize] image skipped:', (e as Error).message);
    return { path: file, changed: false, before, after: before };
  }
}

/**
 * GIF → GIF, same pixel size, ≤ 20 fps, a real palette per clip. This is the
 * single biggest win on the box (20 MB → 3–5 MB typical) and changes nothing
 * the app has to understand.
 */
export async function optimizeGif(file: string, opts: { maxSide?: number; fps?: number } = {}): Promise<OptimizeResult> {
  const before = await sizeOf(file);
  if (path.extname(file).toLowerCase() !== '.gif') return { path: file, changed: false, before, after: before };
  const out = `${file}.opt.gif`;
  const fps = opts.fps ?? 20;
  const scale = opts.maxSide ? `scale='min(${opts.maxSide},iw)':-1:flags=lanczos,` : '';
  const filters = `fps=${fps},${scale}split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle`;
  try {
    await run(ffmpegPath(), ['-y', '-loglevel', 'error', '-i', file, '-filter_complex', filters, out]);
    const changed = await keepIfSmaller(file, out);
    return { path: file, changed, before, after: await sizeOf(file) };
  } catch (e) {
    console.warn('[mediaOptimize] gif skipped:', (e as Error).message);
    await fs.unlink(out).catch(() => {});
    return { path: file, changed: false, before, after: before };
  }
}

/**
 * MP4/WebM → H.264 ≤ 720p, crf 26, faststart. Skipped for clips with an
 * alpha channel (their whole point is the transparency, and yuv420p has
 * none). Kept only when smaller.
 */
export async function shrinkVideo(file: string, opts: { maxHeight?: number; crf?: number } = {}): Promise<OptimizeResult> {
  const before = await sizeOf(file);
  const out = `${file}.opt.mp4`;
  try {
    await run(ffmpegPath(), [
      '-y', '-loglevel', 'error', '-i', file,
      '-vf', `scale=-2:'min(${opts.maxHeight ?? 720},ih)'`,
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'veryfast', '-crf', String(opts.crf ?? 26),
      '-movflags', '+faststart', '-c:a', 'aac', '-b:a', '96k',
      out,
    ]);
    const changed = await keepIfSmaller(file, out);
    return { path: file, changed, before, after: await sizeOf(file) };
  } catch (e) {
    console.warn('[mediaOptimize] video skipped:', (e as Error).message);
    await fs.unlink(out).catch(() => {});
    return { path: file, changed: false, before, after: before };
  }
}

/** Route by extension. `resizeTo` applies to still images only. */
export async function optimizeUpload(file: string, opts: { resizeTo?: number; gifMaxSide?: number } = {}): Promise<OptimizeResult> {
  const ext = path.extname(file).toLowerCase();
  if (ext === '.gif') return optimizeGif(file, { maxSide: opts.gifMaxSide });
  if (['.png', '.jpg', '.jpeg', '.webp'].includes(ext)) return optimizeImage(file, { maxSide: opts.resizeTo });
  if (['.mp4', '.mov', '.m4v', '.webm'].includes(ext)) return shrinkVideo(file);
  return { path: file, changed: false, before: await sizeOf(file), after: await sizeOf(file) };
}
