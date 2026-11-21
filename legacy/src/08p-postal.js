/* =====================================================================
   DLC «Postal Hub — Пошта» (logistics mode). Switched on from the main-menu DLC card.
   Parcels are taken in at post offices (cities only), go first to the country's postal terminal
   (a logistics terminal adapted for mail), then terminal → terminal (truck, plane or ship) and
   finally terminal → destination offices. Yellow dots on the map are the mail runs.
   ===================================================================== */
const PO_Y="246,196,32";let PO_HITS=[],PO_SEL=null;
const PVT={
 pvan:{n:"Поштовий фургон",ic:"truck",cost:32000,mode:"road",cap:600,spd:1.3,up:26,fuel:55,crew:1,tier:1,d:"Остання миля: розвозить до 600 посилок на день від терміналу по відділеннях."},
 ptruck:{n:"Магістральна поштова вантажівка",ic:"truck",cost:110000,mode:"road",cap:4000,spd:1.05,up:80,fuel:160,crew:1,tier:2,d:"До 4 000 посилок за рейс між терміналами й містами."},
 pship:{n:"Поштовий фідер",ic:"ship",cost:9000000,mode:"sea",cap:60000,spd:1.6,up:3000,fuel:1800,crew:10,tier:5,d:"Контейнери з посилками між портовими терміналами різних материків."},
 pplane:{n:"Поштовий літак",ic:"plane",cost:30000000,mode:"air",cap:20000,spd:16,up:7000,fuel:3000,crew:3,tier:6,d:"Експрес-пошта між аеропортами: за години, не за дні."}};
const PO_MG=[["pdir","Директор пошти","mail","Швидша обробка в терміналах (+30% за 10/10), менше втрачених посилок."],["phr","HR пошти","users","Дешевші й лояльніші оператори та кур'єри: −20% фонду оплати за 10/10."],
 ["pmkt","Маркетолог","spark","Більше клієнтів (до +35% попиту) і клієнти легше приймають високі тарифи."],["peco","Економіст","chart","Прогноз попиту, доходу й завантаження на наступний місяць. Точність росте з кваліфікацією."]];
const PO_SIZES=[["s","До 1 кг","конверти й дрібні посилки",.55,1],["m","1–10 кг","звичайні посилки",.35,2.2],["l","10–30 кг","великогабаритні",.1,5.5]];
const PO_SPEED=[["std","Стандарт","3 дні",3,1],["exp","Експрес","1 день",1,1.9]];
const poOn=()=>G.co&&G.board&&SET.dlcPost&&CO.hq!=null;
function poInit(){if(CO.post)return CO.post;CO.post={brand:CO.name+" Пошта",off:[],term:[],veh:[],price:{base:5,size:{s:1,m:2.2,l:5.5},exp:1.9},mix:{exp:.25},
  mgr:{},cand:{},staff:0,rep:3,share:.02,trips:[],hist:{rev:[],par:[]},m:{rev:0,cost:0,par:0,late:0,lost:0},lm:null,day:{par:0,done:0,late:0,cap:0,dem:0},angry:0,uid:1};poMgrCand();return CO.post}
const poRef=cid=>5*priceK(cid); // the market's usual price of a 1-kg standard parcel
const poTerm=cid=>CO.post.term.find(t=>PL[t].cid===cid);
const poMsk=id=>CO.post&&CO.post.mgr[id]?CO.post.mgr[id].skill/10:0;
function poMgrCand(id){const P=CO.post;for(const [k] of PO_MG){if(id&&k!==id)continue;P.cand[k]=[0,1,2].map(()=>{const s=rint(2,10);return{name:personName(),age:rint(26,62),trait:pick(MG_TR),skill:s,sal:Math.round((900+s*300)*(.6+.4*priceK(G.me))/10)*10}})}}

