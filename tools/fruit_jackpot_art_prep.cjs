const fs=require('node:fs/promises');
const path=require('node:path');
const sharp=require('../backend/node_modules/sharp');
async function main(){
 const root=path.resolve(__dirname,'../app/assets/images');
 const records=JSON.parse(await fs.readFile(path.join(__dirname,'fruit_jackpot_art.json'),'utf8'));
 const cards=[];
 for(const [i,{name,path:source}] of records.entries()){
  const wide=name==='card_fruit_jackpot',bg=name==='background';
  const dimensions=bg?[720,1600]:wide?[1024,512]:[512,512];
  const meta=await sharp(source).metadata();if(!wide&&!bg&&!meta.hasAlpha)throw Error(`${name} lacks alpha`);
  const dest=path.join(root,wide?'cards/card_fruit_jackpot.png':`games/fruit_jackpot/${name}.png`);
  await fs.mkdir(path.dirname(dest),{recursive:true});
  let output;
  for(const colours of [256,128,64]){
   output=await sharp(source).resize(...dimensions,{fit:bg||wide?'cover':'contain',background:{r:0,g:0,b:0,alpha:0}}).png({palette:true,colours,compressionLevel:9,effort:10}).toBuffer();
   if(output.length<200*1024)break;
  }
  await fs.writeFile(dest,output);
  console.log(`${name}: ${dimensions.join('x')} ${output.length} bytes`);
  cards.push({input:await sharp(output).resize(192,192,{fit:'contain',background:'#3b176b'}).png().toBuffer(),left:i%4*192,top:Math.floor(i/4)*192});
 }
 const output=path.resolve(__dirname,'../app/build/fruit-jackpot-art-review.png');await fs.mkdir(path.dirname(output),{recursive:true});
 await sharp({create:{width:768,height:Math.ceil(records.length/4)*192,channels:4,background:'#3b176b'}}).composite(cards).png().toFile(output);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
