/* =====================================================================
   Route planner (base game): manual multimodal routing for an order (or a mail run).
   Click cities on the map to add waypoints; every leg has its own transport (truck, train, ship,
   plane). A live calculator shows ETA, fuel & fees, net profit and risk; the system's auto-route
   is shown as a dim dashed line to beat. Legs run one after another: own vehicles where they are
   free, otherwise a partner carrier for a fee.
   ===================================================================== */
const LP={on:false,k:null,post:false,pts:[],modes:[],mode:"road",hover:null,prevSpeed:0};
const LP_C={road:"52,199,89",rail:"236,150,92",sea:"110,190,255",air:"214,150,255"},LP_T={road:"truck",rail:"train",sea:"ship",air:"plane"},LP_N={road:"Авто",rail:"Потяг",sea:"Корабель",air:"Літак"};
const lpOn=()=>G.co&&G.board;
/* a point of the plan is a city id (number) or a road waypoint {v:node,x,z,cp} */
const lpIsW=q=>typeof q==="object";
const lpXZ=q=>lpIsW(q)?q:PL[q];
const lpNode=q=>lpIsW(q)?q.v:PL[q].node;
const lpName=q=>{if(!lpIsW(q))return PL[q].name;const c=bOwn(q.x,q.z);return q.cp?"КПП"+(q.cn?" "+q.cn:""):"дорога"+(c>=0?" ("+G.C[c].name+")":"")};
let LP_OVR=null;{const _r=coRoute;coRoute=function(m,a,b){if(LP_OVR&&LP_OVR.key===m+a+":"+b)return LP_OVR.r;return _r(m,a,b)}}
const lpWith=(key,r,f)=>{const s=LP_OVR;LP_OVR=r?{key,r}:null;try{return f()}finally{LP_OVR=s}};
/* path between two plan points of one mode */
/* the planner suggests the ordinary route: it does not steer around weather — that is the dispatcher's job */
const LP_RC={blk:null,v:-1,m:new Map()};
function lpPlain(m,a,b){if((m!=="road"&&m!=="rail")||!G.board||a===b)return coRoute(m,a,b);if(m==="rail"&&!(PL[a].rail&&PL[b].rail))return null;
  if(LP_RC.blk!==BLK||LP_RC.v!==BLK_V){LP_RC.blk=BLK;LP_RC.v=BLK_V;LP_RC.m.clear()}const key=m+a+":"+b;if(LP_RC.m.has(key))return LP_RC.m.get(key);
  let p;BLK_NOWX=true;try{p=boardPath(PL[a].node,PL[b].node,m==="rail"?BOARD.rbits:undefined)}finally{BLK_NOWX=false}
  let res=null;if(p&&p.length>=4){let len=0;for(let i=2;i<p.length;i+=2)len+=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]);res={p,len:len*CO_DU}}LP_RC.m.set(key,res);return res}
function lpSeg(m,a,b){if(!lpIsW(a)&&!lpIsW(b))return lpPlain(m,a,b);if(m!=="road"&&m!=="rail")return null;
  let p;BLK_NOWX=true;try{p=boardPath(lpNode(a),lpNode(b),m==="rail"?BOARD.rbits:undefined)}finally{BLK_NOWX=false}if(!p)return null;let len=0;for(let i=2;i<p.length;i+=2)len+=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]);return{p,len:len*CO_DU}}
function lpJoin(rs){const f=[];let len=0;rs.forEach((r,i)=>{for(let j=i?2:0;j<r.p.length;j++)f.push(r.p[j]);len+=r.len});return{p:new Float32Array(f),len}}
/* road node under the cursor (roads, rail lines, border checkpoints) */
function lpPickW(x,y,m){if(m!=="road"&&m!=="rail")return null;const g=pickPlane(x,y),g2=pickPlane(x+16,y);if(!g||!g2)return null;
  const R=Math.max(BL.st*.8,Math.hypot(g2[0]-g[0],g2[1]-g[1])),bits=m==="rail"?BOARD.rbits:BOARD.bits;
  let cp=null,cd=R*1.2;for(const c of BOARD.cps||[]){if(!!c.rail!==(m==="rail"))continue;const d=Math.hypot(c.x-g[0],c.z-g[1]);if(d<cd){cd=d;cp=c}}
  const cx=cp?cp.x:g[0],cz=cp?cp.z:g[1],i0=Math.round((cx+WX/2)/BL.st),j0=Math.round((cz+WZ/2)/BL.st),n=Math.ceil(R/BL.st)+1;let best=null,bd=1e9;
  for(let j=j0-n;j<=j0+n;j++)for(let i=i0-n;i<=i0+n;i++){if(i<0||j<0||i>=BL.nx||j>=BL.nz)continue;const v=bNode(i,j);if(!bits[v])continue;const [px,pz]=bXY(v),d=Math.hypot(px-cx,pz-cz);if(d<bd&&d<R*1.3){bd=d;best=v}}
  if(best==null)return null;const [px,pz]=bXY(best);const o={v:best,x:px,z:pz};if(cp){o.cp=1;const A=G.C[cp.a],B=G.C[cp.b];if(A&&B)o.cn=A.name+" – "+B.name}return o}
