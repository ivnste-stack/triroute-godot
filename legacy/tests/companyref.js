// Reference dump of the company start (normal difficulty, the first suggested capital):
// company name, headquarters, the first orders on the board, competitors, manager candidates.
//   node legacy/tests/companyref.js <seed> <outDir>     (run legacy/build.sh first)
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');const D=__dirname;
const seed=+(process.argv[2]||777),out=process.argv[3]||path.join(D,'ref',String(seed));
(async()=>{fs.mkdirSync(out,{recursive:true});
const b=await chromium.launch();const p=await b.newPage();p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
await p.evaluate(s=>{SET.res=600;SEED=s;SET.roadGab=false;
  /* the home market of the Godot version (market_k in sim_core.gd): the board of a small state holds fewer orders */
  coBoardMax=function(){if(CO.tier<1)return 0;const mx=8+CO.tier*2+Math.round(msk("cco")*4)+CO.hubs.reduce((a,h)=>a+h.lvl-1,0);if(CO.tier>=3)return mx;
    const cids=new Set(CO.hubs.map(h=>PL[h.pid].cid));const n=PL.filter(p=>cids.has(p.cid)).length;return Math.max(3,Math.round(mx*Math.min(1.4,Math.max(.35,n/12))))}},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
const pre=await p.evaluate(()=>({name:CO.name,pick:[...document.querySelectorAll('#mbox .choice')].map(e=>e.innerText.split("\n")[0])}));
await p.evaluate(()=>document.querySelector('#mbox .choice').click());await p.waitForTimeout(300);
const r=await p.evaluate(()=>({name:CO.name,hq:CO.hq,me:G.me,cash:CO.cash,
  board:CO.board.map(k=>({...k})),comp:CO.comp,cand:CO.cand,
  places:PL.map(q=>({id:q.id,type:q.type,air:q.air,port:q.port,rail:q.rail,land:q.land}))}));
r.pre=pre;fs.writeFileSync(path.join(out,'company.json'),JSON.stringify(r));
console.log(out,r.name,"hq",r.hq,"board",r.board.length,"first",JSON.stringify(r.board[0]),errs.join(" | "));await b.close()})();
