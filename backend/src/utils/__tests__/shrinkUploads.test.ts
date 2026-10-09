import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import os from 'os';
import path from 'path';
import sharp from 'sharp';
import { planShrink, shrinkInPlace, targetSide, uploadName } from '../shrinkUploads';

test('caps avatars at 512 and everything else at 1600', () => {
  assert.equal(targetSide({ width: 3456, height: 3456 }, true), 512);
  assert.equal(targetSide({ width: 3840, height: 2160 }, false), 1600);
  assert.equal(targetSide({ width: 1080, height: 2400 }, false), 1600);
  assert.equal(targetSide({ width: 512, height: 512 }, true), null);
  assert.equal(targetSide({ width: 1600, height: 900 }, false), null);
  assert.equal(targetSide({ width: 2000, height: 2000, pages: 12 }, false), null, 'animated WebP is left alone');
  assert.equal(targetSide({}, false), null);
});

test('finds the file name in an upload URL', () => {
  assert.equal(uploadName('https://samafox.almobarmg.com/uploads/upload-1-2.jpg'), 'upload-1-2.jpg');
  assert.equal(uploadName('http://46.224.129.250:3000/uploads/upload-3.png?v=2'), 'upload-3.png');
  assert.equal(uploadName('https://example.com/avatar.jpg'), null);
  assert.equal(uploadName(null), null);
});

test('shrinks in place: same name, same format, smaller', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shrink-'));
  const big = { create: { width: 2400, height: 1200, channels: 3 as const, background: '#884422' } };
  await sharp(big).jpeg().toFile(path.join(dir, 'upload-big.jpg'));
  await sharp(big).png().toFile(path.join(dir, 'upload-avatar.png'));
  await sharp({ create: { width: 300, height: 300, channels: 3, background: '#000000' } })
    .jpeg()
    .toFile(path.join(dir, 'upload-small.jpg'));
  fs.writeFileSync(path.join(dir, 'upload-clip.mp4'), 'not an image');

  const plans = await planShrink(dir, new Set(['upload-avatar.png']));
  assert.deepEqual(plans.map((p) => [path.basename(p.file), p.maxSide]).sort(), [
    ['upload-avatar.png', 512],
    ['upload-big.jpg', 1600],
  ]);
  for (const p of plans) await shrinkInPlace(p);

  const jpg = await sharp(path.join(dir, 'upload-big.jpg')).metadata();
  assert.equal(jpg.format, 'jpeg');
  assert.deepEqual([jpg.width, jpg.height], [1600, 800]);
  const png = await sharp(path.join(dir, 'upload-avatar.png')).metadata();
  assert.equal(png.format, 'png');
  assert.deepEqual([png.width, png.height], [512, 256]);
  assert.deepEqual(
    fs.readdirSync(dir).sort(),
    ['upload-avatar.png', 'upload-big.jpg', 'upload-clip.mp4', 'upload-small.jpg'],
    'no temp files left',
  );
});
