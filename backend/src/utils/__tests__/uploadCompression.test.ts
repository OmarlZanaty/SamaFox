import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import sharp from 'sharp';
sharp.cache(false);
import { optimizeUpload } from '../mediaOptimize';
import { localVideoPath } from '../videoPosterBackfill';

test('large transparent upload is capped at 1024 and retains alpha', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'upload-compress-'));
  try {
    const file = path.join(dir, 'art.png');
    await sharp({ create: { width: 2048, height: 1024, channels: 4, background: { r: 10, g: 20, b: 30, alpha: 0.4 } } }).png().toFile(file);
    const result = await optimizeUpload(file, { resizeTo: 1600 });
    const meta = await sharp(result.path).metadata();
    assert.equal(meta.width, 1024); assert.equal(meta.height, 512); assert.equal(meta.hasAlpha, true);
  } finally { await fs.rm(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); }
});
test('GIF and animated WebP upload bytes remain untouched', async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'upload-animation-'));
  try {
    // Two one-pixel frames, red and green.
    const header = Buffer.from('47494638396101000100800000ff000000ff0021ff0b4e45545343415045322e300301000000', 'hex');
    const frame = Buffer.from('21f904000a0000002c0000000001000100000202440100', 'hex');
    const second = Buffer.from('21f904000a0000002c00000000010001000002024c0100', 'hex');
    const gif = path.join(dir, 'animation.gif');
    await fs.writeFile(gif, Buffer.concat([header, frame, second, Buffer.from([0x3b])]));
    const webp = path.join(dir, 'animation.webp');
    await sharp(gif, { animated: true }).webp().toFile(webp);
    assert.equal((await sharp(webp, { animated: true }).metadata()).pages, 2);
    for (const file of [gif, webp]) {
      const before = await fs.readFile(file);
      const result = await optimizeUpload(file);
      assert.equal(result.changed, false); assert.equal(result.path, file);
      assert.deepEqual(await fs.readFile(file), before);
    }
  } finally { await fs.rm(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); }
});
test('poster backfill accepts local video paths and rejects other assets or traversal', () => {
  const root = path.resolve('uploads');
  assert.equal(localVideoPath('https://example.test/uploads/movie.mp4?v=1', root), path.join(root, 'movie.mp4'));
  assert.equal(localVideoPath('/uploads/photo.png', root), null);
  assert.equal(localVideoPath('/other/movie.mp4', root), null);
  assert.equal(localVideoPath('/uploads/..%2Fsecret.mp4', root), null);
});
