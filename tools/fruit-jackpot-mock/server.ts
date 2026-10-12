/** Dev-only in-memory harness. No production accounts or coins. */
import crypto from 'crypto';
import path from 'path';
const express = require(path.join(__dirname,'../../backend/node_modules/express'));
import {BET_STEPS,PAYLINES,PAYTABLE,JACKPOT_MULTIPLIER,MAX_MULTIPLIER,MATH_VERSION,TARGET_RTP,RngStream,computeSpin,validBet,SYMBOLS,weights,Symbol} from '../../backend/src/services/fruitJackpot.math';
const app=express();app.use(express.json());
app.use((q:any,r:any,next:any)=>{r.header('Access-Control-Allow-Origin','*');r.header('Access-Control-Allow-Headers','*');r.header('Access-Control-Allow-Methods','*');if(q.method==='OPTIONS')return r.sendStatus(204);next();});
let balance=500000,nonce=0,roundCount=0,scene='auto',clientSeed='preview',serverSeed=crypto.randomBytes(32).toString('hex');
const history:any[]=[],requests=new Map<string,any>();
const hash=(s:string)=>crypto.createHash('sha256').update(s).digest('hex');
const fair=()=>({serverSeedHash:hash(serverSeed),clientSeed,nonce});
const layout={betSteps:BET_STEPS,paylines:PAYLINES,paytable:PAYTABLE,jackpotMultiplier:JACKPOT_MULTIPLIER,maxMultiplier:MAX_MULTIPLIER,mathVersion:MATH_VERSION,mathRtp:TARGET_RTP,minBet:100,maxBet:100000,enabled:true};
const cairo=new Intl.DateTimeFormat('en-CA',{timeZone:'Africa/Cairo',year:'numeric',month:'2-digit',day:'2-digit'});
function rank(){const now=new Date(),day=cairo.format(now);let lo=+now,hi=lo+27*3600000;while(hi-lo>1){const m=Math.floor((hi+lo)/2);if(cairo.format(new Date(m))===day)lo=m;else hi=m;}const totalWonToday=history.filter(r=>cairo.format(new Date(r.at))===day).reduce((s,r)=>s+r.spin.totalPrize,0);return {roundCount,totalWonToday,rank:totalWonToday>0?1:null,serverTime:now.toISOString(),resetAt:new Date(hi).toISOString()};}
const api='/api/v1/games/fruit-jackpot';
app.get(`${api}/state`,(_:any,r:any)=>r.json({success:true,balance,layout,history,fairness:fair(),...rank()}));
app.get(`${api}/rank`,(_:any,r:any)=>r.json({success:true,...rank()}));
app.get(`${api}/history`,(_:any,r:any)=>r.json({success:true,history}));
app.get(`${api}/fair`,(_:any,r:any)=>r.json({success:true,fairness:fair()}));
app.post(`${api}/seed`,(q:any,r:any)=>{if(typeof q.body?.clientSeed!=='string'||q.body.clientSeed.length<1||q.body.clientSeed.length>64)return r.status(400).json({success:false,code:'BAD_SEED'});clientSeed=q.body.clientSeed;r.json({success:true,fairness:fair()});});
app.post(`${api}/seed/rotate`,(_:any,r:any)=>{const revealed={serverSeed,...fair()};serverSeed=crypto.randomBytes(32).toString('hex');nonce=0;r.json({success:true,revealed,serverSeedHash:hash(serverSeed)});});
app.post(`${api}/verify`,(q:any,r:any)=>{try{const b=q.body; r.json({success:true,spin:{...computeSpin(new RngStream(b.serverSeed,b.clientSeed,b.nonce),b.betPerLine,b.activeLines),serverSeedHash:hash(b.serverSeed)}});}catch(_){r.status(400).json({success:false,code:'BAD_VERIFY'});}});
app.post(`${api}/spin`,(q:any,r:any)=>{
  const bet=q.body?.betPerLine,lines=q.body?.activeLines,key=q.headers['idempotency-key'];
  if(!validBet(bet,lines)||typeof key!=='string'||!key||key.length>128)return r.status(400).json({success:false,code:'BAD_BET'});
  const old=requests.get(key);if(old){if(old.spin.betPerLine!==bet)return r.status(409).json({success:false,code:'IDEMPOTENCY_KEY_REUSED'});return r.json({success:true,...old});}
  if(balance<bet)return r.status(400).json({success:false,code:'INSUFFICIENT'});
  const stream=new RngStream(serverSeed,clientSeed,nonce);
  // Forced scenes script the draw order: 9 cells, centre tile, 3 row badges, bonus pick.
  const cell=(s:Symbol)=>{const w=weights(),t=w.reduce((a,b)=>a+b,0),i=SYMBOLS.indexOf(s);return (w.slice(0,i).reduce((a,b)=>a+b,0)+w[i]!/2)/t;};
  const mixed:Symbol[]=['lemon','kiwi','plum','banana','raspberry','strawberry','kiwi','plum','lemon'];
  const boards:Record<string,[Symbol[],number]>={
    win:[['lemon','lemon','lemon',...mixed.slice(3)],.95],
    bonus:[['lemon','kiwi','plum','multiplier','multiplier','multiplier','kiwi','plum','lemon'],0],
    jackpot:[['cherry','cherry','cherry',...mixed.slice(3)],.9995],
    loss:[mixed,0],
  };
  const forced=boards[scene];scene='auto';
  const scripted=forced?[...forced[0].map(cell),forced[1],.5,.5,.5,.7]:null;let k=0;
  const spin=computeSpin({nextFloat:()=>scripted&&k<scripted.length?scripted[k++]!:stream.nextFloat()},bet,lines);
  balance+=spin.totalPrize-bet;
  const row={id:crypto.randomUUID(),at:new Date().toISOString(),roundNumber:++roundCount,balance,spin:{...spin,requestedPrize:spin.totalPrize,capped:false},...fair()};nonce++;
  history.unshift(row);history.splice(50);requests.set(key,row);setTimeout(()=>r.json({success:true,...row}),200);
});
app.get('/scene/:name',(q:any,r:any)=>{scene=q.params.name;r.json({scene});});
app.listen(3101,'127.0.0.1',()=>console.log('Fruit Jackpot preview http://localhost:3101'));
