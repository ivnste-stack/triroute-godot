/* =====================================================================
   Logistics: yearly permits, fleet upgrades, world prices, firms in cities, port/airport specialisation
   ===================================================================== */
// --- extra cargo types
CARGO.find(c=>c.id==="fuel").dg=1;CARGO.find(c=>c.id==="food").reefer=1;CARGO.find(c=>c.id==="med").reefer=1;
CARGO.push(
 {id:"chem",n:"Хімікати (небезпечний вантаж)",ic:"flame",t:[5,3000],k:1.45,fr:.03,val:2500,dg:1},
 {id:"gas",n:"Скраплений газ (небезпечний вантаж)",ic:"gas",t:[10,4000],k:1.4,fr:.02,val:800,dg:1},
 {id:"expl",n:"Промислова вибухівка",ic:"bolt",t:[1,200],k:2.3,fr:.04,val:6000,dg:1,cls:"expl"},
 {id:"rad",n:"Медичні ізотопи (радіоактивні)",ic:"atom",t:[.05,3],k:4.5,fr:.05,val:250000,dg:1,cls:"rad"},
 {id:"rcont",n:"Рефконтейнери: м'ясо, фрукти, риба",ic:"leaf",t:[300,12000],k:.95,fr:.02,val:3500,reefer:1});
CARGO.forEach(c=>CARGO_I[c.id]=c);

/* ---------- permits: paid every year ---------- */
const PERM=[
 {id:"gdp",n:"GDP: фармацевтика й вакцини",ic:"pill",fee:12000,tier:1,d:"Ліки й вакцини з контролем температури. Аудит складів і рефрижераторів щороку."},
 {id:"adr",n:"ADR: небезпечні вантажі (авто й залізниця)",ic:"barrel",fee:18000,tier:2,d:"Пальне, хімікати, скраплений газ. Водії з допуском, маркування, маршрути в об'їзд міст."},
 {id:"valu",n:"Перевезення цінностей",ic:"gem",fee:45000,tier:3,d:"Банкноти, золото, коштовності: броньовані машини й озброєна охорона."},
 {id:"expl",n:"Вибухові речовини (клас 1)",ic:"bolt",fee:60000,tier:3,need:"adr",d:"Промислова вибухівка для кар'єрів і шахт. Потрібен ADR."},
 {id:"rad",n:"Радіоактивні матеріали (клас 7)",ic:"atom",fee:180000,tier:4,need:"adr",d:"Медичні ізотопи й паливо для АЕС: дозиметристи і спецконтейнери. Потрібен ADR."},
 {id:"imdg",n:"IMDG: небезпечні вантажі морем",ic:"anchor",fee:90000,tier:5,d:"Хімія, газ і пальне в контейнерах і танкерах."},
 {id:"dgr",n:"IATA DGR: небезпечні вантажі літаком",ic:"plane",fee:140000,tier:6,d:"Хімікати, ізотопи й вибухонебезпечні вантажі на борту."}];
const PERM_I={};PERM.forEach(p=>PERM_I[p.id]=p);
function permNeed(cg,mode){const r=[];if(!cg)return r;if(cg.dg)r.push(mode==="sea"?"imdg":mode==="air"?"dgr":"adr");if(cg.cls)r.push(cg.cls);if(cg.id==="med")r.push("gdp");if(cg.id==="gold")r.push("valu");return r}
const permOK=id=>!!(CO.perm&&CO.perm[id]&&CO.perm[id].until>G.day);
function permFee(id){const p=PERM_I[id];return Math.round(p.fee*(.55+.45*priceK(hqP().cid))*(1+.05*(CO.conf||[]).length)/100)*100}
ACT.coPerm=id=>{const p=PERM_I[id];if(!p||CO.tier<p.tier)return;if(p.need&&!permOK(p.need))return toast("warn","Спершу потрібна інша ліцензія",PERM_I[p.need].n);const f=permFee(id);if(CO.cash<f)return toast("warn","Бракує грошей",fmtUSD(f));
  CO.perm=CO.perm||{};const cur=CO.perm[id];CO.cash-=f;CO.m.other+=f;CO.perm[id]={until:Math.max(G.day,cur&&cur.until||0)+365,auto:cur?cur.auto:true};toast("good",cur&&cur.until>G.day?"Ліцензію продовжено":"Ліцензію отримано",`${p.n} · ${fmtUSD(f)} на рік`);updateHUD();renderWin()};
