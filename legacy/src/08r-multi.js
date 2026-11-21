/* =====================================================================
   Route planner, part 2.
   • Збірні авіарейси: one plane, drops in several countries, each with its own critical deadline.
     The player chooses the order of landings in the route planner.
   • Зміна курсу суден: a ship at sea can be re-routed by hand (or around danger automatically)
     when pirates or a storm lie on its course.
   ===================================================================== */
/* ---------- multi-drop air orders ---------- */
function lpMakeMulti(k){const A=PL[k.from];if(!A||!A.air)return null;
  const T=Object.values(VT).filter(t=>t.mode==="air"&&t.tier<=CO.tier&&!t.loc).sort((a,b)=>b.cap-a.cap)[0];if(!T)return null;
  const used=new Set([A.cid]),drops=[],B=PL[k.to];if(B.air&&!used.has(B.cid)){drops.push(B);used.add(B.cid)}
  const cand=PL.filter(p=>p.air&&p.id!==A.id&&!used.has(p.cid)&&coScope(p)&&!inConf(p.cid)&&Math.hypot(p.x-A.x,p.z-A.z)*CO_DU>.35);
  const want=chance(.5)?4:3;while(drops.length<want&&cand.length){const p=cand.splice(Math.floor(R()*cand.length),1)[0];if(used.has(p.cid))continue;if(!coRoute("air",A.id,p.id))continue;drops.push(p);used.add(p.cid)}
  if(drops.length<3)return null;
  const PT=Object.values(VT).find(t=>t.mode==="air"&&t.tier<=7&&!t.loc)||T,sp=Math.min(T.spd,PT.spd)*spdK(),hd=HAND.air*handK(),ul=hd*.5,lt=(a,b)=>{const r=coRoute("air",a.id,b.id);return r?r.len/sp:1e9};
  const eta=ord=>{let t=0,prev=A;return ord.map((d,i)=>{t+=lt(prev,d)+hd*(i?1:2);const e=t;t+=ul;prev=d;return e})};
  const perms=a=>a.length<2?[a]:a.flatMap((x,i)=>perms(a.filter((_,j)=>j!==i)).map(r=>[x,...r]));const all=perms(drops);
  let best=all[0],bt=1e9;for(const o of all){const e=eta(o),s=e[e.length-1];if(s<bt){bt=s;best=o}}
  const eB=eta(best),dl=new Map(best.map((d,i)=>[d.id,+(eB[i]*rnd(1.06,1.25)+.08).toFixed(1)]));
  // one drop is critical: it must go early, even if it is not the nearest
  if(chance(.75)){const c=best[rint(1,best.length-1)];dl.set(c.id,+((2*hd+lt(A,c))*rnd(1.08,1.2)+.05).toFixed(1));c._crit=1;
    let b2=null,t2=1e9;for(const o of all){if(o[0]!==c)continue;const e=eta(o);if(e[e.length-1]<t2){t2=e[e.length-1];b2=o}}const e2=eta(b2);b2.forEach((d,i)=>{if(d!==c)dl.set(d.id,Math.max(dl.get(d.id),+(e2[i]*rnd(1.04,1.15)+.05).toFixed(1)))})}
  const cg=CARGO_I[k.cg],tons=Math.min(k.tons,T.cap*.9);let sh=drops.map(()=>.5+R());const ss=sh.reduce((a,b)=>a+b,0);
  const multi=drops.map((d,i)=>{const tn=Math.max(.2,+(tons*sh[i]/ss).toFixed(1)),r=coRoute("air",A.id,d.id),crit=!!d._crit;delete d._crit;
    return{to:d.id,tons:tn,dl:dl.get(d.id),crit,pay:Math.round((6000+260*r.len*Math.pow(tn,.85))*cg.k*priceK(d.cid)*(crit?1.35:1)*rnd(.95,1.1)*1.15)}});
  const last=best[best.length-1];
  return{...k,to:last.id,tons:+multi.reduce((a,d)=>a+d.tons,0).toFixed(1),pay:multi.reduce((a,d)=>a+d.pay,0),dlDays:Math.max(...multi.map(d=>d.dl)),multi,minR:0}}
{const _g=coGen;coGen=function(){const k=_g();if(!k||k.mode!=="air"||k.legs||!lpOn()||!chance(.4))return k;return lpMakeMulti(k)||k}}
{const _p=coPlan;coPlan=function(k){if(k.multi)return{ok:false,why:"Збірний рейс: порядок посадок прокладається вручну"};return _p(k)}}
{const _b=boardCard;boardCard=function(k,P){if(!k.multi)return _b(k,P);const A=PL[k.from],cg=CARGO_I[k.cg];
  return `<div class="blk" style="border-color:rgba(214,150,255,.45)"><div class="row sp wrap"><div class="row" style="min-width:0"><span class="acc" style="color:rgb(${LP_C.air})">${ic("plane")}</span><div style="min-width:0"><b>Збірний авіарейс з ${plName(A)}</b><div class="note">${ic(cg.ic)} ${esc(cg.n)} · ${k.tons} т · ${k.multi.length} країни · один літак</div></div></div><div style="text-align:right"><b class="num" style="font-size:16px">${fmtUSD(k.pay)}</b><div class="note">${Math.max(0,k.exp-G.day)} дн. на біржі</div></div></div>
  <div style="display:flex;flex-direction:column;gap:4px;margin:8px 0">${k.multi.map(d=>{const p=PL[d.to];return `<div class="row sp"><span class="row" style="gap:6px"><img src="${G.C[p.cid].flag}" style="width:16px;border-radius:2px" alt="">${esc(p.name)} <span class="note">${d.tons} т</span></span><span class="note">${d.crit?`<span class="bad">критично</span> · `:""}до ${daysS(d.dl)} · ${fmtUSD(d.pay)}</span></div>`}).join("")}</div>
  <div class="row sp wrap"><span class="note">У кожної країни свій термін — порядок посадок обираєте ви.</span><div class="row"><button class="btn sm pri" data-act="lpPlan" data-arg="${k.id}">${ic("road")}Прокласти маршрут</button><button class="btn sm" data-act="coDecl" data-arg="${k.id}" aria-label="Прибрати">${ic("trash")}</button></div></div></div>`}}
