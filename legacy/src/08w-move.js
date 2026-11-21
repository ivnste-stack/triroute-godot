/* =====================================================================
   Re-basing a vehicle: the ⇅ button in the fleet window closes the window and shows every city with
   one of your hubs. Clicking one makes it the vehicle's home hub. Only over its own network (road or rail):
   a hub on another continent cannot be reached and is shown greyed out.
   An idle vehicle drives there empty right away; one on a trip goes there after the trip.
   ===================================================================== */
ICONS.updown='<path d="M8 19V5M4.5 8.5 8 5l3.5 3.5M16 5v14M12.5 15.5 16 19l3.5-3.5"/>';
/* icons added after start-up are missing from the SVG sprite: add them */
(function(){const d=document.getElementById("iconDefs");if(!d)return;let s="";for(const k in ICONS)if(!document.getElementById("i-"+k))s+=`<symbol id="i-${k}" viewBox="0 0 24 24">${ICONS[k]}</symbol>`;if(s)d.insertAdjacentHTML("beforeend",s)})();
const MV={on:false,vid:null,ts:[]};
function mvFrom(v){if(v.st!=="trip")return v.loc;const j=CO.jobs.find(x=>x.vids.includes(v.id));return j?j.k.to:v.loc}
function mvTargets(v){const T=VT[v.t],from=mvFrom(v);
  return CO.hubs.map(h=>{const p=PL[h.pid];let why="";if(!modeOK(T.mode,p))why=T.mode==="rail"?"Немає залізничної станції":"Не підходить для цієї техніки";
    else if(h.pid===v.home||(!v.home&&h.pid===v.loc&&v.st!=="trip"))why="Техніка вже приписана сюди";
    else if(h.pid!==from&&!coRoute(T.mode,from,h.pid))why=T.mode==="rail"?"Немає залізничного сполучення":"Інший континент — по дорозі не доїхати";
    else if(hubVehN(h.pid)>=hubVehCap(h))why="Хаб заповнений";return{pid:h.pid,why}})}
ACT.coMove=id=>{const v=CO.veh.find(x=>x.id===+id);if(!v)return;const T=VT[v.t];
  if(T.mode!=="road"&&T.mode!=="rail")return toast("warn","Лише наземна техніка","Переміщувати між хабами можна машини й потяги");
  const ts=mvTargets(v);if(!ts.some(t=>!t.why))return toast("warn","Немає куди перемістити",CO.hubs.length<2?"Відкрийте ще один хаб — тоді техніку можна буде перевести туди":"Усі інші хаби недоступні: інший континент, немає сполучення або вони заповнені");
  closeWin();MV.on=true;MV.vid=v.id;MV.ts=ts;REDRAW=true;
  toast("",`${T.n}: оберіть новий хаб`,"Клікніть на підсвічене місто. Esc — скасувати.")};
function mvClose(){MV.on=false;MV.vid=null;MV.ts=[];REDRAW=true}
function mvApply(v,pid){const T=VT[v.t],h=hubAt(pid);v.home=pid;mvClose();
  if(v.st==="idle"){if(v.loc===pid){toast("good","Приписку змінено",`${T.n} тепер належить хабу ${PL[pid].name}`);return}
    const r=coRoute(T.mode,v.loc,pid);if(!r)return;const fuel=r.len*T.fuel*CO.fuel*fuelK(T.mode);CO.cash-=fuel;CO.m.fuel+=fuel;const tm=r.len/(T.spd*spdK());
    const j={id:CO.uid++,ret:true,k:{id:0,from:v.loc,to:pid,cg:"parcel",tons:0,pay:0,dlDays:1e3,mode:T.mode,risk:0},mode:T.mode,t:v.t,n:1,vids:[v.id],p:r.p,lead:0,len:r.len,tl:0,tm,hs:0,cust:0,tot:tm,t0:coNow(),dl:G.day+1e3,dmg:0,lost:false,hold:0,ev:[]};
    v.st="trip";v.job=j.id;v.idle0=null;CO.jobs.push(j);toast("good","Техніка їде в новий хаб",`${T.n}: ${PL[j.k.from].name} → ${PL[pid].name} · ${kmS(r.len)} км · ${daysS(tm)} · пальне ${fmtUSD(fuel)}`)}
  else toast("good","Приписку змінено",`${T.n} після поточного рейсу поїде в хаб ${PL[pid].name}`)}