/* ---------- daily simulation ---------- */
function poDay(){if(!poOn())return;const P=poInit();const d={par:0,done:0,late:0,cap:0,dem:0,rev:0,cost:0};
  // processing capacity: terminals (adapted) + director; vehicles: last mile and trunk
  const proc=P.term.length*3500*(1+.3*poMsk("pdir"));
  const vans=P.veh.filter(v=>PVT[v.t].mode==="road"&&v.t==="pvan").length,trunk=P.veh.filter(v=>v.t!=="pvan").reduce((a,v)=>a+PVT[v.t].cap,0);
  const lastMile=vans*600,staffCap=P.staff*220;
  // demand from every office whose country has a postal terminal
  const avgP=P.price.base*PO_SIZES.reduce((a,s)=>a+s[3]*P.price.size[s[0]],0)*(1+P.mix.exp*(P.price.exp-1));
  for(const pid of P.off){const p=PL[pid];if(!poTerm(p.cid))continue;const ref=poRef(p.cid)*PO_SIZES.reduce((a,s)=>a+s[3]*s[4],0)*(1+P.mix.exp*.9);
    const rel=avgP/ref,el=Math.pow(clamp(rel,.3,4),-(1.7-.6*poMsk("pmkt")));
    d.dem+=(p.pop*1e6+3000)*.008*(.45+G.C[p.cid].dev)*P.share*el*(.6+P.rep*.13)*(1+.35*poMsk("pmkt"))}
  d.cap=Math.min(proc,lastMile+trunk*.15,staffCap);d.par=Math.round(d.dem);d.done=Math.round(Math.min(d.dem,d.cap));d.late=Math.max(0,d.par-d.done);
  d.rev=d.done*avgP;
  // costs: upkeep and fuel of mail vehicles, staff, offices, terminals
  const wage=P.staff*1500*wageK(G.me)/30*(1-.2*poMsk("phr")),veh=P.veh.reduce((a,v)=>a+PVT[v.t].up,0),fuel=P.veh.reduce((a,v)=>a+PVT[v.t].fuel*.6,0)*CO.fuel;
  const rent=P.off.reduce((a,pid)=>a+40*priceK(PL[pid].cid),0)+P.term.length*250*priceK(G.me),mg=Object.values(P.mgr).reduce((a,g)=>a+g.sal,0)/30;
  const handle=d.done*poRef(G.me)*1.15; // sorting, packaging, last-mile fuel per parcel
  d.cost=wage+veh+fuel+rent+mg+handle;CO.cash+=d.rev-d.cost;CO.m.contract+=d.rev;CO.m.other+=d.cost;P.m.rev+=d.rev;P.m.cost+=d.cost;P.m.par+=d.done;P.m.late+=d.late;
  // reputation: late parcels and expensive tariffs make clients angry
  const lateR=d.par?d.late/d.par:0,rel=avgP/(poRef(G.me)*PO_SIZES.reduce((a,s)=>a+s[3]*s[4],0)*(1+P.mix.exp*.9)),overPrice=Math.max(0,rel-1.25);
  P.rep=clamp(P.rep+(lateR<.05?.01:-lateR*.12)-overPrice*.03,1,5);P.angry=Math.max(0,P.angry*.9+overPrice*30+lateR*40);
  P.share=clamp(P.share+(.0004*P.off.length/Math.max(1,P.off.length)+.0003*poMsk("pmkt"))*(P.rep/3)-overPrice*.0006-lateR*.0008,.003,.35);
  if(P.angry>25&&chance(.08)){coNews("bad","mail",`Клієнти ${P.brand} обурені ${overPrice>lateR?"тарифами":"затримками посилок"}: замовлень меншає`);P.angry*=.5}
  P.day=d;poTrips()}
function poMonth(){if(!CO.post)return;const P=CO.post;P.hist.rev.push(Math.round(P.m.rev-P.m.cost));P.hist.par.push(P.m.par);for(const k in P.hist)if(P.hist[k].length>36)P.hist[k].shift();P.lm=P.m;P.m={rev:0,cost:0,par:0,late:0,lost:0}}
{const _d=coDay;coDay=function(){_d();guard("Пошта",poDay)}}
{const _m=coMonth;coMonth=function(){_m();guard("Пошта · місяць",poMonth)}}

/* ---------- mail runs on the map (visual flow: office → terminal → terminal → office) ---------- */
function poTrips(){const P=CO.post,T=G.day;P.trips=P.trips.filter(t=>T<t.t0+t.tot);if(P.trips.length>70)return;
  const add=(mode,a,b,kind)=>{const r=coRoute(mode,a,b);if(!r||r.len<.01)return;const sp={road:1.2,sea:1.6,air:16}[mode]*spdK();P.trips.push({id:P.uid++,mode,kind,a,b,p:r.p,len:r.len,t0:T+R()*.6,tot:Math.max(.08,r.len/sp)})};
  for(const tp of P.term){const cid=PL[tp].cid,offs=P.off.filter(o=>PL[o].cid===cid&&o!==tp),vans=P.veh.filter(v=>v.t==="pvan"&&v.hub===tp).length||Math.min(2,P.veh.filter(v=>v.t==="pvan").length);
    for(let i=0;i<Math.min(vans,offs.length,4);i++){const o=pick(offs);if(chance(.5))add("road",tp,o,"last");else add("road",o,tp,"first")}}
  if(P.term.length>1)for(let i=0;i<3;i++){const a=pick(P.term),b=pick(P.term.filter(x=>x!==a));const A=PL[a],B=PL[b];
    const hasAir=P.veh.some(v=>v.t==="pplane")&&A.air&&B.air,hasSea=P.veh.some(v=>v.t==="pship")&&A.port!=null&&B.port!=null,hasRoad=P.veh.some(v=>v.t==="ptruck")&&A.land===B.land;
    const m=hasRoad&&chance(.6)?"road":hasAir?"air":hasSea?"sea":hasRoad?"road":null;if(m)add(m,a,b,"trunk")}}