function lpDropsHTML(C){const k=LP.k;const by=new Map((C.drops||[]).map(x=>[x.d.to,x]));
  return `<span class="lbl" style="display:block;margin-top:10px">Пункти посадки</span><div style="display:flex;flex-direction:column;gap:4px;margin-top:6px">${k.multi.slice().sort((a,b)=>{const ia=by.has(a.to)?C.drops.indexOf(by.get(a.to)):99,ib=by.has(b.to)?C.drops.indexOf(by.get(b.to)):99;return ia-ib||a.dl-b.dl}).map(d=>{const p=PL[d.to],x=by.get(d.to),n=x?(C.drops.indexOf(x)+1):null;
    return `<div class="lrow" style="padding:5px 8px"><span class="num" style="width:18px;text-align:center;color:${x?`rgb(${LP_C.air})`:"var(--mut)"}">${n||"·"}</span><div style="min-width:0"><b><img src="${G.C[p.cid].flag}" style="width:14px;border-radius:2px;vertical-align:-1px" alt=""> ${esc(p.name)}</b>${d.crit?` <span class="bad note">критично</span>`:""}<div class="note">${d.tons} т · термін ${daysS(d.dl)} · ${fmtUSD(d.pay)}${x?` · прибуття ${daysS(x.eta)} ${x.late>0?`<span class="bad">запізнення ${daysS(x.late)}</span>`:`<span class="good">вчасно</span>`}`:" · ще не в маршруті"}</div></div></div>`}).join("")}</div>`}
ACT.lpOrder=kind=>{const k=LP.k;if(!k||!k.multi)return;let left=k.multi.map(d=>PL[d.to]),cur=PL[k.from];const ord=[];
  if(kind==="urg")ord.push(...left.sort((a,b)=>k.multi.find(d=>d.to===a.id).dl-k.multi.find(d=>d.to===b.id).dl));
  else while(left.length){left.sort((a,b)=>Math.hypot(a.x-cur.x,a.z-cur.z)-Math.hypot(b.x-cur.x,b.z-cur.z));cur=left.shift();ord.push(cur)}
  LP.pts=[k.from,...ord.map(p=>p.id)];LP.modes=ord.map(()=>"air");LP.mode="air";lpPanel();REDRAW=true};
function lpDropPay(j,d){const late=Math.max(0,G.day-d.dlA);let pay=j.lost?0:d.pay*(late>0?Math.max(.35,1-late*.12):1)*(1-Math.min(.8,j.dmg||0));pay=Math.round(pay);
  CO.cash+=pay;CO.m.contract+=pay;if(!j.lost){CO.cdel++;CO.deliv++;CO.tons+=d.tons}const s=late>2?2:late>0?3.2:5;CO.rating=clamp(CO.rating+(s-CO.rating)*.012,1,5);
  const tone=late>0?"warn":"good",p=PL[d.to];coNews(tone,"plane",`${CO.name}: збірний рейс — ${d.tons} т доставлено в ${p.name} (${cnm(p.cid)}): ${fmtUSD(pay,true)}${late>0?`, запізнення ${late.toFixed(1)} дн.`:", вчасно"}`);
  CO.last.unshift({d:{...G.date},from:j.lp.k0.from,to:d.to,cg:j.k.cg,pay,tone,mode:"air"});if(CO.last.length>30)CO.last.pop()}