function lpCityAt(x,y,R){const lab=typeof coPlaceAt==="function"?coPlaceAt(x,y):null;if(lab!=null)return lab;let best=null,bd=R;for(const p of PL){const q=project(p.x,0,p.z);if(!q)continue;const d=Math.hypot(q.x-x,q.y-y);if(d<bd){bd=d;best=p.id}}return best}
const lpModeOK=(m,p)=>m==="road"?true:m==="rail"?p.rail:m==="sea"?p.port!=null:m==="air"?!!p.air:false;
const lpUnlocked=m=>Object.values(VT).some(T=>T.mode===m&&T.tier<=CO.tier);
/* partner carrier's price: market rate for a hand-made multi-drop leg, a share of the order otherwise */
function lpFee(k,r,m,tons,cid){if(k.multi)return Math.round((({road:600,rail:5000,sea:20000,air:15000})[m]*.25+({road:150,rail:22,sea:9,air:260})[m]*r.len*Math.pow(tons,.85))*CARGO_I[k.cg].k*priceK(cid)*.5);
  return Math.round(k.pay*.55*Math.min(1.4,r.len/Math.max(.05,k.len||r.len))+({road:150,rail:900,sea:4000,air:3000})[m]*priceK(cid))}
/* ---------- one leg: own vehicle if a plan exists, else a partner carrier ---------- */
function lpLeg(a,b,m,i,rr,via){const k=LP.k,r=rr||lpPlain(m,a,b);if(!r)return null;via=via||[];const A=PL[a],B=PL[b];
  if(LP.post){const T=PVT[{road:"ptruck",rail:"ptruck",sea:"pship",air:"pplane"}[m]]||PVT.ptruck,sp=T.spd*spdK(),tm=r.len/sp;
    return{a,b,m,r,via,own:!!CO.post&&CO.post.veh.some(v=>PVT[v.t].mode===m),time:tm+HAND[m]*handK()*.6,cost:r.len*T.fuel*CO.fuel*fuelK(m),risk:lpRisk(r,m)}}
  const kk={...k,multi:null,legs:null,from:a,to:b,mode:m,minR:0,tons:LP.tn||k.tons,...(i===0?{_veh:LP.veh0??undefined,_ctry:PL[LP.pts[0]]?PL[LP.pts[0]].cid:undefined}:{})};let P=null;if(lpUnlocked(m)){try{P=lpWith(m+a+":"+b,via.length?r:null,()=>coPlan(kk))}catch(e){P=null}}
  const share=r.len/Math.max(.05,k.len||r.len);
  if(P&&P.ok)return{a,b,m,r,own:true,P,time:P.tot-(i>0?HAND[m]*handK():0),cost:k.pay-P.profit,run:k.pay-P.profit-P.fuel,risk:lpRisk(r,m),via,veh:VT[P.t].n+(P.n>1?" ×"+P.n:"")};
  const T=Object.values(VT).find(t=>t.mode===m&&t.tier<=7&&!t.loc)||VT.truck,tm=r.len/(T.spd*spdK()),fee=lpFee(k,r,m,LP.tn||k.tons,A.cid);
  return{a,b,m,r,via,own:false,why:P&&P.why,time:tm+HAND[m]*handK()*2,cost:fee,risk:lpRisk(r,m),veh:"партнер · "+T.n.toLowerCase()}}
/* ---------- what can go wrong along a path ---------- */
function lpRisk(r,m){const p=r.p,o={jam:0,wx:0,band:0,pir:0,border:0,cl:0};const seen=new Set();
  for(let i=2;i<p.length;i+=2){const L=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]),n=Math.max(1,Math.ceil(L/(CST*.5)));for(let s=0;s<=n;s++){const x=p[i-2]+(p[i]-p[i-2])*s/n,z=p[i-1]+(p[i+1]-p[i-1])*s/n;
    for(const w of CO.wx||[]){const K=WXK[w.k];if(K[m]&&Math.hypot(x-w.x,z-w.z)<w.r&&!seen.has("w"+w.id)){seen.add("w"+w.id);o.wx++}}
    if(m==="road"||m==="rail")for(const z_ of CO.band||[])if(Math.hypot(x-z_.x,z-z_.z)<z_.r&&!seen.has("b"+z_.id)){seen.add("b"+z_.id);o.band++}
    if(m==="sea")for(const z_ of CO.pir||[])if(Math.hypot(x-z_.x,z-z_.z)<z_.r&&!seen.has("p"+(z_.id||z_.x))){seen.add("p"+(z_.id||z_.x));o.pir++}}}
  if(m==="road"&&JAM.length)for(let i=2;i<p.length;i+=2){const J=jamOn(p[i-2],p[i-1],p[i],p[i+1]);if(J&&!seen.has("j"+J.id)){seen.add("j"+J.id);o.jam++}}
  if(m==="road"||m==="rail"){const cr=bCrossings(p,CO_DU);o.border=cr.length;for(const c of cr)if(incCrossCl(c.a,c.b,c.x,c.z))o.cl++}
  const pr=1-Math.pow(.9,o.wx)*Math.pow(.88,o.band)*Math.pow(.8,o.pir); /* damage: bad weather, bandits, pirates */return{...o,p:pr}}
/* ---------- the whole plan ---------- */
function lpGroups(){const G_=[];let a=LP.pts[0],via=[],rs=[],m=null;for(let i=1;i<LP.pts.length;i++){const q=LP.pts[i];m=LP.modes[i-1];const r=lpSeg(m,LP.pts[i-1],q);if(!r)return{G:G_,bad:i};rs.push(r);
    if(lpIsW(q))via.push(q);else{G_.push({a,b:q,m,via,r:via.length?lpJoin(rs):r});a=q;via=[];rs=[]}}
  return{G:G_,tail:via.length?{via,m,r:lpJoin(rs)}:null}}
