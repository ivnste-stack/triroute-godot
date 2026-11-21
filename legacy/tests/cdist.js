const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(()=>{SET.res=600;SEED=777});
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const r=await p.evaluate(()=>{closeWin();while(modalOpen)nextModal();setSpeed(0);const ks=[];for(let i=0;i<800&&ks.length<300;i++){const k=coGen();if(k)ks.push(k)}
  const cnt=f=>{const m={};for(const k of ks){const n=PL[f(k)].name+(PL[f(k)].type==="cap"?"*":"");m[n]=(m[n]||0)+1}return Object.entries(m).sort((a,b)=>b[1]-a[1]).map(e=>e[0]+":"+e[1]).join(" ")};
  const capFrom=ks.filter(k=>PL[k.from].type==="cap").length,capTo=ks.filter(k=>PL[k.to].type==="cap").length;
  CO.cash=1e6;{const k=CO.board.find(k=>coPlan(k).ok);coDispatch(k,coPlan(k),true)}openWin("coJobs");const t=document.getElementById("win");
  return{n:ks.length,capFrom,capTo,from:cnt(k=>k.from),to:cnt(k=>k.to),noVehText:/Немає вільної техніки/.test(t.innerText),consNo:t.querySelectorAll('[data-act="consNo"]').length,consAdd:t.querySelectorAll(`[data-act="consAdd"]`).length,tip:(t.querySelector(`[data-act="consNo"]`)||{dataset:{}}).dataset.tip}});
console.log(JSON.stringify(r,null,1));console.log(errs.slice(0,5).join("\n"));await b.close()})();