function poDraw(g,dpr){if(!poOn()||!CO.post)return;const P=CO.post,T=coNow(),Pp=(x,y,z)=>{const q=project(x,y,z);return q?[q.x*dpr,q.y*dpr]:null},zf=clamp(11/Cam.dist,1,1.8);
  // runs
  PO_HITS=[];if(PO_SEL){const t=P.trips.find(x=>x.id===PO_SEL);if(!t||T>t.t0+t.tot){PO_SEL=null;$("#ucard").hidden=true}else poRoute(g,t,T,Pp,dpr)}
  for(const t of P.trips){const e=T-t.t0;if(e<0||e>t.tot)continue;const f=e/t.tot,s=f*t.len,j={p:t.p};const pos=coPosAt(j,s),alt=t.mode==="air"?Math.sin(Math.PI*f)*coArcH(t.len):0,q=Pp(pos[0],alt,pos[1]);if(!q)continue;
    {const st={road:.05,sea:.08,air:.12}[t.mode]*Math.min(1,Cam.dist/6+.25)*CO_DU/1.6;let pv=q;for(let k=1;k<=9;k++){const s2=s-k*st;if(s2<0)break;const ff=s2/t.len,pp=coPosAt(j,s2),q2=Pp(pp[0],t.mode==="air"?Math.sin(Math.PI*ff)*coArcH(t.len):0,pp[1]);if(!q2)break;g.strokeStyle=`rgba(${PO_Y},${(.75*(1-k/10)).toFixed(3)})`;g.lineWidth=(t.mode==="sea"?2.4:1.8)*dpr*zf*(1-k/12);g.beginPath();g.moveTo(...pv);g.lineTo(...q2);g.stroke();pv=q2}}
    const r=(t.mode==="road"?3.6:4.6)*dpr*zf;PO_HITS.push({t,x:q[0]/dpr,y:q[1]/dpr});if(PO_SEL===t.id){g.strokeStyle=`rgba(${PO_Y},.8)`;g.lineWidth=1.5*dpr;g.beginPath();g.arc(q[0],q[1],r+3*dpr+((performance.now()/800)%1)*9*dpr,0,7);g.stroke();placeUnitCard(q[0]/dpr,q[1]/dpr)}g.fillStyle=`rgba(${PO_Y},.22)`;g.beginPath();g.arc(q[0],q[1],r*2,0,7);g.fill();g.fillStyle=`rgb(${PO_Y})`;g.strokeStyle="#1a1405";g.lineWidth=1.3*dpr;g.beginPath();g.arc(q[0],q[1],r,0,7);g.fill();g.stroke();
    if(t.mode!=="road"&&Cam.dist<16){drawIcons(g,[t.mode==="air"?"plane":"ship"],q[0]+r+2*dpr,q[1],10*dpr,`rgb(${PO_Y})`)}}
  REDRAW=true}
{const _dc=drawCompany;drawCompany=function(g,dpr){_dc(g,dpr);const c=document.getElementById("vcv");if(c)guard("Пошта",()=>poDraw(c.getContext("2d"),dpr))}}

/* ---------- actions ---------- */
const poOffCost=p=>Math.round(6000*priceK(p.cid)*({cap:2,big:1.6,city:1.2,town:.8}[p.type]||1)/100)*100;
const poAdaptCost=p=>Math.round(hubCost(p)*6/100)*100;
ACT.poOff=pid=>{pid=+pid;const P=poInit(),p=PL[pid];if(P.off.includes(pid))return;if(!CO.hubs.some(h=>h.lvl>=3&&PL[h.pid].cid===p.cid))return toast("warn","Немає логістичного терміналу","Відділення відкривається лише в країні, де у вас є логістичний термінал");const c=poOffCost(p);if(CO.cash<c)return toast("warn","Бракує грошей",fmtUSD(c));
  CO.cash-=c;P.off.push(pid);toast("good","Відкрито поштове відділення",`${p.name}${poTerm(p.cid)?"":" · працюватиме, коли логістичний термінал країни адаптують під пошту"}`);poChips();if(UI.win)renderWin();if(UI.sel!=null)renderInsp()};
ACT.poOffX=pid=>{const P=CO.post;P.off=P.off.filter(x=>x!==+pid);poChips();renderWin()};
ACT.poAdapt=pid=>{pid=+pid;const P=poInit(),h=hubAt(pid),p=PL[pid];if(!h||h.lvl<3)return toast("warn","Потрібен логістичний термінал","Покращіть хаб до логістичного терміналу");if(P.term.includes(pid))return;
  const c=poAdaptCost(p);if(CO.cash<c)return toast("warn","Бракує грошей",fmtUSD(c));CO.cash-=c;P.term.push(pid);if(!P.off.includes(pid))P.off.push(pid);toast("good","Поштовий вузол готовий",`${p.name}: термінал адаптовано для пошти`);poChips();renderWin()};
ACT.poBuy=t=>{const P=poInit(),T=PVT[t];if(CO.tier<T.tier)return;if(!P.term.length)return toast("warn","Немає поштового терміналу","Адаптуйте логістичний термінал під пошту");
  let tp=P.term.find(x=>x===P.buyAt)||P.term[0];if(T.mode==="air"){tp=P.term.find(x=>PL[x].air);if(!tp)return toast("warn","Потрібен термінал з аеропортом","")}if(T.mode==="sea"){tp=P.term.find(x=>PL[x].port!=null);if(!tp)return toast("warn","Потрібен термінал у портовому місті","")}
  if(P.veh.filter(v=>v.hub===tp).length>=40)return toast("warn","Термінал заповнений","Поштовий термінал вміщує 40 одиниць поштової техніки");
  if(CO.cash<T.cost)return toast("warn","Бракує грошей",fmtUSD(T.cost));CO.cash-=T.cost;P.veh.push({id:P.uid++,t,hub:tp});toast("good","Куплено: "+T.n,PL[tp].name);renderWin()};
