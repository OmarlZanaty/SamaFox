import { spawn } from 'child_process';
import { existsSync } from 'fs';
import fs from 'fs/promises';
import path from 'path';

let ffprobePath: string | null = null;

function getFfprobePath(): string {
  if (ffprobePath) return ffprobePath;
  // Use ffprobe-static when available; otherwise fall back to PATH.
  // ffprobe-static ships no linux/arm64 binary, so on the ARM server it hands
  // back a path that does not exist — check before trusting it.
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const mod = require('ffprobe-static');
    const p = mod?.path as string | undefined;
    ffprobePath = p && existsSync(p) ? p : 'ffprobe';
  } catch {
    ffprobePath = 'ffprobe';
  }
  return ffprobePath!;
}

interface FfprobeStream {
  codec_type?: string;
  codec_name?: string;
  duration?: string;
  width?: number;
  height?: number;
  r_frame_rate?: string;
  pix_fmt?: string;
}

interface FfprobeFormat {
  duration?: string;
  size?: string;
}

interface FfprobeOutput {
  streams?: FfprobeStream[];
  format?: FfprobeFormat;
}

function runFfprobe(filePath: string): Promise<FfprobeOutput> {
  return new Promise((resolve, reject) => {
    const proc = spawn(getFfprobePath(), [
      '-v', 'error',
      '-print_format', 'json',
      '-show_streams',
      '-show_format',
      filePath,
    ]);
    const chunks: Buffer[] = [];
    const errChunks: Buffer[] = [];
    proc.stdout.on('data', (b: Buffer) => chunks.push(b));
    proc.stderr.on('data', (b: Buffer) => errChunks.push(b));
    proc.on('error', reject);
    proc.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(`ffprobe exited ${code}: ${Buffer.concat(errChunks).toString('utf8')}`));
      }
      try {
        const json = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        resolve(json);
      } catch (err) {
        reject(err as Error);
      }
    });
  });
}

export interface VideoValidationResult {
  durationMs: number;
  width: number;
  height: number;
  framerate: number;
  hasAlpha: boolean;
  codec: string;
  fileSize: number;
}

export const MAX_VIDEO_BYTES = 8 * 1024 * 1024;
export const TARGET_DURATION_MS = 4000;
export const DURATION_TOLERANCE_MS = 200;

export async function validateGiftVideo(filePath: string): Promise<VideoValidationResult> {
  const stat = await fs.stat(filePath);
  if (stat.size > MAX_VIDEO_BYTES) {
    throw new Error(`Video exceeds ${MAX_VIDEO_BYTES} bytes (got ${stat.size})`);
  }
  const probe = await runFfprobe(filePath);
  const stream = probe.streams?.find((s) => s.codec_type === 'video');
  if (!stream) throw new Error('No video stream found');

  const durationSec =
    Number(stream.duration) || Number(probe.format?.duration) || 0;
  const durationMs = Math.round(durationSec * 1000);
  if (Math.abs(durationMs - TARGET_DURATION_MS) > DURATION_TOLERANCE_MS) {
    throw new Error(`Duration must be ${TARGET_DURATION_MS}ms ±${DURATION_TOLERANCE_MS}ms (got ${durationMs}ms)`);
  }
  const width = stream.width ?? 0;
  const height = stream.height ?? 0;
  if (width > 1080 || height > 1920) {
    throw new Error(`Resolution must be <= 1080x1920 (got ${width}x${height})`);
  }
  const parts = (stream.r_frame_rate ?? '0/1').split('/').map(Number);
  const num = parts[0] ?? 0;
  const den = parts[1] ?? 1;
  const framerate = den ? num / den : 0;
  if (framerate < 29.9) {
    throw new Error(`Minimum framerate is 30fps (got ${framerate.toFixed(2)})`);
  }
  const pixFmt = stream.pix_fmt ?? '';
  const hasAlpha = /yuva|argb|rgba|bgra|ya/i.test(pixFmt);

  return {
    durationMs,
    width,
    height,
    framerate: Math.round(framerate * 100) / 100,
    hasAlpha,
    codec: stream.codec_name ?? 'unknown',
    fileSize: stat.size,
  };
}

