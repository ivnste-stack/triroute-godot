/* =====================================================================
   Consolidated road trips («Збірний рейс»): several exchange orders in one truck.
   The player picks orders, the truck must hold their total weight AND volume, and the
   player sets the order of pick-ups and drop-offs; every order is paid at its own drop
   against its own deadline.
   ===================================================================== */
UI.cons=UI.cons||[];UI.consSt=UI.consSt||[];
const consOK=k=>k&&!k.legs&&!k.multi;
const kVol=k=>+(k.tons*((CARGO_I[k.cg]&&CARGO_I[k.cg].v)||3)).toFixed(1);
function consOrders(){UI.cons=UI.cons.filter(id=>CO.board.some(k=>k.id===id));UI.consSt=UI.consSt.filter(s=>UI.cons.includes(s.id));return UI.cons.map(id=>CO.board.find(k=>k.id===id))}
ACT.consAdd=id=>{id=+id;const k=CO.board.find(x=>x.id===id);if(!consOK(k))return;
  if(UI.cons.includes(id)){UI.cons=UI.cons.filter(x=>x!==id);UI.consSt=UI.consSt.filter(s=>s.id!==id)}
  else{if(UI.cons.length>=6)return toast("warn","Забагато замовлень","У збірний рейс — до 6 замовлень");UI.cons.push(id);
    const lp=UI.consSt.map(s=>s.kind).lastIndexOf("pick");UI.consSt.splice(lp+1,0,{id,kind:"pick"});UI.consSt.push({id,kind:"drop"})}
  UI.consV=null;renderWin();REDRAW=true};
ACT.consClear=()=>{UI.cons=[];UI.consSt=[];UI.consV=null;renderWin();REDRAW=true};
ACT.consMv=a=>{const [i,d]=a.split(":").map(Number),j=i+d,S=UI.consSt;if(j<0||j>=S.length)return;const T=S.slice();[T[i],T[j]]=[T[j],T[i]];
  for(const id of UI.cons){if(T.findIndex(s=>s.id===id&&s.kind==="pick")>T.findIndex(s=>s.id===id&&s.kind==="drop"))return toast("warn","Спершу забрати, потім доставити","Пункт доставки не може стояти раніше за пункт завантаження цього ж замовлення")}
  UI.consSt=T;renderWin();REDRAW=true};
ACT.consVeh=v=>{UI.consV=+v;renderWin();REDRAW=true};
/* the whole trip: the vehicle, the road between the stops, an ETA at each stop */
function consPlan(){const ks=consOrders();if(!ks.length)return null;const S=UI.consSt.map(s=>({...s,k:ks.find(k=>k.id===s.id)})).filter(s=>s.k);
  const tons=+ks.reduce((a,k)=>a+k.tons,0).toFixed(1),vol=+ks.reduce((a,k)=>a+kVol(k),0).toFixed(1),out={ks,S,tons,vol,why:null};
  for(const k of ks){if(k.minR&&CO.rating<k.minR){out.why=`Замовник хоче рейтинг ${k.minR.toFixed(1)}+`;break}const nd=permNeed(CARGO_I[k.cg],"road").filter(x=>!permOK(x));if(nd.length){out.why=`Потрібна ліцензія «${PERM_I[nd[0]].n}»`;break}}
  const free=coCrewFree(),pid0=S[0].kind==="pick"?S[0].k.from:S[0].k.to;
  const cand=CO.veh.filter(v=>{const T=VT[v.t];return T.mode==="road"&&v.st==="idle"&&(hubAt(v.loc)||v.idle0!=null&&coNow()-v.idle0<1)&&T.cap>=tons&&(T.vol||1e9)>=vol&&free.driver>=(T.crew||1)});
  out.cand=cand;if(!cand.length){out.why=out.why||`Немає вільної машини з водієм, що вмістить ${tons} т і ${vol} м³`;return out}
  const lr=v=>coRoute("road",v.loc,pid0);let v=cand.find(x=>x.id===UI.consV);if(!v)v=cand.slice().sort((a,b)=>((lr(a)||{len:1e9}).len-(lr(b)||{len:1e9}).len)||VT[a.t].cost-VT[b.t].cost)[0];
  const T=VT[v.t],leadR=lr(v);if(!leadR){out.why="Машина не доїде до першого пункту";return out}
  const sp=T.spd*spdK(),pause=pid=>HAND.road*handK()*.6*handF(pid);let t=leadR.len/sp,s=leadR.len;const legs=[];out.v=v;out.T=T;out.leadR=leadR;
  S.forEach((st,i)=>{const pid=st.kind==="pick"?st.k.from:st.k.to;st.pid=pid;if(i>0){const prev=S[i-1].pid,r=coRoute("road",prev,pid);if(!r){out.why=`Немає дороги ${PL[prev].name} → ${PL[pid].name}`;return}legs.push(r);t+=r.len/sp;s+=r.len}
    st.s=s;const same=i>0&&S[i-1].pid===pid;t+=i===0||i===S.length-1?HAND.road*handK()*handF(pid):same?0:pause(pid);st.eta=t;if(st.kind==="drop")st.late=Math.max(0,t-st.k.dlDays)});
  if(out.why)return out;const len=s-leadR.len;out.legs=legs;out.len=len;out.tot=t;
  out.fuel=Math.round((leadR.len+len)*T.fuel*CO.fuel*fuelK("road"));const run=(T.up*repK()*[.8,1,1.35][CO.maint]+ROLE.driver.w*wageK(G.me)*CO.wageLv/30*(T.crew||1))*t;
  out.pay=ks.reduce((a,k)=>a+k.pay,0);out.profit=Math.round(out.pay-out.fuel-run);return out}
