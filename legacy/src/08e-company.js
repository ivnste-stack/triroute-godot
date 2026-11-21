/* ================= LOGISTICS COMPANY MODE ================= */
const CO={};let CITY_EV=new Set(),CO_MOUSE=null,CO_CL=[],CO_CP=new Map(),PL=[],CO_GRID=null,CO_HW=null,CO_RW=null,CO_LAND=null,CO_LN={},CO_SEL=null,CO_PREV=null,CO_HITS=[],CO_RT=0;
const CO_ROUTES=new Map();
let railOK=id=>id.startsWith("co")||id==="news";
const CO_MODES=[["co","Мережа компанії","truck"],["grid","Логістичні шляхи","road"],["risk","Ризики перевезень","alert"],["pol","Політична","mapIc"],["dem","Світовий попит","chart"]];
const fmtUSD=(v,sign)=>{const s=sign&&v>0?"+":"",n=v<0?"−":"",a=Math.abs(v);return s+n+"$"+(a>=1e9?(a/1e9).toFixed(2)+" млрд":a>=1e6?(a/1e6).toFixed(a>=1e8?0:a>=1e7?1:2)+" млн":a>=1e4?(a/1e3).toFixed(0)+" тис.":a>=1e3?(a/1e3).toFixed(1)+" тис.":a.toFixed(0))};
const starsH=r=>{const k=Math.round(r);return `<span style="color:var(--warn);letter-spacing:1px">${"★".repeat(k)}</span><span class="mut" style="letter-spacing:1px">${"☆".repeat(5-k)}</span>`};
let CO_DU=1.6; // continents are drawn ~1.6x smaller: route lengths are kept in "economic" units
const KM=2080; // one economic unit ≈ 2080 km: a map sector (7.5 × CO_DU .16) ≈ 2 500 km

if(!ICONS.van)ICONS.van='<path d="M2 7h11v9H2zM13 10h5l3 3v3h-8"/><circle cx="6" cy="17" r="2"/><circle cx="17" cy="17" r="2"/>';
const VT={
 van:{vol:12,n:"Фургон",ic:"van",cost:28000,mode:"road",cap:1.5,spd:1.3,loc:42,role:"driver",up:22,fuel:55,tier:1,d:"До 1,5 т. Швидкий; між рейсами сам розвозить посилки по місту, де стоїть хаб."},
 ltruck:{vol:30,n:"Вантажна машина",ic:"truck",cost:45000,mode:"road",cap:5,spd:1.15,loc:30,role:"driver",up:32,fuel:85,tier:1,d:"До 5 т. З неї починається компанія: їздить між містами країни, а між рейсами розвозить замовлення по місту."},
 truck:{vol:82,n:"Вантажівка",ic:"truck",cost:95000,mode:"road",cap:20,spd:1.0,role:"driver",up:70,fuel:160,tier:2,d:"До 20 т. Основа міжміських і міжнародних перевезень."},
 reefer:{vol:70,n:"Рефрижератор",ic:"truck",cost:130000,mode:"road",cap:18,spd:1.0,role:"driver",up:85,fuel:180,tier:2,fit:["food","med"],d:"До 18 т з холодильною установкою. Продукти й ліки везе без псування: +20% до оплати таких замовлень."},
 tanker:{vol:30,n:"Автоцистерна",ic:"truck",cost:150000,mode:"road",cap:25,spd:.95,role:"driver",up:90,fuel:190,tier:2,fit:["fuel"],d:"До 25 т рідких вантажів. Пальне й хімія: +20% до оплати таких замовлень."},
 rtrain:{vol:120,n:"Автопоїзд",ic:"truck",cost:185000,mode:"road",cap:40,spd:.95,role:"driver",up:120,fuel:240,tier:3,d:"Тягач із двома причепами: до 40 т за рейс. Вигідний на далеких маршрутах."},
 heavy:{vol:60,n:"Важковоз (негабарит)",ic:"truck",cost:420000,mode:"road",cap:80,spd:.7,role:"driver",crew:2,up:260,fuel:420,tier:3,fit:["cars","metal","engines","build"],d:"Низькорамна платформа до 80 т: техніка, метал, обладнання. Повільний, два водії. +20% за важкі вантажі."},
 train:{vol:3000,n:"Вантажний потяг",ic:"train",cost:2600000,mode:"rail",cap:900,spd:1.6,role:"rail",crew:2,up:900,fuel:700,tier:4,d:"Локомотив і 15 вагонів: до 900 т. Тільки між містами із залізничними станціями."},
 ctrain:{vol:2400,n:"Контейнерний експрес",ic:"train",cost:3400000,mode:"rail",cap:500,spd:2.2,role:"rail",crew:2,up:1000,fuel:800,tier:4,fit:["cont","elec","parcel"],d:"Платформи під контейнери до 500 т, швидший за звичайний потяг. +20% за контейнери, електроніку й посилки."},
 htrain:{vol:6000,n:"Важкий потяг",ic:"train",cost:6500000,mode:"rail",cap:2500,spd:1.25,role:"rail",crew:3,up:1800,fuel:1500,tier:7,fit:["grain","metal","build","fuel"],d:"Два локомотиви й 40 вагонів: до 2 500 т зерна, руди чи пального. Повільний, але тонна найдешевша."},
 feeder:{vol:4000,n:"Фідерне судно",ic:"ship",cost:6000000,mode:"sea",cap:1500,spd:1.75,role:"sailor",crew:9,up:2200,fuel:1300,tier:5,d:"Невеликий контейнеровоз до 1 500 т: дешевший і швидший, заходить у будь-який порт."},
 ship:{vol:15000,n:"Контейнеровоз",ic:"ship",cost:14000000,mode:"sea",cap:6000,spd:1.6,role:"sailor",crew:14,up:4500,fuel:2500,tier:5,d:"До 6 000 т. Повільно, але найдешевше за тонну між континентами. Потрібні порти."},
 plane:{vol:500,n:"Вантажний літак",ic:"plane",cost:42000000,mode:"air",cap:60,spd:16,role:"pilot",crew:3,up:9000,fuel:3600,tier:6,d:"До 60 т за кілька годин. Для термінових і дорогих вантажів. Потрібні аеропорти."},
 turbo:{vol:180,n:"Турбогвинтовий вантажник",ic:"plane",cost:16000000,mode:"air",cap:20,spd:10,role:"pilot",crew:2,up:4000,fuel:1500,tier:6,d:"До 20 т. Повільніший за реактивний, зате втричі дешевший і економний на коротких рейсах."},
 bulk:{vol:40000,n:"Балкер",ic:"ship",cost:32000000,mode:"sea",cap:28000,spd:1.3,role:"sailor",crew:20,up:8000,fuel:4200,tier:7,d:"Гігант для зерна, руди й контейнерів: до 28 000 т."},
 jumbo:{vol:900,n:"Важкий авіавантажник",ic:"plane",cost:95000000,mode:"air",cap:130,spd:17,role:"pilot",crew:4,up:16000,fuel:6200,tier:7,d:"До 130 т: двигуни, обладнання, гуманітарні вантажі."},
 mega:{vol:1300,n:"Надважкий транспортник",ic:"plane",cost:180000000,mode:"air",cap:250,spd:15,role:"pilot",crew:6,up:28000,fuel:10500,tier:7,fit:["engines","aid","cars"],d:"Шість двигунів і до 250 т: турбіни, техніка, гуманітарні місії. Тільки аеропорти з довгою смугою. +20% за такі вантажі."},
};
const HAND={road:.25,rail:.6,sea:1.5,air:.4};
const spdK=()=>G.board?.15:1,handK=()=>G.board?.4:1,coNow=()=>G.day+(CO.lastFr||0);
const MODE_N={local:"Місто",road:"Автодороги",rail:"Залізниця",sea:"Море",air:"Авіа"},MODE_IC={local:"van",road:"truck",rail:"train",sea:"ship",air:"plane"};
const ROLE={driver:{n:"Водії",w:1900,ic:"truck",pool:4},rail:{n:"Машиністи",w:2800,ic:"train",pool:3},sailor:{n:"Моряки",w:2300,ic:"anchor",pool:16},pilot:{n:"Пілоти",w:8000,ic:"plane",pool:4}};
const LIC=[
 {n:"—",d:"",cost:0,rat:0,del:0,con:0,xp:0,hide:1},
 {n:"Внутрішні перевезення",d:"Вантажна машина й фургони, замовлення між містами вашої країни, хаби в інших містах країни.",cost:0,rat:0,del:0,con:0,xp:0},
 {n:"Вантажні перевезення",d:"Вантажівки до 20 т, рефрижератори й автоцистерни, великі замовлення від бізнесу, тендери.",cost:60000,rat:3.3,del:100,con:0,xp:250},
 {n:"Міжнародні перевезення",d:"Перетин кордонів на вашому материку, хаби за кордоном, митниця, автопоїзди й негабаритні важковози.",cost:250000,rat:3.5,del:300,con:0,xp:1200},
 {n:"Залізничний оператор",d:"Власні потяги між станціями: сотні тонн за рейс. Звичайні вантажні та контейнерні експреси.",cost:1200000,rat:3.7,del:700,con:0,xp:3500},
 {n:"Морський перевізник",d:"Фідерні судна й контейнеровози між портами різних материків. Хаби на будь-якому континенті.",cost:4000000,rat:3.9,del:1400,con:0,xp:8000},
 {n:"Авіаперевізник",d:"Турбогвинтові й реактивні вантажні літаки між аеропортами: найшвидше і найдорожче.",cost:9000000,rat:4.1,del:2500,con:0,xp:16000},
 {n:"Глобальний інтегратор",d:"Найбільші тендери світу, балкери, важкі потяги, важкі й надважкі літаки. Мета — стати №1.",cost:30000000,rat:4.4,del:4000,con:0,xp:30000},
];
const MG=[
 {id:"coo",n:"Операційний директор",ic:"gear",d:"Менше аварій і поломок, вища якість доставки."},
 {id:"cco",n:"Комерційний директор",ic:"handshake",d:"Дорожчі контракти, більше замовлень, швидше зростання частки ринку."},
 {id:"cfo",n:"Фінансовий директор",ic:"coins",d:"Нижчі витрати й ставки кредитів, ловить менеджерів на крадіжках."},
 {id:"cso",n:"Директор з безпеки",ic:"shield",d:"Захист від крадіжок, захоплень і піратів."},
 {id:"hro",n:"HR-директор",ic:"users",d:"Дешевший найм, вищий моральний дух, менше страйків."},
 {id:"clo",n:"Юрист і митний брокер",ic:"gavel",d:"Веде митне оформлення: пришвидшує проходження кордонів і зменшує штрафи."},
 {id:"cto",n:"Диспетчер-логіст",ic:"cpu",d:"Сам бере замовлення з біржі й прокладає маршрути. Що досвідченіший (і дорожчий), то дешевші й надійніші маршрути. Досвіду компанії за його рейси майже немає."},
];
const CARGO=[
 {id:"parcel",v:6,n:"Збірні посилки",ic:"box",t:[.3,2],k:1,fr:.05,val:9000},
 {id:"food",v:3,n:"Продукти в рефрижераторі",ic:"leaf",t:[1,30],k:1.15,fr:.04,val:2500},
 {id:"med",v:4,n:"Ліки й вакцини",ic:"pill",t:[.3,8],k:1.6,fr:.08,val:60000,theft:1.4},
 {id:"elec",v:5,n:"Електроніка",ic:"cpu",t:[.5,40],k:1.35,fr:.1,val:40000,theft:2},
 {id:"furn",v:7,n:"Меблі",ic:"house",t:[2,40],k:1,fr:.06,val:3000},
 {id:"build",v:0.8,n:"Будматеріали",ic:"factory",t:[10,1500],k:.8,fr:.01,val:300},
 {id:"grain",v:1.4,n:"Зерно",ic:"wheat",t:[200,30000],k:.6,fr:.005,val:250},
 {id:"cars",v:5,n:"Автомобілі",ic:"truck",t:[8,900],k:1.1,fr:.05,val:15000,theft:1.3},
 {id:"fuel",v:1.3,n:"Пальне (небезпечний вантаж)",ic:"barrel",t:[15,5000],k:1.3,fr:.02,val:900},
 {id:"cont",v:2.2,n:"Контейнери",ic:"box",t:[300,25000],k:.75,fr:.01,val:4000},
 {id:"metal",v:0.35,n:"Метал і руда",ic:"ore",t:[80,30000],k:.55,fr:.002,val:400},
 {id:"engines",v:3,n:"Авіадвигуни й обладнання",ic:"gear",t:[2,120],k:1.7,fr:.06,val:90000,theft:.8},
 {id:"gold",v:0.6,n:"Цінності й банкноти",ic:"gem",t:[.1,3],k:3.5,fr:.01,val:2000000,theft:4},
 {id:"aid",v:3.5,n:"Гуманітарна допомога",ic:"heart",t:[2,2000],k:2.1,fr:.03,val:1500,aid:true},
];
const CARGO_I={};CARGO.forEach(c=>CARGO_I[c.id]=c);
const CO_MYTH=[
 ["Найшвидший транспорт — найвигідніший.","Літак перевозить тонну в 10–20 разів дорожче за корабель. Авіацією возять те, що дороге або термінове: ліки, електроніку, запчастини."],
 ["Повна машина завжди вигідніша.","Якщо заради повного завантаження машина три дні чекає вантаж, втрачені дні коштують більше за порожнє місце. Важить оборот техніки."],
 ["Головні витрати перевізника — пальне.","У міських доставках найбільша стаття — люди. На дальніх маршрутах пальне, але амортизація техніки й простої з'їдають не менше."],
 ["Страхування — викинуті гроші.","Одна викрадена фура з електронікою може коштувати як рік страхових внесків. Страховка перетворює рідкісну катастрофу на прогнозовану витрату."],
 ["Дешевша робоча сила завжди краща.","Низькі зарплати — це плинність кадрів, аварії й страйки. Мотивований водій береже машину і вантаж."],
 ["Залізниця застаріла.","На відстанях понад 500–800 км потяг везе тонну вантажу в 3–4 рази дешевше за вантажівку і з меншими викидами."],
 ["Порожній зворотний рейс — дрібниця.","Порожній пробіг — одна з головних втрат галузі. Диспетчери шукають попутні вантажі, щоб машина заробляла в обидва боки."],
 ["Велика компанія не може збанкрутувати.","У логістиці маржа тонка: 3–8%. Кредити на техніку, падіння попиту і дороге пальне можуть потопити навіть гіганта."],
];
const CO_NAMES_A=["Стріла","Меридіан","Вектор","Хорс","Борей","Колібрі","Пульс","Компас","Азимут","Сапсан","Кит","Мандрівник"],CO_NAMES_B=[" Логістик"," Експрес"," Карго"," Доставка"," Транс"];
const COMP_N=["Атлас Карго","Нордлайн","Глобал Пак","Меркурій Експрес","Сітікур'єр","ТрансКонтинент"];
const CO_MS=[
 ["d100","Перша сотня","100 доставок",()=>CO.deliv>=100],
 ["f5","Маленький автопарк","5 одиниць техніки",()=>CO.veh.length>=5],
 ["van","На колесах","Перший фургон",()=>CO.veh.some(v=>v.t==="van")],
 ["hub2","Друга точка","Другий хаб",()=>CO.hubs.length>=2],
 ["c1","Перший контракт","Виконати замовлення між містами",()=>CO.cdel>=1],
 ["abroad","За кордон","Хаб в іншій країні",()=>CO.hubs.some(h=>PL[h.pid].cid!==G.me)],
 ["d10k","Десять тисяч","10 000 доставок",()=>CO.deliv>=1e4],
 ["rail","Сталеві колії","Перший потяг",()=>CO.veh.some(v=>VT[v.t].mode==="rail")],
 ["ocean","Через океан","Рейс між материками",()=>!!CO.flags.ocean],
 ["air","У небі","Перший вантажний літак",()=>CO.veh.some(v=>VT[v.t].mode==="air")],
 ["m1","Мільйон на місяць","Виручка $1 млн за місяць",()=>coRev(CO.lm)>=1e6],
 ["c3","Три материки","Хаби на трьох материках",()=>new Set(CO.hubs.map(h=>PL[h.pid].land)).size>=3],
 ["r45","Бездоганна репутація","Рейтинг 4.5",()=>CO.rating>=4.5],
 ["top3","Призер","Топ-3 логістичних компаній світу",()=>coRank()<=3],
 ["top1","Лідер ринку","№1 серед логістичних компаній світу",()=>coRank()===1],
];

/* ---------- helpers ---------- */
const DFK=()=>[.6,1,1.45][G.diff??1];
const msk=id=>CO.mgr&&CO.mgr[id]?CO.mgr[id].skill/10:0;
const priceK=cid=>.45+G.C[cid].dev*1.35;
const wageK=cid=>.4+G.C[cid].dev*1.5;
const coRev=m=>m?m.local+m.contract+m.tender:0;
const coCost=m=>m?(m.office||0)+m.wage+m.mgmt+m.fuel+m.upkeep+m.rent+m.ins+m.interest+m.claims+m.other+m.mk+(m.hubtax||0):0;
const coZero=()=>({office:0,local:0,contract:0,tender:0,wage:0,mgmt:0,fuel:0,upkeep:0,rent:0,ins:0,interest:0,claims:0,other:0,mk:0,stolen:0,hubtax:0});
const hqP=()=>PL[CO.hq];
const bur=cid=>{const c=G.C[cid];return c?10+(1-clamp(c.dev,0,1))*60:35}; /* paperwork & slow customs: poorer countries 10…70 */
function coRisk(cid){const c=G.C[cid];let r=bur(cid)/80*.55+(100-c.stability)/100*.45;if(CO.conf&&CO.conf.some(x=>x.a===cid||x.b===cid))r+=.6;return clamp(r,0,1.2)}
function riskLvl(cid){const k=Math.floor(G.day/30)+":"+(CO.conf||[]).length;if(!riskLvl.q||riskLvl.k!==k){const v=G.C.map(c=>coRisk(c.id)).sort((a,b)=>a-b),q=f=>v[Math.min(v.length-1,Math.floor(f*v.length))];riskLvl.q=[q(.3),q(.65),q(.88)];riskLvl.k=k}const r=coRisk(cid),Q=riskLvl.q;return r>Q[2]?3:r>Q[1]?2:r>Q[0]?1:0}
const RISK_N=[["Низький","good"],["Помірний","warn"],["Високий","bad"],["Дуже високий","bad"]];
const RISK_COL=[[.27,.62,.42],[.83,.71,.3],[.88,.47,.2],[.78,.2,.18]];
const riskW=r=>r>.75?["Дуже високий","bad"]:r>.5?["Високий","bad"]:r>.3?["Середній","warn"]:["Низький","good"];
function inConf(cid){return CO.conf.some(x=>x.a===cid||x.b===cid)}
function coScope(p){const H=hqP();if(CO.tier>=5)return true;if(CO.tier>=3)return p.land===H.land;if(CO.tier>=1)return p.cid===H.cid;return p.id===H.id}
function hubAt(pid){return (CO.hubs||[]).find(h=>h.pid===pid)}
/* abroad you do not own a hub, you rent one: a small deposit, then a heavy monthly rent — it pays only where the freight is */
const hubAbroad=p=>CO.hq!=null&&PL[CO.hq]&&p.cid!==PL[CO.hq].cid;
function hubOpenCost(p){return hubAbroad(p)?Math.round(hubCost(p)*.1):hubCost(p)}
function hubRentM(h){const p=PL[h.pid];return HUB_RENT[h.lvl]*priceK(p.cid)*(h.rent?2.5:1)+(h.rent?hubCost(p)*.05:0)}
function hubCost(p){return Math.round(({cap:60000,big:35000,city:20000,town:8000,vil:4000}[p.type]||8000)*priceK(p.cid))}
const HUB_LV=["","Хаб 1 рівня","Хаб 2 рівня","Хаб 3 рівня","Логістичний хаб"],HUB_UP=[0,4,15,40],HUB_RENT=[0,300,2500,12000,30000];
const HUB_VEH=[0,8,30,120,300],HUB_STAFF=[0,12,40,150,400],HUB_HAND=[1.15,1,.7,.45,.3],HUB_ORD=[0,1,2,3.5,5];
const hubVehN=pid=>CO.veh.filter(v=>v.loc===pid&&v.st!=="trip").length;
const hubVehCap=h=>SET.sandbox?1e9:HUB_VEH[h.lvl];
const staffCap=()=>SET.sandbox?1e9:6+CO.hubs.reduce((a,h)=>a+HUB_STAFF[h.lvl],0);
const handF=pid=>{const h=hubAt(pid);return HUB_HAND[h?h.lvl:0]};
function coValue(){return CO.cash+CO.veh.reduce((a,v)=>a+VT[v.t].cost*(.35+.4*v.cond/100),0)+CO.hubs.reduce((a,h)=>a+hubCost(PL[h.pid])*h.lvl*.8,0)-CO.loans.reduce((a,l)=>a+l.left,0)}
function coCredit(){return Math.max(15000,Math.round(coValue()*.45+coRev(CO.lm)*2))}
function coRate(){return clamp(.07+(5-CO.rating)*.022-msk("cfo")*.025,.03,.2)}
function coRank(){const my=coYearRev();return 1+CO.comp.filter(c=>c.rev>my).length}
function coYearRev(){const h=CO.hist.rev.slice(-12);const s=h.reduce((a,b)=>a+b,0);return h.length<12?s/Math.max(1,h.length)*12:s}
function coCrewFree(){const f={};for(const r in ROLE)f[r]=(CO.staff[r]||0)+(r==="driver"?CO.founder:0);
  for(const v of CO.veh){if(v.st==="trip"||v.st==="tender"){const T=VT[v.t];f[T.role]-=(T.crew||1)}}return f}
function coCrewNeed(){const f={};for(const r in ROLE)f[r]=0;for(const v of CO.veh){const T=VT[v.t];f[T.role]+=(T.crew||1)}return f}
function coLogo(name,col){const c=document.createElement("canvas");c.width=96;c.height=64;const g=c.getContext("2d");g.fillStyle="#0b1520";g.fillRect(0,0,96,64);g.fillStyle=col;g.fillRect(0,0,96,64);
  g.fillStyle="rgba(0,0,0,.18)";g.beginPath();g.moveTo(0,64);g.lineTo(96,14);g.lineTo(96,64);g.fill();g.strokeStyle="#0b1520";g.lineWidth=5;g.beginPath();g.moveTo(18,44);g.lineTo(46,20);g.lineTo(46,32);g.lineTo(78,32);g.stroke();
  g.fillStyle="#0b1520";g.font="700 15px sans-serif";g.fillText(name.split(" ").map(w=>w[0]).join("").slice(0,2).toUpperCase(),58,56);return c.toDataURL()}
function coNews(tone,icon,text){addNews(G.me,tone,icon,text)}
function coModalOK(){return G.day>=(CO.mcd||0)}
function coModal(s){CO.mcd=G.day+rint(9,18);s.urgent=true;queueModal(s)}

/* ---------- places, networks, routes ---------- */
/* continents: states whose land touches (a common border) form one continent; a state on its own island is a continent of its own */
let CO_CONT=null,CO_CONTW=null;
function coCont(cid){const w=G.world;if(!w||!w.own)return 0;if(CO_CONTW!==w||!CO_CONT||CO_CONT.length!==G.C.length){const n=G.C.length,par=[...Array(n).keys()],f=a=>{while(par[a]!==a)a=par[a]=par[par[a]];return a};
    const own=w.own,ok=o=>o>=0&&o<n;for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){const o=own[y*MW+x];if(!ok(o))continue;const r=x+1<MW?own[y*MW+x+1]:-1,d=y+1<MH?own[(y+1)*MW+x]:-1;
      if(ok(r)&&r!==o){const a=f(o),b=f(r);if(a!==b)par[a]=b}if(ok(d)&&d!==o){const a=f(o),b=f(d);if(a!==b)par[a]=b}}
    CO_CONT=Int32Array.from({length:n},(_,i)=>f(i));CO_CONTW=w}return CO_CONT[cid]??0}
function coPlaces(){
  if(G.board){CO_MAXP=0;CO_HS.clear&&CO_HS.clear();CO_ROUTES.clear();PL=BOARD.towns.map((t,i)=>({id:i,cid:t.cid,cell:0,name:t.name,type:t.type,x:t.x,z:t.z,pop:t.pop,air:t.airOv!=null?!!t.airOv:(t.type==="cap"||t.type==="big"),port:t.port?1:null,rail:!!(BOARD.rnodes&&BOARD.rnodes.has(t.node)),land:coCont(t.cid),node:t.node}));
    CO_LN={};{const cnt={},st={};PL.forEach(p=>{cnt[p.land]=(cnt[p.land]||0)+1;(st[p.land]=st[p.land]||new Set()).add(p.cid)});const LN=["Аркадія","Борея","Велесія","Гелона","Дарінія","Етерра","Зоряна","Ілірія","Корана","Лютея","Мірія","Норвія"];let k=0,ki=0;Object.keys(cnt).map(Number).sort((a,b)=>cnt[b]-cnt[a]||a-b).forEach(l=>{const R_=n=>n<1?"":" "+["II","III","IV","V","VI","VII","VIII","IX","X"][Math.min(8,n-1)];if(cnt[l]>=8||st[l].size>=2){CO_LN[l]=LN[k%LN.length]+R_(Math.floor(k/LN.length));k++}else{CO_LN[l]="Острів "+["Вітрів","Чайок","Скель","Мусонів","Рифів","Туманів"][ki%6]+R_(Math.floor(ki/6));ki++}})}CO_GRID=null;CO_HW=new Uint16Array(NW*NH);CO_RW=new Uint16Array(NW*NH);return}
}
function coRoute(mode,a,b){
  const A=PL[a],B=PL[b];if(a===b)return{p:new Float32Array([A.x,A.z,A.x,A.z]),len:0};
  const key=mode+a+":"+b;if(CO_ROUTES.has(key))return CO_ROUTES.get(key);
  let p=null;
  if(G.board){if(mode==="road")p=boardPath(A.node,B.node);else if(mode==="sea"&&A.port!=null&&B.port!=null)p=boardSea(A,B);else if(mode==="rail"&&A.rail&&B.rail)p=boardPath(A.node,B.node,BOARD.rbits);else if(mode==="air"&&A.air&&B.air)p=incAirPath(A.x,A.z,B.x,B.z)}
  let res=null;if(p&&p.length>=4){let len=0;for(let i=2;i<p.length;i+=2)len+=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]);res={p,len:len*CO_DU}}
  CO_ROUTES.set(key,res);return res;
}
function modeOK(mode,p){return mode==="sea"?p.port!=null:mode==="air"?p.air:mode==="rail"?p.rail:true}

/* ---------- logistics board: the whole field is a hierarchy of squares ---------- */
const BOARD={S:[7.5,2.5,.5,.125],cols:3,rows:2};
/* start-screen / loading background for the logistics mode: one blurred 4K shot of the "Логістичні шляхи" layer */
function coBgSnap(){return; // the logistics menu background is a fixed picture now (LOGI_BG)
  let has=false;try{has=!!localStorage.getItem("pon_bgco1")}catch(e){}if(has||!G.board)return;
  const keep={mode:UI.mode,lf:UI.lf,tx:Cam.tx,tz:Cam.tz,d:Cam.dist,ttx:Cam.ttx,ttz:Cam.ttz,td:Cam.tdist,yaw:Cam.yaw};
  UI.mode="grid";UI.lf=null;applyMapColors();Cam.tdist=Cam.dist=WX*1.03;Cam.ttx=Cam.tx=0;Cam.ttz=Cam.tz=.55;Cam.yaw=0;window.FORCE_RES=[3840,2160];
  requestAnimationFrame(()=>requestAnimationFrame(t=>{guard("Фон логістики",()=>{try{renderFrame(t);drawBorders();
    const a=$("#gl"),o=$("#bcv"),f=document.createElement("canvas");f.width=a.width;f.height=a.height;const fg=f.getContext("2d");fg.drawImage(a,0,0);fg.drawImage(o,0,0,a.width,a.height);
    const c=document.createElement("canvas"),wd=2560;c.width=wd;c.height=Math.round(a.height*wd/a.width);const g=c.getContext("2d");g.imageSmoothingQuality="high";if("filter" in g)g.filter="blur(7px)";g.drawImage(f,0,0,c.width,c.height);
    try{localStorage.setItem("pon_bgco1",c.toDataURL("image/jpeg",.8))}catch(e){}}
    finally{window.FORCE_RES=null;UI.mode=keep.mode;UI.lf=keep.lf;Object.assign(Cam,{tx:keep.tx,tz:keep.tz,dist:keep.d,ttx:keep.ttx,ttz:keep.ttz,tdist:keep.td,yaw:keep.yaw});applyMapColors();updateLegend()}})}))}
function coBgUse(on){window.BG_CO=!!on;const im=$("#bgSnap");if(!im)return;let src=null;if(on)src=LOGI_BG;else try{src=localStorage.getItem("pon_bg5")}catch(e){}
  // the logistics picture is a whole-board view: scale it just enough to cover the screen (plus room for the drift)
  const fit=()=>{im.style.width="";im.style.minHeight="";im.style.height=""}; // the menu picture covers the whole window (CSS), and only pans left-right
  if(!src)return;if(im.src===src){fit();return}
  im.classList.remove("on");setTimeout(()=>{fit();im.onload=()=>im.classList.add("on");im.src=src},on===undefined?0:350)}
setTimeout(()=>coBgUse(true),0);
(function(){G.mapSize=G.mapSize||"m";const sz=$("#sSize");if(sz)sz.addEventListener("click",e=>{const b=e.target.closest("button");if(!b)return;sz.querySelectorAll("button").forEach(x=>x.classList.toggle("on",x===b));G.mapSize=b.dataset.v})})();
(function(){const sm=$("#sMap");if(sm)sm.addEventListener("click",e=>{const b=e.target.closest("button");if(!b)return;sm.querySelectorAll("button").forEach(x=>x.classList.toggle("on",x===b));G.earth=b.dataset.v==="1";G.custom=b.dataset.v==="2";const z=$("#sSizeRow");if(z)z.hidden=G.earth;const ed=$("#sEditRow");if(ed)ed.hidden=G.custom})})();
(function(){G.editFirst=false;const se=$("#sEdit");if(se)se.addEventListener("click",e=>{const b=e.target.closest("button");if(!b)return;se.querySelectorAll("button").forEach(x=>x.classList.toggle("on",x===b));G.editFirst=b.dataset.v==="1"})})();
async function startBoard(restore){
  PREV.stop=true;setWorldScale(G.earth?"earth":"board");G.co=true;G.board=true;DUR=DUR_C;G.dom=false;G.tri=true;G.genN=G.earth?30:Math.max(12,Math.round(30*WX*WZ/384));
  $("#start").hidden=true;$("#loading").hidden=false;const prog=(p,t)=>{$("#loadBar").style.width=(p*100).toFixed(0)+"%";$("#loadTxt").textContent=t};
  // continents and countries from the triangle generator: one triangle = one smallest square of the board
  if(!restore)G.loadW=null;
  const world=G.loadW?await edLoadWorld(G.loadW):G.custom&&!G.earth?await edBlankWorld():await genWorld(SEED,G.genN,(p,t)=>prog(p*.7,t),{big:true,tri:true,earth:!!G.earth});G.wmod=!!G.loadW;
  stopPreview();G.world=world;R=mulberry(SEED^0x5bd1e995);
  if(!restore){G.news=[];G.markers=[];G.inbox=[];G.decisions=[];G.deals=[];G.wars=[];G.flash={};G.resolutions=[];G.orgs=[];G.pending=[];G.histDates=[];
    const used=new Set(world.countries.map(g=>g.name).filter(Boolean));G.C=world.countries.map((geo,i)=>{const c=makeCountry(geo,i,used);const nm=geo.name||(G.earth?earthName(geo,used):null);if(nm){used.add(nm);c.name=nm;c.full=c.ide.gov+" "+nm}return c});const usedCol=new Map();
    G.C.forEach(c=>{const nc=new Set(c.geo.neighbors.map(j=>G.C[j]&&G.C[j].color).filter(Boolean));const opts=COUNTRY_COLS.filter(x=>!nc.has(x));const sorted=opts.sort((a,b)=>(usedCol.get(a)||0)-(usedCol.get(b)||0));c.color=sorted[rint(0,Math.min(2,sorted.length-1))]||pick(COUNTRY_COLS);usedCol.set(c.color,(usedCol.get(c.color)||0)+1)});
    if(G.C.length){initRelations();calibrateResources();initMarket()}}
  G.flash=G.flash||{};G.markers=G.markers||[];
  CO_DU=.16;prog(.75,"Розміщення міст, селищ і сіл…");await tick();if(G.loadW)edLoadTowns(G.loadW);else boardGen();
  prog(.82,"Прокладання доріг по сітці…");await tick();if(G.loadW&&G.loadW.rd)edLoadRoads(G.loadW);else await boardRoads();
  prog(.95,"Підготовка мапи…");await tick();
  initGL(world);buildOverlay();ovBuilt=true;buildCityLabels();
  $("#loading").hidden=true;endPreview();
  UI.mode="co";coPlaces();applyMapColors();
  if(!restore&&(G.custom&&!G.earth||G.editFirst))await editorRun();
  setTimeout(coBgSnap,400);
  if(!restore){const mates=p=>!BOARD.comp||p.node==null?9:PL.filter(q=>q!==p&&q.cid===p.cid&&q.node!=null&&BOARD.comp[q.node]===BOARD.comp[p.node]).length;
    let caps=PL.filter(p=>p.type==="cap"&&!(BOARD.csz&&BOARD.comp&&p.node!=null&&(BOARD.csz.get(BOARD.comp[p.node])||0)<TINY_ISL));{const ok=caps.filter(p=>mates(p)>=2);if(ok.length>=3)caps=ok}caps=caps.sort((a,b)=>G.C[a.cid].dev-G.C[b.cid].dev);
    const pickN=[.08,.3,.5,.72,.94].map(f=>caps[Math.min(caps.length-1,Math.floor(f*caps.length))]).filter((p,i,a)=>p&&a.indexOf(p)===i);
    G.me=pickN[0].cid;coInit(pickN[0].id);
    document.body.classList.add("hqpick");(coStartPick(caps,pickN)?()=>{}:queueModal)({icon:"truck",eyebrow:"Логістична компанія",title:"Де відкриємо перший хаб?",body:`<p>У вас <b>${fmtUSD(CO.cash)}</b>, одна вантажна машина і бажання доставляти. Оберіть столицю для штаб-квартири. Від неї залежать ціни, зарплати й те, куди ви зможете розширитися першими.</p>
      <div class="hint">${ic("bulb")}<div>У <b>багатих</b> країнах доставки дорожчі, але дорожчі й люди. У <b>бідних</b> праця дешева, проте посилки коштують копійки, а ризики вищі.</div></div>`,
      choices:pickN.map(p=>{const c=G.C[p.cid];return{t:`${p.name}, ${c.name}`,d:`Населення міста ${fmtSP(p.pop)} · рівень цін ×${priceK(p.cid).toFixed(2)} · зарплати ×${wageK(p.cid).toFixed(2)} · ризики: ${riskW(coRisk(p.cid))[0].toLowerCase()}`,f(){coSetHQ(p.id)}}})})}
  const p=PL[CO.hq??0]||PL[0];Cam.tdist=Cam.dist=restore?6:WX*1.05;Cam.ttx=Cam.tx=restore?p.x:0;Cam.ttz=Cam.tz=restore?p.z+.3:.6;Cam.yaw=0;
  lastMonth=G.date.m;if(!window.__loopOn){window.__loopOn=true;requestAnimationFrame(loop)}
}
/* lattice of the smallest squares: settlements sit on intersections, roads follow lines and diagonals */
const BL={st:.125,nx:0,nz:0},CST=.125,CBL={st:.125,nx:0,nz:0}; // BL: road lattice (may be the fine 1/3 one in the test mode); CBL: the board's square lattice
function bNode(i,j){return j*BL.nx+i}
function bXY(n){const i=n%BL.nx,j=(n/BL.nx)|0;return[-WX/2+i*BL.st,-WZ/2+j*BL.st]}
function bOwn(x,z){const px=Math.floor((x+WX/2)/WX*MW),py=Math.floor((z+WZ/2)/WZ*MH);if(px<0||py<0||px>=MW||py>=MH)return -1;const o=G.world.own[py*MW+px];return o>=0&&o<NEU?o:-1}
function bInland(x,z){const o=bOwn(x,z);if(o<0)return -1;for(const [dx,dz] of [[1,0],[-1,0],[0,1],[0,-1]])if(bOwn(x+dx*BL.st,z+dz*BL.st)<0)return -1;return o}
function boardGen(){
  BL.st=CST;BL.nx=Math.round(WX/BL.st)+1;BL.nz=Math.round(WZ/BL.st)+1;CBL.nx=BL.nx;CBL.nz=BL.nz;const rr=mulberry((SEED^0x51ab)>>>0),used=new Set(),T=[];
  const pk=arr=>arr[Math.floor(rr()*arr.length)];
  const nm=(vil)=>{for(let k=0;k<400;k++){const n=vil?(k<30?pk(CITY_A)+pk(VIL_B):pk(CITY_A)+pk(CITY_M)+pk(VIL_B)):(k<40?pk(CITY_A)+pk(CITY_B):pk(CITY_A)+pk(CITY_M)+pk(CITY_B));if(!used.has(n)){used.add(n);return n}}return pk(["Нове ","Верхнє ","Мале "])+pk(CITY_A)+pk(CITY_M)+pk(VIL_B)};
  const near=(i,j)=>bXY(bNode(i,j));
  const ok=(x,z,type,min)=>!T.some(o=>Math.hypot(o.x-x,o.z-z)<(o.type==="vil"||type==="vil"?Math.min(min,.45):min));
  const add=(x,z,i,j,type,cid)=>{const pop=type==="vil"?.015+rr()*.05:type==="town"?.12+rr()*.4:type==="cap"?G.C[cid].pop*(.08+rr()*.06):.5+rr()*2.2;const name=nm(type==="vil");if(type==="cap"){G.C[cid].capName=name;G.C[cid].geo.cap={x:(x+WX/2)/WX*MW,y:(z+WZ/2)/WZ*MH}}T.push({x,z,node:bNode(i,j),type,pop,cid,name})};
  /* no settlement right on a state border: a city sits inside its country (the coast is fine — that is where ports are) */
  const onBorder=(x,z,o)=>{for(const s of [1.2,2.2])for(const [dx,dz] of [[1,0],[-1,0],[0,1],[0,-1],[.7,.7],[-.7,.7],[.7,-.7],[-.7,-.7]]){const w=bOwn(x+dx*BL.st*s,z+dz*BL.st*s);if(w>=0&&w!==o)return true}return false};
  // capitals: the inland lattice node closest to each country's seed
  G.C.forEach(c=>{const [cx,cz]=pxToWorld(c.geo.cap.x,c.geo.cap.y);let best=null,bd=1e9;const ci=Math.round((cx+WX/2)/BL.st),cj=Math.round((cz+WZ/2)/BL.st);
    /* the capital goes on the country's biggest piece of land, not on a stray islet near the seed */
    const R=26,W=2*R+1,own=new Int8Array(W*W),lab=new Int32Array(W*W).fill(-1),sz=[];
    for(let dj=-R;dj<=R;dj++)for(let di=-R;di<=R;di++){const i=ci+di,j=cj+dj;if(i<1||j<1||i>=BL.nx-1||j>=BL.nz-1)continue;const [x,z]=near(i,j);if(bInland(x,z)===c.id)own[(dj+R)*W+di+R]=1}
    for(let s=0;s<W*W;s++){if(!own[s]||lab[s]>=0)continue;const L=sz.length;let n=0;const st=[s];lab[s]=L;while(st.length){const q=st.pop();n++;const qx=q%W,qy=(q/W)|0;
      for(const [dx,dy] of [[1,0],[-1,0],[0,1],[0,-1],[1,1],[-1,-1],[1,-1],[-1,1]]){const nx=qx+dx,ny=qy+dy;if(nx<0||ny<0||nx>=W||ny>=W)continue;const t=ny*W+nx;if(own[t]&&lab[t]<0){lab[t]=L;st.push(t)}}}sz.push(n)}
    let big=-1;for(let L=0;L<sz.length;L++)if(big<0||sz[L]>sz[big])big=L;
    for(let dj=-R;dj<=R;dj++)for(let di=-R;di<=R;di++){const s=(dj+R)*W+di+R;if(lab[s]!==big||big<0)continue;const [x,z]=near(ci+di,cj+dj),d=di*di+dj*dj+(onBorder(x,z,c.id)?400:0);if(d<bd){bd=d;best=[x,z,ci+di,cj+dj]}}
    if(best)add(best[0],best[1],best[2],best[3],"cap",c.id)});
  const place=(n,min,type)=>{for(let q=0,t=0;q<n&&t<n*600;t++){const i=2+Math.floor(rr()*(BL.nx-4)),j=2+Math.floor(rr()*(BL.nz-4));const [x,z]=near(i,j);const o=type==="vil"||rr()<.5?bOwn(x,z):bInland(x,z);if(o<0||onBorder(x,z,o)||!ok(x,z,type,min))continue;add(x,z,i,j,type,o);q++}};
  {const A=G.earth?1:WX*WZ/384;place(Math.round(30*A),1,"city");place(Math.round(105*A),.55,"town")}
  /* how many settlements a state should have: small ones still get a handful, big ones many more */
  const area=new Map();for(let j=1;j<BL.nz-1;j++)for(let i=1;i<BL.nx-1;i++){const [x,z]=near(i,j),o=bOwn(x,z);if(o>=0)area.set(o,(area.get(o)||0)+1)}
  const needN=c=>clamp(4+Math.round((area.get(c.id)||0)/260),4,10);
  // every state has at least three settlements
  {const r2=mulberry((SEED^0x3a77)>>>0);for(const c of G.C){let n=T.filter(t=>t.cid===c.id).length;const need=needN(c);if(n>=need)continue;const cand=[];
    for(let pass=0;pass<2&&n<need;pass++){G.C[c.id].tinyIsl=pass===1;cand.length=0;
    for(let j=1;j<BL.nz-1;j++)for(let i=1;i<BL.nx-1;i++){const [x,z]=near(i,j),q=BL.st*.3;if(bOwn(x+1e-4,z+1e-4)<0&&!G.C[c.id].tinyIsl)continue;if(bOwn(x+1e-4,z+1e-4)===c.id?cand.push([x,z,i,j],[x,z,i,j]):0,bOwn(x+q,z+q)===c.id||bOwn(x-q,z+q)===c.id||bOwn(x+q,z-q)===c.id||bOwn(x-q,z-q)===c.id)cand.push([x,z,i,j])}
    for(let k=0;k<cand.length*6&&n<need&&cand.length;k++){const q=cand[Math.floor(r2()*cand.length)],type="town";if(T.some(o=>o.node===bNode(q[2],q[3]))||(k<cand.length*3?onBorder(q[0],q[1],c.id):n>=3)||!ok(q[0],q[1],type,k<cand.length*2?.3:k<cand.length*4?.14:.05))continue;add(q[0],q[1],q[2],q[3],type,c.id);T[T.length-1].extra=1;n++}}delete G.C[c.id].tinyIsl}}
  T.filter(t=>t.type==="city").sort((a,b)=>b.pop-a.pop).slice(0,5).forEach(c=>c.type="big");
  BOARD.towns=T;
}