/** Upper bound for a dashboard-uploaded gift clip. */
export const MAX_DASHBOARD_VIDEO_BYTES = 20 * 1024 * 1024;
export const MAX_DASHBOARD_DURATION_MS = 15000;
export const MIN_DASHBOARD_DURATION_MS = 500;

/**
 * Lenient probe for the admin-dashboard upload path. The owner uploads clips of
 * whatever length they like, so we do NOT enforce the strict 4s window used by
 * the canonical gift module — we only reject what the client genuinely cannot
 * play, and return the real duration so `animationMs` can be stored instead of
 * the 3000ms schema default (which used to cut long clips off mid-play).
 */
export async function probeGiftVideo(filePath: string): Promise<VideoValidationResult> {
  const stat = await fs.stat(filePath);
  if (stat.size > MAX_DASHBOARD_VIDEO_BYTES) {
    throw new Error(`حجم الفيديو أكبر من ${Math.round(MAX_DASHBOARD_VIDEO_BYTES / 1024 / 1024)} ميجابايت`);
  }
  const probe = await runFfprobe(filePath);
  const stream = probe.streams?.find((s) => s.codec_type === 'video');
  if (!stream) throw new Error('الملف لا يحتوي على مسار فيديو');

  const durationSec = Number(stream.duration) || Number(probe.format?.duration) || 0;
  const durationMs = Math.round(durationSec * 1000);
  if (durationMs < MIN_DASHBOARD_DURATION_MS || durationMs > MAX_DASHBOARD_DURATION_MS) {
    throw new Error(`مدة الفيديو يجب أن تكون بين 0.5 و ${MAX_DASHBOARD_DURATION_MS / 1000} ثانية (المدة الحالية ${(durationMs / 1000).toFixed(1)} ث)`);
  }
  const width = stream.width ?? 0;
  const height = stream.height ?? 0;
  if (width > 1080 || height > 1920) {
    throw new Error(`أبعاد الفيديو يجب ألا تتجاوز 1080x1920 (الحالي ${width}x${height})`);
  }
  const parts = (stream.r_frame_rate ?? '0/1').split('/').map(Number);
  const num = parts[0] ?? 0;
  const den = parts[1] ?? 1;
  const framerate = den ? num / den : 0;
  const pixFmt = stream.pix_fmt ?? '';

  return {
    durationMs,
    width,
    height,
    framerate: Math.round(framerate * 100) / 100,
    hasAlpha: /yuva|argb|rgba|bgra|ya/i.test(pixFmt),
    codec: stream.codec_name ?? 'unknown',
    fileSize: stat.size,
  };
}

/** Codecs every client (Android ExoPlayer, iOS, Chrome) can decode. */
const WEB_SAFE_CODECS = new Set(['h264', 'vp8', 'vp9', 'av1']);

export function needsTranscode(codec: string): boolean {
  return !WEB_SAFE_CODECS.has(codec.toLowerCase());
}

function getFfmpegPath(): string {
  return process.env.FFMPEG_PATH?.trim() || 'ffmpeg';
}

/**
 * Re-encodes a clip to H.264 in place.
 *
 * iPhones record in HEVC/H.265 by default, and the owner uploads straight from
 * the phone. Chrome cannot decode HEVC at all and plenty of Android decoders
 * choke on it, so the clip silently failed to play and the room fell back to the
 * gift's still icon. Everything that is not already web-safe gets converted.
 */
export async function transcodeToH264(filePath: string): Promise<void> {
  const outPath = `${filePath}.h264.mp4`;
  await new Promise<void>((resolve, reject) => {
    const proc = spawn(getFfmpegPath(), [
      '-y', '-loglevel', 'error',
      '-i', filePath,
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-preset', 'veryfast',
      '-crf', '24',
      '-movflags', '+faststart',
      '-c:a', 'aac',
      outPath,
    ]);
    const errChunks: Buffer[] = [];
    proc.stderr.on('data', (b: Buffer) => errChunks.push(b));
    proc.on('error', reject);
    proc.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(`ffmpeg exited ${code}: ${Buffer.concat(errChunks).toString('utf8')}`));
      }
      resolve();
    });
  });
  await fs.rename(outPath, filePath);
}

export function isAllowedVideoExtension(filename: string): boolean {
  const ext = path.extname(filename).toLowerCase();
  return ext === '.mp4' || ext === '.webm' || ext === '.mov';
}