/* the panel on the exchange */
function consPanel(){const ks=consOrders();if(!ks.length)return "";
  const m=ks[0].mode,tons=+ks.reduce((a,k)=>a+k.tons,0).toFixed(1),vol=+ks.reduce((a,k)=>a+kVol(k),0).toFixed(1);
  let why=null;for(const k of ks){if(k.minR&&CO.rating<k.minR){why=`Замовник хоче рейтинг ${k.minR.toFixed(1)}+`;break}const nd=permNeed(CARGO_I[k.cg],m).filter(x=>!permOK(x));if(nd.length){why=`Потрібна ліцензія «${PERM_I[nd[0]].n}»`;break}}
  const own=CO.veh.filter(v=>VT[v.t].mode===m&&(v.st==="idle"||isRetV(v))&&!v.resv);if(!why&&!own.length)why=`Немає вільної техніки: ${MODE_N[m].toLowerCase()}`;
  /* what has to travel together at least: everything picked up in one city is loaded at once */
  const byCity=new Map();for(const k of ks){const c=byCity.get(k.from)||{t:0,v:0};c.t+=k.tons;c.v+=kVol(k);byCity.set(k.from,c)}let needT=0,needV=0;for(const c of byCity.values()){needT=Math.max(needT,c.t);needV=Math.max(needV,c.v)}needT=+needT.toFixed(1);needV=+needV.toFixed(1);
  if(!why&&own.length&&!own.some(v=>VT[v.t].cap>=needT&&(VT[v.t].vol||1e9)>=needV))why=`Немає вільної техніки, що вмістить ${needT} т і ${needV} м³ разом — ${byCity.size===1?"усі замовлення завантажуються в одному місті":"стільки забирається в одному місті"}`;
  const big=own.reduce((a,v)=>VT[v.t].cap>a.cap?VT[v.t]:a,{cap:0,vol:0,n:""});
  return `<div class="blk" style="border-color:rgba(92,200,242,.55);margin-bottom:12px"><div class="row sp wrap"><b>${ic(MODE_IC[m])} Збірний рейс · ${LP_N[m]} · ${ks.length} замовлення</b><button class="btn sm" data-act="consClear">${ic("close")}Скасувати</button></div>
   <div style="display:flex;flex-direction:column;gap:4px;margin-top:8px">${ks.map(k=>`<div class="lrow" style="padding:5px 8px"><span class="acc">${ic(CARGO_I[k.cg].ic)}</span><div style="min-width:0;flex:1"><b>${esc(PL[k.from].name)} → ${esc(PL[k.to].name)}</b><div class="note">${esc(CARGO_I[k.cg].n)} · ${k.tons} т · ${kVol(k)} м³ · дедлайн ${daysS(k.dlDays)} · ${fmtUSD(k.pay)}</div></div><button class="btn sm" data-act="consAdd" data-arg="${k.id}" aria-label="Прибрати">${ic("close")}</button></div>`).join("")}</div>
   <div class="note" style="margin-top:8px">Разом ${tons} т · ${vol} м³${big.cap?` · найбільша вільна: ${esc(big.n)} (${big.cap} т, ${big.vol} м³)`:""}. Порядок зупинок і дорогу ви прокладаєте самі: забрати можна в будь-якому порядку, але доставити — лише те, що вже в кузові.</div>
   ${why?`<div class="note bad" style="margin-top:6px">${ic("alert")} ${esc(why)}</div>`:""}
   <button class="btn pri" style="width:100%;margin-top:10px" data-act="consRoute" ${why||ks.length<2||!lpOn()?"disabled":""}>${ic("road")}${ks.length<2?"Додайте ще замовлення":"Прокласти маршрут збірного рейсу"}</button></div>`}