/* ---------- the countryside road web (both road generators) ----------
   1. junction points by Poisson-disk sampling over each state's land (even spacing, no visible grid), settlements as fixed points;
   2. a Gabriel graph per state: two points are joined only if no other point lies in the circle on their segment —
      planar (no crossings), natural blocks like a real road map;
   3. pruning: no over-long links, no two links leaving a point at a sharp angle (no twin roads side by side). */
function roadWeb(T,SP){const rf=mulberry((SEED^0x5151)>>>0),cl=SP*.15,pts=[];
  const okAt=(x,z)=>{const o=bOwn(x,z);if(o<0)return -1;for(const [dx,dz] of [[cl,0],[-cl,0],[0,cl],[0,-cl],[cl*.7,cl*.7],[-cl*.7,-cl*.7],[cl*.7,-cl*.7],[-cl*.7,cl*.7]])if(bOwn(x+dx,z+dz)!==o)return -1;return o};
  // Bridson-style sampling on a background grid
  const cs=SP/Math.SQRT2,GW=Math.ceil(WX/cs),GH=Math.ceil(WZ/cs),grid=new Int32Array(GW*GH).fill(-1),gi=(x,z)=>Math.floor((z+WZ/2)/cs)*GW+Math.floor((x+WX/2)/cs);
  const free=(x,z,r)=>{const i=Math.floor((x+WX/2)/cs),j=Math.floor((z+WZ/2)/cs);for(let v=j-2;v<=j+2;v++)for(let u=i-2;u<=i+2;u++){if(u<0||v<0||u>=GW||v>=GH)continue;const k=grid[v*GW+u];if(k>=0&&Math.hypot(pts[k].x-x,pts[k].z-z)<r)return false}return true};
  const put=(p)=>{const k=gi(p.x,p.z);if(k<0||k>=grid.length)return;pts.push(p);grid[k]=pts.length-1};
  for(const t of T)if(free(t.x,t.z,SP*.3))put({x:t.x,z:t.z,cid:t.cid,town:t});
  const act=[];for(let z=-WZ/2+SP/2;z<WZ/2;z+=SP*1.7)for(let x=-WX/2+SP/2;x<WX/2;x+=SP*1.7){const px=x+(rf()-.5)*SP,pz=z+(rf()-.5)*SP,o=okAt(px,pz);if(o<0||!free(px,pz,SP))continue;put({x:px,z:pz,cid:o});act.push(pts.length-1)}
  while(act.length){const ai=Math.floor(rf()*act.length),a=pts[act[ai]];let found=false;
    for(let k=0;k<24;k++){const ang=rf()*Math.PI*2,r=SP*(1+rf()),x=a.x+Math.cos(ang)*r,z=a.z+Math.sin(ang)*r;if(x<-WX/2||z<-WZ/2||x>=WX/2||z>=WZ/2)continue;const o=okAt(x,z);if(o<0||!free(x,z,SP))continue;put({x,z,cid:o});act.push(pts.length-1);found=true;break}
    if(!found)act.splice(ai,1)}
  // Gabriel graph per state
  const by={};pts.forEach((p,i)=>(by[p.cid]=by[p.cid]||[]).push(i));const E=[];
  for(const cid in by){const L=by[cid];for(let a=0;a<L.length;a++)for(let b=a+1;b<L.length;b++){const P=pts[L[a]],Q=pts[L[b]],d=Math.hypot(P.x-Q.x,P.z-Q.z);if(d>SP*4.2)continue;
      const mx=(P.x+Q.x)/2,mz=(P.z+Q.z)/2,r2=(d/2)*(d/2)*.98;let ok=true;for(const c of L){if(c===L[a]||c===L[b])continue;const R=pts[c];if((R.x-mx)**2+(R.z-mz)**2<r2){ok=false;break}}
      if(ok)E.push({a:L[a],b:L[b],d})}}
  // pruning: drop the longer of two links that leave one point less than 38° apart
  E.sort((a,b)=>a.d-b.d);const keep=[],adj=pts.map(()=>[]);
  for(const e of E){let bad=false;for(const [u,v] of [[e.a,e.b],[e.b,e.a]]){const U=pts[u],V=pts[v],an=Math.atan2(V.z-U.z,V.x-U.x);for(const w of adj[u]){const W=pts[w],aw=Math.atan2(W.z-U.z,W.x-U.x);let df=Math.abs(an-aw);if(df>Math.PI)df=2*Math.PI-df;if(df<.6){bad=true;break}}if(bad)break}
    if(bad)continue;keep.push(e);adj[e.a].push(e.b);adj[e.b].push(e.a)}
  return keep.map(e=>[pts[e.a],pts[e.b]])}
/* ---------- test road generator: Gabriel graph + A* with road reuse ----------
   key points = every settlement + evenly spread countryside points (Poisson disk) so roads reach almost all land;
   A and B are joined only if no other point lies inside the circle with AB as its diameter (planar, with loops but no needless crossings). */
function gabPoints(T,comp){const SP=.3,rf=mulberry((SEED^0x6ab)>>>0),pts=[],cs=SP/Math.SQRT2,GW=Math.ceil(WX/cs),GH=Math.ceil(WZ/cs),grid=new Int32Array(GW*GH).fill(-1);
  const gi=(x,z)=>Math.floor((z+WZ/2)/cs)*GW+Math.floor((x+WX/2)/cs);
  const free=(x,z,r)=>{const i=Math.floor((x+WX/2)/cs),j=Math.floor((z+WZ/2)/cs);for(let v=j-3;v<=j+3;v++)for(let u=i-3;u<=i+3;u++){if(u<0||v<0||u>=GW||v>=GH)continue;const k=grid[v*GW+u];if(k>=0&&Math.hypot(pts[k].x-x,pts[k].z-z)<r)return false}return true};
  const put=p=>{const k=gi(p.x,p.z);if(k<0||k>=grid.length)return;pts.push(p);if(grid[k]<0)grid[k]=pts.length-1};
  for(const t of T)pts.push({x:t.x,z:t.z,node:t.node,town:t,cid:t.cid,lc:comp[t.node]});
  for(let i=0;i<pts.length;i++){const k=gi(pts[i].x,pts[i].z);if(k>=0&&k<grid.length&&grid[k]<0)grid[k]=i}
  const csz=new Map();for(let n=0;n<comp.length;n++)if(comp[n]>=0)csz.set(comp[n],(csz.get(comp[n])||0)+1);const big_=Math.max(...csz.values()),spOf=c=>(csz.get(c)||0)<big_*.18?.3:.4;
  const clear=.06,inland=(x,z)=>{const o=bOwn(x,z);if(o<0)return -1;for(const [dx,dz] of [[clear,0],[-clear,0],[0,clear],[0,-clear]])if(bOwn(x+dx,z+dz)!==o)return -1;return o};
  for(let tries=0;tries<160000;tries++){const x=(rf()-.5)*WX,z=(rf()-.5)*WZ,o=inland(x,z);if(o<0)continue;const n=nodeAt(x,z);if(comp[n]<0||!free(x,z,spOf(comp[n])))continue;put({x,z,node:n,cid:o,lc:comp[n]})}
  return pts}
/* a Gabriel graph of a point subset (points of one landmass only) */
function gabGraph(P,lim,skip){const cs=lim,GW=Math.ceil(WX/cs)+1,cell=new Map(),key=(x,z)=>Math.floor((z+WZ/2)/cs)*GW+Math.floor((x+WX/2)/cs);
  P.forEach((p,i)=>{const k=key(p.x,p.z);if(!cell.has(k))cell.set(k,[]);cell.get(k).push(i)});
  const near=(x,z,r)=>{const i=Math.floor((x+WX/2)/cs),j=Math.floor((z+WZ/2)/cs),n=Math.ceil(r/cs),out=[];for(let v=j-n;v<=j+n;v++)for(let u=i-n;u<=i+n;u++){const L=cell.get(v*GW+u);if(L)out.push(...L)}return out};
  const E=[];for(let a=0;a<P.length;a++){const A=P[a];for(const b of near(A.x,A.z,lim)){if(b<=a)continue;const B=P[b];if(A.lc!==B.lc||A.node===B.node||skip&&skip(A,B))continue;
      const d=Math.hypot(A.x-B.x,A.z-B.z);if(d>lim)continue;const mx=(A.x+B.x)/2,mz=(A.z+B.z)/2,r2=(d/2)*(d/2)*.999;let ok=true;
      for(const c of near(mx,mz,d/2)){if(c===a||c===b)continue;const C=P[c];if((C.x-mx)**2+(C.z-mz)**2<r2){ok=false;break}}if(ok)E.push({a:A,b:B,d})}}return E}
/* three layers: motorways between big cities, roads between all settlements, local roads over the whole land; each routed in that order so later ones join earlier ones */
function gabEdges(pts){const big=p=>p.town&&p.town.type!=="town"&&p.town.type!=="vil",set=p=>!!p.town,seen=new Set(),out=[];
  const take=(E,lv,cls)=>{E.sort((x,y)=>x.d-y.d);for(const e of E){const k=Math.min(e.a.node,e.b.node)+":"+Math.max(e.a.node,e.b.node);if(seen.has(k))continue;seen.add(k);out.push({...e,lv,cls})}};
  take(gabGraph(pts.filter(big),5.5),3,0);
  take(gabGraph(pts.filter(set),2.6).map(e=>({...e,lv:e.a.town.type!=="vil"&&e.b.town.type!=="vil"?2:1})),2,1);
  take(gabGraph(pts,1.5,(A,B)=>!A.town&&!B.town&&A.cid!==B.cid),1,2);
  return out.map(e=>e.cls===1?{...e,lv:e.a.town.type!=="vil"&&e.b.town.type!=="vil"?2:1}:e)}
const TINY_ISL=40; // landmasses smaller than this (lattice points) get no roads: only a port or an airport
async function boardRoads(){
  const N=BL.nx*BL.nz,D=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]],usedE=new Uint8Array(N*8),bits=new Uint8Array(N),usedR=new Uint8Array(N*8),rbits=new Uint8Array(N);let RS={u:usedE,b:bits,out:LOG,rail:false};
  const pn=makePerlin(mulberry((SEED^0x77)>>>0)),terr=new Float32Array(N),own=new Int16Array(N);for(let n=0;n<N;n++){const [x,z]=bXY(n);own[n]=bOwn(x,z);terr[n]=own[n]<0?1e9:1+.35*Math.max(-1,Math.min(1,pn(x*.35,z*.35)*1.6))}
  const comp=new Int32Array(N).fill(-1);{let k=0;for(let n=0;n<N;n++){if(own[n]<0||comp[n]>=0)continue;const st=[n];comp[n]=k;while(st.length){const m=st.pop(),x=m%BL.nx,y=(m/BL.nx)|0;for(const [dx,dy] of D){const nx=x+dx,ny=y+dy;if(nx<0||ny<0||nx>=BL.nx||ny>=BL.nz)continue;const q=ny*BL.nx+nx;if(own[q]>=0&&comp[q]<0){comp[q]=k;st.push(q)}}}k++}}
  BOARD.comp=comp;const csz=new Map();for(let n=0;n<N;n++)if(comp[n]>=0)csz.set(comp[n],(csz.get(comp[n])||0)+1);BOARD.csz=csz;const tinyN=n=>(csz.get(comp[n])||0)<TINY_ISL;
  /* a capital cut off from its own towns (on a separate island) moves to the biggest town of the country's main landmass */
  if(!G.loadW)for(const c of G.C){const ts=(BOARD.towns||[]).filter(t=>t.cid===c.id&&t.node!=null&&comp[t.node]>=0),cap=ts.find(t=>t.type==="cap");if(!cap)continue;
    const grp=new Map();for(const t of ts){const g=comp[t.node];grp.set(g,(grp.get(g)||0)+(t.type==="vil"?.3:1))}
    let bg=comp[cap.node],bn=grp.get(bg)||0;for(const [g,n] of grp)if(n>bn+.5&&!tinyN(ts.find(t=>comp[t.node]===g).node)){bg=g;bn=n}
    if(bg===comp[cap.node])continue;const nc=ts.filter(t=>comp[t.node]===bg&&t.type!=="vil").sort((a,b)=>b.pop-a.pop)[0];if(!nc)continue;
    cap.type="city";nc.type="cap";nc.pop=Math.max(nc.pop,cap.pop);c.capName=nc.name;c.geo.cap={x:(nc.x+WX/2)/WX*MW,y:(nc.z+WZ/2)/WZ*MH}}
  // a road edge must lie on land: an edge between two triangles of the lattice needs land on at least one side,
  // an edge that cuts through a square against its diagonal needs both halves on land — no roads "in the air" over water
  const eok=new Uint8Array(N*8),st=BL.st,LD=(u,v)=>bOwn(-WX/2+u*st,-WZ/2+v*st)>=0,OW=(u,v)=>bOwn(-WX/2+u*st,-WZ/2+v*st),OK2=(u1,v1,u2,v2)=>{const a=OW(u1,v1),b=OW(u2,v2);return (a>=0||b>=0)&&!(a>=0&&b>=0&&a!==b)};
  for(let n=0;n<N;n++){if(own[n]<0&&!0)continue;const x=n%BL.nx,y=(n/BL.nx)|0;for(let d=0;d<8;d++){const dx=D[d][0],dy=D[d][1],x2=x+dx,y2=y+dy;if(x2<0||y2<0||x2>=BL.nx||y2>=BL.nz)continue;
    const mx=x+dx/2,my=y+dy/2;let ok;
    if(!dx||!dy){const px=-dy,py=dx;ok=OK2(mx+px*.2,my+py*.2,mx-px*.2,my-py*.2)}
    else{const ci=Math.min(x,x2),cj=Math.min(y,y2),sd=SQD&&ci<SQW&&cj<SQH?SQD[cj*SQW+ci]:(dx*dy>0?1:0),along=(dx*dy>0)===(sd===1);
      if(along){const px=-dy/Math.SQRT2,py=dx/Math.SQRT2;ok=OK2(mx+px*.25,my+py*.25,mx-px*.25,my-py*.25)}
      else{const c=sd?[[2/3,1/3],[1/3,2/3]]:[[1/3,1/3],[2/3,2/3]];ok=LD(ci+c[0][0],cj+c[0][1])&&LD(ci+c[1][0],cj+c[1][1])}}
    eok[n*8+d]=ok?1:0}}
  LOG.hw=[];LOG.rail=[];LOG.air=[];LOG.ports=[];LOG.cities=[];LOG.towns=[];LOG.vil=[];LOG.ticks=new Float32Array(0);
  const route=(a,b,lv,lockC)=>{if(tinyN(a)||tinyN(b))return;lockC=lockC??-1;const S=N*9,g=new Float32Array(S).fill(1e9),prev=new Int32Array(S).fill(-1),hk=[],hv=[];
    const push=(f,s)=>{hk.push(f);hv.push(s);let k=hk.length-1;while(k>0){const p=(k-1)>>1;if(hk[p]<=hk[k])break;[hk[p],hk[k]]=[hk[k],hk[p]];[hv[p],hv[k]]=[hv[k],hv[p]];k=p}};
    const pop=()=>{const s=hv[0],lk=hk.pop(),lv_=hv.pop();if(hk.length){hk[0]=lk;hv[0]=lv_;let k=0;for(;;){const l=k*2+1,r=l+1;let m=k;if(l<hk.length&&hk[l]<hk[m])m=l;if(r<hk.length&&hk[r]<hk[m])m=r;if(m===k)break;[hk[m],hk[k]]=[hk[k],hk[m]];[hv[m],hv[k]]=[hv[k],hv[m]];k=m}}return s};
    const bi=b%BL.nx,bj=(b/BL.nx)|0,hh=n=>{const dx=Math.abs(n%BL.nx-bi),dz=Math.abs(((n/BL.nx)|0)-bj);return (Math.max(dx,dz)+.4142*Math.min(dx,dz))*.45};
    const s0=a*9+8;g[s0]=0;push(hh(a),s0);let end=-1;
    while(hk.length){const s=pop(),n=(s/9)|0,dir=s%9;if(n===b){end=s;break}const gs=g[s];const x=n%BL.nx,y=(n/BL.nx)|0;
      for(let d=0;d<8;d++){if(dir<8){const df=Math.min(Math.abs(d-dir),8-Math.abs(d-dir));if(df>(RS.gab?3:2))continue}
        const nx=x+D[d][0],ny=y+D[d][1];if(nx<0||ny<0||nx>=BL.nx||ny>=BL.nz)continue;const m=ny*BL.nx+nx;
        const df=dir<8?Math.min(Math.abs(d-dir),8-Math.abs(d-dir)):0;
        if(terr[m]>=1e9||!eok[n*8+d]||lockC>=0&&own[m]!==lockC)continue;const c=RS.gab?(d&1?1.4142:1)*(RS.u[n*8+d]?RS.reuse:1)+df*.35+(own[m]!==own[n]?.6:0):(d&1?1.4142:1)*(RS.u[n*8+d]?(RS.rail?.2:.32):terr[m]*(RS.rail?1.15*(usedE[n*8+d]?6:bits[m]&&m!==b?1.8:1):1))+ /* railways keep their own corridor beside the roads */(df===1?(RS.rail?1.1:.35):df===2?(RS.rail?9:1.6):0)+(own[m]!==own[n]?.6:0);
        const ns=m*9+d,ng=gs+c;if(ng<g[ns]){g[ns]=ng;prev[ns]=s;push(ng+hh(m),ns)}}}
    if(end<0)return;const nodes=[];for(let s=end;s>=0;s=prev[s])nodes.push((s/9)|0);nodes.reverse();
    for(let k=1;k<nodes.length;k++){const a_=nodes[k-1],b_=nodes[k];const dx=b_%BL.nx-a_%BL.nx,dz=((b_/BL.nx)|0)-((a_/BL.nx)|0);const d=D.findIndex(q=>q[0]===dx&&q[1]===dz);RS.u[a_*8+d]=1;RS.u[b_*8+((d+4)%8)]=1;RS.b[a_]|=1<<d;RS.b[b_]|=1<<((d+4)%8)}
    // simplify collinear runs into polyline vertices
    const pts=[];for(let k=0;k<nodes.length;k++){const [x,z]=bXY(nodes[k]);pts.push(x,z)}
    if(pts.length>=4){if(RS.rail)LOG.rail.push({p:new Float32Array(pts)});else LOG.hw.push({lv,p:new Float32Array(pts)})}};
  const rr2=mulberry((SEED^0x99)>>>0),T=BOARD.towns,same=(a,b)=>comp[a.node]===comp[b.node],dist=(a,b)=>same(a,b)?Math.hypot(a.x-b.x,a.z-b.z):1e9,cities=T.filter(t=>t.type!=="town"&&t.type!=="vil");
  if(SET.roadGab){RS.gab=true;const pts=gabPoints(T,comp),E=gabEdges(pts);let r=0;window.__gab={pts:pts.length,edges:E.length};
    for(const e of E){RS.reuse=e.cls===2?.75:.3;route(e.a.node,e.b.node,e.lv);if(++r%30===0)await tick()}RS.gab=false;BOARD.bits=bits}
  else{
  // 1. motorways between cities: minimum spanning tree + each city to its nearest neighbours
  const links=[],seen=new Set(),add=(a,b,lv)=>{const k=Math.min(a.node,b.node)+":"+Math.max(a.node,b.node);if(seen.has(k))return;seen.add(k);links.push([a,b,lv])};
  {const inT=[cities[0]];const rest=cities.slice(1);while(rest.length){let bd=1e9,bi=0,bo=null;rest.forEach((c,i)=>inT.forEach(o=>{const d=dist(c,o);if(d<bd){bd=d;bi=i;bo=o}}));const c=rest.splice(bi,1)[0];if(bd<1e8)add(bo,c,3);inT.push(c)}}
  cities.forEach(c=>cities.filter(o=>o!==c).sort((a,b)=>dist(a,c)-dist(b,c)).slice(0,4).forEach((o,q)=>{if(dist(o,c)<(q<2?7:4.5))add(c,o,3)}));
  let k=0;for(const [a,b,lv] of links){route(a.node,b.node,lv);if(++k%6===0)await tick()}
  // 2. towns: 2–4 links each, villages 2–3 links: a dense web with alternative routes
  const lk=new Set(),link=(a,b,lv)=>{const key=Math.min(a.node,b.node)+":"+Math.max(a.node,b.node);if(lk.has(key)||seen.has(key))return;lk.add(key);route(a.node,b.node,lv)};
  const net=cities.slice();for(const t of T.filter(t=>t.type==="town").sort((a,b)=>Math.min(...cities.map(c=>dist(a,c)))-Math.min(...cities.map(c=>dist(b,c))))){
    const near=net.slice().sort((a,b)=>dist(a,t)-dist(b,t));near.slice(0,4).forEach((o,q)=>{const d=dist(o,t);if(d<1e8&&(q===0||d<(q===1?3:2.4)&&(q<3||rr2()<.5)))link(t,o,2)});net.push(t);if(++k%8===0)await tick()}
  // 3. villages: local roads to the nearest settlement
  for(const v of T.filter(t=>t.type==="vil")){const near=net.slice().sort((a,b)=>dist(a,v)-dist(b,v));near.slice(0,3).forEach((o,q)=>{const d=dist(o,v);if(d<1e8&&(q===0||d<(q===1?3:1.9)&&(q<2||rr2()<.5)))link(v,o,1.5)});net.push(v);if(++k%12===0)await tick()}
  // 4. the countryside: a planar web of local roads over every state (never across a border)
  {const web=roadWeb(T,.4),fk=new Set();let r=0;
    for(const [p,q] of web){const a=p.town?p.town.node:nodeAt(p.x,p.z),b=q.town?q.town.node:nodeAt(q.x,q.z);if(a===b)continue;const key=Math.min(a,b)+":"+Math.max(a,b);if(fk.has(key)||lk.has(key)||seen.has(key))continue;fk.add(key);route(a,b,1,p.cid);if(++r%40===0)await tick()}}
  BOARD.bits=bits;}
  // railways: capitals ↔ neighbouring capitals, capital ↔ big cities of its country, every city ↔ nearest rail hub
  RS={u:usedR,b:rbits,rail:true};const rseen=new Set(),rl=(a,b)=>{const key=Math.min(a.node,b.node)+":"+Math.max(a.node,b.node);if(rseen.has(key)||dist(a,b)>=1e8)return;rseen.add(key);route(a.node,b.node,0)};
  const caps=T.filter(t=>t.type==="cap"&&G.C[t.cid].geo.area>2500);if(!caps.length)caps.push(...T.filter(t=>t.type==="cap"));const bigs=T.filter(t=>t.type==="big"),cits=T.filter(t=>t.type==="city");
  {const inT=[caps[0]],rest=caps.slice(1);while(rest.length){let bd=1e9,bi=0,bo=null;rest.forEach((c,i)=>inT.forEach(o=>{const d=dist(c,o);if(d<bd){bd=d;bi=i;bo=o}}));const c=rest.splice(bi,1)[0];if(bd<1e8&&bd<9)rl(bo,c);inT.push(c)}}
  caps.forEach(c=>caps.filter(o=>o!==c).sort((a,b)=>dist(a,c)-dist(b,c)).slice(0,2).forEach(o=>{if(dist(o,c)<6)rl(c,o)}));await tick();
  bigs.forEach(b=>{const cap=caps.find(c=>c.cid===b.cid)||caps.slice().sort((x,y)=>dist(x,b)-dist(y,b))[0];if(cap)rl(b,cap);const o=bigs.concat(caps).filter(x=>x!==b&&x!==cap).sort((x,y)=>dist(x,b)-dist(y,b))[0];if(o&&dist(o,b)<5)rl(b,o)});await tick();
  cits.forEach(c=>{const o=caps.concat(bigs).sort((x,y)=>dist(x,c)-dist(y,c))[0];if(o&&dist(o,c)<6)rl(c,o)});
  BOARD.rbits=rbits;for(const t of T)if(tinyN(t.node)&&t.portOv!==false)t.portOv=true;boardPorts();for(const t of T)if(tinyN(t.node)&&!t.port)t.airOv=true;boardCheckpoints();BOARD.rnodes=new Set(T.filter(t=>rbits[t.node]).map(t=>t.node));
  LOG.built=true;
}
/* ports: settlements whose lattice point sits on the land/water edge */
function bWaterCell(ci,cj){if(ci<0||cj<0||ci>=CBL.nx-1||cj>=CBL.nz-1)return false;const x0=-WX/2+ci*CBL.st,z0=-WZ/2+cj*CBL.st;for(const [u,v] of [[.25,.25],[.75,.25],[.25,.75],[.75,.75],[.5,.5]])if(bOwn(x0+u*CBL.st,z0+v*CBL.st)>=0)return false;return true}
function boardPorts(){const T=BOARD.towns;for(const t of T){t.port=false;if(t.portOv===false)continue;if(t.type==="vil"&&!t.portOv)continue;const x=t.x,z=t.z,q=CBL.st*.3;let w=0,l=0;for(const [dx,dz] of [[q,q],[-q,q],[q,-q],[-q,-q]])(bOwn(x+dx,z+dz)<0?w++:l++);
  if(!w)continue;const i=Math.round((t.x+WX/2)/CBL.st),j=Math.round((t.z+WZ/2)/CBL.st);let wc=null;for(let r=0;r<=2&&!wc;r++)for(let dj=-1-r;dj<=r&&!wc;dj++)for(let di=-1-r;di<=r;di++)if(bWaterCell(i+di,j+dj)){wc=[i+di,j+dj];break}
  if(!wc)continue;if(t.type==="town"&&!t.portOv&&((t.node*2654435761)>>>0)%10>=6)continue;t.port=true;t.wc=wc}
  BOARD.sea=new Map()}
function boardSea(A,B){const ta=BOARD.towns[A.id],tb=BOARD.towns[B.id];if(!ta||!tb||!ta.wc||!tb.wc)return null;const key=A.id+":"+B.id;if(BOARD.sea.has(key))return BOARD.sea.get(key);
  const W=CBL.nx-1,H=CBL.nz-1,N=W*H,g=new Float32Array(N).fill(1e9),prev=new Int32Array(N).fill(-1),wat=BOARD.wat||(BOARD.wat=(()=>{const a=new Uint8Array(N);for(let j=0;j<H;j++)for(let i=0;i<W;i++)a[j*W+i]=bWaterCell(i,j)?1:0;return a})());
  const s0=ta.wc[1]*W+ta.wc[0],e0=tb.wc[1]*W+tb.wc[0],ex=tb.wc[0],ey=tb.wc[1],hk=[],hv=[];
  const push=(f,v)=>{hk.push(f);hv.push(v);let k=hk.length-1;while(k>0){const p=(k-1)>>1;if(hk[p]<=hk[k])break;[hk[p],hk[k]]=[hk[k],hk[p]];[hv[p],hv[k]]=[hv[k],hv[p]];k=p}};
  const pop=()=>{const v=hv[0],lk=hk.pop(),lv=hv.pop();if(hk.length){hk[0]=lk;hv[0]=lv;let k=0;for(;;){const l=k*2+1,r=l+1;let m=k;if(l<hk.length&&hk[l]<hk[m])m=l;if(r<hk.length&&hk[r]<hk[m])m=r;if(m===k)break;[hk[m],hk[k]]=[hk[k],hk[m]];[hv[m],hv[k]]=[hv[k],hv[m]];k=m}}return v};
  g[s0]=0;push(0,s0);while(hk.length){const n=pop();if(n===e0)break;const x=n%W,y=(n/W)|0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const nx=x+dx,ny=y+dy;if(nx<0||ny<0||nx>=W||ny>=H)continue;const m=ny*W+nx;if(!wat[m])continue;if(dx&&dy&&(!wat[y*W+nx]||!wat[ny*W+x]))continue;
    const ng=g[n]+(dx&&dy?1.4142:1);if(ng<g[m]){g[m]=ng;prev[m]=n;push(ng+Math.hypot(nx-ex,ny-ey),m)}}}
  let res=null;if(g[e0]<1e9){const cells=[];for(let n=e0;n>=0;n=prev[n]){cells.push(n);if(n===s0)break}cells.reverse();
    const ax=ta.x,az=ta.z,bx=tb.x,bz=tb.z,pts=[ax,az];let pd=null;for(let k=0;k<cells.length;k++){const c=cells[k],d=k?c-cells[k-1]:null;if(k>0&&k<cells.length-1&&d===cells[k+1]-c)continue;pts.push(-WX/2+(c%W+.5)*CBL.st,-WZ/2+(((c/W)|0)+.5)*CBL.st)}pts.push(bx,bz);res=new Float32Array(pts)}
  BOARD.sea.set(key,res);return res}
function boardPath(a,b,bitsArg){ // shortest path on the built road graph between two lattice nodes
  const N=BL.nx*BL.nz,D=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]],g=new Float32Array(N).fill(1e9),prev=new Int32Array(N).fill(-1),hk=[],hv=[],bits=bitsArg||BOARD.bits,isR=!!bitsArg&&bitsArg===BOARD.rbits;
  const push=(f,s)=>{hk.push(f);hv.push(s);let k=hk.length-1;while(k>0){const p=(k-1)>>1;if(hk[p]<=hk[k])break;[hk[p],hk[k]]=[hk[k],hk[p]];[hv[p],hv[k]]=[hv[k],hv[p]];k=p}};
  const pop=()=>{const s=hv[0],lk=hk.pop(),lv_=hv.pop();if(hk.length){hk[0]=lk;hv[0]=lv_;let k=0;for(;;){const l=k*2+1,r=l+1;let m=k;if(l<hk.length&&hk[l]<hk[m])m=l;if(r<hk.length&&hk[r]<hk[m])m=r;if(m===k)break;[hk[m],hk[k]]=[hk[k],hk[m]];[hv[m],hv[k]]=[hv[k],hv[m]];k=m}}return s};
  g[a]=0;push(0,a);while(hk.length){const n=pop();if(n===b)break;const x=n%BL.nx,y=(n/BL.nx)|0;for(let d=0;d<8;d++){if(!(bits[n]&(1<<d)))continue;const m=(y+D[d][1])*BL.nx+x+D[d][0];if(BLK&&BLK(n,m,isR))continue;const ng=g[n]+(d&1?1.4142:1)*BL.st;if(ng<g[m]){g[m]=ng;prev[m]=n;push(ng,m)}}}
  if(g[b]>=1e9)return null;const nodes=[];for(let n=b;n>=0;n=prev[n]){nodes.push(n);if(n===a)break}nodes.reverse();
  const pts=[];for(let k=0;k<nodes.length;k++){if(k>0&&k<nodes.length-1&&nodes[k]-nodes[k-1]===nodes[k+1]-nodes[k])continue;const [x,z]=bXY(nodes[k]);pts.push(x,z)}return new Float32Array(pts.length>=4?pts:[...pts,...pts])}
