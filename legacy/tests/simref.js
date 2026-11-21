// Reference run of the company simulation, day by day, for the Godot port (godot/tests/test_sim.gd).
//   node legacy/tests/simref.js <outFile> [days] [seed…]     (run legacy/build.sh first)
// Deterministic: the game's RNG is seeded by the world seed; incidents, monthly events/tenders and the postal
// service are switched off (not ported yet); Math.pow is replaced by the correctly rounded one of crmath.js
// (the Godot version uses the same, see native/src/core/crmath.h). Time stands still (speed 0) and every
// day runs 8 frames (G.pfr = 0, 1/8 … 7/8; coFrame) and then dayTick().
// Policy each morning: the best-paying single-leg orders that the company can do on time are dispatched.
// Scenarios: "start" — the company as it starts; "fleet" — more vehicles and drivers, tier 2 and a
// dispatcher (CTO), so returns, the dispatcher, wages and managers are covered too; "abroad" — tier 4:
// orders across the continent (border checkpoints, customs) and trains.
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');const D=__dirname;
const out=process.argv[2]||path.join(D,'ref','sim.json'),days=+(process.argv[3]||150),seeds=process.argv.slice(4).map(Number);if(!seeds.length)seeds.push(777,303);
const cr=fs.readFileSync(path.join(D,'crmath.js'),'utf8');
(async()=>{const b=await chromium.launch();const res={days,runs:[]};
for(const seed of seeds)for(const sc of ["start","fleet","abroad"]){
const p=await b.newPage();p.setDefaultTimeout(1200000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
await p.addScriptTag({content:cr});
await p.evaluate(s=>{Math.pow=CRMATH.pow;SET.res=600;SEED=s;SET.roadGab=false;
  /* before the game starts: frames run between the start and the first step, and incidents draw from R there */
  guard=function(n,f){f()}; /* errors must stop the run, not be swallowed */
  incDay=()=>{};incFrame=()=>{};coJobsDay=()=>{};coMonthEvents=()=>{};poDay=()=>{};poMonth=()=>{};
  const _sh=coSetHQ;coSetHQ=function(){const r=_sh.apply(this,arguments);setSpeed(0);return r}},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);
const r=await p.evaluate(([sc,days])=>{
  setSpeed(0);CO.lastFr=0;G.pfr=0;
  const dv=new DataView(new ArrayBuffer(8));const H=x=>{dv.setFloat64(0,+x,true);let s="";for(let i=0;i<8;i++)s+=dv.getUint8(i).toString(16).padStart(2,"0");return s};
  const SC={fleet:{cash:250000,tier:2,staff:{driver:8},veh:["ltruck","ltruck","van","van","van","truck","truck"]},
    abroad:{cash:2e6,tier:4,staff:{driver:12,rail:6},veh:["truck","truck","truck","rtrain","reefer","ltruck","van","train","train"]}}[sc];
  if(SC){CO.cash=SC.cash;CO.tier=SC.tier;Object.assign(CO.staff,SC.staff);
    for(const t of SC.veh)CO.veh.push({id:CO.uid++,t,loc:CO.hq,st:"idle",cond:100,km:0});
    CO.mgr.cto={...CO.cand.cto[0]};delete CO.cand.cto;CO.auto=true}
  const policy=()=>{let n=0;for(const k of CO.board.slice().sort((a,b)=>b.pay-a.pay)){if(k.legs&&k.legs.length>1)continue;const P=coPlan(k);if(P.ok&&!P.late){coDispatch(k,P,true);n++}}return n};
  const rec=[];
  for(let d=0;d<days&&!G.over;d++){const sent=policy();
    for(let f=0;f<8;f++){G.pfr=f/8;coFrame()}
    dayTick();
    rec.push({day:G.day,sent,cash:H(CO.cash),rating:H(CO.rating),morale:H(CO.morale),fuel:H(CO.fuel),parts:H(CO.parts),uid:CO.uid,deliv:H(CO.deliv),cdel:CO.cdel,xp:CO.xp||0,
      m:Object.keys(CO.m).map(k=>k+"="+H(CO.m[k])).join(" "),
      board:CO.board.map(k=>k.id+":"+H(k.pay)).join(" "),
      jobs:CO.jobs.map(j=>j.id+":"+(j.ret?"r":"")+H(j.tot)+":"+H(j.t0)+":"+j.vids.join("/")+":"+(j.stops?j.stops.length:0)).join(" "),
      veh:CO.veh.map(v=>v.id+":"+v.loc+":"+v.st+":"+H(v.cond)+":"+H(v.km)).join(" "),
      hubs:CO.hubs.map(h=>H(h.share)).join(" "),conf:CO.conf.map(c=>c.a+"-"+c.b+"@"+c.until).join(" "),
      comp:CO.comp.map(c=>H(c.rev)).join(" "),pool:Object.keys(CO.pool).map(k=>k+"="+CO.pool[k]).join(" ")})}
  return {name:CO.name,hq:CO.hq,over:!!G.over,rec}},[sc,days]);
r.seed=seed;r.scenario=sc;r.errors=errs;res.runs.push(r);
const L=r.rec[r.rec.length-1];console.log(seed,sc,r.name,"days",r.rec.length,"delivered",L.cdel,"cash",new DataView(Uint8Array.from(L.cash.match(/../g).map(h=>parseInt(h,16))).buffer).getFloat64(0,true).toFixed(0),errs.join(" | "));
await p.close()}
fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify(res));await b.close()})();