ACT.coPermAuto=id=>{if(CO.perm&&CO.perm[id]){CO.perm[id].auto=!CO.perm[id].auto;renderWin()}};
function permDay(){if(!CO.perm)return;for(const id in CO.perm){const P=CO.perm[id],p=PERM_I[id],left=Math.round(P.until-G.day);
  if(left===30&&!P.warn){P.warn=1;coNews("warn","doc",`Через 30 днів спливає ліцензія «${p.n}»`)}
  if(P.until<=G.day&&!P.gone){const f=permFee(id);if(P.auto&&CO.cash>=f){CO.cash-=f;CO.m.other+=f;P.until+=365;P.warn=0;coNews("good","doc",`Ліцензію «${p.n}» продовжено ще на рік: ${fmtUSD(f)}`)}
    else{P.gone=1;coNews("bad","doc",`Ліцензія «${p.n}» сплила: такі вантажі більше не можна брати`);toast("bad","Ліцензія сплила",p.n)}}
  if(P.until>G.day)P.gone=0}}

/* ---------- fleet upgrades ---------- */
const UPG=[
 {id:"eco",n:"Тренінг економного водіння",ic:"bulb",cost:25000,tier:1,fx:{road:.06},d:"Водії плавно розганяються й гальмують: −6% пального на авто."},
 {id:"tyre",n:"Шини з низьким опором кочення",ic:"gear",cost:70000,tier:2,fx:{road:.04},rep:.05,d:"−4% пального на авто, шини служать довше: −5% на ремонт."},
 {id:"aero",n:"Аеродинамічні обтічники",ic:"wind",cost:150000,tier:2,fx:{road:.07},d:"Спойлери й бокові екрани на причепах: −7% пального на трасі."},
 {id:"shop",n:"Власна СТО",ic:"gear",cost:400000,tier:2,rep:.25,mo:6000,d:"Ремонт, евакуатор і утримання техніки на 25% дешевші. Утримання СТО $6 тис./міс."},
 {id:"tele",n:"Телематика й оптимізація маршрутів",ic:"target",cost:350000,tier:3,fx:{road:.05,rail:.05,sea:.05,air:.05},gps:.5,d:"−5% пального на всіх видах техніки, збої GPS удвічі рідші."},
 {id:"pred",n:"Предиктивне обслуговування",ic:"cpu",cost:900000,tier:4,brk:.4,rep:.1,d:"Датчики попереджають про несправність: поломок у дорозі на 40% менше."},
 {id:"hyb",n:"Гібридні тягачі",ic:"bolt",cost:2500000,tier:4,fx:{road:.15},d:"−15% пального на авто."},
 {id:"loco",n:"Рекуперація на локомотивах",ic:"train",cost:3000000,tier:4,fx:{rail:.12},d:"Енергія гальмування повертається в мережу: −12% на залізниці."},
 {id:"slow",n:"Оптимізація швидкості суден",ic:"ship",cost:3500000,tier:5,fx:{sea:.12},d:"Економічний режим і очищення корпусу: −12% пального в морі."},
 {id:"wing",n:"Вінглети й легкі контейнери",ic:"plane",cost:6000000,tier:6,fx:{air:.08},d:"−8% пального на літаках."}];
const hasU=id=>!!(CO.upg&&CO.upg[id]);
function fuelK(mode){let k=1;for(const u of UPG)if(hasU(u.id)&&u.fx&&u.fx[mode])k*=1-u.fx[mode];return k}
function repK(){let k=CO.parts||1;for(const u of UPG)if(hasU(u.id)&&u.rep)k*=1-u.rep;return k}
function brkK(){let k=1;for(const u of UPG)if(hasU(u.id)&&u.brk)k*=1-u.brk;return k}
function gpsK(){let k=1;for(const u of UPG)if(hasU(u.id)&&u.gps)k*=1-u.gps;return k}
ACT.coUpg=id=>{const u=UPG.find(x=>x.id===id);if(!u||hasU(id)||CO.tier<u.tier)return;const c=Math.round(u.cost*(.6+.4*(CO.parts||1)));if(CO.cash<c)return toast("warn","Бракує грошей",fmtUSD(c));
  CO.cash-=c;CO.m.other+=c;CO.upg=CO.upg||{};CO.upg[id]={d:G.day};toast("good","Модернізацію впроваджено",u.n);updateHUD();renderWin()};