const BRAD={cap:.08,big:.064,city:.052,town:.032,vil:.016};
/* legend filters */
const LF_SET={port:p=>p.port!=null,air:p=>p.air,rail:p=>p.rail,hub:p=>!!hubAt(p.id)};
/* legend = visibility switches: every item can be shown/hidden on the map */
UI.hid=(()=>{try{return new Set(JSON.parse(localStorage.getItem("pon_hid")||"[]"))}catch(e){return new Set()}})();
function vis(k){if(!G.co)return true;if(UI.hid.has(k))return false;if((k==="r1"||k==="r2"||k==="r3")&&UI.hid.has("roads"))return false;return true}
ACT.lv=k=>{UI.hid.has(k)?UI.hid.delete(k):UI.hid.add(k);try{localStorage.setItem("pon_hid",JSON.stringify([...UI.hid]))}catch(e){}REDRAW=true;applyMapColors();updateLegend();coChipFilter();CITY_KEY=""};
ACT.lvAll=()=>{UI.hid.clear();try{localStorage.setItem("pon_hid","[]")}catch(e){}REDRAW=true;applyMapColors();updateLegend();coChipFilter()};
function hubVis(pid){if(!vis("hub"))return null;const h=hubAt(pid);return h&&vis("hub_"+h.lvl)?h:null}
function lfMatch(p){return true}
function lfCountries(){return null}
const iconD=n=>{const s=ICONS[n],A=(el,k)=>{const m=el.match(new RegExp("\\b"+k+'="([^"]+)"'));return m?+m[1]:0},o=[];
  for(const m of s.matchAll(/<(path|circle|line|rect)\b[^>]*>/g)){const el=m[0];if(m[1]==="path"){const d=el.match(/\bd="([^"]+)"/);if(d)o.push(d[1])}
    else if(m[1]==="circle"){const cx=A(el,"cx"),cy=A(el,"cy"),r=A(el,"r");o.push(`M${cx-r} ${cy}a${r} ${r} 0 1 0 ${2*r} 0a${r} ${r} 0 1 0 ${-2*r} 0`)}
    else if(m[1]==="line")o.push(`M${A(el,"x1")} ${A(el,"y1")}L${A(el,"x2")} ${A(el,"y2")}`);
    else{const x=A(el,"x"),y=A(el,"y"),w=A(el,"width"),h=A(el,"height");o.push(`M${x} ${y}h${w}v${h}h${-w}z`)}}return o.join(" ")};
const ICP={};function icPath(n){return ICP[n]||(ICP[n]=new Path2D(iconD(n)))}
function drawIcons(g,list,x,y,sz,col){const sc=sz/24;for(const n of list){g.save();g.translate(x,y-sz/2);g.scale(sc,sc);g.strokeStyle=col;g.lineWidth=1.8;g.lineJoin="round";g.lineCap="round";g.stroke(icPath(n));g.restore();x+=sz+2}}
ACT.lf=k=>{UI.lf=UI.lf===k?null:k;applyMapColors();updateLegend();CITY_KEY="";coChipFilter()};
function coChipFilter(){if(!CITY_EL.length)return;for(const c of CITY_EL){if(!c.cap)continue;{const on=vis("s_city");c.el.style.opacity=on?"":"0";c.el.style.pointerEvents=on?"":"none"}const pl=PL.find(q=>q.type==="cap"&&q.cid===c.cid);const ht=c.el.querySelector(".hubtag");const hv=pl&&hubVis(pl.id);if(ht)ht.style.display=hv?"":"none";c.el.classList.toggle("hubcap",!!hv);{const hh=pl&&hubAt(pl.id);c.el.classList.toggle("rentcap",!!(hv&&hh&&hh.rent))}
  const cb=c.el.querySelector(".cb em");if(cb&&pl&&G.board){let t=cb.querySelector(".fac");if(!t){t=document.createElement("span");t.className="fac";cb.appendChild(t)}t.innerHTML=[pl.port!=null&&vis("port")?ic("anchor"):"",pl.air&&vis("air")?ic("plane"):"",pl.rail&&vis("rails")?ic("train"):""].join("")}}}
/* coastal side walls: real vertical faces dropped from every coastline vertex by half a lattice square.
   upper half — soil, lower half — under water; faces turned away from the camera are skipped */
let WALLS=null,WALLS_W=null;
function wallSegs(){if(WALLS&&WALLS_W===G.world)return WALLS;WALLS_W=G.world;WALLS=[];const own=G.world.own,wat=(x,z)=>{const px=Math.floor((x+WX/2)/WX*MW),py=Math.floor((z+WZ/2)/WZ*MH);if(px<0||py<0||px>=MW||py>=MH)return true;return own[py*MW+px]<0};
  for(const l of G.world.lines){if(l.a!==0)continue;const p=l.p;for(let i=2;i<p.length;i+=2){const x1=p[i-2],z1=p[i-1],x2=p[i],z2=p[i+1],L=Math.hypot(x2-x1,z2-z1);if(L<1e-6)continue;
    let nx=-(z2-z1)/L,nz=(x2-x1)/L;const mx=(x1+x2)/2,mz=(z1+z2)/2;if(!wat(mx+nx*.02,mz+nz*.02)){nx=-nx;nz=-nz}
    WALLS.push({x1,z1,x2,z2,nx,nz,tri:wallWater(x1,z1,x2,z2,nx,nz,wat),bb:[Math.min(x1,x2),Math.max(x1,x2),Math.min(z1,z2),Math.max(z1,z2)]})}}return WALLS}
/* water triangles of the lattice right in front of a wall: the face is clipped to them, so it never hangs over land in front of it */
function wallWater(x1,z1,x2,z2,nx,nz,wat){if(!SQD||TRI_K!==0)return null;const st=TRI_S/MW*WX,out=[],i0=Math.floor((Math.min(x1,x2)+WX/2)/st)-4,i1=Math.floor((Math.max(x1,x2)+WX/2)/st)+4,j0=Math.floor((Math.min(z1,z2)+WZ/2)/st)-4,j1=Math.floor((Math.max(z1,z2)+WZ/2)/st)+4;
  const mx=(x1+x2)/2,mz=(z1+z2)/2,dx=x2-x1,dz=z2-z1,LL=dx*dx+dz*dz;let landFront=0;
  const dSeg=(px,pz)=>{const t=clamp(((px-x1)*dx+(pz-z1)*dz)/LL,0,1);return Math.hypot(px-x1-dx*t,pz-z1-dz*t)};
  for(let j=j0;j<=j1;j++)for(let i=i0;i<=i1;i++){if(i<0||j<0||i>=SQW||j>=SQH)continue;const d=SQD[j*SQW+i],X=-WX/2+i*st,Z=-WZ/2+j*st;
    const T=d?[[[0,0],[1,0],[1,1]],[[0,0],[1,1],[0,1]]]:[[[0,0],[1,0],[0,1]],[[1,0],[1,1],[0,1]]];
    for(const t of T){const cx=X+(t[0][0]+t[1][0]+t[2][0])/3*st,cz=Z+(t[0][1]+t[1][1]+t[2][1])/3*st;if(dSeg(cx,cz)>st*3.2)continue;
      if(!wat(cx,cz)){const tt=((cx-x1)*dx+(cz-z1)*dz)/LL;if((cx-mx)*nx+(cz-mz)*nz>st*.05&&dSeg(cx,cz)<st*2.4&&tt>-.7&&tt<1.7)landFront++; /* land just past a corner counts too: the face is clipped there */continue}for(const v of t)out.push(X+v[0]*st,Z+v[1]*st)}}
  if(!out.length)return null;const r=new Float32Array(out);r.free=!landFront;return r}
/* faces in open water are drawn in one batch; only walls with land close in front are clipped one by one */
function drawWalls(g,dpr){const h0=CST/2,a=project(Cam.tx,0,Cam.tz),b=project(Cam.tx,-h0,Cam.tz),c=project(Cam.tx,0,Cam.tz+h0);if(!a||!b||!c)return;
  const vl=Math.hypot(a.x-b.x,a.y-b.y),dl=Math.hypot(a.x-c.x,a.y-c.y),H=h0*clamp(dl/Math.max(vl,1e-3),1,6);if(dl<1.5)return;
  const W=wallSegs(),vb=vbox(),e=GL.eye||camEye(),P=(x,y,z)=>{const q=project(x,y,z);return q?[q.x*dpr,q.y*dpr]:null},lx=-.45,lz=.89;
  const free=[[],[],[],[],[],[],[]],tight=[];
  const wb=project(Cam.tx,-H,Cam.tz),clipOn=!!wb&&Math.hypot(wb.x-a.x,wb.y-a.y)>12; /* thin walls (zoomed out): the overhang is under a pixel or two — no per-wall clipping */
  for(const s of W){if(vb&&(s.bb[1]<vb.x0||s.bb[0]>vb.x1||s.bb[3]<vb.z0||s.bb[2]>vb.z1))continue;if(s.nx*(e[0]-(s.x1+s.x2)/2)+s.nz*(e[2]-(s.z1+s.z2)/2)<=0)continue;if(!s.tri)continue;
    const t1=P(s.x1,0,s.z1),t2=P(s.x2,0,s.z2),m1=P(s.x1,-H/2,s.z1),m2=P(s.x2,-H/2,s.z2),b1=P(s.x1,-H,s.z1),b2=P(s.x2,-H,s.z2);if(!t1||!t2||!m1||!m2||!b1||!b2)continue;
    const v={t1,t2,m1,m2,b1,b2,lv:Math.round(Math.max(0,s.nx*lx+s.nz*lz)*6),s};if(s.tri.free||!clipOn)free[v.lv].push(v);else tight.push(v)}
  const shade=L=>{const sh=.62+.38*L/6;return[`rgb(${Math.round(112*sh)},${Math.round(80*sh)},${Math.round(54*sh)})`,`rgba(${Math.round(18+22*sh)},${Math.round(62+40*sh)},${Math.round(92+40*sh)},.72)`]};
  const faces=(L,col)=>{g.fillStyle=col[0];g.beginPath();for(const v of L){g.moveTo(...v.t1);g.lineTo(...v.t2);g.lineTo(...v.m2);g.lineTo(...v.m1);g.closePath()}g.fill();
    g.fillStyle=col[1];g.beginPath();for(const v of L){g.moveTo(...v.m1);g.lineTo(...v.m2);g.lineTo(...v.b2);g.lineTo(...v.b1);g.closePath()}g.fill()};
  const lines=L=>{g.strokeStyle="rgba(10,16,22,.45)";g.lineWidth=1*dpr;g.beginPath();for(const v of L){g.moveTo(...v.t1);g.lineTo(...v.b1);g.moveTo(...v.t2);g.lineTo(...v.b2)}g.stroke();
    g.strokeStyle="rgba(170,225,250,.45)";g.beginPath();for(const v of L){g.moveTo(...v.m1);g.lineTo(...v.m2)}g.stroke()};
  g.lineJoin="miter";for(let L=0;L<=6;L++)if(free[L].length)faces(free[L],shade(L));lines(free.flat());
  for(const v of tight){const tq=v.s.tri;g.save();g.beginPath();let ok=true;for(let k=0;k<tq.length;k+=6){const A=P(tq[k],0,tq[k+1]),B=P(tq[k+2],0,tq[k+3]),C=P(tq[k+4],0,tq[k+5]);if(!A||!B||!C){ok=false;break}g.moveTo(...A);g.lineTo(...B);g.lineTo(...C);g.closePath()}
    if(ok){g.clip();faces([v],shade(v.lv));lines([v])}g.restore()}}
const MTW=new Map();function mtW(g,t){const k=g.font+"|"+t;let w=MTW.get(k);if(w==null){w=g.measureText(t).width;if(MTW.size>6000)MTW.clear();MTW.set(k,w)}return w}
function drawBoardTowns(g,dpr){
  BOARD.lbl=[];if(!BOARD.towns)return;
  {const P2=(x,z)=>{const p=project(x,0,z);return p?[p.x*dpr,p.y*dpr]:null};const a=P2(Cam.tx,Cam.tz),b=P2(Cam.tx+1,Cam.tz),pu=a&&b?Math.hypot(b[0]-a[0],b[1]-a[1])/dpr:40;
   if(pu>45&&(!UI.lf||UI.lf==="road"||UI.lf==="railway")){const W=g.canvas.width,H=g.canvas.height,sz=clamp(pu/40,3.5,7)*dpr;const busy=new Set();for(const j of CO.jobs||[]){const st=coJobState(j,coNow()-j.t0);if(/Пропускний/.test(st.ph)){const q=coPosAt(j,st.s);busy.add(Math.round(q[0]*20)+":"+Math.round(q[1]*20))}}
    for(const c of BOARD.cps||[]){if(!vis("cp"))break;if(c.rail?!vis("rail"):!(vis("r1")||vis("r2")||vis("r3")))continue;const q=P2(c.x,c.z);if(!q||q[0]<-20||q[1]<-20||q[0]>W+20||q[1]>H+20)continue;
      g.fillStyle="#0b1520";g.strokeStyle="#e8edf2";g.lineWidth=1.2*dpr;g.fillRect(q[0]-sz,q[1]-sz,sz*2,sz*2);g.strokeRect(q[0]-sz,q[1]-sz,sz*2,sz*2);
      g.save();g.beginPath();g.rect(q[0]-sz,q[1]-sz*.35,sz*2,sz*.7);g.clip();for(let k=-3;k<4;k++){g.fillStyle=k%2?"#f0625f":"#ffffff";g.beginPath();g.moveTo(q[0]+k*sz*.5,q[1]-sz);g.lineTo(q[0]+k*sz*.5+sz*.5,q[1]-sz);g.lineTo(q[0]+k*sz*.5,q[1]+sz);g.lineTo(q[0]+k*sz*.5-sz*.5,q[1]+sz);g.fill()}g.restore()}}}const P=(x,z)=>{const p=project(x,0,z);return p?[p.x*dpr,p.y*dpr]:null};const W=g.canvas.width,H=g.canvas.height;
  const c0=P(Cam.tx,Cam.tz),c1=P(Cam.tx+1,Cam.tz);const ppu=c0&&c1?Math.hypot(c1[0]-c0[0],c1[1]-c0[1])/dpr:40;
  const RAD=BRAD;const boxes=[];
  const order=(BOARD.ordPL&&BOARD.ordPL.length===PL.length&&BOARD.ordPL[0]&&PL.includes(BOARD.ordPL[0]))?BOARD.ordPL:(BOARD.ordPL=PL.slice().sort((a,b)=>({cap:0,big:1,city:2,town:3,vil:4}[a.type]-{cap:0,big:1,city:2,town:3,vil:4}[b.type])));
  const lfOn=UI.lf&&LF_SET[UI.lf];
  const vbT=vbox();for(const p of order){if(vbT&&(p.x<vbT.x0||p.x>vbT.x1||p.z<vbT.z0||p.z>vbT.z1))continue;const edAll=typeof ED!=="undefined"&&ED.on; // the editor always shows every settlement
    if(!edAll&&!vis(p.type==="vil"?"s_vil":p.type==="town"?"s_town":"s_city"))continue;const shown=edAll||(p.type==="vil"?ppu>150:p.type==="town"?ppu>60:true);if(!shown)continue;const c=P(p.x,p.z);if(!c||c[0]<-60||c[1]<-60||c[0]>W+60||c[1]>H+60)continue;
    if(!lfMatch(p))continue;
    const hbm=hubVis(p.id);if(hbm){const hs=({cap:7,big:6,city:5,town:4,vil:3}[p.type]||4)*dpr;
      if(p.type!=="cap"){g.fillStyle=CITY_EV.has(p.id)?"#f0625f":hbm.rent?"#a9b4be":"#ffb347";g.strokeStyle="#06121b";g.lineWidth=1.4*dpr;g.fillRect(c[0]-hs,c[1]-hs,hs*2,hs*2);g.strokeRect(c[0]-hs,c[1]-hs,hs*2,hs*2)}}
    if(p.type==="cap"&&!ED.on)continue; // capitals use the country label chip (the editor has no chips)
    const s=hbm?({big:6,city:5,town:4,vil:3}[p.type]||4)*dpr:(p.type==="cap"?5:p.type==="big"||p.type==="city"?4:p.type==="town"?3:2.2)*dpr;if(!hbm){g.fillStyle=CITY_EV.has(p.id)?"#f0625f":p.type==="vil"||p.type==="town"?"#ffffff":"#5cc8f2";g.strokeStyle="#071420";g.lineWidth=1.3*dpr;
    {const d=s*.86;g.save();g.translate(c[0],c[1]);g.rotate(Math.PI/4);g.fillRect(-d,-d,2*d,2*d);g.strokeRect(-d,-d,2*d,2*d);g.restore()}}
    if(UI.hideNames)continue;
    // label (skip if it would overlap a more important one)
    const big=p.type==="cap"||p.type==="big"||p.type==="city";const fs=(big?12:p.type==="town"?10.5:9.5)*dpr;const hb=hubVis(p.id),tag=hb?(p.id===CO.hq?"★ ШТАБ · ":"")+(hb.rent?"ОРЕНДА · ":"")+HUB_LV[hb.lvl].toUpperCase():"";
    g.font=`700 ${9*dpr}px "JetBrains Mono",monospace`;const tgw=tag?mtW(g,tag):0;g.font=`${big?700:600} ${fs}px "Inter",sans-serif`;const icl=[p.port!=null&&vis("port")?"anchor":"",p.air&&vis("air")?"plane":"",p.rail&&vis("rails")?"train":""].filter(Boolean),pml=typeof poHasOff==="function"&&poHasOff(p.id),isz=11*dpr,nmw=mtW(g,p.name)+(icl.length+(pml?1:0)?(icl.length+(pml?1:0))*(isz+2*dpr)+4*dpr:0);const tw=Math.max(nmw,tgw)+12*dpr,th=fs+8*dpr+(tag?12*dpr:0),lx=c[0]+s+5*dpr,ly=c[1]-th/2;
    if(boxes.some(b=>lx<b[2]&&lx+tw>b[0]&&ly<b[3]&&ly+th>b[1]))continue;boxes.push([lx,ly,lx+tw,ly+th]);BOARD.lbl.push({pid:p.id,x0:(c[0]-s-4*dpr)/dpr,y0:ly/dpr,x1:(lx+tw)/dpr,y1:(ly+th)/dpr});
    g.fillStyle="rgba(8,18,28,.86)";g.fillRect(lx,ly,tw,th);g.strokeStyle=tag?(hb&&hb.rent?"rgba(170,182,194,.85)":"rgba(255,179,71,.8)"):"rgba(160,180,198,.28)";g.lineWidth=1*dpr;g.strokeRect(lx+.5*dpr,ly+.5*dpr,tw-dpr,th-dpr);g.fillStyle="#c9d4de";g.textAlign="left";g.textBaseline="middle";g.fillText(p.name,lx+6*dpr,ly+(fs+8*dpr)/2+.5*dpr);if(icl.length||pml){g.font=`${big?700:600} ${fs}px "Inter",sans-serif`;const ix=lx+6*dpr+mtW(g,p.name)+5*dpr;if(icl.length)drawIcons(g,icl,ix,ly+(fs+8*dpr)/2,isz,UI.lf&&LF_SET[UI.lf]?"#ffd28a":"#9fb4c6");if(pml){ICP.mailbox=ICP.mailbox||new Path2D("M3 5h18v14H3z M3 7l9 6 9-6");drawIcons(g,["mailbox"],ix+icl.length*(isz+2*dpr),ly+(fs+8*dpr)/2,isz,"rgb(246,196,32)")}}
    if(tag){g.font=`700 ${9*dpr}px "JetBrains Mono",monospace`;g.fillStyle=hb&&hb.rent?"#b8c2cc":"#ffb347";g.fillText(tag,lx+6*dpr,ly+fs+8*dpr+3*dpr)}g.textBaseline="alphabetic"}
  g.globalAlpha=1;
}
function boardHQ(){const x=-WX/2+8+2*1+1,z=-WZ/2+2*1+1;return[(x+WX/2)/WX*MW,(z+WZ/2)/WZ*MH]}
function drawBoard(g,dpr){
  const P=(x,z)=>{const p=project(x,0,z);return p?[p.x*dpr,p.y*dpr]:null};
  const hx=WX/2,hz=WZ/2,W=g.canvas.width,H=g.canvas.height;
  // pixels per world unit near the view centre → which levels are legible
  const c0=P(Cam.tx,Cam.tz),c1=P(Cam.tx+1,Cam.tz);const ppu=c0&&c1?Math.hypot(c1[0]-c0[0],c1[1]-c0[1])/dpr:40;
  const lv=[{s:SECTOR,w:3.2,col:"rgba(28,40,52,.95)"},{s:SECTOR/3,w:1.7,col:"rgba(40,54,68,.8)"},{s:.5,w:1,col:"rgba(60,74,88,.55)"},{s:.125,w:.7,col:"rgba(80,94,108,.4)"}];
  g.lineCap="butt";
  const gk=["g0","g1","g3","g3"];
  // the highlighted level is drawn last, so coarser lines lying on top of it do not hide its lines
  const hk=["sector","quarter","","cell"].indexOf(UI.lf||"-"),ord=[3,2,1,0].filter(k=>k!==hk).concat(hk>=0?[hk]:[]);
  for(const k of ord){const L=lv[k],px=L.s*ppu,on=k===hk;if(px<(on?6:7))continue;const a=on?clamp((px-6)/8,0,1):clamp((px-7)/18,0,1);
    g.strokeStyle=on?"rgba(120,214,250,.95)":L.col;g.globalAlpha=a;g.lineWidth=(on?(k===3?1:1.8):L.w)*dpr*(k===0&&!on?1:clamp(.7+ppu/400,.7,1.4));g.beginPath();
    const vb=vbox(),n=vb?2:24;const seg=(x0,z0,x1,z1)=>{if(vb){if(x0===x1){if(x0<vb.x0||x0>vb.x1)return;z0=Math.max(z0,vb.z0);z1=Math.min(z1,vb.z1);if(z1<=z0)return}else{if(z0<vb.z0||z0>vb.z1)return;x0=Math.max(x0,vb.x0);x1=Math.min(x1,vb.x1);if(x1<=x0)return}}let pen=false;for(let q=0;q<=n;q++){const t=q/n,p=P(x0+(x1-x0)*t,z0+(z1-z0)*t);if(!p){pen=false;continue}pen?g.lineTo(...p):g.moveTo(...p);pen=true}};
    const st=L.s,skip=v=>!on&&k>0&&Math.abs(Math.round(v/lv[k-1].s)*lv[k-1].s-v)<1e-6;
    const nx=Math.floor(WX/st+1e-6),nz=Math.floor(WZ/st+1e-6);for(let i=0;i<=nx;i++){const x=-hx+i*st;if(skip(i*st))continue;seg(x,-hz,x,hz)}
    for(let i=0;i<=nz;i++){const z=-hz+i*st;if(skip(i*st))continue;seg(-hx,z,hx,z)}
    g.stroke();g.globalAlpha=1}
  g.textBaseline="alphabetic";
}

/* ---------- detailed road network ---------- */

/* ---------- spurs: make sure a road reaches the centre of every settlement ---------- */

/* ---------- villages: many small settlements, visible on deep zoom ---------- */

/* ---------- start ---------- */
async function startCompany(){return startBoard()}
function coInit(hq){
  const nm=pick(CO_NAMES_A)+pick(CO_NAMES_B);
  Object.assign(CO,{name:nm,col:"#ffb347",hq,cash:[8000,3500,2000][G.diff??1],rating:3,tier:1,veh:[],jobs:[],board:[],hubs:[],staff:{driver:1,rail:0,sailor:0,pilot:0},founder:0,wageLv:1,morale:66,
    mgr:{},cand:{},loans:[],ins:false,fuel:1,maint:1,pir:[],conf:[],comp:[],hist:{cash:[],rev:[],rat:[],prof:[]},m:coZero(),lm:null,uid:1,auto:false,ms:[],deliv:0,cdel:0,xp:0,tons:0,mcd:0,
    tenders:[],flags:{},neg:0,cls:[],wx:[],clV:1,pool:{driver:3,rail:0,sailor:0,pilot:0},strike:0,dayLocal:0,buyAt:null,last:[]});
  CO.logo=coLogo(nm,CO.col);
}
function coSetHQ(pid){document.body.classList.remove("hqpick");setTimeout(()=>coSandbox(true),0);
  const p=PL[pid];CO.hq=pid;G.me=p.cid;CO.hubs=[{pid,lvl:1,share:.05,mk:0}];CO.veh=[{id:CO.uid++,t:"ltruck",loc:pid,st:"idle",cond:100,km:0}];
  // piracy hot spots and competitors
  const R2=mulberry((SEED^0x7f4a)>>>0);
  CO.comp=COMP_N.map((n,i)=>({n,rev:Math.exp(Math.log(1.5e6)+(i/(COMP_N.length-1)*.8+R2()*.2)*Math.log(60)),g:.004+R2()*.01}));
  for(let i=0;i<40&&CO.board.length<Math.min(coBoardMax(),10);i++){const k=coGen();if(k)CO.board.push(k)}
  CO.ms=[];G.news=[];coNews("good","truck",`${CO.name}: перша вантажна машина виїхала з гаража в місті ${p.name}`);
  buildHUD();ovBuilt=true;coWho();
  for(let i=0;i<6;i++)coMgrCand();
  updateHUD();updateLegend();applyMapColors();
  if(!G.board){Cam.tdist=4.2;Cam.ttx=p.x;Cam.ttz=p.z+.35}
  queueModal({icon:"truck",tone:"good",eyebrow:CO.name,title:"Компанія зареєстрована",body:`<p>Штаб у місті <b>${esc(p.name)}</b> (${esc(G.C[p.cid].name)}). Ви — керівник: у компанії одна вантажна машина до 5 т і один найнятий водій.</p>
   <div class="hint">${ic("truck")}<div><b>Рейси по країні.</b> Беріть замовлення між містами своєї країни у вікні «Замовлення і рейси». Поки машина стоїть у хабі, вона розвозить замовлення по місту.</div></div>
   <div class="hint">${ic("users")}<div><b>Ростіть.</b> Купуйте фургони й вантажні машини (вікно «Автопарк»), наймайте водіїв («Персонал»), відкривайте хаби в інших містах країни.</div></div>
   <div class="hint">${ic("star")}<div><b>Рейтинг</b> росте від якісних доставок і відкриває ліцензії: вантажівки, рефрижератори й цистерни, кордони й негабарит, потяги, кораблі, літаки.</div></div>
   <div class="hint">${ic("alert")}<div><b>Нештатні випадки:</b> аварії, пошкоджені й викрадені вантажі, пірати, черги й огляди на митниці, страйки. Менеджери допомагають — але деякі крадуть.</div></div>`,choices:[{t:"До роботи",d:"Гра стартує на звичайній швидкості",f(){setSpeed(1);openWin("coHome")}}]});
}
function coWho(){{const wb=$("#whoBox");if(wb)wb.dataset.tip="<b>Ваша компанія</b>Натисніть, щоб показати штаб на мапі."}const ml_=$("#myLeader");if(ml_){ml_.style.cursor="pointer";ml_.onclick=e=>{e.stopPropagation();ACT.coFly(CO.hq)};ml_.title="Показати штаб на мапі"}document.querySelectorAll("#speed button").forEach((b,i)=>{if(i)b.dataset.tip=T(["","Звичайна швидкість","Швидко","Дуже швидко"][i],["","1 ігрова доба ≈ 2,5 хв. Рейс у сусіднє місто — кілька хвилин.","1 доба ≈ 30 с.","1 доба ≈ 5 с."][i])});const ml=$("#cMarket .lbl");if(ml){ml.textContent="Пальне, барель";$("#cMarket").dataset.tip=T("Ціна пального","Світова ціна барелю нафти. Від неї залежить вартість кожного рейсу. Стрибає при нафтових шоках, війнах і санкціях і поступово повертається до норми ≈ $80.")}
  const ct=$("#cTension"),cp=$("#cPop");if(ct){ct.querySelector(".lbl").textContent="Рейси в дорозі";ct.dataset.tip=T("Рейси в дорозі","Скільки вантажів зараз везе ваша техніка і скільки замовлень чекає на біржі. Клік відкриває вікно «Рейси в дорозі».");ct.style.cursor="pointer";ct.onclick=()=>openWin("coTrips")}
  if(cp){cp.querySelector(".lbl").textContent="Виручка за місяць";cp.dataset.tip=T("Виручка цього місяця","Гроші від доставок по країні, міжнародних перевезень і тендерів з 1-го числа. Поруч — зміна відносно минулого місяця за той самий час. Клік відкриває «Фінанси».");cp.style.cursor="pointer";cp.onclick=()=>openWin("coFin")}$("#myFlag").src=CO.logo;$("#myName").textContent=CO.name;$("#myLeader").textContent=`${LIC[CO.tier].n} · штаб: ${hqP().name}`;$("#whoBox").onclick=()=>openWin("coHome")}

/* ---------- daily simulation ---------- */
function coDay(){
  G.day++;const d=G.date;d.d++;const dim=[31,28,31,30,31,30,31,31,30,31,30,31][d.m];let nm=false;
  if(d.d>dim){d.d=1;d.m++;nm=true;if(d.m>11){d.m=0;d.y++}}
  updateMarketDaily();
  coSandbox();guard("Компанія · місто",coLocal);guard("Компанія · рейси",coJobsDay);guard("Компанія · обстановка",incDay);guard("Компанія · біржа",coBoardDay);guard("Компанія · диспетчер",coAuto);guard("Компанія · повернення",coReturns);
  guard("Компанія · ринок",bizPrices);guard("Компанія · ліцензії",bizDay);
  if(nm)guard("Компанія · місяць",coMonth);
  if(UI.win&&UI.win.startsWith("co"))CO.winDirty=true;
}
/* finance: deliveries inside one country vs. international */
const revKey=k=>PL[k.from]&&PL[k.to]&&PL[k.from].cid===PL[k.to].cid?"local":"contract";
function coLocal(){
  const free=coCrewFree();let drv=free.driver,rev=0,tot=0,want=0,cnt=0;
  const strike=CO.strike>G.day;
  for(const h of CO.hubs){const p=PL[h.pid],c=G.C[p.cid];
    const mk=Math.log10(1+(h.mk||0)/400)*.05;
    const target=clamp(.035+(CO.rating-3)*.035+h.lvl*.015+msk("cco")*.03+mk,.01,.5);
    h.share+=(target-h.share)*.015;
    const market=(p.pop*1000+400)*(.45+c.dev),w=market*h.share;
    let cap=0,n=0;h.ids=[];
    for(const v of CO.veh){if(v.loc!==p.id||v.st!=="idle")continue;const T=VT[v.t];if(!T.loc)continue;
      if(drv<(T.crew||1))continue;drv-=(T.crew||1);v.today=Math.round(T.loc*Math.sqrt(R())*(v.cond>35?1:.6));cap+=v.today;n++;h.ids.push(v.id)}
    const cm=(.72+CO.morale/220)*(1+msk("coo")*.08)*(strike?.1:1);cap*=cm;
    const served=Math.min(w,cap),fr_=cap>0?served/cap:0;for(const id of h.ids){const v=CO.veh.find(x=>x.id===id);if(v)v.done=Math.round(v.today*cm*fr_)}h.want=w;h.cap=cap;h.served=served;h.nloc=n;
    const price=4.2*priceK(p.cid)*(1+msk("cco")*.06);rev+=served*price;tot+=served;h.earn=(h.earn||0)+served*price;want+=w;cnt+=n;
  }
  CO.cash+=rev;CO.m.local+=rev;CO.deliv+=tot;CO.dayLocal=tot;
  // wear & upkeep
  let up=0;for(const v of CO.veh){const T=VT[v.t];up+=T.up*[.8,1,1.35][CO.maint];if(T.loc&&v.st==="idle")v.cond=Math.max(0,v.cond-.035*[1.5,1,.6][CO.maint])}
  CO.cash-=up;CO.m.upkeep+=up;
  // service quality → rating
  if(tot>0){const avgC=CO.veh.length?CO.veh.reduce((a,v)=>a+v.cond,0)/CO.veh.length:100;
    const s=clamp(2.7+1.4*CO.morale/100+msk("coo")*.6+(avgC-80)/80+(strike?-1.5:0),1,5);
    const w=Math.min(.012,tot*.00015);CO.rating=clamp(CO.rating+(s-CO.rating)*w,1,5)}
  // morale
  const over=CO.hubs.reduce((a,h)=>a+(h.want>h.cap*1.6?1:0),0);
  const mt=clamp(52+(CO.wageLv-1)*130+msk("hro")*16-over*3-(CO.cash<0?12:0)+(CO.founder?6:0),5,98);CO.morale+=(mt-CO.morale)*.04;
  // local accidents
  for(const v of CO.veh){const T=VT[v.t];if(!T.loc||v.loc==null||v.st!=="idle")continue;
    if(chance(DFK()*.0009*(1-.45*msk("coo"))*(1.35-CO.morale/100)*(1.2-v.cond/250))){
      const cost=Math.round(rnd(800,4500)*priceK(PL[v.loc].cid));CO.cash-=cost;CO.m.claims+=cost;v.cond=Math.max(0,v.cond-rnd(15,40));CO.rating=clamp(CO.rating-.01,1,5);
      coNews("bad","alert",`${T.n} ${CO.name} потрапив у ДТП у місті ${PL[v.loc].name}: збитки ${fmtUSD(cost)}`);toast("bad","ДТП у місті",`${T.n} · ${PL[v.loc].name} · ${fmtUSD(cost)}`)}}
}

/* ---------- contracts board ---------- */
function coBoardMax(){if(SET.sandbox&&CO.sbFilled)return Math.min(80,20+CO.hubs.length);return CO.tier>=1?8+CO.tier*2+Math.round(msk("cco")*4)+CO.hubs.reduce((a,h)=>a+h.lvl-1,0):0}
function coBoardDay(){
  CO.board=CO.board.filter(k=>k.exp>G.day);
  const mx=coBoardMax();for(let i=0;i<(SET.sandbox&&CO.sbFilled?25:Math.max(3,Math.ceil(mx/5)))&&CO.board.length<mx;i++){if(!chance(.65))continue;for(let a=0;a<5;a++){const k=coGen();if(k){CO.board.push(k);break}}}
}
/* ---------- orders: an enterprise ships from its city; long hauls become chains of legs ---------- */
const CH_RATE={road:150,rail:22,sea:9,air:260},CH_BASE={road:600,rail:5000,sea:20000,air:15000},CH_SPD={road:1.05,rail:1.6,sea:1.5,air:16};
const nodeOK=(m,p)=>m==="road"?true:m==="rail"?!!p.rail:m==="sea"?p.port!=null:!!p.air;
const chCost=(m,len,t)=>CH_RATE[m]*len*Math.pow(t,.85)+CH_BASE[m]*.15;
function roadLim(){const own=CO.veh.filter(v=>VT[v.t].mode==="road").map(v=>VT[v.t].cap),c=own.length?own:Object.values(VT).filter(T=>T.mode==="road"&&T.tier<=CO.tier).map(T=>T.cap);return c.length?Math.max(...c)*8:0} /* a road leg takes at most ~8 of your biggest trucks; heavier loads go by rail or the partner brings them */
/* transfer points of a mode near p on its land (p itself first when it has one) */
function chNear(p,m,n){return PL.filter(q=>q.land===p.land&&nodeOK(m,q)&&!inConf(q.cid)&&(CO.tier>=3||q.cid===p.cid)).map(q=>({q,d:Math.hypot(q.x-p.x,q.z-p.z)})).sort((a,b)=>a.d-b.d).slice(0,n||2).map(o=>o.q)}
/* the cheapest way between two cities of one land: by road, or by road + rail + road when rail is unlocked and pays off */
function chLand(X,Y,tons,noRail){if(X.id===Y.id)return[];const lim=roadLim();let best=null,bc=1e18;
  if(tons<=lim){const r=coRoute("road",X.id,Y.id);if(r){bc=chCost("road",r.len,tons);best=[{a:X.id,b:Y.id,m:"road",len:r.len}]}}
  if(!noRail&&CO.tier>=4){for(const S1 of chNear(X,"rail",2))for(const S2 of chNear(Y,"rail",2)){if(S1.id===S2.id)continue;const rr=coRoute("rail",S1.id,S2.id);if(!rr)continue;
      const L=[];let c=chCost("rail",rr.len,tons),ok=true;
      for(const [u,v] of [[X,S1],[S2,Y]]){if(u.id===v.id)continue;if(tons>lim){ok=false;break}const r=coRoute("road",u.id,v.id);if(!r){ok=false;break}c+=chCost("road",r.len,tons);L.push({a:u.id,b:v.id,m:"road",len:r.len})}
      if(!ok)continue;const legs=[...(X.id!==S1.id?[L[0]]:[]),{a:S1.id,b:S2.id,m:"rail",len:rr.len},...(S2.id!==Y.id?[L[L.length-1]]:[])];if(c<bc){bc=c;best=legs}}}
  return best}