ACT.consAdd=id=>{id=+id;const k=CO.board.find(x=>x.id===id);if(!consOK(k))return;
  if(UI.cons.includes(id)){UI.cons=UI.cons.filter(x=>x!==id)}
  else{const ks=consOrders();if(ks.length&&ks[0].mode!==k.mode)return toast("warn","Інший вид транспорту",`У збірному рейсі — лише ${LP_N[ks[0].mode].toLowerCase()}: одна техніка везе всі замовлення`);if(UI.cons.length>=6)return toast("warn","Забагато замовлень","У збірний рейс — до 6 замовлень");UI.cons.push(id)}
  renderWin();REDRAW=true};
ACT.consRoute=()=>{const ks=consOrders();if(ks.length<2)return;const m=ks[0].mode;
  const kC={id:CO.uid++,from:ks[0].from,to:ks[ks.length-1].to,cg:ks[0].cg,tons:+ks.reduce((a,k)=>a+k.tons,0).toFixed(1),_vol:+ks.reduce((a,k)=>a+kVol(k),0).toFixed(1),pay:ks.reduce((a,k)=>a+k.pay,0),dlDays:Math.max(...ks.map(k=>k.dlDays)),mode:m,risk:0,minR:0,len:ks.reduce((a,k)=>a+k.len,0),
    cons:ks.map(k=>({id:k.id,from:k.from,to:k.to,cg:k.cg,tons:k.tons,vol:kVol(k),pay:k.pay,dl:k.dlDays}))};
  lpOpen(kC,false)};