/* ---------- world prices: fuel and spare parts follow wars, sanctions and closures ---------- */
function bizPrices(){CO.parts=CO.parts||1;const conf=(CO.conf||[]).length,cls=CO.cls||[],sanc=cls.filter(c=>/санкц|Торговельна/i.test(c.why)).length,cty=cls.filter(c=>c.kind==="cty").length,hur=(CO.wx||[]).filter(w=>w.k==="hur").length;
  const fT=1+.1*conf+.04*sanc+.03*cty+.03*hur,pT=1+.07*conf+.08*sanc+.03*cty;
  CO.fuel=clamp(CO.fuel+(fT-CO.fuel)*.015+CO.fuel*rnd(-.006,.006),.6,2.2);CO.parts=clamp(CO.parts+(pT-CO.parts)*.015+CO.parts*rnd(-.004,.004),.7,2)}
function bizWhy(){const conf=(CO.conf||[]).length,cls=CO.cls||[],sanc=cls.filter(c=>/санкц|Торговельна/i.test(c.why)).length,cty=cls.filter(c=>c.kind==="cty").length;const r=[];
  if(conf)r.push(`${conf} воєнн${conf===1?"ий конфлікт":"і конфлікти"}: пальне й запчастини дорожчають`);if(sanc)r.push(`санкції й торговельні війни (${sanc}): дорожчають запчастини`);if(cty)r.push(`закриті країни (${cty}): ланцюги постачання рвуться`);
  if(!r.length)r.push("у світі спокійно: ціни повертаються до норми");return r}
function bizMonth(){if(!G.co)return;if(hasU("shop")){const c=UPG.find(u=>u.id==="shop").mo;CO.cash-=c;CO.m.upkeep+=c}
  if(chance(.07)){const E=[["Дефіцит мікрочипів: запчастини й електроніка для техніки подорожчали",rnd(1.12,1.3)],["Нові мита на імпортні запчастини",rnd(1.08,1.15)],["Обвал цін на сталь: запчастини подешевшали",rnd(.85,.93)]];const e=pick(E);CO.parts=clamp((CO.parts||1)*e[1],.7,2);coNews(e[1]>1?"bad":"good","gear",`${e[0]} (${e[1]>1?"+":"−"}${Math.abs((e[1]-1)*100).toFixed(0)}%)`)}}
{const _cm=coMonth;coMonth=function(){_cm();guard("Бізнес · місяць",bizMonth)}}
function bizDay(){if(!G.co)return;permDay()}

/* ---------- firms in every city: senders and receivers of cargo ---------- */
const IND={
 agro:{n:"Агрохолдинг",ic:"wheat",a:["Агро","Нива","Колос","Лан","Зерно","Степ"],b:["трейд","холдинг","експорт","інвест"]},
 food:{n:"Харчове виробництво",ic:"leaf",a:["Смак","Молоко","Хліб","Фрукт","Свіжо","Добро"],b:["фуд","пром","дар","продукт"]},
 pharma:{n:"Фармацевтика",ic:"pill",a:["Фарм","Біо","Медик","Віта","Здраво"],b:["фарм","лаб","мед","ген"]},
 tech:{n:"Електроніка",ic:"cpu",a:["Техно","Сигма","Кібер","Електро","Цифро"],b:["тех","системс","трон","лайн"]},
 retail:{n:"Торговельна мережа",ic:"house",a:["Мега","Дім","Еко","Родина","Квадрат","Гуд"],b:["маркет","ритейл","плюс","мол"]},
 build:{n:"Будівництво",ic:"factory",a:["Буд","Граніт","Бетон","Мур","Каркас"],b:["інвест","монтаж","буд","девелопмент"]},
 auto:{n:"Автоімпорт",ic:"truck",a:["Авто","Мотор","Драйв","Кар"],b:["імпорт","дилер","центр","моторс"]},
 energy:{n:"Енергетика й хімія",ic:"barrel",a:["Нафто","Газо","Хім","Енерго","Петро"],b:["термінал","хім","пром","ресурс"]},
 metal:{n:"Металургія й гірництво",ic:"ore",a:["Сталь","Руда","Метал","Залізо","Кремінь"],b:["комбінат","прокат","видобуток","груп"]},
 port:{n:"Контейнерний термінал",ic:"anchor",a:["Порт","Карго","Контейнер","Причал"],b:["термінал","сервіс","лайн","хаб"]},
 aero:{n:"Авіаремонт",ic:"plane",a:["Авіа","Турбо","Крило","Аеро"],b:["ремонт","сервіс","техніка","мотор"]},
 bank:{n:"Банк",ic:"gem",a:["Нац","Кредит","Капітал","Золотий","Перший"],b:["банк","інвест","фінанс","резерв"]},
 nuke:{n:"Ядерна медицина й енергетика",ic:"atom",a:["Атом","Ізотоп","Реактор","Ядро"],b:["мед","енерго","сервіс","центр"]},
 furn:{n:"Меблева фабрика",ic:"house",a:["Дуб","Комфорт","Інтер'єр","Затишок"],b:["меблі","фабрика","дизайн","стиль"]},
 aid:{n:"Гуманітарна місія",ic:"heart",fixed:["Фонд «Надія»","Місія «Світанок»","Фонд «Відродження»","Червоний півмісяць","Карітас-допомога"]}};