function coGen(){
  const modes=[];if(CO.tier>=1)modes.push("road","road","road");if(CO.tier>=4)modes.push("rail","rail");if(CO.tier>=5)modes.push("sea","sea");if(CO.tier>=6)modes.push("air","air");
  const mode=pick(modes),aidOK=CO.tier>=3;
  // the shipper: an enterprise in a city near your network (bigger cities and more firms ship more)
  const HP=CO.hubs.map(h=>PL[h.pid]),lands=new Set(HP.map(p=>p.land)),Dref=G.board?2.6:5,onB=new Map();for(const q of CO.board){onB.set(q.from,(onB.get(q.from)||0)+1);onB.set(q.from+":"+q.to,(onB.get(q.from+":"+q.to)||0)+1)}
  const hubC=new Set(HP.map(p=>p.cid)),ownC=new Set(CO.hubs.filter(h=>!h.rent).map(h=>PL[h.pid].cid));const pool=PL.filter(p=>lands.has(p.land)&&coScope(p)&&!inConf(p.cid)&&hubC.has(p.cid));if(!pool.length)return null;
  let tw=0;const waitAt=new Set(CO.veh.filter(v=>v.st==="idle"&&v.idle0!=null&&!hubAt(v.loc)).map(v=>v.loc));const ws=pool.map(p=>{let d=1e9,lv=1;for(const h of CO.hubs){const q=PL[h.pid],dd=Math.hypot(q.x-p.x,q.z-p.z);if(dd<d){d=dd;lv=h.lvl}}const w=Math.pow(firmsOf(p.id).length,1.25)*(Math.sqrt(p.pop)+.15)*HUB_ORD[lv]/(1+(d/Dref)*(d/Dref))*(waitAt.has(p.id)?3:1)/(1+1.5*(onB.get(p.id)||0))*(ownC.has(p.cid)?1:.3);tw+=w;return w}); /* a rented hub abroad brings far less freight than your own network */ /* shippers notice your truck waiting in town */ /* bigger hubs attract more freight around them */
  /* capitals ship about half of the freight, the other cities of the country the rest (their weight is softened so one big city does not take it all) */
  {const hasOwn=pool.some(p=>ownC.has(p.cid)),hasRent=pool.some(p=>!ownC.has(p.cid)),wantOwn=!hasRent||hasOwn&&chance(.78),inSet=p=>ownC.has(p.cid)===wantOwn||!hasOwn; /* ~¾ of the freight from your own network, ~¼ from rented hubs abroad */
    const capI=pool.map((p,i)=>p.type==="cap"&&inSet(p)?i:-1).filter(i=>i>=0),oth=pool.map((p,i)=>p.type!=="cap"&&inSet(p)?i:-1).filter(i=>i>=0);
    const useCap=capI.length&&(!oth.length||chance(.5)),idx=useCap?capI:oth;let t=0;const w=idx.map(i=>{const x=useCap?ws[i]:Math.sqrt(ws[i])*(ownC.has(pool[i].cid)?1:.3);t+=x;return x});
    if(t>0){let r=R()*t;for(let q=0;q<idx.length;q++){r-=w[q];if(r<=0){ws.chosen=idx[q];break}}}}
  let r=R()*tw,A=pool[0];if(ws.chosen!=null)A=pool[ws.chosen];else for(let i=0;i<pool.length;i++){r-=ws[i];if(r<=0){A=pool[i];break}}
  // cargo and tonnage by the main mode
  const caps=Object.values(VT).filter(T=>T.mode===mode&&T.tier<=CO.tier).map(T=>T.cap);if(!caps.length)return null;const capMax=Math.max(...caps);
  const own=CO.veh.filter(v=>VT[v.t].mode==="road").reduce((a,v)=>a+VT[v.t].cap,0),rng_={road:[.3,Math.max(1.5,Math.min(capMax*2.4,own*1.15))],rail:[80,CO.tier>=7?5000:2400],sea:[300,CO.tier>=7?40000:16000],air:[1,CO.tier>=7?400:110]}[mode];
  // the main leg and the consignee
  let main=null,B=null;
  const far=(p,q,k)=>Math.hypot(p.x-q.x,p.z-q.z)*CO_DU>k;
  if(mode==="road"){let c=PL.filter(p=>p.id!==A.id&&p.land===A.land&&coScope(p)&&(CO.tier>=3||p.cid===A.cid)&&(!inConf(p.cid)||aidOK));if(!c.length)return null;{const dom=c.filter(p=>p.cid===A.cid);if(dom.length&&chance(.5))c=dom} /* about half of the road freight stays inside the country */
    const gr_=typeof coGrade==="function"?coGrade():9;let t2=0;const w2=c.map(p=>{let w=(Math.sqrt(p.pop)+.1)/(1+3*(onB.get(A.id+":"+p.id)||0))*(p.cid===A.cid?4:1);if(gr_<2){const d=Math.hypot(p.x-A.x,p.z-A.z);w/=1+d*d/4}t2+=w;return w});let r2=R()*t2;B=c[0];for(let i=0;i<c.length;i++){r2-=w2[i];if(r2<=0){B=c[i];break}}}
  else{const P1=chNear(A,mode,1)[0];if(!P1)return null;
    const c=PL.filter(p=>p.id!==P1.id&&nodeOK(mode,p)&&coScope(p)&&(!inConf(p.cid)||aidOK)&&(mode==="rail"?p.land===P1.land&&(CO.tier>=3||p.cid===P1.cid)&&far(p,P1,G.board?.5:2):mode==="sea"?(p.land!==P1.land||far(p,P1,G.board?.9:4)):far(p,P1,G.board?.6:2.5)));
    if(!c.length)return null;const P2=pick(c),rr=coRoute(mode,P1.id,P2.id);if(!rr)return null;main={a:P1.id,b:P2.id,m:mode,len:rr.len};
    // the consignee: the port/station/airport city itself or a city nearby on that land
    const near=PL.filter(p=>p.land===P2.land&&coScope(p)&&(!inConf(p.cid)||aidOK)&&Math.hypot(p.x-P2.x,p.z-P2.z)<(G.board?1.2:4)).sort((a,b)=>Math.hypot(a.x-P2.x,a.z-P2.z)-Math.hypot(b.x-P2.x,b.z-P2.z)).slice(0,6);
    B=chance(.35)?P2:pick(near.length?near:[P2])}
  const aid=(inConf(B.cid)||inConf(A.cid))&&aidOK;
  const cgs=CARGO.filter(c=>(aid?c.aid:!c.aid)&&c.t[1]>=rng_[0]&&c.t[0]<=rng_[1]&&(mode!=="air"||c.val>=2500||c.aid));if(!cgs.length)return null;
  const cg=pick(cgs);const lo=Math.max(cg.t[0],rng_[0]),hi=Math.min(cg.t[1],rng_[1]);
  let tons=lo*Math.pow(hi/lo,Math.pow(R(),1.6));if(mode==="road"){const ov=CO.veh.filter(v=>VT[v.t].mode==="road").reduce((a,v)=>a+(VT[v.t].vol||0),0);if(ov>0)tons=Math.max(.3,Math.min(tons,ov*1.1/(cg.v||3)))}tons=tons<5?+tons.toFixed(1):Math.round(tons);
  // legs: feeders by road (or rail when it is cheaper) to the port/station/airport and from it; partners sometimes do a part themselves
  let legs,pIn=null,pOut=null;
  if(mode==="road"){legs=chLand(A,B,tons,true);if(!legs||!legs.length)return null;if(legs[0].len<(G.board?.03:.35))return null}
  else{const P1=PL[main.a],P2=PL[main.b];let pre=chLand(A,P1,tons,mode==="rail"),post=chLand(P2,B,tons,mode==="rail");
    const hubOn=new Set(HP.map(p=>p.land));
    if(pre==null||pre.length&&chance(.3)){if(pre&&pre.length||A.id!==P1.id)pIn=P1.id;pre=[]}
    if(post==null||post.length&&(chance(.25)||!hubOn.has(P2.land))){if(B.id!==P2.id)pOut=P2.id;post=[]}
    legs=[...pre,main,...post]}
  const from=legs[0].a,to=legs[legs.length-1].b,F=PL[from],T_=PL[to];
  const ml=legs.reduce((a,L)=>CH_RATE[L.m]*L.len>CH_RATE[a.m]*a.len?L:a,legs[0]);
  const len=legs.reduce((a,L)=>a+L.len,0),border=F.cid!==T_.cid;
  const travel=legs.reduce((a,L)=>a+L.len/(CH_SPD[L.m]*spdK())+HAND[L.m]*handK()*2,0)+(border?1*handK():0);
  const urg=R();const dlDays=Math.max(G.board?.6:1.5,travel*(2.3-urg*.9)+(legs.some(L=>L.m==="sea")?3:G.board?.4:1.2));
  const seaL=legs.find(L=>L.m==="sea"),risk=clamp((coRisk(F.cid)+coRisk(T_.cid))/2*(cg.theft||.7)+(seaL&&coPirOn(coRoute("sea",seaL.a,seaL.b).p)?.5:0),0,2);
  const minR=chance(.22)?clamp(Math.round((CO.rating+rnd(-.4,.5))*10)/10,2.5,4.9):0;
  const gr=typeof coGrade==="function"?coGrade():0,prem=gr>=2&&chance(.15),vip=!prem&&gr>=3&&chance(.12);
  const pk=(priceK(F.cid)+priceK(T_.cid))/2;
  const pay=Math.round(legs.reduce((a,L)=>a+CH_BASE[L.m]*(L===ml?1:.25)+CH_RATE[L.m]*L.len*Math.pow(tons,.85),0)*cg.k*pk*(1+urg*.45)*(1+risk*.18)*(.8+CO.rating*.07)*(1+msk("cco")*.12)*(minR?1.3:1)*(aid?1.4:1)*rnd(.9,1.1)*(1+gr*.03)*(prem?rnd(1.4,1.6):1)*(vip?1.35:1));
  const dlK=prem?.65:gr<2?1.25:1;
  const k={id:CO.uid++,from,to,cg:cg.id,tons,pay,dlDays:+(dlDays*dlK).toFixed(1),mode:ml.m,risk,minR,len,exp:G.day+(prem?rint(2,4):rint(5,12))};if(prem)k.prem=1;if(vip)k.vip=1;
  if(legs.length>1)k.legs=legs.map(L=>({a:L.a,b:L.b,m:L.m}));
  if(pIn!=null){k.pIn=pIn;k.src=A.id}if(pOut!=null){k.pOut=pOut;k.dst=B.id}
  return k;
}
function coPirOn(p){if(!CO.pir.length)return false;for(let i=0;i<p.length;i+=2)for(const z of CO.pir)if(Math.hypot(p[i]-z.x,p[i+1]-z.z)<z.r)return true;return false}
const isRetV=v=>v.st==="trip"&&VT[v.t].mode==="road"&&CO.jobs.some(x=>x.ret&&x.vids.includes(v.id));
function retPos(v){const j=CO.jobs.find(x=>x.ret&&x.vids.includes(v.id));if(!j)return null;return coPosAt(j,coJobState(j,coNow()-j.t0).s)}
function retLead(v,dest){const q=retPos(v);if(!q||!BOARD.bits)return null;const p=boardPath(nodeAt(q[0],q[1]),PL[dest].node);if(!p)return null;const a=[q[0],q[1],...p];let L=0;for(let i=2;i<a.length;i+=2)L+=Math.hypot(a[i]-a[i-2],a[i+1]-a[i-1]);return{p:new Float32Array(a),len:L*CO_DU}}
const vCid=v=>{if(v.st==="trip"){const q=retPos(v);if(q){const o=bOwn(q[0],q[1]);if(o>=0)return o}}return PL[v.loc]?PL[v.loc].cid:-1};
function coPlan1(k){
  const mode=k.mode,A=PL[k.from];
  if(k.minR&&CO.rating<k.minR)return{ok:false,why:`Замовник хоче рейтинг ${k.minR.toFixed(1)}+`};
  if(CO.strike>G.day)return{ok:false,why:"Страйк: водії не виходять на рейси"};
  {const nd=permNeed(CARGO_I[k.cg],mode).filter(x=>!permOK(x));if(nd.length)return{ok:false,why:`Потрібна ліцензія «${PERM_I[nd[0]].n}»`,perm:nd[0]}}
  {const w=specWhy(k,null);if(w)return{ok:false,why:w}}
  if(mode==="sea"||mode==="air"){for(const pid of [k.from,k.to]){const w=incPortCl(PL[pid],mode);if(w)return{ok:false,why:`${mode==="sea"?"Порт":"Аеропорт"} ${PL[pid].name} закрито: ${w.toLowerCase()}`}}}
  const main=coRoute(mode,k.from,k.to);if(!main)return{ok:false,why:BLK?"Маршрут перекрито: закритий кордон або негода":"Маршрут недоступний"};
  const free=coCrewFree();let best=null,why="Немає вільної техніки: "+MODE_N[mode].toLowerCase();
  for(const t in VT){const T=VT[t];if(T.mode!==mode)continue;{const w=specWhy(k,t);if(w){why=w;continue}}
    const idle=CO.veh.filter(v=>v.t===t&&(v.st==="idle"&&(hubAt(v.loc)||v.idle0!=null&&coNow()-v.idle0<1)||isRetV(v))&&(k._ctry==null||vCid(v)===k._ctry)&&!(k._ex&&k._ex.has(v.id))&&(k._veh==null||v.id===k._veh)&&(!v.resv||v.id===k._veh));if(!idle.length)continue;
    const n=Math.max(Math.ceil(k.tons/T.cap),T.vol?Math.ceil((k._vol!=null?k._vol:k.tons*((CARGO_I[k.cg]&&CARGO_I[k.cg].v)||3))/T.vol):1);if(k._one&&n>1){why=`Не вміщує: ${T.n.toLowerCase()} бере ${T.cap} т і ${T.vol} м³`;continue}if(n>14){why="Замало місткості: потрібно "+n+" × "+T.n.toLowerCase();continue}
    if(idle.length<n){why=`Потрібно ${n} × ${T.n.toLowerCase()}, вільних ${idle.length}`;continue}
    if(free[T.role]+Math.min(n,idle.filter(isRetV).length)*(T.crew||1)<(T.crew||1)*n){why=`Бракує персоналу: ${ROLE[T.role].n.toLowerCase()}`;continue}
    idle.sort((a,b)=>Math.hypot(PL[a.loc].x-A.x,PL[a.loc].z-A.z)-Math.hypot(PL[b.loc].x-A.x,PL[b.loc].z-A.z));
    const sel=[];let lead=0,leadR=null;for(const v of idle){const r=v.st==="trip"?retLead(v,k.from):coRoute(mode,v.loc,k.from);if(!r)continue;sel.push(v);if(!leadR||r.len>=lead){lead=r.len;leadR=r}if(sel.length===n)break}
    if(sel.length<n){why=BLK?"Техніку відрізано: закритий кордон або негода":"Техніка на іншому материку";continue}
    const border=PL[k.from].cid!==PL[k.to].cid;
    const cust=border?((mode==="road"||mode==="rail")?(G.board?cpWait(PL[k.to].cid,mode)*Math.max(1,Math.round(Math.hypot(PL[k.to].x-A.x,PL[k.to].z-A.z)/5)):.35+bur(PL[k.to].cid)/110):.3)*(1-(G.board?0:.6*msk("clo"))):0;
    const tl=lead/(T.spd*spdK()),tm=main.len/(T.spd*spdK()),hs=HAND[mode]*handK()*(handF(k.from)+handF(k.to))/2,tot=tl+hs+tm+cust+hs;
    const fuel=(lead+main.len)*T.fuel*CO.fuel*fuelK(mode)*n*(1-.06*msk("cto"))*(lead>0?1:1);
    const runc=(T.up*repK()*[.8,1,1.35][CO.maint]+ROLE[T.role].w*wageK(G.me)*CO.wageLv/30*(T.crew||1))*tot*n;
    const pk_=T.fit&&T.fit.includes(k.cg)?1.2:1,c={ok:true,t,n,vids:sel.map(v=>v.id),lead,leadR,main,tl,tm,hs,cust,tot,fuel,payK:pk_,profit:k.pay*pk_-fuel-runc,late:tot>k.dlDays};
    if(!best||(!c.late&&best.late)||(c.late===best.late&&c.profit>best.profit))best=c}
  return best||{ok:false,why};
}
/* transshipment at a hub that is not yours: its owner charges a tax (manual routes and the dispatcher's alike) */
function hubTax(k,pid,m){return hubAt(pid)?0:Math.round((k?k.pay:0)*.04+({road:120,rail:450,sea:1500,air:1100})[m]*priceK(PL[pid].cid))}
const hubTaxPay=ht=>{const x=(ht||[]).reduce((a,h)=>a+h.f,0);if(x){CO.cash-=x;CO.m.hubtax=(CO.m.hubtax||0)+x}return x};
function coPlan(k){if(!k.legs||k.legs.length<2)return coPlan1(k);
  if(k.minR&&CO.rating<k.minR)return{ok:false,why:`Замовник хоче рейтинг ${k.minR.toFixed(1)}+`};
  const ex=new Set(),sub=[],ht=[];let tot=0,fuel=0,cost=0,payK=1;
  for(let i=0;i<k.legs.length;i++){const L=k.legs[i],kk={...k,legs:null,from:L.a,to:L.b,mode:L.m,minR:0,pay:0,_ex:ex,len:coRoute(L.m,L.a,L.b)?.len||k.len};const P=coPlan1(kk);
    if(!P.ok)return{ok:false,why:`Ділянка ${i+1} (${MODE_N[L.m].toLowerCase()} ${PL[L.a].name} → ${PL[L.b].name}): ${P.why}`};
    P.vids.forEach(id=>ex.add(id));sub.push(P);tot+=P.tot;fuel+=P.fuel;cost+=-P.profit+(i?(250+k.tons*1.5)*priceK(PL[L.a].cid):0);if(i&&k.legs[i-1].m!==L.m){const x=hubTax(k,L.a,L.m);if(x){cost+=x;ht.push({pid:L.a,f:x})}}if(L.m===k.mode)payK=P.payK||1}
  const M=sub[k.legs.findIndex(L=>L.m===k.mode)]||sub[0];
  return{ok:true,chain:sub,ht,t:M.t,n:M.n,lead:sub[0].lead,tot,fuel,payK,profit:k.pay*payK-cost,late:tot>k.dlDays}}
function coDispatch(k,P,silent){
  if(!P||!P.ok)return false;
  if(P.chain){CO.board=CO.board.filter(x=>x!==k);hubTaxPay(P.ht);const plan=k.legs.map(L=>({a:L.a,b:L.b,m:L.m,r:null}));lpRunLeg(k,plan,0,G.day+k.dlDays);
    if(!silent)toast("good","Рейс відправлено",`${k.legs.map(L=>LP_N[L.m]).join(" → ")}: ${PL[k.from].name} → ${PL[k.to].name}`);if(UI.win==="coJobs"||UI.win==="coTrips")CO.winDirty=true;return true}
  CO.cash-=P.fuel;CO.m.fuel+=P.fuel;
  const path=[];const lp=P.leadR.p,mp=P.main.p;for(let i=0;i<lp.length;i++)path.push(lp[i]);for(let i=2;i<mp.length;i++)path.push(mp[i]);
  const j={id:k.id,k,mode:k.mode,t:P.t,n:P.n,vids:P.vids,payK:P.payK||1,p:new Float32Array(path),lead:P.lead,len:P.main.len,tl:P.tl,tm:P.tm,hs:P.hs,cust:P.cust,tot:P.tot,t0:coNow(),dl:G.day+k.dlDays,dmg:0,lost:false,hold:0,ev:[]};
  if(G.board&&(k.mode==="road"||k.mode==="rail")){const tot=j.lead+j.len,wl=(()=>{let L=0;for(let i=2;i<j.p.length;i+=2)L+=Math.hypot(j.p[i]-j.p[i-2],j.p[i+1]-j.p[i-1]);return L})(),eco=wl>0?tot/wl:CO_DU;
    j.stops=bCrossings(j.p,eco).map(c=>({s:c.s,a:c.a,b:c.b,x:c.x,z:c.z,w:cpWait(c.b,k.mode)}));if(j.stops.length){j.tot=j.tl+j.hs+j.tm+j.hs+j.stops.reduce((a,q)=>a+q.w,0);j.cust=0}}
  for(const v of CO.veh)if(P.vids.includes(v.id)&&v.st==="trip"){const rj=CO.jobs.find(x=>x.ret&&x.vids.includes(v.id));if(rj){CO.jobs=CO.jobs.filter(x=>x!==rj);if(CO_SEL===rj)CO_SEL=null}} /* a truck on its way home turns to the new order */
  for(const v of CO.veh)if(P.vids.includes(v.id)){v.st="trip";v.job=j.id;v.idle0=null}
  CO.jobs.push(j);CO.board=CO.board.filter(x=>x!==k);
  if(k.mode==="sea"&&PL[k.from].land!==PL[k.to].land)CO.flags.ocean=1;
  const A=PL[k.from],B=PL[k.to],cg=CARGO_I[k.cg];
  if(!silent)toast("good","Рейс відправлено",`${VT[P.t].n}${P.n>1?" ×"+P.n:""}: ${A.name} → ${B.name}`);
  if(UI.win==="coJobs"||UI.win==="coTrips")CO.winDirty=true;return true;
}
function coAuto(){
  if(!CO.auto||!CO.mgr.cto||CO.strike>G.day)return;let n=0;
  const lim=SET.sandbox&&CO.sbFilled?40:4,sk=msk("cto");for(const k of CO.board.slice().sort((a,b)=>b.pay-a.pay)){if(n>=lim)break;const P=coPlan(k);
    const guess=P.profit*(1+(R()-.5)*(1-sk)*.9); /* a weak dispatcher misjudges orders */
    if(P.ok&&(lim>4||!P.late&&guess>k.pay*.15)){const extra=Math.round(P.fuel*(1-sk)*.45);CO.cash-=extra;CO.m.fuel+=extra; /* and plans longer, costlier routes */
      k.how="mgr";coDispatch(k,P,true);n++}}
  if(n)coNews("","cpu",`Диспетчерська ${CO.name} відправила ${n} ${n===1?"рейс":"рейси"}`);
}

/* ---------- trips ---------- */
function coReturns(){for(const v of CO.veh){const T=VT[v.t];if(v.st!=="idle"||T.mode==="local"){v.idle0=null;continue}
    if(hubAt(v.loc)){v.idle0=null;continue}if(v.idle0==null){v.idle0=coNow();continue}if(coNow()-v.idle0<1)continue; /* a day in the unloading city waiting for a new order */
    let best=null,bl=1e9;for(const h of CO.hubs){if(!modeOK(T.mode,PL[h.pid])||hubVehN(h.pid)>=hubVehCap(h))continue;const r=coRoute(T.mode,v.loc,h.pid);if(r&&r.len<bl){bl=r.len;best={h,r}}}if(!best){v.idle0=coNow()+30;continue}
    const fuel=best.r.len*T.fuel*CO.fuel*fuelK(T.mode);CO.cash-=fuel;CO.m.fuel+=fuel;const tm=best.r.len/(T.spd*spdK());
    const j={id:CO.uid++,ret:true,k:{id:0,from:v.loc,to:best.h.pid,cg:"parcel",tons:0,pay:0,dlDays:1e3,mode:T.mode,risk:0},mode:T.mode,t:v.t,n:1,vids:[v.id],p:best.r.p,lead:0,len:best.r.len,tl:0,tm,hs:0,cust:0,tot:tm,t0:coNow(),dl:G.day+1e3,dmg:0,lost:false,hold:0,ev:[]};
    v.st="trip";v.job=j.id;v.idle0=null;CO.jobs.push(j)}}
/* checkpoints: road/rail crossings between countries; vehicles stop and wait there */
function bCrossings(pts,eco){ // border crossings of a road: the exact point where it passes from one state's land into another's
  const out=[],step=CST*.12;let s=0,prev=-1,px=pts[0],pz=pts[1],ps=0;
  for(let i=2;i<pts.length;i+=2){const x0=pts[i-2],z0=pts[i-1],x1=pts[i],z1=pts[i+1],L=Math.hypot(x1-x0,z1-z0);if(!L)continue;const n=Math.max(1,Math.ceil(L/step));
    for(let k=(i===2?0:1);k<=n;k++){const t=k/n,x=x0+(x1-x0)*t,z=z0+(z1-z0)*t,o=bOwn(x,z);
      if(o>=0){if(prev>=0&&o!==prev){let ax=px,az=pz,bx=x,bz=z,as=ps,bs=s+L*t;for(let q=0;q<14;q++){const mx=(ax+bx)/2,mz=(az+bz)/2,ms=(as+bs)/2,m=bOwn(mx,mz);if(m===prev){ax=mx;az=mz;as=ms}else{bx=mx;bz=mz;bs=ms}}
          const ws=(as+bs)/2;if(!out.length||ws-out[out.length-1].ws>.12)out.push({ws,s:ws*eco,x:(ax+bx)/2,z:(az+bz)/2,a:prev,b:o})}
        prev=o;px=x;pz=z;ps=s+L*t}}
    s+=L}
  // a road that only grazes the border (in and straight back out) has no checkpoint
  for(let i=1;i<out.length;i++)if(out[i].a===out[i-1].b&&out[i].b===out[i-1].a&&out[i].ws-out[i-1].ws<.3){out.splice(i-1,2);i=Math.max(0,i-2)}
  return out}
function boardCheckpoints(){const seen=[],cps=[];for(const h of LOG.hw.concat(LOG.rail.map(r=>({p:r.p,rail:1})))){for(const c of bCrossings(h.p,1)){if(seen.some(q=>Math.hypot(q.x-c.x,q.z-c.z)<CST*.3))continue;seen.push(c);cps.push({x:c.x,z:c.z,a:c.a,b:c.b,rail:!!h.rail})}}BOARD.cps=cps}
function cpWait(cid,mode){return((mode==="rail"?.25:.35)+bur(cid)/110)*(1-.6*msk("clo"))*(G.board?.45:1)}
function driveAt(j,e,s0,s1,T){const st=(j.stops||[]).filter(q=>q.s>=s0&&q.s<s1);if(!st.length)return{s:s0+(T>0?e/T:1)*(s1-s0)};const v=T>0?(s1-s0)/T:1e9;let pos=s0;
  for(const q of st){const t=(q.s-pos)/v;if(e<t)return{s:pos+e*v};e-=t;pos=q.s;if(e<q.w)return{s:pos,wait:q};e-=q.w}return{s:Math.min(s1,pos+e*v)}}
const segW=(j,s0,s1)=>(j.stops||[]).filter(q=>q.s>=s0&&q.s<s1).reduce((a,q)=>a+q.w,0);
function coJobState(j,e){let inc=null;
  if(j.pz&&j.pz.length){let sub=0;for(const p of j.pz){if(e>=p.e+p.w)sub+=p.w;else if(e>=p.e){inc=p;sub+=e-p.e;break}else break}e-=sub}
  let drg=null;if(j.drag)for(const d of j.drag){if(e>d.e0){if(e<d.e1)drg=d;e-=(Math.min(e,d.e1)-d.e0)*(1-d.f)}}
  const st=coJobState0(j,e);if(inc){st.ph=inc.ph;st.inc=inc}else if(drg&&st.seg>=0)st.ph=drg.ph;else if(j.gps&&coNow()<j.gps.until)st.ph="Втрачено сигнал GPS: остання відома позиція";else if(j.back&&st.seg>=0)st.ph="Везе вантаж назад відправнику";return st}
function coJobState0(j,e){const h0=j.cont?0:j.hs;if(j.stops&&j.stops.length&&!j.ret){const tl=j.tl+segW(j,0,j.lead),tm=j.tm+segW(j,j.lead,j.lead+j.len+1e-9);
    if(e<tl){const d=driveAt(j,e,0,j.lead,j.tl);return{s:d.s,w:d.wait,seg:d.wait?-1:0,f:j.lead>0?d.s/j.lead:1,ph:d.wait?`Пропускний пункт ${G.C[d.wait.a].name} → ${G.C[d.wait.b].name}: очікування`:"Порожній перегін до відвантаження"}}
    e-=tl;if(e<h0)return{s:j.lead,seg:-1,ph:"Завантаження"};
    e-=h0;if(e<tm){const d=driveAt(j,e,j.lead,j.lead+j.len+1e-9,j.tm);return{s:d.s,w:d.wait,seg:d.wait?-1:1,f:(d.s-j.lead)/(j.len||1),ph:d.wait?`Пропускний пункт ${G.C[d.wait.a].name} → ${G.C[d.wait.b].name}: очікування`:j.hold>0?"Захоплено":"У дорозі з вантажем"}}
    return{s:j.lead+j.len,seg:-1,ph:"Розвантаження"}}
  if(j.ret)return{s:clamp(e/j.tm,0,1)*j.len,seg:1,f:clamp(e/j.tm,0,1),ph:"Повертається в хаб без вантажу"};
  if(e<j.tl)return{s:j.tl>0?e/j.tl*j.lead:0,seg:0,f:j.tl>0?e/j.tl:1,ph:"Порожній перегін до відвантаження"};
  e-=j.tl;if(e<h0)return{s:j.lead,seg:-1,ph:"Завантаження"};
  e-=h0;if(e<j.tm)return{s:j.lead+e/j.tm*j.len,seg:1,f:e/j.tm,ph:j.hold>0?"Захоплено":"У дорозі з вантажем"};
  e-=j.tm;if(e<j.cust)return{s:j.lead+j.len,seg:-1,ph:"Митне оформлення"};
  return{s:j.lead+j.len,seg:-1,ph:"Розвантаження"};
}
function vsDamage(vs,x){vs.forEach(v=>v.cond=Math.max(0,v.cond-x))}
/* company experience: earned by deliveries; a route planned by hand teaches far more than one planned by the dispatcher */
function coXP(j,k,late){const nl=j.lp?j.lp.plan.length:1,mgr=k.how==="mgr";let x=(10+6*(nl-1)+4*Math.log2(1+k.pay/2000))*(late>0?.5:1)*(j.dmg>.05?.6:1);if(mgr)x*=.08;return Math.max(mgr?0:1,Math.round(x))}
function coComplete(j){
  if(j.ret){CO.jobs=CO.jobs.filter(x=>x!==j);for(const v of CO.veh)if(j.vids.includes(v.id)){v.st="idle";v.job=null;v.loc=j.k.to;v.km+=j.len*KM;v.idle0=null}if(CO_SEL===j){CO_SEL=null;$("#ucard").hidden=true}return}
  if(j.back||j.cx0){CO.jobs=CO.jobs.filter(x=>x!==j);const at=j.back?j.k.from:j.k.from;for(const v of CO.veh)if(j.vids.includes(v.id)){v.st="idle";v.job=null;v.loc=at;v.idle0=hubAt(at)?null:coNow();v.km+=(j.len||0)*KM}
    if(j.back){coNews("warn",MODE_IC[j.mode],`${CO.name}: вантаж «${CARGO_I[j.k.cg].n.toLowerCase()}» повернено відправнику в ${PL[at].name}`);CO.last.unshift({d:{...G.date},from:j.k.from,to:j.k.to,cg:j.k.cg,pay:j.comp||0,tone:"warn",mode:j.mode});if(CO.last.length>30)CO.last.pop()}
    if(CO_SEL===j){CO_SEL=null;$("#ucard").hidden=true}return}
  CO.jobs=CO.jobs.filter(x=>x!==j);const k=j.k,cg=CARGO_I[k.cg],T=VT[j.t],B=PL[k.to];
  const late=Math.max(0,G.day-j.dl);let pay=k.pay*(j.payK||1);if(late>0)pay*=Math.max(.35,1-late*.12);
  const value=k.tons*cg.val;let claim=0;
  if(j.lost){pay=0;claim=value*.6}else if(j.dmg>0){claim=Math.min(value*Math.min(1,j.dmg)*.8,k.pay*3+1500);pay*=1-Math.min(.8,j.dmg);if(j.dmg>.08){CO.rating=clamp(CO.rating-Math.min(.3,j.dmg*.6),1,5);toast("bad","Штраф за пошкоджений вантаж",`${cg.n} · ${fmtUSD(claim)} · рейтинг −${Math.min(.3,j.dmg*.6).toFixed(2)}`)}}
  const covered=CO.ins?claim*.8:0;
  CO.cash+=pay-claim+covered;CO.m[revKey(k)]+=pay;CO.m.claims+=claim-covered;
  const s=j.lost?1:j.dmg>.3?1.6:late>2?2:late>0?3.2:j.dmg>0?3.8:5;
  const w=Math.min(.05,.01+Math.log10(1+k.pay)*.005);CO.rating=clamp(CO.rating+(s-CO.rating)*w,1,5);
  for(const v of CO.veh)if(j.vids.includes(v.id)){v.st="idle";v.job=null;v.loc=k.to;v.idle0=hubAt(k.to)?null:coNow();v.km+=(j.lead+j.len)*KM;v.cond=Math.max(0,v.cond-(j.lead+j.len)*{road:1.6,rail:.5,sea:.25,air:.12}[j.mode]*[1.4,1,.65][CO.maint])}
  if(!j.lost){CO.cdel++;CO.deliv++;CO.tons+=k.tons;const xp=coXP(j,k,late);CO.xp=(CO.xp||0)+xp;j.xp=xp}
  const tone=j.lost?"bad":late>0||j.dmg>.05?"warn":"good";
  const txt=j.lost?`вантаж втрачено, претензія ${fmtUSD(claim-covered)}`:`${fmtUSD(pay,true)}${late>0?`, запізнення ${late.toFixed(1)} дн.`:" вчасно"}${j.dmg>.05?`, пошкоджено ${(j.dmg*100).toFixed(0)}%`:""}${j.xp?`, +${j.xp} досвіду`:""}`;
  coNews(tone,MODE_IC[j.mode],`${CO.name}: ${cg.n.toLowerCase()} доставлено в ${B.name} — ${txt}`);
  CO.last.unshift({d:{...G.date},from:k.from,to:k.to,cg:k.cg,pay:pay-claim+covered,tone,mode:j.mode});if(CO.last.length>30)CO.last.pop();
  if(CO_SEL===j){CO_SEL=null;$("#ucard").hidden=true}
}

/* ---------- per-frame: finish trips mid-day, show the clock ---------- */
function coChipTags(){if(!G.board||!CITY_EL.length)return;for(const c of CITY_EL){if(!c.cap)continue;const pl=PL.find(q=>q.type==="cap"&&q.cid===c.cid);const h=pl&&hubAt(pl.id);const cb=c.el.querySelector(".cb");if(!cb)continue;let t=cb.querySelector(".hubtag");
  const txt=h?(pl.id===CO.hq?"★ Штаб · ":"")+(h.rent?"Оренда · ":"")+HUB_LV[h.lvl]:"";c.el.classList.toggle("hubcap",!!h);c.el.classList.toggle("rentcap",!!(h&&h.rent));if(!txt){if(t)t.remove();continue}if(!t){t=document.createElement("i");t.className="hubtag";cb.appendChild(t)}t.textContent=txt}CITY_KEY=""}
function coFrame(){if(!G.speed)CO.lastFr=G.pfr??CO.lastFr;
{const off=(ANIM_T*25)%14.14;document.querySelectorAll(".meter i.hand").forEach(e=>e.style.setProperty("--hp",off.toFixed(1)+"px"))}
const fr=G.speed&&!modalOpen?clamp(acc/DUR[G.speed],0,.999):(CO.lastFr||0);CO.lastFr=fr;const T=G.day+fr;
  guard("Інциденти",()=>incFrame(T));
  {let done=0;for(const j of CO.jobs.slice())if(j.hold<=0&&T-j.t0>=j.tot){coComplete(j);done++}if(done)guard("Компанія · повернення",coReturns)}
  if(UI.win==="coTrips"&&(CO.jpT=(CO.jpT||0)+1)%6===0)for(const j of CO.jobs){if(j.hold>0)continue;const e=T-j.t0,el=document.querySelector(`[data-jp="${j.id}"]`);if(el){const s_=coJobState(j,e);el.style.width=(clamp(e/j.tot,0,1)*100).toFixed(1)+"%";el.classList.toggle("hand",s_.seg<0||!!s_.inc);el.style.background=s_.inc&&INC_RED.has(s_.inc.k)?"var(--bad)":""}const tx=document.querySelector(`[data-jt="${j.id}"]`);if(tx)tx.textContent=`${coJobState(j,e).ph} · залишилось ${daysS(Math.max(0,j.tot-e))}`}
  const lk=CO.jobs.length+":"+CO.hubs.length+":"+CO.hubs.map(h=>h.lvl).join("")+":"+CITY_EL.length;if(lk!==CO.lgk){CO.lgk=lk;updateLegend();updateHUD();coChipTags();coChipFilter();if(UI.win&&UI.win.startsWith("co"))CO.winDirty=true}
  // window refresh is coalesced: at most ~1.3 times per second, never while the player scrolls or drags a slider
  if(CO.winDirty&&UI.win&&!UI.busy&&winIdle()&&performance.now()-CO_RT>750){CO.winDirty=false;CO_RT=performance.now();renderWin()}
  // camera follows the selected vehicle
  if(CO_SEL&&CO.follow&&CO.jobs.includes(CO_SEL)){try{const j=CO_SEL,st=coJobState(j,j.hold>0?Math.min(T-j.t0,j.tl+j.hs+j.tm*.5):T-j.t0),q=coPosAt(j,st.s);if(q&&isFinite(q[0])&&isFinite(q[1])){Cam.ttx=q[0];Cam.ttz=q[1]}else CO.follow=false}catch(e){CO.follow=false}}
  const h=Math.floor(fr*24),mm=Math.floor((fr*24-h)*6)*10,key=G.day*1000+h*60+mm;if(key!==CO.clk){CO.clk=key;const el=$("#vDate");if(el)el.innerHTML=`${dateStr(G.date)} <span class="mut" style="font-size:12px;margin-left:4px">${String(h).padStart(2,"0")}:${String(mm).padStart(2,"0")}</span>`}}

