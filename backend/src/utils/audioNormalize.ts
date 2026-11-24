import { spawn } from 'child_process';
import fs from 'fs/promises';
import path from 'path';

// M1: phones hand over audio in odd containers (3gp/amr/wma), or as a content://
// file with no extension at all. Anything that is not already a format every
// phone plays natively is converted to MP3 on the server (ffmpeg is on prod), so
// playback never depends on the listener's codecs. A file ffmpeg cannot read as
// audio is rejected instead of being stored as a dead track.

const NATIVE = new Set(['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.flac']);

const ffmpegPath = () => process.env.FFMPEG_PATH?.trim() || 'ffmpeg';

function run(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(ffmpegPath(), args);
    const err: Buffer[] = [];
    proc.stderr.on('data', (b: Buffer) => err.push(b));
    proc.on('error', reject);
    proc.on('close', (code) =>
      code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code}: ${Buffer.concat(err).toString('utf8').slice(0, 300)}`)));
  });
}

export function needsAudioConversion(ext: string): boolean {
  return !NATIVE.has(ext.toLowerCase());
}

/**
 * Returns the (possibly new) absolute path + filename of a playable audio file.
 * Throws when the file is not audio at all. A native format that ffmpeg cannot
 * convert is left untouched (best effort); a non-native one that fails is rejected.
 */
export async function normalizeAudioUpload(file: string): Promise<{ path: string; filename: string; size: number; converted: boolean }> {
  const ext = path.extname(file).toLowerCase();
  if (!needsAudioConversion(ext)) {
    return { path: file, filename: path.basename(file), size: (await fs.stat(file)).size, converted: false };
  }
  const out = `${file.slice(0, file.length - ext.length)}.mp3`;
  const pending = `${out}.pending.mp3`;
  try {
    await run(['-y', '-loglevel', 'error', '-i', file, '-vn', '-map', '0:a:0', '-c:a', 'libmp3lame', '-q:a', '4', '-ar', '44100', pending]);
    await fs.rename(pending, out);
    if (out !== file) await fs.unlink(file).catch(() => {});
    return { path: out, filename: path.basename(out), size: (await fs.stat(out)).size, converted: true };
  } catch (e) {
    await fs.unlink(pending).catch(() => {});
    throw e;
  }
}
