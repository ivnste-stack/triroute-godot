/* =====================================================================
   Controls: key bindings (Settings → «Керування»). Keys are matched by physical position
   (KeyboardEvent.code), so they work the same on the Ukrainian and English layouts.
   ===================================================================== */
const KEYS_DEF=[
 ["Шари мапи",[["lay_co","Мережа компанії","Digit1"],["lay_grid","Логістичні шляхи","Digit2"],["lay_risk","Ризики перевезень","Digit3"],["lay_pol","Політична","Digit4"],["lay_dem","Світовий попит","Digit5"]]],
 ["Вікна",[["w_coHome","Компанія","KeyC"],["w_coJobs","Біржа вантажів","KeyO"],["w_coTrips","Рейси в дорозі","KeyR"],["w_coFleet","Автопарк","KeyV"],["w_coFin","Фінанси","KeyF"],["w_coNet","Мережа хабів","KeyH"],["w_coStaff","Персонал і менеджмент","KeyP"],["w_news","Новини","KeyN"]]],
 ["Мапа",[["names","Приховати або показати назви всіх міст","KeyL"],["shot","Скріншот мапи","F2"]]]];
const KEYS_FIXED=[["Пауза / продовжити","Space"],["Журнал діагностики","F8"],["Рух камери","W A S D / стрілки"],["Поворот камери","Q / E"],["Закрити вікно, меню","Esc"]];
let KEYS={};function keysLoad(){KEYS={};for(const [,L] of KEYS_DEF)for(const [id,,k] of L)KEYS[id]=k;try{Object.assign(KEYS,JSON.parse(localStorage.getItem("pon_keys")||"{}"))}catch(e){}}
function keysSave(){try{localStorage.setItem("pon_keys",JSON.stringify(KEYS))}catch(e){}}
keysLoad();
const keyName=c=>!c?"—":c.startsWith("Key")?c.slice(3):c.startsWith("Digit")?c.slice(5):c.startsWith("Numpad")?"Num "+c.slice(6):({Space:"Пробіл",Minus:"-",Equal:"=",BracketLeft:"[",BracketRight:"]",Semicolon:";",Quote:"'",Comma:",",Period:".",Slash:"/",Backslash:"\\",Backquote:"`",Tab:"Tab",Enter:"Enter"})[c]||c;
const KEYS_BUSY=new Set(["KeyW","KeyA","KeyS","KeyD","KeyQ","KeyE","Space","Escape","ArrowUp","ArrowDown","ArrowLeft","ArrowRight"]);
let KEY_WAIT=null;
function keysAct(id){if(id==="shot")return guard("Скріншот",takeShot);
  if(id==="names"){UI.hideNames=!UI.hideNames;document.body.classList.toggle("nonames",UI.hideNames);REDRAW=true;toast("",UI.hideNames?"Назви міст сховано":"Назви міст показано",`Клавіша ${keyName(KEYS.names)}`);return}
  if(id.startsWith("lay_")){if(!G.co)return;const m=id.slice(4);ACT.mode(m);if(typeof buildModeDD==="function")buildModeDD();return}
  if(id.startsWith("w_")){const w=id.slice(2);if(!WINS[w])return;if(UI.win===w)closeWin();else openWin(w)}}
addEventListener("keydown",e=>{
  if(KEY_WAIT){e.preventDefault();e.stopImmediatePropagation();const id=KEY_WAIT;KEY_WAIT=null;
    if(e.code==="Escape"){renderMenu();return}if(e.code==="Backspace"||e.code==="Delete"){KEYS[id]="";keysSave();renderMenu();return}
    if(KEYS_BUSY.has(e.code)){toast("warn","Клавіша зайнята",`${keyName(e.code)} керує камерою або паузою`);renderMenu();return}
    for(const k in KEYS)if(KEYS[k]===e.code&&k!==id)KEYS[k]="";KEYS[id]=e.code;keysSave();renderMenu();return}
  if(e.ctrlKey||e.metaKey||e.altKey)return;const t=e.target;if(t&&(t.tagName==="INPUT"||t.tagName==="TEXTAREA"||t.isContentEditable))return;
  if(G.me==null||MENU.open||modalOpen||($("#start")&&!$("#start").hidden))return;
  for(const id in KEYS)if(KEYS[id]&&KEYS[id]===e.code){e.preventDefault();keysAct(id);return}},true);
/* settings: two tabs — interface and controls */
function keysHTML(){return `<div class="kbind">${KEYS_DEF.map(([g,L])=>`<span class="lbl" style="display:block;margin:12px 0 6px">${g}</span><div class="kgrid">${L.map(([id,n])=>`<div class="kcell"><span>${n}</span><button class="btn sm kbtn ${KEY_WAIT===id?"pri":""}" data-act="keyBind" data-arg="${id}">${KEY_WAIT===id?"Натисніть клавішу…":keyName(KEYS[id])}</button></div>`).join("")}</div>`).join("")}
  <span class="lbl" style="display:block;margin:14px 0 6px">Постійні клавіші</span><div class="kgrid">${KEYS_FIXED.map(([n,k])=>`<div class="kcell"><span>${n}</span><span class="pill">${k}</span></div>`).join("")}</div>
  <div class="row sp wrap" style="margin-top:12px;gap:8px"><span class="note">Клік по клавіші, потім натисніть нову. Backspace — зняти призначення, Esc — скасувати.</span><button class="btn sm" data-act="keyReset">${ic("refresh")}Скинути</button></div></div>`}
ACT.keyBind=id=>{KEY_WAIT=id;renderMenu()};
ACT.keyReset=()=>{try{localStorage.removeItem("pon_keys")}catch(e){}keysLoad();renderMenu();toast("good","Клавіші скинуто","Стандартне призначення")};
ACT.setTab=t=>{MENU.setTab=t;KEY_WAIT=null;renderMenu()};
{const _rm=renderMenu;renderMenu=function(){_rm();if(MENU.view!=="set")return;const b=$("#menuBox"),mb=b&&b.querySelector(".mb");if(!mb)return;const tab=MENU.setTab||"gfx";
  const seg=`<div class="seg" style="margin-bottom:12px"><button class="${tab==="gfx"?"on":""}" data-act="setTab" data-arg="gfx">${ic("layers")} Графіка та інтерфейс</button><button class="${tab==="ctl"?"on":""}" data-act="setTab" data-arg="ctl">${ic("gear")} Керування</button></div>`;
  if(tab==="ctl"){mb.innerHTML=seg+`<span class="lbl" style="display:block;font-size:12px">Призначення клавіш</span>`+keysHTML();const h=b.querySelector(".mhead h3");if(h)h.textContent="Керування"}else mb.insertAdjacentHTML("afterbegin",seg)}}

/* Space only pauses and resumes: never clicks a focused button or scrolls a window */
addEventListener("keydown",e=>{if(e.code!=="Space"||e.ctrlKey||e.metaKey||e.altKey)return;const t=e.target;if(t&&(t.tagName==="INPUT"||t.tagName==="TEXTAREA"||t.isContentEditable))return;
  e.preventDefault();e.stopImmediatePropagation();if(e.repeat)return;if(document.activeElement&&document.activeElement!==document.body)document.activeElement.blur();
  if(G.me==null||MENU.open||modalOpen||ED.on||($("#start")&&!$("#start").hidden))return;setSpeed(G.speed?0:G.lastSpeed||1)},true);
addEventListener("keyup",e=>{if(e.code==="Space"&&!(e.target&&(e.target.tagName==="INPUT"||e.target.tagName==="TEXTAREA")))e.preventDefault()},true);
