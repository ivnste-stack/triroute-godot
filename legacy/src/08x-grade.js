/* =====================================================================
   Grades of experience. The box in the top-left corner (it used to show the year) shows the company's grade
   as a badge whose colour changes with the grade. Hovering shows the ladder and the points to the next grade.
   Each grade opens features and is required for the next licence.
   ===================================================================== */
const GRADES=[
 {n:"Стажер",xp:0,col:"#8a96a3",u:["Перевезення по країні","М'якші дедлайни й більше коротких рейсів"]},
 {n:"Експедитор",xp:250,col:"#5fd08a",u:["Збірні рейси","Переміщення техніки між хабами","Ліцензія «Вантажні перевезення»","+3% до оплати"]},
 {n:"Диспетчер",xp:1200,col:"#4fd1c5",u:["Термінові замовлення (+40–60%)","Зміна курсу техніки в дорозі","Найм диспетчера-логіста","Ліцензія «Міжнародні перевезення»","+6% до оплати"]},
 {n:"Логіст",xp:3500,col:"#5cc8f2",u:["Ключові клієнти (+35%)","Ліцензія «Залізничний оператор»","+9% до оплати"]},
 {n:"Старший логіст",xp:8000,col:"#7d8cff",u:["Ліцензія «Морський перевізник»","+12% до оплати"]},
 {n:"Менеджер ланцюгів",xp:16000,col:"#c08bff",u:["Ліцензія «Авіаперевізник»","+15% до оплати"]},
 {n:"Директор логістики",xp:30000,col:"#ffb347",u:["Ліцензія «Глобальний інтегратор»","+18% до оплати"]},
 {n:"Магнат перевезень",xp:50000,col:"#ff6b6b",u:["Вершина: ваше ім'я знає кожен вантажовідправник","+21% до оплати"]}];
/* licences ask for the grade instead of a bare number of points */
LIC.forEach((l,i)=>{if(i>=2){l.gr=i-1;l.xp=GRADES[i-1].xp}});
function coGrade(){const x=CO.xp||0;let g=0;for(let i=0;i<GRADES.length;i++)if(x>=GRADES[i].xp)g=i;return g}
const GR_FEAT={cons:1,move:1,reroute:2,cto:2};
function grOK(f){if(SET.sandbox)return true;const need=GR_FEAT[f]||0;if(coGrade()>=need)return true;
  toast("warn",`Потрібен грейд «${GRADES[need].n}»`,`Ще ${Math.max(0,GRADES[need].xp-Math.floor(CO.xp||0)).toLocaleString("uk-UA")} досвіду. Досвід дають успішні доставки, особливо з маршрутом, прокладеним вручну.`);return false}
{const _a=ACT.consAdd;ACT.consAdd=id=>{if(!(UI.cons&&UI.cons.includes(+id))&&!grOK("cons"))return;return _a(id)}}
{const _a=ACT.coMove;if(_a)ACT.coMove=id=>{if(!grOK("move"))return;return _a(id)}}
{const _a=ACT.srOpen;if(_a)ACT.srOpen=id=>{if(!grOK("reroute"))return;return _a(id)}}
{const _a=ACT.coHireM;ACT.coHireM=a=>{if(String(a).split(":")[0]==="cto"&&!grOK("cto"))return;return _a(a)}}
/* the badge: a shield in the grade's colour with chevrons for the grade */
function grBadge(g,sz){const c=GRADES[g].col,chev=y=>`<path d="M10 ${y}l6-3.4 6 3.4" fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`;let inner="";
  if(g===0)inner=`<circle cx="16" cy="15.5" r="2.6" fill="${c}"/>`;
  else if(g<4)for(let i=0;i<g;i++)inner+=chev(20-i*4.4);
  else{inner=`<path d="M16 6.4l1.5 3 3.3.5-2.4 2.3.6 3.3-3-1.6-3 1.6.6-3.3-2.4-2.3 3.3-.5z" fill="${c}"/>`;for(let i=0;i<g-4;i++)inner+=chev(21.5-i*3.6)}
  return `<svg width="${sz}" height="${sz}" style="width:${sz}px;height:${sz}px;flex:none;display:block" viewBox="0 0 32 32" aria-hidden="true"><path d="M16 2.5 27 6.5v8.6c0 7-4.7 12.2-11 14.4C9.7 27.3 5 22.1 5 15.1V6.5z" fill="${c}22" stroke="${c}" stroke-width="1.8" stroke-linejoin="round"/>${inner}</svg>`}