ACT.poSell=t=>{const P=CO.post,i=P.veh.findIndex(v=>v.t===t);if(i<0)return;P.veh.splice(i,1);CO.cash+=PVT[t].cost*.45;renderWin()};
ACT.poStaff=n=>{const P=poInit();n=+n;if(n>0){const fee=Math.round(800*wageK(G.me)*n*(1-.3*poMsk("phr")));if(CO.cash<fee)return toast("warn","Бракує грошей",fmtUSD(fee));CO.cash-=fee;P.staff+=n}else P.staff=Math.max(0,P.staff+n);renderWin()};
ACT.poPrice=a=>{const [k,v]=a.split(":"),P=poInit();if(k==="base")P.price.base=clamp(+v,1,40);else if(k==="exp")P.price.exp=clamp(+v,1,4);else if(k==="mix")P.mix.exp=clamp(+v,0,1);else P.price.size[k]=clamp(+v,.3,20);if(UI.win)renderWin()};
ACT.poHire=a=>{const [id,i]=a.split(":"),P=poInit(),g=P.cand[id][+i];if(CO.cash<g.sal*2)return toast("warn","Бракує грошей","");CO.cash-=g.sal*2;P.mgr[id]={...g};poMgrCand(id);toast("good","Найнято",`${g.name} · ${PO_MG.find(x=>x[0]===id)[1]}`);renderWin()};
ACT.poFire=id=>{delete CO.post.mgr[id];renderWin()};
ACT.poBrand=()=>{const P=poInit();queueModal({icon:"mail",eyebrow:"Пошта",title:"Назва поштової служби",body:`<input id="poNameIn" maxlength="32" value="${esc(P.brand)}" style="width:100%;height:40px;padding:0 12px;background:rgba(255,255,255,.05);border:1px solid var(--line-hi);color:var(--fg);font:600 15px/1 var(--f-body)">`,choices:[{t:"Зберегти",d:"",f(){}},{t:"Скасувати",d:"",f(){}}]});
  const el0=$("#poNameIn"),b0=document.querySelector("#mbox .choice");if(b0)b0.addEventListener("click",()=>{const n=(el0.value||"").trim();if(n){P.brand=n.slice(0,32);toast("good","Назву змінено",P.brand);if(UI.win)renderWin()}},{capture:true,once:true});
  setTimeout(()=>{if(el0){el0.focus();el0.select();el0.onkeydown=e=>{e.stopPropagation();if(e.key==="Enter"&&b0)b0.click()}}},50)};

/* ---------- windows ---------- */
const poHead=t=>{const P=poInit();return `<div class="row sp" style="margin-bottom:12px"><div class="row" style="gap:10px"><span style="color:rgb(${PO_Y})">${ic("mail")}</span><div><b style="font-size:16px">${esc(P.brand)}</b><div class="note">DLC «Postal Hub — Пошта» · ${t}</div></div></div><button class="btn sm" data-act="poBrand">${ic("doc")}Перейменувати</button></div>`};
WINS.poOffices=()=>{const P=poInit(),hubs3=CO.hubs.filter(h=>h.lvl>=3);
  const cids=[...new Set(P.off.map(o=>PL[o].cid))],noT=cids.filter(c=>!poTerm(c));
  return poHead("Відділення й термінали")+`<div class="hint">${ic("info")}<div>Посилки приймають <b>поштові відділення</b> в містах. Кожна посилка спершу їде в <b>поштовий термінал</b> своєї країни, звідти — в термінал країни призначення і далі у відділення. Відділення працює, лише коли в його країні є хоча б один поштовий термінал. Термінал — це <b>логістичний термінал</b>, адаптований під пошту.</div></div>
  ${noT.length?`<div class="hint" style="border-color:rgba(241,196,83,.45)">${ic("alert")}<div>Немає поштового терміналу: ${noT.map(c=>esc(G.C[c].name)).join(", ")}. Відділення там не працюють.</div></div>`:""}
  ${sect("Поштові термінали")}${hubs3.length?hubs3.map(h=>{const p=PL[h.pid],is=P.term.includes(h.pid);return `<div class="lrow" style="margin-bottom:6px"><span style="color:rgb(${PO_Y})">${ic(is?"mail":"building")}</span><div style="min-width:0"><b>${plName(p)}</b><div class="note">${is?`Поштовий вузол · обробка ${Math.round(3500*(1+.3*poMsk("pdir"))).toLocaleString("uk-UA")} посилок/день · техніка ${P.veh.filter(v=>v.hub===h.pid).length}/40`:"Логістичний термінал · можна адаптувати під пошту"}</div></div>${is?`<span class="pill good">Пошта</span>`:`<button class="btn sm pri" data-act="poAdapt" data-arg="${p.id}">${ic("gear")}Адаптувати · ${fmtUSD(poAdaptCost(p))}</button>`}</div>`}).join(""):`<div class="note">Немає логістичних терміналів. Покращіть хаб до рівня «Логістичний термінал» у вікні «Мережа хабів».</div>`}
  ${sect("Відділення · "+P.off.length)}${P.off.map(pid=>{const p=PL[pid];return `<div class="lrow" style="margin-bottom:6px"><span class="${poTerm(p.cid)?"warn":"mut"}">${ic("mail")}</span><div><b>${plName(p)}</b><div class="note">${poTerm(p.cid)?"Працює":"Чекає на поштовий термінал у країні"}</div></div>${P.term.includes(pid)?"":`<button class="btn sm" data-act="poOffX" data-arg="${pid}" aria-label="Закрити">${ic("trash")}</button>`}</div>`}).join("")||`<div class="note">Ще немає відділень.</div>`}
  ${sect("Відкрити відділення")}<div class="note" style="margin-bottom:6px">У будь-якому місті країни, де у вас є логістичний термінал. Також — з картки міста на мапі. Більші міста — більше клієнтів.</div>${PL.filter(p=>!P.off.includes(p.id)&&CO.hubs.some(h=>h.lvl>=3&&PL[h.pid].cid===p.cid)).sort((a,b)=>(poTerm(b.cid)?1:0)-(poTerm(a.cid)?1:0)||b.pop-a.pop).slice(0,14).map(p=>`<div class="lrow" style="margin-bottom:6px"><span class="mut">${ic("pin")}</span><div><b>${plName(p)}</b><div class="note">${fmtSP(p.pop)}${poTerm(p.cid)?" · є термінал":" · немає терміналу в країні"}</div></div><button class="btn sm ${CO.cash>=poOffCost(p)?"pri":""}" data-act="poOff" data-arg="${p.id}">${ic("plus")}${fmtUSD(poOffCost(p))}</button></div>`).join("")}`};