function lpBlock(C){const k=LP.k;if(!k||LP.post)return null;if(C.consBlock)return C.consBlock;if(LP.veh0!=null&&C.legs[0]&&!C.legs[0].own){const v=CO.veh.find(x=>x.id===LP.veh0);return `${v?VT[v.t].n:"Обрана техніка"} не підходить${C.legs[0].why?": "+C.legs[0].why.toLowerCase():""}`}if(k.minR&&CO.rating<k.minR)return `Замовник хоче рейтинг ${k.minR.toFixed(1)}+ (у вас ${CO.rating.toFixed(2)})`;
  const cg=CARGO_I[k.cg];for(const L of C.legs){if(!lpUnlocked(L.m)){const t=Math.min(...Object.values(VT).filter(T=>T.mode===L.m).map(T=>T.tier));return `${LP_N[L.m]}: потрібна ліцензія «${LIC[t].n}»`}
    const nd=permNeed(cg,L.m).filter(id=>!permOK(id));if(nd.length)return `Потрібна ліцензія «${PERM_I[nd[0]].n}»`;
    /* without the international licence a route may not leave your country, not even in transit */
    if(CO.tier<3&&(L.m==="road"||L.m==="rail")){const home=hqP().cid,out=[L.a,L.b].map(i=>PL[i]).find(p=>p&&p.cid!==home);
      if(out||L.r&&L.r.p&&bCrossings(L.r.p,CO_DU).length)return `Маршрут виходить за межі країни${out?" ("+(G.C[out.cid].name||"")+")":""}: потрібна ліцензія «${LIC[3].n}». Прокладіть маршрут дорогами своєї країни`}
    if(CO.tier<5&&[L.a,L.b].some(i=>PL[i]&&!coScope(PL[i])))return `Пункт маршруту поза зоною вашої ліцензії: потрібна ліцензія «${LIC[5].n}»`}return null}
function lpCalc(){if(LP.k&&LP.k.cons&&!LP.post)return lpCalcCons();const legs=[],gr=lpGroups(),M=LP.k&&LP.k.multi,got=new Set();gr.G.forEach((g,i)=>{if(M)LP.tn=Math.max(.1,+M.filter(d=>!got.has(d.to)).reduce((a,d)=>a+d.tons,0).toFixed(1));const L=lpLeg(g.a,g.b,g.m,i,g.r,g.via);if(L)legs.push(L);if(M&&M.some(d=>d.to===g.b))got.add(g.b)});LP.tn=null;
  let t=0,c=0,risk=1,len=0;const tr=[],ht=[];legs.forEach((L,i)=>{t+=L.time;c+=L.cost;risk*=1-L.risk.p;len+=L.r.len;if(i&&legs[i-1].m!==L.m){const f=Math.round((250+(LP.k?LP.k.tons:20)*1.5)*priceK(PL[L.a].cid));c+=f;t+=HAND[L.m]*handK()*.5;tr.push(f);
    /* transshipment at a hub that is not yours: the owner charges a tax */
    if(!LP.post){const x=hubTax(LP.k,L.a,L.m);if(x){c+=x;ht.push({pid:L.a,f:x})}}}L.tEnd=t});
  let done=!gr.tail&&LP.pts.length>1&&LP.pts[LP.pts.length-1]===(LP.post?LP.dest:LP.k.to);
  let drops=null,late=LP.k&&!M?Math.max(0,t-LP.k.dlDays):0,pay=LP.k?LP.k.pay*(late>0?Math.max(.35,1-late*.12):1):0;
  if(M){drops=[];let off=0,lastNew=-1;const g2=new Set(),ul=HAND.air*handK()*.5;legs.forEach((L,i)=>{const d=M.find(x=>x.to===L.b);if(d&&!g2.has(d.to)){g2.add(d.to);const eta=L.tEnd+off;drops.push({d,eta,late:Math.max(0,eta-d.dl)});off+=ul;lastNew=i}});t+=off;
    done=!gr.tail&&g2.size===M.length&&lastNew===legs.length-1;late=drops.reduce((a,x)=>Math.max(a,x.late),0);pay=drops.reduce((a,x)=>a+x.d.pay*(x.late>0?Math.max(.35,1-x.late*.12):1),0)}
  return{legs,t,c,risk:1-risk,len,tr,ht,done,late,net:pay-c,tail:gr.tail,drops}}
function lpAuto(){if(LP.post||LP.k.multi)return null;if(LP.k.cons)return{P:null,r:null};const k=LP.k;let P=null;try{P=coPlan(k)}catch(e){}const r=coRoute(k.mode,k.from,k.to);return{P,r}}

/* ---------- open / close ---------- */
ACT.lpPlan=id=>{const k=CO.board.find(x=>x.id===+id);if(!k)return;if(!k.multi){const P=coPlan(k);if(!P.ok)return toast("warn","Маршрут не прокласти",P.why)}lpOpen(k,false)};
{const _ss=setSpeed;setSpeed=function(i){if(i&&(LP.on||typeof SR!=="undefined"&&SR.on)){toast("warn","Час на паузі","Поки прокладаєш маршрут, час стоїть: відправ рейс за маршрутом або закрий планувальник");updateHUD();return}return _ss(i)}}
function lpOpen(k,post,from,dest){CO_PREV=null;LP.veh0=null;LP.on=true;LP.byMgr=false;LP.k=k;LP.post=post;LP.dest=dest;LP.pts=[post?from:k.from];LP.modes=[];LP.mode=post?"road":k.mode;LP.prevSpeed=G.speed;setSpeed(0);closeWin();document.body.classList.add("lplan");
  const A=PL[LP.pts[0]],B=PL[post?dest:k.to];Cam.ttx=(A.x+B.x)/2;Cam.ttz=(A.z+B.z)/2+.3;Cam.tdist=clamp(Math.hypot(A.x-B.x,A.z-B.z)*1.6+3,3,WX*1.1);lpPanel();REDRAW=true}