function grTip(){const g=coGrade(),x=Math.floor(CO.xp||0),nx=GRADES[g+1],G0=GRADES[g];
  const pct=nx?Math.round((x-G0.xp)/(nx.xp-G0.xp)*100):100;
  const ladder=GRADES.map((q,i)=>`<div class="row" style="gap:8px;margin-top:4px;opacity:${i<=g?1:.55}"><span style="display:inline-flex">${grBadge(i,16)}</span><b style="color:${i===g?q.col:"inherit"}">${q.n}</b><span class="note" style="margin-left:auto">${q.xp.toLocaleString("uk-UA")}</span></div>${i===g+1?`<div class="note" style="margin:2px 0 0 24px;font-size:11px">${q.u.join(" · ")}</div>`:""}`).join("");
  return `<b style="color:${G0.col}">Грейд: ${G0.n}</b><div class="note" style="margin-top:4px">Досвід ${x.toLocaleString("uk-UA")}${nx?` · до «${nx.n}» ще ${(nx.xp-x).toLocaleString("uk-UA")}`:" · найвищий грейд"}</div>
    <div style="height:6px;background:rgba(255,255,255,.08);margin:6px 0 4px"><i style="display:block;height:100%;width:${pct}%;background:${G0.col}"></i></div>${ladder}
    <div class="note" style="margin-top:6px;font-size:11px">Досвід дають успішні доставки: за маршрут, прокладений вручну, — повний, за маршрут диспетчера-логіста — 8%.</div>`}
function grBox(){const el=$("#yearBox");if(!el)return;if(!G.co){if(el.dataset.gr!=="y"){el.dataset.gr="y";el.textContent=G.date.y;el.removeAttribute("data-tip")}return}
  const g=coGrade(),x=Math.floor(CO.xp||0),key=g+":"+x;if(el.dataset.gr===key)return;el.dataset.gr=key;
  el.innerHTML=grBadge(g,30);el.classList.add("grbox");el.style.color=GRADES[g].col;el.dataset.tip=grTip();
  if(CO.grd==null)CO.grd=g;else if(g>CO.grd){CO.grd=g;const q=GRADES[g];coNews("good","star",`${CO.name} отримала грейд «${q.n}»`);toast("good",`Новий грейд: ${q.n}`,q.u.join(" · "))}}
setInterval(()=>{try{if(G.co&&CO.hubs)grBox()}catch(e){}},800);
/* the trip card is rebuilt every 0.7 s: keep the hover look on whatever the pointer is over, or it blinks */
let UC_H=null;
(function(){const el=document.getElementById("ucard");if(!el)return;el.addEventListener("pointerover",e=>{const a=e.target.closest&&e.target.closest("[data-act]");UC_H=a&&el.contains(a)?{act:a.dataset.act,arg:a.dataset.arg}:null});el.addEventListener("pointerleave",()=>{UC_H=null;el.querySelectorAll(".hov").forEach(x=>x.classList.remove("hov"))})})();
{const _c=coCard;coCard=function(){const r=_c.apply(this,arguments);if(UC_H){const s=`#ucard [data-act="${UC_H.act}"]`+(UC_H.arg!=null?`[data-arg="${UC_H.arg}"]`:"");const x=document.querySelector(s);if(x)x.classList.add("hov")}return r}}
/* test switch «Пришвидшений прогрес ×5»: every finished trip counts five times for experience, deliveries, contracts and revenue */
{const _c=coComplete;coComplete=function(j){if(!SET.fastprog||!G.co)return _c.apply(this,arguments);
  const b={xp:CO.xp||0,del:CO.deliv||0,cd:CO.cdel||0,loc:CO.m.local||0,con:CO.m.contract||0,r:CO.rating};const res=_c.apply(this,arguments);
  const K=4,dl=(CO.m.local||0)-b.loc,dc=(CO.m.contract||0)-b.con;
  CO.xp=(CO.xp||0)+K*Math.max(0,(CO.xp||0)-b.xp);CO.deliv=(CO.deliv||0)+K*Math.max(0,(CO.deliv||0)-b.del);CO.cdel=(CO.cdel||0)+K*Math.max(0,(CO.cdel||0)-b.cd);
  if(dl>0){CO.m.local+=K*dl;CO.cash+=K*dl}if(dc>0){CO.m.contract+=K*dc;CO.cash+=K*dc}
  const dr=CO.rating-b.r;if(dr>0)CO.rating=clamp(CO.rating+2*dr,1,5);return res}}
