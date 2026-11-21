const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message+' '+(e.stack||'').split('\n')[1]));p.on('console',m=>{if(m.type()==="error")errs.push(m.text().slice(0,300))});
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(()=>{SET.res=900;SEED=777});
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const STEP=`(n,dt)=>{for(let i=0;i<n;i++){G.day+=dt;CO.lastFr=0;coFrame();coReturns()}}`;
const r=await p.evaluate((STEP)=>{const step=eval(STEP);closeWin();while(modalOpen)nextModal();setSpeed(0);JAM.length=0;CO.wx=[];const out={};
  // C. demand in the training tooltip
  out.demand=G.C.slice(0,5).map(c=>coDemand(c.id)[0]);
  // D. the highlighted choice
  queueModal({title:"t",choices:[{t:"Відкрити штаб тут",hl:1,f(){}},{t:"Інша",f(){}}]});out.hl=!!document.querySelector("#mbox .choice.hl");while(modalOpen)nextModal();
  // B. vehicle choice in the planner
  CO.cash=1e6;CO.staff.driver=5;ACT.coBuy("ltruck");ACT.coBuy("van");const k=CO.board.find(k=>k.mode==="road"&&coPlan(k).ok);ACT.lpPlan(k.id);
  out.dbg={on:LP.on,k:!!LP.k,p0:LP.pts[0],m:LP.mode,veh:CO.veh.map(v=>v.t+":"+v.st+":"+PL[v.loc].cid+":"+v.resv),cid:PL[LP.pts[0]]&&PL[LP.pts[0]].cid};if(!LP.on)return out;const L=lpVehList();out.vehList=L.map(v=>VT[v.t].n+"@"+PL[v.loc].name);const van=L.find(v=>v.t==="van");if(van&&k.tons>1.5){ACT.lpVeh(van.id);LP.mode="road";lpAdd(k.to);out.vanBlock=lpBlock(lpCalc());ACT.lpUndo()}const pick=L.find(v=>v.t==="ltruck")||L[0];ACT.lpVeh(pick.id);LP.mode="road";lpAdd(k.to);const C=lpCalc();
  out.vehPicked={want:VT[pick.t].n,used:C.legs[0]&&C.legs[0].veh,html:/Хто їде/.test($("#lpPanel").innerHTML)};
  const before=CO.jobs.length;ACT.lpGo();const j=CO.jobs[CO.jobs.length-1];out.dispatchedWith=j?VT[CO.veh.find(v=>v.id===j.vids[0]).t].n:null;
  // G. cancel with a fine
  step(30,.01);const c0=CO.cash,r0=CO.rating,info=coCancelInfo(j);coCancelDo(j);const ret=CO.jobs.find(x=>x.ret&&x.vids.includes(j.vids[0]));
  out.cancel={fine:info.fine,cashDrop:Math.round(c0-CO.cash),rating:+(r0-CO.rating).toFixed(2),returning:!!ret,retFrom:ret?[+ret.p[0].toFixed(2),+ret.p[1].toFixed(2)]:null};
  // A. a truck driving home takes a new order on the way
  for(const v of CO.veh){if(v.st==="idle"){v.st="idle"}}let k2=null;for(let i=0;i<300&&!k2;i++){const q=coGen();if(q&&q.mode==="road"){const P=coPlan(q);if(P.ok&&P.vids.some(id=>CO.veh.find(v=>v.id===id).st==="trip")){k2=q;CO.board.push(q)}}}
  if(k2){const P=coPlan(k2),rv=CO.veh.find(v=>P.vids.includes(v.id)&&v.st==="trip"),retJ=CO.jobs.find(x=>x.ret&&x.vids.includes(rv.id));coDispatch(k2,P,true);out.redirect={ok:true,retGone:!CO.jobs.includes(retJ),newJob:CO.jobs.some(x=>!x.ret&&x.vids.includes(rv.id)),lead:+P.lead.toFixed(3)}}else out.redirect="no returning-vehicle plan";
  // E. hurricane: slows, does not stop
  const jr=CO.jobs.find(x=>!x.ret&&x.mode==="road");if(jr){const st=coJobState(jr,coNow()-jr.t0),q=coPosAt(jr,Math.min(jr.lead+jr.len,st.s+.05));CO.wx=[{id:CO.uid++,k:"hur",n:"Ураган",x:q[0],z:q[1],r:.3,t0:coNow()-.1,until:coNow()+3,near:"т",on:1}];const tot0=jr.tot;let paused=false,slowed=null;
    for(let i=0;i<400;i++){G.day+=.002;CO.lastFr=0;incFrame(G.day);const s=coJobState(jr,coNow()-jr.t0);if(s.inc&&s.inc.k==="wx")paused=true;if(/сповільнено/.test(s.ph))slowed=s.ph}
    out.hur={paused,slowed,totAdded:+(jr.tot-tot0).toFixed(3),blocksRoads:!!(WXK.hur.road)}}
  return out},STEP);
console.log(JSON.stringify(r,null,1));console.log(errs.slice(0,6).join("\n"));await b.close()})();
