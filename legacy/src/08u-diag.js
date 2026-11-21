/* =====================================================================
   Diagnostics log (F8 or menu «Журнал діагностики»).
   Every click, window, speed change, error, frozen frame and a 2-second heartbeat (fps, memory, canvases, trips)
   is kept in localStorage, so it survives a crashed tab. A session that did not end cleanly is detected on the
   next start and its log is offered for copying.
   ===================================================================== */
const DIAG={log:[],prev:null,crashed:false,max:900,dirty:false,t:0,frames:0,fmax:0,fsum:0,lastF:0,open:false};
const diagLS=(k,v)=>{try{if(v===undefined)return localStorage.getItem(k);if(v===null)localStorage.removeItem(k);else localStorage.setItem(k,v)}catch(e){return null}};
function diagNow(){const d=new Date();return d.toTimeString().slice(0,8)+"."+String(d.getMilliseconds()).padStart(3,"0")}
function diagCtx(){try{if(G.me==null)return "меню";return `д${(G.day+(CO.lastFr||0)).toFixed(2)} ×${G.speed}`}catch(e){return "?"}}
function diagFlush(){DIAG.dirty=false;diagLS("pon_diag",JSON.stringify(DIAG.log));diagLS("pon_diag_run",JSON.stringify({start:DIAG.t,last:Date.now()}))}
function diag(kind,msg,now){DIAG.log.push(`${diagNow()} [${diagCtx()}] ${kind.padEnd(6)} ${String(msg).slice(0,400)}`);if(DIAG.log.length>DIAG.max)DIAG.log.splice(0,DIAG.log.length-DIAG.max);
  if(now)diagFlush();else if(!DIAG.dirty){DIAG.dirty=true;setTimeout(diagFlush,300)}if(DIAG.open)diagRender()}
/* the previous session: crashed if its run marker is still there */
(function(){const run=diagLS("pon_diag_run"),old=diagLS("pon_diag");if(run&&old){try{DIAG.prev=JSON.parse(old);const r=JSON.parse(run);DIAG.crashed=true;DIAG.prevInfo=`почалася ${new Date(r.start).toLocaleString("uk-UA")}, останній запис ${new Date(r.last).toLocaleString("uk-UA")}`;diagLS("pon_diag_prev",old);diagLS("pon_diag_previnfo",DIAG.prevInfo)}catch(e){}}
  else{const p=diagLS("pon_diag_prev");if(p){try{DIAG.prev=JSON.parse(p);DIAG.prevInfo=diagLS("pon_diag_previnfo")||""}catch(e){}}}
  DIAG.t=Date.now();diag("старт",`TriRoute · ${navigator.userAgent} · екран ${screen.width}×${screen.height} ×${devicePixelRatio} · вікно ${innerWidth}×${innerHeight}${DIAG.crashed?" · попередня сесія завершилась аварійно":""}`,true);
  addEventListener("pagehide",()=>{diag("вихід","сторінку закрито нормально");diagFlush();diagLS("pon_diag_run",null)});
  if(DIAG.crashed)setTimeout(()=>toast("bad","Попередня сесія завершилась аварійно","Натисніть, щоб відкрити журнал діагностики (F8) і скопіювати його",()=>diagOpen(true)),1500)})();
/* errors */
addEventListener("error",e=>diag("ПОМИЛКА",`${e.message} @ ${(e.filename||"").split("/").pop()}:${e.lineno}:${e.colno}`,true));
addEventListener("unhandledrejection",e=>diag("ПОМИЛКА","promise: "+(e.reason&&e.reason.message||e.reason),true));
{const _g=guard;guard=function(name,f){return _g(name,()=>{try{return f()}catch(e){diag("ПОМИЛКА",`${name}: ${e&&e.message} | ${(e&&e.stack||"").split("\n").slice(1,3).join(" ").trim()}`,true);throw e}})}}
/* what the player does */
document.addEventListener("click",e=>{const a=e.target.closest&&e.target.closest("[data-act]");if(a)diag("клік",`${a.dataset.act}${a.dataset.arg!=null?"("+a.dataset.arg+")":""} «${(a.textContent||"").trim().slice(0,40)}»`,true);
  else if(e.target&&e.target.id==="gl"||e.target&&e.target.closest&&e.target.closest("#overlay"))diag("клік","мапа "+e.clientX+","+e.clientY,true)},true);
{let wt=0;addEventListener("wheel",e=>{const t=performance.now();if(t-wt<800)return;wt=t;diag("зум",`${e.deltaY>0?"віддалення":"наближення"} · камера ${typeof Cam!=="undefined"?Cam.dist.toFixed(2)+"→"+Cam.tdist.toFixed(2):"?"}`)},{passive:true,capture:true})}
addEventListener("resize",()=>diag("вікно",`розмір ${innerWidth}×${innerHeight} ×${devicePixelRatio}`));
{const cv=document.getElementById("gl");if(cv){cv.addEventListener("webglcontextlost",()=>diag("ПОМИЛКА","WebGL: контекст відеокарти втрачено",true));cv.addEventListener("webglcontextrestored",()=>diag("відео","WebGL: контекст відновлено",true))}
  try{const gl=cv&&cv.getContext("webgl2"),x=gl&&gl.getExtension("WEBGL_debug_renderer_info");if(gl)diag("відео",`${x?gl.getParameter(x.UNMASKED_RENDERER_WEBGL):gl.getParameter(gl.RENDERER)} · макс. текстура ${gl.getParameter(gl.MAX_TEXTURE_SIZE)}`)}catch(e){}}
