// Reference dumps of the HTML world generator for the Godot port.
//   node legacy/tests/worldref.js <seed> <outDir>     (run legacy/build.sh first)
// Runs genWorld() exactly as a new logistics game does (map size "m", board lattice) and writes
// the intermediate arrays the C++ generator must reproduce bit for bit:
//   low.f32, H.f32, Mf.f32 (heights), land.u8, own_grow.i8 (states after region growing, before the lattice),
//   own.i8 (final), sqd.u8 / sql.i16 (board lattice), meta.json (sizes, threshold, seeds, countries).
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');const D=__dirname;
const seed=+(process.argv[2]||777),out=process.argv[3]||path.join(D,'ref',String(seed));
(async()=>{fs.mkdirSync(out,{recursive:true});
const b=await chromium.launch();const p=await b.newPage();p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
const r=await p.evaluate(async(seed)=>{
  G.mapSize="m";setWorldScale("board");G.genN=Math.max(12,Math.round(30*WX*WZ/384));
  // the same generator with hooks that keep the intermediate arrays
  let src=genWorld.toString();
  const hook=(after,code)=>{if(!src.includes(after))throw new Error("hook not found: "+after.slice(0,40));src=src.replace(after,after+code)};
  src=src.replace("const sc=[MW,MH],","window.__D={};const sc=[MW,MH],");
  src=src.replace("const sample=[];","__D.low=low;__D.H=H;__D.Mf=Mf;const sample=[];");
  hook("for(let i=0;i<H.length;i++){if(H[i]>T){land[i]=1;landCount++}}",";__D.land=land;__D.T=T;__D.landCount=landCount;");
  hook("if(nbMask)for(let i=0;i<own.length;i++)if(nbMask[i])own[i]=NEU+nbMask[i];",";__D.ownGrow=own.slice();__D.seeds=seeds.map(s=>({x:s.x,y:s.y,m:s.m,off:s.off}));");
  const f=new Function("mulberry","makePerlin","return "+src.replace(/^async function genWorld/,"async function"))(mulberry,makePerlin);
  window.__D=null;const w=await f(SEED=seed,G.genN,()=>{},{big:true,tri:true});
  for(const k of ["low","H","Mf","land","ownGrow"])if(!__D[k])throw new Error("missing "+k);if(!SQD)throw new Error("no SQD");
  const b64=a=>{const u=new Uint8Array(a.buffer,a.byteOffset,a.byteLength);let s="";for(let i=0;i<u.length;i+=0x8000)s+=String.fromCharCode.apply(null,u.subarray(i,i+0x8000));return btoa(s)};
  return{MW,MH,WX,WZ,TRI_S,N:G.genN,T:__D.T,landCount:__D.landCount,seeds:__D.seeds,countries:w.countries,
    low:b64(__D.low),H:b64(__D.H),Mf:b64(__D.Mf),land:b64(__D.land),ownGrow:b64(__D.ownGrow),own:b64(w.own),sqd:b64(SQD),sql:b64(SQL)}},seed);
for(const [k,ext] of [["low","f32"],["H","f32"],["Mf","f32"],["land","u8"],["ownGrow","i8"],["own","i8"],["sqd","u8"],["sql","i16"]]){fs.writeFileSync(path.join(out,k+"."+ext),Buffer.from(r[k],'base64'));delete r[k]}
fs.writeFileSync(path.join(out,'meta.json'),JSON.stringify(r));
console.log(out,"MW",r.MW,"MH",r.MH,"N",r.N,"T",r.T,"land",r.landCount,"countries",r.countries.length,errs.join(" | "));await b.close()})();
