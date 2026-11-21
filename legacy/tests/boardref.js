// Reference dump of the board (towns, roads, railways, ports, checkpoints) for the Godot port.
//   node legacy/tests/boardref.js <seed> <outDir>     (run legacy/build.sh first)
// Starts a normal logistics game (map size "m") and, before the headquarters is picked, writes:
//   board.json  - state populations/areas (input of the town generator) and the board result:
//                 towns, roads (level + polyline), railways, checkpoints
//   bits.u8 / rbits.u8 (road / rail graph: 8 direction bits per lattice node), comp.i32 (land components)
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');const D=__dirname;
const seed=+(process.argv[2]||777),out=process.argv[3]||path.join(D,'ref',String(seed));
(async()=>{fs.mkdirSync(out,{recursive:true});
const b=await chromium.launch();const p=await b.newPage();p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
await p.evaluate(s=>{SET.res=600;SEED=s;SET.roadGab=false},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
const r=await p.evaluate(()=>{
  const b64=a=>{const u=new Uint8Array(a.buffer,a.byteOffset,a.byteLength);let s="";for(let i=0;i<u.length;i+=0x8000)s+=String.fromCharCode.apply(null,u.subarray(i,i+0x8000));return btoa(s)};
  const f6=v=>Math.round(v*1e6)/1e6;
  return{seed:SEED,mapSize:G.mapSize,nx:BL.nx,nz:BL.nz,
    states:G.C.map(c=>({pop:c.pop,area:c.geo.area,capName:c.capName,name:c.name,full:c.full,color:c.color,dev:c.dev,gdp:c.gdp,stability:c.stability,infl:c.infl,unemp:c.unemp,tech:c.tech,corr:c.corr,mil:c.mil,leader:c.leader.name,age:c.leader.age,ideol:c.ide.id,trait:c.trait.id,laws:[...c.laws],deposit:c.res.deposit,electionIn:c.electionIn,treasury:c.treasury,debt:c.debt})),
    towns:BOARD.towns.map(t=>({x:t.x,z:t.z,node:t.node,type:t.type,pop:t.pop,cid:t.cid,name:t.name,port:!!t.port,wc:t.wc||null,airOv:!!t.airOv,portOv:t.portOv??null,extra:!!t.extra})),
    hw:LOG.hw.map(h=>({lv:h.lv,p:Array.from(h.p)})),rail:LOG.rail.map(h=>Array.from(h.p)),
    cps:BOARD.cps.map(c=>({x:c.x,z:c.z,a:c.a,b:c.b,rail:c.rail})),
    bits:b64(BOARD.bits),rbits:b64(BOARD.rbits),comp:b64(BOARD.comp)}});
for(const [k,ext] of [["bits","u8"],["rbits","u8"],["comp","i32"]]){fs.writeFileSync(path.join(out,k+"."+ext),Buffer.from(r[k],'base64'));delete r[k]}
fs.writeFileSync(path.join(out,'board.json'),JSON.stringify(r));
console.log(out,"towns",r.towns.length,"roads",r.hw.length,"rail",r.rail.length,"checkpoints",r.cps.length,errs.join(" | "));await b.close()})();
