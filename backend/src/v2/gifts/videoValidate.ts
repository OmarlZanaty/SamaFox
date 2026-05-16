import { spawn } from 'child_process';
import fs from 'fs/promises';
import path from 'path';

let ffprobePath: string | null = null;

function getFfprobePath(): string {
  if (ffprobePath) return ffprobePath;
  // Use ffprobe-static when available; otherwise fall back to PATH.
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const mod = require('ffprobe-static');
    ffprobePath = (mod?.path as string) || 'ffprobe';
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

export function isAllowedVideoExtension(filename: string): boolean {
  const ext = path.extname(filename).toLowerCase();
  return ext === '.mp4' || ext === '.webm' || ext === '.mov';
}
