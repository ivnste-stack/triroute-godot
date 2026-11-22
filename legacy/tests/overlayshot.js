// Screenshot of the HTML version's map with its overlays (the WebGL map, the border/road/settlement canvas and
// the country chips), no interface, for comparing with the Godot renderer.
//   node legacy/tests/overlayshot.js <seed> <out.png> [x,z,dist]
const {chromium}=require('playwright');const D=__dirname;
const seed=+(process.argv[2]||777),out=process.argv[3]||D+'/ref/ov_'+seed+'.png',cam=(process.argv[4]||'').split(',').filter(Boolean).map(Number);
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1600,height:900}});p.setDefaultTimeout(600000);
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
await p.evaluate(s=>{SET.res=1600;SEED=s;SET.wfx=0},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
const keep=await p.evaluate(cam=>{while(modalOpen)nextModal();document.body.classList.remove("hqpick");applyMapColors();
  if(cam.length){Cam.ttx=Cam.tx=cam[0];Cam.ttz=Cam.tz=cam[1];Cam.tdist=Cam.dist=cam[2]}else{Cam.tx=Cam.ttx=0;Cam.tz=Cam.ttz=.6;Cam.dist=Cam.tdist=WX*1.05}
  const keep=new Set(["gl","bcv","cities","vcv"]);const path=[];for(const id of keep){let e=document.getElementById(id);while(e&&e!==document.body){path.push(e);e=e.parentElement}}
  for(const el of document.querySelectorAll("body *"))if(!path.includes(el)&&!path.some(q=>q.contains(el)))el.style.visibility="hidden";
  REDRAW=true;CITY_KEY="";return {mode:UI.mode,cols:G.C.map(c=>c.color)}},cam);
require('fs').writeFileSync(out+'.colors.txt',(await p.evaluate(()=>{const c=coColors?coColors():null;return (c||G.C.map(x=>x.color)).map(v=>Array.isArray(v)?"#"+v.map(q=>Math.round(q*255).toString(16).padStart(2,"0")).join(""):v).join('\n')})));
await p.waitForTimeout(2500);await p.screenshot({path:out});console.log(out,keep.mode);await b.close()})();
