/* ================= UI CORE ================= */
const UI={sel:null,win:null,inspTab:"ov",mode:"pol",newsDirty:true,mailDirty:true,mres:0,nf:"all",picking:false,busy:false};
const ACT={};const DD={};const CH={};
let modalQ=[],modalOpen=false;

/* tooltip */
(function(){
  const tip=$("#tip");let cur=null;
  document.addEventListener("mouseover",e=>{if(typeof SET!=="undefined"&&SET.noTips){tip.hidden=true;return}const t=e.target.closest("[data-tip]");if(t===cur)return;cur=t;if(!t){tip.hidden=true;return}tip.innerHTML=t.dataset.tip;tip.hidden=false;place(e)});
  document.addEventListener("mousemove",e=>{if(cur)place(e)});
  function place(e){const r=tip.getBoundingClientRect();let x=e.clientX+14,y=e.clientY+16;if(x+r.width>innerWidth-8)x=e.clientX-r.width-14;if(y+r.height>innerHeight-8)y=e.clientY-r.height-12;tip.style.left=x+"px";tip.style.top=y+"px"}
  document.addEventListener("scroll",()=>{tip.hidden=true;cur=null},true);
})();
const T=(title,text,link)=>`<b>${esc(title)}</b>${text}${link?`<span class="tl">${link}</span>`:""}`.replace(/"/g,"&quot;");

/* actions delegation */
document.addEventListener("click",e=>{
  const ddb=e.target.closest(".dd>button");if(ddb){openDD(ddb.parentElement.dataset.dd,ddb);return}
  const ddi=e.target.closest(".ddlist div[data-v]");if(ddi){const id=ddi.parentElement.dataset.dd;const d=DD[id];d.value=ddi.dataset.v;closeDD();d.on(d.value);return}
  if(!e.target.closest(".ddlist"))closeDD();
  const a=e.target.closest("[data-act]");if(a&&!a.disabled){const f=ACT[a.dataset.act];if(f)f(a.dataset.arg,a,e)}
});
document.addEventListener("input",e=>{const t=e.target;if(t.classList.contains("rng"))setRngFill(t);if(t.dataset.live&&ACT[t.dataset.live])ACT[t.dataset.live](t.value,t,"input")});
document.addEventListener("change",e=>{const t=e.target;if(t.dataset.commit&&ACT[t.dataset.commit])ACT[t.dataset.commit](t.value,t,"change")});
function setRngFill(t){const p=(t.value-t.min)/(t.max-t.min)*100;t.style.setProperty("--p",p+"%")}
function fillRanges(root){root.querySelectorAll(".rng").forEach(setRngFill)}

/* dropdown */
function dd(id,opts,value,on){DD[id]={opts,value:String(value),on};const o=opts.find(x=>String(x.v)===String(value))||opts[0];
  return `<div class="dd" data-dd="${id}"><button type="button">${o?.img?`<img src="${o.img}" alt="" style="width:20px;height:13px">`:o?.ic?ic(o.ic):""}<span>${esc(o?.l??"")}</span>${ic("chev")}</button></div>`}
function openDD(id,btn){closeDD();const d=DD[id];if(!d)return;const r=btn.getBoundingClientRect();const L=document.createElement("div");L.className="ddlist";L.dataset.dd=id;
  L.innerHTML=d.opts.map(o=>`<div data-v="${o.v}" class="${String(o.v)===d.value?"on":""}">${o.img?`<img src="${o.img}" alt="">`:o.ic?ic(o.ic):""}${esc(o.l)}${o.s?`<small>${esc(o.s)}</small>`:""}</div>`).join("");
  document.body.appendChild(L);const h=Math.min(300,L.scrollHeight);let top=r.bottom+4;if(top+h>innerHeight-10)top=r.top-h-4;L.style.left=r.left+"px";L.style.top=top+"px";L.style.width=Math.max(r.width,200)+"px"}
function closeDD(){document.querySelectorAll(".ddlist").forEach(x=>x.remove())}

/* toasts */
let SIM=false,TOAST_T=0;
function toast(tone,title,text,onClick){
  if(SIM){const now=performance.now();if(now-TOAST_T<(tone==="bad"?3500:8000))return;TOAST_T=now}
  const box=$("#toasts");const el=document.createElement("div");el.className="toast glass "+(tone||"");
  el.innerHTML=`${ic(tone==="bad"?"alert":tone==="good"?"check":"info")}<div><b>${esc(title)}</b><span>${esc(text)}</span></div>`;
  if(onClick){el.style.cursor="pointer";el.onclick=()=>{onClick();el.remove()}}
  box.prepend(el);while(box.children.length>4)box.lastChild.remove();setTimeout(()=>el.remove(),6500);
}

/* modal */
function queueModal(s){
  modalQ.push(s);if(!modalOpen)nextModal()}
function nextModal(){const s=modalQ.shift();if(!s){modalOpen=false;$("#modal").hidden=true;return}showModal(s)}
function showModal(s){
  modalOpen=true;const m=$("#modal"),b=$("#mbox");
  b.innerHTML=`<div class="mhead"><div class="mic ${s.tone||""}">${ic(s.icon||"info")}</div><div class="grow"><span class="lbl">${esc(s.eyebrow||"")}</span><h3>${esc(s.title)}</h3></div>${s.closable?`<button class="xbtn" data-act="mclose">${ic("close")}</button>`:""}</div>
  <div class="mb">${s.body||""}${(s.choices||[]).map((c,i)=>`<button class="choice${c.hl?" hl":""}" data-act="mchoice" data-arg="${i}" ${c.dis?"disabled":""}><b>${esc(c.t)}</b>${c.d?`<span>${esc(c.d)}</span>`:""}</button>`).join("")}</div>`;
  b._s=s;m.hidden=false;fillRanges(b);if(s.after)s.after(b);
}
ACT.mchoice=i=>{const s=$("#mbox")._s;const c=s.choices[+i];if(c.keep){c.f&&c.f();return}nextModal();try{c.f&&c.f()}catch(e){console.error(e)}refreshAll()};
ACT.mclose=()=>nextModal();
addEventListener("keydown",e=>{if(e.key==="Escape"){if(modalOpen&&$("#mbox")._s?.closable)nextModal();else if(UI.win)closeWin();else if(UI.sel!=null)selectCountry(null)}if(e.key===" "&&e.target===document.body&&!UI.picking){e.preventDefault();setSpeed(G.speed?0:G.lastSpeed||1)}});

/* charts */
function chart(id,data,o={}){CH[id]={data,...o};return `<div class="chart" data-chart="${id}"><canvas style="height:${o.h||120}px"></canvas><div class="ctip" hidden></div></div>`}
function drawCharts(root){root.querySelectorAll(".chart").forEach(el=>{const s=CH[el.dataset.chart];if(s)drawChart(el,s,-1);if(!el._b){el._b=1;el.addEventListener("mousemove",e=>{const s=CH[el.dataset.chart];if(!s)return;const r=el.getBoundingClientRect();const n=s.data.length;const L=el._L||44;const i=Math.round((e.clientX-r.left-L)/(r.width-L-12)*(n-1));drawChart(el,s,clamp(i,0,n-1))});el.addEventListener("mouseleave",()=>{const s=CH[el.dataset.chart];s&&drawChart(el,s,-1)})}})}
function drawChart(el,s,hi){
  const cv=el.querySelector("canvas"),tip=el.querySelector(".ctip");const dpr=devicePixelRatio||1,w=cv.clientWidth,h=cv.clientHeight;if(!w)return;
  cv.width=w*dpr;cv.height=h*dpr;const g=cv.getContext("2d");g.scale(dpr,dpr);
  const d=s.data;if(d.length<2){g.fillStyle="#7d8e9e";g.font="12px Onest";g.fillText("Дані з'являться через місяць",8,h/2);return}
  let mn=Math.min(...d),mx=Math.max(...d);if(s.zero)mn=Math.min(0,mn);if(mx-mn<1e-9){mx+=1;mn-=1}const pad=(mx-mn)*.12;mx+=pad;if(!s.zero)mn-=pad;
  g.font="500 10px JetBrains Mono, monospace";let af=s.fmt?(v=>s.fmt(v,true)):(v=>v.toFixed(0));{const ls=[0,1,2,3].map(k=>af(mn+(mx-mn)*k/3));if(new Set(ls).size<4)af=v=>Number(v.toPrecision(4)).toLocaleString("uk-UA")}let lw=0;for(let k=0;k<=3;k++){lw=Math.max(lw,g.measureText(af(mn+(mx-mn)*k/3)).width)}
  const L=Math.ceil(lw)+12,Rr=12,Tp=8,B=18,X=i=>L+i/(d.length-1)*(w-L-Rr),Y=v=>Tp+(1-(v-mn)/(mx-mn))*(h-Tp-B);
  g.font="500 10px JetBrains Mono, monospace";g.textBaseline="middle";
  for(let k=0;k<=3;k++){const v=mn+(mx-mn)*k/3,y=Y(v);g.strokeStyle="rgba(146,186,214,.10)";g.lineWidth=1;g.beginPath();g.moveTo(L,y);g.lineTo(w-Rr,y);g.stroke();g.fillStyle="#7d8e9e";g.textAlign="right";g.fillText(af(v),L-6,y)}
  if(s.labels){g.textAlign="left";g.fillStyle="#7d8e9e";g.fillText(s.labels[0],L,h-7);g.textAlign="right";g.fillText(s.labels[s.labels.length-1],w-Rr,h-7)}
  el._L=L;const col=s.color||"#5cc8f2";
  const grd=g.createLinearGradient(0,Tp,0,h-B);grd.addColorStop(0,col+"55");grd.addColorStop(1,col+"00");
  g.beginPath();d.forEach((v,i)=>i?g.lineTo(X(i),Y(v)):g.moveTo(X(i),Y(v)));g.lineTo(X(d.length-1),h-B);g.lineTo(X(0),h-B);g.closePath();g.fillStyle=grd;g.fill();
  g.beginPath();d.forEach((v,i)=>i?g.lineTo(X(i),Y(v)):g.moveTo(X(i),Y(v)));g.strokeStyle=col;g.lineWidth=2;g.lineJoin="round";g.stroke();
  const e=hi>=0?hi:d.length-1;g.fillStyle=col;g.strokeStyle="#0b1119";g.lineWidth=2;g.beginPath();g.arc(X(e),Y(d[e]),4.5,0,7);g.fill();g.stroke();
  if(hi>=0){g.strokeStyle="rgba(231,238,244,.35)";g.lineWidth=1;g.beginPath();g.moveTo(X(hi),Tp);g.lineTo(X(hi),h-B);g.stroke();tip.hidden=false;tip.style.left=X(hi)+"px";tip.style.top=Y(d[hi])+"px";tip.textContent=(s.labels?s.labels[hi]+" · ":"")+(s.fmt?s.fmt(d[hi]):d[hi].toFixed(1))}else tip.hidden=true;
}

/* ================= HUD ================= */
const RAIL=[
 ["news","news","Стрічка новин","Що відбувається у світі."],
];
function buildHUD(){
  $("#rail").innerHTML=RAIL.filter(r=>r==="|"||railOK(r[0])).filter((r,i,a)=>r!=="|"||(i>0&&a[i-1]!=="|"&&i<a.length-1)).map(r=>r==="|"?`<div class="rsep"></div>`:`<button class="rbtn ${""}" data-act="win" data-arg="${r[0]}" data-tip="${T(r[2],r[3])}" aria-label="${r[2]}">${ic(r[1])}</button>`).join("");
  $("#speed").innerHTML=[["pause","Пауза (пробіл)"],["play","Звичайна швидкість"],["ff","Швидко"],["fff","Дуже швидко"]].map((s,i)=>`<button data-act="speed" data-arg="${i}" data-tip="${T(s[1],"")}" aria-label="${s[1]}">${ic(s[0],s[0]==="pause"?"":"fill")}</button>`).join("");
  const modes=CO_MODES;
  if(!$("#modeCell")){const cell=document.createElement("div");cell.className="cell dd-cell";cell.id="modeCell";$("#speed").after(cell)}
  $("#modeCell").dataset.tip=T("Шар мапи","Мережа компанії — ваші хаби, техніка й рейси, перекриті дороги й кордони. Логістичні шляхи — дороги, залізниці, порти, аеропорти й пункти пропуску. Ризики перевезень — наскільки небезпечно возити вантажі в кожній країні. Політична — держави та їхні кордони. Світовий попит — де найбільше замовлень на доставку.");
  $("#modeCell").innerHTML=`<span class="lbl">Шар мапи</span>${dd("mapmode",modes.map(m=>({v:m[0],l:m[1],ic:m[2]})),UI.mode,v=>{ACT.mode(v);buildModeDD()})}`;
  ["idbox","kpis","rail","bar"].forEach(id=>$("#"+id).hidden=false);
  const me=G.C[G.me];$("#myFlag").src=me.flag;$("#myName").textContent=me.name;$("#myLeader").textContent=`${me.leader.title} · ${me.ide.n}`;
  $("#whoBox").onclick=()=>{selectCountry(G.me);flyTo(G.me)};
}
function updateHUD(){coHUD()}
ACT.speed=i=>setSpeed(+i);
function setSpeed(i){const fr=G.speed?acc/DUR[G.speed]:(G.pfr||0);if(!i)G.pfr=Math.min(fr,.999);else acc=Math.min(fr,.999)*DUR[i];if(i)G.lastSpeed=i;G.speed=i;updateHUD()}
ACT.mode=m=>{UI.mode=m;applyMapColors();updateLegend()};
function buildModeDD(){const modes=CO_MODES;$("#modeCell").innerHTML=`<span class="lbl">Шар мапи</span>${dd("mapmode",modes.map(m=>({v:m[0],l:m[1],ic:m[2]})),UI.mode,v=>{ACT.mode(v);buildModeDD()})}`}
function applyMapColors(){
  if(["co","risk","grid","pol","dem"].includes(UI.mode)&&typeof coColors==="function"&&CO.hubs&&PL.length){setMapColors(coColors());return}
  const me=G.me;setMapColors(G.C.map(c=>UI.mode!=="pol"&&me!=null&&c.id===me?hex3("#5cc8f2"):hex3(c.color)));
}
const mixc=(a,b,t)=>[lerp(a[0],b[0],t),lerp(a[1],b[1],t),lerp(a[2],b[2],t)];

/* ================= MAP OVERLAY ================= */
let ovBuilt=false;
function buildOverlay(){
  const L=$("#ovl");L.innerHTML="";
  G.C.forEach(c=>{
    const d=document.createElement("div");d.className="clabel"+(c.id===G.me?" me":"");d.textContent=c.name;d.id="lb"+c.id;L.appendChild(d);
    const cp=document.createElement("div");cp.className="cap";cp.id="cp"+c.id;L.appendChild(cp);
  });
  ovBuilt=true;
}
function updateOverlay(){
  if(!ovBuilt||!G.C.length&&!G.board)return;
  guard("Міста",updateCities);
  drawBorders();
}
/* dashed line anchored to the world: dash pattern does not crawl when the camera pans or zooms */
function wdash(g,P,pts,off=0){if(pts.length<2)return;const q=Math.pow(2,Math.round(Math.log2(Math.max(.25,Cam.dist)))),D=.0075*q,Gp=.0065*q,per=D+Gp;let acc=((off*q)%per+per)%per;
  g.beginPath();let budget=24000;for(let i=1;i<pts.length&&budget>0;i++){const a=pts[i-1],b=pts[i],L=Math.hypot(b[0]-a[0],b[1]-a[1],b[2]-a[2]);if(!L||!isFinite(L))continue;let s=0;
    let guardN=0;while(s<L&&guardN++<4000&&budget-->0){const ph=acc%per;if(ph<D-1e-9){const e=Math.min(L,s+Math.max(D-ph,per*1e-4));const pa=P(a[0]+(b[0]-a[0])*s/L,a[1]+(b[1]-a[1])*s/L,a[2]+(b[2]-a[2])*s/L),pb=P(a[0]+(b[0]-a[0])*e/L,a[1]+(b[1]-a[1])*e/L,a[2]+(b[2]-a[2])*e/L);if(pa&&pb){g.moveTo(...pa);g.lineTo(...pb)}acc+=e-s;s=e}else{const e=Math.min(L,s+Math.max(per-ph,per*1e-4));acc+=e-s;s=e}}}
  g.setLineDash([]);g.stroke()}
/* route line in the interface style: dark casing, coloured core, chevrons pointing along the motion (anchored to the world) */
function wroute(g,P,pts,rgb,dpr){if(pts.length<2)return;g.lineCap="butt";
  g.strokeStyle=`rgba(${rgb},1)`;g.lineWidth=2.4*dpr;wdash(g,P,pts,0);g.lineCap="round";
  const e=P(...pts[pts.length-1]);if(e){g.fillStyle=`rgba(${rgb},.25)`;g.strokeStyle=`rgba(${rgb},1)`;g.lineWidth=2*dpr;g.beginPath();g.arc(e[0],e[1],4*dpr,0,7);g.fill();g.stroke()}}
/* ground polyline → screen, clipped against the camera's near plane: a segment whose far end is behind
   the camera (close zoom, looking ahead) is cut where it leaves the view instead of being dropped */
function clipPath(g,p,m,sw,sh){const E=.05,P=(x,z,cw)=>[(m[0]*x+m[8]*z+m[12])/cw*sw+sw,sh-(m[1]*x+m[9]*z+m[13])/cw*sh];let pen=false,px=0,pz=0,pc=0;
  for(let i=0;i<p.length;i+=2){const x=p[i],z=p[i+1],cw=m[3]*x+m[11]*z+m[15];
    if(i>0){if(pc>E&&cw>E){if(!pen){const a=P(px,pz,pc);g.moveTo(a[0],a[1]);pen=true}const b=P(x,z,cw);g.lineTo(b[0],b[1])}
      else if(pc>E||cw>E){const t=(E-pc)/(cw-pc),ix=px+(x-px)*t,iz=pz+(z-pz)*t,c=P(ix,iz,E);
        if(pc>E){if(!pen){const a=P(px,pz,pc);g.moveTo(a[0],a[1])}g.lineTo(c[0],c[1]);pen=false}else{const b=P(x,z,cw);g.moveTo(c[0],c[1]);g.lineTo(b[0],b[1]);pen=true}}
      else pen=false}
    px=x;pz=z;pc=cw}}
function drawBorders(){
  const cv=$("#bcv"),L=G.world&&G.world.lines;if(!cv||!L||!GL.vp)return;
  const dpr=renderDpr(),W=window.FORCE_RES?FORCE_RES[0]:Math.floor(innerWidth*dpr),H=window.FORCE_RES?FORCE_RES[1]:Math.floor(innerHeight*dpr);
  if(cv.width!==W||cv.height!==H){cv.width=W;cv.height=H}
  const g=cv.getContext("2d");g.setTransform(1,0,0,1,0,0);g.clearRect(0,0,W,H);
  const m=GL.vp,sw=W/2,sh=H/2;
  const path=(p,keep)=>{if(!keep)g.beginPath();clipPath(g,p,m,sw,sh)};
  const zw=clamp(13/Cam.dist,1,3.2);
  g.lineJoin="round";g.lineCap="round";
  {const hx=WX/2,hz=WZ/2,fr=[],N=24;for(const [ax,az,bx,bz] of [[-hx,-hz,hx,-hz],[hx,-hz,hx,hz],[hx,hz,-hx,hz],[-hx,hz,-hx,-hz]])for(let i=0;i<N;i++)fr.push(lerp(ax,bx,i/N),lerp(az,bz,i/N));fr.push(-hx,-hz);
   const P=new Float32Array(fr);
   g.strokeStyle="rgba(92,200,242,.16)";g.lineWidth=6*dpr;path(P);g.stroke();
   g.strokeStyle="rgba(120,214,248,.9)";g.lineWidth=1.4*dpr;path(P);g.stroke();}
  if(G.co&&G.board)guard("Берегові стінки",()=>drawWalls(g,dpr));
  // coastlines (seas and lakes) — one batched vector pass
  const vb=vbox();g.beginPath();for(const l of L){if(l.a===0&&inVB(l,l.p,vb))path(l.p,true)}
  g.strokeStyle="rgba(150,220,245,.22)";g.lineWidth=3.2*zw*dpr;g.stroke();
  g.strokeStyle="rgba(5,12,20,.92)";g.lineWidth=1.3*zw*dpr;g.stroke();
  // country borders
  if(!(G.co&&UI.mode==="pol"&&typeof vis==="function"&&!vis("pol_b"))){g.beginPath();for(const l of L){if(l.a!==0&&inVB(l,l.p,vb))path(l.p,true)}
  g.strokeStyle="rgba(6,10,14,.9)";g.lineWidth=1.25*zw*dpr;g.stroke();}
  const s=UI.selP!=null?null:UI.sel;
  if(s!=null){const id=s+1;
    g.beginPath();for(const l of L){if(l.a===id||l.b===id)path(l.p,true)}
    g.strokeStyle="rgba(92,200,242,.28)";g.lineWidth=5*zw*dpr;g.stroke();
    g.strokeStyle="#c9efff";g.lineWidth=1.5*zw*dpr;g.stroke();}
  if(G.board)guard("Поле",()=>drawBoard(g,dpr));
  guard("Логістика",()=>drawLogistics(g,dpr));
  if(G.board)guard("Поселення",()=>drawBoardTowns(g,dpr));
  
  
  
  
  if(G.co)guard("Компанія",()=>drawCompany(g,dpr));
}

/* ================= SELECTION & INSPECTOR ================= */
function onMapClick(k){if(k<0){selectCountry(null);return}selectCountry(k)}
function selectCountry(k){UI.selP=null;UI.sel=k;UI.selN=false;if(k==null){$("#insp").hidden=true;return}renderInsp()}
ACT.iclose=()=>{UI.selN=false;selectCountry(null)};

function renderInsp(){const _ib=$("#insp .ibody"),_sc=_ib?_ib.scrollTop:0;renderInsp0();const _nb=$("#insp .ibody");if(_nb&&_sc)_nb.scrollTop=_sc}
function renderInsp0(){return coInsp()}
const WINS={};
ACT.win=id=>{if(UI.win===id)closeWin();else openWin(id)};
function openWin(id){UI.win=id;renderWin();updateHUD()}
function closeWin(){UI.win=null;const el=$("#win");el.hidden=true;el._w=null;updateHUD()}
ACT.wclose=closeWin;
function winIdle(){return performance.now()-(UI.scrollT||0)>1600}
["wheel","touchmove","scroll"].forEach(ev=>addEventListener(ev,e=>{if(e.target&&e.target.closest&&e.target.closest("#win,#insp"))UI.scrollT=performance.now()},{passive:true,capture:true}));
addEventListener("pointerdown",e=>{if(e.target&&e.target.closest&&e.target.closest("#win .wbody,#insp .ibody")){const t=e.target.closest(".wbody,.ibody");if(t&&e.offsetX>t.clientWidth-2)UI.scrollT=performance.now()+4000}},{capture:true});
/* in-place DOM patch: only touches nodes that changed, keeps scroll/hover and avoids full relayout */
function morphKids(a,b){const A=a.childNodes,B=b.childNodes;
  for(let i=0;i<B.length;i++){const x=A[i],y=B[i];if(!x){a.appendChild(y.cloneNode(true));continue}morphNode(x,y)}
  while(A.length>B.length)a.removeChild(a.lastChild)}
function morphNode(x,y){
  if(x.nodeType!==y.nodeType||x.nodeName!==y.nodeName){x.replaceWith(y.cloneNode(true));return}
  if(x.nodeType===3||x.nodeType===8){if(x.data!==y.data)x.data=y.data;return}
  if(x.nodeType!==1)return;
  if(x.nodeName==="CANVAS"){if(x.className!==y.className)x.className=y.className;return}
  const xa=x.attributes,ya=y.attributes;
  for(let i=xa.length-1;i>=0;i--){const n=xa[i].name;if(!y.hasAttribute(n))x.removeAttribute(n)}
  for(let i=0;i<ya.length;i++){const n=ya[i].name,v=ya[i].value;if(x.getAttribute(n)!==v){x.setAttribute(n,v);if(n==="value"&&"value" in x)x.value=v;if(n==="checked")x.checked=true}}
  if(x.nodeName==="INPUT"||x.nodeName==="TEXTAREA"||x.nodeName==="SELECT")return;
  if(x.innerHTML===y.innerHTML)return;
  morphKids(x,y)}
function renderWin(){
  if(!UI.win)return;const w=WINS[UI.win];const r=RAIL.find(x=>x[0]===UI.win);const el=$("#win");
  const sc=el.querySelector(".wbody")?.scrollTop||0;
  const html=`<div class="whead"><div class="wic">${ic(r[1])}</div><div class="wt"><span class="lbl">${esc(CO.name)} · ${dateStr(G.date)}</span><h3>${r[2]}</h3></div><button class="xbtn" data-act="wclose" aria-label="Закрити">${ic("close")}</button></div><div class="wbody">${w()}</div>`;
  if(el._w===UI.win&&!el.hidden&&el.firstElementChild){if(el._h===html)return;el._h=html;const tp=document.createElement("div");tp.innerHTML=html;morphKids(el,tp);fillRanges(el);drawCharts(el);return}
  el._w=UI.win;el._h=html;el.hidden=false;el.innerHTML=html;
  const wb=el.querySelector(".wbody");wb.scrollTop=sc;drawCharts(el);fillRanges(el);if(wb.scrollTop!==sc)requestAnimationFrame(()=>{wb.scrollTop=sc});
  
}
function refreshAll(){updateHUD();if(UI.win&&!UI.busy)renderWin();if(UI.sel!=null)renderInsp();applyMapColors()}
const stat=(l,v,s,tip,cls="")=>`<div class="stat" ${tip?`data-tip="${tip}"`:""}><span class="lbl">${l}</span><div class="v ${cls}">${v}</div>${s?`<div class="s">${s}</div>`:""}</div>`;
const sect=t=>`<div class="sect"><h4>${t}</h4></div>`;











WINS.news=()=>{
  const f=UI.nf;const items=G.news.filter(n=>f==="all"||(f==="me"&&n.me)||(f==="conf"&&["bad"].includes(n.tone))||(f==="good"&&n.tone==="good")).slice(0,120);
  return `<div class="seg">${[["all","Усі"],["me","Ваша країна"],["conf","Конфлікти і кризи"],["good","Співпраця"]].map(x=>`<button data-act="nf" data-arg="${x[0]}" class="${f===x[0]?"on":""}">${x[1]}</button>`).join("")}</div>
  <div class="feed">${items.map(n=>`<div class="fi"><span class="d">${shortDate(n.d)}</span><span class="${n.tone}">${ic(n.icon)}</span><span>${esc(n.text)}</span></div>`).join("")||`<div class="note">Поки тихо.</div>`}</div>`;
};
ACT.nf=f=>{UI.nf=f;renderWin()};


/* ================= START & PICK ================= */
