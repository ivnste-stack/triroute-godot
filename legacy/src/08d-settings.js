/* ================= PAUSE MENU: save / load / settings / exit ================= */
const SET=(()=>{try{return Object.assign({res:0,noTraffic:false,noTips:false,noTicker:false},JSON.parse(localStorage.getItem("pon_settings")||"{}"))}catch(e){return{res:0,noTraffic:false,noTips:false,noTicker:false}}})();SET.sandbox=false; /* «Відкрито все» is replaced by the ×5 progress test switch */
const RES_OPTS=[{v:0,l:"Авто (за екраном)"},{v:1280,l:"HD · 1280×720"},{v:1600,l:"HD+ · 1600×900"},{v:1920,l:"Full HD · 1920×1080"},{v:2560,l:"2K · 2560×1440"},{v:3840,l:"4K · 3840×2160"}];
function renderDpr(){if(SET.eco&&!window.FORCE_RES)return Math.min(devicePixelRatio||1,1,SET.res?SET.res/Math.max(320,innerWidth):1);return SET.res?clamp(SET.res/Math.max(320,innerWidth),.5,4):Math.min(devicePixelRatio||1,1.5)}
function saveSettings(){try{localStorage.setItem("pon_settings",JSON.stringify(SET))}catch(e){}applySettings()}
function applySettings(){const tk=$("#ticker");if(tk)tk.style.visibility=SET.noTicker?"hidden":"";CITY_KEY=""}
const MENU={open:false,view:"main",prevSpeed:0};
(function(){
  const el=document.createElement("div");el.id="menu";el.hidden=true;el.innerHTML=`<div class="mbox glass" id="menuBox" style="width:min(460px,100%)"></div>`;document.body.appendChild(el);
  const st=document.createElement("style");st.textContent=`#sActs{display:grid;grid-template-columns:1fr auto 1fr;gap:10px;align-items:center;margin-top:22px}#sActs .sa{display:flex;gap:10px;min-width:0}#sActs .l{justify-content:flex-end}#sActs .r{justify-content:flex-start}#sGo{height:44px;padding:0 22px}@media (max-width:560px){#sActs{grid-template-columns:1fr}#sActs .sa{justify-content:center}#sGo{order:-1}}#menu{position:fixed;inset:0;z-index:200;display:grid;place-items:center;background:rgba(2,5,9,.62);padding:16px}#menu[hidden]{display:none!important}
   #menu .mitem{display:flex;align-items:center;gap:12px;width:100%;height:46px;padding:0 16px;background:rgba(255,255,255,.035);border:1px solid var(--line-hi);cursor:pointer;font:600 14px/1 var(--f-body);color:var(--fg)}
   #menu .mitem:hover{border-color:var(--accent);background:var(--accent-soft)}#menu .mitem.dng:hover{border-color:var(--bad);background:rgba(240,98,95,.12)}
   #menu .slot{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:12px;border:1px solid var(--line);background:var(--glass-lo)}
   #menu .slot img{width:34px;height:22px;border:1px solid var(--line-hi)}
   #gearBtn{width:44px;flex:none;display:grid;place-items:center;background:none;border:0;border-left:1px solid var(--line);color:var(--fg-2);cursor:pointer}#gearBtn:hover{color:var(--fg);background:var(--accent-soft)}`;document.head.appendChild(st);
  const g=document.createElement("button");g.id="gearBtn";g.setAttribute("data-act","menuOpen");g.setAttribute("aria-label","Меню");g.dataset.tip=T("Меню (Esc)","Збереження, завантаження, налаштування, вихід.");g.innerHTML=ic("menu");$("#bar").appendChild(g);
  {const lb=$("#sLoad");if(lb)lb.disabled=!anySave()}
})();
addEventListener("keydown",e=>{if(e.key!=="Escape")return;
  if(MENU.open){e.stopImmediatePropagation();e.preventDefault();if(MENU.view!=="main"&&G.me!=null){MENU.view="main";renderMenu()}else closeMenu();return}
  if(G.me==null||modalOpen||UI.win||UI.sel!=null||$(".ddlist"))return;
  e.stopImmediatePropagation();e.preventDefault();openMenu();},true);