function lpClose(){LP.on=false;lpTagsOff();CO_PREV=null;{const c=document.getElementById("vcv");if(c)c.getContext("2d").clearRect(0,0,c.width,c.height)}document.body.classList.remove("lplan");const el=$("#lpPanel");if(el)el.remove();if(LP.prevSpeed)setSpeed(LP.prevSpeed);REDRAW=true}
ACT.lpCancel=()=>{const post=LP.post;lpClose();openWin(post?"poShip":"coJobs")};
ACT.lpMode=m=>{LP.mode=m;lpPanel()};
ACT.lpUndo=()=>{if(LP.pts.length>1){LP.pts.pop();LP.modes.pop();lpPanel();REDRAW=true}};
ACT.lpAutoUse=()=>{if(LP.post||!CO.mgr.cto)return;const k=LP.k;if(k.cons){LP.pts=consAutoSeq(k);LP.modes=LP.pts.slice(1).map(()=>k.mode);LP.byMgr=true;lpPanel();REDRAW=true;return}if(k.legs){LP.pts=[k.legs[0].a,...k.legs.map(L=>L.b)];LP.modes=k.legs.map(L=>L.m)}else{LP.pts=[k.from,k.to];LP.modes=[k.mode]}LP.byMgr=true;lpPanel();REDRAW=true};
const lpLock=()=>{const l=LP.pts[LP.pts.length-1];return lpIsW(l)?LP.modes[LP.modes.length-1]:null};
const lpPtOK=(m,q)=>lpIsW(q)?(m==="road"||m==="rail"&&!!BOARD.rbits[q.v]):lpModeOK(m,PL[q]);
function lpAdd(pid){const last=LP.pts[LP.pts.length-1];if(!LP.post&&!lpUnlocked(lpLock()||LP.mode))return toast("warn","Немає ліцензії",`${LP_N[lpLock()||LP.mode]}: цей вид транспорту ще недоступний`);if(pid===last||lpIsW(pid)&&lpIsW(last)&&pid.v===last.v)return;const m=lpLock()||LP.mode;LP.mode=m;
  if(!lpPtOK(m,last)||!lpPtOK(m,pid)){const bad=!lpPtOK(m,last)?last:pid;return toast("warn",`${LP_N[m]}: немає ${m==="rail"?"станції":m==="sea"?"порту":"аеропорту"}`,lpName(bad))}
  const r=lpSeg(m,last,pid);if(!r)return toast("warn","Маршрут недоступний",`${LP_N[m]} не пройде між ${lpName(last)} і ${lpName(pid)}: море, закритий кордон або негода`);
  LP.pts.push(pid);LP.modes.push(m);LP.byMgr=false;lpPanel();REDRAW=true}

/* ---------- panel ---------- */
function lpBar(v,max,cls){return `<div class="meter" style="margin-top:4px"><i style="width:${clamp(v/max*100,2,100).toFixed(0)}%;background:var(--${cls})"></i></div>`}
/* which vehicle starts the route: idle in a hub, waiting after a delivery, or driving home — only in the order's country */
function lpVehList(){const k=LP.k;if(!k||LP.post||lpIsW(LP.pts[0]))return[];const m=k.cons?k.mode:(LP.modes[0]||LP.mode),cid=PL[LP.pts[0]].cid;
  return CO.veh.filter(v=>VT[v.t].mode===m&&!v.resv&&(v.st==="idle"&&(hubAt(v.loc)||v.idle0!=null&&coNow()-v.idle0<1)||isRetV(v))&&vCid(v)===cid)}
function lpVehHTML(){const L=lpVehList(),m=LP.k.cons?LP.k.mode:(LP.modes[0]||LP.mode);if(!L.length)return `<div class="note warn" style="margin-top:10px">${ic("alert")} У країні ${esc(G.C[PL[LP.pts[0]].cid]?G.C[PL[LP.pts[0]].cid].name:"")} немає вільної техніки: ${MODE_N[m].toLowerCase()}</div>`;
  const st=v=>v.st==="trip"?"повертається в хаб":hubAt(v.loc)?"у хабі":"чекає після доставки";
  return `<span class="lbl" style="display:block;margin-top:10px">Хто їде · ${esc(G.C[PL[LP.pts[0]].cid].name)}</span><div style="display:flex;flex-direction:column;gap:4px;margin-top:6px;max-height:150px;overflow:auto">
   <button class="btn sm ${LP.veh0==null?"pri":""}" data-act="lpVeh" data-arg="auto" style="justify-content:flex-start">${ic("cpu")}Найближча, що вміщує вантаж</button>
   ${L.slice(0,12).map(v=>{const T=VT[v.t],pl=PL[v.loc];return `<button class="btn sm ${LP.veh0===v.id?"pri":""}" data-act="lpVeh" data-arg="${v.id}" style="justify-content:flex-start">${ic(T.ic)}${esc(T.n)} · ${esc(pl.name)} · ${st(v)} · ${T.cap} т / ${T.vol} м³${v.cond<60?` · стан ${v.cond.toFixed(0)}%`:""}</button>`}).join("")}</div>`}
