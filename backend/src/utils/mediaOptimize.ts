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

// ── Animated GIF policy ───────────────────────────────────────────────────
//
// What matters to a PHONE is not the bytes on disk but width × height × frames:
// every frame becomes a full RGBA texture. The catalogue held avatar frames of
// 420×746 × 111 frames (≈130 MB decoded each) and chat bubbles animated on
// every message; a room with a few of them sat at 1–1.5 GB and Android killed
// the app ("التطبيق بيفصل ويطلعني"). Pixel size and frame count are capped
// here per role, at upload time, and the 2026-09-21 bulk job applied the same
// numbers to everything already on the box.
export type GifRole = 'frame' | 'badge' | 'bubble' | 'banner' | 'icon' | 'bg' | 'default';

export const GIF_POLICY: Record<GifRole, { maxSide: number; maxFps: number; maxFrames: number }> = {
  frame:   { maxSide: 360, maxFps: 12, maxFrames: 48 },
  badge:   { maxSide: 256, maxFps: 12, maxFrames: 48 },
  bubble:  { maxSide: 480, maxFps: 10, maxFrames: 40 },
  banner:  { maxSide: 640, maxFps: 12, maxFrames: 48 },
  icon:    { maxSide: 256, maxFps: 12, maxFrames: 48 },
  bg:      { maxSide: 540, maxFps: 10, maxFrames: 60 },
  default: { maxSide: 360, maxFps: 12, maxFrames: 48 },
};

/** Hard ceiling after normalisation — anything still above this is refused. */
export const GIF_MAX_BYTES = 3 * 1024 * 1024;
export const GIF_MAX_DECODED_MB = 60;

export interface GifProbe { width: number; height: number; frames: number; durationS: number }

const ffprobePath = () => process.env.FFPROBE_PATH?.trim() || 'ffprobe';

function runOut(bin: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn(bin, args);
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    proc.stdout.on('data', (b: Buffer) => out.push(b));
    proc.stderr.on('data', (b: Buffer) => err.push(b));
    proc.on('error', reject);
    proc.on('close', (code) =>
      code === 0
        ? resolve(Buffer.concat(out).toString('utf8'))
        : reject(new Error(`${bin} exited ${code}: ${Buffer.concat(err).toString('utf8').slice(0, 400)}`)),
    );
  });
}

/** Exact frame count and size of a GIF (frames are counted, not estimated). */
export async function probeGif(file: string): Promise<GifProbe> {
  const raw = await runOut(ffprobePath(), [
    '-v', 'error', '-select_streams', 'v:0', '-count_frames',
    '-show_entries', 'stream=width,height,nb_read_frames,avg_frame_rate:format=duration',
    '-of', 'json', file,
  ]);
  const j = JSON.parse(raw);
  const st = j.streams?.[0] ?? {};
  const width = Number(st.width) || 0;
  const height = Number(st.height) || 0;
  const frames = Number(st.nb_read_frames) || 0;
  let durationS = Number(j.format?.duration) || 0;
  if (durationS <= 0 && frames > 0) {
    const [n = 10, d = 1] = String(st.avg_frame_rate || '10/1').split('/').map(Number);
    const fps = d ? n / d : 10;
    durationS = fps ? frames / fps : 0;
  }
  return { width, height, frames, durationS };
}

export const gifDecodedMb = (p: GifProbe) => (p.width * p.height * 4 * Math.max(p.frames, 1)) / 1048576;

/**
 * Bring a GIF within [GIF_POLICY] for its role: downscale, cap the frame rate
 * and the frame count (the rate drops further for long clips so the total
 * stays under `maxFrames`). Replaces the file in place. Returns the probe of
 * whatever is on disk afterwards, and throws only if the result is still
 * beyond the hard ceiling — the caller then deletes the upload and tells the
 * dashboard why.
 */
export async function normalizeGif(file: string, role: GifRole = 'default'): Promise<{ probe: GifProbe; changed: boolean }> {
  if (path.extname(file).toLowerCase() !== '.gif') {
    return { probe: { width: 0, height: 0, frames: 0, durationS: 0 }, changed: false };
  }
  const pol = GIF_POLICY[role] ?? GIF_POLICY.default;
  const before = await probeGif(file);
  const tooBig = Math.max(before.width, before.height) > pol.maxSide;
  const tooMany = before.frames > pol.maxFrames;
  const tooFast = before.durationS > 0 && before.frames / before.durationS > pol.maxFps + 0.5;
  let probe = before;
  let changed = false;
  if (tooBig || tooMany || tooFast) {
    let fps = pol.maxFps;
    if (before.durationS > 0 && before.durationS * fps > pol.maxFrames) {
      fps = Math.max(4, pol.maxFrames / before.durationS);
    }
    const scale = tooBig
      ? `scale='if(gt(iw,ih),${pol.maxSide},-2)':'if(gt(iw,ih),-2,${pol.maxSide})':flags=lanczos,`
      : '';
    const filters =
      `fps=${fps.toFixed(3)},${scale}split[a][b];` +
      `[a]palettegen=stats_mode=diff:reserve_transparent=1[p];` +
      `[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle:alpha_threshold=128`;
    const out = `${file}.norm.gif`;
    try {
      await run(ffmpegPath(), ['-y', '-loglevel', 'error', '-i', file, '-filter_complex', filters, '-loop', '0', out]);
      const after = await probeGif(out);
      if (after.frames > 0 && gifDecodedMb(after) <= gifDecodedMb(before)) {
        await fs.rename(out, file);
        probe = after;
        changed = true;
      } else {
        await fs.unlink(out).catch(() => {});
      }
    } catch (e) {
      console.warn('[mediaOptimize] gif normalise skipped:', (e as Error).message);
      await fs.unlink(out).catch(() => {});
    }
  }
  const bytes = await sizeOf(file);
  const decoded = gifDecodedMb(probe);
  if (bytes > GIF_MAX_BYTES || decoded > GIF_MAX_DECODED_MB) {
    throw new Error(
      `الصورة المتحركة أثقل من المسموح (${probe.width}×${probe.height}، ${probe.frames} إطار، ` +
      `${(bytes / 1048576).toFixed(1)} ميجابايت). الحد: ${pol.maxSide}px، ${pol.maxFrames} إطار، ${GIF_MAX_BYTES / 1048576} ميجابايت.`,
    );
  }
  return { probe, changed };
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
export async function optimizeUpload(file: string, opts: { resizeTo?: number; gifMaxSide?: number; gifRole?: GifRole } = {}): Promise<OptimizeResult> {
  const ext = path.extname(file).toLowerCase();
  if (ext === '.gif') {
    // Role policy first (pixels + frames), then the palette pass for bytes.
    // normalizeGif throws when the clip is beyond the hard ceiling; that
    // propagates so the upload is refused with the reason.
    const before = await sizeOf(file);
    await normalizeGif(file, opts.gifRole ?? 'default');
    const pal = await optimizeGif(file, { maxSide: opts.gifMaxSide });
    return { path: file, changed: true, before, after: pal.after };
  }
  if (['.png', '.jpg', '.jpeg', '.webp'].includes(ext)) return optimizeImage(file, { maxSide: opts.resizeTo });
  if (['.mp4', '.mov', '.m4v', '.webm'].includes(ext)) return shrinkVideo(file);
  return { path: file, changed: false, before: await sizeOf(file), after: await sizeOf(file) };
}
