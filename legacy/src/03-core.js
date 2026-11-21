"use strict";
/* ================= ICONS ================= */
const ICONS={
home:'<path d="M3 11l9-8 9 8M5 10v10h14V10"/>',
coins:'<ellipse cx="12" cy="6" rx="7" ry="3"/><path d="M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6"/>',
building:'<path d="M3 21h18M5 21V10M19 21V10M9.7 21V10M14.3 21V10M2 10l10-6 10 6z"/>',
scale:'<path d="M12 3v18M7 21h10M5 7h14M5 7l-3 7h6zM19 7l-3 7h6z"/>',
users:'<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><circle cx="17" cy="9" r="2.5"/><path d="M16.5 14c2.8 0 5 1.8 5 5"/>',
chart:'<path d="M3 3v18h18"/><path d="M7 15l4-5 3 3 5-7"/>',
trade:'<path d="M4 8h14l-3.5-3.5M20 16H6l3.5 3.5"/>',
globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18"/>',
org:'<circle cx="12" cy="5" r="2.5"/><circle cx="5" cy="18" r="2.5"/><circle cx="19" cy="18" r="2.5"/><path d="M12 7.5v4M12 11.5L6.5 16M12 11.5l5.5 4.5"/>',
eye:'<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
swords:'<path d="M4 4l11 11M4 4h4M4 4v4M20 4L9 15M20 4h-4M20 4v4M13 17l4 4M17 17l-4 4M11 17l-4 4M7 17l4 4"/>',
news:'<path d="M4 5h13v14H6a2 2 0 0 1-2-2zM17 9h3v8a2 2 0 0 1-2 2"/><path d="M7 9h7M7 13h7M7 16h4"/>',
mail:'<rect x="3" y="5" width="18" height="14"/><path d="M3 7l9 6 9-6"/>',
play:'<path d="M7 4.5l12 7.5-12 7.5z"/>',
pause:'<path d="M8 5v14M16 5v14"/>',
ff:'<path d="M3 5.5l8 6.5-8 6.5zM12 5.5l8 6.5-8 6.5z"/>',
fff:'<path d="M2 6l6 6-6 6zM9 6l6 6-6 6zM16 6l6 6-6 6z"/>',
close:'<path d="M6 6l12 12M18 6L6 18"/>',
bolt:'<path d="M13 2L4 14h7l-1 8 9-12h-7z"/>',
house:'<path d="M3 11l9-7 9 7v10H3zM9 21v-6h6v6"/>',
heart:'<path d="M12 20s-8-4.6-8-10.5A4.5 4.5 0 0 1 12 7a4.5 4.5 0 0 1 8 2.5C20 15.4 12 20 12 20z"/>',
book:'<path d="M4 4h6a2 2 0 0 1 2 2v14a2 2 0 0 0-2-2H4zM20 4h-6a2 2 0 0 0-2 2v14a2 2 0 0 1 2-2h6z"/>',
umbrella:'<path d="M3 12a9 9 0 0 1 18 0zM12 12v7a2 2 0 0 0 4 0M12 3v0"/>',
shield:'<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
siren:'<path d="M6 18v-6a6 6 0 0 1 12 0v6M4 18h16v3H4zM12 2.5v2M3.8 6.3l1.4 1.4M20.2 6.3l-1.4 1.4"/>',
road:'<path d="M8 3L4 21M16 3l4 18M12 4v3M12 10v3M12 16v4"/>',
wheat:'<path d="M12 21V8M12 9c-3 0-4.5-2.5-4.5-5 2.5 0 4.5 1.5 4.5 5zM12 9c3 0 4.5-2.5 4.5-5-2.5 0-4.5 1.5-4.5 5zM12 15c-3 0-4.5-2.5-4.5-5 2.5 0 4.5 1.5 4.5 5zM12 15c3 0 4.5-2.5 4.5-5-2.5 0-4.5 1.5-4.5 5z"/>',
factory:'<path d="M3 21V10l6 4v-4l6 4V4h4v17zM3 21h18M7 17h2M12 17h2"/>',
leaf:'<path d="M5 19C5 10 10 5 20 4c0 10-5 15-14 15zM5 19l8-8"/>',
gavel:'<path d="M13 3.5l7.5 7.5M10 6.5l7.5 7.5M11.5 5l-4 4M19 12.5l-4 4M9.5 11.5L3 18M3 21h10"/>',
briefcase:'<rect x="3" y="7" width="18" height="13"/><path d="M9 7V4h6v3M3 12.5h18"/>',
alert:'<path d="M12 3l10 18H2zM12 10v5M12 18v.4"/>',
info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.4"/>',
help:'<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17v.4"/>',
check:'<path d="M4 12.5l5 5L20 6.5"/>',
up:'<path d="M12 19V5M5.5 11.5L12 5l6.5 6.5"/>',
down:'<path d="M12 5v14M5.5 12.5L12 19l6.5-6.5"/>',
layers:'<path d="M12 3l9 5-9 5-9-5zM3 13l9 5 9-5"/>',
crown:'<path d="M3 19h18M4 16L3 7l5 4 4-6 4 6 5-4-1 9z"/>',
flame:'<path d="M12 21c-4 0-7-3-7-7 0-4 4-6 4-10 3 2 5 4 5 7 1-1 2-2 2-4 2 2 3 4 3 7 0 4-3 7-7 7z"/>',
target:'<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
cpu:'<rect x="6" y="6" width="12" height="12"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4"/>',
skull:'<path d="M12 3a8 8 0 0 0-8 8c0 2.6 1.2 4.6 3 5.8V20h10v-3.2c1.8-1.2 3-3.2 3-5.8a8 8 0 0 0-8-8z"/><circle cx="9" cy="11" r="1.6"/><circle cx="15" cy="11" r="1.6"/><path d="M10 20v-2M14 20v-2"/>',
doc:'<path d="M6 3h9l4 4v14H6z"/><path d="M14 3v5h5M9 12h7M9 15.5h7M9 19h4"/>',
menu:'<path d="M4 6.5h16M4 12h16M4 17.5h16"/>',
gear:'<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v2.6M12 18.6v2.6M21.2 12h-2.6M5.4 12H2.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8M18.5 18.5l-1.8-1.8M7.3 7.3L5.5 5.5"/><circle cx="12" cy="12" r="6.4"/>',
pill:'<path d="M10.5 3.5a5 5 0 0 1 7 7l-7 7a5 5 0 0 1-7-7zM7 7l7 7"/>',
atom:'<circle cx="12" cy="12" r="1.5"/><ellipse cx="12" cy="12" rx="10" ry="4"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(60 12 12)"/><ellipse cx="12" cy="12" rx="10" ry="4" transform="rotate(-60 12 12)"/>',
ore:'<path d="M2 20L9 7l4 7 2-3 7 9z"/>',
tree:'<path d="M12 2l6 9h-3l4 6H5l4-6H6zM12 17v5"/>',
beam:'<path d="M4 5h16M4 19h16M12 5v14M8 5v2M16 5v2M8 19v-2M16 19v-2"/>',
battery:'<rect x="3" y="7" width="16" height="10"/><path d="M21 10v4M7 10v4M11 10v4"/>',
gem:'<path d="M6 3h12l4 6-10 12L2 9zM2 9h20M9 3l3 18M15 3l-3 18"/>',
coil:'<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>',
sack:'<path d="M8.5 3h7l-2 3.5c4 2 6.5 6 6.5 9a5.5 5.5 0 0 1-5.5 5.5h-5A5.5 5.5 0 0 1 4 15.5c0-3 2.5-7 6.5-9z"/>',
coal:'<path d="M3 17l4-7 5 2 3-5 6 6-2.5 6H5z"/>',
gas:'<path d="M12 22a6 6 0 0 0 6-6c0-4-6-11-6-11s-6 7-6 11a6 6 0 0 0 6 6z"/><path d="M12 19a2.5 2.5 0 0 0 2.5-2.5c0-1.6-2.5-4-2.5-4s-2.5 2.4-2.5 4A2.5 2.5 0 0 0 12 19z"/>',
barrel:'<path d="M6 3h12v18H6zM6 8h12M6 16h12"/>',
mega:'<path d="M3 10v4h4l9 5V5L7 10zM19.5 9a4 4 0 0 1 0 6"/>',
flag:'<path d="M5 21V4M5 4h12l-2 4 2 4H5"/>',
dollar:'<path d="M12 2v20M17 6H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
user:'<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>',
chev:'<path d="M6 9l6 6 6-6"/>',
bulb:'<path d="M9 18h6M10 21h4M12 3a6 6 0 0 0-4 10.5c.8.8 1 1.5 1 2.5h6c0-1 .2-1.7 1-2.5A6 6 0 0 0 12 3z"/>',
lock:'<rect x="5" y="11" width="14" height="10"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
dice:'<rect x="4" y="4" width="16" height="16"/><circle cx="9" cy="9" r=".8"/><circle cx="15" cy="15" r=".8"/><circle cx="15" cy="9" r=".8"/><circle cx="9" cy="15" r=".8"/>',
plus:'<path d="M12 5v14M5 12h14"/>',
minus:'<path d="M5 12h14"/>',
handshake:'<path d="M2 11l4-4 4 2 3-2 4 1 5 4M2 11l6 6 2-1 2 2 2-1 2 1 4-5M10 9l4 4"/>',
wave:'<path d="M2 8c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2M2 14c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2M2 20c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2"/>',
quake:'<path d="M2 12h4l2-5 3 10 3-14 3 13 2-4h3"/>',
virus:'<circle cx="12" cy="12" r="5"/><path d="M12 2v5M12 17v5M2 12h5M17 12h5M5 5l3.5 3.5M15.5 15.5L19 19M5 19l3.5-3.5M15.5 8.5L19 5"/>',
wind:'<path d="M3 8h11a3 3 0 1 0-3-3M3 12h16a3 3 0 1 1-3 3M3 16h7"/>',
sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
cyber:'<rect x="3" y="4" width="18" height="12"/><path d="M8 20h8M12 16v4M8 9l2 2-2 2M12 13h4"/>',
spark:'<path d="M12 2l2.2 6.8L21 11l-6.8 2.2L12 20l-2.2-6.8L3 11l6.8-2.2z"/>',
fist:'<path d="M7 11V6a1.5 1.5 0 0 1 3 0v4M10 10V5a1.5 1.5 0 0 1 3 0v5M13 10V6a1.5 1.5 0 0 1 3 0v5M16 11V8a1.5 1.5 0 0 1 3 0v6c0 4-3 7-7 7s-7-2-7-6v-2a2 2 0 0 1 2-2h3"/>',
mapIc:'<path d="M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3zM9 3v15M15 6v15"/>',
send:'<path d="M3 11l18-8-8 18-2-8z"/>',
trash:'<path d="M4 7h16M9 7V4h6v3M6 7l1 14h10l1-14"/>',
refresh:'<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
star:'<path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z"/>',
pin:'<path d="M12 21s-7-6-7-11a7 7 0 0 1 14 0c0 5-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>',
ship:'<path d="M3 15l2.5 5h13l2.5-5zM5.5 15V9h13v6M9 9V5h5l2 4M11 5V3"/>',
plane:'<path d="M21 15.5v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0v5l-8 5v2l8-2.5V18l-2 1.5V21l3.5-1 3.5 1v-1.5L13 18v-5z"/>',
anchor:'<circle cx="12" cy="5" r="2"/><path d="M12 7v14M5 13a7 7 0 0 0 14 0M8.5 10h7"/>',
bike:'<path d="M2 17.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M15 17.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M5.5 17.5L9 9h6l3.5 8.5M9 9l3 8.5M14 5h2.5l1 4"/>',scooter:'<path d="M3 17a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M16 17a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0M8 17h8M13 17l-1-7h3l3 7M12 10l-1-4H8"/>',van:'<path d="M2 7h11l4 4h4v6H2zM13 7v4h4M6 19a2 2 0 1 0 0-.1M17 19a2 2 0 1 0 0-.1"/>',train:'<path d="M6 3h12a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zM4 11h16M8 21l2-4M16 21l-2-4M8 14h.01M16 14h.01"/>',box:'<path d="M3 7l9-4 9 4v10l-9 4-9-4zM3 7l9 4 9-4M12 11v10"/>',truck:'<path d="M2 6h12v10H2zM14 9h4l4 4v3h-8M6 19a2 2 0 1 0 0-.1M17 19a2 2 0 1 0 0-.1"/>',
};
function ic(n,c=""){return `<svg class="ic ${c}"><use href="#i-${n}"/></svg>`}
(function(){let s="";for(const k in ICONS)s+=`<symbol id="i-${k}" viewBox="0 0 24 24">${ICONS[k]}</symbol>`;document.getElementById("iconDefs").innerHTML=s;})();