function openMenu(view="main"){if(!MENU.open){MENU.prevSpeed=G.speed;if(G.me!=null)setSpeed(0)}MENU.open=true;MENU.view=view;$("#menu").hidden=false;renderMenu()}
function closeMenu(){MENU.open=false;$("#menu").hidden=true;if(G.me!=null&&MENU.prevSpeed)setSpeed(MENU.prevSpeed)}
ACT.menuOpen=()=>openMenu();ACT.menuClose=()=>closeMenu();ACT.menuView=v=>{MENU.view=v;renderMenu()};ACT.menuLoad=()=>openMenu("load");ACT.menuSet=()=>openMenu("set");
function slotMeta(i){try{return JSON.parse(localStorage.getItem("pon_meta_"+i)||"null")}catch(e){return null}}
function anySave(){for(const i of ["auto",1,2,3])if(slotMeta(i))return true;return false}
function renderMenu(){
  const b=$("#menuBox"),v=MENU.view,ing=G.me!=null;
  b.style.width=v==="set"?"min(720px,100%)":"min(460px,100%)";
  const head=(icn,eb,t)=>`<div class="mhead"><div class="mic">${ic(icn)}</div><div class="grow"><span class="lbl">${eb}</span><h3>${t}</h3></div><button class="xbtn" data-act="${v==="main"||!ing?"menuClose":"menuView"}" data-arg="main" aria-label="Закрити">${ic("close")}</button></div>`;
  const slots=save=>(save?[1,2,3]:["auto",1,2,3].filter(i=>i!=="auto"||slotMeta(i))).map(i=>{const m=slotMeta(i);return `<div class="slot"><div class="row" style="min-width:0">${m?`<img src="${m.flag}" alt="">`:`<span class="mut">${ic("doc")}</span>`}<div style="min-width:0"><b>${i==="auto"?"Автозбереження · ":""}${m?esc(m.name):"Порожній слот "+i}</b><div class="note">${m?`${esc(m.mode)} · ${esc(m.date)} · збережено ${esc(m.when)}`:"Немає збереження"}</div></div></div>
     <div class="row">${save?`<button class="btn sm pri" data-act="doSave" data-arg="${i}">${m?"Перезаписати":"Зберегти"}</button>`:`<button class="btn sm pri" data-act="doLoad" data-arg="${i}" ${m?"":"disabled"}>Завантажити</button>`}${m?`<button class="btn sm" data-act="delSave" data-arg="${i}" aria-label="Видалити">${ic("trash")}</button>`:""}</div></div>`}).join("");
  if(v==="main")b.innerHTML=head("menu","Пауза · "+(G.me!=null?dateStr(G.date):""),"Меню")+`<div class="mb">
    <button class="mitem" data-act="menuClose">${ic("play","fill")}Продовжити</button>
    <button class="mitem" data-act="menuView" data-arg="save">${ic("doc")}Зберегти гру</button>
    <button class="mitem" data-act="menuView" data-arg="load">${ic("refresh")}Завантажити гру</button>
    <button class="mitem" data-act="menuView" data-arg="set">${ic("gear")}Налаштування</button>
    <button class="mitem dng" data-act="menuView" data-arg="exit">${ic("close")}Вийти в головне меню</button>
    <button class="mitem" data-act="diagOpen">${ic("doc")}Журнал діагностики · F8</button>
    <div class="note">Esc — відкрити або закрити меню.</div></div>`;
  if(v==="save")b.innerHTML=head("doc","Збереження","Зберегти гру")+`<div class="mb">${slots(true)}<div class="note">Гра зберігається в цьому браузері. Світ відтворюється із зерна, тому збереження компактні.</div></div>`;
  if(v==="load")b.innerHTML=head("refresh","Завантаження","Завантажити гру")+`<div class="mb">${slots(false)}${ing?`<div class="note">Поточний незбережений прогрес буде втрачено.</div>`:""}</div>`;
  if(v==="set")b.innerHTML=head("gear","Налаштування","Графіка та інтерфейс")+`<div class="mb">
    <div><div class="row sp"><span class="lbl">Гучність музики</span><span class="num" id="musVolV">${Math.round((SET.musVol??.6)*100)}%</span></div><input class="rng" type="range" min="0" max="100" step="1" value="${Math.round((SET.musVol??.6)*100)}" data-live="musVol" style="width:100%;margin-top:8px" aria-label="Гучність музики"><div class="note" style="margin-top:6px">Для музики в меню і в грі. 0% — тиша.</div></div>
    <div><div class="row sp"><span class="lbl">Відблиски на воді (тест)</span><span class="num" id="wfxV">${Math.round((SET.wfx??.5)*100)}%</span></div><input class="rng" type="range" min="0" max="100" step="5" value="${Math.round((SET.wfx??.5)*100)}" data-live="wfx" style="width:100%;margin-top:8px" aria-label="Відблиски на воді"><div class="note" style="margin-top:6px">Окремі трикутники води переливаються, ніби на сонці. 0% — вимкнено (мапа менше навантажує відеокарту).</div></div>
    <div><span class="lbl">Роздільна здатність рендеру мапи</span><div style="margin-top:8px">${dd("setRes",RES_OPTS.map(o=>({v:o.v,l:o.l,ic:"layers"})),SET.res,v=>{SET.res=+v;saveSettings();renderMenu()})}</div>
     <div class="note" style="margin-top:6px">Зараз мапа рендериться у ${Math.round(innerWidth*renderDpr())}×${Math.round(innerHeight*renderDpr())} пікселів. 2K і 4K — максимальна чіткість кордонів і тексту на великих екранах, але більше навантаження на відеокарту.</div><div class="note" style="margin-top:6px">${ic("eye")} Скріншот мапи для геймплейних фото: <b>F2</b> (змінюється у вкладці «Керування») або <b>Ctrl+Shift+S</b>. У кадр потрапляє лише мапа з увімкненими шарами.</div></div>
    <div class="setgrid">${[["fastprog","Пришвидшений прогрес ×5 (тест)","Досвід, кількість доставок і контрактів та виручка з доставок рахуються вп'ятеро швидше, рейтинг росте втричі швидше — щоб швидко пройти грейди й ліцензії"],["eco","Енергозбереження","Менше кадрів на секунду і нижча роздільна здатність мапи — карта менше гріє ноутбук"],["roadGab","Тестова генерація доріг","Граф Габріеля по всій суші + A* з повторним використанням доріг і штрафом за поворот. Діє для нової гри"],["noMusic","Музика в головному меню","Грає в меню та під час створення світу, плавно стихає, коли мапа готова"],["noGameMusic","Музика в грі","Фонові треки під час гри: у перемішку, без частих повторів"],["noTips","Підказки при наведенні","Пояснення показників"],["noTicker","Бігуча стрічка новин","Внизу екрана"]].map(([k,n,d])=>`<div class="setcell"><div style="min-width:0"><b>${n}</b><div class="note">${d}</div></div><button class="tg ${(k.startsWith("no")?SET[k]:!SET[k])?"":"on"}" data-act="setTg" data-arg="${k}" aria-label="${n}"></button></div>`).join("")}</div></div>`;
  if(v==="exit")b.innerHTML=head("close","Вихід","Вийти в головне меню?")+`<div class="mb"><p>Незбережений прогрес буде втрачено.</p>
    <button class="mitem" data-act="saveExit">${ic("doc")}Спершу зберегти</button><button class="mitem dng" data-act="doExit">${ic("close")}Вийти без збереження</button><button class="mitem" data-act="menuView" data-arg="main">Скасувати</button></div>`;
  fillRanges(b);
}
ACT.setTg=k=>{SET[k]=!SET[k];saveSettings();renderMenu();if(k==="sandbox"&&typeof coSandbox==="function")coSandbox(true)};
addEventListener("keydown",e=>{if(e.key==="Escape"){const m=$("#ngModal");if(m&&!m.hidden&&!MENU.open){m.hidden=true;e.stopImmediatePropagation()}}},true);
ACT.ngOpen=()=>{$("#ngModal").hidden=false};ACT.ngClose=()=>{$("#ngModal").hidden=true};
ACT.appExit=()=>{try{window.close()}catch(e){}setTimeout(()=>{queueModal({icon:"close",eyebrow:"Вихід",title:"Гру можна закрити разом із вкладкою",body:"<p>Браузер не дозволяє сторінці закрити себе. Прогрес збережених ігор лишається в цьому браузері.</p>",choices:[{t:"Зрозуміло",d:"",f(){}}]})},150)};
ACT.doExit=()=>{try{location.reload()}catch(e){}};
ACT.delSave=i=>{try{localStorage.removeItem("pon_save_"+i);localStorage.removeItem("pon_meta_"+i)}catch(e){}$("#sLoad").disabled=!anySave();renderMenu()};

