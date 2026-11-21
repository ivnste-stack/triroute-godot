/* ================= MAIN ================= */
let SEED=(Math.random()*1e9)|0;
function showSeed(){$("#sSeed").textContent="#"+SEED.toString(36).toUpperCase()}
showSeed();
$("#sReroll").onclick=()=>{SEED=(Math.random()*1e9)|0;showSeed()};
$("#sDiff").addEventListener("click",e=>{const b=e.target.closest("button");if(!b)return;$("#sDiff").querySelectorAll("button").forEach(x=>x.classList.toggle("on",x===b));G.diff=+b.dataset.v});
$("#sGo").onclick=startGame;

G.co=true;
async function startGame(){PREV.stop=true;return startCompany()}
const DUR_W=[0,650,260,80],DUR_C=[0,150000,30000,5000];let DUR=DUR_W;let acc=0,lastT=0,lastMonth=-1;
const ERR={};
function guard(name,f){try{f()}catch(e){console.error(name,e);if(!ERR[name]){ERR[name]=1;toast("bad","Збій модуля: "+name,(e&&e.message||String(e)).slice(0,140)+" — гра продовжується")}}}
/* frame pacing: full rate only while the camera moves; the game running caps at 30 fps (20 in eco); a still, paused map redraws a few times a second */
let REDRAW=true,LAST_DRAW=0,CAM_KEY="",ANIM_T=0;
["pointermove","pointerdown","wheel","keydown","click"].forEach(ev=>addEventListener(ev,()=>{REDRAW=true},{passive:true,capture:true}));
function needDraw(t){if(window.FORCE_RES)return true;
  const moving=Math.abs(Cam.tdist-Cam.dist)>1e-3||Math.abs(Cam.ttx-Cam.tx)>1e-4||Math.abs(Cam.ttz-Cam.tz)>1e-4;
  const k=[Cam.tx,Cam.tz,Cam.dist,Cam.yaw].map(v=>v.toFixed(4)).join()+innerWidth+"x"+innerHeight;const camCh=k!==CAM_KEY;CAM_KEY=k;
  const eco=!!SET.eco,run=G.speed>0&&!modalOpen&&G.me!=null;
  const fast=run&&G.co&&CO.jobs&&CO.jobs.length&&G.speed>=2;let iv=moving||camCh?(eco?33:0):REDRAW?(eco?50:16):run?(eco?50:fast?0:33):(eco?250:125);
  if(G.co&&G.tri&&(SET.wfx??.5)>0)iv=Math.min(iv,eco?66:40); /* water glints need a steady frame rate */
  if(t-LAST_DRAW<iv-1)return false;LAST_DRAW=t;REDRAW=false;return true}
function loop(t){
  requestAnimationFrame(loop);
  const dt=Math.min(250,t-(lastT||t));lastT=t;if(G.me==null||G.speed>0&&!modalOpen)ANIM_T+=dt/1000;
  guard("Симуляція",()=>simStep(dt));
  if(needDraw(t))guard("Рендер мапи",()=>renderFrame(t));
  guard("Стрічка",()=>tickerStep(t));
}
function simStep(dt){
  if(G.me!=null&&G.speed>0&&!modalOpen&&(!G.over||G.observer)){
    acc+=dt;let n=0;
    while(acc>=DUR[G.speed]&&n<4){acc-=DUR[G.speed];n++;SIM=true;try{dayTick()}finally{SIM=false}
      if(G.date.m!==lastMonth){lastMonth=G.date.m;G.histDates.push(shortDate(G.date));if(G.histDates.length>60)G.histDates.shift();if(!UI.busy&&winIdle()){if(UI.win)renderWin();if(UI.sel!=null)renderInsp()}applyMapColors()}
    }
    if(n){updateHUD();if(UI.win==="war"&&UI.warDirty&&!UI.busy&&!modalOpen&&performance.now()-(UI.warT||0)>1500){UI.warDirty=false;UI.warT=performance.now();renderWin()}if((UI.win==="news"||UI.win==="inbox")&&UI.feedDirty&&!UI.busy){UI.feedDirty=false;renderWin()}}
    if(modalOpen)acc=0;
    if(G.co)guard("Рейси",coFrame);
  }
}
addEventListener("resize",()=>{if(UI.win)renderWin()});

/* main menu logo picture (the text logo stays in the markup, hidden) */
{const im=document.querySelector(".sbrand .logoimg");if(im)im.src=LOGO_IMG}
