// Reference run of the company simulation, day by day, for the Godot port (godot/tests/test_sim.gd).
//   node legacy/tests/simref.js <outFile> [days] [seed…]     (run legacy/build.sh first)
// Deterministic: the game's RNG is seeded by the world seed, Math.random (road closures, pirate zones) too;
// the postal service is switched off (not ported yet); city deliveries are gone (coLocal keeps upkeep and morale); in "fleet" the first tender offer is taken; decisions in dialogs take
// the first choice; Math.pow is replaced by the correctly rounded one of crmath.js
// (the Godot version uses the same, see native/src/core/crmath.h). Time stands still (speed 0) and every
// day runs 8 frames (G.pfr = 0, 1/8 … 7/8; coFrame) and then dayTick().
// Policy each morning: the best-paying orders that the company can do on time are dispatched (chains of legs
// too); in "abroad" and "ocean" the route planner then sends the best-paying chain left when that pays, and
// every 10 days the planner's estimates for the first orders on the board are recorded.
// Scenarios: "start" — the company as it starts; "fleet" — more vehicles and drivers, tier 2 and a
// dispatcher (CTO), so returns, the dispatcher, wages and managers are covered too; "abroad" — tier 4:
// orders across the continent (border checkpoints, customs) and trains; "staff" — "fleet" with low wages, an
// honest finance director and a dishonest, underpaid operations director (strikes, embezzlement, pay rises),
// and every decision takes the second choice; "ocean" — tier 5 with a hub and ships in the nearest port; "air" —
// tier 6 with planes (multi-drop flights). Also: a consolidated road trip in "fleet", and once a week a course
// change around danger in "fleet", "ocean" and "air".
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');const D=__dirname;
const out=process.argv[2]||path.join(D,'ref','sim.json'),days=+(process.argv[3]||150),seeds=process.argv.slice(4).map(Number);if(!seeds.length)seeds.push(777,303);
const cr=fs.readFileSync(path.join(D,'crmath.js'),'utf8');
(async()=>{const b=await chromium.launch();const res={days,runs:[]};
for(const seed of seeds)for(const sc of ["start","fleet","abroad","staff","ocean","air"]){
const p=await b.newPage();p.setDefaultTimeout(1200000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
await p.addScriptTag({content:cr});
await p.evaluate(s=>{Math.pow=CRMATH.pow;SET.res=600;SEED=s;SET.roadGab=false;
  /* before the game starts: frames run between the start and the first step, and incidents draw from R there */
  guard=function(n,f){f()}; /* errors must stop the run, not be swallowed */
  window.__inc=[incFrame,coJobsDay];incFrame=()=>{};coJobsDay=()=>{}; /* switched back on when the run starts */
  poDay=()=>{};poMonth=()=>{};
  // the home market (market_k in sim_core.gd): while inside its own states the board holds fewer orders in a small state
  coBoardMax=function(){if(CO.tier<1)return 0;const mx=8+CO.tier*2+Math.round(msk("cco")*4)+CO.hubs.reduce((a,h)=>a+h.lvl-1,0);if(CO.tier>=3)return mx;
    const cids=new Set(CO.hubs.map(h=>PL[h.pid].cid));const n=PL.filter(p=>cids.has(p.cid)).length;return Math.max(3,Math.round(mx*Math.min(1.4,Math.max(.35,n/12))))};
  /* the game has no city deliveries any more (removed in the Godot version): the day of the company keeps only
     the upkeep and the morale (no local market, revenue, couriers' wear, service rating or city accidents) */
  coLocal=function(){let up=0;for(const v of CO.veh){up+=VT[v.t].up*[.8,1,1.35][CO.maint]}CO.cash-=up;CO.m.upkeep+=up;
    const mt=clamp(52+(CO.wageLv-1)*130+msk("hro")*16-(CO.cash<0?12:0)+(CO.founder?6:0),5,98);CO.morale+=(mt-CO.morale)*.04};
  /* decisions are taken at once: the first choice (the Godot test does the same, Sim.auto_choice = 0) */
  coModal=function(s){CO.mcd=G.day+rint(9,18);s.choices[Math.min(window.__choice||0,s.choices.length-1)].f()};
  const _sh=coSetHQ;coSetHQ=function(){const r=_sh.apply(this,arguments);setSpeed(0);return r}},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);
const r=await p.evaluate(([sc,days])=>{
  setSpeed(0);CO.lastFr=0;G.pfr=0;
  [incFrame,coJobsDay]=window.__inc;INC_F=0; /* trips are checked every other frame: start on the same parity as Sim.inc_f */
  Math.random=mulberry((SEED^0x51ed)>>>0); /* road closures and pirate zones; the Godot version uses Sim.RX */
  /* the frame logic runs once per frame: HTML also re-runs it from HUD refreshes (coFrame → updateHUD → coHUD →
     coFrame when the number of trips changes), which is interface plumbing, not game logic — Godot does not */
  {const _cf=coFrame;coFrame=function(){if(!window.__step)return;window.__step=false;_cf()}}
  const dv=new DataView(new ArrayBuffer(8));const H=x=>{dv.setFloat64(0,+x,true);let s="";for(let i=0;i<8;i++)s+=dv.getUint8(i).toString(16).padStart(2,"0");return s};
  const SC={fleet:{cash:250000,tier:2,staff:{driver:8},veh:["ltruck","ltruck","van","van","van","truck","truck"]},
    abroad:{cash:2e6,tier:4,staff:{driver:12,rail:6},veh:["truck","truck","truck","rtrain","reefer","ltruck","van","train","train"]},
    staff:{cash:250000,tier:2,staff:{driver:8},veh:["ltruck","ltruck","van","van","van","truck","truck"]},
    ocean:{cash:5e7,tier:5,staff:{driver:16,rail:8,sailor:40},veh:["truck","truck","truck","truck","train","train"]},
    air:{cash:2e8,tier:6,staff:{driver:16,pilot:30},veh:["plane","plane","turbo","truck","truck","truck"]}}[sc];
  if(SC){CO.cash=SC.cash;CO.tier=SC.tier;Object.assign(CO.staff,SC.staff);
    for(const t of SC.veh)CO.veh.push({id:CO.uid++,t,loc:CO.hq,st:"idle",cond:100,km:0});
    CO.mgr.cto={...CO.cand.cto[0]};delete CO.cand.cto;CO.auto=true}
  if(sc==="ocean"){const H=PL[CO.hq];const P=H.port!=null?H:PL.filter(p=>p.port!=null&&p.land===H.land).sort((a,b)=>Math.hypot(a.x-H.x,a.z-H.z)-Math.hypot(b.x-H.x,b.z-H.z))[0];
    if(P){if(P.id!==CO.hq)CO.hubs.push({pid:P.id,lvl:1,share:.04,mk:0});for(const t of ["feeder","ship","feeder"])CO.veh.push({id:CO.uid++,t,loc:P.id,st:"idle",cond:100,km:0})}}
  openWin=()=>{}; /* the planner opens the orders window after sending: interface only */
  if(sc==="staff"){window.__choice=1;CO.wageLv=.7;CO.mgr.cfo={...CO.cand.cfo[0],honest:true};delete CO.cand.cfo;
    CO.mgr.coo={...CO.cand.coo[0],honest:false,sal:500};delete CO.cand.coo}
  const policy=()=>{let n=0;if(sc==="fleet"&&!CO.tenders.length&&(CO.toff||[]).length)ACT.coTd(CO.toff[0].id);for(const k of CO.board.slice().sort((a,b)=>b.pay-a.pay)){const P=coPlan(k);if(P.ok&&!P.late){coDispatch(k,P,true);n++}}
    /* the route planner: the best-paying chain order left is sent along its legs when that pays */
    if(sc==="abroad"||sc==="ocean"){const k=CO.board.filter(k=>k.legs).sort((a,b)=>b.pay-a.pay)[0];
      if(k){Object.assign(LP,{k,pts:[k.from,...k.legs.map(L=>L.b)],modes:k.legs.map(L=>L.m),veh0:null,post:false,byMgr:false,tn:null});const C=lpCalc();if(C.done&&!lpGroups().bad&&C.legs.length&&C.legs.length===lpGroups().G.length&&!lpBlock(C)&&C.net>0){ACT.lpGo();n+=100}}}
    /* multi-drop flights: the most urgent landing first */
    if(sc==="air")for(const k of CO.board.filter(k=>k.multi).sort((a,b)=>b.pay-a.pay).slice(0,1)){const ord=k.multi.map(d=>PL[d.to]).sort((a,b)=>k.multi.find(d=>d.to===a.id).dl-k.multi.find(d=>d.to===b.id).dl);
      Object.assign(LP,{k,pts:[k.from,...ord.map(p=>p.id)],modes:ord.map(()=>"air"),veh0:null,post:false,byMgr:false,tn:null});const C=lpCalc();if(C.done&&!lpGroups().bad&&C.legs.length&&C.legs.length===lpGroups().G.length&&!lpBlock(C)&&C.net>0){ACT.lpGo();n+=1000}}
    /* a consolidated road trip of the three best-paying small road orders (up to 6 t, no special permits) */
    if(sc==="fleet"){const ks=CO.board.filter(k=>consOK(k)&&k.mode==="road"&&k.tons<=6&&permNeed(CARGO_I[k.cg],"road").every(permOK)).sort((a,b)=>b.pay-a.pay).slice(0,3);
      if(ks.length>=2){UI.cons=ks.map(k=>k.id);let kC=null;const _lo=lpOpen;lpOpen=k=>{kC=k};ACT.consRoute();lpOpen=_lo;
        Object.assign(LP,{k:kC,pts:consAutoSeq(kC),veh0:null,consVeh:undefined,post:false,byMgr:false,tn:null});LP.modes=LP.pts.slice(1).map(()=>"road");
        const C=lpCalc();if(C.done&&!lpBlock(C)&&C.net>0){ACT.lpGo();n+=10000}UI.cons=[]}}
    /* once a week the first trip that can turns its course around danger */
    if((sc==="fleet"||sc==="ocean"||sc==="air")&&G.day%7===3){const j=CO.jobs.find(j=>srOK(j));
      if(j){Object.assign(SR,{j,m:j.mode,pts:[],avoid:true,ck:null});const C=srCalc();if(!C.bad){ACT.srGo();n+=100000}}}
    return n};
  const lpRec=()=>CO.board.slice(0,4).map(k=>{Object.assign(LP,{k,pts:k.legs?[k.from,...k.legs.map(L=>L.b)]:[k.from,k.to],modes:k.legs?k.legs.map(L=>L.m):[k.mode],veh0:null,post:false,tn:null});
    const C=lpCalc(),b=lpBlock(C);return k.id+":"+H(C.t)+":"+H(C.c)+":"+H(C.risk)+":"+H(C.net)+":"+(C.done?1:0)+":"+C.legs.map(L=>L.own?"o":"p").join("")+":"+(b?1:0)}).join(" ");
  const rec=[];
  for(let d=0;d<days&&!G.over;d++){const sent=policy();
    for(let f=0;f<8;f++){G.pfr=f/8;window.__step=true;coFrame()}
    dayTick();
    rec.push({day:G.day,sent,cash:H(CO.cash),rating:H(CO.rating),morale:H(CO.morale),fuel:H(CO.fuel),parts:H(CO.parts),uid:CO.uid,deliv:H(CO.deliv),cdel:CO.cdel,xp:CO.xp||0,
      m:Object.keys(CO.m).map(k=>k+"="+H(CO.m[k])).join(" "),
      board:CO.board.map(k=>k.id+":"+H(k.pay)).join(" "),
      jobs:CO.jobs.map(j=>j.id+":"+(j.ret?"r":"")+(j.back?"b":"")+(j.cx0?"x":"")+(j.lost?"l":"")+H(j.tot)+":"+H(j.t0)+":"+j.vids.join("/")+":"+(j.stops?j.stops.length:0)+":"+H(j.dmg)+":"+(j.pz?j.pz.length:0)+":"+H(j.payK||1)).join(" "),
      cls:(CO.cls||[]).map(c=>c.id+c.kind+c.a+"-"+(c.b??"")+"@"+H(c.until)).join(" "),wx:(CO.wx||[]).map(w=>w.id+w.k+"@"+H(w.until)).join(" "),
      band:(CO.band||[]).map(z=>z.id+"@"+H(z.x)).join(" "),pir:(CO.pir||[]).map(z=>z.id+"@"+H(z.x)).join(" "),jam:JAM.map(J=>J.id+":"+J.n+"@"+H(J.until)).join(" "),mcd:CO.mcd||0,
      lp:d%10===9?lpRec():"",
      td:CO.tenders.map(t=>t.t+":"+t.n+":"+t.left+":"+t.pay).join(" ")+"|"+(CO.toff||[]).map(o=>o.id+":"+o.t+":"+o.n+":"+o.pay).join(" "),
      mgr:Object.keys(CO.mgr).map(k=>k+":"+CO.mgr[k].sal+":"+CO.mgr[k].loyal+":"+CO.mgr[k].honest).join(" ")+"|"+CO.strike+"|"+H(CO.wageLv)+"|"+Object.keys(CO.staff).map(k=>CO.staff[k]).join(","),
      veh:CO.veh.map(v=>v.id+":"+v.loc+":"+v.st+":"+H(v.cond)+":"+H(v.km)).join(" "),
      hubs:CO.hubs.map(h=>H(h.share)).join(" "),conf:CO.conf.map(c=>c.a+"-"+c.b+"@"+c.until).join(" "),
      comp:CO.comp.map(c=>H(c.rev)).join(" "),pool:Object.keys(CO.pool).map(k=>k+"="+CO.pool[k]).join(" ")})}
  return {name:CO.name,hq:CO.hq,over:!!G.over,rec}},[sc,days]);
r.seed=seed;r.scenario=sc;r.errors=errs;res.runs.push(r);
const L=r.rec[r.rec.length-1];console.log(seed,sc,r.name,"days",r.rec.length,"delivered",L.cdel,"cash",new DataView(Uint8Array.from(L.cash.match(/../g).map(h=>parseInt(h,16))).buffer).getFloat64(0,true).toFixed(0),errs.join(" | "));
await p.close()}
fs.mkdirSync(path.dirname(out),{recursive:true});fs.writeFileSync(out,JSON.stringify(res));await b.close()})();