/* ---------- serialisation ---------- */
function enc(v){if(v==null||typeof v!=="object")return typeof v==="number"&&!isFinite(v)?0:v;
  if(ArrayBuffer.isView(v)){const fl=v instanceof Float32Array||v instanceof Float64Array;return{__ta:v.constructor.name,d:fl?Array.from(v,x=>Math.round(x*1e4)/1e4):Array.from(v)}}
  if(v instanceof Set)return{__set:[...v].map(enc)};if(v instanceof Map)return{__map:[...v].map(([k,x])=>[k,enc(x)])};if(Array.isArray(v))return v.map(enc);
  const o={};for(const k in v){if(typeof v[k]!=="function")o[k]=enc(v[k])}return o}
function dec(v){if(v==null||typeof v!=="object")return v;if(Array.isArray(v))return v.map(dec);
  if(v.__ta)return new ({Float32Array,Float64Array,Int8Array,Uint8Array,Int16Array,Uint16Array,Int32Array}[v.__ta])(v.d);if(v.__set)return new Set(v.__set.map(dec));if(v.__map)return new Map(v.__map.map(([k,x])=>[k,dec(x)]));
  const o={};for(const k in v)o[k]=dec(v[k]);return o}
const G_SKIP=new Set(["world","P","provAt","provPix","bpt","nukeFx","tq","resolutions","orgs"]);
function saveWrite(i){const g={};for(const k in G)if(!G_SKIP.has(k))g[k]=enc(G[k]);
    const S={v:2,seed:SEED,co:true,board:true,earth:!!G.earth,wmod:G.wmod?edSerialize():null,CO:enc(CO),N:G.genN||34,diff:G.diff,G:g,misc:{mode:UI.mode}};
    const meta={name:CO.name,flag:CO.logo,date:dateStr(G.date),mode:"Логістична компанія",when:new Date().toLocaleString("uk-UA",{day:"2-digit",month:"2-digit",hour:"2-digit",minute:"2-digit"})};
    localStorage.setItem("pon_save_"+i,JSON.stringify(S));localStorage.setItem("pon_meta_"+i,JSON.stringify(meta));return meta}