/* ---------- changing course of a trip under way : ships, trucks, planes ---------- */
const SR={on:false,j:null,pts:[],avoid:false,prevSpeed:0,hover:null,hk:"",hp:null,m:"sea"};
const SR_N={sea:{w:"Судно",where:"по морю",pt:"точка в морі",bad:"Через ці точки судно не пройде: суходіл."},
  road:{w:"Вантажівка",where:"по дорогах або значках КПП",pt:"точка на дорозі",bad:"Через ці точки немає проїзду: дорогу перекрито."},
  air:{w:"Літак",where:"будь-де на мапі",pt:"точка курсу",bad:"Курс не прокласти: закрите небо."}};
function srWat(){const W=CBL.nx-1,H=CBL.nz-1;if(!BOARD.wat||BOARD.wat.length!==W*H){const a=new Uint8Array(W*H);for(let j=0;j<H;j++)for(let i=0;i<W;i++)a[j*W+i]=bWaterCell(i,j)?1:0;BOARD.wat=a}return BOARD.wat}
const srCell=(x,z)=>{const W=CBL.nx-1,H=CBL.nz-1,i=Math.floor((x+WX/2)/CBL.st),j=Math.floor((z+WZ/2)/CBL.st);return i<0||j<0||i>=W||j>=H?-1:j*W+i};
const srCXY=c=>{const W=CBL.nx-1;return[-WX/2+(c%W+.5)*CBL.st,-WZ/2+(((c/W)|0)+.5)*CBL.st]};
function srNearW(c,rad,pass){const W=CBL.nx-1,H=CBL.nz-1;if(c>=0&&pass(c))return c;if(c<0)return -1;const x0=c%W,y0=(c/W)|0;let best=-1,bd=1e9;
  for(let dy=-rad;dy<=rad;dy++)for(let dx=-rad;dx<=rad;dx++){const x=x0+dx,y=y0+dy;if(x<0||y<0||x>=W||y>=H)continue;const m=y*W+x;if(pass(m)&&dx*dx+dy*dy<bd){bd=dx*dx+dy*dy;best=m}}return best}
/* what can hurt this kind of transport: pirates & storms at sea, bandits & bad weather on roads, bad weather in the air */
const srDanger=(m=SR.m)=>(m==="sea"?(CO.pir||[]).map(z=>({x:z.x,z:z.z,r:z.r,k:"pir",n:"Пірати: "+(z.name||"")})):m==="road"?(CO.band||[]).map(z=>({x:z.x,z:z.z,r:z.r,k:"band",n:"Бандити: "+(z.name||"")})):[])
  .concat((CO.wx||[]).filter(w=>WXK[w.k][m]).map(w=>({x:w.x,z:w.z,r:w.r,k:"wx",n:w.n})));