const CG_IND={parcel:[["retail","tech"],["retail"]],food:[["agro","food"],["retail","food"]],med:[["pharma"],["pharma","retail"]],elec:[["tech"],["retail","tech"]],furn:[["furn"],["retail"]],build:[["build","metal"],["build"]],
 grain:[["agro"],["food","agro","port"]],cars:[["auto","port"],["auto"]],fuel:[["energy"],["energy","port"]],cont:[["port"],["port","retail"]],metal:[["metal"],["build","metal","port"]],engines:[["aero"],["aero"]],
 gold:[["bank"],["bank"]],aid:[["aid"],["aid"]],chem:[["energy"],["energy","pharma","agro"]],gas:[["energy"],["energy"]],expl:[["energy","metal"],["metal","build"]],rad:[["nuke"],["nuke","pharma"]],rcont:[["port","agro","food"],["retail","food","port"]]};
const FIRMS=new Map();
function firmName(ind,r){const I=IND[ind];if(I.fixed)return I.fixed[Math.floor(r()*I.fixed.length)];const nm=I.a[Math.floor(r()*I.a.length)]+I.b[Math.floor(r()*I.b.length)];
  const f=Math.floor(r()*5);return ind==="bank"?`АТ «${nm}»`:f===0?`ТОВ «${nm}»`:f===1?`ПрАТ «${nm}»`:f===2?`Група «${nm}»`:`«${nm}»`}
function firmsOf(pid){let L=FIRMS.get(pid);if(L)return L;const p=PL[pid],r=mulberry(((SEED||1)*31+pid*7919)>>>0);L=[];
  const n=Math.max(1,Math.round(({cap:9,big:7,city:4,town:2,vil:1}[p.type]||2)*(p.type==="vil"?1:clamp(.75+Math.sqrt(p.pop||.1)*.35,.75,1.6)))),pool=["retail","food","build","tech","furn","agro","pharma","auto","metal","energy"];if(p.type==="vil"||p.type==="town")pool.push("agro","agro","food");
  const want=["retail"];if(p.port!=null)want.push("port");if(p.air&&p.type!=="town")want.push("aero");if(p.type==="cap")want.push("bank","pharma");
  while(want.length<n)want.push(pool[Math.floor(r()*pool.length)]);const seen=new Set();
  for(const ind of want.slice(0,n)){let nm=firmName(ind,r),k=0;while(seen.has(nm)&&k++<5)nm=firmName(ind,r);seen.add(nm);L.push({n:nm,ind})}FIRMS.set(pid,L);return L}
function firmFor(pid,inds,salt){const L=firmsOf(pid),m=L.filter(f=>inds.includes(f.ind));if(m.length)return m[Math.abs(salt)%m.length];
  const r=mulberry(((SEED||1)*131+pid*31+inds[0].length*977+salt)>>>0),f={n:firmName(inds[0],r),ind:inds[0],extra:1};L.push(f);return f}
function bizFirmsK(k){const ii=CG_IND[k.cg]||[["retail"],["retail"]];k.fs=firmFor(k.src??k.from,ii[0],k.id).n;k.ft=firmFor(k.dst??k.to,ii[1],k.id*7+3).n}
const kFirms=k=>{if(!k||k.id===0)return null;if(!k.fs)bizFirmsK(k);return k};
{const _cg=coGen;coGen=function(){const k=_cg();if(!k)return k;{const nd=permNeed(CARGO_I[k.cg],k.mode).filter(id=>!permOK(id));if(nd.length&&(nd.some(id=>PERM_I[id].tier>CO.tier)||chance(.8)))return null}bizFirmsK(k);return k}}