/* autosave every 15 minutes of play into its own slot (shown first under «Завантажити») */
setInterval(()=>{try{if(!G.co||G.me==null||!CO.hubs||LP.on||SR.on||MENU.open)return;const m=saveWrite("auto");toast("","Автозбереження",m.date);const b=$("#sLoad");if(b)b.disabled=false}catch(e){}},15*60*1000);
ACT.doSave=i=>{
  try{const meta=saveWrite(i);
    toast("good","Гру збережено",`Слот ${i} · ${meta.date}`);$("#sLoad").disabled=false;MENU.view="main";renderMenu();
  }catch(e){console.error(e);toast("bad","Не вдалося зберегти",/quota/i.test(e.message||e.name)?"Недостатньо місця в сховищі браузера":"Сховище браузера недоступне")}
};
ACT.doLoad=i=>{if(G.me!=null){try{sessionStorage.setItem("pon_autoload",String(i));location.reload();return}catch(e){}}closeMenu();loadGame(+i)};
async function loadGame(i){PREV.stop=true;
  let S;try{S=JSON.parse(localStorage.getItem("pon_save_"+i))}catch(e){}if(!S)return toast("bad","Збереження не знайдено","Слот порожній або пошкоджений");
  $("#start").hidden=true;$("#loading").hidden=false;const prog=(p,t)=>{$("#loadBar").style.width=(p*100).toFixed(0)+"%";$("#loadTxt").textContent=t};
  if(S.board){if(typeof coBgUse==="function")coBgUse(true);SEED=S.seed;G.loadW=S.wmod||null;G.earth=!!S.earth;G.mapSize=S.G&&S.G.mapSize||"legacy";G.diff=S.diff;G.C=dec(S.G.C);for(const k in S.G)if(k!=="orgs"&&k!=="resolutions")G[k]=dec(S.G[k]);G.loadW=S.wmod||null;G.orgs=[];G.resolutions=[];
    await startBoard(true);Object.assign(CO,dec(S.CO));coMigrate();CO.jobs.forEach(j=>delete j._c);coPlaces();buildHUD();coWho();UI.picking=false;$("#insp").hidden=true;applySettings();updateHUD();updateLegend();G.speed=0;
    toast("good","Гру завантажено",`${CO.name} · ${dateStr(G.date)}`);return}
  $("#loading").hidden=true;$("#start").hidden=false;toast("warn","Збереження не підтримується","Це збереження зі старих режимів гри, яких більше немає");
}
applySettings();
setTimeout(()=>{let a=null;try{a=sessionStorage.getItem("pon_autoload");sessionStorage.removeItem("pon_autoload")}catch(e){}if(a)loadGame(+a)},50);