ACT.lpVeh=a=>{LP.veh0=a==="auto"?null:+a;lpPanel();REDRAW=true};
function lpPanel(){let el=$("#lpPanel");if(!LP.on){if(el)el.remove();return}if(!el){el=document.createElement("div");el.id="lpPanel";el.className="glass";document.body.appendChild(el)}
  const k=LP.k,C=lpCalc(),A=LP.post||!CO.mgr.cto?null:lpAuto(),lastQ=LP.pts[LP.pts.length-1],lock=lpLock(),dest=PL[LP.post?LP.dest:k.to];
  const riskC=C.risk>.35?"bad":C.risk>.15?"warn":"good",dl=LP.post||k.multi||k.cons?null:k.dlDays;
  const aT=A&&A.P&&A.P.ok?A.P.tot:null,aNet=A&&A.P&&A.P.ok?A.P.profit:null,aRisk=A&&A.r?lpRisk(A.r,k.mode).p:null;
  const cmp=(v,a,lowerBetter,fmt)=>a==null||!C.legs.length?"":`<span class="note ${(lowerBetter?v<a:v>a)?"good":"bad"}" style="margin-left:6px">диспетчер ${fmt(a)}</span>`;
  el.innerHTML=`<div class="row sp"><b style="font-size:15px">${ic("road")} Прокладання маршруту</b><button class="xbtn" data-act="lpCancel" aria-label="Закрити">${ic("close")}</button></div>
   <div class="note" style="margin-top:4px">${LP.post?`Поштовий рейс · ${esc(PL[LP.pts[0]].name)} → ${esc(dest.name)}`:(k.cons?`Збірний рейс · ${k.cons.length} замовлення · ${k.tons} т · ${k._vol} м³ · ${LP_N[k.mode].toLowerCase()} · оплата до ${fmtUSD(k.pay)}`:`${esc(CARGO_I[k.cg].n)}, ${k.tons} т · ${esc(PL[k.from].name)} → ${k.multi?`${k.multi.length} країни (збірний авіарейс)`:esc(dest.name)} · оплата ${fmtUSD(k.pay)}`)}</div>
   ${LP.post?"":lpVehHTML()}<span class="lbl" style="display:block;margin-top:10px">Транспорт наступної ділянки</span>
   <div class="seg" style="margin-top:6px">${["road","rail","sea","air"].map(m=>{const ok=(LP.post?m!=="rail":lpUnlocked(m))&&(!k||!k.cons||m===k.mode)&&(lock?m===lock:lpPtOK(m,lastQ));return `<button class="${LP.mode===m?"on":""}" data-act="lpMode" data-arg="${m}" ${ok?"":"disabled"} style="${ok?"":"opacity:.4"}">${ic(LP_T[m])} ${LP_N[m]}</button>`}).join("")}</div>
   <div class="note" style="margin-top:6px">${C.done?`<span class="good">${ic("check")} ${k&&k.cons?"Маршрут охоплює всі замовлення":k&&k.multi?"Усі пункти охоплено":"Маршрут доходить до "+esc(dest.name)}</span>`:`Клікніть місто, будь-яку ділянку дороги чи значок КПП — наступна точка. Ціль: <b>${k&&k.cons?"забрати й доставити всі замовлення — доставити можна лише те, що вже в кузові":k&&k.multi?"усі пункти збірного рейсу, останнім — пункт посадки":esc(dest.name)}</b>${lock?`<br>Ви на дорозі: ділянка закінчується в місті, транспорт — ${LP_N[lock].toLowerCase()}.`:""}`}</div>
   <div style="display:flex;flex-direction:column;gap:5px;margin-top:10px">${C.legs.map((L,i)=>`<div class="lrow" style="padding:6px 8px"><span style="color:rgb(${LP_C[L.m]})">${ic(LP_T[L.m])}</span><div style="min-width:0"><b>${esc(PL[L.a].name)} → ${esc(PL[L.b].name)}</b><div class="note">${L.via&&L.via.length?`через: ${L.via.map(v=>esc(lpName(v))).join(", ")} · `:""}${kmS(L.r.len)} · ${daysS(L.time)} · ${fmtUSD(L.cost)} · ${L.veh||(L.own?"власна техніка":"партнер")}${L.risk.jam?` · <span class="bad">перекриття ${L.risk.jam}</span>`:""}${L.risk.wx?` · негода`:""}${L.risk.band?` · бандити`:""}${L.risk.pir?` · пірати`:""}${L.risk.cl?` · <span class="bad">закритий кордон</span>`:""}</div></div></div>`).join("")||(C.tail?"":`<div class="note">Ще немає ділянок.</div>`)}${C.tail?`<div class="lrow" style="padding:6px 8px;opacity:.8"><span style="color:rgb(${LP_C[C.tail.m]})">${ic(LP_T[C.tail.m])}</span><div><b>${esc(lpName(LP.pts[LP.pts.length-1-C.tail.via.length]))} → …</b><div class="note">через: ${C.tail.via.map(v=>esc(lpName(v))).join(", ")} · ${kmS(C.tail.r.len)} · доведіть до міста</div></div></div>`:""}
    ${C.tr.length?`<div class="note">Перевантаження між видами транспорту: ${C.tr.length} · ${fmtUSD(C.tr.reduce((a,b)=>a+b,0))}</div>`:""}${C.ht&&C.ht.length?`<div class="note warn" data-tip="${T("Податок за чужий хаб","Перевантаження в місті, де у вас немає власного хаба: власник хаба бере податок — 4% від оплати замовлення плюс збір за вид транспорту. Відкрийте свій хаб у цьому місті, щоб не платити.")}">Податок за чужі хаби: ${C.ht.map(h=>esc(PL[h.pid].name)).join(", ")} · ${fmtUSD(C.ht.reduce((a,h)=>a+h.f,0))}</div>`:""}</div>
   ${k&&k.multi?lpDropsHTML(C):""}${k&&k.cons?consPlanHTML(C):""}<div class="blk" style="margin-top:10px">
    <div class="row sp"><span>Орієнтовне прибуття</span><b class="num ${dl!=null&&C.t>dl?"bad":""}">${C.legs.length?daysS(C.t):"—"}${cmp(C.t,aT,true,daysS)}</b></div>${dl!=null?lpBar(C.t,dl*1.3,C.t>dl?"bad":"good")+`<div class="note">дедлайн ${daysS(dl)}${C.legs.length?(C.t<=dl?` · запас ${daysS(dl-C.t)}`:` · <span class="bad">запізнення ${daysS(C.t-dl)}</span>`):""}</div>`:""}
    <div class="row sp" style="margin-top:8px"><span>Пальне, фрахт і збори</span><b class="num">${fmtUSD(C.c)}</b></div>
    ${LP.post?"":`<div class="row sp" style="margin-top:8px"><span>Чистий прибуток</span><b class="num ${C.net>=0?"good":"bad"}">${C.legs.length?fmtUSD(C.net,true):"—"}${cmp(C.net,aNet,false,v=>fmtUSD(v,true))}</b></div>`}
    <div class="row sp" style="margin-top:8px"><span>Ризик пошкодження</span><b class="num ${riskC}">${C.legs.length?Math.round(C.risk*100)+"%":"—"}${cmp(C.risk,aRisk,true,v=>Math.round(v*100)+"%")}</b></div>${lpBar(C.risk,.6,riskC)}</div>
   ${A?`<div class="note" style="margin-top:8px"><span style="display:inline-block;width:18px;border-top:2px dashed rgba(220,230,240,.55);vertical-align:middle;margin-right:6px"></span>Маршрут диспетчера-логіста: ${aT!=null?`${daysS(aT)} · ${fmtUSD(aNet,true)}`:esc(A.P?A.P.why:"недоступний")}</div>`:""}
   <div class="row wrap" style="gap:6px;margin-top:10px"><button class="btn sm" data-act="lpUndo" ${LP.pts.length>1?"":"disabled"}>${ic("refresh")}Прибрати ділянку</button>${A?`<button class="btn sm" data-act="lpAutoUse">${ic("cpu")}Маршрут від диспетчера</button>`:""}${k&&k.multi?`<button class="btn sm" data-act="lpOrder" data-arg="near">${ic("mapIc")}Спершу ближчі</button><button class="btn sm" data-act="lpOrder" data-arg="urg">${ic("alert")}Спершу термінові</button>`:""}</div>
   ${(()=>{const b=lpBlock(C);return b?`<div class="note bad" style="margin-top:10px">${ic("lock")} ${esc(b)}</div>`:""})()}<button class="btn pri" style="width:100%;margin-top:10px" data-act="lpGo" ${C.done&&!lpBlock(C)?"":"disabled"}>${ic("send")}${LP.post?"Запустити рейс":"Відправити за маршрутом"}</button>`}