/* ---------- node specialisation: reefer plugs and deep berths in ports, heavy runways in airports ---------- */
const NSPEC=new Map();
function nodeSpec(p){let s=NSPEC.get(p.id);if(s)return s;const h=(((p.id+1)*2654435761)^((SEED||1)*40503))>>>0,a=h%100,b=(h>>>8)%100,c=(h>>>16)%100;
  s={reefer:p.port!=null&&(p.type==="cap"||p.type==="big"||(p.type==="city"&&a<60)||(p.type==="town"&&a<25)),deep:p.port!=null&&(p.type==="cap"||(p.type==="big"&&b<70)||(p.type==="city"&&b<30)),
    heavy:!!p.air&&(p.type==="cap"||(p.type==="big"&&c<65)||(p.type==="city"&&c<20))};NSPEC.set(p.id,s);return s}
function specWhy(k,t){const A=PL[k.from],B=PL[k.to],cg=CARGO_I[k.cg];
  if(k.mode==="sea"&&cg&&cg.reefer)for(const p of [A,B])if(!nodeSpec(p).reefer)return `Порт ${p.name} не приймає рефрижераторні контейнери`;
  if(t==="bulk")for(const p of [A,B])if(!nodeSpec(p).deep)return `Порт ${p.name} мілководний: балкер не зайде`;
  if(t==="jumbo"||t==="mega")for(const p of [A,B])if(!nodeSpec(p).heavy)return `Аеропорт ${p.name}: коротка смуга для важкого літака`;
  return null}
function specHTML(p){const s=nodeSpec(p),y=(ok,t)=>`<span class="${ok?"good":"mut"}">${ic(ok?"check":"close")} ${t}</span>`;const r=[];
  if(p.port!=null)r.push(`<div class="row wrap" style="gap:4px 12px"><b>${ic("anchor")} Порт</b>${y(s.reefer,"рефконтейнери")}${y(s.deep,"глибоководний причал (балкери)")}</div>`);
  if(p.air)r.push(`<div class="row wrap" style="gap:4px 12px"><b>${ic("plane")} Аеропорт</b>${y(true,"вантажні літаки")}${y(s.heavy,"важкі авіавантажники")}</div>`);
  if(p.rail)r.push(`<div class="row wrap" style="gap:4px 12px"><b>${ic("train")} Залізнична станція</b></div>`);return r.join("")}

/* ---------- windows ---------- */
function permSect(){const T0=G.day;
  return `${sect("Дозволи на спецвантажі")}<div class="hint">${ic("info")}<div>Небезпечні, цінні й фармацевтичні вантажі платять більше, але потрібна <b>ліцензія на рік</b>. Без неї такі замовлення на біржі заблоковані. Продовження автоматичне, якщо вистачає грошей. Ціна залежить від країни штабу й ситуації у світі.</div></div>
  <div style="display:flex;flex-direction:column;gap:6px;margin-bottom:10px">${PERM.map(p=>{const P=CO.perm&&CO.perm[p.id],ok=permOK(p.id),lock=CO.tier<p.tier,f=permFee(p.id),left=P?Math.round(P.until-T0):0;
    return `<div class="blk" style="${ok?"border-color:rgba(91,214,140,.45)":lock?"opacity:.55":""}"><div class="row sp wrap"><div class="row" style="gap:10px;min-width:0"><span class="${ok?"good":lock?"mut":"acc"}">${ic(p.ic)}</span><div style="min-width:0"><b>${p.n}</b><div class="note">${p.d}</div></div></div>
     <div style="text-align:right">${ok?`<span class="pill ${left<31?"warn":"good"}">діє ще ${left} дн.</span>`:lock?`<span class="pill">${ic("lock")}Ліцензія «${LIC[p.tier].n}»</span>`:P?`<span class="pill bad">сплила</span>`:""}</div></div>
     ${lock?"":`<div class="row sp wrap" style="margin-top:8px"><span class="note">${fmtUSD(f)} на рік</span><div class="row">${P?`<button class="tg ${P.auto?"on":""}" data-act="coPermAuto" data-arg="${p.id}" aria-label="Автопродовження" data-tip="${T("Автопродовження","Списати оплату автоматично, коли ліцензія спливе.")}"></button>`:""}<button class="btn sm ${ok?"":"pri"}" data-act="coPerm" data-arg="${p.id}" ${CO.cash>=f?"":"disabled"}>${ic("doc")}${ok?"Продовжити на рік":"Купити на рік"}</button></div></div>`}</div>`}).join("")}</div>`}