/* A* over the cell grid: water only for ships, everything but closed skies for planes; with avoid, danger zones cost a lot */
function srGrid(m,x0,z0,x1,z1,avoid){const W=CBL.nx-1,H=CBL.nz-1,N=W*H;let pass;
  if(m==="sea"){const wat=srWat();pass=c=>!!wat[c]}
  else{const blk=new Uint8Array(N);if(SKY.size)for(let c=0;c<N;c++){const [x,z]=srCXY(c),o=bOwn(x,z);if(o>=0&&SKY.has(o))blk[c]=1}pass=c=>!blk[c]}
  const s0=srNearW(srCell(x0,z0),3,pass),e0=srNearW(srCell(x1,z1),3,pass);if(s0<0||e0<0)return null;
  const D=avoid?srDanger(m):[],pen=new Float32Array(D.length?N:0);if(D.length)for(const z of D){const r=Math.ceil(z.r/CBL.st)+1,c=srCell(z.x,z.z);if(c<0)continue;const cx=c%W,cy=(c/W)|0;
    for(let dy=-r;dy<=r;dy++)for(let dx=-r;dx<=r;dx++){const x=cx+dx,y=cy+dy;if(x<0||y<0||x>=W||y>=H)continue;const [px,pz]=srCXY(y*W+x);if(Math.hypot(px-z.x,pz-z.z)<z.r)pen[y*W+x]=30}}
  const g=new Float32Array(N).fill(1e9),prev=new Int32Array(N).fill(-1),hk=[],hv=[],ex=e0%W,ey=(e0/W)|0;
  const push=(f,v)=>{hk.push(f);hv.push(v);let k=hk.length-1;while(k>0){const p=(k-1)>>1;if(hk[p]<=hk[k])break;[hk[p],hk[k]]=[hk[k],hk[p]];[hv[p],hv[k]]=[hv[k],hv[p]];k=p}};
  const pop=()=>{const v=hv[0],lk=hk.pop(),lv=hv.pop();if(hk.length){hk[0]=lk;hv[0]=lv;let k=0;for(;;){const l=k*2+1,r=l+1;let mm=k;if(l<hk.length&&hk[l]<hk[mm])mm=l;if(r<hk.length&&hk[r]<hk[mm])mm=r;if(mm===k)break;[hk[mm],hk[k]]=[hk[k],hk[mm]];[hv[mm],hv[k]]=[hv[k],hv[mm]];k=mm}}return v};
  g[s0]=0;push(0,s0);while(hk.length){const n=pop();if(n===e0)break;const x=n%W,y=(n/W)|0;for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;const nx=x+dx,ny=y+dy;if(nx<0||ny<0||nx>=W||ny>=H)continue;const c=ny*W+nx;if(!pass(c))continue;if(dx&&dy&&(!pass(y*W+nx)||!pass(ny*W+x)))continue;
    const ng=g[n]+(dx&&dy?1.4142:1)+(pen.length?pen[c]:0);if(ng<g[c]){g[c]=ng;prev[c]=n;push(ng+Math.hypot(nx-ex,ny-ey),c)}}}
  if(g[e0]>=1e9)return null;const cells=[];for(let n=e0;n>=0;n=prev[n]){cells.push(n);if(n===s0)break}cells.reverse();
  const pts=[x0,z0];for(let k=0;k<cells.length;k++){const c=cells[k];if(k>0&&k<cells.length-1&&c-cells[k-1]===cells[k+1]-c)continue;pts.push(...srCXY(c))}pts.push(x1,z1);return pts}
/* roads: the road graph; with avoid, nodes inside bandit zones, bad weather and jams are closed for this search */
function srRoad(a,b,avoid){const na=a.v!=null?a.v:nodeAt(a.x,a.z),nb=b.v!=null?b.v:nodeAt(b.x,b.z);let p=null;
  if(avoid){const D=srDanger("road"),bad=n=>{if(JAMN.has(n))return true;const [x,z]=bXY(n);return D.some(q=>Math.hypot(x-q.x,z-q.z)<q.r)};const sv=BLK;BLK=(n,m,r)=>(sv&&sv(n,m,r))||bad(m)&&m!==nb;try{p=boardPath(na,nb)}finally{BLK=sv}}
  if(!p)p=boardPath(na,nb);if(!p)return null;const out=Array.from(p);if(a.v==null||a.start)out.unshift(a.x,a.z);return out}
function srSeg(m,a,b,avoid){if(m==="road")return srRoad(a,b,avoid);if(m==="air"&&!avoid){const p=incAirPath(a.x,a.z,b.x,b.z);return p?Array.from(p):null}return srGrid(m,a.x,a.z,b.x,b.z,avoid)}
const srLen=p=>{let L=0;for(let i=2;i<p.length;i+=2)L+=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]);return L};
function srOK(j){if(!j||j.cons||!["sea","road","air"].includes(j.mode)||j.ret||j.back||j.lost||j.hold>0||!CO.jobs.includes(j))return false;const st=coJobState(j,coNow()-j.t0);
  if(j.mode==="road"&&j.lead>.002&&st.s<j.lead*.97&&(st.seg===0||!!st.w||st.inc&&["wx","jam"].includes(st.inc.k)))return true; /* the empty run to the loading city */
  return st.s>=j.lead-1e-6&&st.s<j.lead+j.len*.97&&(st.seg===1||!!st.w||st.inc&&["wx","jam"].includes(st.inc.k))}