/* ================= RNG / UTIL ================= */
function mulberry(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
let R=Math.random;
const rnd=(a=1,b)=>b===undefined?R()*a:a+R()*(b-a);
const rint=(a,b)=>Math.floor(rnd(a,b+1));
const pick=a=>a[Math.floor(R()*a.length)];
const chance=p=>R()<p;
const clamp=(v,a=0,b=100)=>v<a?a:v>b?b:v;
const lerp=(a,b,t)=>a+(b-a)*t;
const sstep=(a,b,x)=>{const t=clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)};
function shuffle(a){for(let i=a.length-1;i>0;i--){const j=Math.floor(R()*(i+1));[a[i],a[j]]=[a[j],a[i]]}return a}
const $=s=>document.querySelector(s);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

function fmtPop(m){return m>=1000?(m/1000).toFixed(2)+" млрд":m>=10?m.toFixed(0)+" млн":m.toFixed(1)+" млн"}
const MONTHS=["січ","лют","бер","кві","тра","чер","лип","сер","вер","жов","лис","гру"];
const MONTHS_FULL=["січня","лютого","березня","квітня","травня","червня","липня","серпня","вересня","жовтня","листопада","грудня"];
function dateStr(d){return `${d.d} ${MONTHS_FULL[d.m]} ${d.y}`}
function dayDate(t){const D={...G.date};let n=Math.floor(t)-G.day;const dim=[31,28,31,30,31,30,31,31,30,31,30,31];while(n>0){D.d++;if(D.d>dim[D.m]){D.d=1;D.m++;if(D.m>11){D.m=0;D.y++}}n--}
  const h=Math.floor(((t%1)+1)%1*24);return `${D.d} ${MONTHS_FULL[D.m]}, ${String(h).padStart(2,"0")}:00`}