/* ---------- monthly ---------- */
/* test mode: everything unlocked (logistics only) */
/* sandbox fill: a hub with a full fleet and crews in every settlement — a stress test for the map */
function coSandboxFill(){if(CO.sbFilled)return;CO.sbFilled=true;CO.cash=Math.max(CO.cash,1e12);
  const add=(t,pid,n)=>{for(let i=0;i<n;i++)CO.veh.push({id:CO.uid++,t,loc:pid,st:"idle",cond:100,km:0})};
  for(const p of PL){let h=hubAt(p.id);if(!h){h={pid:p.id,lvl:1,share:.04,mk:0};CO.hubs.push(h)}h.lvl=p.type==="vil"?1:p.type==="town"?2:3;
    const big=p.type==="cap"||p.type==="big"||p.type==="city";
    add("ltruck",p.id,p.type==="vil"?1:p.type==="town"?2:3);add("van",p.id,p.type==="vil"?1:2);
    add("truck",p.id,big?2:p.type==="town"?1:0);if(big)add("rtrain",p.id,1);
    if(p.rail&&big)add("train",p.id,1);if(p.port!=null)add(p.type==="cap"?"bulk":"ship",p.id,1);if(p.air)add(p.type==="cap"?"jumbo":"plane",p.id,1)}
  const need=coCrewNeed();for(const r in ROLE)CO.staff[r]=Math.max(CO.staff[r]||0,need[r]+50);
  for(const sd of MG){if(!CO.mgr[sd.id]){coMgrCand(sd.id);const c=CO.cand[sd.id].slice().sort((a,b)=>b.skill-a.skill)[0];CO.mgr[sd.id]={...c,skill:10,honest:true,loyal:100};delete CO.cand[sd.id]}}
  CO.auto=true;CO.wageLv=Math.max(CO.wageLv,1.2);CO.morale=90;applyMapColors();updateLegend();
  toast("good","Тестова мережа",`${CO.hubs.length} хабів · ${CO.veh.length} од. техніки · автодиспетчер увімкнено`)}
function coSandbox(refresh){if(!G.co||!SET.sandbox||CO.hq==null)return;if(!CO.sbFilled)coSandboxFill();const was=CO.tier;CO.tier=LIC.length-1;CO.cash=Math.max(CO.cash,1e11);{const nd=coCrewNeed();for(const r in ROLE)if((CO.staff[r]||0)<nd[r])CO.staff[r]=nd[r]+20}CO.neg=0;
  for(const r in ROLE)CO.pool[r]=Math.max(CO.pool[r]||0,999);
  if(refresh){if(was!==CO.tier){coWho();applyMapColors()}updateHUD();if(UI.win)renderWin();if(UI.sel!=null)renderInsp();toast("good","Відкрито все","Безкінечні гроші, усі ліцензії, необмежений найм")}}
function coMonth(){
  const m=CO.m,wk=wageK(G.me)*CO.wageLv*(1-msk("hro")*.08);let wage=0,mgmt=0,rent=0,mk=0,ins=0,interest=0,stolen=0;
  for(const r in ROLE)wage+=(CO.staff[r]||0)*ROLE[r].w*wk;
  const N=Object.values(CO.staff).reduce((a,b)=>a+b,0);const office=Math.round(45*Math.pow(N,1.12)*priceK(G.me)*(1-msk("cfo")*.1));m.office=(m.office||0)+office;CO.cash-=office;
  // labour market refresh: depends on wages, HR director, network size
  const lk=clamp(CO.wageLv,.8,1.8)*(1+msk("hro")*.8)*(1+Math.min(3,CO.hubs.length*.25));
  for(const r in ROLE){const T=Object.values(VT).filter(t=>t.role===r);const open=T.some(t=>t.tier<=CO.tier);CO.pool=CO.pool||{};CO.pool[r]=open?Math.round(Math.min((CO.pool[r]||0)*.5+ROLE[r].pool*lk,ROLE[r].pool*lk*2.5)):0}
  for(const id in CO.mgr)mgmt+=CO.mgr[id].sal;
  for(const h of CO.hubs){rent+=hubRentM(h);mk+=h.mk||0}
  if(CO.ins)ins=Math.round(500+CO.veh.reduce((a,v)=>a+VT[v.t].cost,0)*.0035);
  for(const l of CO.loans){const int=l.left*l.rate/12,pr=Math.min(l.left,l.amt/24);interest+=int;l.left-=pr;CO.cash-=pr}
  CO.loans=CO.loans.filter(l=>l.left>1);
  if(CO.cash<0)interest+=-CO.cash*.025;
  // tenders
  for(const t of CO.tenders){m.tender+=t.pay*t.n;t.left--}
  CO.cash+=m.tender;
  const ended=CO.tenders.filter(t=>t.left<=0);ended.forEach(t=>{let n=t.n;for(const v of CO.veh)if(n>0&&v.st==="tender"&&v.t===t.t){v.st="idle";n--}coNews("good","doc",`Завершено тендер «${t.n_}»: техніка повернулася в роботу`)});CO.tenders=CO.tenders.filter(t=>t.left>0);
  // dishonest managers
  for(const id in CO.mgr){const g=CO.mgr[id];if(!g.honest)stolen+=Math.max(200,coRev(m)*rnd(.008,.025))}
  m.wage+=wage;m.mgmt+=mgmt;m.rent+=rent;m.mk+=mk;m.ins+=ins;m.interest+=interest;m.stolen+=stolen;m.other+=stolen;
  CO.cash-=wage+mgmt+rent+mk+ins+interest+stolen;
  // history
  CO.hist.cash.push(CO.cash);CO.hist.rev.push(coRev(m));CO.hist.rat.push(+CO.rating.toFixed(2));CO.hist.prof.push(coRev(m)-coCost(m));
  for(const k in CO.hist)if(CO.hist[k].length>48)CO.hist[k].shift();
  CO.lm=m;CO.m=coZero();
  // competitors
  CO.comp.forEach(c=>c.rev*=1+c.g+rnd(-.02,.02));
  // world: border conflicts
  CO.conf.filter(x=>x.until<=G.day).forEach(x=>{G.esc[x.a][x.b]=G.esc[x.b][x.a]=0;coNews("good","handshake",`Кордон ${G.C[x.a].name} — ${G.C[x.b].name} знову відкрито`)});CO.conf=CO.conf.filter(x=>x.until>G.day);
  if(chance(.12)&&CO.conf.length<3){const a=pick(G.C);const b=G.C[pick(a.geo.neighbors.filter(j=>G.C[j])||[])];if(b&&!inConf(a.id)&&!inConf(b.id)){CO.conf.push({a:a.id,b:b.id,until:G.day+rint(90,270)});G.esc[a.id][b.id]=G.esc[b.id][a.id]=3;
    coNews("bad","swords",`Конфлікт на кордоні ${a.name} — ${b.name}: перевезення ускладнені, ризики зросли`);toast("bad","Прикордонний конфлікт",`${a.name} — ${b.name}`)}}
  if(chance(.05)){const k=rnd(1.15,1.4);CO.fuel=Math.min(2.2,CO.fuel*k);coNews("bad","barrel",`Пальне подорожчало на ${((k-1)*100).toFixed(0)}%: світові ціни на нафту стрибнули`)}
  // events (one optional modal per month at most)
  guard("Компанія · події",coMonthEvents);
  // management candidates refresh
  for(const s of MG)if(!CO.mgr[s.id]&&(!CO.cand[s.id]||chance(.25)))coMgrCand(s.id);
  // achievements
  for(const [id,n,d,f] of CO_MS){if(!CO.ms.includes(id)&&f()){CO.ms.push(id);coNews("good","star",`Досягнення ${CO.name}: «${n}»`);toast("good","Досягнення: "+n,d)}}
  // bankruptcy
  if(CO.cash<-coCredit()*.5)CO.neg++;else if(CO.cash>0)CO.neg=0;
  if(CO.neg>=3){G.over=true;setSpeed(0);queueModal({icon:"alert",tone:"bad",eyebrow:"Банкрутство",title:`${CO.name} збанкрутувала`,body:`<p>Три місяці поспіль борги перевищували кредитний ліміт. Кредитори забирають техніку.</p><p class="note">Виконано ${CO.cdel} контрактів, доставлено ${Math.round(CO.deliv).toLocaleString("uk-UA")} відправлень.</p>`,choices:[{t:"Головне меню",d:"",f(){location.reload()}}]})}
  coWho();
}
/* tenders: long contracts offered on a board in the Orders window */
const TD_NM={air:["фармацевтичного концерну","виробника електроніки","авіабудівного заводу","міжнародного Червоного Хреста"],sea:["зернотрейдера","металургійного комбінату","автоконцерну","нафтової компанії"],rail:["вугільної шахти","металургійного комбінату","зернового елеватора","цементного заводу"],road:["мережі супермаркетів","автозаводу","фармацевтичної компанії","інтернет-магазину","будівельного холдингу","виробника добрив"]};
function coTenderOffers(){CO.toff=(CO.toff||[]).filter(o=>o.exp>G.day);if(CO.tier<2)return;
  const types=Object.keys(VT).filter(t=>VT[t].tier>=1&&VT[t].tier<=CO.tier&&VT[t].mode!=="local");let added=0;
  for(let i=0;i<3&&CO.toff.length<5;i++){if(!chance(i?.45:.85))continue;const t=pick(types),T=VT[t];const n=T.cost>1e7?1:T.cost>1e6?rint(1,2):rint(2,5),months=rint(4,9);
    const pay=Math.round(T.cost*(T.cost>1e7?.036:T.cost>1e6?.06:.11)*priceK(G.me)*(1+msk("cco")*.1));
    CO.toff.push({id:CO.uid++,t,n,months,pay,n_:pick(TD_NM[T.mode]||TD_NM.road),exp:G.day+rint(20,40)});added++}
  if(added)toast("","Нові тендери",`${added} ${added===1?"пропозиція":"пропозиції"} у «Біржі вантажів»`,()=>openWin("coJobs"))}
ACT.coTd=id=>{const o=(CO.toff||[]).find(x=>x.id===+id);if(!o)return;const idle=CO.veh.filter(v=>v.t===o.t&&v.st==="idle");if(idle.length<o.n)return toast("warn","Бракує техніки",`Потрібно ${o.n} × ${VT[o.t].n.toLowerCase()}, вільних ${idle.length}`);
  const T=VT[o.t],free=coCrewFree();if(free[T.role]<(T.crew||1)*o.n)return toast("warn","Бракує екіпажів",ROLE[T.role].n);
  idle.slice(0,o.n).forEach(v=>v.st="tender");CO.tenders.push({t:o.t,n:o.n,left:o.months,pay:o.pay,n_:o.n_});CO.toff=CO.toff.filter(x=>x!==o);coNews("good","doc",`${CO.name} виграла тендер ${o.n_}`);toast("good","Тендер підписано",`${o.n} × ${T.n.toLowerCase()} на ${o.months} міс.`);renderWin()};
ACT.coTdX=id=>{CO.toff=(CO.toff||[]).filter(x=>x.id!==+id);renderWin()};
ACT.coJf=k=>{UI.jfl=k;UI.jmore=15;UI.bmore=15;UI.jpin=null;renderWin()};ACT.coJmore=()=>{UI.jmore=(UI.jmore||15)+15;renderWin()};ACT.coBmore=()=>{UI.bmore=(UI.bmore||15)+15;renderWin()};
function coMonthEvents(){
  const ok=coModalOK();
  // strike
  const staffN=Object.values(CO.staff).reduce((a,b)=>a+b,0);
  if(ok&&CO.morale<34&&staffN>=5&&chance(.4-msk("hro")*.25)){coModal({icon:"fist",tone:"bad",eyebrow:"Персонал",title:"Працівники погрожують страйком",body:`<p>Моральний дух ${CO.morale.toFixed(0)}/100. Водії вимагають підвищення зарплат і кращих умов.</p>`,
    choices:[{t:"Підняти зарплати на 15%",d:"Моральний дух швидко зросте",f(){CO.wageLv=Math.min(1.8,CO.wageLv+.15);CO.morale+=15}},
      {t:"Переговори",d:`Шанс ≈${Math.round((.3+msk("hro")*.6)*100)}% домовитись без витрат`,f(){if(chance(.3+msk("hro")*.6)){CO.morale+=10;toast("good","Домовилися","Страйку не буде")}else{CO.strike=G.day+6;coNews("bad","fist",`Страйк у ${CO.name}: техніка стоїть`);toast("bad","Страйк","6 днів простою")}}},
      {t:"Звільнити заводіїв",d:"−10% персоналу, рейтинг −0,1, дух −10",f(){for(const r in CO.staff)CO.staff[r]=Math.floor(CO.staff[r]*.9);CO.rating=clamp(CO.rating-.1,1,5);CO.morale-=10}}]});return}
  // embezzlement caught
  const thief=Object.entries(CO.mgr).find(([id,g])=>!g.honest&&id!=="cfo");
  if(ok&&thief&&CO.mgr.cfo&&CO.mgr.cfo.honest&&chance(.15+msk("cfo")*.5)){const [id,g]=thief;const s=MG.find(x=>x.id===id);g.honest=true;const loss=Math.round(Math.max(3000,coRev(CO.lm)*rnd(.03,.08)));
    coModal({icon:"coins",tone:"bad",eyebrow:"Фінансовий аудит",title:`${s.n} краде`,body:`<p>Фінансовий директор ${esc(CO.mgr.cfo.name)} знайшов фіктивні рахунки: <b>${esc(g.name)}</b> виводив гроші через підставних підрядників. Збитки ≈ ${fmtUSD(loss)}.</p>`,
      choices:[{t:"Звільнити і подати до суду",d:"Повернемо частину грошей",f(){delete CO.mgr[id];CO.cash+=loss*.5;coMgrCand(id);toast("good","Менеджера звільнено","Повернуто "+fmtUSD(loss*.5))}},
        {t:"Залишити з попередженням",d:"Він вдячний… поки що",f(){g.honest=chance(.6);g.loyal=Math.min(100,g.loyal+20)}}]});return}
  // raise demand
  for(const [id,g] of Object.entries(CO.mgr)){const s=MG.find(x=>x.id===id);const want=coMgrSal(g.skill);
    if(ok&&want>g.sal*1.25&&chance(.3)){const ns=Math.round(want);coModal({icon:"briefcase",tone:"warn",eyebrow:"Менеджмент",title:`${s.n} просить підвищення`,body:`<p>${esc(g.name)} каже, що компанія виросла, а його зарплата — ні. Ринок пропонує ${fmtUSD(ns)}/міс замість ${fmtUSD(g.sal)}.</p>`,
      choices:[{t:`Погодитись: ${fmtUSD(ns)}/міс`,d:"Лояльність +20",f(){g.sal=ns;g.loyal=Math.min(100,g.loyal+20)}},{t:`Компроміс: ${fmtUSD((g.sal+ns)/2)}/міс`,d:"50% що погодиться",f(){if(chance(.5)){g.sal=Math.round((g.sal+ns)/2)}else{g.loyal-=20;toast("warn","Менеджер незадоволений","Лояльність падає")}}},
        {t:"Відмовити",d:"Лояльність −30, може піти",f(){g.loyal-=30;if(g.loyal<25){delete CO.mgr[id];coMgrCand(id);coNews("bad","briefcase",`${s.n} ${CO.name} пішов до конкурентів`);toast("bad","Менеджер звільнився",s.n)}}}]});return}}
  // tender
  coTenderOffers();
  if(chance(.1)){const up=chance(.55);CO.rating=clamp(CO.rating+(up?.12:-.12),1,5);coNews(up?"good":"bad",up?"star":"alert",up?`Вірусний відгук: клієнт розхвалив швидкість ${CO.name}`:`Вірусне відео: водій ${CO.name} кидає посилки через паркан`);toast(up?"good":"bad",up?"Вірусний відгук":"Вірусний скандал",up?"Рейтинг +0,12":"Рейтинг −0,12")}
  const avgC=CO.veh.length?CO.veh.reduce((a,v)=>a+v.cond,0)/CO.veh.length:100;
  if(avgC<50&&chance(.4)){const fine=Math.round(800+CO.veh.length*300*priceK(G.me));CO.cash-=fine;CO.lm.other+=fine;coNews("bad","gavel",`Техогляд виявив зношену техніку ${CO.name}: штраф ${fmtUSD(fine)}`);toast("bad","Штраф за техстан",fmtUSD(fine))}
}

/* ---------- management ---------- */
const MG_TR=["Обережний","Амбітний","Харизматичний","Педант","Ризиковий","Ветеран галузі","Молодий талант","Прагматик"];
function coMgrSal(skill){return Math.round((1200+skill*380)*(1+Math.log10(1+coRev(CO.lm)/150000)*.8)*(.6+.4*priceK(G.me))/10)*10}
function coMgrCand(id){if(!id){for(const s of MG)if(!CO.cand[s.id])coMgrCand(s.id);return}
  CO.cand[id]=[0,1,2].map(()=>{const sk=clamp(Math.round(rnd(2,9.5)),1,10);return{name:personName(),age:rint(28,63),skill:sk,sal:coMgrSal(sk),trait:pick(MG_TR),honest:chance(.78),loyal:rint(45,85)}})}
ACT.coHireM=a=>{const [id,i]=a.split(":");const g=CO.cand[id][+i];if(CO.cash<g.sal)return toast("warn","Бракує грошей","Підписний бонус — місячна зарплата");CO.cash-=g.sal;CO.m.mgmt+=g.sal;CO.mgr[id]={...g};delete CO.cand[id];
  toast("good","Менеджера найнято",`${g.name} · ${MG.find(x=>x.id===id).n}`);renderWin()};
ACT.coFireM=id=>{const g=CO.mgr[id];CO.cash-=g.sal;CO.m.mgmt+=g.sal;delete CO.mgr[id];coMgrCand(id);if(id==="cto")CO.auto=false;renderWin()};
ACT.coRecand=id=>{const c=Math.round(1500*priceK(G.me));if(CO.cash<c)return;CO.cash-=c;CO.m.other+=c;coMgrCand(id);renderWin()};

/* ---------- player actions ---------- */
ACT.coBuy=t=>{const T=VT[t];if(CO.tier<T.tier)return;if(CO.cash<T.cost)return toast("warn","Бракує грошей",`${T.n} коштує ${fmtUSD(T.cost)}`);
  let hubs=CO.hubs.filter(h=>modeOK(T.mode,PL[h.pid]));if(T.mode==="local")hubs=CO.hubs;
  if(!hubs.length)return toast("warn","Немає відповідного хабу",T.mode==="sea"?"Потрібен хаб у портовому місті":T.mode==="air"?"Потрібен хаб у місті з аеропортом":"Потрібен хаб біля залізничної станції");
  let h=hubs.find(x=>x.pid===CO.buyAt)||hubs.find(x=>x.pid===CO.hq)||hubs[0];
  if(hubVehN(h.pid)>=hubVehCap(h)){const o=hubs.find(x=>hubVehN(x.pid)<hubVehCap(x));if(!o)return toast("warn","Хаби заповнені",`${HUB_LV[h.lvl]} у місті ${PL[h.pid].name} вміщує ${hubVehCap(h)} од. техніки. Покращіть хаб або відкрийте новий.`);toast("",`${PL[h.pid].name}: місця немає`,`Техніку поставлено в хаб ${PL[o.pid].name}`);h=o}
  CO.cash-=T.cost;CO.veh.push({id:CO.uid++,t,loc:h.pid,st:"idle",cond:100,km:0});
  toast("good","Куплено: "+T.n,`${PL[h.pid].name} · ${fmtUSD(T.cost)}`);updateHUD();renderWin()};
ACT.coSell=a=>{const [t,loc]=a.split(":");const v=CO.veh.find(v=>v.t===t&&v.st==="idle"&&String(v.loc)===loc);if(!v)return;const T=VT[t];const p=Math.round(T.cost*(.25+.35*v.cond/100));CO.cash+=p;CO.veh=CO.veh.filter(x=>x!==v);toast("","Продано: "+T.n,fmtUSD(p,true));renderWin()};
ACT.coRepair=a=>{const [t,loc]=a.split(":");const vs=CO.veh.filter(v=>v.t===t&&v.st==="idle"&&String(v.loc)===loc&&v.cond<99);const c=Math.round(vs.reduce((s,v)=>s+VT[t].cost*(100-v.cond)/100*.22,0)*repK());
  if(!vs.length)return;if(CO.cash<c)return toast("warn","Бракує грошей","Ремонт "+fmtUSD(c));CO.cash-=c;CO.m.upkeep+=c;vs.forEach(v=>v.cond=100);toast("good","Техніку відремонтовано",fmtUSD(c));renderWin()};
ACT.coFfl=k=>{UI.ffl=k;UI.fmore=0;renderWin()};ACT.coFmore=()=>{UI.fmore=(UI.fmore||120)+120;renderWin()};
ACT.coMaint=v=>{CO.maint=+v;renderWin()};
ACT.coBuyAt=v=>{CO.buyAt=+v;renderWin()};
ACT.coHire=a=>{const [r,n]=a.split(":");let k=+n;if(k>0){k=Math.min(k,Math.floor(CO.pool[r]||0));if(k<=0)return toast("warn","Ринок праці вичерпано",`${ROLE[r].n}: нові кандидати з'являться наступного місяця. Підвищення зарплат і HR-директор приводять більше людей.`)}
  const fee=Math.round(ROLE[r].w*wageK(G.me)*.5*Math.abs(k)*(1-msk("hro")*.3));
  if(k>0){const tot=Object.values(CO.staff).reduce((a,b)=>a+b,0),room=staffCap()-tot;if(room<=0)return toast("warn","Немає робочих місць",`Хаби вміщують ${staffCap()} працівників. Покращіть хаби або відкрийте нові.`);if(k>room){k=room}}
  if(k>0){if(CO.cash<fee)return toast("warn","Бракує грошей","Найм коштує "+fmtUSD(fee));CO.cash-=fee;CO.m.wage+=fee;CO.staff[r]+=k;CO.pool[r]-=k}
  else{const q=Math.min(CO.staff[r],-k);if(!q)return;const sev=Math.round(ROLE[r].w*wageK(G.me)*CO.wageLv*q);CO.cash-=sev;CO.m.wage+=sev;CO.staff[r]-=q;CO.morale-=q*.6}
  updateHUD();renderWin()};
ACT.coWageLive=(v,t)=>{CO.wageLv=+v/100;const el=$("#coWv");if(el)el.textContent=v+"%";UI.busy=true};
ACT.coWageSet=()=>{UI.busy=false;renderWin()};
ACT.coLic=()=>{const n=LIC[CO.tier+1];if(!n)return;const ok=coLicOK();if(!ok.ok)return;CO.cash-=n.cost;CO.tier++;if(CO.tier===2)setTimeout(coTenderOffers,0);coNews("good","doc",`${CO.name} отримала ліцензію «${n.n}»`);
  queueModal({icon:"star",tone:"good",eyebrow:"Нова ліцензія",title:n.n,body:`<p>${n.d}</p><div class="hint">${ic("bulb")}<div>${["","Купіть фургон у вікні «Автопарк» і найміть водія. Замовлення між містами з'являться у вікні «Замовлення». Відкривайте хаби в інших містах країни: клацніть на країну на мапі.","Вантажівки беруть до 20 т. Покращуйте хаби до 2 рівня — вони дають більше замовлень. Іноді надходитимуть тендери.","Тепер можна возити через кордони свого материка і відкривати хаби за кордоном. Стежте за ризиками: крадіжки, конфлікти, черги на кордонах. Пришвидшити митницю допоможе юрист і митний брокер.","Потяги ходять між містами зі станціями (шар «Дороги й порти»). Хаб має бути біля станції.","Кораблі потребують хабу в портовому місті. Тепер можна відкривати хаби на інших материках.","Літаки потребують хабу в місті з аеропортом: столиці й великі міста.","Балкери й важкі літаки, найбільші контракти. Обійдіть конкурентів у рейтингу компаній."][CO.tier]}</div></div>`,choices:[{t:"Чудово",d:"",f(){}}]});
  coWho();applyMapColors();updateHUD();renderWin()};
function coLicOK(){const n=LIC[CO.tier+1];if(!n)return{ok:false};const r=[[CO.rating>=n.rat,`Рейтинг ${n.rat.toFixed(1)}`,CO.rating.toFixed(2)],[(CO.cdel||0)>=n.del,`Доставок ${n.del.toLocaleString("uk-UA")}`,Math.floor(CO.cdel||0).toLocaleString("uk-UA")],[CO.cdel>=n.con,`Контрактів ${n.con}`,CO.cdel],[(CO.xp||0)>=(n.xp||0),n.gr!=null&&typeof GRADES!=="undefined"?`Грейд «${GRADES[n.gr].n}»`:`Досвід ${(n.xp||0).toLocaleString("uk-UA")}`,typeof GRADES!=="undefined"?GRADES[coGrade()].n:Math.floor(CO.xp||0).toLocaleString("uk-UA")],[CO.cash>=n.cost,`Внесок ${fmtUSD(n.cost)}`,fmtUSD(CO.cash)]].filter((x,i)=>(i!==2||n.con>0)&&(i!==3||n.xp>0));return{ok:r.every(x=>x[0]),r}}
ACT.coHub=pid=>{pid=+pid;const p=PL[pid];if(hubAt(pid)||!coScope(p))return;const ab=hubAbroad(p),c=hubOpenCost(p);if(CO.cash<c)return toast("warn","Бракує грошей",(ab?"Застава за оренду хаба ":"Хаб коштує ")+fmtUSD(c));
  CO.cash-=c;CO.hubs.push({pid,lvl:1,share:.01,mk:0,...(ab?{rent:1}:{})});coNews("good","building",`${CO.name} ${ab?"орендувала":"відкрила"} хаб у місті ${p.name} (${G.C[p.cid].name})`);toast("good",ab?"Хаб в оренді":"Новий хаб",ab?`${p.name}: оренда ${fmtUSD(hubRentM({pid,lvl:1,rent:1}))}/міс.`:p.name);
  if(p.cid!==G.me)CO.flags.abroad=1;applyMapColors();coChipTags();if(UI.sel!=null)renderInsp();renderWin()};
ACT.coHubUp=pid=>{const h=hubAt(+pid);if(!h||h.lvl>=4)return;if(h.rent&&h.lvl>=2)return toast("warn","Орендований хаб","Орендодавець дозволяє розширити його лише до 2 рівня");const c=hubCost(PL[h.pid])*HUB_UP[h.lvl];if(CO.cash<c)return toast("warn","Бракує грошей",fmtUSD(c));CO.cash-=c;h.lvl++;toast("good",HUB_LV[h.lvl],PL[h.pid].name);if(UI.sel!=null)renderInsp();renderWin()};
ACT.coHubClose=pid=>{pid=+pid;if(pid===CO.hq)return;const h=hubAt(pid);CO.hubs=CO.hubs.filter(x=>x!==h);if(!h.rent)CO.cash+=hubCost(PL[pid])*h.lvl*.3;toast("",h.rent?"Оренду хаба припинено":"Хаб закрито",PL[pid].name);applyMapColors();renderWin()};
ACT.coMk=a=>{const [pid,v]=a.split(":");const h=hubAt(+pid);if(h){h.mk=+v;renderWin()}};
ACT.coIns=()=>{CO.ins=!CO.ins;renderWin()};
ACT.coAutoT=()=>{if(!CO.mgr.cto)return toast("warn","Потрібен директор диспетчерської","Найміть його у вікні «Персонал»");CO.auto=!CO.auto;renderWin()};
ACT.coLoan=f=>{const lim=coCredit()-CO.loans.reduce((a,l)=>a+l.left,0);const a=Math.round(Math.max(0,lim)*+f);if(a<1000)return toast("warn","Кредитний ліміт вичерпано","");CO.loans.push({amt:a,left:a,rate:coRate()});CO.cash+=a;toast("good","Кредит отримано",`${fmtUSD(a)} під ${(coRate()*100).toFixed(1)}%`);renderWin()};
ACT.coRepay=()=>{let pay=Math.min(CO.cash*.8,CO.loans.reduce((a,l)=>a+l.left,0));if(pay<100)return;CO.cash-=pay;for(const l of CO.loans){const x=Math.min(l.left,pay);l.left-=x;pay-=x}CO.loans=CO.loans.filter(l=>l.left>1);renderWin()};
ACT.coSend=id=>{const k=CO.board.find(x=>x.id===+id);if(!k)return;const P=coPlan(k);if(!P.ok)return toast("warn","Неможливо відправити",P.why);coDispatch(k,P);CO_PREV=null;updateHUD();renderWin()};
ACT.consNo=id=>{const k=CO.board.find(x=>x.id===+id);if(!k)return;const P=coPlan(k);toast("warn","Збірний рейс недоступний",P.ok?"":P.why)};
ACT.lpPlanNo=id=>{const k=CO.board.find(x=>x.id===+id);if(!k)return;const P=coPlan(k);toast("warn","Маршрут не прокласти",P.ok?"":P.why)};
ACT.coShow=id=>{const k=CO.board.find(x=>x.id===+id);if(!k)return;CO_PREV=CO_PREV===k.id?null:k.id;if(CO_PREV){const A=PL[k.from],B=PL[k.to];Cam.ttx=(A.x+B.x)/2;Cam.ttz=(A.z+B.z)/2+.3;Cam.tdist=clamp(Math.hypot(A.x-B.x,A.z-B.z)*1.5+3,3,WX*1.1)}renderWin()};
ACT.coJob=id=>{const j=CO.jobs.find(x=>x.id===+id);if(!j)return;CO_SEL=j;CO.follow=true;const q=coPosAt(j,coJobState(j,G.day-j.t0).s);Cam.ttx=q[0];Cam.ttz=q[1]+.3;Cam.tdist=Math.min(Cam.tdist,6);coCard()};
ACT.coDecl=id=>{CO.board=CO.board.filter(x=>x.id!==+id);renderWin()};
ACT.coUcClose=()=>{CO_SEL=null;CO.follow=false;$("#ucard").hidden=true};
ACT.coFly=pid=>{const p=PL[+pid];if(!p)return;CO.follow=false;Cam.ttx=p.x;Cam.ttz=p.z+.12;Cam.tdist=Math.min(Cam.tdist,2.4);CO.ping={pid:p.id,t:performance.now()}};
ACT.coCountry=k=>{UI.selP=null;UI.sel=+k;renderInsp()};
ACT.coGoto=pid=>{const p=PL[+pid];Cam.ttx=p.x;Cam.ttz=p.z+.3;Cam.tdist=Math.min(Cam.tdist,5);UI.sel=p.cid;if(G.board)UI.selP=p.id;renderInsp()};
ACT.coRename=()=>{queueModal({icon:"doc",eyebrow:"Компанія",title:"Нова назва компанії",body:`<input id="coNameIn" maxlength="32" value="${esc(CO.name)}" style="width:100%;height:40px;padding:0 12px;background:rgba(255,255,255,.05);border:1px solid var(--line-hi);color:var(--fg);font:600 15px/1 var(--f-body)">`,
  choices:[{t:"Зберегти",d:"Назва й логотип оновляться",f(){}},{t:"Скасувати",d:"",f(){}}]});
  const el0=$("#coNameIn");const save=()=>{const n=(el0.value||"").trim();if(n){CO.name=n.slice(0,32);CO.logo=coLogo(CO.name,CO.col);coWho();updateHUD();updateLegend();if(UI.win)renderWin();toast("good","Компанію перейменовано",CO.name)}};
  const b0=document.querySelector("#mbox .choice");if(b0)b0.addEventListener("click",save,{capture:true,once:true});
  setTimeout(()=>{if(el0){el0.focus();el0.select();el0.onkeydown=e=>{e.stopPropagation();if(e.key==="Enter"&&b0)b0.click()}}},50)};

/* ---------- HUD ---------- */
function coHUD(){if(!CO.hubs||!CO.veh)return;
  if(typeof grBox==="function")grBox();else $("#yearBox").textContent=G.date.y;const lm=CO.lm,pr=lm?coRev(lm)-coCost(lm):0;
  const busy=CO.veh.filter(v=>v.st!=="idle").length,staff=Object.values(CO.staff).reduce((a,b)=>a+b,0)+CO.founder;
  const K=[
   ["Гроші",fmtUSD(CO.cash),`<span class="d ${CO.cash>=0?"good":"bad"}">${CO.cash>=0?"▲":"▼"}</span>`,T("Гроші компанії","Готівка на рахунку. Нижче нуля — дорогий овердрафт; три місяці глибокого мінусу — банкрутство.")],
   ["Прибуток / міс",lm?fmtUSD(pr,true):"—",lm?`<span class="d ${pr>=0?"good":"bad"}"></span>`:"",T("Прибуток за минулий місяць","Виручка від доставок по країні, міжнародних перевезень і тендерів мінус зарплати, пальне, оренда, ремонти, податки за чужі хаби, кредити й претензії.")],
   ["Рейтинг",CO.rating.toFixed(2)+" ★","",T("Рейтинг компанії","1–5 зірок. Росте від вчасних і цілих доставок, падає від запізнень, аварій і крадіжок. Відкриває ліцензії, підвищує попит і ціну замовлень.")],
   ["Доставки / день",Math.round(CO.dayLocal).toLocaleString("uk-UA"),"",T("Доставки за день","Посилки, розвезені по містах за останній день. Всього: "+Math.round(CO.deliv).toLocaleString("uk-UA")+", контрактів: "+CO.cdel)],
   ["Техніка",`${CO.veh.length}`,`<span class="d mut" style="font-size:11px">${busy} у рейсі</span>`,T("Автопарк","Уся техніка компанії. У рейсах, на тендерах або вільна (вільні фургони й вантажні машини працюють у місті).")],
   ["Персонал",staff,"",T("Персонал","Водії, машиністи, моряки й пілоти. Моральний дух: "+CO.morale.toFixed(0)+"/100.")],
   ["Ліцензія",`${CO.tier}/${LIC.length-1}`,"",T(LIC[CO.tier].n,LIC[CO.tier].d)],
  ];
  $("#kpis").innerHTML=K.map(k=>`<div class="kpi" data-tip="${k[3]}"><span class="lbl">${k[0]}</span><div class="v">${k[1]}${k[2]}</div></div>`).join("");
  CO.clk=-1;coFrame();
  $("#vTension").innerHTML=`${CO.jobs.length}<span class="mut" style="font-size:11px;margin-left:6px">${CO.tier>=1?CO.board.length+" на біржі":"з ліцензією 2"}</span>`;
  $("#vMarket").innerHTML=`<span class="${CO.fuel>1.15?"bad":CO.fuel<.9?"good":""}">${fmtUSD(CO.fuel*80)}</span>`;
  {let c=$("#cParts");if(!c){c=document.createElement("div");c.className="cell opt";c.id="cParts";c.innerHTML=`<span class="lbl">ТО вантажівки</span><span class="v" id="vParts">—</span>`;$("#cMarket").after(c)}
   const pk=CO.parts||1,rk=typeof repK==="function"?repK():pk;c.dataset.tip=T("Запчастини й ремонт",`Середня вартість планового техобслуговування вантажівки (норма ≈ $1 200). Так само дорожчають ремонт, евакуатори, утримання техніки й модернізація. Війни, санкції й закриті країни піднімають ціни. ${typeof bizWhy==="function"?bizWhy().join(". "):""}`);
   $("#vParts").innerHTML=`<span class="${pk>1.12?"bad":pk<.92?"good":""}">${fmtUSD(1200*pk*priceK(G.me))}</span>${Math.abs(rk-pk)>.005?`<span class="mut" style="font-size:11px;margin-left:6px">з СТО ${fmtUSD(1200*rk*priceK(G.me))}</span>`:""}`}
  {const rv=coRev(CO.m),dm=[31,28,31,30,31,30,31,31,30,31,30,31][G.date.m],prev=CO.lm?coRev(CO.lm)*G.date.d/dm:0,dlt=prev>0?(rv/prev-1)*100:null;
   $("#vPop").innerHTML=`${fmtUSD(rv)}${dlt!=null?`<span class="${dlt>=0?"good":"bad"}" style="font-size:11px;margin-left:6px">${dlt>=0?"+":""}${dlt.toFixed(0)}%</span>`:""}`}
  document.querySelectorAll("#speed button").forEach((b,i)=>b.classList.toggle("on",i===G.speed));
  document.querySelectorAll("#rail .rbtn").forEach(b=>b.classList.toggle("on",b.dataset.arg===UI.win));
  const jb=$("#coJobBadge");if(jb){const n=CO.board.length;jb.hidden=!n||CO.tier<1;jb.textContent=n}{const tb=$("#coTripBadge");if(tb){const n=CO.jobs.filter(j=>!j.ret).length;tb.hidden=!n;tb.textContent=n}}
}

