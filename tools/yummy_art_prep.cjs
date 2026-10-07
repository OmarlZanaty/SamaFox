const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('../backend/node_modules/sharp');

const source = process.argv[2];
if (!source) throw new Error('Usage: node tools/yummy_art_prep.cjs <generated-image-directory>');
const files = {
  background: 'exec-4e8d6b74-8e0d-40eb-84ee-130ab4e27e8f.png',
  strawberry: 'exec-e8aee7b6-ab40-4eed-b168-e06281b2b9da.png',
  cherry: 'exec-8cc1d733-7fd4-4658-824e-1d485378bafe.png',
  orange: 'exec-dfc027ef-7785-4b74-b16e-030d1ceb8873.png',
  lemon: 'exec-7a014d04-86a1-4709-9191-e42379a4e950.png',
  watermelon: 'exec-3c8ae4d4-bfa1-42db-9e65-0e0a3c9cb215.png',
  grapes: 'exec-3c284964-526e-4727-b405-ed38d42ea4d3.png',
  candy: 'exec-f935798f-429a-4e03-9e0c-5df0de02c17e.png',
  diamond: 'exec-0031be76-2cea-480f-b72e-0c7958c7622c.png',
  wild: 'exec-bc082a69-95e4-4bd3-abc5-b053fe93794a.png',
  bonus: 'exec-ea88642a-a1ab-4d30-98d3-f82c8f8bc9ef.png',
  jackpot: 'exec-c7d792d1-62ca-4c1d-b0ae-b5b225cde37f.png',
  logo: 'exec-f57a463a-c9d6-41ae-bf85-fb847d257dcb.png',
  bonus_chest: 'exec-d8674ce2-a2b5-4e1b-a48e-fce9f7e0bce1.png',
  bonus_open: 'exec-b9f79ee9-a096-4660-8740-b9b872e20be5.png',
  card_yummy: 'exec-6dabd923-b522-422e-82a7-0609cb621833.png',
};
async function main() {
  const root = path.resolve(__dirname, '../app/assets/images');
  await fs.mkdir(path.join(root, 'games/yummy'), {recursive: true});
  for (const [name, filename] of Object.entries(files)) {
    const dimensions = name === 'background' ? [720, 1280] : name === 'card_yummy' ? [1024, 512] : [512, 512];
    const input = path.join(source, filename);
    const metadata = await sharp(input).metadata();
    if (!['background', 'card_yummy'].includes(name) && !metadata.hasAlpha) throw new Error(`${name} lacks alpha`);
    const destination = path.join(root, name === 'card_yummy' ? 'cards/card_yummy.png' : `games/yummy/${name}.png`);
    let output;
    for (const colours of [256, 128, 64]) {
      output = await sharp(input).resize(...dimensions, {fit: 'contain', background: {r: 0, g: 0, b: 0, alpha: 0}})
        .png({palette: true, colours, compressionLevel: 9, effort: 10}).toBuffer();
      if (output.length <= 150 * 1024) break;
    }
    await fs.writeFile(destination, output);
    console.log(`${name}: ${dimensions.join('×')}, ${output.length} bytes, alpha=${metadata.hasAlpha}`);
  }
  const cards = [];
  let index = 0;
  for (const name of Object.keys(files)) {
    const asset = path.join(root, name === 'card_yummy' ? 'cards/card_yummy.png' : `games/yummy/${name}.png`);
    cards.push({input: await sharp(asset).resize(192,192,{fit:'contain',background:'#d6efff'}).png().toBuffer(),left:(index%4)*192,top:Math.floor(index/4)*192});
    index++;
  }
  const contact = path.resolve(__dirname, '../app/build/yummy-art-review.png');
  await fs.mkdir(path.dirname(contact), {recursive:true});
  await sharp({create:{width:768,height:768,channels:4,background:'#d6efff'}}).composite(cards).png().toFile(contact);
}
main().catch(error => {console.error(error); process.exitCode=1;});