function shortDate(d){return `${String(d.d).padStart(2,"0")} ${MONTHS[d.m]} ${String(d.y).slice(2)}`}

/* ================= NAMES ================= */
const SYL_A=["Ва","Ве","Ко","Ар","Ел","Мо","Та","Ра","Сі","Лу","Ор","Да","Бе","Ка","Не","Ір","Ос","За","Вел","Тор","Гал","Мир","Кар","Сол","Аль","Бор","Дор","Фар","Хел","Нор","Ул","Ям","Кес","Лір","Мар","Сен","Тал","Едр","Аур","Віс","Грен","Зел"];
const SYL_B=["ла","ра","ве","ні","до","ри","на","ме","ло","ста","ти","се","ва","ге","мі","ко","",""];
const SYL_C=["ія","ан","ленд","стан","ора","ея","ин","ар","онія","ендія","ада","ент","ура","ійя","ос","ова","анія","ур"];
const FIRST=["Арвін","Ліра","Маркус","Сельма","Давор","Іліана","Рустам","Ерік","Нора","Тео","Камілла","Віктор","Аміра","Йонас","Мілена","Оскар","Зара","Леон","Ірма","Бруно","Хана","Феліція","Рафаель","Ада","Казимир","Ярема","Інга","Матео","Соня","Гюнтер","Олена","Тарас","Адріан","Вероніка","Ісмаїл","Дана","Кірра","Еміль","Самуель","Марта","Луїза","Тамір"];
const LAST=["Вальден","Корса","Ренгард","Остаріо","Белов","Маркос","Тальберг","Ністрем","Кавано","Деметріу","Сарін","Ольховський","Ферран","Гольм","Ріваль","Карпа","Мендес","Лоран","Штайн","Оката","Новак","Дракер","Віллар","Ардені","Квіст","Мороз","Еспіно","Галлахер","Бранд","Сівак","Орсіні","Тамура","Левицька","Костелло","Джабарі","Фрост"];
function genCountryName(used){
  for(let k=0;k<200;k++){
    let n=pick(SYL_A)+pick(SYL_B)+pick(SYL_C);
    n=n.replace(/([аеиіоуяю])([аеиіоуяюї])/g,(m,a,b)=>a+"р"+b);
    if(n.length<5||n.length>11||used.has(n))continue;
    used.add(n);return n;
  }
  return "Земля "+used.size;
}
function personName(){return pick(FIRST)+" "+pick(LAST)}
function initials(n){return n.split(" ").map(s=>s[0]).join("").slice(0,2)}