/* during the empty run the new course leads to the loading city; the loaded part of the trip stays as planned */
function srLeadNow(j){const st=coJobState(j,coNow()-j.t0);return j.mode==="road"&&j.lead>.002&&st.s<j.lead-1e-6}
function srLeadIdx(j){const A=PL[j.k.from];let bi=-1,bd=1e9;let L=0;for(let i=0;i<j.p.length/2;i++){if(i)L+=Math.hypot(j.p[i*2]-j.p[i*2-2],j.p[i*2+1]-j.p[i*2-1])*CO_DU;const d=Math.hypot(j.p[i*2]-A.x,j.p[i*2+1]-A.z)+Math.abs(L-j.lead)*.5;if(d<bd){bd=d;bi=i}}return bi}
function srNow(j){const st=coJobState(j,coNow()-j.t0),pos=coPosAt(j,st.s),rem=[pos[0],pos[1]],lead=srLeadNow(j),li=lead?srLeadIdx(j):1e9;for(let i=pos[2]+1;i<=li&&i<j.p.length/2;i++)rem.push(j.p[i*2],j.p[i*2+1]);return{st,pos,rem,left:Math.max(0,j.tot-(coNow()-j.t0))}}
function srStart(j,N){if(j.mode!=="road")return{x:N.pos[0],z:N.pos[1]};return{x:N.pos[0],z:N.pos[1],v:nodeAt(N.pos[0],N.pos[1]),start:1}} // the nearest road point: the truck may turn back
function srDest(j){const B=PL[srLeadNow(j)?j.k.from:j.k.to];return j.mode==="road"?{x:B.x,z:B.z,v:B.node}:{x:B.x,z:B.z}}
function srBuild(){const j=SR.j,N=srNow(j),way=[srStart(j,N),...SR.pts,srDest(j)];const out=[];
  for(let i=1;i<way.length;i++){const p=srSeg(SR.m,way[i-1],way[i],SR.avoid);if(!p)return null;for(let k=out.length?2:0;k<p.length;k++)out.push(p[k])}return out}
function srCalc(){const ck=SR.pts.map(q=>q.x+','+q.z).join(';')+SR.avoid+SR.j.t0+':'+coNow().toFixed(3)+CO.clV;if(SR.ck===ck)return SR.cc;SR.ck=ck;return SR.cc=srCalc0()}
function srCalc0(){const j=SR.j,m=SR.m,T=VT[j.t],N=srNow(j),np=srBuild(),sp=T.spd*spdK(),oldLen=srLen(N.rem)*CO_DU,oldRisk=lpRisk({p:N.rem},m);
  const unl=N.st.s>=j.lead+j.len?0:j.hs;const curEta=N.left;if(!np)return{N,oldLen,oldRisk,curEta,bad:true};
  const len=srLen(np)*CO_DU,cps=m==="road"?bCrossings(np,CO_DU).filter(c=>c.s>.03).map(c=>({s:c.s,a:c.a,b:c.b,x:c.x,z:c.z,w:cpWait(c.b,m)})):[],wait=cps.reduce((a,q)=>a+q.w,0);
  const eta=len/sp+unl+wait+(m==="air"?(j.cust||0):0)+(srLeadNow(j)?j.tm+(j.stops||[]).filter(q=>q.s>j.lead).reduce((a,q)=>a+(q.w||0),0):0),extra=Math.max(0,(len-oldLen)*T.fuel*CO.fuel*fuelK(m)*j.n),risk=lpRisk({p:np},m);return{N,np,len,eta,extra,risk,oldLen,oldRisk,curEta,unl,cps,wait,dl:j.dl-coNow()}}
function srOpen(j){if(typeof lpOn!=="function"||!lpOn())return;if(!srOK(j))return toast("warn","Курс змінити не можна",`${SR_N[j.mode]?SR_N[j.mode].w:"Транспорт"} не в дорозі або затриманий`);
  SR.on=true;SR.j=j;SR.m=j.mode;SR.pts=[];SR.avoid=false;SR.hk="";SR.hp=null;SR.prevSpeed=G.speed;setSpeed(0);closeWin();document.body.classList.add("lplan");
  const q=srNow(j).pos,B=PL[j.k.to];Cam.ttx=(q[0]+B.x)/2;Cam.ttz=(q[1]+B.z)/2+.3;Cam.tdist=clamp(Math.hypot(q[0]-B.x,q[1]-B.z)*1.5+3,3,WX*1.1);srPanel();REDRAW=true}
