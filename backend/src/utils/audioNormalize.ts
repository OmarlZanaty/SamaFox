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

// User-supplied input: a crafted file (huge declared duration, odd demuxer) must not
// pin an ffmpeg process and the HTTP request forever.
const FFMPEG_TIMEOUT_MS = 120_000;

function run(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(ffmpegPath(), args);
    const err: Buffer[] = [];
    let errLen = 0;
    const timer = setTimeout(() => proc.kill('SIGKILL'), FFMPEG_TIMEOUT_MS);
    proc.stderr.on('data', (b: Buffer) => { if (errLen < 4096) { err.push(b); errLen += b.length; } });
    proc.on('error', (e) => { clearTimeout(timer); reject(e); });
    proc.on('close', (code, signal) => {
      clearTimeout(timer);
      code === 0 ? resolve() : reject(new Error(`ffmpeg exited ${code ?? signal}: ${Buffer.concat(err).toString('utf8').slice(0, 300)}`));
    });
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
    // protocol_whitelist: an uploaded HLS/concat playlist must not make ffmpeg fetch URLs (SSRF).
    await run(['-y', '-loglevel', 'error', '-protocol_whitelist', 'file', '-i', file, '-vn', '-map', '0:a:0', '-c:a', 'libmp3lame', '-q:a', '4', '-ar', '44100', pending]);
    await fs.rename(pending, out);
    if (out !== file) await fs.unlink(file).catch(() => {});
    return { path: out, filename: path.basename(out), size: (await fs.stat(out)).size, converted: true };
  } catch (e) {
    await fs.unlink(pending).catch(() => {});
    throw e;
  }
}