/* ================= FLAGS ================= */
const FLAGCOL=["#c8312f","#1f4fa0","#f2f2ee","#f2c230","#1f8a4c","#1b1b1b","#3d9be0","#e57a1f","#7a1f2b","#11807a","#5b2d8a"];
function genFlag(){
  const c=document.createElement("canvas");c.width=120;c.height=80;const g=c.getContext("2d");
  const cols=shuffle(FLAGCOL.slice());const [a,b,d,e]=cols;const t=rint(0,8);
  const rect=(x,y,w,h,col)=>{g.fillStyle=col;g.fillRect(x,y,w,h)};
  switch(t){
    case 0:rect(0,0,120,27,a);rect(0,27,120,26,b);rect(0,53,120,27,d);break;
    case 1:rect(0,0,40,80,a);rect(40,0,40,80,b);rect(80,0,40,80,d);break;
    case 2:rect(0,0,120,40,a);rect(0,40,120,40,b);break;
    case 3:rect(0,0,120,80,a);rect(30,0,14,80,b);rect(0,33,120,14,b);break;
    case 4:for(let i=0;i<7;i++)rect(0,i*80/7,120,80/7+1,i%2?b:a);rect(0,0,52,46,d);break;
    case 5:rect(0,0,120,80,a);g.fillStyle=b;g.beginPath();g.moveTo(0,0);g.lineTo(120,0);g.lineTo(0,80);g.fill();g.strokeStyle=d;g.lineWidth=10;g.beginPath();g.moveTo(120,0);g.lineTo(0,80);g.stroke();break;
    case 6:rect(0,0,120,27,a);rect(0,27,120,26,b);rect(0,53,120,27,a);g.fillStyle=d;g.beginPath();g.moveTo(0,0);g.lineTo(50,40);g.lineTo(0,80);g.fill();break;
    case 7:rect(0,0,120,80,a);g.fillStyle=b;g.beginPath();g.arc(60,40,22,0,7);g.fill();break;
    default:rect(0,0,120,80,a);rect(0,58,120,22,b);rect(0,52,120,6,d);
  }
  if(chance(.5)){ // emblem
    const ex=t===4?26:t===6?18:t===3?37:60,ey=t===4?23:t===3?40:40;
    g.fillStyle=t===7?a:e;g.save();g.translate(ex,ey);
    const k=rint(0,2);
    if(k===0){g.beginPath();for(let i=0;i<10;i++){const r=i%2?5:12,an=i*Math.PI/5-Math.PI/2;g.lineTo(Math.cos(an)*r,Math.sin(an)*r)}g.fill()}
    else if(k===1){g.beginPath();g.arc(0,0,9,0,7);g.fill();g.fillStyle=t===7?b:a;g.beginPath();g.arc(4,-2,8,0,7);g.fill()}
    else{g.beginPath();g.moveTo(0,-11);g.lineTo(10,0);g.lineTo(0,11);g.lineTo(-10,0);g.fill()}
    g.restore();
  }
  return c.toDataURL();
}
