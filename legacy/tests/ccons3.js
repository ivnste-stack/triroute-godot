const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message+' '+(e.stack||'').split('\n')[1]));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(()=>{SET.res=900;SEED=777});
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const r=await p.evaluate(()=>{closeWin();while(modalOpen)nextModal();setSpeed(0);const H=CO.hq,to=PL.find(q=>q.cid===PL[H].cid&&q.id!==H&&coRoute("road",H,q.id)).id;
  const mk=(cg,t)=>({id:CO.uid++,from:H,to,cg,tons:t,pay:2000,dlDays:4,mode:"road",risk:.2,minR:0,len:coRoute("road",H,to).len,exp:G.day+9});
  const a=mk("engines",2.2),c=mk("elec",5);CO.board.push(a,c);UI.cons=[];openWin("coJobs");ACT.consAdd(a.id);ACT.consAdd(c.id);
  const btn=document.querySelector('#win [data-act="consRoute"]'),note=[...document.querySelectorAll('#win .note.bad')].map(e=>e.innerText).join(" | ");
  // the planner itself (opened anyway) must not show deliveries
  ACT.consRoute();LP.mode="road";lpAdd(to);const C=lpCalc();const html=$("#lpPanel").innerText;
  return{btnDisabled:btn&&btn.disabled,note,plannerBlock:C.consBlock,done:C.done,greenDelivered:/вчасно/.test(html),notFit:/не вміщується/.test(html)}});
console.log(JSON.stringify(r,null,1));console.log(errs.slice(0,5).join("\n"));await b.close()})();