/* returns: a vehicle with a home hub goes there, not to the nearest one */
{const _r=coReturns;coReturns=function(){for(const v of CO.veh){if(v.home==null||v.st!=="idle"||v.loc===v.home||hubAt(v.loc))continue; /* parked at a hub: stays until sent */
    const h=hubAt(v.home);if(!h){v.home=null;continue}
    if(v.idle0==null||coNow()-v.idle0<1)continue;const T=VT[v.t],r=coRoute(T.mode,v.loc,v.home);if(!r||hubVehN(v.home)>=hubVehCap(h))continue;
    const fuel=r.len*T.fuel*CO.fuel*fuelK(T.mode);CO.cash-=fuel;CO.m.fuel+=fuel;const tm=r.len/(T.spd*spdK());
    const j={id:CO.uid++,ret:true,k:{id:0,from:v.loc,to:v.home,cg:"parcel",tons:0,pay:0,dlDays:1e3,mode:T.mode,risk:0},mode:T.mode,t:v.t,n:1,vids:[v.id],p:r.p,lead:0,len:r.len,tl:0,tm,hs:0,cust:0,tot:tm,t0:coNow(),dl:G.day+1e3,dmg:0,lost:false,hold:0,ev:[]};
    v.st="trip";v.job=j.id;v.idle0=null;CO.jobs.push(j)}
  return _r()}}
/* picking on the map */
{const _cc=coClick;coClick=function(x,y){if(!MV.on)return _cc(x,y);const v=CO.veh.find(q=>q.id===MV.vid);if(!v){mvClose();return true}
  let best=null,bd=26;for(const t of MV.ts){const q=project(PL[t.pid].x,0,PL[t.pid].z);if(!q)continue;const d=Math.hypot(q.x-x,q.y-y);if(d<bd){bd=d;best=t}}
  if(!best){toast("warn","Оберіть хаб","Клікніть на підсвічене місто з хабом. Esc — скасувати.");return true}
  if(best.why){toast("warn",PL[best.pid].name,best.why);return true}mvApply(v,best.pid);return true}}
addEventListener("keydown",e=>{if(MV.on&&e.key==="Escape"){e.stopImmediatePropagation();mvClose();toast("","Переміщення скасовано","")}},true);
function mvDraw(g,dpr){const v=CO.veh.find(q=>q.id===MV.vid);if(!v){mvClose();return}const t=performance.now()/1000;REDRAW=true;
  const f=(t*.8)%1;for(const T_ of MV.ts){const p=PL[T_.pid],q=project(p.x,0,p.z);if(!q)continue;const x=q.x*dpr,y=q.y*dpr,ok=!T_.why,col=ok?"92,200,242":"150,160,172";
    if(ok){g.strokeStyle=`rgba(${col},${(1-f).toFixed(2)})`;g.lineWidth=2*dpr;g.beginPath();g.arc(x,y,(10+f*22)*dpr,0,7);g.stroke()}
    g.fillStyle=`rgb(${col})`;g.strokeStyle="#0b1520";g.lineWidth=1.5*dpr;g.beginPath();g.arc(x,y,8*dpr,0,7);g.fill();g.stroke();drawIcons(g,["updown"],x-5*dpr,y,10*dpr,"#0b1520");
    const txt=ok?p.name:`${p.name} · ${T_.why}`;g.font=`700 ${10*dpr}px "JetBrains Mono",monospace`;const tw=g.measureText(txt).width+12*dpr;
    g.fillStyle="rgba(8,18,28,.9)";g.fillRect(x-tw/2,y+12*dpr,tw,17*dpr);g.strokeStyle=`rgba(${col},.9)`;g.lineWidth=1*dpr;g.strokeRect(x-tw/2,y+12*dpr,tw,17*dpr);
    g.fillStyle=`rgb(${col})`;g.textAlign="center";g.textBaseline="middle";g.fillText(txt,x,y+20.5*dpr);g.textBaseline="alphabetic"}
  const vp=PL[mvFrom(v)],q=project(vp.x,0,vp.z);if(q){g.fillStyle="#ffb347";g.strokeStyle="#0b1520";g.lineWidth=1.5*dpr;g.beginPath();g.arc(q.x*dpr,q.y*dpr,5*dpr,0,7);g.fill();g.stroke()}}
{const _dc=drawCompany;drawCompany=function(g,dpr){_dc(g,dpr);if(MV.on){const c=document.getElementById("vcv");if(c)guard("Переміщення",()=>mvDraw(c.getContext("2d"),dpr))}}}
