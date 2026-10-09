const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const sharp = require('../backend/node_modules/sharp');

// Built-in imagegen originals; an override directory may use semantic filenames.
const source = process.argv[2] || path.join(process.env.CODEX_HOME ||
  path.join(os.homedir(), '.codex'), 'generated_images/01a1170b-65dc-7191-9783-e91af6c83d37');
const files = {
  "background": "exec-8fb2d90b-b6f6-48dd-b2bb-2c8c43757831.png",
  "strawberry": "exec-058dbb9d-b60f-44ed-a514-d60caf330b83.png",
  "cherry": "exec-ebdbf8fa-faa4-44d3-aac9-2c75df503eb7.png",
  "orange": "exec-c997d7ee-2cc2-4b13-81f4-3278064d3c5b.png",
  "lemon": "exec-f00172eb-9278-4c75-a5fe-90f9a8682008.png",
  "watermelon": "exec-9eef4c51-6af0-476c-a5b2-49d6b567c008.png",
  "grapes": "exec-4ade5287-5f5f-4aed-9a8e-d786888e0fc9.png",
  "candy": "exec-5e48200f-e808-4c02-a3cb-ff5f91bf1a56.png",
  "diamond": "exec-47265b40-4341-4f1e-9d75-46e28eebd772.png",
  "wild": "exec-dc4f43a7-3883-434a-9e39-bd1c8283a597.png",
  "bonus": "exec-c7b584e0-e28b-490e-8bf4-288e01213b45.png",
  "jackpot": "exec-412341d6-f571-4de0-8fe1-35a45005e040.png",
  "logo": "exec-6f71845b-f6b1-4d00-99bd-6bb20f572bae.png",
  "bonus_chest": "exec-7426ee06-8297-4e48-90e4-e0f98253a2de.png",
  "bonus_open": "exec-0e3fecf7-a1f3-41e3-874e-d32999c699c2.png",
  "card_yummy": "exec-3995d273-af96-4b07-8101-6548b8792a45.png"
};
const clear = {r: 0, g: 0, b: 0, alpha: 0};
const limit = 250000;

async function bounds(input, name) {
  if (!(await sharp(input).metadata()).hasAlpha) throw new Error(name + ' lacks alpha');
  const {data, info} = await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  let left = info.width, top = info.height, right = -1, bottom = -1, empty = 0;
  for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
    const a = data[(y * info.width + x) * info.channels + info.channels - 1];
    if (!a) empty++;
    // Ignore near-invisible generated alpha specks when measuring the silhouette.
    if (a > 8) {
      left = Math.min(left, x); top = Math.min(top, y);
      right = Math.max(right, x); bottom = Math.max(bottom, y);
    }
  }
  if (empty < info.width * info.height * 0.05 || right < left)
    throw new Error(name + ' needs real transparency and visible artwork');
  return {left, top, width: right - left + 1, height: bottom - top + 1};
}

async function prepare(name, filename) {
  let input = path.join(source, name + '.png');
  try { await fs.access(input); } catch { input = path.join(source, filename); }
  const cutout = !['background', 'card_yummy'].includes(name);
  const size = name === 'background' ? [720, 1280] : name === 'card_yummy' ? [1024, 512] : [512, 512];
  let pixels;
  if (cutout) {
    // 430px art on 512px canvas: 41px (~8%) minimum transparent padding.
    const art = await sharp(input).extract(await bounds(input, name))
      .resize(430, 430, {fit: 'inside'}).png().toBuffer();
    pixels = await sharp({create: {width: 512, height: 512, channels: 4, background: clear}})
      .composite([{input: art, gravity: 'centre'}]).png().toBuffer();
  } else {
    pixels = await sharp(input).resize(...size, {fit: 'cover', position: 'centre'})
      .flatten({background: '#87ceeb'}).png().toBuffer();
  }
  let output = await sharp(pixels).png({compressionLevel: 9, effort: 10}).toBuffer();
  if (output.length > limit) for (const colours of [256, 192, 128, 96, 64]) {
    output = await sharp(pixels).png({palette: true, colours, dither: 0.7, compressionLevel: 9, effort: 10}).toBuffer();
    if (output.length <= limit) break;
  }
  if (output.length > limit) throw new Error(name + ' exceeds 250 KB');
  const meta = await sharp(output).metadata();
  if (meta.width !== size[0] || meta.height !== size[1]) throw new Error(name + ' invalid dimensions');
  if (cutout) {
    const b = await bounds(output, name);
    if (b.left < 40 || b.top < 40 || b.left + b.width > 472 || b.top + b.height > 472)
      throw new Error(name + ' invalid padding');
  }
  return {name, output, size, cutout};
}

async function reviewSheet(assets) {
  const tiles = [];
  for (const [i, a] of assets.entries()) {
    const left = (i % 4) * 256, top = Math.floor(i / 4) * 324;
    tiles.push({input: await sharp(a.output).resize(240, 240, {fit: 'contain', background: clear}).png().toBuffer(), left: left + 8, top: top + 8});
    tiles.push({input: await sharp(a.output).resize(60, 60, {fit: 'contain', background: clear}).png().toBuffer(), left: left + 8, top: top + 256});
    const label = '<svg width="176" height="60"><style>text{font-family:Arial,sans-serif;fill:#e4eeff}</style>' +
      '<text x="0" y="22" font-size="16">' + a.name + '</text><text x="0" y="44" font-size="12">' +
      a.size.join(' x ') + ' | ' + (a.output.length / 1000).toFixed(1) + ' KB</text></svg>';
    tiles.push({input: Buffer.from(label), left: left + 76, top: top + 256});
  }
  // Checkerboard previews plus dark 60px previews expose alpha and legibility.
  const checker = '<svg width="1024" height="1296"><defs><pattern id="c" width="32" height="32" patternUnits="userSpaceOnUse">' +
    '<rect width="32" height="32" fill="#dce9f1"/><path d="M0 0h16v16H0zM16 16h16v16H16z" fill="#b9cbd7"/>' +
    '</pattern></defs><rect width="1024" height="1296" fill="url(#c)"/>' +
    [0,1,2,3].map(r => '<rect x="0" y="' + (r * 324 + 252) + '" width="1024" height="72" fill="#172b45"/>').join('') + '</svg>';
  return sharp(Buffer.from(checker)).composite(tiles).png({compressionLevel: 9}).toBuffer();
}

async function main() {
  // Finish validation and contact sheet before replacing any project artwork.
  const assets = [];
  for (const [name, file] of Object.entries(files)) assets.push(await prepare(name, file));
  const review = await reviewSheet(assets);
  const root = path.resolve(__dirname, '../app/assets/images');
  for (const a of assets) {
    const dest = path.join(root, a.name === 'card_yummy' ? 'cards/card_yummy.png' : 'games/yummy/' + a.name + '.png');
    await fs.writeFile(dest, a.output);
    console.log(a.name + ': ' + a.size.join('x') + ', ' + a.output.length + ' bytes, transparent=' + a.cutout);
  }
  const contact = path.resolve(__dirname, '../app/build/yummy-art-review.png');
  await fs.mkdir(path.dirname(contact), {recursive: true});
  await fs.writeFile(contact, review);
  console.log('Review sheet: ' + review.length + ' bytes');
}
main().catch(error => {console.error(error); process.exitCode = 1;});