/* ---------- dispatch: legs run one after another ---------- */
ACT.lpGo=()=>{const C=lpCalc();if(!C.done)return;{const b=lpBlock(C);if(b)return toast("warn","Відправити не можна",b)}if(LP.k.cons&&!LP.post)return consGoPlan(C);if(LP.post)return lpGoPost(C);const k=LP.k;k.how=LP.byMgr?"mgr":"hand";
  const plan=C.legs.map(L=>({a:L.a,b:L.b,m:L.m,r:L.via&&L.via.length?L.r:null}));{const P0=C.legs[0]&&C.legs[0].P;plan.veh0=LP.veh0??(P0&&P0.ok&&P0.n===1?P0.vids[0]:null);plan.ctry=PL[LP.pts[0]].cid}
  if(k.multi){const got=new Set();let rem=k.multi.reduce((a,d)=>a+d.tons,0);plan.forEach(L=>{L.tons=+Math.max(.1,rem).toFixed(1);L.pay=0;const d=k.multi.find(x=>x.to===L.b);if(d&&!got.has(d.to)){got.add(d.to);L.drop={...d,dlA:G.day+d.dl};rem-=d.tons}});const z=plan[plan.length-1];z.pay=z.drop.pay;z.dl=z.drop.dlA}CO.board=CO.board.filter(x=>x!==k);const dl=G.day+k.dlDays;
  hubTaxPay(C.ht);
  lpClose();lpRunLeg(k,plan,0,dl);toast("good","Рейс за вашим маршрутом",`${plan.length} ${plan.length===1?"ділянка":"ділянки"} · ${plan.map(p=>LP_N[p.m]).join(" → ")}`);openWin("coJobs")};
function lpRunLeg(k,plan,i,dl){const L=plan[i],kk={...k,multi:null,legs:null,cons:null,...(plan.cons?{_veh:plan.veh,_one:true,_vol:L.vol}:i===0&&plan.veh0!=null?{_veh:plan.veh0}:{}),from:L.a,to:L.b,mode:L.m,minR:0,id:k.id,tons:L.tons||k.tons,pay:L.pay!=null?L.pay:k.pay};let P=null;if(lpUnlocked(L.m)){try{P=lpWith(L.m+L.a+":"+L.b,L.r,()=>coPlan(kk))}catch(e){}}
  if(!P||!P.ok){const r=L.r||coRoute(L.m,L.a,L.b);if(!r){toast("bad","Ділянку не пройти",`${PL[L.a].name} → ${PL[L.b].name}`);return}const T=Object.values(VT).find(t=>t.mode===L.m&&!t.loc)||VT.truck,tm=r.len/(T.spd*spdK()),hs=HAND[L.m]*handK();
    const fee=lpFee(k,r,L.m,L.tons||k.tons,PL[L.a].cid);
    P={ok:true,t:Object.keys(VT).find(x=>VT[x]===T),n:1,vids:[],lead:0,leadR:{p:new Float32Array([r.p[0],r.p[1]]),len:0},main:r,tl:0,tm,hs,cust:0,tot:hs+tm+hs,fuel:fee,profit:0,late:false};CO.m.other+=0}
  if(i>0&&!plan.cons){const f=Math.round((250+k.tons*1.5)*priceK(PL[L.a].cid));CO.cash-=f;CO.m.other+=f}
  coDispatch(kk,P,true);const j=CO.jobs.find(x=>x.k===kk);if(!j)return;j.lp={plan,i,k0:k};j.dl=L.dl||dl;if(i>0)j.cont=false}
{const _c=coComplete;coComplete=function(j){if(j.lp&&j.lp.i<j.lp.plan.length-1&&!j.back&&!j.cx0){CO.jobs=CO.jobs.filter(x=>x!==j);const L=j.lp.plan[j.lp.i];if(L.drop&&!L.paid){L.paid=1;lpDropPay(j,L.drop)}if(L.drops&&!L.paid){L.paid=1;for(const d of L.drops)consPay(j,d)}
    for(const v of CO.veh)if(j.vids.includes(v.id)){v.st="idle";v.job=null;v.loc=L.b;v.idle0=hubAt(L.b)?null:coNow()}
    coNews("",LP_T[L.m],`Перевантаження в ${PL[L.b].name}: «${CARGO_I[j.k.cg].n.toLowerCase()}» їде далі (${LP_N[j.lp.plan[j.lp.i+1].m].toLowerCase()})`);
    const sel=CO_SEL===j,fol=!!CO.follow;if(sel){CO_SEL=null;$("#ucard").hidden=true}const d=j.dmg,lost=j.lost,ev=j.ev;lpRunLeg(j.lp.k0,j.lp.plan,j.lp.i+1,j.dl);const n=CO.jobs.find(x=>x.lp&&x.lp.k0===j.lp.k0);if(n){n.dmg=d;n.lost=lost;n.ev=ev.concat(n.ev);if(sel){CO_SEL=n;CO.follow=fol;coCard()}}return} /* the selection and the follow camera move on to the next leg */
  return _c(j)}}