function srClose(){SR.on=false;lpTagsOff();document.body.classList.remove("lplan");const el=$("#lpPanel");if(el)el.remove();if(SR.prevSpeed)setSpeed(SR.prevSpeed);REDRAW=true}
ACT.srOpen=id=>{const j=CO.jobs.find(x=>x.id===+id);if(j)srOpen(j)};
ACT.srCancel=()=>srClose();
ACT.srUndo=()=>{SR.pts.pop();srPanel();REDRAW=true};
ACT.srAvoid=()=>{SR.avoid=!SR.avoid;srPanel();REDRAW=true};
ACT.srGo=()=>{const C=srCalc();if(C.bad)return;const j=SR.j,m=SR.m,T=VT[j.t],tm=C.len/(T.spd*spdK());
  if(C.extra>0){CO.cash-=C.extra;CO.m.fuel+=C.extra}
  if(srLeadNow(j)){const li=srLeadIdx(j),main=Array.from(j.p.slice(li*2)),np=C.np.concat(main.slice(2)),P=new Float32Array(np);
    const cps=bCrossings(P,CO_DU).filter(c=>c.s>.03).map(c=>({s:c.s,a:c.a,b:c.b,x:c.x,z:c.z,w:cpWait(c.b,m)})),wait=cps.reduce((a,q)=>a+q.w,0);
    Object.assign(j,{p:P,lead:C.len,tl:tm,cont:false,pz:[],drag:[],t0:coNow(),wxd:null,wxCool:0,srWarn:{},jn:null,stops:cps});delete j._c;j.tot=tm+(j.hs||0)+j.tm+wait;
    j.ev.push(`Перегін змінено${SR.pts.length?` через ${SR.pts.length} ${SR.pts.length===1?"точку":"точки"}`:""}`);CO.winDirty=true;srClose();
    toast("good","Перегін змінено",`${T.n}: до ${PL[j.k.from].name} через ${daysS(tm)}${C.extra>0?` · пальне +${fmtUSD(C.extra)}`:""}`);return}
  const H=m==="air"?coAlt(j,C.N.st):0;
  Object.assign(j,{p:new Float32Array(C.np),lead:0,tl:0,len:C.len,tm,cont:true,pz:[],t0:coNow(),cust:m==="air"?(j.cust||0):0,wxd:null,wxCool:0,srWarn:{},jn:null});delete j._c;
  if(m==="road"){j.stops=C.cps;j.tot=tm+C.unl+C.wait}else{j.stops=[];j.tot=tm+C.unl+(j.cust||0)}
  if(m==="air"){j.airS=1;j.airH=H/.22*CO_DU}
  j.ev.push(`Курс змінено${SR.pts.length?` через ${SR.pts.length} ${SR.pts.length===1?"точку":"точки"}`:""}${SR.avoid?" в обхід небезпечних зон":""}`);CO.winDirty=true;
  srClose();toast("good","Курс змінено",`${T.n}: прибуття через ${daysS(C.eta)}${C.extra>0?` · пальне +${fmtUSD(C.extra)}`:""}`)};
function srRiskTxt(r){return [r.pir?`пірати ${r.pir}`:"",r.band?`бандити ${r.band}`:"",r.wx?`негода ${r.wx}`:"",r.jam?`перекриття ${r.jam}`:"",r.cl?`закриті кордони ${r.cl}`:""].filter(Boolean).join(", ")||"чисто"}
function srPanel(){let el=$("#lpPanel");if(!SR.on){if(el)el.remove();return}if(!el){el=document.createElement("div");el.id="lpPanel";el.className="glass";document.body.appendChild(el)}
  const j=SR.j,m=SR.m,T=VT[j.t],C=srCalc(),B=PL[j.k.to],cg=CARGO_I[j.k.cg],good=(a,b)=>a<b-.005?"good":a>b+.005?"bad":"",N_=SR_N[m];
  const legend=m==="sea"?"червоні кола — пірати, сині — шторми":m==="road"?"червоні кола — бандити, сині — негода; з «Оминати небезпеку» маршрут обходить і перекриті дороги":"сині кола — негода; закрите небо літак обходить сам";
  el.innerHTML=`<div class="row sp"><b style="font-size:15px">${ic(LP_T[m])} Зміна курсу</b><button class="xbtn" data-act="srCancel" aria-label="Закрити">${ic("close")}</button></div>
   <div class="note" style="margin-top:4px">${esc(T.n)}${j.n>1?" ×"+j.n:""} · ${esc(cg.n)}, ${j.k.tons} т · до ${esc(B.name)}</div>
   <div class="note" style="margin-top:8px">Клікайте ${N_.where} — точки нового курсу. Пунктир — поточний курс; ${legend}.</div>
   <div style="display:flex;flex-direction:column;gap:4px;margin-top:8px">${SR.pts.map((q,i)=>`<div class="lrow" style="padding:5px 8px"><span class="num" style="color:rgb(${LP_C[m]})">${i+1}</span><div class="note">${q.cp?esc(lpName(q)):N_.pt}${!q.cp?(()=>{const c=bOwn(q.x,q.z);return c>=0?" · "+esc(cnm(c)):""})():""}</div></div>`).join("")||`<div class="note">${SR.avoid?"Курс прокладено автоматично в обхід небезпеки.":"Точок ще немає — новий курс іде прямо до "+esc(B.name)+"."}</div>`}</div>
   ${C.bad?`<div class="note bad" style="margin-top:8px">${ic("alert")} ${N_.bad}</div>`:`<div class="blk" style="margin-top:10px">
    <div class="row sp"><span>Прибуття</span><b class="num ${good(C.eta,C.curEta)}">${daysS(C.eta)} <span class="note">зараз ${daysS(C.curEta)}</span></b></div>${lpBar(C.eta,Math.max(C.dl,C.eta,.1)*1.2,C.eta>C.dl?"bad":"good")}<div class="note">дедлайн через ${daysS(Math.max(0,C.dl))}${C.eta>C.dl?` · <span class="bad">запізнення ${daysS(C.eta-C.dl)}</span>`:""}</div>
    <div class="row sp" style="margin-top:8px"><span>Відстань</span><b class="num">${kmS(C.len)} <span class="note">зараз ${kmS(C.oldLen)}</span></b></div>
    ${m==="road"&&C.cps.length?`<div class="row sp" style="margin-top:8px"><span>Пункти пропуску</span><b class="num">${C.cps.length} · ${daysS(C.wait)}</b></div>`:""}
    <div class="row sp" style="margin-top:8px"><span>Додаткове пальне</span><b class="num">${C.extra>0?fmtUSD(C.extra):"—"}</b></div>
    <div class="row sp" style="margin-top:8px"><span>Ризик</span><b class="num ${good(C.risk.p,C.oldRisk.p)}">${Math.round(C.risk.p*100)}% <span class="note">зараз ${Math.round(C.oldRisk.p*100)}%</span></b></div>
    <div class="note">на новому курсі: ${srRiskTxt(C.risk)} · на поточному: ${srRiskTxt(C.oldRisk)}</div></div>`}
   <div class="row wrap" style="gap:6px;margin-top:10px"><button class="btn sm" data-act="srUndo" ${SR.pts.length?"":"disabled"}>${ic("refresh")}Прибрати точку</button><button class="btn sm ${SR.avoid?"pri":""}" data-act="srAvoid">${ic("shield")}Оминати небезпеку</button></div>
   <button class="btn pri" style="width:100%;margin-top:10px" data-act="srGo" ${C.bad?"disabled":""}>${ic(LP_T[m])}Змінити курс</button>`}
