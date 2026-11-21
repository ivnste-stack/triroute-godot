const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
for(const seed of [777,303]){
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(s=>{SET.res=600;SEED=s},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const r=await p.evaluate(()=>{closeWin();while(modalOpen)nextModal();setSpeed(0);const start=CO.board.length,max=coBoardMax(),cities=PL.filter(q=>q.cid===PL[CO.hq].cid).length;
  const fromAll={},snap=[];for(let d=0;d<30;d++){G.day+=1;coBoardDay();for(const k of CO.board)fromAll[PL[k.from].name]=(fromAll[PL[k.from].name]||0)+1;if(d%10===9)snap.push(CO.board.map(k=>PL[k.from].name.slice(0,4)+">"+PL[k.to].name.slice(0,4)).join(" "))}
  openWin("coJobs");const btns=[...document.querySelectorAll('#win .bdwhy')].map(e=>{const r=e.querySelector('.row').getBoundingClientRect(),w=document.getElementById('win').getBoundingClientRect();return Math.round(r.x-w.x)});
  return{start,max,cities,distinctFrom:Object.keys(fromAll).length,fromAll:Object.entries(fromAll).sort((a,b)=>b[1]-a[1]).map(e=>e[0]+":"+e[1]).join(" "),snap,btnLeftX:btns.join(",")}});
r.seed=seed;console.log(JSON.stringify(r,null,1));console.log(errs.slice(0,3).join("\n"));await p.close()}
await b.close()})();