/* ---------- windows ---------- */
RAIL.unshift(["coHome","briefcase","Компанія","Огляд, рейтинг, ліцензії, досягнення і поради."],["coJobs","box","Біржа вантажів","Замовлення від підприємств, прокладання маршрутів, автодиспетчеризація, тендери."],["coTrips","road","Рейси в дорозі","Техніка в рейсах, ділянки маршрутів, повернення в хаби, останні доставки."],["coFleet","truck","Автопарк","Купівля, продаж і ремонт техніки."],["coNet","globe","Мережа хабів","Хаби в містах, місцевий ринок доставок, реклама, склади."],["coStaff","users","Персонал і менеджмент","Найм, зарплати, моральний дух, топменеджери."],["coFin","coins","Фінанси","Прибутки й витрати, кредити, страхування, рейтинг компаній світу."],"|");
const _buildHUD0=buildHUD;buildHUD=function(){_buildHUD0();if(G.co){if(CO.hq!=null&&PL.length)coWho();const b=document.querySelector('#rail [data-arg="coJobs"]');if(b&&!$("#coJobBadge"))b.insertAdjacentHTML("beforeend",`<span class="badge" id="coJobBadge" hidden>0</span>`);const t=document.querySelector('#rail [data-arg="coTrips"]');if(t&&!$("#coTripBadge"))t.insertAdjacentHTML("beforeend",`<span class="badge" id="coTripBadge" hidden>0</span>`)}};
const plName=(p,fl=true)=>`${fl?`<img src="${G.C[p.cid].flag}" alt="" style="width:18px;height:12px;border:1px solid var(--line-hi);vertical-align:-1px;margin-right:5px">`:""}${esc(p.name)}`;
const kmS=len=>Math.round(len*KM).toLocaleString("uk-UA")+" км";
const daysS=d=>d<1/24?Math.max(1,Math.round(d*1440))+" хв":d<1?Math.round(d*24)+" год":d.toFixed(1)+" дн.";
function coAdvice(){const A=[];const H=CO.hubs.map(h=>({h,p:PL[h.pid]}));
  const free=coCrewFree(),need=coCrewNeed();
  for(const r in ROLE){const lack=need[r]-((CO.staff[r]||0)+(r==="driver"?CO.founder:0));if(lack>0)A.push(["bad",`Бракує персоналу: <b>${ROLE[r].n.toLowerCase()}</b> — ${lack}. Частина техніки стоїть без екіпажу. Наймайте у вікні «Персонал».`])}
  if(CO.cash<0)A.push(["bad",`Рахунок у мінусі — овердрафт коштує 2,5% на місяць. Візьміть кредит, продайте зайву техніку або скоротіть витрати.`]);
  const lo=CO.veh.filter(v=>v.cond<45).length;if(lo)A.push(["warn",`${lo} од. техніки зношені (стан нижче 45%): більше аварій і поломок. Ремонт — у вікні «Автопарк».`]);
  if(CO.morale<40)A.push(["warn",`Моральний дух ${CO.morale.toFixed(0)}/100 — ризик страйку й аварій. Підніміть зарплати або найміть HR-директора.`]);
  const lic=coLicOK();if(lic.ok)A.push(["good",`Можна отримати ліцензію <b>«${LIC[CO.tier+1].n}»</b>!`]);
  if(CO.tier>=1&&!CO.veh.some(v=>VT[v.t].mode==="road"))A.push(["warn","Ліцензія дозволяє міжміські рейси, але у вас немає фургона чи вантажівки."]);
  if(CO.tier>=1&&CO.hubs.length<2)A.push(["","Відкрийте хаб в іншому місті своєї країни: клацніть на країну на мапі й оберіть місто."]);
  if(CO.lm&&CO.lm.stolen>0&&!CO.mgr.cfo)A.push(["warn",`Нез'ясовані втрати ${fmtUSD(CO.lm.stolen)} минулого місяця. Без фінансового директора ніхто не перевірить менеджерів.`]);
  if(!CO.ins&&CO.tier>=2)A.push(["","Без страховки кожна крадіжка чи аварія з вантажем лягає на вас. Увімкніть у вікні «Фінанси»."]);
  if(!A.length)A.push(["good","Усе під контролем. Розширюйтеся: нові хаби, техніка, ліцензії."]);return A.slice(0,5)}
