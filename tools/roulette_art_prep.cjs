const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('../backend/node_modules/sharp');

// Normalizes the Codex-generated ROULETTE artwork (ROULETTE_ARTWORK_BRIEF.md).
//   node tools/roulette_art_prep.cjs <dir with background.png, watermelon.png, …>
// Cutouts: 512×512 with ~8% transparent padding. Background 720×1280, card 1024×512.
// Every file is validated and a review sheet written before anything is replaced.
const source = process.argv[2];
if (!source) throw new Error('usage: node tools/roulette_art_prep.cjs <source dir>');
const names = ['background', 'turret', 'chip_100', 'chip_500', 'chip_1k', 'chip_5k', 'chip_10k', 'trophy', 'logo', 'card'];
const clear = {r: 0, g: 0, b: 0, alpha: 0};
const limit = 250000;

async function bounds(input, name) {
  const {data, info} = await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  let left = info.width, top = info.height, right = -1, bottom = -1, empty = 0;
  for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
    const a = data[(y * info.width + x) * info.channels + info.channels - 1];
    if (!a) empty++;
    if (a > 8) {
      left = Math.min(left, x); top = Math.min(top, y);
      right = Math.max(right, x); bottom = Math.max(bottom, y);
    }
  }
  if (empty < info.width * info.height * 0.05 || right < left)
    throw new Error(name + ' needs real transparency and visible artwork');
  return {left, top, width: right - left + 1, height: bottom - top + 1};
}

async function prepare(name) {
  const input = path.join(source, name + '.png');
  const cutout = !['background', 'card'].includes(name);
  const size = name === 'background' ? [720, 1280] : name === 'card' ? [1024, 512] : [512, 512];
  let pixels;
  if (cutout) {
    const art = await sharp(input).extract(await bounds(input, name))
      .resize(430, 430, {fit: 'inside'}).png().toBuffer();
    pixels = await sharp({create: {width: 512, height: 512, channels: 4, background: clear}})
      .composite([{input: art, gravity: 'centre'}]).png().toBuffer();
  } else {
    pixels = await sharp(input).resize(...size, {fit: 'cover', position: 'centre'})
      .flatten({background: '#111634'}).png().toBuffer();
  }
  let output = await sharp(pixels).png({compressionLevel: 9, effort: 10}).toBuffer();
  if (output.length > limit) for (const colours of [256, 192, 128, 96, 64]) {
    output = await sharp(pixels).png({palette: true, colours, dither: 0.7, compressionLevel: 9, effort: 10}).toBuffer();
    if (output.length <= limit) break;
  }
  if (output.length > limit) throw new Error(name + ' exceeds 250 KB');
  return {name, output, size, cutout};
}

async function reviewSheet(assets) {
  const tiles = [];
  for (const [i, a] of assets.entries()) {
    const left = (i % 4) * 256, top = Math.floor(i / 4) * 290;
    tiles.push({input: await sharp(a.output).resize(240, 240, {fit: 'contain', background: clear}).png().toBuffer(), left: left + 8, top: top + 8});
    const label = '<svg width="240" height="30"><style>text{font-family:Arial,sans-serif;fill:#fff3bf}</style>' +
      '<text x="0" y="20" font-size="15">' + a.name + ' · ' + (a.output.length / 1000).toFixed(0) + ' KB</text></svg>';
    tiles.push({input: Buffer.from(label), left: left + 8, top: top + 252});
  }
  const rows = Math.ceil(assets.length / 4);
  return sharp({create: {width: 1024, height: rows * 290, channels: 4, background: '#260d55'}})
    .composite(tiles).png({compressionLevel: 9}).toBuffer();
}

async function main() {
  const assets = [];
  for (const name of names) assets.push(await prepare(name));
  const review = await reviewSheet(assets);
  const root = path.resolve(__dirname, '../app/assets/images');
  await fs.mkdir(path.join(root, 'games/roulette'), {recursive: true});
  for (const a of assets) {
    const dest = path.join(root, a.name === 'card' ? 'cards/card_roulette.png' : 'games/roulette/' + a.name + '.png');
    await fs.writeFile(dest, a.output);
    console.log(a.name + ': ' + a.size.join('x') + ', ' + a.output.length + ' bytes');
  }
  const contact = path.resolve(__dirname, '../app/build/roulette-art-review.png');
  await fs.mkdir(path.dirname(contact), {recursive: true});
  await fs.writeFile(contact, review);
  console.log('Review sheet: ' + contact);
}
main().catch(error => {console.error(error); process.exitCode = 1;});