/* the planner side: what is in the vehicle on each leg, when each order arrives */
function lpCalcCons(){const k=LP.k,O=k.cons,gr=lpGroups(),seq=[LP.pts[0],...gr.G.map(g=>g.b)],picked=new Set(),dropped=new Set(),evAt=[],load=[],vols=[];let t_=0,v_=0,maxT=0,maxV=0;
  seq.forEach(pid=>{const ev=[];if(!lpIsW(pid)){for(const o of O)if(!picked.has(o.id)&&o.from===pid){picked.add(o.id);ev.push({o,kind:"pick"});t_+=o.tons;v_+=o.vol}
      for(const o of O)if(picked.has(o.id)&&!dropped.has(o.id)&&o.to===pid&&!ev.some(e=>e.o===o)){dropped.add(o.id);ev.push({o,kind:"drop"});t_-=o.tons;v_-=o.vol}}
    evAt.push(ev);load.push(+Math.max(0,t_).toFixed(2));vols.push(+Math.max(0,v_).toFixed(2));maxT=Math.max(maxT,t_);maxV=Math.max(maxV,v_)});
  const legs=[];let consBlock=null;gr.G.forEach((g,i)=>{if(consBlock)return;const r=g.r,tons=i===0?Math.max(.1,maxT):Math.max(.1,load[i]),vol=i===0?maxV:vols[i];
    const kk={...k,multi:null,legs:null,cons:null,from:g.a,to:g.b,mode:g.m,minR:0,tons,_vol:vol,_one:true,_veh:i?LP.consVeh:(LP.veh0??null),...(i?{}:{_ctry:PL[LP.pts[0]].cid}),pay:0};let P=null;
    if(lpUnlocked(g.m)){try{P=lpWith(g.m+g.a+":"+g.b,g.via.length?r:null,()=>coPlan(kk))}catch(e){P=null}}
    if(!P||!P.ok){consBlock=i===0?`${P&&P.why?P.why:"Немає вільної техніки"} — потрібно ${+maxT.toFixed(1)} т і ${+maxV.toFixed(1)} м³ в одному кузові`:`Ділянка ${i+1}: ${P&&P.why?P.why:"техніка недоступна"}`;return}
    if(i===0)LP.consVeh=P.vids[0];
    legs.push({a:g.a,b:g.b,m:g.m,r,own:true,P,time:P.tot-(i>0?HAND[g.m]*handK():0),cost:-P.profit,risk:lpRisk(r,g.m),via:g.via,veh:VT[P.t].n,tons:load[i],vol:vols[i]})});
  let t=0,c=0,risk=1,len=0;legs.forEach(L=>{t+=L.time;c+=L.cost;risk*=1-L.risk.p;len+=L.r.len;L.tEnd=t});
  const rows=O.map(o=>{let eta=null;for(let i=1;i<seq.length&&i<=legs.length;i++)if(evAt[i].some(e=>e.o===o&&e.kind==="drop"))eta=legs[i-1].tEnd;return{o,picked:picked.has(o.id),dropped:dropped.has(o.id),eta,late:eta!=null?Math.max(0,eta-o.dl):0}});
  const pay=rows.reduce((a,r)=>a+(r.dropped?r.o.pay*(r.late>0?Math.max(.35,1-r.late*.12):1):0),0);
  const done=!gr.tail&&!consBlock&&legs.length===gr.G.length&&rows.every(r=>r.dropped)&&LP.pts.length>1&&!lpIsW(LP.pts[LP.pts.length-1]);
  return{legs,t,c,risk:1-risk,len,tr:[],done,late:Math.max(0,...rows.map(r=>r.late)),net:pay-c,tail:gr.tail,drops:null,rows,evAt,consBlock,maxT,maxV}}
function consPlanHTML(C){const v=CO.veh.find(x=>x.id===LP.consVeh),T=v&&VT[v.t];
  return `<div class="blk" style="margin-top:10px"><span class="lbl">Замовлення збірного рейсу</span>${T?`<div class="note" style="margin-top:4px">${ic(T.ic)} ${esc(T.n)} · кузов ${T.cap} т / ${T.vol} м³ · найбільше завантаження ${+C.maxT.toFixed(1)} т / ${+C.maxV.toFixed(1)} м³</div>`:""}
   ${C.consBlock?`<div class="note bad" style="margin-top:6px">${ic("alert")} Вантаж не вміщується — маршрут не можна відправити</div>`:""}${C.rows.map(r=>`<div class="row sp" style="margin-top:5px;gap:8px"><span class="note" style="min-width:0">${C.consBlock?ic("pin"):r.dropped?`<span class="good">${ic("check")}</span>`:r.picked?ic("box"):ic("pin")} ${esc(PL[r.o.from].name)} → ${esc(PL[r.o.to].name)} · ${r.o.tons} т</span><span class="note">${C.consBlock?`<span class="bad">не вміщується</span>`:r.dropped?(r.late>0?`<span class="bad">запізнення ${daysS(r.late)}</span>`:`<span class="good">${daysS(r.eta)} · вчасно</span>`):r.picked?"у кузові":"ще не забрано"} · ≤ ${daysS(r.o.dl)}</span></div>`).join("")}</div>`}
/* the dispatcher's sequence: all pick-ups nearest first, then drops by deadline */
function consAutoSeq(k){const O=k.cons,seq=[O[0].from],left=new Set(O.map(o=>o.from));left.delete(O[0].from);let cur=PL[O[0].from];
  while(left.size){let best=null,bd=1e9;for(const pid of left){const d=Math.hypot(PL[pid].x-cur.x,PL[pid].z-cur.z);if(d<bd){bd=d;best=pid}}left.delete(best);seq.push(best);cur=PL[best]}
  for(const o of O.slice().sort((a,b)=>a.dl-b.dl))if(seq[seq.length-1]!==o.to)seq.push(o.to);return seq}