const advHint=a=>`<div class="hint" style="${a[0]==="bad"?"border-color:rgba(240,98,95,.4);background:rgba(240,98,95,.07)":a[0]==="warn"?"border-color:rgba(241,196,83,.35);background:rgba(241,196,83,.06)":a[0]==="good"?"border-color:rgba(91,212,146,.35);background:rgba(91,212,146,.06)":""}">${ic(a[0]==="bad"?"alert":a[0]==="good"?"check":"bulb")}<div>${a[1]}</div></div>`;
WINS.coHome=()=>{
  const lm=CO.lm,pr=lm?coRev(lm)-coCost(lm):0,n=LIC[CO.tier+1],lic=coLicOK();const myth=CO_MYTH[(G.date.m+G.date.y)%CO_MYTH.length];
  return `<div class="row sp" style="margin-bottom:12px"><div class="row"><img src="${CO.logo}" alt="" style="width:48px;height:32px;border:1px solid var(--line-hi)"><div><b style="font-size:16px">${esc(CO.name)}</b><div class="note"><span style="cursor:pointer" data-act="coFly" data-arg="${CO.hq}">${ic("pin")} Штаб: ${esc(hqP().name)}</span>, ${esc(G.C[hqP().cid].name)} · ${CO.hubs.length} ${CO.hubs.length===1?"хаб":"хаби"} · ${new Set(CO.hubs.map(h=>PL[h.pid].cid)).size} країн</div></div></div><button class="btn sm" data-act="coRename">${ic("doc")}Перейменувати</button></div>
  <div class="grid4">${stat("Гроші",fmtUSD(CO.cash),"вартість компанії "+fmtUSD(coValue()),T("Гроші","Готівка. Вартість компанії — гроші плюс техніка і хаби мінус кредити."),CO.cash<0?"bad":"")}
  ${stat("Рейтинг",CO.rating.toFixed(2)+" ★",starsH(CO.rating),T("Рейтинг","Середня оцінка клієнтів. Вчасні й цілі доставки його піднімають, аварії, запізнення й крадіжки — опускають."),CO.rating>=4?"good":CO.rating<2.6?"bad":"")}
  ${stat("Досвід",Math.floor(CO.xp||0).toLocaleString("uk-UA"),`${Math.round(CO.deliv).toLocaleString("uk-UA")} доставок · ${CO.cdel} контрактів`,T("Досвід компанії","Росте за кожну успішну доставку з біржі: більше за великі й багатоділянкові рейси, удвічі менше за запізнення. Маршрут, прокладений вручну, дає повний досвід, маршрут диспетчера-логіста — лише 8%. Потрібен для ліцензій."))}
  ${stat("Прибуток / міс",lm?fmtUSD(pr,true):"—",lm?"виручка "+fmtUSD(coRev(lm)):"перший місяць ще триває",T("Прибуток","За минулий місяць."),pr>=0?"good":"bad")}</div>
  ${sect("Порадник")}${coAdvice().map(advHint).join("")}
  ${sect("Ліцензії")}
  <div style="display:flex;flex-direction:column;gap:6px;margin-bottom:10px">${LIC.map((l,i)=>{if(l.hide)return "";const got=i<=CO.tier,cur=i===CO.tier,nx=i===CO.tier+1;
   return `<div class="blk" style="${cur?"border-color:var(--accent)":nx?"border-color:rgba(241,196,83,.45)":""};${!got&&!nx?"opacity:.55":""}"><div class="row sp wrap"><div class="row" style="gap:10px;min-width:0"><span class="${got?"good":nx?"warn":"mut"}">${ic(got?"check":"lock")}</span><div style="min-width:0"><b>${i}. ${l.n}</b><div class="note">${l.d}</div></div></div>
    <span class="pill ${cur?"acc":got?"good":nx?"warn":""}">${cur?"Поточна":got?"Отримано":nx?"Наступна":`${l.rat.toFixed(1)}★ · ${fmtUSD(l.cost)}`}</span></div>
    ${nx?`<div class="kv" style="margin-top:10px">${lic.r.map(x=>`<span class="${x[0]?"good":"mut"}">${ic(x[0]?"check":"lock")} ${x[1]}</span><span class="num ${x[0]?"good":""}">${x[2]}</span>`).join("")}</div>
     <button class="btn ${lic.ok?"pri":""}" style="margin-top:10px" data-act="coLic" ${lic.ok?"":"disabled"}>${ic("doc")}Отримати ліцензію · ${fmtUSD(l.cost)}</button>`:""}</div>`}).join("")}</div>
  <div class="grid2"><div class="blk"><div class="lbl">${ic("coins")}Гроші на кінець місяця</div>${CO.hist.cash.length>1?chart("coc",CO.hist.cash,{fmt:v=>fmtUSD(v),color:"#f0a347",zero:true}):`<div class="note">Графік з'явиться через пару місяців.</div>`}</div>
  <div class="blk"><div class="lbl">${ic("chart")}Виручка за місяць</div>${CO.hist.rev.length>1?chart("cor",CO.hist.rev,{fmt:v=>fmtUSD(v)}):`<div class="note">Графік з'явиться через пару місяців.</div>`}</div></div>
  ${sect("Досягнення")}<div class="grid2">${CO_MS.map(([id,nm,d])=>`<div class="row" style="gap:8px;opacity:${CO.ms.includes(id)?1:.45}"><span class="${CO.ms.includes(id)?"good":"mut"}">${ic(CO.ms.includes(id)?"star":"lock")}</span><div><b>${nm}</b><div class="note">${d}</div></div></div>`).join("")}</div>
  ${sect("Логістичний лікбез")}<div class="myth"><span class="m">МІФ</span><s>${myth[0]}</s><span class="f">ФАКТ</span><span>${myth[1]}</span></div>`;
};
function jobRow(j){const e=coNow()-j.t0,st=coJobState(j,e),T=VT[j.t],cg=j.ret?{n:"повернення в хаб"}:CARGO_I[j.k.cg],A=PL[j.k.from],B=PL[j.k.to];const prog=clamp(e/j.tot,0,1),left=Math.max(0,j.tot-e),lateBy=G.day+left-j.dl;
  return `<div class="lrow" style="cursor:pointer;margin-bottom:6px" data-act="coJob" data-arg="${j.id}"><span class="acc">${ic(T.ic)}</span><div style="min-width:0"><div class="row sp wrap"><b>${plName(A,false)} → ${plName(B,false)}</b><span class="note">${T.n}${j.n>1?" ×"+j.n:""} · ${esc(cg.n)} · ${j.k.tons} т</span></div>
   <div class="meter" style="margin:6px 0 4px"><i data-jp="${j.id}" class="${st.seg<0&&j.hold<=0?"hand":""}" style="width:${(prog*100).toFixed(1)}%;${j.hold>0||j.lost?"background:var(--bad)":""}"></i></div><div class="note">${j.hold>0?`<span class="bad">${j.seized?"Захоплено піратами":"Затримано"} · ще ${j.hold} дн.</span>`:`<span data-jt="${j.id}" class="${st.inc?INC_RED.has(st.inc.k)?"bad":"warn":""}">${esc(st.ph)} · залишилось ${daysS(left)}</span>`}${lateBy>.05?` · <span class="bad">запізнення ${lateBy.toFixed(1)} дн.</span>`:""}${j.lost?` · <span class="bad">вантаж втрачено</span>`:j.dmg>.02?` · <span class="warn">пошкоджено ${(j.dmg*100).toFixed(0)}%</span>`:""}</div></div><span class="num">${fmtUSD(j.k.pay)}</span></div>`}
function chainHTML(k){const out=[];
  if(k.pIn!=null)out.push(`<div class="note" style="margin-top:2px">${ic("handshake")} Відправник сам довезе вантаж із міста ${esc(PL[k.src].name)} до міста ${esc(PL[k.pIn].name)}</div>`);
  if(k.legs)out.push(`<div class="note" style="margin-top:2px">${k.legs.map(L=>`${ic(MODE_IC[L.m])} ${esc(PL[L.a].name)}`).join(" › ")} › ${esc(PL[k.to].name)}</div>`);
  if(k.pOut!=null)out.push(`<div class="note" style="margin-top:2px">${ic("handshake")} Одержувач сам забере вантаж у місті ${esc(PL[k.pOut].name)} і довезе до ${esc(PL[k.dst].name)}</div>`);
  return out.join("")}
const CONS_TIP=T("Збірний рейс","Позначте кілька замовлень одного виду транспорту цією кнопкою — одна машина, потяг, судно чи літак забере й розвезе їх за маршрутом, який ви прокладете. Головне — щоб вага й об'єм усіх вантажів разом вмістилися в кузов і встигнути в дедлайни.");
function boardCard(k,P){const A=PL[k.from],B=PL[k.to],cg=CARGO_I[k.cg],rw=riskW(k.risk);P=P||coPlan(k);const sel=CO_PREV===k.id;
  return `<div class="blk" style="${sel?"border-color:var(--accent)":""}"><div class="row sp wrap"><div class="row" style="min-width:0"><span class="acc">${ic(MODE_IC[k.mode])}</span><div style="min-width:0"><b>${plName(A)} → ${plName(B)}</b><div class="note">${ic(cg.ic)} ${esc(cg.n)} · ${k.tons.toLocaleString("uk-UA")} т · ${(k.tons*(cg.v||3)).toLocaleString("uk-UA",{maximumFractionDigits:1})} м³ · ${kmS(k.len)}${A.cid!==B.cid?" · кордон":""}</div>${kFirms(k)?`<div class="note" style="margin-top:2px">${ic("building")} ${esc(k.fs)} → ${esc(k.ft)}</div>`:""}${chainHTML(k)}</div></div><div style="text-align:right"><b class="num" style="font-size:16px">${fmtUSD(k.pay)}</b><div class="note">термін ${daysS(k.dlDays)}</div></div></div>
  <div class="row wrap" style="gap:6px;margin:8px 0">${k.prem?`<span class="pill warn" data-tip="${T("Термінове замовлення","Відкривається з грейду «Диспетчер». Дедлайн на третину тісніший, зате оплата +40–60%. На біржі висить лише 2–4 дні.")}">${ic("bolt")}Терміново</span>`:""}${k.vip?`<span class="pill acc" data-tip="${T("Ключовий клієнт","Відкривається з грейду «Логіст». Великий постійний відправник: оплата +35%.")}">${ic("crown")}Ключовий клієнт</span>`:""}<span class="pill ${rw[1]}" data-tip="${T("Ризик крадіжки чи нападу","Залежить від країн відправки й призначення (бюрократія, стабільність, війна), від того, наскільки вантаж привабливий для крадіїв (електроніка, ліки, авто — вище), і від піратських вод на морському плечі. Чим вищий ризик — тим дорожче платять. Директор з безпеки знижує шанс інциденту.")}">${ic("shield")}Ризик: ${rw[0].toLowerCase()}</span>${k.minR?`<span class="pill ${CO.rating>=k.minR?"acc":"bad"}">${ic("star")}Вимога ${k.minR.toFixed(1)}★</span>`:""}${cg.aid?`<span class="pill warn">${ic("heart")}Зона конфлікту</span>`:""}${permNeed(cg,k.mode).map(id=>`<span class="pill ${permOK(id)?"good":"bad"}" data-tip="${T(PERM_I[id].n,PERM_I[id].d)}">${ic(PERM_I[id].ic)}${id==="adr"||id==="imdg"||id==="dgr"?"Небезпечний вантаж":id==="gdp"?"Фарма":id==="valu"?"Цінності":id==="expl"?"Вибухівка":"Радіоактивний"}</span>`).join("")}${cg.reefer&&k.mode==="sea"?`<span class="pill">${ic("leaf")}Рефконтейнер</span>`:""}<span class="pill" data-tip="${T("Термін пропозиції","Скільки днів замовлення ще висітиме на біржі. Потім замовник віддасть його іншому перевізнику і воно зникне. Це не дедлайн доставки — дедлайн рахується з моменту, коли ви приймете замовлення.")}">${ic("info")}${Math.max(0,k.exp-G.day)} дн. на біржі</span></div>
  ${P.ok?`<div class="row sp wrap"><div class="note">${P.chain?P.chain.map(q=>VT[q.t].n+(q.n>1?" ×"+q.n:"")).join(" → "):VT[P.t].n+(P.n>1?" ×"+P.n:"")} · ${P.lead>.05?"перегін "+kmS(P.lead)+" · ":""}доставка за ${daysS(P.tot)} ${P.late?`<span class="bad">— запізнення!</span>`:`<span class="good">— вчасно</span>`} · пальне ${fmtUSD(P.fuel)} · прибуток ≈ <b class="${P.profit>0?"good":"bad"}">${fmtUSD(P.profit,true)}</b></div>
   <div class="row">${typeof consOK==="function"&&consOK(k)?`<button class="btn sm ${UI.cons&&UI.cons.includes(k.id)?"pri":""}" data-act="consAdd" data-arg="${k.id}" data-tip="${CONS_TIP}">${ic(UI.cons&&UI.cons.includes(k.id)?"check":"plus")}${UI.cons&&UI.cons.includes(k.id)?"У збірному":"До збірного рейсу"}</button>`:""}<button class="btn sm" data-act="coShow" data-arg="${k.id}">${ic("mapIc")}${sel?"Сховати":"На мапі"}</button>${lpOn()?`<button class="btn sm pri" data-act="lpPlan" data-arg="${k.id}">${ic("road")}Прокласти маршрут</button>`:`<button class="btn sm pri" data-act="coSend" data-arg="${k.id}">${ic("send")}Відправити</button>`}</div></div>`
  :`<div class="bdwhy"><span class="note warn">${/^Замовник хоче рейтинг|^Немає вільної техніки/.test(P.why)||permNeed(cg,k.mode).some(id=>!permOK(id))&&/^Потрібна ліцензія «/.test(P.why)?"":ic("alert")+" "+esc(P.why)}</span><div class="row">${typeof consOK==="function"&&consOK(k)?(/^Немає вільної техніки/.test(P.why)&&!(UI.cons&&UI.cons.includes(k.id))?`<button class="btn sm" style="opacity:.45;cursor:not-allowed" aria-disabled="true" data-act="consNo" data-arg="${k.id}" data-tip="${T("Збірний рейс недоступний",esc(P.why)+". Дочекайтеся, поки техніка звільниться, або купіть ще в «Автопарку».")}">${ic("plus")}До збірного рейсу</button>`:`<button class="btn sm ${UI.cons&&UI.cons.includes(k.id)?"pri":""}" data-act="consAdd" data-arg="${k.id}" data-tip="${CONS_TIP}">${ic(UI.cons&&UI.cons.includes(k.id)?"check":"plus")}${UI.cons&&UI.cons.includes(k.id)?"У збірному":"До збірного рейсу"}</button>`):""}<button class="btn sm" data-act="coShow" data-arg="${k.id}">${ic("mapIc")}${sel?"Сховати":"На мапі"}</button>${lpOn()?`<button class="btn sm" style="opacity:.45;cursor:not-allowed" aria-disabled="true" data-act="lpPlanNo" data-arg="${k.id}" data-tip="${T("Маршрут не прокласти",esc(P.why)+".")}">${ic("road")}Прокласти маршрут</button>`:""}</div></div>`}</div>`}
WINS.coJobs=()=>{
  if(CO.tier<1)return `<div class="locked-hero">${ic("lock")}<h4>Біржа вантажів закрита</h4><p class="note" style="max-width:420px;margin:0 auto">Потрібна ліцензія «${LIC[1].n}».</p></div>
`;
  const jf=UI.jfl||"all",mOK=m=>jf==="all"||m===jf,modes=[["all","Усі",""],["road","Авто","truck"],["rail","Залізниця","train"],["sea","Море","ship"],["air","Авіа","plane"]];
  const jobs=CO.jobs.filter(j=>mOK(j.mode)),bd=CO.board.filter(k=>mOK(k.mode)),tds=CO.tenders.filter(t=>mOK(VT[t.t].mode)),tof=(CO.toff||[]).filter(o=>o.exp>G.day&&mOK(VT[o.t].mode)),last=CO.last.filter(l=>mOK(l.mode));
  const board=bd.slice().sort((a,b)=>b.id-a.id).map(k=>({k,P:coPlan(k)}));
  const cnt=m=>m==="all"?CO.jobs.length+CO.board.length:CO.jobs.filter(j=>j.mode===m).length+CO.board.filter(k=>k.mode===m).length;
  const tdRow=o=>{const T=VT[o.t],idle=CO.veh.filter(v=>v.t===o.t&&v.st==="idle").length,ok=idle>=o.n;return `<div class="blk"><div class="row sp wrap"><div class="row" style="min-width:0"><span class="acc">${ic(T.ic)}</span><div style="min-width:0"><b>Контракт ${esc(o.n_)}</b><div class="note">${o.n} × ${T.n.toLowerCase()} з екіпажами · ${o.months} міс. · пропозиція діє ще ${Math.max(1,Math.round(o.exp-G.day))} дн.</div></div></div><div style="text-align:right"><b class="num" style="font-size:16px">${fmtUSD(o.pay*o.n)}/міс</b><div class="note">разом ${fmtUSD(o.pay*o.n*o.months)}</div></div></div>
    <div class="row sp wrap" style="margin-top:8px"><span class="note ${ok?"good":"warn"}">${ok?`${ic("check")} Вільно ${idle} з ${o.n} потрібних`:`${ic("alert")} Потрібно ${o.n}, вільно ${idle}: купіть техніку в «Автопарку»`}</span><div class="row"><button class="btn sm" data-act="coTdX" data-arg="${o.id}" aria-label="Відхилити">${ic("trash")}</button><button class="btn sm ${ok?"pri":""}" data-act="coTd" data-arg="${o.id}" ${ok?"":"disabled"}>${ic("doc")}Підписати</button></div></div></div>`};
  return `<div class="grid3">${stat("Досвід",Math.floor(CO.xp||0).toLocaleString("uk-UA"),"за маршрути, прокладені вручну",T("Досвід","Ручне прокладання дає повний досвід, диспетчер-логіст — лише 8%."))}
  ${stat("На біржі",CO.board.length,"до "+coBoardMax()+" одночасно",T("Біржа","Замовлення з'являються в містах, де у вас є хаби. Більше хабів і складів, комерційний директор — більше замовлень."))}
  ${stat("Тендери",CO.tenders.length,CO.tenders.reduce((a,t)=>a+t.n,0)+" од. техніки зайнято",T("Тендери","Довгострокові контракти: стабільний дохід щомісяця."))}</div>
  <div class="seg" style="margin:4px 0 12px;flex-wrap:wrap">${modes.map(([k,n,i])=>`<button class="${jf===k?"on":""}" data-act="coJf" data-arg="${k}">${i?ic(i):""} ${n} · ${cnt(k)}</button>`).join("")}</div>
  ${sect("Біржа вантажів")}<div class="row sp" style="padding:10px 12px;border:1px solid var(--line);background:var(--glass-lo);margin-bottom:12px"><div><b>Автодиспетчеризація</b><div class="note">${CO.mgr.cto?"Диспетчер-логіст сам бере замовлення й прокладає маршрути. Досвіду компанії за такі рейси майже немає.":"Потрібен диспетчер-логіст (вікно «Персонал»)."}</div></div><button class="tg ${CO.auto?"on":""}" data-act="coAutoT" aria-label="Автодиспетчеризація"></button></div>
  ${typeof consPanel==="function"?consPanel():""}
  ${board.length?(()=>{const n=Math.max(UI.bmore||15,15),pin=UI.jpin;let show=board.slice(0,n);if(pin&&pin.kind==="board"&&!show.some(x=>x.k.id===pin.id)){const k=CO.board.find(x=>x.id===pin.id);if(k)show=[{k,P:coPlan(k)}].concat(show)}
    return `<div style="display:flex;flex-direction:column;gap:8px">${show.map(x=>boardCard(x.k,x.P)).join("")}</div>${board.length>n?`<button class="btn sm" style="margin-top:8px" data-act="coBmore">Показати ще ${Math.min(15,board.length-n)} з ${board.length-n}</button>`:""}`})():`<div class="note">Нових замовлень${jf!=="all"?" цього типу":""} поки немає — вони з'являються щодня.</div>`}
  ${sect("Тендери")}<div class="hint">${ic("info")}<div><b>Як працюють тендери.</b> Компанія-замовник наймає вашу техніку з екіпажами на кілька місяців. Поки діє контракт, ці машини не беруть інших рейсів, а ви щомісяця отримуєте фіксовану оплату за кожну одиницю. Нові пропозиції з'являються на початку місяця з ліцензією «Вантажні перевезення» і діють 3–6 тижнів. Щоб підписати тендер, потрібна вільна техніка потрібного типу.</div></div>
  ${CO.tier<2?`<div class="note">${ic("lock")} Тендери відкриються з ліцензією «Вантажні перевезення».</div>`:""}
  ${tds.length?`<span class="lbl" style="display:block;margin:6px 0">Діючі контракти</span>`+tds.map(t=>`<div class="lrow" style="margin-bottom:6px"><span class="acc">${ic(VT[t.t].ic)}</span><div><b>Контракт ${esc(t.n_)}</b><div class="note">${t.n} × ${VT[t.t].n.toLowerCase()} · ще ${t.left} міс.</div></div><span class="num good">${fmtUSD(t.pay*t.n)}/міс</span></div>`).join(""):""}
  ${CO.tier>=2?(tof.length?`<span class="lbl" style="display:block;margin:10px 0 6px">Пропозиції</span><div style="display:flex;flex-direction:column;gap:8px">${tof.map(tdRow).join("")}</div>`:`<div class="note">Нових пропозицій${jf!=="all"?" цього типу":""} зараз немає — наступні з'являться на початку місяця.</div>`):""}`;
};
WINS.coTrips=()=>{
  const jf=UI.jfl||"all",mOK=m=>jf==="all"||m===jf,modes=[["all","Усі",""],["road","Авто","truck"],["rail","Залізниця","train"],["sea","Море","ship"],["air","Авіа","plane"]];
  const jobs=CO.jobs.filter(j=>mOK(j.mode)),last=CO.last.filter(l=>mOK(l.mode)),cnt=m=>m==="all"?CO.jobs.length:CO.jobs.filter(j=>j.mode===m).length;
  return `<div class="grid3">${stat("У дорозі",CO.jobs.filter(j=>!j.ret).length,CO.veh.filter(v=>v.st==="trip").length+" од. техніки",T("Рейси","Техніка, що зараз везе вантаж або їде по нього."))}
  ${stat("Повертаються в хаб",CO.jobs.filter(j=>j.ret).length,"порожні пробіги додому","")}${stat("Доставлено",CO.cdel.toLocaleString("uk-UA"),Math.round(CO.tons).toLocaleString("uk-UA")+" т","")}</div>
  <div class="seg" style="margin:4px 0 12px;flex-wrap:wrap">${modes.map(([k,n,i])=>`<button class="${jf===k?"on":""}" data-act="coJf" data-arg="${k}">${i?ic(i):""} ${n} · ${cnt(k)}</button>`).join("")}</div>
  ${(()=>{const L=jobs.slice().sort((a,b)=>b.t0-a.t0),n=Math.max(UI.jmore||15,15),pin=UI.jpin,show=L.slice(0,n);if(pin&&pin.kind==="job"){const j=CO.jobs.find(x=>x.id===pin.id);if(j&&!show.includes(j))show.unshift(j)}
    return sect(`У дорозі · ${CO.jobs.length}`)+(show.length?show.map(jobRow).join("")+(L.length>n?`<button class="btn sm" style="margin-top:4px" data-act="coJmore">Показати ще ${Math.min(15,L.length-n)} з ${L.length-n}</button>`:""):`<div class="note">Немає активних рейсів${jf!=="all"?" цього типу":""}.</div>`)})()}
  ${last.length?sect("Останні доставки")+`<div class="tbwrap"><table class="tb"><tbody>${last.slice(0,10).map(l=>`<tr><td class="note">${dateStr(l.d)}</td><td>${ic(MODE_IC[l.mode])} ${esc(PL[l.from].name)} → ${esc(PL[l.to].name)}</td><td class="note">${esc(CARGO_I[l.cg].n)}</td><td class="r num ${l.tone}">${fmtUSD(l.pay,true)}</td></tr>`).join("")}</tbody></table></div>`:""}`;
};
WINS.coFleet=()=>{
  const ff=UI.ffl||"all",fOK=t=>ff==="all"||VT[t].mode===ff;
  const groups={};for(const v of CO.veh){if(!fOK(v.t))continue;const k=v.t+":"+v.loc+":"+v.st;(groups[k]=groups[k]||[]).push(v)}
  const ST={idle:["Вільна","good"],trip:["У рейсі","acc"],tender:["Тендер","warn"]};
  const rows=Object.values(groups).sort((a,b)=>VT[b[0].t].cost-VT[a[0].t].cost);
  const hubOpts=CO.hubs.map(h=>({v:h.pid,l:PL[h.pid].name,ic:"building"}));
  return `<div class="grid3">${stat("Техніка",CO.veh.length,`${CO.veh.filter(v=>v.st==="idle").length} вільні`,"")}${stat("Вартість парку",fmtUSD(CO.veh.reduce((a,v)=>a+VT[v.t].cost*(.35+.4*v.cond/100),0)),"за ринковою оцінкою","")}
  ${stat("Середній стан",(CO.veh.length?CO.veh.reduce((a,v)=>a+v.cond,0)/CO.veh.length:100).toFixed(0)+"%","зношена техніка частіше ламається",T("Стан техніки","Знижується з кожним кілометром. Нижче 45% — більше аварій і поломок, ризик штрафу на техогляді."))}</div>
  <div class="row sp wrap" style="margin-bottom:12px"><div><span class="lbl">Обслуговування</span><div class="seg" style="margin-top:6px">${["Економне","Стандартне","Преміальне"].map((n,i)=>`<button class="${CO.maint===i?"on":""}" data-act="coMaint" data-arg="${i}">${n}</button>`).join("")}</div></div>
   <div style="min-width:200px"><span class="lbl">Нова техніка прибуває в</span><div style="margin-top:6px">${dd("coBuyAt",hubOpts,CO.buyAt??CO.hq,v=>ACT.coBuyAt(v))}</div></div></div>
  <div class="note" style="margin:-4px 0 12px">Економне: дешевше утримання, але техніка зношується швидше й частіше ламається. Преміальне — навпаки.</div>
  <div class="seg" style="margin:4px 0 10px;flex-wrap:wrap">${[["all","Уся",""],["road","Авто","truck"],["rail","Залізниця","train"],["sea","Море","ship"],["air","Авіа","plane"]].map(([k,n,i])=>{const c=k==="all"?CO.veh.length:CO.veh.filter(v=>VT[v.t].mode===k).length;return `<button class="${ff===k?"on":""}" data-act="coFfl" data-arg="${k}">${i?ic(i):""} ${n} · ${c}</button>`}).join("")}</div>
  ${sect("Ваша техніка")}<div class="tbwrap"><table class="tb"><thead><tr><th>Тип</th><th>Де</th><th>Стан</th><th>Статус</th><th class="r">Дії</th></tr></thead><tbody>
  ${rows.slice(0,UI.fmore||120).map(g=>{const v=g[0],Ty=VT[v.t],cond=g.reduce((a,x)=>a+x.cond,0)/g.length;const p=PL[v.loc];return `<tr><td><span class="row">${ic(Ty.ic)}<b>${Ty.n}</b>${g.length>1?`<span class="pill">×${g.length}</span>`:""}${(Ty.mode==="road"||Ty.mode==="rail")&&typeof ACT.coMove==="function"?`<button class="btn sm icon" style="padding:3px 5px" data-act="coMove" data-arg="${v.id}" data-tip="${T("Перемістити в інший хаб","Покаже на мапі всі ваші хаби — клікніть, щоб приписати техніку туди. Лише по дорозі"+(Ty.mode==="rail"?" (залізниці)":"")+": на інший континент не перемістити."+(v.home!=null&&PL[v.home]?" Зараз приписана: "+PL[v.home].name+".":""))}">${ic("updown")}</button>`:""}</span></td><td class="note">${v.st==="trip"?"в дорозі":esc(p.name)}</td><td style="width:110px"><div class="meter"><i style="width:${cond}%;background:var(--${cond>65?"good":cond>40?"warn":"bad"})"></i></div></td><td><span class="pill ${ST[v.st][1]}">${ST[v.st][0]}</span></td>
   <td class="r">${v.st==="idle"?`<span class="row" style="justify-content:flex-end;gap:4px">${cond<99?`<button class="btn sm" data-act="coRepair" data-arg="${v.t}:${v.loc}">${ic("gear")}Ремонт</button>`:""}<button class="btn sm" data-act="coSell" data-arg="${v.t}:${v.loc}" data-tip="${T("Продати одну","≈ "+fmtUSD(Ty.cost*(.25+.35*v.cond/100)))}">${ic("coins")}Продати</button></span>`:""}</td></tr>`}).join("")||`<tr><td colspan="5" class="note">Техніки немає.</td></tr>`}</tbody></table></div>${rows.length>(UI.fmore||120)?`<button class="btn sm" style="margin-top:8px" data-act="coFmore">Показати ще ${Math.min(120,rows.length-(UI.fmore||120))} з ${rows.length-(UI.fmore||120)}</button>`:""}
  ${sect("Купити")}<div class="grid2">${Object.entries(VT).filter(([t])=>fOK(t)).sort((a,b)=>a[1].tier-b[1].tier||a[1].cost-b[1].cost).map(([t,T])=>{const lock=CO.tier<T.tier;return `<div class="blk" style="${lock?"opacity:.5":""}"><div class="row sp"><div class="row"><span class="acc" style="font-size:20px">${ic(T.ic)}</span><div><b>${T.n}</b><div class="note">${MODE_N[T.mode]}${T.cap?` · до ${T.cap.toLocaleString("uk-UA")} т`:""}${T.vol?` · ${T.vol.toLocaleString("uk-UA")} м³`:""}${T.loc?" · доставка по місту":""}</div></div></div><b class="num">${fmtUSD(T.cost)}</b></div>
   <div class="note" style="margin:6px 0">${T.d} Екіпаж: ${T.crew||1} (${ROLE[T.role].n.toLowerCase()}). Утримання ${fmtUSD(T.up*30)}/міс.</div>
   ${lock?`<span class="pill">${ic("lock")}Ліцензія «${LIC[T.tier].n}»</span>`:`<button class="btn sm ${CO.cash>=T.cost?"pri":""}" data-act="coBuy" data-arg="${t}" ${CO.cash>=T.cost?"":"disabled"}>${ic("plus")}Купити</button>`}</div>`}).join("")}</div>`;
};
WINS.coNet=()=>{
  const recs=PL.filter(p=>!hubAt(p.id)&&coScope(p)).sort((a,b)=>b.pop-a.pop).slice(0,8);
  return `<div class="hint">${ic("bulb")}<div>Хаб — база вашої техніки в місті: звідси машини виїздять на рейси й сюди повертаються. Він дає <b>місцевий ринок доставок</b>, а підприємства навколо частіше дають <b>замовлення</b>. Рівні: 1, 2, 3, а хаб 3 рівня можна перетворити на <b>Логістичний хаб</b>. Щоб відкрити хаб, клацніть на країну на мапі або оберіть місто зі списку нижче.</div></div>
  ${sect("Ваші хаби")}<div style="display:flex;flex-direction:column;gap:8px">${CO.hubs.map(h=>{const p=PL[h.pid],q=h.want>0?Math.min(1,h.cap/h.want):1;const up=h.lvl<4?hubCost(p)*HUB_UP[h.lvl]:0;
   return `<div class="blk"><div class="row sp wrap"><div class="row"><span class="acc">${ic(h.pid===CO.hq?"star":"building")}</span><div><b style="cursor:pointer" data-act="coGoto" data-arg="${p.id}">${plName(p)}</b><div class="note">${HUB_LV[h.lvl]} · ${({cap:"столиця",big:"велике місто",city:"місто",town:"містечко"})[p.type]} · ${fmtSP(p.pop)} · ${[p.air?"аеропорт":"",p.port!=null?"порт":"",p.rail?"залізниця":""].filter(Boolean).join(", ")||"тільки автодороги"}</div></div></div>
    <div class="row">${h.lvl<4?`<button class="btn sm" data-act="coHubUp" data-arg="${p.id}" data-tip="${T(HUB_LV[h.lvl+1],`Техніки в хабі: ${HUB_VEH[h.lvl]} → ${HUB_VEH[h.lvl+1]}. Робочих місць: +${HUB_STAFF[h.lvl+1]-HUB_STAFF[h.lvl]}. Завантаження й розвантаження ${Math.round((1-HUB_HAND[h.lvl+1])*100)}% швидше. Замовлень від підприємств поблизу ×${HUB_ORD[h.lvl+1]}. Більша частка міського ринку і +1 місце на біржі. Оренда ${fmtUSD(HUB_RENT[h.lvl+1]*priceK(p.cid))}/міс.`)}">${ic("up")}${HUB_LV[h.lvl+1]} · ${fmtUSD(up)}</button>`:""}${h.pid!==CO.hq?`<button class="btn sm" data-act="coHubClose" data-arg="${p.id}" aria-label="Закрити хаб">${ic("trash")}</button>`:""}</div></div>
    <div class="grid3" style="margin-top:10px">${stat("Попит",Math.round(h.want||0)+"/день","частка ринку "+((h.share||0)*100).toFixed(1)+"%",T("Попит на ваші доставки","Залежить від населення, багатства міста, вашого рейтингу, реклами і рівня хабу."))}${stat("Потужність",Math.round(h.cap||0)+"/день",(h.nloc||0)+" од. техніки",T("Потужність","Скільки посилок встигають розвезти фургони й вантажні машини, що стоять у хабі цього міста."),q<.6?"warn":"")}${stat("Розвезено",Math.round(h.served||0)+"/день",fmtUSD((h.served||0)*4.2*priceK(p.cid))+"/день","")}</div>
    <div class="row wrap" style="gap:6px 14px;margin-top:8px"><span class="note ${hubVehN(p.id)>=hubVehCap(h)?"warn":""}">${ic("truck")} Техніка ${hubVehN(p.id)} / ${HUB_VEH[h.lvl]}</span><span class="note">${ic("users")} Робочих місць ${HUB_STAFF[h.lvl]}</span><span class="note">${ic("box")} Завантаження ${h.lvl>1?"−"+Math.round((1-HUB_HAND[h.lvl])*100)+"%":"звичайне"}</span><span class="note">${ic("doc")} Замовлень ×${HUB_ORD[h.lvl]}</span></div>
    <div class="row sp" style="margin-top:8px"><span class="note">Реклама в місті</span>${dd("mk"+p.id,[0,500,2000,8000,30000].map(v=>({v,l:v?fmtUSD(v)+"/міс":"Без реклами",ic:"spark"})),h.mk||0,v=>ACT.coMk(p.id+":"+v))}</div></div>`}).join("")}</div>
  ${sect("Де відкрити наступний хаб")}${CO.tier<1?`<div class="note">${ic("lock")} Нові хаби відкриваються з ліцензією «Міжміська доставка».</div>`:`<div class="tbwrap"><table class="tb"><tbody>${recs.map(p=>`<tr><td><b style="cursor:pointer" data-act="coGoto" data-arg="${p.id}">${plName(p)}</b><div class="note">${({cap:"Столиця",big:"Велике місто",city:"Місто",town:"Містечко"})[p.type]} · ${fmtSP(p.pop)}</div></td><td class="note">${[p.air?ic("plane"):"",p.port!=null?ic("anchor"):"",p.rail?ic("train"):""].join(" ")}</td><td class="r"><button class="btn sm ${CO.cash>=hubOpenCost(p)?"pri":""}" data-act="coHub" data-arg="${p.id}" ${CO.cash>=hubOpenCost(p)?"":"disabled"}>${ic("plus")}${hubAbroad(p)?"Оренда ":""}${fmtUSD(hubOpenCost(p))}</button></td></tr>`).join("")}</tbody></table></div>`}
  ${sect("Ліцензії")}${LIC.map((l,i)=>l.hide?"":`<div class="row" style="gap:10px;padding:6px 0;border-bottom:1px solid var(--line);opacity:${i<=CO.tier?1:.55}"><span class="${i<=CO.tier?"good":"mut"}">${ic(i<=CO.tier?"check":"lock")}</span><div><b>${i}. ${l.n}</b><div class="note">${l.d}</div></div></div>`).join("")}`;
};
WINS.coStaff=()=>{
  const need=coCrewNeed(),wk=wageK(G.me)*CO.wageLv;
  const stN=Object.values(CO.staff).reduce((a,b)=>a+b,0);return `<div class="grid3">${stat("Персонал",stN+CO.founder,SET.sandbox?"":`робочих місць ${stN} / ${staffCap()}`,T("Робочі місця","Кожен хаб дає робочі місця: 1 рівень 12, 2 рівень 40, 3 рівень 150, логістичний хаб 400. Щоб наймати більше людей, покращуйте хаби або відкривайте нові."),!SET.sandbox&&stN>=staffCap()?"warn":"")}${stat("Моральний дух",CO.morale.toFixed(0)+"/100",CO.morale<35?"ризик страйку":CO.morale>70?"команда задоволена":"нормально",T("Моральний дух","Залежить від зарплат, перевантаження і HR-директора. Впливає на аварії, якість і страйки."),CO.morale<35?"bad":CO.morale>65?"good":"warn")}
  ${stat("Фонд оплати",fmtUSD(Object.keys(ROLE).reduce((a,r)=>a+(CO.staff[r]||0)*ROLE[r].w*wk,0))+"/міс","без менеджменту","")}</div>
  <div class="blk"><div class="row sp"><span class="lbl">Рівень зарплат відносно ринку</span><span class="num" id="coWv">${Math.round(CO.wageLv*100)}%</span></div><input class="rng" type="range" min="80" max="180" step="5" value="${Math.round(CO.wageLv*100)}" data-live="coWageLive" data-commit="coWageSet" style="width:100%;margin-top:8px"><div class="note" style="margin-top:6px">Нижче 100% — економія, але падає дух і ростуть аварії. Вище — дорожче, зате надійно.</div></div>
  ${sect("Працівники")}<div class="tbwrap"><table class="tb"><thead><tr><th>Роль</th><th>Є</th><th>Потрібно</th><th>Зарплата</th><th data-tip="${T("Ринок праці","Скільки людей готові прийти до вас цього місяця. Поповнюється щомісяця: більше при вищих зарплатах, з HR-директором і великою мережею хабів.")}">Кандидати</th><th class="r">Найм</th></tr></thead><tbody>
  ${Object.entries(ROLE).map(([r,R_])=>{const have=(CO.staff[r]||0)+(r==="driver"?CO.founder:0),lack=need[r]-have;return `<tr><td><span class="row">${ic(R_.ic)}<b>${R_.n}</b></span></td><td class="num">${have}</td><td class="num ${lack>0?"bad":""}">${need[r]}</td><td class="note">${fmtUSD(R_.w*wk)}/міс</td><td class="num ${(CO.pool[r]||0)>0?"":"mut"}">${CO.pool[r]||0}</td>
   <td class="r"><span class="row" style="justify-content:flex-end;gap:4px"><button class="btn sm" data-act="coHire" data-arg="${r}:-1" aria-label="Звільнити">${ic("minus")}</button><button class="btn sm" data-act="coHire" data-arg="${r}:1">${ic("plus")}1</button><button class="btn sm ${lack>0?"pri":""}" data-act="coHire" data-arg="${r}:${Math.max(5,lack)}">${ic("plus")}${Math.max(5,lack)}</button></span></td></tr>`}).join("")}</tbody></table></div>
  <div class="note" style="margin-top:6px">Найм коштує пів місячної зарплати (оголошення, навчання). Звільнення — місячна компенсація. Що більше людей, то дорожчі офіс, бухгалтерія й диспетчери.</div>
  ${sect("Топменеджмент")}<div class="ministers" style="display:flex;flex-direction:column;gap:10px">${MG.map(s=>{const g=CO.mgr[s.id];
   if(g)return `<div class="mcard"><div class="avatar">${initials(g.name)}</div><div style="min-width:0"><div class="row sp wrap"><div><div class="row" style="gap:6px"><span class="acc">${ic(s.ic)}</span><b>${s.n}</b></div><div class="note">${esc(g.name)}, ${g.age} · ${esc(g.trait)} · навичка ${"★".repeat(Math.round(g.skill/2))}${"☆".repeat(5-Math.round(g.skill/2))} · лояльність ${g.loyal}</div><div class="note">${s.d}</div></div><div class="row"><span class="num">${fmtUSD(g.sal)}/міс</span><button class="btn sm dng" data-act="coFireM" data-arg="${s.id}">Звільнити</button></div></div></div></div>`;
   const cs=CO.cand[s.id]||[];return `<div class="blk"><div class="row sp"><div class="row" style="gap:6px"><span class="mut">${ic(s.ic)}</span><b>${s.n}</b><span class="pill">вакансія</span></div><button class="btn sm" data-act="coRecand" data-arg="${s.id}">${ic("refresh")}Інші кандидати · ${fmtUSD(1500*priceK(G.me))}</button></div><div class="note" style="margin:4px 0 8px">${s.d}</div>
    ${cs.map((g,i)=>`<div class="row sp" style="padding:6px 0;border-top:1px solid var(--line)"><div><b>${esc(g.name)}</b>, ${g.age} <span class="note">· ${esc(g.trait)} · навичка ${"★".repeat(Math.round(g.skill/2))}${"☆".repeat(5-Math.round(g.skill/2))}</span></div><div class="row"><span class="num">${fmtUSD(g.sal)}/міс</span><button class="btn sm ${CO.cash>=g.sal?"pri":""}" data-act="coHireM" data-arg="${s.id}:${i}" ${CO.cash>=g.sal?"":"disabled"}>Найняти</button></div></div>`).join("")}</div>`}).join("")}</div>
  <div class="note" style="margin-top:8px">Чесність кандидата не видно в резюме. Нечесний менеджер потроху виводить гроші — ловить їх тільки фінансовий директор.</div>`;
};
/* what the end of the month will charge: payroll, office, managers, rent, ads, insurance, interest */
function coMonthPlan(){const wk=wageK(G.me)*CO.wageLv*(1-msk("hro")*.08);let wage=0,mgmt=0,rent=0,mk=0,ins=0,interest=0;for(const r in ROLE)wage+=(CO.staff[r]||0)*ROLE[r].w*wk;
  const N=Object.values(CO.staff).reduce((a,b)=>a+b,0),office=Math.round(45*Math.pow(N,1.12)*priceK(G.me)*(1-msk("cfo")*.1));for(const id in CO.mgr)mgmt+=CO.mgr[id].sal;
  for(const h of CO.hubs){rent+=hubRentM(h);mk+=h.mk||0}if(CO.ins)ins=Math.round(500+CO.veh.reduce((a,v)=>a+VT[v.t].cost,0)*.0035);
  for(const l of CO.loans)interest+=l.left*l.rate/12;if(CO.cash<0)interest+=-CO.cash*.025;return{wage,office,mgmt,rent,mk,ins,interest}}
WINS.coFin=()=>{
  const m=CO.m,l=CO.lm,PLN=coMonthPlan();const rows=[["Доставки по країні","local",1],["Офіс, бухгалтерія, диспетчери","office",-1],["Міжнародні перевезення","contract",1],["Тендери","tender",1],["Зарплати і найм","wage",-1],["Менеджмент","mgmt",-1],["Пальне","fuel",-1],["Утримання і ремонт","upkeep",-1],["Оренда хабів","rent",-1],["Податок за чужі хаби","hubtax",-1],["Реклама","mk",-1],["Страхування","ins",-1],["Відсотки","interest",-1],["Претензії й збитки","claims",-1],["Інше (штрафи, втрати)","other",-1]];
  const debt=CO.loans.reduce((a,x)=>a+x.left,0),lim=coCredit();const rank=coRank();const my=coYearRev();
  const lb=[...CO.comp.map(c=>({n:c.n,rev:c.rev})),{n:CO.name,rev:my,me:true}].sort((a,b)=>b.rev-a.rev);
  return `<div class="grid4">${stat("Гроші",fmtUSD(CO.cash),"",T("Гроші",""),CO.cash<0?"bad":"")}${stat("Кредити",fmtUSD(debt),"ставка "+(coRate()*100).toFixed(1)+"%",T("Кредити","Повертаються рівними частинами за 24 місяці. Ставка залежить від рейтингу і фінансового директора."))}${stat("Кредитний ліміт",fmtUSD(lim),"",T("Ліміт","Залежить від вартості компанії і виручки."))}${stat("Місце у світі",rank+" з "+(CO.comp.length+1),"за річною виручкою",T("Рейтинг компаній","Порівняння з найбільшими логістичними компаніями світу."),rank===1?"good":"")}</div>
  ${sect("Прибутки і витрати")}<div class="note" style="margin-bottom:8px">Зарплати, офіс, менеджмент, оренда, реклама, страхування й відсотки списуються одним платежем в останній день місяця. До того в колонці «Цей місяць» видно очікувану суму. Одноразові витрати (найм, звільнення) списуються одразу.</div><div class="tbwrap"><table class="tb"><thead><tr><th>Стаття</th><th class="r">Цей місяць</th><th class="r">Минулий</th></tr></thead><tbody>
  ${rows.map(([n,k,s])=>`<tr><td>${n}</td><td class="r num ${s>0?"good":""}">${m[k]?fmtUSD(s*m[k],true):PLN[k]?"":"—"}${PLN[k]?`<div class="note" style="font-size:11px">${m[k]?"+ ":""}≈ ${fmtUSD(-PLN[k],true)} в кінці місяця</div>`:""}</td><td class="r num">${l&&l[k]?fmtUSD(s*l[k],true):"—"}</td></tr>`).join("")}
  <tr><td><b>Разом</b></td><td class="r num"><b>${fmtUSD(coRev(m)-coCost(m),true)}</b></td><td class="r num"><b>${l?fmtUSD(coRev(l)-coCost(l),true):"—"}</b></td></tr></tbody></table></div>
  <div class="note" style="margin-top:6px">Зарплати, оренда, реклама, страховка і кредити списуються на початку місяця.</div>
  ${sect("Кредити і страхування")}<div class="row wrap" style="gap:8px;margin-bottom:10px"><button class="btn sm" data-act="coLoan" data-arg=".25">${ic("plus")}Кредит ${fmtUSD(Math.max(0,(lim-debt)*.25))}</button><button class="btn sm" data-act="coLoan" data-arg="1">${ic("plus")}Весь ліміт ${fmtUSD(Math.max(0,lim-debt))}</button><button class="btn sm" data-act="coRepay" ${debt>0?"":"disabled"}>${ic("check")}Погасити достроково</button></div>
  <div class="row sp" style="padding:10px 12px;border:1px solid var(--line);background:var(--glass-lo)"><div><b>Страхування вантажів</b><div class="note">Покриває 80% претензій за викрадені й пошкоджені вантажі. ≈ ${fmtUSD(500+CO.veh.reduce((a,v)=>a+VT[v.t].cost,0)*.0035)}/міс.</div></div><button class="tg ${CO.ins?"on":""}" data-act="coIns" aria-label="Страхування"></button></div>
  ${sect("Найбільші логістичні компанії світу")}<div class="tbwrap"><table class="tb"><tbody>${lb.map((c,i)=>`<tr style="${c.me?"background:rgba(255,179,71,.08)":""}"><td class="num" style="width:30px">${i+1}</td><td>${c.me?`<b class="warn">${esc(c.n)}</b>`:esc(c.n)}</td><td class="r num">${fmtUSD(c.rev)}/рік</td></tr>`).join("")}</tbody></table></div>`;
};

/* ---------- country card (inspector) ---------- */
function coInsp(){
  const k=UI.sel;if(k==null)return;const c=G.C[k],el=$("#insp");el.hidden=false;
  const sp=G.board&&UI.selP!=null&&PL[UI.selP]&&PL[UI.selP].cid===k?PL[UI.selP]:null;
  const pls=sp?PL.slice().sort((a,b)=>Math.hypot(a.x-sp.x,a.z-sp.z)-Math.hypot(b.x-sp.x,b.z-sp.z)).slice(0,10):PL.filter(p=>p.cid===k).sort((a,b)=>({cap:0,big:1,city:2,town:3}[a.type]-{cap:0,big:1,city:2,town:3}[b.type])||b.pop-a.pop);
  const rw=RISK_N[riskLvl(k)],conf=CO.conf.filter(x=>x.a===k||x.b===k),pir=CO.pir.filter(z=>z.cid===k);
  const body=`${conf.length?`<div class="hint" style="border-color:rgba(240,98,95,.4);background:rgba(240,98,95,.07)">${ic("swords")}<div><b>Прикордонний конфлікт</b> з ${conf.map(x=>esc(G.C[x.a===k?x.b:x.a].name)).join(", ")}. Перевезення ризиковані, але гуманітарні вантажі оплачуються щедро.</div></div>`:""}
   ${pir.length?`<div class="hint" style="border-color:rgba(240,98,95,.4);background:rgba(240,98,95,.07)">${ic("skull")}<div>Біля узбережжя діють <b>пірати</b>. Директор з безпеки знижує ризик.</div></div>`:""}
   <div class="blk"><div class="kv">
    <span>Материк</span><b>${esc(CO_LN[pls[0]?.land]||"—")}</b>
    <span>Населення</span><b class="num">${fmtPop(c.pop)}</b>
    <span data-tip="${T("Рівень цін","Скільки платять за доставку відносно середнього світового рівня.")}">Ціни на доставку</span><b class="num">×${priceK(k).toFixed(2)}</b>
    <span>Зарплати</span><b class="num">×${wageK(k).toFixed(2)}</b>
    <span>Стабільність</span><b class="num">${c.stability.toFixed(0)}%</b>
    <span data-tip="${T("Ризик","Ймовірність крадіжок і затримок на кордонах.")}">Ризик перевезень</span><b class="${rw[1]}">${rw[0]}</b>
   </div></div>
   ${sp&&typeof poInspBlk==="function"?poInspBlk(sp):""}${sp?bizInsp(sp):""}
   ${(()=>{const hs=CO.hubs.filter(h=>PL[h.pid]&&PL[h.pid].cid===k);if(!hs.length)return"";return sect("Ваша мережа тут")+`<div style="display:flex;flex-direction:column;gap:6px;margin-bottom:6px">${hs.map(h=>{const q=PL[h.pid],hq=h.pid===CO.hq;return `<div class="lrow" style="cursor:pointer;border-color:rgba(255,179,71,.45);background:rgba(255,179,71,.07)" data-act="coFly" data-arg="${q.id}"><span class="warn">${ic(hq?"star":"building")}</span><div style="min-width:0"><b>${hq?"Штаб · ":""}${HUB_LV[h.lvl]}</b><div class="note">${esc(q.name)} · ${CO.veh.filter(v=>v.loc===q.id).length} од. техніки</div></div><span class="pill warn">${ic("pin")}На мапі</span></div>`}).join("")}</div>`})()}
   ${sect(sp?"Поруч":"Міста й села")}<div style="display:flex;flex-direction:column;gap:6px">${pls.map(p=>{const h=hubAt(p.id),can=coScope(p),cost=hubOpenCost(p);
    return `<div class="lrow"><span class="${h?"warn":"mut"}">${ic(h?(p.id===CO.hq?"star":"building"):p.type==="cap"?"crown":"pin")}</span><div style="min-width:0"><b style="cursor:pointer" data-act="coGoto" data-arg="${p.id}">${esc(p.name)}</b><div class="note">${fmtSP(p.pop)} ${p.air?ic("plane"):""}${p.port!=null?ic("anchor"):""}${p.rail?ic("train"):""}${h?` · <span class="warn">${HUB_LV[h.lvl]}</span>`:""}</div></div>
     ${h?(h.lvl<4?`<button class="btn sm" data-act="coHubUp" data-arg="${p.id}">${ic("up")}${fmtUSD(cost*HUB_UP[h.lvl])}</button>`:`<span class="pill good">Логістичний хаб</span>`):can?`<button class="btn sm ${CO.cash>=cost?"pri":""}" data-act="coHub" data-arg="${p.id}" ${CO.cash>=cost?"":"disabled"} data-tip="${hubAbroad(p)?T("Орендувати хаб","За кордоном хаб не купити, лише орендувати: застава "+fmtUSD(cost)+", далі ≈ "+fmtUSD(hubRentM({pid:p.id,lvl:1,rent:1}))+"/міс. (значно дорожче за власний). Тут можна тримати свою техніку, і біржа даватиме замовлення з цієї країни. Розширити можна лише до 2 рівня."):T("Відкрити хаб","Власний хаб 1 рівня в цьому місті: техніка виїздить звідси на рейси.")}">${ic("plus")}${hubAbroad(p)?"Оренда ":""}${fmtUSD(cost)}</button>`:`<span class="pill" data-tip="${T("Недоступно",CO.tier<1?"Потрібна ліцензія «Міжміська доставка».":CO.tier<3?"Хаби за кордоном — з ліцензією «Міжнародні перевезення».":"Інші материки — з ліцензією «Морський перевізник».")}">${ic("lock")}</span>`}</div>`}).join("")}</div>`;
  el.innerHTML=`<div class="ihead">${sp?`<span class="acc">${ic(sp.type==="vil"?"house":sp.type==="town"?"pin":"building")}</span>`:`<img src="${c.flag}" alt="" style="width:30px;height:20px;border:1px solid var(--line-hi)">`}<div style="min-width:0;flex:1"><h2>${esc((sp?sp.name:c.name).toUpperCase())}</h2>${sp?`<div class="note" style="cursor:pointer" data-act="coCountry" data-arg="${k}">${({cap:"Столиця",big:"Велике місто",city:"Середнє місто",town:"Мале місто",vil:"Мале місто"})[sp.type]} · ${esc(c.name)} ›</div>`:""}</div><button class="xbtn" data-act="iclose" aria-label="Закрити">${ic("close")}</button></div><div class="ibody">${body}</div>`;
}

/* ---------- map colours & legend ---------- */
function coDemand(){const d=G.C.map(()=>0);for(const p of PL){const c=G.C[p.cid];if(c)d[p.cid]+=(p.pop*1000+400)*(.45+c.dev)*priceK(p.cid)}return G.C.map((c,i)=>d[i]/Math.max(1,Math.sqrt(c.geo.area||1)))}
const DEM_COL=[[.78,.9,.97],[.47,.73,.9],[.22,.5,.78],[.1,.29,.55]];
function demLevels(){const v=coDemand(),srt=v.slice().sort((a,b)=>a-b),q=f=>srt[Math.floor(f*(srt.length-1))];const t=[q(.35),q(.65),q(.88)];return v.map(x=>x<t[0]?0:x<t[1]?1:x<t[2]?2:3)}
function coColors(){const hubC=new Set(CO.hubs.map(h=>PL[h.pid].cid));
  if(UI.mode==="pol")return G.C.map(c=>hex3(c.color));
  if(UI.mode==="dem"){const L=demLevels();return L.map(l=>DEM_COL[l])}
  if(UI.mode==="grid")return G.C.map(()=>vis("land")?[.72,.75,.78]:[.3,.33,.36]);
  return G.C.map(c=>{if(UI.mode==="risk")return RISK_COL[riskLvl(c.id)];
    const p=PL.find(q=>q.cid===c.id&&q.type==="cap");const ok=p&&coScope(p);
    if(hubC.has(c.id)&&vis("hub"))return mixc(hex3(c.color),[1,.7,.28],.35);if(ok)return vis("avail")?mixc(hex3(c.color),[.3,.34,.38],.35):hex3(c.color);return vis("unavail")?mixc(hex3(c.color),[.17,.2,.24],.78):hex3(c.color)})}
const _updLegendCo=updateLegend;
const LG_INC=`<div class="lg"><b style="display:inline-block;width:9px;height:9px;border-radius:50%;background:#ff8a2a;box-shadow:0 0 0 3px rgba(255,138,42,.25);margin:0 4px 0 3px"></b><b style="display:inline-block;width:9px;height:9px;border-radius:50%;background:#f0443c;box-shadow:0 0 0 3px rgba(240,68,60,.25);margin-right:6px"></b>Перекриті дороги</div><div class="lg"><i style="height:2px;background:#f0443c"></i>Закриті кордони</div><div class="lg"><b class="sq" style="background:rgba(160,190,255,.22);border:1px dashed #a8c4ff;border-radius:50%"></b>Негода</div><div class="lg"><b class="sq" style="background:#f0625f;border-radius:50%"></b>Закриті порти й аеропорти</div><div class="lg"><i style="height:0;border-top:2px dashed #d696ff"></i>Закрите небо (війна)</div><div class="lg"><b class="sq" style="background:rgba(240,98,95,.18);border:1px dashed #f0625f;border-radius:50%"></b>Зона піратства</div><div class="lg"><b class="sq" style="background:rgba(255,140,60,.18);border:1px dashed #ff8c3c;border-radius:50%"></b>Зона бандитів на дорогах</div><div class="lg"><b class="sq" style="background:#0b1520;border:2px solid #f0625f;border-radius:50%"></b>Напад: пограбування, захоплення</div><div class="lg"><b class="sq" style="background:transparent;border:1px dashed #c9d4de;border-radius:50%"></b>Збій GPS: техніка зникає з карти</div>`;
const LG_SET=`<div class="lg"><b class="sq sqc" style="margin:0 9px"></b>Столиці, великі й середні міста</div><div class="lg"><b class="sq" style="transform:rotate(45deg)"></b>Малі міста</div>`;
updateLegend=function(){if(!G.co||!["co","risk","grid","pol","dem"].includes(UI.mode))return _updLegendCo();const el=$("#legend");if(!el)return;el.hidden=false;
  if(UI.mode==="pol"){el.innerHTML=`<span class="lbl">Політична карта</span><div class="lg"><i style="height:2px;background:#0b1520;box-shadow:0 0 0 1px rgba(255,255,255,.25)"></i>Кордони держав</div>${LG_SET}<div class="note" style="margin-top:6px">${G.C.length} держав</div>`;return}
  if(UI.mode==="dem"){el.innerHTML=`<span class="lbl">Світовий попит на доставку</span>${["Низький","Середній","Високий","Дуже високий"].map((n,i)=>`<div class="lg"><b class="sq" style="width:14px;height:10px;margin:0 6px;background:rgb(${DEM_COL[i].map(v=>Math.round(v*255)).join(",")})"></b>${n}</div>`).join("")}${LG_SET}<div class="note" style="margin-top:6px">Попит: населення й багатство міст країни на одиницю площі</div>`;return}
  if(UI.mode==="grid"){el.innerHTML=`<span class="lbl">Логістичні шляхи</span><div class="lg"><b class="sq" style="background:#b8bfc7"></b>Суходіл (усі держави)</div><div class="lg"><b class="sq sqc" style="margin:0 9px"></b>Столиці, великі й середні міста</div><div class="lg"><b class="sq" style="transform:rotate(45deg)"></b>Малі міста</div>${G.board?`<div class="lg lfi${UI.lf==="sector"?" on":""}" data-act="lf" data-arg="sector"><b class="sq" style="background:transparent;border:2px solid #e6edf3"></b>Сектор ≈ ${Math.round(SECTOR*CO_DU*KM)} км</div><div class="lg lfi${UI.lf==="quarter"?" on":""}" data-act="lf" data-arg="quarter"><b class="sq" style="background:transparent;border:1px solid #aab6c2"></b>Квартал ≈ ${Math.round(SECTOR/3*CO_DU*KM)} км</div><div class="lg lfi${UI.lf==="cell"?" on":""}" data-act="lf" data-arg="cell"><b class="sq" style="background:transparent;border:1px dashed #7d8894"></b>Клітинка ≈ ${Math.round(.125*CO_DU*KM)} км (трикутники суші й води)</div>`:`<div class="lg"><b class="sq" style="background:transparent;border:1px solid #8a9199"></b>Сітка: клітинка ≈ ${Math.round(.08*CO_DU*KM)} км</div>`}<div class="lg lfi${UI.lf==="road"?" on":""}" data-act="lf" data-arg="road"><i style="height:2px;background:#f4b453"></i>Автомагістралі й дороги</div><div class="lg lfi${UI.lf==="railway"?" on":""}" data-act="lf" data-arg="railway"><i style="height:4px;background:#6b3b1a"></i>Залізниця</div><div class="lg"><b class="sq" style="width:10px;height:10px;margin:0 8px;background:repeating-linear-gradient(135deg,#f0625f 0 3px,#fff 3px 6px);border:1px solid #e8edf2"></b>Пропускний пункт на кордоні</div><div class="lg lfi${UI.lf==="port"?" on":""}" data-act="lf" data-arg="port"><b class="ico">${ic("anchor")}</b>Морський порт</div><div class="lg lfi${UI.lf==="air"?" on":""}" data-act="lf" data-arg="air"><b class="ico">${ic("plane")}</b>Аеропорт</div><div class="lg lfi${UI.lf==="rail"?" on":""}" data-act="lf" data-arg="rail"><b class="ico">${ic("train")}</b>Залізнична станція</div>${LG_INC}<div class="lg"><b class="sq" style="background:#ffb347"></b>Хаби</div><div class="lg"><b class="sq" style="background:#ffb347;width:6px;height:6px;margin:0 10px"></b>Хаб 1 рівня</div><div class="lg"><b class="sq" style="background:#ffb347"></b>Хаб 2 рівня</div><div class="lg"><b class="sq" style="background:#ffb347;width:10px;height:10px;margin:0 8px"></b>Хаб 3 рівня</div><div class="lg"><b class="sq" style="background:#ffb347;width:12px;height:12px;margin:0 7px"></b>Логістичний хаб</div><div class="note" style="margin-top:6px">Клік по пункту — фільтр</div>`;return}
  el.innerHTML=UI.mode==="risk"?`<span class="lbl">Ризики перевезень</span>${["Низький","Помірний","Високий","Дуже високий"].map((n,i)=>`<div class="lg"><b class="sq" style="background:rgb(${RISK_COL[i].map(v=>Math.round(v*255)).join(",")})"></b>${n}</div>`).join("")}<div class="lg"><b class="sq" style="background:rgba(240,98,95,.25);border:1px dashed #f0625f;border-radius:50%"></b>Зона піратства</div><div class="lg"><b class="sq" style="background:rgba(255,140,60,.2);border:1px dashed #ff8c3c;border-radius:50%"></b>Зона бандитів на дорогах</div><div class="note" style="margin-top:6px">Рівень відносно інших держав: повільна митниця, нестабільність, конфлікти</div>`
  :`<span class="lbl">Мережа ${esc(CO.name)}</span><div class="lg"><b class="sq" style="background:#ffb347"></b>Хаби</div><div class="lg"><b class="sq" style="background:#34c759;border-radius:50%"></b>Фургони й вантажівки</div><div class="lg"><b class="sq" style="background:#ec965c;border-radius:50%"></b>Потяги</div><div class="lg"><b class="sq" style="background:#6ebeff;border-radius:50%"></b>Кораблі</div><div class="lg"><b class="sq" style="background:#d696ff;border-radius:50%"></b>Літаки</div><div class="lg"><b class="sq" style="background:#f0625f;border-radius:50%"></b>Інцидент: ДТП, поломка, пальне</div><div class="lg"><b class="sq" style="background:#f1c453;border-radius:50%"></b>Затримка: кордон, негода, перекриття</div>${LG_INC}<div class="lg"><b class="sq" style="background:#7d8a96"></b>Доступно за ліцензією</div><div class="lg"><b class="sq" style="background:#2b333c"></b>Поки недоступно</div>
  <div class="lg"><i style="height:4px;background:#f6b94f;box-shadow:0 0 0 1px rgba(6,12,18,.6)"></i>Автомагістралі</div><div class="lg"><i style="height:2px;background:#f4b453"></i>Дороги</div><div class="lg lfi${UI.lf==="railway"?" on":""}" data-act="lf" data-arg="railway"><i style="height:4px;background:#6b3b1a"></i>Залізниця</div><div class="lg"><b class="sq" style="width:10px;height:10px;margin:0 8px;background:repeating-linear-gradient(135deg,#f0625f 0 3px,#fff 3px 6px);border:1px solid #e8edf2"></b>Пропускний пункт на кордоні</div><div class="lg lfi${UI.lf==="port"?" on":""}" data-act="lf" data-arg="port"><b class="ico">${ic("anchor")}</b>Морський порт</div><div class="lg lfi${UI.lf==="air"?" on":""}" data-act="lf" data-arg="air"><b class="ico">${ic("plane")}</b>Аеропорт</div><div class="lg lfi${UI.lf==="rail"?" on":""}" data-act="lf" data-arg="rail"><b class="ico">${ic("train")}</b>Залізнична станція</div><div class="note" style="margin-top:6px">Хабів: ${CO.hubs.length} · рейсів у дорозі: ${CO.jobs.length}</div>`};

/* collapse button for the legend on every layer */
const LV_MAP=[["Хаби","hub"],["Гаражі","hub_1"],["Склади","hub_2"],["Логістичні термінали","hub_3"],["Кордони держав","pol_b"],["Фургони","v_road"],["Потяги","v_rail"],["Кораблі","v_sea"],["Літаки","v_air"],["Доступно за ліцензією","avail"],["Поки недоступно","unavail"],["Зона піратства","pir"],["Перекриті дороги","jam"],["Закриті кордони","clb"],["Негода","wx"],["Закриті порти","clp"],["Закрите небо","sky"],["Зона бандитів","band"],["Напад","mark"],["Автомагістраль між","r3"],["Автомагістралі й","roads"],["Автомагістралі","r3"],["Дороги","r2"],["Дорога між містами","r2"],["Місцева дорога","r1"],["Автомагістралі й дороги","roads"],["Залізнична станція","rails"],["Залізниця","rail"],["Пропускний","cp"],["Морський порт","port"],["Аеропорт","air"],["Суходіл","land"],["Столиці","s_city"],["Малі міста","s_town"]];
{const _ulAll=updateLegend;updateLegend=function(){_ulAll();const el=$("#legend");if(!el||el.hidden)return;
  if(G.co&&["co","grid","pol","dem"].includes(UI.mode)){let any=false;el.querySelectorAll(".lg").forEach(d=>{const t=d.textContent.trim(),m=LV_MAP.find(x=>t.startsWith(x[0]));if(!m)return;d.removeAttribute("data-act");d.classList.remove("on");d.classList.add("lfi");d.dataset.act="lv";d.dataset.arg=m[1];const off=UI.hid.has(m[1]);d.classList.toggle("off",off);if(off)any=true});
    el.querySelectorAll(".note").forEach(n=>{if(/фільтр|Клік по пункту|Фільтр/.test(n.textContent))n.remove()})}if(!el.querySelector(".lgx")){const b=document.createElement("button");b.className="lgx";b.setAttribute("aria-label","Згорнути легенду");b.setAttribute("data-act","lgToggle");el.appendChild(b)}el.classList.toggle("col",!!UI.lgc)}}
ACT.lgToggle=()=>{UI.lgc=!UI.lgc;try{localStorage.setItem("pon_lgc",UI.lgc?"1":"")}catch(e){}updateLegend()};
try{UI.lgc=!!localStorage.getItem("pon_lgc")}catch(e){}
/* ---------- drawing ---------- */
function coCum(j){if(j._c&&j._c.length===j.p.length/2)return j._c;const n=j.p.length/2,c=new Float32Array(n);for(let i=1;i<n;i++)c[i]=c[i-1]+Math.hypot(j.p[i*2]-j.p[i*2-2],j.p[i*2+1]-j.p[i*2-1]);j._c=c;return c}
function coPosAt(j,s){s/=CO_DU;const c=coCum(j),n=c.length;if(s<=0)return[j.p[0],j.p[1],0];if(s>=c[n-1])return[j.p[n*2-2],j.p[n*2-1],0];
  let lo=0,hi=n-1;while(hi-lo>1){const m=(lo+hi)>>1;if(c[m]<=s)lo=m;else hi=m}const t=(s-c[lo])/((c[hi]-c[lo])||1);return[j.p[lo*2]+(j.p[hi*2]-j.p[lo*2])*t,j.p[lo*2+1]+(j.p[hi*2+1]-j.p[lo*2+1])*t,lo]}
function coArcH(L){return clamp(L/CO_DU*.22,.05,.9)}
function coAlt(j,st){if(j.mode!=="air"||st.seg<0)return 0;const L=st.seg===0?j.lead:j.len,f=clamp(st.f,0,1);return Math.sin(Math.PI*(j.airS===st.seg?.5+.5*f:f))*coArcH(j.airS===st.seg?Math.max(L,j.airH||0):L)}
function drawCompany(g,dpr){
  CO_HITS=[];if(!CO.hubs||!PL.length)return;
  const P=(x,y,z)=>{const p=project(x,y,z);return p?[p.x*dpr,p.y*dpr]:null};
  const now=ANIM_T,zf=clamp(11/Cam.dist,1,1.8),RGB="255,179,71";
  const T0=coNow();
  // piracy zones
  for(const z of (UI.mode==="risk"&&!G.board?CO.pir:[])){const c=P(z.x,0,z.z),e=P(z.x+z.r,0,z.z);if(!c||!e)continue;const r=Math.hypot(e[0]-c[0],e[1]-c[1]);
    g.fillStyle="rgba(240,98,95,.08)";g.strokeStyle="rgba(240,98,95,.55)";g.lineWidth=1.2*dpr;g.setLineDash([5*dpr,5*dpr]);g.beginPath();g.ellipse(c[0],c[1],r,r*.62,0,0,7);g.fill();g.stroke();g.setLineDash([]);
    if(Cam.dist<16){g.font=`600 ${10*dpr}px "JetBrains Mono",monospace`;g.fillStyle="rgba(255,150,145,.9)";g.textAlign="center";g.fillText("ПІРАТИ",c[0],c[1]+3*dpr)}}
  // settlement territory on the logistics layer
  if(UI.mode==="grid"&&!G.board){const d=Cam.dist,blds=[];for(const p of PL){if(p.type==="vil"&&d>2.3||p.type==="town"&&d>4.2)continue;const r=coRad(p);
    const c=P(p.x,0,p.z);if(!c)continue;const ex=P(p.x+r,0,p.z),ez=P(p.x,0,p.z+r);if(!ex||!ez)continue;const rx=Math.hypot(ex[0]-c[0],ex[1]-c[1]),rz=Math.hypot(ez[0]-c[0],ez[1]-c[1]);if(rx<4*dpr)continue;
    if(c[0]<-rx||c[1]<-rz||c[0]>g.canvas.width+rx||c[1]>g.canvas.height+rz)continue;
    g.fillStyle=p.type==="cap"?"rgba(92,200,242,.13)":"rgba(92,200,242,.09)";g.strokeStyle=p.type==="cap"?"rgba(40,140,200,.75)":"rgba(40,140,200,.5)";g.lineWidth=(p.type==="cap"?1.6:1.1)*dpr;
    g.beginPath();g.ellipse(c[0],c[1],rx,rz,0,0,7);g.fill();g.stroke();}
  }
  // contract preview
  if(CO_PREV){const k=CO.board.find(x=>x.id===CO_PREV);if(k){CO.pvScr=null;lpWave(g,P,PL[k.from],LP_DEP,dpr);lpWave(g,P,PL[k.to],LP_ARR,dpr);REDRAW=true}else CO_PREV=null}
  // hubs
  const cour=[];
  for(const h of CO.hubs){const p=PL[h.pid],q=P(p.x,0,p.z);if(!q)continue;const s=(5+h.lvl*1.5)*dpr*Math.min(zf,1.4);
    if(G.board){CO_HITS.push({hub:h,x:q[0]/dpr,y:q[1]/dpr});continue}
    g.fillStyle=`rgba(${RGB},.18)`;g.beginPath();g.arc(q[0],q[1],s*2.6,0,7);g.fill();
    g.fillStyle=`rgb(${RGB})`;g.strokeStyle="#06121b";g.lineWidth=1.6*dpr;g.fillRect(q[0]-s,q[1]-s,s*2,s*2);g.strokeRect(q[0]-s,q[1]-s,s*2,s*2);
    if(h.pid===CO.hq){g.fillStyle="#06121b";g.beginPath();for(let i=0;i<10;i++){const a=-Math.PI/2+i*Math.PI/5,rr=i%2?s*.35:s*.8;g.lineTo(q[0]+Math.cos(a)*rr,q[1]+Math.sin(a)*rr)}g.fill()}
    if(!G.board&&(Cam.dist<9||h.pid===CO.hq&&Cam.dist<14)){g.font=`700 ${9.5*dpr}px "JetBrains Mono",monospace`;g.textAlign="center";const txt=(h.pid===CO.hq?"ШТАБ · ":"")+HUB_LV[h.lvl].toUpperCase();const w=g.measureText(txt).width+8*dpr;
      g.fillStyle="rgba(6,18,27,.85)";g.fillRect(q[0]-w/2,q[1]+s+4*dpr,w,14*dpr);g.fillStyle=`rgb(${RGB})`;g.fillText(txt,q[0],q[1]+s+14*dpr)}
    CO_HITS.push({hub:h,x:q[0]/dpr,y:q[1]/dpr});
    if(Cam.dist<13&&h.ids&&h.ids.length){const paths=coCityPaths(p);const ids=h.ids.filter(id=>{const v=CO.veh.find(x=>x.id===id);return v&&v.st==="idle"&&v.loc===h.pid}).slice(0,240)
      ids.forEach((id,i)=>{const pp=paths[(i*7+3)%paths.length],L=pp.L,sp=(.018+((id*37)%11)*.0022)/(G.board?40:CO_DU);let d=((now+id*5.3)*sp)%(2*L);const fwd=d<L,s0=fwd?d:2*L-d;
        const at=s_=>{s_=clamp(s_,0,L);let k=1;while(k<pp.c.length-1&&pp.c[k]<s_)k++;const t=(s_-pp.c[k-1])/((pp.c[k]-pp.c[k-1])||1);return[pp.p[(k-1)*2]+(pp.p[k*2]-pp.p[(k-1)*2])*t,pp.p[(k-1)*2+1]+(pp.p[k*2+1]-pp.p[(k-1)*2+1])*t]};
        const q=at(s0),qs=P(q[0],0,q[1]);if(!qs)return;const tr=[];for(let k=1;k<=4;k++){const t2=P(...(x=>[x[0],0,x[1]])(at(s0+(fwd?-1:1)*k*.012/(G.board?20:CO_DU))));if(t2)tr.push(t2)}
        cour.push({id,x:qs[0],y:qs[1],tr,pid:p.id})})}
  }
  // couriers: individual dots, or one cluster marker when 5+ overlap
  CO_CL=[];{const cell=22*dpr,grp=new Map(),small=new Map();const isSmall=pid=>{if(small.has(pid))return small.get(pid);const q=PL[pid],r=G.board?(BRAD[q.type]||.04):.1,a=P(q.x,0,q.z),b=P(q.x+r,0,q.z);const v=!a||!b||Math.hypot(b[0]-a[0],b[1]-a[1])<70*dpr;small.set(pid,v);return v};
  for(const c of cour){const k=isSmall(c.pid)?"p"+c.pid:Math.floor(c.x/cell)+":"+Math.floor(c.y/cell);if(!grp.has(k))grp.set(k,[]);grp.get(k).push(c)}
    for(const L of grp.values()){if(L.length>=2){const c=L[0],x=c.x,y=c.y,hs=8*dpr;
        let prev=[x,y];c.tr.forEach((t,k)=>{g.strokeStyle=`rgba(${RGB},${(.55-k*.12).toFixed(2)})`;g.lineWidth=1.4*dpr;g.beginPath();g.moveTo(...prev);g.lineTo(...t);g.stroke();prev=t});
        g.fillStyle="rgba(11,21,32,.55)";g.strokeStyle=`rgb(${RGB})`;g.lineWidth=1.4*dpr;g.fillRect(x-hs,y-hs,hs*2,hs*2);g.strokeRect(x-hs,y-hs,hs*2,hs*2);
        g.fillStyle=`rgb(${RGB})`;g.strokeStyle="rgba(6,18,27,.85)";g.lineWidth=.9*dpr;g.beginPath();g.arc(x,y,2.8*dpr,0,7);g.fill();g.stroke();
        const txt="×"+L.length;g.font=`700 ${9.5*dpr}px "JetBrains Mono",monospace`;const tw=g.measureText(txt).width+6*dpr;g.fillStyle="#0b1520";g.fillRect(x+hs-1*dpr,y-hs-11*dpr,tw,12*dpr);g.strokeStyle=`rgb(${RGB})`;g.lineWidth=1*dpr;g.strokeRect(x+hs-1*dpr,y-hs-11*dpr,tw,12*dpr);
        g.fillStyle=`rgb(${RGB})`;g.textAlign="left";g.textBaseline="middle";g.fillText(txt,x+hs+2*dpr,y-hs-5*dpr);g.textBaseline="alphabetic";
        CO_CL.push({x:x/dpr,y:y/dpr,r:14,ids:L.map(c=>c.id),pid:L[0].pid})}
      else for(const c of L){let prev=[c.x,c.y];c.tr.forEach((t,k)=>{g.strokeStyle=`rgba(${RGB},${(.55-k*.12).toFixed(2)})`;g.lineWidth=1.4*dpr;g.beginPath();g.moveTo(...prev);g.lineTo(...t);g.stroke();prev=t});
        g.fillStyle=`rgb(${RGB})`;g.strokeStyle="rgba(6,18,27,.85)";g.lineWidth=.9*dpr;g.beginPath();g.arc(c.x,c.y,2.6*dpr*Math.min(zf,1.3),0,7);g.fill();g.stroke();
        CO_CL.push({x:c.x/dpr,y:c.y/dpr,r:8,ids:[c.id],pid:c.pid})}}
    const tp=$("#coTip");if(tp&&!tp.hidden&&CO_MOUSE&&performance.now()-(CO.tipT||0)>250){CO.tipT=performance.now();coTipShow(CO_MOUSE)}}
  g=coVcv(g);
  if(CO.ping&&performance.now()-CO.ping.t<3200){const q=PL[CO.ping.pid],c=q&&P(q.x,0,q.z);if(c){const a=(performance.now()-CO.ping.t)/1000;for(let k=0;k<2;k++){const f=((a*.9+k*.5)%1);g.strokeStyle=`rgba(255,179,71,${(1-f).toFixed(2)})`;g.lineWidth=2.4*dpr;g.beginPath();g.arc(c[0],c[1],(10+f*46)*dpr,0,7);g.stroke()}REDRAW=true}}
  const j=CO_SEL;if(j){if(!CO.jobs.includes(j)){CO_SEL=null;$("#ucard").hidden=true}else{const st=coJobState(j,T0-j.t0);const pts=[];
    const c=coCum(j),n=c.length;if(j.mode==="air"){for(let k=0;k<=48;k++){const s_=st.s+(c[n-1]*CO_DU-st.s)*k/48;const pp=coPosAt(j,s_);const seg=s_<j.lead?0:1,L=seg===0?j.lead:j.len,f=(s_-(seg?j.lead:0))/(L||1);pts.push([pp[0],Math.sin(Math.PI*clamp(f,0,1))*coArcH(L),pp[1]])}}
    else{const q0=coPosAt(j,st.s);pts.push([q0[0],0,q0[1]]);for(let i=0;i<n;i++){if(c[i]*CO_DU<=st.s)continue;pts.push([j.p[i*2],0,j.p[i*2+1]])}}
    CO.rtScr={id:j.id,kind:"job",pts:pts.map(q=>P(...q)).filter(Boolean).map(q=>[q[0]/dpr,q[1]/dpr])};wroute(g,P,pts,({road:"52,199,89",rail:"236,150,92",sea:"110,190,255",air:"214,150,255"})[j.mode]||"255,205,130",dpr,ANIM_T);{const S=CO.rtScr.pts;let ux=null,uy=null;if(S.length>1){const a=S[0];for(let i=1;i<S.length;i++){const dx=S[i][0]-a[0],dy=S[i][1]-a[1],l=Math.hypot(dx,dy);if(l>14){ux=dx/l;uy=dy/l;break}}}CO.cdir=ux==null?null:[ux,uy]}}}
  // trips
  for(const j of CO.jobs){if(!vis("v_"+j.mode)&&CO_SEL!==j)continue;const e=T0-j.t0,st=coJobState(j,j.hold>0?Math.min(e,j.tl+j.hs+j.tm*.5):e);const pos=coPosAt(j,st.s),alt=coAlt(j,st);const sp=P(pos[0],alt,pos[1]);if(!sp)continue;
    const gv=incGpsVis(j);if(gv<=0)continue;g.globalAlpha=gv;
    const inc=st.inc&&st.inc.k!=="stop"?st.inc:null,red=j.hold>0||j.lost||inc&&INC_RED.has(inc.k),amb=inc&&!red,rgb=red?"240,98,95":({road:"52,199,89",rail:"236,150,92",sea:"110,190,255",air:"214,150,255"})[j.mode]||RGB;
    // trail
    if(st.seg>=0&&!inc){const step={road:.05,rail:.06,sea:.08,air:.12}[j.mode]*Math.min(1,Cam.dist/6+.25)*CO_DU/1.6;let prev=sp;for(let k=1;k<=9;k++){const s2=st.s-k*step;if(s2<0)break;const pp=coPosAt(j,s2);let a2=0;if(j.mode==="air"){const L=st.seg===0?j.lead:j.len,base=st.seg===0?0:j.lead,f=(s2-base)/(L||1);a2=f>=0?Math.sin(Math.PI*clamp(f,0,1))*coArcH(L):0}const q=P(pp[0],a2,pp[1]);if(!q)break;
      g.strokeStyle=`rgba(${rgb},${(.75*(1-k/10)).toFixed(3)})`;g.lineWidth=(j.mode==="sea"?2.4:1.8)*dpr*zf*(1-k/12);g.beginPath();g.moveTo(...prev);g.lineTo(...q);g.stroke();prev=q}}
    if(j.mode==="air"&&alt>0){const sh=P(pos[0],0,pos[1]);if(sh){g.fillStyle="rgba(0,0,0,.35)";g.beginPath();g.ellipse(sh[0],sh[1],3*dpr*zf,1.6*dpr*zf,0,0,7);g.fill()}}
    const r=4.2*dpr*zf;
    if(CO_SEL===j){g.strokeStyle=`rgba(${rgb},${(.9-((now*1.2)%1)*.9).toFixed(3)})`;g.lineWidth=1.5*dpr;g.beginPath();g.arc(sp[0],sp[1],r+3*dpr+((now*1.2)%1)*10*dpr,0,7);g.stroke()}
    const bl=inc?.5+.5*Math.sin(performance.now()/1000*(red?9:5)):1;if(inc){REDRAW=true;const wc=amb?"241,196,83":rgb;for(let w=0;w<(amb?2:1);w++){const f=((performance.now()/900)+w*.5)%1;g.strokeStyle=`rgba(${wc},${(.9*(1-f)).toFixed(3)})`;g.lineWidth=1.8*dpr;g.beginPath();g.arc(sp[0],sp[1],r+2*dpr+f*14*dpr,0,7);g.stroke()}}
    g.fillStyle=`rgba(${rgb},${(.22*bl+.06).toFixed(3)})`;g.beginPath();g.arc(sp[0],sp[1],r*2.1,0,7);g.fill();
    g.fillStyle=red&&inc?`rgba(${rgb},${(.35+.65*bl).toFixed(3)})`:`rgb(${rgb})`;g.strokeStyle="#06121b";g.lineWidth=1.4*dpr;
    g.beginPath();g.arc(sp[0],sp[1],r,0,7);g.fill();g.stroke();
    if(inc&&red&&Cam.dist<16){g.font=`800 ${9*dpr}px "JetBrains Mono",monospace`;g.textAlign="center";g.fillStyle="#06121b";g.fillText("!",sp[0],sp[1]+3.2*dpr)}
    if(j.n>1&&Cam.dist<12){g.font=`700 ${9*dpr}px "JetBrains Mono",monospace`;g.textAlign="left";g.fillStyle=`rgb(${rgb})`;g.fillText("×"+j.n,sp[0]+r+3*dpr,sp[1]-r)}
    if(gv<1&&Cam.dist<18){g.font=`700 ${8.5*dpr}px "JetBrains Mono",monospace`;g.textAlign="left";g.fillStyle="#c9d4de";g.fillText("GPS?",sp[0]+r+3*dpr,sp[1]+r+6*dpr)}
    g.globalAlpha=1;CO_HITS.push({j,x:sp[0]/dpr,y:sp[1]/dpr});
  }
  guard("Напади",()=>drawIncMarks(g,dpr));
  // selected trip: remaining route
  {const j=CO_SEL;if(j&&CO.jobs.includes(j)){const h=CO_HITS.find(x=>x.j===j);if(h){if(CO.cdir){const o=CO.cdirS||CO.cdir;CO.cdirS=[o[0]+(CO.cdir[0]-o[0])*.12,o[1]+(CO.cdir[1]-o[1])*.12];const l=Math.hypot(...CO.cdirS)||1;placeUnitCard(h.x,h.y,CO.cdirS[0]/l,CO.cdirS[1]/l)}else placeUnitCard(h.x,h.y);if(performance.now()-(CO.cardT||0)>700)coCard()}}}
}
function coPlaceAt(x,y,strict){if(!G.board)return null;for(const b of BOARD.lbl||[])if(x>=b.x0&&x<=b.x1&&y>=b.y0&&y<=b.y1)return b.pid;
  for(const c of CITY_EL){if(!c.cap||!c.vis||c.el.style.opacity==="0")continue;const r=c.el.getBoundingClientRect();if(x>=r.left-4&&x<=r.right&&y>=r.top&&y<=r.bottom){const pl=PL.find(q=>q.type==="cap"&&q.cid===c.cid);if(pl)return pl.id}}
  if(strict)return null;for(const h of CO_HITS)if(h.hub&&Math.hypot(h.x-x,h.y-y)<12)return h.hub.pid;return null}
function coVcv(base){let c=document.getElementById("vcv");if(!c){c=document.createElement("canvas");c.id="vcv";c.style.cssText="position:absolute;inset:0;width:100%;height:100%;pointer-events:none";const ov=$("#overlay");ov.insertBefore(c,$("#ovl"))}
  if(c.width!==base.canvas.width||c.height!==base.canvas.height){c.width=base.canvas.width;c.height=base.canvas.height}const g=c.getContext("2d");g.setTransform(1,0,0,1,0,0);g.clearRect(0,0,c.width,c.height);return g}
function nearLine(L,x,y){if(!L||!L.pts||L.pts.length<2)return 1e9;let bd=1e9;for(let i=1;i<L.pts.length;i++){const [ax,ay]=L.pts[i-1],[bx,by]=L.pts[i],vx=bx-ax,vy=by-ay,l2=vx*vx+vy*vy||1e-9,t=clamp(((x-ax)*vx+(y-ay)*vy)/l2,0,1);bd=Math.min(bd,Math.hypot(x-ax-vx*t,y-ay-vy*t))}return bd}
function coOpenOrder(kind,id){UI.jpin={kind,id};const j=kind==="job"?CO.jobs.find(x=>x.id===id):CO.board.find(x=>x.id===id);if(j&&UI.jfl&&UI.jfl!=="all"&&(j.mode||j.k&&j.k.mode)!==UI.jfl)UI.jfl="all";openWin(kind==="job"?"coTrips":"coJobs");requestAnimationFrame(()=>{const el=document.querySelector(kind==="job"?`#win [data-act="coJob"][data-arg="${id}"]`:`#win [data-act="coShow"][data-arg="${id}"]`);const box=el&&(kind==="job"?el:el.closest(".blk"));if(!box)return;
  UI.scrollT=performance.now();box.scrollIntoView({block:"center",behavior:"smooth"});box.classList.remove("flashsel");void box.offsetWidth;box.classList.add("flashsel")})}