function upgSect(ff){const m=ff&&ff!=="all"?ff:null;const L=UPG.filter(u=>!m||!u.fx||u.fx[m]||u.rep||u.brk);const pk=.6+.4*(CO.parts||1);
  return `${sect("Модернізація")}<div class="grid2">${L.map(u=>{const got=hasU(u.id),lock=CO.tier<u.tier,c=Math.round(u.cost*pk);return `<div class="blk" style="${got?"border-color:rgba(91,214,140,.45)":lock?"opacity:.5":""}"><div class="row sp"><div class="row" style="gap:8px"><span class="${got?"good":"acc"}">${ic(u.ic)}</span><b>${u.n}</b></div>${got?`<span class="pill good">${ic("check")}Є</span>`:""}</div>
    <div class="note" style="margin:6px 0">${u.d}</div>${got?"":lock?`<span class="pill">${ic("lock")}Ліцензія «${LIC[u.tier].n}»</span>`:`<button class="btn sm ${CO.cash>=c?"pri":""}" data-act="coUpg" data-arg="${u.id}" ${CO.cash>=c?"":"disabled"}>${ic("plus")}Впровадити · ${fmtUSD(c)}</button>`}</div>`}).join("")}</div>`}
{const _f=WINS.coFleet;WINS.coFleet=()=>_f()+upgSect(UI.ffl)}
{const _h=WINS.coHome;WINS.coHome=()=>{const h=_h();const key='<div class="grid2"><div class="blk"><div class="lbl">';const i=h.indexOf(key);return i<0?h+permSect():h.slice(0,i)+permSect()+h.slice(i)}}

function bizInsp(p){const s=specHTML(p),F=firmsOf(p.id);return `${s?sect("Інфраструктура")+`<div class="blk" style="display:flex;flex-direction:column;gap:6px">${s}</div>`:""}${sect("Підприємства")}<div style="display:flex;flex-direction:column;gap:6px">${F.slice(0,9).map(f=>`<div class="row" style="gap:8px"><span class="mut">${ic(IND[f.ind].ic)}</span><div style="min-width:0"><b>${esc(f.n)}</b><div class="note">${IND[f.ind].n}</div></div></div>`).join("")}</div>`}

/* hover card for any settlement: type, people, transport and the biggest firms */
function placeTip(p){const TY={cap:"Столиця",big:"Велике місто",city:"Середнє місто",town:"Мале місто",vil:"Мале місто"}[p.type]||"Поселення",h=hubAt(p.id),F=firmsOf(p.id),y=(ok,t)=>`<span class="${ok?"good":"mut"}">${ic(ok?"check":"close")} ${t}</span>`,s=nodeSpec(p);
  return `<div class="row sp" style="gap:14px"><b>${esc(p.name)}</b><span class="note">${TY} · ${esc(G.C[p.cid].name)}</span></div>
  <div class="note" style="margin-top:2px">Населення ${fmtSP(p.pop)}${h?` · <span class="warn">${HUB_LV[h.lvl]}${p.id===CO.hq?" · штаб":""}</span>`:""}</div>
  ${p.rail||p.port!=null||p.air?`<div style="margin-top:7px;padding-top:7px;border-top:1px solid var(--line);display:flex;flex-direction:column;gap:3px">
   ${p.rail?y(true,"залізнична станція"):""}${p.port!=null?y(true,`порт${s.reefer?", рефконтейнери":""}${s.deep?", балкери":""}`):""}${p.air?y(true,`аеропорт${s.heavy?", важкі літаки":""}`):""}</div>`:""}
  ${F.length?`<div style="margin-top:7px;padding-top:7px;border-top:1px solid var(--line)"><span class="lbl">Підприємства · ${F.length}</span>${F.slice(0,3).map(f=>`<div class="row" style="gap:6px;margin-top:4px"><span class="mut">${ic(IND[f.ind].ic)}</span><span>${esc(f.n)}</span><span class="note">${IND[f.ind].n.toLowerCase()}</span></div>`).join("")}${F.length>3?`<div class="note" style="margin-top:4px">і ще ${F.length-3} · клік — подробиці</div>`:""}</div>`:""}`}