/* go: the legs run one after another with the pinned vehicle; orders are paid where they are dropped */
function consGoPlan(C){const k=LP.k,how=LP.byMgr?"mgr":"hand";
  const plan=C.legs.map((L,i)=>({a:L.a,b:L.b,m:L.m,r:L.via&&L.via.length?L.r:null,tons:Math.max(.1,L.tons),vol:L.vol,pay:0,drops:(C.evAt[i+1]||[]).filter(e=>e.kind==="drop").map(e=>({...e.o,dlA:G.day+e.o.dl,done:0,how}))}));
  plan.cons=true;plan.veh=LP.consVeh;const v=CO.veh.find(x=>x.id===plan.veh);if(v)v.resv=k.id;
  CO.board=CO.board.filter(x=>!k.cons.some(o=>o.id===x.id));UI.cons=[];
  lpClose();lpRunLeg(k,plan,0,G.day+k.dlDays);toast("good","Збірний рейс відправлено",`${k.cons.length} замовлення · ${plan.length} ${plan.length===1?"ділянка":"ділянки"} · ${LP_N[k.mode]}`);openWin("coTrips")}
/* the last leg: pay its drops, free the vehicle; an aborted trip frees it too */
{const _c=coComplete;coComplete=function(j){const pl=j.lp&&j.lp.plan;if(!pl||!pl.cons||j.ret)return _c(j);
  const last=j.lp.i===pl.length-1;if(j.back||j.cx0||j.lost){for(const v of CO.veh)if(v.resv===j.lp.k0.id)v.resv=null;for(const L of pl.slice(j.lp.i))for(const d of L.drops||[])consPay(j,d)}
  if(!last&&!j.back&&!j.cx0)return _c(j);
  const L=pl[j.lp.i];if(!L.paid){L.paid=1;for(const d of L.drops||[])consPay(j,d)}
  CO.jobs=CO.jobs.filter(x=>x!==j);for(const v of CO.veh)if(j.vids.includes(v.id)){v.st="idle";v.job=null;v.loc=j.back?j.k.from:L.b;v.idle0=hubAt(v.loc)?null:coNow();v.km+=(j.lead+j.len)*KM;v.resv=null}
  for(const v of CO.veh)if(v.resv===j.lp.k0.id)v.resv=null;if(CO_SEL===j){CO_SEL=null;$("#ucard").hidden=true}CO.winDirty=true}}
/* dispatch: one job, a list of stops along its path */
ACT.consGo=()=>{const C=consPlan();if(!C||C.why||C.ks.length<2)return;const T=C.T,v=C.v,sp=T.spd*spdK();
  const pts=Array.from(C.leadR.p);for(const r of C.legs)for(let i=2;i<r.p.length;i++)pts.push(r.p[i]);
  const first=C.S[0],last=C.S[C.S.length-1],hs=HAND.road*handK();
  const k={id:CO.uid++,from:first.pid,to:last.pid,cg:C.ks[0].cg,tons:C.tons,pay:C.pay,dlDays:Math.max(...C.ks.map(k=>k.dlDays)),mode:"road",risk:C.ks.reduce((a,k)=>a+k.risk,0)/C.ks.length,minR:0,len:C.len,how:"hand"};
  const j={id:k.id,k,mode:"road",t:v.t,n:1,vids:[v.id],p:new Float32Array(pts),lead:C.leadR.len,len:C.len,tl:C.leadR.len/sp,tm:C.len/sp,hs:hs*handF(first.pid),cust:0,t0:coNow(),dl:G.day+k.dlDays,dmg:0,lost:false,hold:0,ev:[],
    cons:{stops:C.S.map((s,i)=>({i,pid:s.pid,kind:s.kind,id:s.k.id,s:s.s,done:i===0?1:0})),orders:C.ks.map(o=>({...o,dlA:G.day+o.dlDays,done:0,how:"hand"})),n:C.ks.length}};
  j.tot=j.tl+j.hs+j.tm+hs*handF(last.pid);
  if(G.board){const tot=j.lead+j.len,wl=(()=>{let L=0;for(let i=2;i<j.p.length;i+=2)L+=Math.hypot(j.p[i]-j.p[i-2],j.p[i+1]-j.p[i-1]);return L})(),eco=wl>0?tot/wl:CO_DU;
    j.stops=bCrossings(j.p,eco).map(c=>({s:c.s,a:c.a,b:c.b,x:c.x,z:c.z,w:cpWait(c.b,"road")}));if(j.stops.length){j.tot+=j.stops.reduce((a,q)=>a+q.w,0)}}
  CO.cash-=C.fuel;CO.m.fuel+=C.fuel;v.st="trip";v.job=j.id;v.idle0=null;CO.jobs.push(j);CO.board=CO.board.filter(x=>!UI.cons.includes(x.id));
  j.ev.push(`Збірний рейс: ${C.ks.length} замовлення, ${C.S.length} зупинок`);
  toast("good","Збірний рейс відправлено",`${T.n}: ${C.S.map(s=>PL[s.pid].name).filter((n,i,a)=>a[i-1]!==n).join(" → ")}`);
  UI.cons=[];UI.consSt=[];UI.consV=null;updateHUD();renderWin();REDRAW=true};
