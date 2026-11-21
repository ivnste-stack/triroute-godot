const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(()=>{SET.res=600;SEED=777});
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);await p.evaluate(()=>{const c=document.querySelector('#mbox .choice');if(c)c.click()});
const r=await p.evaluate(()=>{closeWin();while(modalOpen)nextModal();setSpeed(0);const out={};
  const stat=xp=>{CO.xp=xp;const ks=[];for(let i=0;i<600&&ks.length<250;i++){const k=coGen();if(k&&k.mode==="road")ks.push(k)}const n=ks.length,mr=ks.filter(k=>k.minR);
    const ppk=ks.reduce((a,k)=>a+k.pay/Math.max(.01,k.len)/Math.pow(k.tons,.85),0)/n;
    return{n,grade:GRADES[coGrade()].n,minR:mr.length,minROK:mr.filter(k=>k.minR<=CO.rating).length,prem:ks.filter(k=>k.prem).length,vip:ks.filter(k=>k.vip).length,
      avgLen:+(ks.reduce((a,k)=>a+k.len,0)/n*KM).toFixed(0),dlPerLen:+(ks.reduce((a,k)=>a+k.dlDays/Math.max(.01,k.len),0)/n).toFixed(1),payIdx:Math.round(ppk)}};
  out.g0=stat(0);out.g2=stat(1500);out.g3=stat(4000);
  // board fill at a higher licence over 30 days
  CO.xp=0;CO.tier=4;CO.board=[];const mx=coBoardMax();const fill=[];for(let d=0;d<30;d++){G.day+=1;coBoardDay();if(d%5===4)fill.push(CO.board.length)}out.fill={max:mx,fill:fill.join(",")};
  return out});
console.log(JSON.stringify(r,null,1));console.log(errs.slice(0,5).join("\n"));await b.close()})();