/* ---------- start-screen background: one fixed generated world, saved once as an image ---------- */
const PREV={stop:false};
function stopPreview(){PREV.stop=true;Cam.yaw=0}
function endPreview(){PREV.stop=true;document.body.classList.remove("preview");const im=$("#bgSnap");if(im)im.hidden=true}
(function(){
  const st=document.createElement("style");st.textContent=`#bgSnap{position:fixed;left:50%;top:-24px;width:120vw;height:calc(100vh + 48px);object-fit:cover;filter:blur(6px) brightness(.9);pointer-events:none;opacity:0;transition:opacity .8s;animation:bgPan 48s ease-in-out infinite alternate;will-change:transform}
   #bgSnap.on{opacity:1}@keyframes bgPan{from{transform:translateX(-56%)}to{transform:translateX(-44%)}}#bgSnap{transform:translateX(-50%)}
   body.preview #gl,body.preview #overlay{opacity:0}@media (prefers-reduced-motion:reduce){#bgSnap{animation:none}}`;document.head.appendChild(st);
  const im=document.createElement("img");im.id="bgSnap";im.alt="";document.body.insertBefore(im,document.body.firstChild);document.body.classList.add("preview");
  const show=src=>{if(window.BG_CO)return;im.onload=()=>im.classList.add("on");im.src=src};
  let src=null;try{src=localStorage.getItem("pon_bg5")}catch(e){}
  if(src){show(src);return}
  setTimeout(async()=>{let a=null;try{a=sessionStorage.getItem("pon_autoload")}catch(e){}if(a||PREV.stop||G.me!=null)return;
    let w;try{w=await genWorld(20260101,30,()=>{},{abort:()=>PREV.stop||$("#start").hidden})}catch(e){return}if(PREV.stop||G.me!=null||$("#start").hidden)return;
    G.world=w;initGL(w);const cols=[];w.countries.forEach((c,i)=>{const nc=new Set(c.neighbors.map(j=>cols[j]).filter(Boolean));const opts=COUNTRY_COLS.filter(x=>!nc.has(x));cols[i]=opts[i%Math.max(1,opts.length)]||COUNTRY_COLS[i%COUNTRY_COLS.length]});
    setMapColors(cols.map(hex3));window.FORCE_RES=[3840,2160];Cam.tdist=Cam.dist=16.5;Cam.ttx=Cam.tx=0;Cam.ttz=Cam.tz=.45;Cam.yaw=0;
    requestAnimationFrame(()=>requestAnimationFrame(t=>{if(PREV.stop)return;guard("Фон",()=>{renderFrame(t);drawBorders();
      window.FORCE_RES=null;const a=$("#gl"),o=$("#bcv"),f=document.createElement("canvas");f.width=a.width;f.height=a.height;const fg=f.getContext("2d");fg.drawImage(a,0,0);fg.drawImage(o,0,0,a.width,a.height);const c=document.createElement("canvas"),wd=2560;c.width=wd;c.height=Math.round(a.height*wd/a.width);const g=c.getContext("2d");g.imageSmoothingQuality="high";if("filter" in g)g.filter="blur(7px)";g.drawImage(f,0,0,c.width,c.height);
      const d=c.toDataURL("image/jpeg",.8);try{localStorage.setItem("pon_bg5",d);["pon_bg","pon_bg2","pon_bg3","pon_bg4"].forEach(k=>localStorage.removeItem(k));localStorage.removeItem("pon_bg")}catch(e){}show(d)})}));
  },150);
})();

/* «Спершу зберегти» from the exit dialog: save into a slot, then leave to the main menu */
ACT.saveExit=()=>{MENU.exitAfter=true;MENU.view="save";renderMenu()};
{const _ds=ACT.doSave;ACT.doSave=i=>{const before=localStorage.getItem("pon_meta_"+i);_ds(i);if(MENU.exitAfter){const after=localStorage.getItem("pon_meta_"+i);MENU.exitAfter=false;if(after&&after!==before||after){setTimeout(()=>ACT.doExit(),600)}}}}
{const _mv=ACT.menuView;ACT.menuView=v=>{if(v!=="save")MENU.exitAfter=false;_mv(v)}}

ACT.wfx=v=>{SET.wfx=clamp(+v/100,0,1);{const l=$("#wfxV");if(l)l.textContent=Math.round(SET.wfx*100)+"%"}REDRAW=true;clearTimeout(ACT.wfx.t);ACT.wfx.t=setTimeout(saveSettings,300)};
