// Screenshot of the HTML version's map layer only (the WebGL canvas, no roads / labels / interface),
// for comparing with the Godot renderer.   node legacy/tests/mapshot.js <seed> <out.png> [x,z,dist]
const {chromium}=require('playwright');const D=__dirname;
const seed=+(process.argv[2]||777),out=process.argv[3]||D+'/ref/map_'+seed+'.png',cam=(process.argv[4]||'').split(',').filter(Boolean).map(Number);
(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const p=await b.newPage({viewport:{width:1600,height:900}});p.setDefaultTimeout(600000);
await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
await p.evaluate(s=>{SET.res=1600;SEED=s;SET.wfx=0},seed);
await p.evaluate(()=>ACT.ngOpen());await p.click('#sGo');await p.waitForSelector('#mbox .choice');
await p.evaluate(cam=>{while(modalOpen)nextModal();UI.mode="pol";applyMapColors();
  if(cam.length){Cam.ttx=Cam.tx=cam[0];Cam.ttz=Cam.tz=cam[1];Cam.tdist=Cam.dist=cam[2]}else{Cam.tx=Cam.ttx=0;Cam.tz=Cam.ttz=.6;Cam.dist=Cam.tdist=WX*1.05}
  for(const el of document.body.children)if(el.id!=="gl")el.style.visibility="hidden";REDRAW=true},cam);
require('fs').writeFileSync(out+'.colors.txt',(await p.evaluate(()=>G.C.map(c=>c.color).join('\n'))));
await p.waitForTimeout(2500);await p.locator('#gl').screenshot({path:out});console.log(out);await b.close()})();
