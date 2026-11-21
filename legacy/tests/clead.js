const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(()=>{SET.res=900;SEED=777});
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const STEP=`(n,dt)=>{for(let i=0;i<n;i++){G.day+=dt;CO.lastFr=0;coFrame();coReturns()}}`;
const r=await p.evaluate((STEP)=>{const step=eval(STEP);closeWin();while(modalOpen)nextModal();setSpeed(0);CO.cash=1e6;CO.xp=2000;const o={};
  // an order whose loading city is not the hub: the truck drives there empty first
  const H=CO.hq;const k=CO.board.find(k=>k.mode==="road"&&k.from!==H&&!k.legs&&coPlan(k).ok);if(!k)return{err:"no lead order"};
  coDispatch(k,coPlan(k),true);const j=CO.jobs.find(x=>!x.ret);o.lead=+j.lead.toFixed(3);step(3,.01);const st=coJobState(j,coNow()-j.t0);o.phase=st.ph;o.srOK=srOK(j);
  o.badge=(buildHUD(),coHUD(),$("#coTripBadge")&&!$("#coTripBadge").hidden?$("#coTripBadge").textContent:null);
  ACT.srOpen(j.id);o.srOn=SR.on;const C=srCalc();o.calc=C.bad?"bad":{len:+C.len.toFixed(3),eta:+C.eta.toFixed(2),cur:+C.curEta.toFixed(2)};
  const lenBefore=j.len;ACT.srGo();o.after={lead:+j.lead.toFixed(3),lenSame:j.len===lenBefore,tot:+j.tot.toFixed(2)};
  const d0=CO.cdel;for(let i=0;i<600&&CO.jobs.includes(j);i++)step(1,.01);o.delivered=!CO.jobs.includes(j)&&CO.cdel>d0;o.lastEv=j.ev.slice(-3);
  // autosave slot
  saveWrite("auto");o.autoMeta=!!slotMeta("auto");
  // road events
  JAM.length=0;JAMN.clear();incJams(coNow(),.1);o.jams=JAM.length;o.target=rcTarget();
  return o},STEP);
console.log(JSON.stringify(r,null,1));console.log(errs.slice(0,5).join("\n"));await b.close()})();