WINS.poShip=()=>{const P=poInit(),d=P.day;const cnt=t=>P.veh.filter(v=>v.t===t).length;
  return poHead("Відправки й поштова техніка")+`<div class="grid4">${stat("Прийнято за день",(d.par||0).toLocaleString("uk-UA"),"посилок","")}${stat("Доставлено",(d.done||0).toLocaleString("uk-UA"),"вчасно",d.late?"warn":"")}${stat("Затримано",(d.late||0).toLocaleString("uk-UA"),d.par?Math.round(d.late/d.par*100)+"%":"—",T("Затримки","Посилки, на які забракло потужності: терміналів, фургонів, операторів. Затримки б'ють по репутації."),d.late?"bad":"")}${stat("Потужність",Math.round(d.cap||0).toLocaleString("uk-UA"),"посилок/день",T("Потужність","Найменше з трьох: обробка в терміналах, вантажівки й фургони, оператори."))}</div>
  ${sect("Вузькі місця")}<div class="kv"><span>Обробка в терміналах</span><b class="num">${Math.round(P.term.length*3500*(1+.3*poMsk("pdir"))).toLocaleString("uk-UA")}/день</b><span>Фургони останньої милі + магістраль</span><b class="num">${Math.round(cnt("pvan")*600+P.veh.filter(v=>v.t!=="pvan").reduce((a,v)=>a+PVT[v.t].cap,0)*.15).toLocaleString("uk-UA")}/день</b><span>Оператори й кур'єри (${P.staff})</span><b class="num">${(P.staff*220).toLocaleString("uk-UA")}/день</b></div>
  <div class="row sp" style="margin:10px 0"><span>Оператори й кур'єри пошти: <b>${P.staff}</b></span><div class="row"><button class="btn sm" data-act="poStaff" data-arg="-5">−5</button><button class="btn sm pri" data-act="poStaff" data-arg="5">+5 · ${fmtUSD(800*wageK(G.me)*5*(1-.3*poMsk("phr")))}</button><button class="btn sm pri" data-act="poStaff" data-arg="25">+25</button></div></div>
  ${sect("Поштова техніка")}<div class="note" style="margin-bottom:8px">Окремий парк: автомашини, літаки й кораблі (без потягів). Стоїть у поштових терміналах, по 40 одиниць на термінал. Жовті точки на мапі — поштові рейси.</div>
  <div class="grid2">${Object.entries(PVT).map(([t,T])=>{const lock=CO.tier<T.tier;return `<div class="blk" style="${lock?"opacity:.5":""}"><div class="row sp"><div class="row" style="gap:8px"><span style="color:rgb(${PO_Y})">${ic(T.ic)}</span><b>${T.n}</b></div><span class="pill">${cnt(t)}</span></div><div class="note" style="margin:6px 0">${T.d}</div>
    ${lock?`<span class="pill">${ic("lock")}Ліцензія «${LIC[T.tier].n}»</span>`:`<div class="row" style="gap:6px"><button class="btn sm ${CO.cash>=T.cost?"pri":""}" data-act="poBuy" data-arg="${t}">${ic("plus")}${fmtUSD(T.cost)}</button>${cnt(t)?`<button class="btn sm" data-act="poSell" data-arg="${t}">${ic("coins")}Продати</button>`:""}</div>`}</div>`}).join("")}</div>`};
{const _ps=WINS.poShip;WINS.poShip=()=>{let h=_ps();if(typeof lpOn!=="function"||!lpOn())return h;const P=poInit();if(!P.term.length)return h;const f=P.term.includes(UI.lpF)?UI.lpF:P.term[0];
  const dst=P.term.filter(x=>x!==f).concat(P.off.filter(o=>!P.term.includes(o)&&o!==f)).slice(0,24);
  return h+`${sect("Прокласти поштовий рейс")}<div class="note" style="margin-bottom:8px">Оберіть термінал відправлення і пункт призначення — далі прокладіть маршрут на мапі (авто, корабель, літак).</div>
   <div class="seg" style="flex-wrap:wrap;margin-bottom:8px">${P.term.map(t=>`<button class="${t===f?"on":""}" data-act="lpPostFrom" data-arg="${t}">${ic("mail")} ${esc(PL[t].name)}</button>`).join("")}</div>
   ${dst.map(d=>`<div class="lrow" style="margin-bottom:6px"><span style="color:rgb(${PO_Y})">${ic(P.term.includes(d)?"building":"mail")}</span><div><b>${plName(PL[d])}</b><div class="note">${P.term.includes(d)?"поштовий термінал":"відділення"} · ${PL[d].cid===PL[f].cid?"всередині країни":"інша країна"}</div></div><button class="btn sm" data-act="lpPost" data-arg="${f}:${d}">${ic("road")}Прокласти маршрут</button></div>`).join("")||`<div class="note">Немає куди: відкрийте ще відділення або термінал.</div>`}`}}