ACT.coOpenJob=id=>coOpenOrder("job",+id);
function coClick(x,y){
  if(CO_SEL&&CO.rtScr&&CO.rtScr.id===CO_SEL.id&&nearLine(CO.rtScr,x,y)<8&&!CO_HITS.some(h=>h.j&&Math.hypot(h.x-x,h.y-y)<14)){coOpenOrder("job",CO_SEL.id);return true}
  if(CO_PREV&&CO.pvScr&&CO.pvScr.id===CO_PREV&&nearLine(CO.pvScr,x,y)<8){coOpenOrder("board",CO_PREV);return true}
  if(G.board){let jh=null,bd=14;for(const h of CO_HITS){if(!h.j)continue;const d=Math.hypot(h.x-x,h.y-y);if(d<bd){bd=d;jh=h}}
    if(jh){CO_SEL=jh.j;CO.follow=true;coCard();return true}
    const pid=coPlaceAt(x,y);if(pid!=null){UI.selP=pid;UI.sel=PL[pid].cid;renderInsp();return true}}
  if(G.board&&!CO_CL.some(c=>Math.hypot(c.x-x,c.y-y)<c.r)&&!CO_HITS.some(h=>Math.hypot(h.x-x,h.y-y)<14)){let best=null,bd=16;for(const p of PL){const q=project(p.x,0,p.z);if(!q)continue;const d=Math.hypot(q.x-x,q.y-y);if(d<bd){bd=d;best=p}}if(best){UI.selP=best.id;UI.sel=best.cid;renderInsp();return true}}
  for(const c of CO_CL){if(c.ids.length>=2&&Math.hypot(c.x-x,c.y-y)<c.r){const q=pickPlane(x,y);if(q){Cam.ttx=q[0];Cam.ttz=q[1];Cam.tdist=Math.max(2.2,Cam.tdist*.55)}return true}}
  let best=null,bd=14;for(const h of CO_HITS){const d=Math.hypot(h.x-x,h.y-y);if(d<bd){bd=d;best=h}}if(!best)return false;
  if(best.j){CO_SEL=best.j;CO.follow=true;coCard();return true}
  if(best.hub){UI.sel=PL[best.hub.pid].cid;renderInsp();return true}return false}
/* place the trip card next to its vehicle on the map */
function placeUnitCard(x,y,ux,uy){const el=$("#ucard");if(el.hidden)return;const w=el.offsetWidth,h=el.offsetHeight;let lx=x+22,ly=y-h/2;if(lx+w>innerWidth-12)lx=x-w-22;
  if(ux!=null){if(Math.abs(ux)>.3||placeUnitCard.side==null)placeUnitCard.side=ux>0?-1:1;lx=placeUnitCard.side<0?x-w-34:x+34;if(lx<12)lx=x+34;if(lx+w>innerWidth-12)lx=x-w-34}ly=clamp(ly,70,innerHeight-h-90);el.style.transform=`translate(${lx.toFixed(0)}px,${ly.toFixed(0)}px)`}
function coCard(){const j=CO_SEL;if(!j)return;CO.cardT=performance.now();const el=$("#ucard"),T=VT[j.t],cg=j.ret?{n:"Повернення в хаб",val:0}:CARGO_I[j.k.cg],A=PL[j.back?j.k.to:j.k.from],B=PL[j.back?j.k.from:j.k.to];
  const e=coNow()-j.t0,st=coJobState(j,e),left=Math.max(0,j.tot-e),prog=clamp(e/j.tot,0,1),lateBy=coNow()+left-j.dl;
  const rows=[["Техніка",`${T.n}${j.n>1?" ×"+j.n:""}`],["Вантаж",`${esc(cg.n)}, ${j.k.tons.toLocaleString("uk-UA")} т`],...(j.lp&&j.lp.plan.length>1?[["Маршрут",`ділянка ${j.lp.i+1} з ${j.lp.plan.length}: ${j.lp.plan.map(L=>LP_N[L.m]).join(" → ")}`]]:[]),...(kFirms(j.k)?[["Відправник",esc(j.k.fs)],["Отримувач",esc(j.k.ft)]]:[]),["Вартість вантажу",fmtUSD(j.k.tons*cg.val)],["Оплата",fmtUSD(j.k.pay)],["Відстань",kmS(j.lead+j.len)],["Етап",j.hold>0?`<span class="bad">${j.seized?"Захоплено піратами":"Затримано"}</span>`:st.inc?`<span class="${INC_RED.has(st.inc.k)?"bad":"warn"}">${esc(st.ph)}</span>`:esc(st.ph)],["Термін",lateBy>.05?`<span class="bad">запізнення ${lateBy.toFixed(1)} дн.</span>`:`<span class="good">встигаємо</span>`]];
  if(j.ret)rows.splice(0,rows.length,["Техніка",T.n],["Рейс","Порожній, повернення в хаб"],["Відстань",kmS(j.len)],["Етап",esc(st.ph)]);
  if(j.dmg>.02)rows.push(["Пошкодження",`<span class="warn">${(j.dmg*100).toFixed(0)}%</span>`]);if(j.lost)rows.push(["Вантаж",`<span class="bad">втрачено</span>`]);
  el.innerHTML=`<div class="uc-head"><div class="uc-ic">${ic(T.ic)}</div><div class="grow"><span class="lbl">${esc(CO.name)} · ${MODE_N[j.mode]}</span><b>Рейс №${j.id}</b><div class="note">${esc(cg.n)}</div></div><button class="xbtn" data-act="coUcClose" aria-label="Закрити">${ic("close")}</button></div>
  <div class="uc-body"><div class="uc-route"><div class="row"><img src="${G.C[A.cid].flag}" alt="">${esc(A.name)}</div><div class="uc-arrow">${ic("down")}</div><div class="row"><img src="${G.C[B.cid].flag}" alt="">${esc(B.name)}</div></div>
  <dl class="kv">${rows.map(r=>`<dt>${r[0]}</dt><dd>${r[1]}</dd>`).join("")}<dt>Прибуття через</dt><dd>${daysS(left)}</dd></dl>
  <div ${j.ret?'style="margin-top:2px"':`class="ucopen" data-act="coOpenJob" data-arg="${j.id}" title="Відкрити в «Рейси в дорозі»"`}><div class="row sp"><span class="lbl">${j.ret?"Маршрут":"Маршрут · відкрити замовлення ›"}</span><span class="num mut">${(prog*100).toFixed(0)}%</span></div><div class="meter" style="margin-top:6px"><i style="width:${(prog*100).toFixed(1)}%"></i></div></div>
  ${j.ev.length?`<div class="note">${j.ev.slice(-3).map(esc).join("<br>")}</div>`:""}</div>`;el.hidden=false}

/* settlement radius on the logistics grid (cell = .08): biggest city just under 4 cells across, village under 1 cell */
let CO_MAXP=0;function coRad(p){if(!CO_MAXP)CO_MAXP=Math.max(...PL.filter(q=>q.type!=="vil").map(q=>q.pop),.01);
  if(p.type==="vil")return .026+.006*Math.min(1,p.pop/.05);return .045+.105*Math.sqrt(Math.min(1,p.pop/CO_MAXP))}
/* ---------- settlement layouts (city / town / village), white buildings ---------- */
const CO_HS=new Map();
function coLayout(p,r){let L=CO_HS.get(p.id);if(L)return L;const rr=mulberry((p.id*7919+13)>>>0),R_=()=>rr(),kind=p.type==="town"?"town":p.type==="vil"?"vil":"city";
  const roads=[],H=[],ring=(f,a0=0,a1=6.2832)=>{const q=[];const n=Math.max(12,Math.round(48*(a1-a0)/6.2832));for(let i=0;i<=n;i++){const t=a0+(a1-a0)*i/n;q.push([p.x+Math.cos(t)*r*f,p.z+Math.sin(t)*r*f])}roads.push(q)};
  const ray=(a,f0,f1)=>roads.push([[p.x+Math.cos(a)*r*f0,p.z+Math.sin(a)*r*f0],[p.x+Math.cos(a)*r*f1,p.z+Math.sin(a)*r*f1]]);
  const box=(ang,f,w,d,h,rot)=>H.push({x:p.x+Math.cos(ang)*r*f,z:p.z+Math.sin(ang)*r*f,w:w*r,d:d*r,h:h*r,a:rot??ang+Math.PI/2});
  const tall=p.type==="cap"?1.25:p.type==="big"?1.05:.85;
  if(kind==="city"){ring(.12);ring(.62);ring(.8);const n=8,o=R_()*.4;for(let i=0;i<n;i++)ray(o+i*6.2832/n,.12,1);
    for(let i=0;i<30;i++){const ang=R_()*6.2832,f=.18+R_()*.4;box(ang,f,.05+R_()*.03,.05+R_()*.03,(.13+R_()*.25)*tall,R_()*.3)}
    for(let i=0;i<9;i++){const ang=R_()*6.2832,f=.68+R_()*.07;box(ang,f,.05+R_()*.03,.04,(.07+R_()*.14)*tall)}
    for(let i=0;i<5;i++){const ang=R_()*6.2832;box(ang,.9,.05,.04,.06)}}
  else if(kind==="town"){ring(.42);ring(.62);const n=10,o=R_();for(let i=0;i<n;i++)ray(o+i*6.2832/n,.62,1);for(let i=0;i<4;i++)ray(o+i*1.57+.3,.42,.62);
    box(R_()*6.2832,.03,.1,.06,.06,R_());
    for(let i=0;i<26;i++){const ang=R_()*6.2832,f=R_()<.6?.5+R_()*.06:.7+R_()*.22,w=.06+R_()*.05;box(ang,f,w,.045+R_()*.02,.035+R_()*.035);if(R_()<.18){const t=ang+Math.PI/2;H.push({x:H[H.length-1].x+Math.cos(t)*w*r*.6,z:H[H.length-1].z+Math.sin(t)*w*r*.6,w:.045*r,d:.08*r,h:.04*r,a:ang+Math.PI/2})}}}
  else{const n=6+Math.floor(R_()*2),o=R_();for(let i=0;i<n;i++)ray(o+i*6.2832/n,.08,1);ring(.08);ring(.55,o+.4,o+4.6);
    for(let i=0;i<12;i++){const ang=R_()*6.2832,f=.35+R_()*.5;box(ang,f,.07+R_()*.04,.045+R_()*.02,.035+R_()*.025)}}
  L={roads,H};CO_HS.set(p.id,L);return L}
function coHouses(p,r,out,g,P,dpr,rx){const L=coLayout(p,r);
  g.strokeStyle="rgba(255,255,255,.9)";g.lineWidth=clamp(rx*.022,1,4)*dpr/dpr*dpr;g.lineCap="round";
  for(const q of L.roads){g.beginPath();let pen=false;for(const [x,z] of q){const s=P(x,0,z);if(!s){pen=false;continue}pen?g.lineTo(...s):g.moveTo(...s);pen=true}g.stroke()}
  for(const b of L.H){const q=project(b.x,0,b.z);if(q)out.push({...b,dep:q.w})}}
function coDrawHouse(g,b,P,dpr){const ca=Math.cos(b.a),sa=Math.sin(b.a),hw=b.w/2,hd=b.d/2,h=b.h;
  const loc=[[-hw,-hd],[hw,-hd],[hw,hd],[-hw,hd]].map(([u,v])=>[b.x+u*ca-v*sa,b.z+u*sa+v*ca]);
  const v=[...loc.map(([x,z])=>P(x,0,z)),...loc.map(([x,z])=>P(x,h,z))];if(v.some(q=>!q))return;
  const eye=camEye();g.lineJoin="round";g.lineWidth=.8*dpr;g.strokeStyle="rgba(40,52,64,.8)";
  for(let i=0;i<4;i++){const j=(i+1)%4,mx=(loc[i][0]+loc[j][0])/2,mz=(loc[i][1]+loc[j][1])/2,nx=mx-b.x,nz=mz-b.z;if((eye[0]-mx)*nx+(eye[2]-mz)*nz<=0)continue;
    const lit=.78+.18*clamp((nz*.8-nx*.4)/Math.hypot(nx,nz),-1,1);g.fillStyle=`rgb(${Math.round(250*lit)},${Math.round(251*lit)},${Math.round(253*lit)})`;
    g.beginPath();g.moveTo(...v[i]);g.lineTo(...v[j]);g.lineTo(...v[j+4]);g.lineTo(...v[i+4]);g.closePath();g.fill();g.stroke()}
  g.fillStyle="#ffffff";g.beginPath();g.moveTo(...v[4]);g.lineTo(...v[5]);g.lineTo(...v[6]);g.lineTo(...v[7]);g.closePath();g.fill();g.stroke()}

/* ---------- city streets for couriers ---------- */
function coCityPaths(p){let r=CO_CP.get(p.id);if(r)return r;r=[];
  if(G.board){const R_=(BRAD[p.type]||.04)*.92,rr=mulberry((p.id*9973+7)>>>0);const push=pts=>{const c=[0];for(let i=2;i<pts.length;i+=2)c.push(c[c.length-1]+Math.hypot(pts[i]-pts[i-2],pts[i+1]-pts[i-1]));r.push({p:pts,c,L:c[c.length-1]})};
    {const q=[];for(let k=0;k<=32;k++){const a=k/32*6.2832;q.push(p.x+Math.cos(a)*R_*.62,p.z+Math.sin(a)*R_*.62)}push(q)}
    for(let k=0;k<5;k++){const a=rr()*3.1416,o=(rr()-.5)*R_*.8,nx=-Math.sin(a),nz=Math.cos(a),h=Math.sqrt(Math.max(0,R_*R_-o*o));const q=[];for(let t=0;t<=8;t++){const s=-h+2*h*t/8;q.push(p.x+Math.cos(a)*s+nx*o,p.z+Math.sin(a)*s+nz*o)}push(q)}
    CO_CP.set(p.id,r);return r}const R0=G.board?({cap:.2,big:.16,city:.13,town:.08,vil:.04}[p.type]||.1)*1.6:(.24+Math.sqrt(p.pop)*.14)/CO_DU;
  const push=pts=>{if(pts.length<4)return;const c=[0];for(let i=2;i<pts.length;i+=2)c.push(c[c.length-1]+Math.hypot(pts[i]-pts[i-2],pts[i+1]-pts[i-1]));if(c[c.length-1]>.04)r.push({p:pts,c,L:c[c.length-1]})};
  for(const h of LOG.hw){const q=h.p;let cur=[];for(let i=0;i<q.length;i+=2){const inside=Math.hypot(q[i]-p.x,q[i+1]-p.z)<R0;if(inside)cur.push(q[i],q[i+1]);else{if(cur.length){if(i>=2)cur.push(q[i],q[i+1]);push(cur)}cur=[]}}push(cur)}
  // densify long segments so dots follow the curve, then add a few side streets
  const rr=mulberry((p.id*9973+7)>>>0);
  for(let k=0;k<6;k++){const a=rr()*6.283,L=R0*(.45+rr()*.5),pts=[p.x,p.z];let x=p.x,z=p.z,an=a;for(let q=0;q<5;q++){an+=(rr()-.5)*.9;x+=Math.cos(an)*L/5;z+=Math.sin(an)*L/5*.8;pts.push(x,z)}push(pts)}
  CO_CP.set(p.id,r);return r}
function coTipShow(e){const el=$("#coTip");if(G.board){if(!el)return;if($("#start")&&!$("#start").hidden||modalOpen){el.hidden=true;return}
    if(UI.coPickHQ){const h=coStartTip(e);if(h){el.innerHTML=h;el.hidden=false;el.style.whiteSpace="normal";el.style.width="320px";const w=el.offsetWidth,hh=el.offsetHeight;let x=e.clientX+18,y=e.clientY-hh/2;if(x+w>innerWidth-10)x=e.clientX-w-18;y=clamp(y,70,innerHeight-hh-10);el.style.left=x+"px";el.style.top=y+"px"}else el.hidden=true;return}
    {let hb=null,bd=1e9;for(const h of INC_HIT){const d=Math.hypot(h.x-e.clientX,h.y-e.clientY);if(d<h.r&&d<bd){bd=d;hb=h}}
     if(hb){el.innerHTML=hb.html;el.hidden=false;el.style.maxWidth="340px";el.style.width="340px";el.style.whiteSpace="normal";const w=el.offsetWidth,hh=el.offsetHeight;let x=e.clientX+18,y=e.clientY-hh/2;if(x+w>innerWidth-10)x=e.clientX-w-18;y=clamp(y,70,innerHeight-hh-10);el.style.left=x+"px";el.style.top=y+"px";return}el.style.maxWidth="";el.style.width="";el.style.whiteSpace=""}if(document.body.classList.contains("lplan")){el.hidden=true;return}const pid=coPlaceAt(e.clientX,e.clientY,true),h=pid!=null&&hubAt(pid);
    const vs=h?CO.veh.filter(v=>v.loc===pid&&v.st==="idle"&&VT[v.t].loc):[];if(!vs.length){const zt=pid==null?zoneTip(e):null;if(pid!=null||zt){el.innerHTML=zt||placeTip(PL[pid]);el.hidden=false;const w=el.offsetWidth,hh=el.offsetHeight;let x=e.clientX+18,y=e.clientY-hh/2;if(x+w>innerWidth-10)x=e.clientX-w-18;y=clamp(y,70,innerHeight-hh-10);el.style.left=x+"px";el.style.top=y+"px";return}el.hidden=true;return}vs.forEach(v=>{if(!v.nm)v.nm=personName()});
    const show=vs.slice(0,14),tot=vs.reduce((a,v)=>a+(v.done||0),0);
    el.innerHTML=`<div class="row sp" style="gap:12px"><b>${vs.length===1?"Доставка по місту":"×"+vs.length+" машин по місту"}</b><span class="note">${esc(PL[pid].name)} · сьогодні ${tot} пос.</span></div>
     ${show.map(v=>{const T_=VT[v.t];return `<div class="row sp" style="gap:12px;padding:5px 0;border-top:1px solid var(--line)"><span class="row" style="gap:6px">${ic(T_.ic)}<span>${esc(v.nm)}</span></span><span class="note">${T_.n.toLowerCase()} · ${v.done??0} пос. сьогодні · стан ${v.cond.toFixed(0)}%</span></div>`}).join("")}
     ${vs.length>show.length?`<div class="note" style="padding-top:5px;border-top:1px solid var(--line)">і ще ${vs.length-show.length}…</div>`:""}`;
    el.hidden=false;const w=el.offsetWidth,hh=el.offsetHeight;let x=e.clientX+18,y=e.clientY-hh/2;if(x+w>innerWidth-10)x=e.clientX-w-18;y=clamp(y,70,innerHeight-hh-10);el.style.left=x+"px";el.style.top=y+"px";return}
  if(!G.co||!CO_CL.length||$("#start")&&!$("#start").hidden){if(el)el.hidden=true;return}
  let best=null,bd=1e9;for(const c of CO_CL){const d=Math.hypot(c.x-e.clientX,c.y-e.clientY);if(d<c.r&&d<bd){bd=d;best=c}}
  if(!best){if(el)el.hidden=true;return}
  const vs=best.ids.map(id=>CO.veh.find(v=>v.id===id)).filter(Boolean);vs.forEach(v=>{if(!v.nm)v.nm=personName()});
  const p=PL[best.pid];const show=vs.slice(0,12);
  el.innerHTML=`<div class="row sp" style="gap:12px"><b>${vs.length>1?"×"+vs.length+" машин по місту":"Доставка по місту"}</b><span class="note">${esc(p.name)}</span></div>
   ${show.map(v=>{const T_=VT[v.t];return `<div class="row sp" style="gap:12px;padding:5px 0;border-top:1px solid var(--line)"><span class="row" style="gap:6px">${ic(T_.ic)}<span>${esc(v.nm)}</span></span><span class="note">${T_.n.toLowerCase()} · стан ${v.cond.toFixed(0)}%</span></div>`}).join("")}
   ${vs.length>show.length?`<div class="note" style="padding-top:5px;border-top:1px solid var(--line)">і ще ${vs.length-show.length}…</div>`:""}`;
  el.hidden=false;const w=el.offsetWidth,h=el.offsetHeight;let x=e.clientX+18,y=e.clientY-h/2;if(x+w>innerWidth-10)x=e.clientX-w-18;y=clamp(y,70,innerHeight-h-10);el.style.left=x+"px";el.style.top=y+"px"}
(function(){const d=document.createElement("div");d.id="coTip";d.className="glass";d.hidden=true;d.style.cssText="position:fixed;z-index:70;min-width:280px;max-width:480px;padding:10px 12px;pointer-events:none;font-size:12.5px;white-space:nowrap";document.body.appendChild(d);
  addEventListener("mousemove",e=>{const over=e.target&&e.target.closest&&e.target.closest("#win,#insp,#legend,#bar,#rail,#top,#ucard,#modal,#menu,.ddlist");CO_MOUSE=over?null:{clientX:e.clientX,clientY:e.clientY};if(G.co){if(over){const t=$("#coTip");if(t)t.hidden=true}else coTipShow(CO_MOUSE)}},{passive:true});addEventListener("pointerdown",()=>{const t=$("#coTip");if(t)t.hidden=true},{passive:true})})();

(function(){const cv=document.getElementById("gl");if(cv)cv.addEventListener("pointermove",e=>{if(e.buttons&&G.co&&CO.follow){CO.follow=false;toast("","Камера більше не стежить","Клікніть на транспорт ще раз, щоб стежити")}},{passive:true})})();
/* ---------- save / load glue ---------- */
function coMigrate(){let back=0;CO.veh=(CO.veh||[]).filter(v=>{if(VT[v.t])return true;back+=({bike:200,scoot:1200}[v.t]||0);return false});CO.cash+=back;
  if(CO.staff){delete CO.staff.courier;if(CO.founder){CO.staff.driver=(CO.staff.driver||0)+CO.founder;CO.founder=0}}if(CO.pool)delete CO.pool.courier;if(CO.tier<1)CO.tier=1;if(CO.xp==null)CO.xp=Math.round((CO.cdel||0)*14);
  if(!CO.veh.length&&CO.hq!=null)CO.veh.push({id:CO.uid++,t:"ltruck",loc:CO.hq,st:"idle",cond:100,km:0});
  for(const h of CO.hubs||[])if(h.ids)h.ids=h.ids.filter(id=>CO.veh.some(v=>v.id===id))}