/* an order is paid at its own drop, against its own deadline */
function consPay(j,o){if(o.done)return;o.done=1;const cg=CARGO_I[o.cg],late=Math.max(0,coNow()-o.dlA);
  if(j.lost||j.back){CO.rating=clamp(CO.rating-.08,1,5);coNews("bad","truck",`${CO.name}: «${cg.n.toLowerCase()}» до ${PL[o.to].name} не доставлено`);return}
  const pay=Math.round(o.pay*(j.payK||1)*(late>0?Math.max(.35,1-late*.12):1)*(1-Math.min(.8,j.dmg||0)));CO.cash+=pay;CO.m[revKey(o)]+=pay;CO.cdel++;CO.deliv++;CO.tons+=o.tons;
  const s=late>2?2:late>0?3.2:j.dmg>.05?3.8:5,w=Math.min(.05,.01+Math.log10(1+pay)*.005);CO.rating=clamp(CO.rating+(s-CO.rating)*w,1,5);
  const xp=Math.round(coXP(j,o,late)*1.25);CO.xp=(CO.xp||0)+xp; /* planning a shared trip teaches more */
  const tone=late>0?"warn":"good";coNews(tone,"truck",`${CO.name}: ${cg.n.toLowerCase()} доставлено в ${PL[o.to].name} — ${fmtUSD(pay,true)}${late>0?`, запізнення ${late.toFixed(1)} дн.`:" вчасно"}, +${xp} досвіду (збірний рейс)`);
  CO.last.unshift({d:{...G.date},from:o.from,to:o.to,cg:o.cg,pay,tone,mode:"road"});if(CO.last.length>30)CO.last.pop();j.ev.push(`Доставлено в ${PL[o.to].name}: ${fmtUSD(pay)}`)}
/* stops along the way: a short stop to load or unload, the drop is paid on the spot */
{const _f=coFrame;coFrame=function(){_f();for(const j of CO.jobs){if(!j.cons||j.hold>0)continue;const st=coJobState(j,coNow()-j.t0),S=j.cons.stops,L=S.length-1;
    for(const s of S){if(s.done||s.i===L||st.s<s.s-1e-6)continue;s.done=1;const same=S[s.i-1]&&S[s.i-1].pid===s.pid;
      if(s.kind==="drop"){const o=j.cons.orders.find(x=>x.id===s.id);if(o)consPay(j,o)}
      if(!same)coPause(j,HAND.road*handK()*.6*handF(s.pid),`${s.kind==="pick"?"Завантаження":"Розвантаження"} · ${PL[s.pid].name}`,"stop");else if(s.kind==="pick")j.ev.push(`Завантажено в ${PL[s.pid].name}`)}}}}