/* a click becomes a course point: a water cell for ships, a road node (or checkpoint) for trucks, any point for planes */
function srPick(x,y){const m=SR.m;if(m==="road")return lpPickW(x,y,"road");const g=pickPlane(x,y);if(!g)return null;
  if(m==="sea"){const c=srCell(g[0],g[1]);if(c<0||!srWat()[c])return null;const [cx,cz]=srCXY(c);return{x:cx,z:cz,c}}return{x:g[0],z:g[1]}}
{const _cc=coClick;coClick=function(x,y){if(!SR.on)return _cc(x,y);const q=srPick(x,y);
  if(!q)return toast("warn",SR.m==="sea"?"Тут суходіл":"Тут немає дороги",SR.m==="sea"?"Точка курсу має бути в морі":"Клікніть по дорозі або значку КПП"),true;SR.pts.push(q);srPanel();REDRAW=true;return true}}
addEventListener("pointermove",e=>{if(SR.on){SR.hover={x:e.clientX,y:e.clientY};REDRAW=true}},{passive:true});
addEventListener("keydown",e=>{if(SR.on&&e.key==="Escape"){e.stopImmediatePropagation();srClose()}if(SR.on&&(e.ctrlKey||e.metaKey)&&e.code==="KeyZ"){e.preventDefault();ACT.srUndo()}},true);
function srDraw(g,dpr){if(!SR.on)return;if(!CO.jobs.includes(SR.j)){srClose();return}const m=SR.m,P=(x,z)=>{const q=project(x,0,z);return q?[q.x*dpr,q.y*dpr]:null};
  const line=(p,col,w,dash)=>{g.save();g.setLineDash(dash||[]);g.strokeStyle=col;g.lineWidth=w*dpr;g.beginPath();let s=false;for(let i=0;i<p.length;i+=2){const q=P(p[i],p[i+1]);if(!q){s=false;continue}s?g.lineTo(...q):g.moveTo(...q);s=true}g.stroke();g.restore()};
  for(const z of srDanger()){const c=P(z.x,z.z),e=P(z.x+z.r,z.z);if(!c||!e)continue;const r=Math.hypot(e[0]-c[0],e[1]-c[1]),red=z.k!=="wx";g.fillStyle=red?"rgba(240,98,95,.16)":"rgba(110,170,255,.16)";g.strokeStyle=red?"rgba(240,98,95,.8)":"rgba(110,170,255,.8)";g.lineWidth=1.5*dpr;g.beginPath();g.arc(c[0],c[1],r,0,7);g.fill();g.stroke()}
  const C=srCalc();line(C.N.rem,"rgba(220,230,240,.6)",2,[6*dpr,5*dpr]);
  if(C.np){line(C.np,"rgba(6,12,18,.7)",5);line(C.np,`rgb(${LP_C[m]})`,3)}
  if(SR.hover){const k=Math.round(SR.hover.x/4)+":"+Math.round(SR.hover.y/4)+":"+SR.pts.length+SR.avoid;if(SR.hk!==k){SR.hk=k;const q=srPick(SR.hover.x,SR.hover.y);SR.hq=q;
      SR.hp=q?srSeg(m,SR.pts.length?SR.pts[SR.pts.length-1]:srStart(SR.j,C.N),q,SR.avoid):null}
    if(SR.hp){g.save();g.globalAlpha=.8;line(SR.hp,`rgb(${LP_C[m]})`,2,[3*dpr,4*dpr]);g.restore()}
    if(SR.hq){const s=P(SR.hq.x,SR.hq.z);if(s){g.fillStyle="#fff";g.strokeStyle=`rgb(${LP_C[m]})`;g.lineWidth=2.5*dpr;g.beginPath();g.arc(s[0],s[1],4.5*dpr,0,7);g.fill();g.stroke()}}}
  SR.pts.forEach(q=>{const s=P(q.x,q.z);if(!s)return;g.fillStyle=`rgb(${LP_C[m]})`;g.strokeStyle="#06121b";g.lineWidth=2*dpr;g.beginPath();g.arc(s[0],s[1],5.5*dpr,0,7);g.fill();g.stroke()});
  const s=P(C.N.pos[0],C.N.pos[1]);if(s){g.fillStyle="#fff";g.strokeStyle=`rgb(${LP_C[m]})`;g.lineWidth=3*dpr;g.beginPath();g.arc(s[0],s[1],7*dpr,0,7);g.fill();g.stroke()}
  const B=PL[SR.j.k.to],d=P(B.x,B.z);if(d){const f=(performance.now()/900)%1;g.strokeStyle=`rgba(255,214,90,${(1-f).toFixed(2)})`;g.lineWidth=2.4*dpr;g.beginPath();g.arc(d[0],d[1],(10+f*16)*dpr,0,7);g.stroke()}
  lpTags(g,dpr,[{pid:SR.j.k.from,tag:"ВІДПРАВКА",col:LP_DEP},{pid:B.id,tag:"ПРИБУТТЯ",col:LP_ARR}]);REDRAW=true}
{const _dc=drawCompany;drawCompany=function(g,dpr){_dc(g,dpr);if(SR.on){const c=document.getElementById("vcv");if(c)guard("Курс",()=>srDraw(c.getContext("2d"),dpr))}}}
/* "Змінити курс" in the trip card (DLC only) */
{const _c=coCard;coCard=function(){_c();const j=CO_SEL;if(!j||typeof lpOn!=="function"||!lpOn()||!srOK(j))return;const b=$("#ucard .uc-body");const h=srHit(j);if(b&&!b.querySelector("[data-act=srOpen]"))b.insertAdjacentHTML("beforeend",`<button class="btn sm${h?" pri":""}" style="margin-top:-6px;width:100%;flex-shrink:0" data-act="srOpen" data-arg="${j.id}">${ic(LP_T[j.mode])}Змінити курс${h?" — небезпека на шляху":""}</button>`)}}
/* danger ahead: which zone the rest of the course crosses */
function srHit(j){const N=srNow(j),p=N.rem;for(const z of srDanger(j.mode)){for(let i=0;i<p.length;i+=2)if(Math.hypot(p[i]-z.x,p[i+1]-z.z)<z.r)return z;
  for(let i=2;i<p.length;i+=2){const ax=p[i-2],az=p[i-1],bx=p[i],bz=p[i+1],L=Math.hypot(bx-ax,bz-az)||1e-9,t=clamp(((z.x-ax)*(bx-ax)+(z.z-az)*(bz-az))/(L*L),0,1);if(Math.hypot(ax+(bx-ax)*t-z.x,az+(bz-az)*t-z.z)<z.r)return z}}return null}
{const _jd=coJobsDay;coJobsDay=function(){_jd();if(typeof lpOn!=="function"||!lpOn())return;for(const j of CO.jobs){if(!srOK(j))continue;const z=srHit(j);if(!z)continue;j.srWarn=j.srWarn||{};const key=z.k+Math.round(z.x*10)+":"+Math.round(z.z*10);if(j.srWarn[key])continue;j.srWarn[key]=1;
  const w=z.k==="pir"?"піратська зона":z.k==="band"?"зона бандитів":z.n.toLowerCase(),who=VT[j.t].n;
  coNews("warn",LP_T[j.mode],`${who} → ${PL[j.k.to].name}: на курсі ${w} — можна змінити курс у картці рейсу`);
  toast("warn",`${z.k==="pir"?"Пірати":z.k==="band"?"Бандити":z.n} на курсі`,`${who} → ${PL[j.k.to].name}. Відкрийте рейс і натисніть «Змінити курс»`)}}}
