const {chromium}=require('playwright');const D=__dirname;
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const out=[];
for(const seed of (process.argv[2]||"777,101,202,303,404,505,606,808").split(",").map(Number)){
const p=await b.newPage({viewport:{width:1300,height:900}});p.setDefaultTimeout(600000);const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(800);await p.evaluate(s=>{SET.res=600;SEED=s},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
const r=await p.evaluate(()=>{const mates=p=>PL.filter(q=>q!==p&&q.cid===p.cid&&q.node!=null&&BOARD.comp[q.node]===BOARD.comp[p.node]).length;
  const caps=PL.filter(p=>p.type==="cap");const iso=caps.filter(p=>mates(p)<3).map(p=>p.name+":"+mates(p)+"/"+PL.filter(q=>q.cid===p.cid).length);
  const opts=[...document.querySelectorAll('#mbox .choice')].length;return{caps:caps.length,iso,hqMates:mates(PL[CO.hq]),board:CO.board.length}});
r.seed=seed;r.errs=errs.slice(0,2);out.push(r);console.log(JSON.stringify(r));await p.close()}
await b.close()})();