ACT.lpPostFrom=t=>{UI.lpF=+t;renderWin()};
WINS.poRev=()=>{const P=poInit(),l=P.lm,m=P.m,ref=poRef(G.me);const rng=(k,v,min,max,step,lbl)=>`<div class="row sp" style="gap:10px;margin:6px 0"><span style="min-width:150px">${lbl}</span><input type="range" class="rng" min="${min}" max="${max}" step="${step}" value="${v}" oninput="ACT.poPrice('${k}:'+this.value);this.nextElementSibling.textContent=(${k==="mix"?"Math.round(this.value*100)+'%'":k==="base"?"'$'+(+this.value).toFixed(2)":"'×'+(+this.value).toFixed(2)"})"><b class="num" style="min-width:60px;text-align:right">${k==="mix"?Math.round(v*100)+"%":k==="base"?"$"+(+v).toFixed(2):"×"+(+v).toFixed(2)}</b></div>`;
  const avg=P.price.base*PO_SIZES.reduce((a,s)=>a+s[3]*P.price.size[s[0]],0)*(1+P.mix.exp*(P.price.exp-1)),refAvg=ref*PO_SIZES.reduce((a,s)=>a+s[3]*s[4],0)*(1+P.mix.exp*.9),rel=avg/refAvg;
  const eco=P.mgr.peco,fc=eco?(()=>{const acc=eco.skill/10,err=(1-acc)*.35,base=(P.day.done||0)*30,noise=1+((G.date.m*7919)%100/100-.5)*err*2;return{par:Math.round(base*(1+P.share*2)*noise),rev:Math.round((P.day.rev||0)*30*noise),load:P.day.cap?Math.round(P.day.dem/P.day.cap*100):0,acc:Math.round(acc*100)}})():null;
  return poHead("Тарифи, доходи й команда")+`<div class="grid4">${stat("Дохід за день",fmtUSD(P.day.rev||0),"",T("Дохід","Оплата за доставлені посилки."))}${stat("Витрати за день",fmtUSD(P.day.cost||0),"техніка, люди, оренда","")}${stat("Репутація",P.rep.toFixed(2)+" ★",P.angry>15?`<span class="bad">клієнти обурені</span>`:"клієнти задоволені","",P.rep>=3.8?"good":P.rep<2.5?"bad":"")}${stat("Частка ринку",(P.share*100).toFixed(1)+"%","у містах з відділеннями","")}</div>
  ${sect("Тарифи")}<div class="note" style="margin-bottom:6px">Ринкова ціна посилки 1 кг у вашій країні ≈ ${fmtUSD(ref)}. Дорожчі тарифи — більше грошей з посилки, але менше клієнтів; понад +25% до ринку клієнти обурюються і йдуть до конкурентів.</div>
  ${rng("base",P.price.base,1,20,.25,"Базовий тариф (до 1 кг)")}
  ${PO_SIZES.map(([k,n,d])=>rng(k,P.price.size[k],.3,12,.1,`${n} · ${d}`)).join("")}
  ${rng("exp",P.price.exp,1,4,.05,"Надбавка за експрес (1 день)")}
  ${rng("mix",P.mix.exp,0,1,.05,"Частка експрес-посилок")}
  <div class="row sp" style="margin-top:8px"><span class="note">Середній чек</span><b class="num ${rel>1.25?"bad":rel<.85?"good":""}">${fmtUSD(avg)} · ${rel>1?"+":""}${Math.round((rel-1)*100)}% до ринку</b></div>
  <div class="note" style="margin-top:6px">Терміни: стандарт ${PO_SPEED[0][2]}, експрес ${PO_SPEED[1][2]}. Якщо потужності бракує, посилки запізнюються — репутація падає, клієнтів меншає.</div>
  ${sect("Команда пошти")}<div style="display:flex;flex-direction:column;gap:8px">${PO_MG.map(([id,n,i,d])=>{const g=P.mgr[id],cs=P.cand[id]||[];return g?`<div class="blk"><div class="row sp"><div class="row" style="gap:6px"><span class="acc">${ic(i)}</span><b>${n}</b><span class="pill good">у штаті</span></div><button class="btn sm" data-act="poFire" data-arg="${id}">${ic("trash")}Звільнити</button></div><div class="note" style="margin:4px 0 6px">${d}</div><div class="row sp" style="padding:6px 0;border-top:1px solid var(--line)"><div><b>${esc(g.name)}</b>${g.age?", "+g.age:""} <span class="note">${g.trait?"· "+esc(g.trait)+" ":""}· навичка ${"★".repeat(Math.round(g.skill/2))}${"☆".repeat(5-Math.round(g.skill/2))}</span></div><span class="num">${fmtUSD(g.sal)}/міс</span></div></div>`
   :`<div class="blk"><div class="row sp"><div class="row" style="gap:6px"><span class="mut">${ic(i)}</span><b>${n}</b><span class="pill">вакансія</span></div><button class="btn sm" data-act="poRecand" data-arg="${id}">${ic("refresh")}Інші кандидати · ${fmtUSD(1500*priceK(G.me))}</button></div><div class="note" style="margin:4px 0 8px">${d}</div>
    ${cs.map((c,k)=>`<div class="row sp" style="padding:6px 0;border-top:1px solid var(--line)"><div><b>${esc(c.name)}</b>${c.age?", "+c.age:""} <span class="note">${c.trait?"· "+esc(c.trait)+" ":""}· навичка ${"★".repeat(Math.round(c.skill/2))}${"☆".repeat(5-Math.round(c.skill/2))}</span></div><div class="row"><span class="num">${fmtUSD(c.sal)}/міс</span><button class="btn sm ${CO.cash>=c.sal*2?"pri":""}" data-act="poHire" data-arg="${id}:${k}" ${CO.cash>=c.sal*2?"":"disabled"}>Найняти</button></div></div>`).join("")}</div>`}).join("")}</div>
  ${sect("Прогноз економіста")}${fc?`<div class="kv"><span>Посилок наступного місяця</span><b class="num">≈ ${fc.par.toLocaleString("uk-UA")}</b><span>Дохід наступного місяця</span><b class="num">≈ ${fmtUSD(fc.rev)}</b><span>Завантаження потужностей</span><b class="num ${fc.load>100?"bad":fc.load>85?"warn":"good"}">${fc.load}%${fc.load>100?" — потрібні фургони, оператори або термінал":""}</b><span>Точність прогнозу</span><b class="num">${fc.acc}%</b></div>`:`<div class="note">Найміть економіста, щоб бачити прогноз попиту, доходу й завантаження.</div>`}
  ${sect("Місяць")}<div class="kv"><span>Цей місяць</span><b class="num">${fmtUSD(m.rev-m.cost,true)} · ${m.par.toLocaleString("uk-UA")} посилок</b><span>Минулий</span><b class="num">${l?fmtUSD(l.rev-l.cost,true)+" · "+l.par.toLocaleString("uk-UA")+" посилок":"—"}</b></div>`};

