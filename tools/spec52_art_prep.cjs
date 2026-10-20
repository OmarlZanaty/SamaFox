// SPEC52 art prep — room emoji + rocket/PK/handshake (docs/spec52/ART_BRIEF.md).
//   node tools/spec52_art_prep.cjs <dir with emoji_<id>.png / rocket.png …>
// Emoji → app/assets/images/emoji/<id>.webp (256×256, transparent, ~15–30 KB).
// Others → app/assets/images/spec52/<name>.png (512 max side).
// A *_left emoji with no source is made by mirroring its *_right twin.
// Green (#00FF00) chroma backgrounds are keyed out; real alpha is kept.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('../backend/node_modules/sharp');

const src = process.argv[2];
if (!src) throw new Error('usage: node tools/spec52_art_prep.cjs <source dir>');
const root = path.join(__dirname, '..', 'app', 'assets', 'images');

async function keyGreen(input) {
  const { data, info } = await sharp(input).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let keyed = 0;
  for (let i = 0; i < data.length; i += 4) {
    const r = data[i], g = data[i + 1], b = data[i + 2];
    if (g > 180 && r < 120 && b < 120) {
      data[i + 3] = 0;
      keyed++;
    }
  }
  return { buf: await sharp(data, { raw: info }).png().toBuffer(), keyed };
}

async function prep(file, outFile, size, mirror = false, webp = true) {
  const { buf } = await keyGreen(file);
  let img = sharp(buf).trim({ threshold: 1 });
  if (mirror) img = img.flop();
  const trimmed = await img.png().toBuffer();
  const out = sharp(trimmed).resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } });
  await fs.mkdir(path.dirname(outFile), { recursive: true });
  if (webp) await out.webp({ quality: 82, alphaQuality: 90, effort: 5 }).toFile(outFile);
  else await out.png({ compressionLevel: 9, palette: true }).toFile(outFile);
  const st = await fs.stat(outFile);
  console.log(`${path.basename(outFile)}  ${(st.size / 1024).toFixed(1)} KB`);
}

(async () => {
  const files = (await fs.readdir(src)).filter((f) => f.toLowerCase().endsWith('.png'));
  const have = new Set(files.map((f) => f.replace(/\.png$/i, '')));
  for (const f of files) {
    const base = f.replace(/\.png$/i, '');
    const input = path.join(src, f);
    if (base.startsWith('emoji_')) {
      const id = base.slice('emoji_'.length);
      await prep(input, path.join(root, 'emoji', `${id}.webp`), 256);
      if (id.endsWith('_right') && !have.has(`emoji_${id.replace(/_right$/, '_left')}`)) {
        await prep(input, path.join(root, 'emoji', `${id.replace(/_right$/, '_left')}.webp`), 256, true);
      }
    } else {
      await prep(input, path.join(root, 'spec52', `${base}.png`), 512, false, false);
    }
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
