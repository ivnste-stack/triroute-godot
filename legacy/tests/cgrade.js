const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(()=>{SET.res=900;SEED=777});
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const r=await p.evaluate(()=>{closeWin();while(modalOpen)nextModal();setSpeed(0);const o={};
  o.g0=coGrade();const k=CO.board.find(k=>consOK(k));UI.cons=[];ACT.consAdd(k.id);o.consBlocked=!UI.cons.length;
  CO.xp=1500;o.g1=coGrade();ACT.consAdd(k.id);o.consOK=UI.cons.length===1;UI.cons=[];
  o.lic=coLicOK().r.map(x=>x[1]+"="+x[2]).join(" | ");CO.tier=3;o.lic4=coLicOK().r.map(x=>x[1]+"="+x[2]).join(" | ");CO.tier=1;
  // seasons
  const seen={};for(const m of [0,6,9,3]){G.date.m=m;seen[m]=[...new Set(Array.from({length:40},()=>pick(wxSeason())))].join(",")}G.date.m=0;o.season=seen;
  return o});
console.log(JSON.stringify(r,null,1));
await p.waitForTimeout(600);await p.hover('#yearBox');await p.waitForTimeout(700);
console.log('tip',await p.evaluate(()=>{const t=document.getElementById('tip');const r=t.getBoundingClientRect();return [r.height,[...t.querySelectorAll('*')].map(e=>e.tagName+Math.round(e.getBoundingClientRect().height)).slice(0,14).join(' '),getComputedStyle(t).whiteSpace]}));await p.screenshot({path:D+'/grade.png',clip:{x:0,y:0,width:560,height:520}});
// planner preview through weather + hub tax
const r2=await p.evaluate(()=>{const H=CO.hq,dests=PL.filter(q=>q.cid===PL[H].cid&&q.id!==H&&coRoute("road",H,q.id)).sort((a,b)=>coRoute("road",H,b.id).len-coRoute("road",H,a.id).len);const to=dests[0];
  const r0=coRoute("road",H,to.id),mid=r0.p.length/2|0,mx=r0.p[mid&~1],mz=r0.p[(mid&~1)+1];
  CO.wx=[{id:CO.uid++,k:"snow",n:"Снігова буря",x:mx,z:mz,r:.3,t0:coNow()-.1,until:coNow()+2,near:"т",on:1}];incBlk();
  const rAvoid=coRoute("road",H,to.id),k={id:CO.uid++,from:H,to:to.id,cg:"engines",tons:2,pay:3000,dlDays:5,mode:"road",risk:.2,minR:0,len:r0.len,exp:G.day+9};CO.board.push(k);
  ACT.lpPlan(k.id);LP.mode="road";const plain=lpSeg("road",H,to.id);
  return{avoidLen:+rAvoid.len.toFixed(3),plainLen:+plain.len.toFixed(3),origLen:+r0.len.toFixed(3)}});
console.log(JSON.stringify(r2));
console.log(errs.slice(0,5).join("\n"));await b.close()})();
