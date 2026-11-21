const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
for(const seed of (process.argv[2]||"777,303").split(",").map(Number)){
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(s=>{SET.res=600;SEED=s},seed);
const t0=Date.now();await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');const gen=Date.now()-t0;
const r=await p.evaluate(()=>{const T=BOARD.towns.filter(t=>t.type!=="vil");const per=G.C.map(c=>T.filter(t=>t.cid===c.id).length).sort((a,b)=>a-b);
  const border=T.filter(t=>{for(const s of [1.2])for(const [dx,dz] of [[1,0],[-1,0],[0,1],[0,-1]]){const w=bOwn(t.x+dx*BL.st*s,t.z+dz*BL.st*s);if(w>=0&&w!==t.cid)return true}return false}).map(t=>t.type+(t.extra?"*":"")+":"+t.name).join(" ");
  const F=PL.filter(q=>q.type!=="vil").map(q=>[q.type,firmsOf(q.id).length]);const avg=ty=>{const a=F.filter(f=>f[0]===ty).map(f=>f[1]);return a.length?(a.reduce((x,y)=>x+y,0)/a.length).toFixed(1)+"("+Math.min(...a)+"-"+Math.max(...a)+")":"-"};
  return{towns:T.length,countries:G.C.length,perCountry:per.join(","),border,firms:{cap:avg("cap"),big:avg("big"),city:avg("city"),town:avg("town")}}});
r.seed=seed;r.genMs=gen;r.errs=errs.slice(0,2);console.log(JSON.stringify(r));await p.close()}
await b.close()})();