/* the end of the trip: the last drops, the truck stays where it unloaded */
{const _c=coComplete;coComplete=function(j){if(!j.cons||j.ret)return _c(j);
  for(const o of j.cons.orders)consPay(j,o);CO.jobs=CO.jobs.filter(x=>x!==j);const at=j.back?j.k.from:j.k.to;
  for(const v of CO.veh)if(j.vids.includes(v.id)){v.st="idle";v.job=null;v.loc=at;v.idle0=hubAt(at)?null:coNow();v.km+=(j.lead+j.len)*KM;v.cond=Math.max(0,v.cond-(j.lead+j.len)*1.6*[1.4,1,.65][CO.maint])}
  if(CO_SEL===j){CO_SEL=null;$("#ucard").hidden=true}CO.winDirty=true}}
/* the trip card lists the stops */
{const _cc=coCard;coCard=function(){_cc();const j=CO_SEL;if(!j||!j.cons)return;const b=$("#ucard .uc-body");if(!b||b.querySelector(".consst"))return;
  b.insertAdjacentHTML("afterbegin",`<div class="consst" style="margin-bottom:8px"><span class="lbl">Збірний рейс · ${j.cons.n} замовлення</span>${j.cons.stops.map(s=>`<div class="note" style="margin-top:2px">${s.done?`<span class="good">${ic("check")}</span>`:ic("pin")} ${s.i+1}. ${s.kind==="pick"?"Забрати":"Доставити"} · ${esc(PL[s.pid].name)}</div>`).join("")}</div>`)}}
/* the planned trip on the map while it is being put together */
{const _dc=drawCompany;drawCompany=function(g,dpr){_dc(g,dpr);if(true)return;const C=consPlan();if(!C||!C.leadR)return;
  const P=(x,y,z)=>{const q=project(x,y,z);return q?[q.x*dpr,q.y*dpr]:null},path=r=>{const o=[];for(let i=0;i<r.p.length;i+=2)o.push([r.p[i],0,r.p[i+1]]);return o};
  g.save();g.globalAlpha=.55;wroute(g,P,path(C.leadR),"200,210,220",dpr);g.restore();for(const r of C.legs||[])wroute(g,P,path(r),"92,200,242",dpr);
  C.S.forEach((s,i)=>{if(s.pid==null)return;const p=PL[s.pid],q=P(p.x,0,p.z);if(!q)return;const off=C.S.slice(0,i).filter(x=>x.pid===s.pid).length*16*dpr;
    g.fillStyle=s.kind==="pick"?"rgb(92,200,242)":"rgb(255,214,90)";g.strokeStyle="#06121b";g.lineWidth=1.6*dpr;g.beginPath();g.arc(q[0]+off,q[1]-14*dpr,8*dpr,0,7);g.fill();g.stroke();
    g.fillStyle="#06121b";g.font=`700 ${10*dpr}px "JetBrains Mono",monospace`;g.textAlign="center";g.textBaseline="middle";g.fillText(String(i+1),q[0]+off,q[1]-14*dpr+.5*dpr);g.textBaseline="alphabetic"});REDRAW=true}}

/* ---------- cancel an accepted trip: the fine grows with how long the order has been with you ---------- */
function coCancelInfo(j){const pl=j.lp&&j.lp.plan,k0=j.lp?j.lp.k0:j.k;
  const pay=pl&&pl.cons?pl.slice(j.lp.i).reduce((a,L)=>a+(L.drops||[]).filter(d=>!d.done).reduce((x,d)=>x+d.pay,0),0):k0.pay;
  const held=Math.max(0,coNow()-(j.lp&&j.lp.t00!=null?j.lp.t00:j.t0)),f=clamp(held/Math.max(.5,k0.dlDays||1),0,1);
  return{pay,held,fine:Math.round(pay*(.1+.6*f)+150*priceK(G.me)),rat:+(.05+.15*f).toFixed(2)}}
ACT.coCancel=id=>{const j=CO.jobs.find(x=>x.id===+id);if(!j||j.ret)return;const c=coCancelInfo(j);
  queueModal({icon:"alert",tone:"warn",eyebrow:"Скасування рейсу",title:`Скасувати рейс №${j.id}?`,body:`<p>Замовлення у вас уже ${daysS(c.held)}. Замовник виставить штраф <b>${fmtUSD(c.fine)}</b>, рейтинг знизиться на <b>${c.rat.toFixed(2)}</b>. Що довше вантаж у вас, то дорожче скасування.</p><p class="note">Техніка розвернеться й поїде до найближчого хабу.</p>`,
    choices:[{t:"Скасувати рейс",d:`Штраф ${fmtUSD(c.fine)} · рейтинг −${c.rat.toFixed(2)}`,f(){coCancelDo(j)}},{t:"Продовжити рейс",d:"Нічого не змінювати",hl:1,f(){}}]})};