/* rail buttons appear only with the DLC on */
RAIL.push("|",["poOffices","mail","Пошта: відділення","Поштові відділення в містах і поштові термінали (адаптація логістичних терміналів)."],["poShip","send","Пошта: відправки","Потік посилок, вузькі місця, поштова техніка й персонал."],["poRev","coins","Пошта: тарифи й доходи","Ціни за вагу й терміни, репутація, менеджери, прогнози економіста."]);
{const ok=railOK,PO_W=new Set(["poOffices","poShip","poRev"]);railOK=id=>PO_W.has(id)?poOn():ok(id)}
{const _b=buildHUD;buildHUD=function(){_b();if(G.co)guard("Пошта",()=>{const r=$("#rail");if(!r)return;r.querySelectorAll('[data-arg^="po"]').forEach(b=>b.style.color=`rgb(${PO_Y})`)})}}

/* ---------- main-menu DLC card ---------- */
function dlcCard(){const c=document.querySelector(".dlcs .dlc");if(!c)return;const on=!!SET.dlcPost;c.style.setProperty("--dlcbg",`url(${DLC_POST_BG})`);
  c.innerHTML=`<div class="dlc-t"><div class="row" style="gap:8px"><span class="dlc-tag" style="border-color:rgb(${PO_Y});color:rgb(${PO_Y})">DLC</span><b>Postal Hub — Пошта</b></div><div class="note">Масштабні логістичні хаби, світові відділення та нові виклики! Очоліть напрям міжнародних поштових доставок та виведіть свою кар'єру на глобальний рівень вже зараз!</div><button class="btn sm ${on?"pri":""}" data-act="dlcPost" style="align-self:flex-start;margin-top:2px">${on?ic("check")+"Увімкнено":"Увімкнути"}</button></div><div class="dlc-img" style="border:0;background:none"></div><button class="dlcx" data-act="dlcCloseCard" data-arg="0" aria-label="Закрити"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button>`}
ACT.dlcPost=()=>{SET.dlcPost=!SET.dlcPost;saveSettings();dlcCard();toast(SET.dlcPost?"good":"",SET.dlcPost?"Postal Hub увімкнено":"Postal Hub вимкнено","Діє в режимі логістичної компанії")};
setTimeout(dlcCard,0);

/* the DLC panel can be closed for this visit; it is back after the page reloads */
ACT.dlcCloseCard=i=>{const cs=document.querySelectorAll(".dlcs .dlc");const c=cs[+i];if(c)c.classList.add("closed");if(cs[0]&&cs[0].classList.contains("closed")&&cs[1]&&cs[1].classList.contains("closed"))ACT.dlcClose()};
ACT.dlcClose=()=>{const d=document.querySelector(".dlcs");if(d)d.classList.add("closed")};

