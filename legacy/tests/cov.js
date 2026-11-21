// Logistics-mode regression + coverage harness.
// usage: node cov.js [cov]   — with "cov" writes covfun.json (function name → calls) for the inline script
const {chromium}=require('playwright');const D=__dirname;const fs=require('fs');
const COV=process.argv[2]==="cov";
async function session(b,kind,res){
  const p=await b.newPage({viewport:{width:1300,height:850}});p.setDefaultTimeout(180000);const errs=[];
  p.on('pageerror',e=>errs.push(kind+' PAGEERR '+e.message+' '+(e.stack||'').split('\n')[1]));
  p.on('console',m=>{const t=m.text();if(m.type()==="error"||/Збій модуля/.test(t))errs.push(kind+' C '+t.slice(0,300))});
  if(COV)await p.coverage.startJSCoverage({resetOnNavigation:false,reportAnonymousScripts:true});
  await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);
  await p.evaluate(()=>{SET.res=900;SEED=777;SET.sandbox=false;SET.noMusic=true;try{localStorage.clear()}catch(e){}});
  const out={kind};
  // start screen
  await p.evaluate(()=>ACT.ngOpen());
  if(await p.$('#sMode button[data-v="2"]'))await p.click('#sMode button[data-v="2"]');
  if(kind==="earth")await p.click('#sMap button[data-v="1"]');
  if(kind==="small"){await p.click('#sSize button[data-v="s"]')}
  if(kind==="train")await p.click('#sDiff button[data-v="0"]');
  await p.click('#sGo');
  await p.waitForFunction(()=>document.querySelector('#mbox .choice')||(window.G&&G.co&&window.CO&&CO.hq!=null&&CO.hubs&&CO.hubs.length),null,{timeout:400000});
  for(let i=0;i<3;i++){const has=await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c){c.click();return true}return false});if(!has)break;await p.waitForTimeout(300)}
  if(kind==="train"){await p.evaluate(()=>{while(modalOpen)nextModal();const p0=PL.find(q=>q.type==="cap");const s=project(p0.x,0,p0.z);coClick(s.x,s.y)});await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});await p.waitForTimeout(300)}
  out.start=await p.evaluate(()=>({co:G.co,hq:CO.hq,hubs:CO.hubs.length,pl:PL.length,C:G.C.length,me:G.me,cash:Math.round(CO.cash)}));
  // play: a growing company, all DLCs
  out.play=await p.evaluate(()=>{closeWin();while(modalOpen)nextModal();SET.dlcPost=true;SET.dlcLog=true;CO.tier=7;CO.cash=5e9;CO.rating=4.2;for(const r in CO.pool)CO.pool[r]=400;
    const H=PL[CO.hq],near=PL.filter(q=>q.land===H.land).slice(0,14).concat(PL.filter(q=>q.port!=null||q.air).slice(0,10));
    for(const q of near){try{ACT.coHub(q.id);const h=hubAt(q.id);if(h)h.lvl=Math.min(3,h.lvl+2);CO.buyAt=q.id;ACT.coBuy("truck");ACT.coBuy("van");if(q.rail)ACT.coBuy("train");if(q.port!=null)ACT.coBuy("ship");if(q.air)ACT.coBuy("plane")}catch(e){}}
    for(const r in ROLE)ACT.coHire(r+":120");
    try{ACT.poAdapt&&ACT.poAdapt(CO.hq);PL.filter(q=>q.cid===H.cid).slice(0,6).forEach(q=>ACT.poOff&&ACT.poOff(q.id));for(let i=0;i<6;i++)ACT.poBuy&&ACT.poBuy("pvan")}catch(e){}
    let sent=0,done0=CO.deliv;
    for(let d=0;d<240;d++){dayTick();for(const k of CO.board.slice(0,6)){const P=coPlan(k);if(P.ok){ACT.coSend(k.id);sent++}}
      for(const j of CO.jobs.slice())if(G.day-j.t0>j.tot*.5&&!j.lp)j.t0-=j.tot*.3;CO.lastFr=.5;coFrame()}
    return{days:G.day,sent,deliv:CO.deliv-done0,jobs:CO.jobs.length,cash:Math.round(CO.cash),rating:+CO.rating.toFixed(2),htax:Math.round((CO.mhist||[]).reduce((a,m)=>a+(m.hubtax||0),0)+(CO.m.hubtax||0)+(CO.lm&&CO.lm.hubtax||0)),chains:CO.jobs.filter(j=>j.chain||j.plan).length,hubs:CO.hubs.length,veh:CO.veh.length,post:CO.post?CO.post.trips.length:-1,news:G.news.length}});
  // every window & layer
  out.ui=await p.evaluate(()=>{const opened=[];const rail=[...document.querySelectorAll('#rail [data-act="win"]')].map(b=>b.dataset.arg);
    for(const k of new Set(rail.concat(Object.keys(WINS).filter(k=>/^(co|po)[A-Z]/.test(k))))){try{openWin(k);renderWin();opened.push(k)}catch(e){opened.push(k+"!ERR:"+e.message)}}closeWin();
    const lay=[];for(const m of CO_MODES){try{ACT.mode(m[0]);lay.push(m[0])}catch(e){lay.push(m[0]+"!"+e.message)}}ACT.mode("co");
    for(const k of Object.keys(LF_SET||{}))try{ACT.lf(k);ACT.lf(k)}catch(e){}
    return{rail,opened,lay}});
  await p.waitForTimeout(1500);
  // map interaction: click cities, inspector, hover tips
  out.map=await p.evaluate(()=>{let n=0;for(const q of PL.slice(0,30)){const s=project(q.x,0,q.z);if(!s)continue;try{coClick(s.x,s.y);n++}catch(e){return "ERR "+e.message}}
    const j=CO.jobs[0];if(j){ACT.coJob(j.id);coCard()}return{clicked:n,insp:!$("#insp").hidden}});
  await p.mouse.move(650,420);await p.waitForTimeout(400);await p.mouse.move(700,450);await p.waitForTimeout(800);
  // planner, multi-drop, ship reroute
  out.dlc=await p.evaluate(()=>{const o={};try{let k=null;for(let i=0;i<3000&&!k;i++){const c=coGen();if(c&&c.multi)k=c}if(k){CO.board.push(k);ACT.lpPlan(k.id);ACT.lpOrder("urg");o.multi=lpCalc().done;ACT.lpGo()}}catch(e){o.multi="ERR "+e.message}
    try{const k=CO.board.find(x=>!x.multi&&coPlan(x).ok);if(k){const had=CO.mgr.cto;if(!had)CO.mgr.cto={id:"cto",name:"Тест",skill:5,sal:1,honest:true,loyal:100};ACT.lpPlan(k.id);ACT.lpAutoUse();if(!had)delete CO.mgr.cto;o.plan=lpCalc().done;ACT.lpGo()}}catch(e){o.plan="ERR "+e.message}
    try{const j=CO.jobs.find(x=>x.mode==="sea"&&srOK(x));if(j){srOpen(j);ACT.srAvoid();o.ship=!srCalc().bad;ACT.srGo()}else o.ship="none"}catch(e){o.ship="ERR "+e.message}
    try{const t=CO.post&&CO.post.term[0];if(t!=null){const d=CO.post.off.find(x=>x!==t);if(d!=null){ACT.lpPost(t+":"+d);o.post=true;ACT.lpCancel()}}}catch(e){o.post="ERR "+e.message}
    for(let d=0;d<30;d++){dayTick();CO.lastFr=.5;coFrame()}o.jobs=CO.jobs.length;return o});
  await p.waitForTimeout(1200);
  // menu, settings, keys, screenshot, save + load
  out.menu=await p.evaluate(async()=>{const o={};try{openMenu&&openMenu();MENU.view="set";renderMenu();MENU.setTab="ctl";renderMenu();MENU.setTab="gfx";renderMenu();MENU.view="save";renderMenu();ACT.doSave(1);o.saved=!!localStorage.getItem("pon_save_1");closeMenu&&closeMenu()}catch(e){o.err=e.message}
    try{if(typeof shotTake==="function")await shotTake();}catch(e){o.shot="ERR "+e.message}return o});
  await p.waitForTimeout(800);
  if(kind==="rand"){
    const sig1=await p.evaluate(()=>({cash:Math.round(CO.cash),jobs:CO.jobs.length,hubs:CO.hubs.length,veh:CO.veh.length,day:G.day}));
    await p.evaluate(()=>{G.me=null});await p.evaluate(()=>loadGame(1));await p.waitForFunction(()=>G.co&&CO&&CO.hubs&&CO.hubs.length&&G.me!=null,null,{timeout:400000});await p.waitForTimeout(1500);
    const sig2=await p.evaluate(()=>{for(let d=0;d<20;d++){dayTick();coFrame()}return{cash:Math.round(CO.cash),jobs:CO.jobs.length,hubs:CO.hubs.length,veh:CO.veh.length,day:G.day}});
    out.load={sig1,sig2};
  }
  try{await p.screenshot({path:D+'/cov_'+kind+'.png',timeout:120000})}catch(e){errs.push(kind+' screenshot timeout')}
  if(COV){const c=await p.coverage.stopJSCoverage();for(const e of c){if(!e.source||e.source.length<500000)continue;res.src=e.source;for(const f of e.functions){const r=f.ranges[0];const key=r.startOffset;const cur=res.fn[key]||{n:f.functionName,s:r.startOffset,e:r.endOffset,c:0};cur.c+=r.count;res.fn[key]=cur}}}
  out.errs=errs;await p.close();return out}
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});const res={fn:{},src:null};
  const kinds=(process.argv[3]||"rand,earth,small,train").split(",");
  for(const k of kinds){try{const o=await session(b,k,res);console.log(JSON.stringify(o))}catch(e){console.log(k+" FAILED "+e.message)}}
  if(COV){fs.writeFileSync(D+'/covfun.json',JSON.stringify(Object.values(res.fn)));fs.writeFileSync(D+'/covsrc.js',res.src)}
  await b.close()})();