function coCancelDo(j){if(!CO.jobs.includes(j))return;const c=coCancelInfo(j);CO.cash-=c.fine;CO.m.claims+=c.fine;CO.rating=clamp(CO.rating-c.rat,1,5);
  const st=coJobState(j,coNow()-j.t0),q=coPosAt(j,st.s),m=j.mode,T=VT[j.t];CO.jobs=CO.jobs.filter(x=>x!==j);
  for(const v of CO.veh)if(v.resv&&j.lp&&v.resv===j.lp.k0.id)v.resv=null;
  if(CO_SEL===j){CO_SEL=null;$("#ucard").hidden=true}
  const k0=j.lp?j.lp.k0:j.k;coNews("bad","alert",`${CO.name} скасувала рейс ${PL[k0.from].name} → ${PL[k0.to].name}: штраф ${fmtUSD(c.fine)}`);toast("warn","Рейс скасовано",`Штраф ${fmtUSD(c.fine)} · рейтинг −${c.rat.toFixed(2)}`);
  const vs=CO.veh.filter(v=>j.vids.includes(v.id));if(!vs.length){CO.winDirty=true;return}
  // home: the nearest hub that takes this kind of transport, from the exact point where the vehicle is
  let best=null,bd=1e9;for(const h of CO.hubs){const p=PL[h.pid];if(!modeOK(m,p))continue;const d=Math.hypot(p.x-q[0],p.z-q[1]);if(d<bd){bd=d;best=p}}
  let path=null;if(best&&typeof srSeg==="function"){try{path=srSeg(m,{x:q[0],z:q[1],...(m==="road"||m==="rail"?{v:nodeAt(q[0],q[1]),start:1}:{})},{x:best.x,z:best.z,...(m==="road"||m==="rail"?{v:best.node}:{})},false)}catch(e){path=null}}
  if(!best||!path||path.length<4){for(const v of vs){v.st="idle";v.job=null;v.loc=best?best.id:CO.hq;v.idle0=null}CO.winDirty=true;return}
  let L=0;for(let i=2;i<path.length;i+=2)L+=Math.hypot(path[i]-path[i-2],path[i+1]-path[i-1]);const len=L*CO_DU,tm=len/(T.spd*spdK());
  const r={id:CO.uid++,ret:true,k:{id:0,from:best.id,to:best.id,cg:"parcel",tons:0,pay:0,dlDays:1e3,mode:m,risk:0},mode:m,t:j.t,n:vs.length,vids:vs.map(v=>v.id),p:new Float32Array(path),lead:0,len,tl:0,tm,hs:0,cust:0,tot:tm,t0:coNow(),dl:G.day+1e3,dmg:0,lost:false,hold:0,ev:["Рейс скасовано: повернення в хаб"]};
  for(const v of vs){v.st="trip";v.job=r.id;v.idle0=null}CO.jobs.push(r);CO.winDirty=true}
/* a chain keeps the moment the order was accepted */
{const _r=lpRunLeg;lpRunLeg=function(k,plan,i,dl){if(i===0&&plan.t00==null)plan.t00=coNow();_r(k,plan,i,dl);const j=CO.jobs.find(x=>x.lp&&x.lp.plan===plan);if(j)j.lp.t00=plan.t00}}
{const _cc=coCard;coCard=function(){_cc();const j=CO_SEL;if(!j||j.ret)return;const b=$("#ucard .uc-body");if(!b||b.querySelector("[data-act=coCancel]"))return;
  b.insertAdjacentHTML("beforeend",`<button class="btn sm" style="margin-top:-6px;width:100%;flex-shrink:0" data-act="coCancel" data-arg="${j.id}">${ic("close")}Скасувати рейс · штраф ${fmtUSD(coCancelInfo(j).fine)}</button>`)}}