/* mail run along a hand-made route */
function lpGoPost(C){const P=poInit();let t=G.day+(CO.lastFr||0);for(const L of C.legs){const sp={road:1.2,rail:1.2,sea:1.6,air:16}[L.m]*spdK();P.trips.push({id:P.uid++,mode:L.m==="rail"?"road":L.m,kind:"trunk",a:L.a,b:L.b,p:L.r.p,len:L.r.len,t0:t,tot:Math.max(.08,L.r.len/sp),manual:1});t+=L.r.len/sp+HAND[L.m]*handK()*.5}
  CO.cash-=C.c;CO.m.other+=C.c;P.m.cost+=C.c;lpClose();toast("good","Поштовий рейс запущено",`${C.legs.length} ${C.legs.length===1?"ділянка":"ділянки"} · ${daysS(C.t)}`);openWin("poShip")}
ACT.lpPost=a=>{const [f,t]=a.split(":").map(Number);if(!lpOn())return;lpOpen(null,true,f,t)};

/* ---------- map ---------- */
const LP_FLAG=new Map();function lpFlag(cid){const c=G.C[cid];if(!c||!c.flag)return null;let im=LP_FLAG.get(cid);if(!im){im=new Image();im.src=c.flag;LP_FLAG.set(cid,im)}return im.complete&&im.naturalWidth?im:null}
/* departure / arrival blocks: DOM, so they sit above every city chip; leader + ring on the canvas */
function lpTagBox(){let c=document.getElementById("lpTags");if(!c){c=document.createElement("div");c.id="lpTags";document.body.appendChild(c)}return c}
function lpTagsOff(){const c=document.getElementById("lpTags");if(c)c.remove()}
function lpTags(g,dpr,list){const box=lpTagBox(),seen=new Set(),placed=[];
  for(const t of list){const p=PL[t.pid],q=project(p.x,0,p.z);const key=t.tag+":"+t.pid;seen.add(key);let el=box.querySelector(`[data-k="${key}"]`);
    if(!el){el=document.createElement("div");el.className="lptag";el.dataset.k=key;box.appendChild(el)}
    const html=`<i>${esc(t.tag)} · ${esc(G.C[p.cid].name)}</i><b>${G.C[p.cid].flag?`<img src="${G.C[p.cid].flag}" alt="">`:""}${esc(p.name)}${t.extra?`<span>${esc(t.extra)}</span>`:""}</b>`;
    if(el.dataset.h!==html){el.dataset.h=html;el.innerHTML=html}el.style.setProperty("--c",t.col);
    if(!q){el.style.display="none";continue}el.style.display="";const w=el.offsetWidth,h=el.offsetHeight;let bx=q.x-w/2,by=q.y-h-20;
    for(let k=0;k<6&&placed.some(b=>bx<b[2]&&bx+w>b[0]&&by<b[3]&&by+h>b[1]);k++)by-=h+6;placed.push([bx,by,bx+w,by+h]);
    el.style.transform=`translate(${bx.toFixed(1)}px,${by.toFixed(1)}px)`;
    const x=q.x*dpr,y=q.y*dpr;g.save();g.strokeStyle=`rgba(${t.col},.9)`;g.lineWidth=1.6*dpr;g.beginPath();g.moveTo(x,(by+h)*dpr);g.lineTo(x,y-9*dpr);g.stroke();
    g.fillStyle=`rgba(${t.col},.22)`;g.beginPath();g.arc(x,y,9*dpr,0,7);g.fill();g.lineWidth=2.4*dpr;g.stroke();g.restore()}
  for(const el of [...box.children])if(!seen.has(el.dataset.k))el.remove()}
const LP_DEP="92,200,242",LP_ARR="255,214,90",LP_CRIT="240,98,95";
{const _cc=coClick;coClick=function(x,y){if(!LP.on)return _cc(x,y);const pid=lpCityAt(x,y,18);if(pid!=null){lpAdd(pid);return true}
  const w=lpPickW(x,y,lpLock()||LP.mode);if(w)lpAdd(w);else if(LP.mode!=="road"&&LP.mode!=="rail"&&!lpLock())toast("","Проміжні точки — лише для авто і потяга",`${LP_N[LP.mode]} їде від міста до міста`);return true}}