addEventListener("keydown",e=>{if(e.repeat)return;if(e.target&&/INPUT|TEXTAREA/.test(e.target.tagName))return;diag("клав",e.code)},true);
{const _o=openWin;openWin=function(id){diag("вікно","відкрито "+id);return _o(id)}}
{const _c=closeWin;closeWin=function(){if(UI.win)diag("вікно","закрито "+UI.win);return _c.apply(this,arguments)}}
{const _s=setSpeed;setSpeed=function(i){diag("швидк",`${G.speed} → ${i}`);return _s(i)}}
{const _q=queueModal;queueModal=function(m){diag("модал",(m&&m.title||"").slice(0,80));return _q(m)}}
{const _t=toast;toast=function(tone,t,d,f){if(t!=="Попередня сесія завершилась аварійно")diag("тост",`${t} · ${String(d||"").replace(/<[^>]+>/g,"").slice(0,120)}`);return _t(tone,t,d,f)}}
{const _lo=lpOpen;lpOpen=function(k,post){diag("план",`відкрито: ${post?"пошта":k?`${PL[k.from].name} → ${PL[k.to].name}, ${k.tons} т, ${k.legs?k.legs.map(L=>L.m).join(">"):k.mode}`:"?"}`,true);return _lo.apply(this,arguments)}}
{const _lc=lpClose;lpClose=function(){diag("план","закрито");return _lc()}}
{const _d=coDispatch;coDispatch=function(k,P,s){diag("рейс",`відправлено ${PL[k.from].name} → ${PL[k.to].name} (${P&&P.chain?"ланцюжок "+P.chain.length:P&&P.t})`);return _d(k,P,s)}}
{const _cc=coCard;coCard=function(){const j=CO_SEL;if(j&&DIAG.lastCard!==j.id){DIAG.lastCard=j.id;diag("картка",`рейс №${j.id} ${j.mode}${j.ret?" (повернення)":""}${j.lp?" ділянка "+(j.lp.i+1)+"/"+j.lp.plan.length:""} стеження=${!!CO.follow}`)}return _cc()}}
/* frames: frozen ones are logged immediately, the rest goes into the heartbeat */
(function fr(t){requestAnimationFrame(fr);if(DIAG.lastF){const d=t-DIAG.lastF;DIAG.frames++;DIAG.fsum+=d;if(d>DIAG.fmax)DIAG.fmax=d;if(d>700&&!document.hidden)diag("ЗАВИС",`кадр ${Math.round(d)} мс`,true)}DIAG.lastF=t})(0);
try{new PerformanceObserver(l=>{for(const e of l.getEntries())if(e.duration>400)diag("ДОВГО",`завдання ${Math.round(e.duration)} мс`,true)}).observe({entryTypes:["longtask"]})}catch(e){}
setInterval(()=>{if(document.hidden)return;const n=DIAG.frames||1,cv=["gl","bcv","vcv"].map(id=>{const c=document.getElementById(id);return c?`${id} ${c.width}×${c.height}`:""}).filter(Boolean).join(", ");
  let g="";try{if(G.me!=null)g=` · рейсів ${CO.jobs.length} · біржа ${CO.board.length} · техніка ${CO.veh.length} · перекриттів ${JAM.length} · план ${LP.on?"так":"ні"} · стеження ${CO.follow&&CO_SEL?"№"+CO_SEL.id:"ні"} · камера ${Cam.dist.toFixed(1)} · вікно ${UI.win||"—"}`}catch(e){}
  const mem=performance.memory?` · пам'ять ${Math.round(performance.memory.usedJSHeapSize/1e6)}/${Math.round(performance.memory.jsHeapSizeLimit/1e6)} МБ`:"";
  diag("пульс",`${(n/2).toFixed(0)} к/с · кадр сер ${(DIAG.fsum/n).toFixed(0)} мс, макс ${DIAG.fmax.toFixed(0)} мс${mem} · DOM ${document.getElementsByTagName("*").length} · ${cv} · dpr ${typeof renderDpr==="function"?renderDpr().toFixed(2):"?"}${g}`,true);
  DIAG.frames=0;DIAG.fsum=0;DIAG.fmax=0},2000);