/* clicking a yellow dot: route tracer + card, as for ordinary trips */
function poRoute(g,t,T,Pp,dpr){const f=clamp((T-t.t0)/t.tot,0,1),j={p:t.p},c=coCum(j),n=c.length,s0=f*t.len,pts=[];
  if(t.mode==="air"){for(let k=0;k<=40;k++){const ff=f+(1-f)*k/40,q=coPosAt(j,ff*t.len);pts.push([q[0],Math.sin(Math.PI*ff)*coArcH(t.len),q[1]])}}
  else{const q0=coPosAt(j,s0);pts.push([q0[0],0,q0[1]]);for(let i=0;i<n;i++)if(c[i]*CO_DU>s0)pts.push([t.p[i*2],0,t.p[i*2+1]])}
  wroute(g,(x,y,z)=>Pp(x,y,z),pts,PO_Y,dpr)}
function poCard(t){const el=$("#ucard"),A=PL[t.a],B=PL[t.b],T=coNow(),f=clamp((T-t.t0)/t.tot,0,1),kind={first:"Збір посилок у відділенні → термінал",last:"Термінал → відділення: доставка",trunk:"Між терміналами"}[t.kind];
  el.innerHTML=`<div class="uc-head"><div class="uc-ic" style="color:rgb(${PO_Y})">${ic(t.mode==="air"?"plane":t.mode==="sea"?"ship":"truck")}</div><div class="grow"><span class="lbl">${esc(CO.post.brand)}</span><b>Поштовий рейс</b><div class="note">${kind}</div></div><button class="xbtn" data-act="poUcClose" aria-label="Закрити">${ic("close")}</button></div>
   <div class="uc-body"><div class="uc-route"><div class="row"><img src="${G.C[A.cid].flag}" alt="">${esc(A.name)}</div><div class="uc-arrow">${ic("down")}</div><div class="row"><img src="${G.C[B.cid].flag}" alt="">${esc(B.name)}</div></div>
   <dl class="kv"><dt>Відстань</dt><dd>${kmS(t.len)}</dd><dt>Прибуття через</dt><dd>${daysS(Math.max(0,t.t0+t.tot-T))}</dd></dl>
   <div><div class="row sp"><span class="lbl">Маршрут</span><span class="num mut">${Math.round(f*100)}%</span></div><div class="meter" style="margin-top:6px"><i style="width:${(f*100).toFixed(1)}%;background:rgb(${PO_Y})"></i></div></div></div>`;el.hidden=false}
ACT.poUcClose=()=>{PO_SEL=null;$("#ucard").hidden=true};
{const _cc=coClick;coClick=function(x,y){if(poOn()&&!(typeof ED!=="undefined"&&ED.on)){let b=null,bd=12;for(const h of PO_HITS){const d=Math.hypot(h.x-x,h.y-y);if(d<bd){bd=d;b=h}}if(b){CO_SEL=null;PO_SEL=b.t.id;poCard(b.t);return true}if(PO_SEL){PO_SEL=null;$("#ucard").hidden=true}}return _cc(x,y)}}
setInterval(()=>{if(PO_SEL&&CO.post){const t=CO.post.trips.find(x=>x.id===PO_SEL);if(t)poCard(t)}},700);
/* offices: shown as a separate yellow mail box next to the city's transport icons */
const poHasOff=pid=>!!(poOn()&&CO.post&&CO.post.off.includes(pid));
{const _f=coChipFilter;coChipFilter=function(){_f();if(!G.board||!CITY_EL.length)return;for(const c of CITY_EL){if(!c.cap)continue;const pl=PL.find(q=>q.type==="cap"&&q.cid===c.cid),cb=c.el.querySelector(".cb em");if(!cb||!pl)continue;const fac=cb.querySelector(".fac");if(!fac)continue;let m=fac.querySelector(".pmail");
  if(poHasOff(pl.id)){if(!m){m=document.createElement("span");m.className="pmail";m.innerHTML=ic("mail");fac.appendChild(m)}}else if(m)m.remove()}}}
function poChips(){CITY_KEY="";try{coChipFilter()}catch(e){}REDRAW=true}
/* opening an office from the city card */
function poInspBlk(p){if(!poOn())return"";const P=poInit(),has=P.off.includes(p.id),term=CO.hubs.some(h=>h.lvl>=3&&PL[h.pid].cid===p.cid),post=poTerm(p.cid),c=poOffCost(p);
  return `${sect("Пошта")}<div class="blk"><div class="row sp wrap" style="gap:8px"><div class="row" style="gap:8px"><span style="color:rgb(${PO_Y})">${ic("mail")}</span><div><b>${has?"Поштове відділення працює":"Поштового відділення немає"}</b><div class="note">${has?(post?"Приймає й видає посилки":"Чекає, поки логістичний термінал країни адаптують під пошту"):term?"Звідси відправлятимуть і сюди доставлятимуть посилки":"Потрібен ваш логістичний термінал у цій країні"}</div></div></div>
   ${has?"":`<button class="btn sm ${term&&CO.cash>=c?"pri":""}" data-act="poOff" data-arg="${p.id}" ${term?"":"disabled"}>${ic("plus")}Відкрити відділення · ${fmtUSD(c)}</button>`}</div></div>`}

ACT.poRecand=id=>{const c=Math.round(1500*priceK(G.me));if(CO.cash<c)return toast("warn","Бракує грошей",fmtUSD(c));CO.cash-=c;CO.m.other+=c;poMgrCand(id);renderWin()};