addEventListener("pointermove",e=>{if(LP.on){LP.hover={x:e.clientX,y:e.clientY};REDRAW=true}},{passive:true});
addEventListener("keydown",e=>{if(LP.on&&e.key==="Escape"){e.stopImmediatePropagation();ACT.lpCancel()}if(LP.on&&(e.ctrlKey||e.metaKey)&&e.code==="KeyZ"){e.preventDefault();ACT.lpUndo()}},true);
/* a city marked by expanding waves: blue — departure, yellow — arrival */
function lpWave(g,P,p,col,dpr){if(!p)return;const q=P(p.x,0,p.z);if(!q)return;const t=performance.now()/1100;
  for(let w=0;w<3;w++){const f=(t+w/3)%1;g.strokeStyle=`rgba(${col},${(.95*(1-f)).toFixed(3)})`;g.lineWidth=2.4*dpr*(1-f*.5);g.beginPath();g.arc(q[0],q[1],(6+f*26)*dpr,0,7);g.stroke()}
  g.fillStyle=`rgb(${col})`;g.strokeStyle="#06121b";g.lineWidth=1.6*dpr;g.beginPath();g.arc(q[0],q[1],4.5*dpr,0,7);g.fill();g.stroke()}
function lpDraw(g,dpr){if(!LP.on)return;const P=(x,y,z)=>{const q=project(x,y,z);return q?[q.x*dpr,q.y*dpr]:null};const path=(r,m)=>{const pts=[];if(m==="air"){const H=coArcH(r.len);for(let i=0;i<=40;i++){const t=i/40;pts.push([lerp(r.p[0],r.p[r.p.length-2],t),Math.sin(Math.PI*t)*H,lerp(r.p[1],r.p[r.p.length-1],t)])}}else for(let i=0;i<r.p.length;i+=2)pts.push([r.p[i],0,r.p[i+1]]);return pts};
  // the system's route, dim
  for(let i=1;i<LP.pts.length;i++){const r=lpSeg(LP.modes[i-1],LP.pts[i-1],LP.pts[i]);if(r){const pts=path(r,LP.modes[i-1]);g.strokeStyle="rgba(6,12,18,.7)";g.lineWidth=5*dpr;g.beginPath();pts.forEach((q,n)=>{const s=P(...q);if(s)n?g.lineTo(...s):g.moveTo(...s)});g.stroke();g.strokeStyle=`rgb(${LP_C[LP.modes[i-1]]})`;g.lineWidth=3*dpr;g.stroke()}}
  // preview to the city under the cursor
  if(LP.hover){const m=lpLock()||LP.mode,last=LP.pts[LP.pts.length-1];let t=lpCityAt(LP.hover.x,LP.hover.y,22);if(t==null){const k_=LP.hover.x+","+LP.hover.y+m+LP.pts.length;if(LP.hk!==k_){LP.hk=k_;LP.hw=lpPickW(LP.hover.x,LP.hover.y,m)}t=LP.hw}
    if(t!=null&&t!==last&&lpPtOK(m,t)&&lpPtOK(m,last)){const r=lpSeg(m,last,t);if(r){g.save();g.globalAlpha=.85;wroute(g,P,path(r,m),LP_C[m],dpr);g.restore()}
      if(lpIsW(t)){const q=P(t.x,0,t.z);if(q){g.fillStyle="#fff";g.strokeStyle=`rgb(${LP_C[m]})`;g.lineWidth=2.5*dpr;g.beginPath();g.arc(q[0],q[1],5*dpr,0,7);g.fill();g.stroke();
        g.font=`600 ${11*dpr}px Inter,system-ui,sans-serif`;g.textAlign="left";const s=lpName(t),w_=g.measureText(s).width;g.fillStyle="rgba(6,12,18,.82)";g.fillRect(q[0]+9*dpr,q[1]-9*dpr,w_+10*dpr,18*dpr);g.fillStyle="#fff";g.textBaseline="middle";g.fillText(s,q[0]+14*dpr,q[1]);g.textBaseline="alphabetic"}}}}
  LP.pts.forEach((pid,i)=>{const p=lpXZ(pid),q=P(p.x,0,p.z);if(!q)return;if(lpIsW(pid)){g.fillStyle="#fff";g.strokeStyle=`rgb(${LP_C[LP.modes[i-1]]})`;g.lineWidth=2.5*dpr;g.beginPath();g.arc(q[0],q[1],4*dpr,0,7);g.fill();g.stroke();return}if(i===0)return;g.fillStyle=`rgb(${LP_C[LP.modes[i-1]]})`;g.strokeStyle="#06121b";g.lineWidth=2*dpr;g.beginPath();g.arc(q[0],q[1],5.5*dpr,0,7);g.fill();g.stroke()});
  if(LP.k&&LP.k.cons){for(const o of LP.k.cons){lpWave(g,P,PL[o.from],LP_DEP,dpr);lpWave(g,P,PL[o.to],LP_ARR,dpr)}REDRAW=true;return}
  const M=LP.k&&LP.k.multi,dests=M?M.map(x=>({pid:x.to,tag:x.crit?"ПОСАДКА · КРИТИЧНО":"ПОСАДКА",col:x.crit?LP_CRIT:LP_ARR,extra:"≤ "+daysS(x.dl)})):[{pid:LP.post?LP.dest:LP.k.to,tag:"ПРИБУТТЯ",col:LP_ARR}];
  for(const d of dests)lpWave(g,P,PL[d.pid],d.col,dpr);
  lpWave(g,P,PL[lpIsW(LP.pts[0])?LP.k.from:LP.pts[0]],LP_DEP,dpr);
  REDRAW=true}
{const _dc=drawCompany;drawCompany=function(g,dpr){_dc(g,dpr);if(LP.on){const c=document.getElementById("vcv");if(c)guard("Маршрут",()=>lpDraw(c.getContext("2d"),dpr))}}}

/* the route planner is part of the base game: the second DLC card is gone */
setTimeout(()=>{const c=document.querySelectorAll(".dlcs .dlc")[1];if(c)c.remove()},0);