/* the console */
function diagText(){return (DIAG.prev?`=== Попередня сесія${DIAG.crashed?" (АВАРІЙНО)":""}: ${DIAG.prevInfo||""} ===\n${DIAG.prev.join("\n")}\n\n`:"")+`=== Поточна сесія ===\n${DIAG.log.join("\n")}`}
function diagRender(){const el=document.getElementById("diagBox");if(!el)return;const pre=el.querySelector("pre");const atEnd=pre.scrollTop+pre.clientHeight>=pre.scrollHeight-20;pre.textContent=diagText();if(atEnd)pre.scrollTop=pre.scrollHeight}
function diagOpen(prevFirst){let el=document.getElementById("diagBox");if(el){el.remove();DIAG.open=false;return}DIAG.open=true;el=document.createElement("div");el.id="diagBox";el.className="glass";
  el.style.cssText="position:fixed;z-index:200;left:50%;top:84px;bottom:86px;transform:translateX(-50%);width:min(980px,calc(100vw - 32px));display:flex;flex-direction:column;padding:14px;gap:10px";
  el.innerHTML=`<div class="row sp"><b style="font-size:15px">${ic("doc")} Журнал діагностики</b><button class="xbtn" data-act="diagClose" aria-label="Закрити">${ic("close")}</button></div>
   <div class="note">Гра записує кліки, вікна, швидкість, помилки, зависання кадрів і стан кожні 2 с. Журнал зберігається навіть після вильоту вкладки: відкрийте гру знову, натисніть F8 і скопіюйте текст.${DIAG.crashed?` <b class="bad">Попередня сесія завершилась аварійно — її журнал угорі.</b>`:""}</div>
   <div class="row" style="gap:6px;flex-wrap:wrap"><button class="btn sm pri" data-act="diagCopy">${ic("doc")}Скопіювати</button><button class="btn sm" data-act="diagSave">${ic("down")}Завантажити .txt</button><button class="btn sm" data-act="diagClear">${ic("trash")}Очистити</button></div>
   <pre style="flex:1;min-height:0;overflow:auto;margin:0;padding:10px;background:rgba(4,10,16,.7);border:1px solid var(--line);font:11.5px/1.45 'JetBrains Mono',monospace;white-space:pre-wrap;word-break:break-word;color:#c9d4de;user-select:text"></pre>`;
  document.body.appendChild(el);diagRender();const pre=el.querySelector("pre");pre.scrollTop=prevFirst?0:pre.scrollHeight}
ACT.diagOpen=()=>{if(typeof closeMenu==="function"&&MENU.open)closeMenu();diagOpen()};ACT.diagClose=()=>{const el=document.getElementById("diagBox");if(el)el.remove();DIAG.open=false};
ACT.diagCopy=()=>{const t=diagText();const ok=()=>toast("good","Журнал скопійовано","Вставте його в повідомлення");
  if(navigator.clipboard&&navigator.clipboard.writeText)navigator.clipboard.writeText(t).then(ok,()=>diagSel());else diagSel()};
function diagSel(){const pre=document.querySelector("#diagBox pre");if(!pre)return;const r=document.createRange();r.selectNodeContents(pre);const s=getSelection();s.removeAllRanges();s.addRange(r);try{document.execCommand("copy");toast("good","Журнал скопійовано","Вставте його в повідомлення")}catch(e){toast("","Текст виділено","Натисніть Ctrl+C")}}
ACT.diagSave=()=>{const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([diagText()],{type:"text/plain"}));a.download=`triroute-diag-${new Date().toISOString().slice(0,19).replace(/[:T]/g,"-")}.txt`;document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},1000)};
ACT.diagClear=()=>{DIAG.log=[];DIAG.prev=null;DIAG.crashed=false;diagLS("pon_diag_prev",null);diagLS("pon_diag_previnfo",null);diag("журнал","очищено",true)};
addEventListener("keydown",e=>{if(e.code==="F8"){e.preventDefault();diagOpen()}else if(e.code==="Escape"&&DIAG.open){e.stopImmediatePropagation();ACT.diagClose()}},true);
