/* =====================================================================
   Logistics: incidents on the road, border trouble, closures, weather, traffic
   ===================================================================== */
const INC_RED=new Set(["acc","brk","fuel","cl","cxl","theft","pir"]); // red blinking; everything else is an amber delay
let BLK_NOWX=false,INC_HIT=[],BLK=null,BLK_V=-1,BLK_W=null,JAM=[],JAMN=new Map(),SKY=new Set();
const WXK={
  snow:{n:"Снігова буря",ic:"wind",road:1,air:1,col:"205,228,255"},
  storm:{n:"Шторм",ic:"wave",sea:1,col:"110,170,255"},
  hur:{n:"Ураган",ic:"wind",sea:1,air:1,slow:{road:.4,rail:.5},col:"196,150,255"},
  fog:{n:"Густий туман",ic:"eye",air:1,col:"200,208,216"},
  flood:{n:"Повінь",ic:"wave",road:1,rail:1,col:"92,170,236"},
  hsnow:{n:"Сильний снігопад",ic:"snow",air:1,slow:{road:.45,rail:.6},col:"232,242,255"},
  ice:{n:"Ожеледиця",ic:"ice",slow:{road:.35},col:"150,220,255"},
  rain:{n:"Сильна злива",ic:"rain",slow:{road:.6,rail:.8},col:"120,160,220"},
  tstorm:{n:"Буря",ic:"bolt",air:1,slow:{road:.55,rail:.7},col:"255,200,90"}};
ICONS.snow='<path d="M12 2v20M4 7l16 10M20 7 4 17M9.5 3.5 12 6l2.5-2.5M9.5 20.5 12 18l2.5 2.5"/>';
ICONS.ice='<path d="M3 20h18M6 16l2-4M11 16l2-4M16 16l2-4M12 3v6M9 5.5 12 9l3-3.5"/>';
ICONS.rain='<path d="M7 15a4.5 4.5 0 1 1 1.2-8.8A6 6 0 0 1 19.5 9 3.5 3.5 0 0 1 18 15z"/><path d="M8 18l-1 3M12 18l-1 3M16 18l-1 3"/>';
/* which weather can happen now: winter brings snow and ice, the rest of the year rain and storms */
function wxSeason(){const m=G.date.m;return m===11||m<=1?["snow","snow","hsnow","hsnow","ice","ice","fog","storm"]:m<=4?["rain","rain","tstorm","flood","flood","fog","storm","storm"]:m<=7?["rain","tstorm","tstorm","hur","fog","storm","storm","flood"]:m<=9?["rain","rain","tstorm","hur","fog","fog","storm","flood"]:["rain","hsnow","ice","fog","fog","storm","storm","tstorm"]}
const wxCl=K=>[K.road?"закрито дороги":K.slow&&K.slow.road?"сповільнено рух дорогами":"",K.rail?"закрито залізницю":K.slow&&K.slow.rail?"сповільнено потяги":"",K.sea?"закрито порти":"",K.air?"закрито аеропорти":""].filter(Boolean).join(", ");
const CL_WHY={cty:["Надзвичайний стан","Карантин через епідемію","Масові протести","Міжнародні санкції"],pair:["Дипломатичний конфлікт","Взаємні санкції","Торговельна війна"],cp:["Ремонт пункту пропуску","Страйк митників","Збій митної бази даних","Мінування узбіччя"]};
function incInit(){CO.cls=CO.cls||[];CO.wx=CO.wx||[];CO.band=CO.band||[];CO.imk=CO.imk||[];CO.pir=CO.pir||[];if(CO.clV==null)CO.clV=1}
const nodeAt=(x,z)=>bNode(clamp(Math.round((x+WX/2)/BL.st),0,BL.nx-1),clamp(Math.round((z+WZ/2)/BL.st),0,BL.nz-1));
function bNown(){const N=BL.nx*BL.nz;if(BOARD.nown&&BOARD.nown.length===N&&BOARD.nownW===G.world)return BOARD.nown;const a=new Int16Array(N);
  for(let n=0;n<N;n++){const [x,z]=bXY(n);a[n]=bOwn(x+1e-4,z+1e-4)}BOARD.nownW=G.world;return BOARD.nown=a}
const cnm=id=>G.C[id]?G.C[id].name:"—";
function incChanged(){CO.clV=(CO.clV||0)+1}

/* ---------- route blocking: closed borders, closed countries, closed checkpoints, roads shut by weather ---------- */
function incBlk(){incInit();BLK_V=CO.clV;BLK_W=G.world;CO_ROUTES.clear();SKY=new Set();for(const c of CO.cls)if(c.conf){SKY.add(c.a);SKY.add(c.b)}
  const pr=new Set(),cc=new Set(),cps=[];for(const c of CO.cls){if(c.kind==="pair"){pr.add(c.a*1000+c.b);pr.add(c.b*1000+c.a)}else if(c.kind==="cty")cc.add(c.a);else cps.push(c)}
  let wxn=null;const N=BL.nx*BL.nz;
  for(const w of CO.wx){const K=WXK[w.k];if(!K.road&&!K.rail||w.t0>coNow())continue;wxn=wxn||new Uint8Array(N);const f=(K.road?1:0)|(K.rail?2:0);
    const i0=Math.max(0,Math.floor((w.x-w.r+WX/2)/BL.st)),i1=Math.min(BL.nx-1,Math.ceil((w.x+w.r+WX/2)/BL.st)),k0=Math.max(0,Math.floor((w.z-w.r+WZ/2)/BL.st)),k1=Math.min(BL.nz-1,Math.ceil((w.z+w.r+WZ/2)/BL.st));
    for(let k=k0;k<=k1;k++)for(let i=i0;i<=i1;i++){const n=bNode(i,k),[x,z]=bXY(n);if(Math.hypot(x-w.x,z-w.z)<w.r*.8)wxn[n]|=f}}
  if(!pr.size&&!cc.size&&!cps.length&&!wxn){BLK=null;return}
  const own=bNown();
  BLK=(n,m,rail)=>{if(!BLK_NOWX&&wxn&&(wxn[m]&(rail?2:1)))return true;const a=own[n],b=own[m];if(a===b||a<0||b<0)return false;
    if(cc.has(a)||cc.has(b)||pr.has(a*1000+b))return true;
    if(cps.length){const [x1,z1]=bXY(n),[x2,z2]=bXY(m),mx=(x1+x2)/2,mz=(z1+z2)/2;for(const c of cps)if(Math.hypot(mx-c.x,mz-c.z)<CST*1.6)return true}return false}}
function incCrossCl(a,b,x,z){for(const c of CO.cls){if(c.kind==="cty"&&(c.a===a||c.a===b))return c;if(c.kind==="pair"&&(c.a===a&&c.b===b||c.a===b&&c.b===a))return c;if(c.kind==="cp"&&Math.hypot(x-c.x,z-c.z)<CST*1.8)return c}return null}
/* when the closure of a port/airport ends: the latest of the reasons keeping it shut */
function incPortUntil(p,mode){if(!CO.cls)return null;let u=null;const add=(why,until)=>{if(!u||until>u.until)u={why,until}};
  if(mode==="air"&&SKY.has(p.cid))for(const c of CO.cls)if(c.conf&&(c.a===p.cid||c.b===p.cid))add("Закрите небо: воєнний стан",c.until);
  for(const c of CO.cls)if(c.kind==="cty"&&c.a===p.cid)add(c.why,c.until);
  for(const w of CO.wx||[]){const K=WXK[w.k];if(w.t0>coNow())continue;if((mode==="sea"?K.sea:K.air)&&Math.hypot(p.x-w.x,p.z-w.z)<w.r)add(w.n,w.until)}return u}
function incPortCl(p,mode){if(!CO.cls)return null;if(mode==="air"&&SKY.has(p.cid))return "Закрите небо: воєнний стан";for(const c of CO.cls)if(c.kind==="cty"&&c.a===p.cid)return c.why;
  for(const w of CO.wx||[]){const K=WXK[w.k];if(w.t0>coNow())continue;if((mode==="sea"?K.sea:K.air)&&Math.hypot(p.x-w.x,p.z-w.z)<w.r)return w.n}return null}

/* ---------- closed sky: countries at war; planes fly around them ---------- */
function skyHit(x0,z0,x1,z1){if(!SKY.size)return false;const L=Math.hypot(x1-x0,z1-z0),n=Math.max(2,Math.ceil(L/(BL.st*.5)));for(let k=1;k<n;k++){const o=bOwn(x0+(x1-x0)*k/n,z0+(z1-z0)*k/n);if(o>=0&&SKY.has(o))return true}return false}
function incAirPath(x0,z0,x1,z1){if(!SKY.size||!skyHit(x0,z0,x1,z1))return new Float32Array([x0,z0,x1,z1]);
  const S=1,ST=CBL.st,W=CBL.nx,H=CBL.nz,N=W*H,id=(x,z)=>{const i=clamp(Math.round((x+WX/2)/ST/S),0,W-1),k=clamp(Math.round((z+WZ/2)/ST/S),0,H-1);return k*W+i},xy=c=>[-WX/2+(c%W)*S*ST,-WZ/2+((c/W)|0)*S*ST];
  const bad=c=>{const x=c%W,z=(c/W)|0;for(let dz=-1;dz<=1;dz++)for(let dx=-1;dx<=1;dx++){const i=x+dx,k=z+dz;if(i<0||k<0||i>=W||k>=H)continue;const o=bOwn(-WX/2+i*ST+1e-4,-WZ/2+k*ST+1e-4);if(o>=0&&SKY.has(o))return true}return false};
  const s0=id(x0,z0),e0=id(x1,z1),g=new Float32Array(N).fill(1e9),prev=new Int32Array(N).fill(-1),hk=[],hv=[],[ex,ez]=xy(e0);
  const push=(f,v)=>{hk.push(f);hv.push(v);let k=hk.length-1;while(k>0){const p=(k-1)>>1;if(hk[p]<=hk[k])break;[hk[p],hk[k]]=[hk[k],hk[p]];[hv[p],hv[k]]=[hv[k],hv[p]];k=p}};
  const pop=()=>{const v=hv[0],lk=hk.pop(),lv=hv.pop();if(hk.length){hk[0]=lk;hv[0]=lv;let k=0;for(;;){const l=k*2+1,r=l+1;let m=k;if(l<hk.length&&hk[l]<hk[m])m=l;if(r<hk.length&&hk[r]<hk[m])m=r;if(m===k)break;[hk[m],hk[k]]=[hk[k],hk[m]];[hv[m],hv[k]]=[hv[k],hv[m]];k=m}}return v};
  g[s0]=0;push(0,s0);while(hk.length){const n=pop();if(n===e0)break;const x=n%W,z=(n/W)|0;for(let dz=-1;dz<=1;dz++)for(let dx=-1;dx<=1;dx++){if(!dx&&!dz)continue;const nx=x+dx,nz=z+dz;if(nx<0||nz<0||nx>=W||nz>=H)continue;const m=nz*W+nx;
    const ng=g[n]+(dx&&dz?1.4142:1)*(m!==e0&&bad(m)?25:1);if(ng<g[m]){g[m]=ng;prev[m]=n;const [mx,mz]=xy(m);push(ng+Math.hypot(mx-ex,mz-ez)/(S*ST),m)}}}
  if(g[e0]>=1e9)return null;const cells=[];for(let n=e0;n>=0;n=prev[n]){cells.push(n);if(n===s0)break}cells.reverse();
  const raw=[[x0,z0],...cells.slice(1,-1).map(xy),[x1,z1]],out=[raw[0]];let i=0;
  while(i<raw.length-1){let k=raw.length-1;while(k>i+1&&skyHit(raw[i][0],raw[i][1],raw[k][0],raw[k][1]))k--;out.push(raw[k]);i=k}
  return new Float32Array(out.flat())}
/* a plane already in the air when the sky closes turns away */
function incAirReroute(j,st){const T=VT[j.t],sp=T.spd*spdK(),cur=coPosAt(j,st.s),A=PL[j.k.from],B=PL[j.ret?j.k.to:j.k.to],H=coAlt(j,st);
  if(st.seg===0&&!j.ret){const a=incAirPath(cur[0],cur[1],A.x,A.z),b=incAirPath(A.x,A.z,B.x,B.z);if(!a||!b)return false;
    const pts=[...a,...Array.from(b).slice(2)],la=pl(a)*CO_DU,lb=pl(b)*CO_DU;Object.assign(j,{p:new Float32Array(pts),lead:la,len:lb,tl:la/sp,tm:lb/sp,t0:coNow(),pz:[],airS:0,airH:H/.22*CO_DU});j.tot=j.tl+j.hs+j.tm+j.hs+(j.cust||0)}
  else{const b=incAirPath(cur[0],cur[1],B.x,B.z);if(!b)return false;const lb=pl(b)*CO_DU;Object.assign(j,{p:b,lead:0,tl:0,len:lb,tm:lb/sp,t0:coNow(),pz:[],cont:true,airS:1,airH:H/.22*CO_DU});j.tot=j.tm+(j.ret?0:j.hs+(j.cust||0))}
  delete j._c;j.ev.push("Закрите небо: літак змінив курс в обхід зони бойових дій");CO.winDirty=true;return true}
const pl=p=>{let L=0;for(let i=2;i<p.length;i+=2)L+=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]);return L};
function incSkyCheck(j,st){if(j.skyV===CO.clV)return;if(st.seg<0)return;j.skyV=CO.clV;if(!SKY.size)return;const s=st.s/CO_DU,c=coCum(j),n=c.length;let hit=false;
  for(let i=1;i<n&&!hit;i++){if(c[i]<s)continue;const a=i===1||c[i-1]<s?coPosAt(j,st.s):[j.p[i*2-2],j.p[i*2-1]];hit=skyHit(a[0],a[1],j.p[i*2],j.p[i*2+1])}
  if(hit&&incAirReroute(j,st))toast("warn","Закрите небо",`${VT[j.t].n}: курс змінено в обхід зони бойових дій`)}

/* ---------- pauses: the vehicle stops where it is (accident, queue, weather) ---------- */
function coPause(j,w,ph,k,extra){j.pz=j.pz||[];let at=coNow()-j.t0;for(const p of j.pz)if(at>=p.e&&at<p.e+p.w)at=p.e+p.w;
  const p=Object.assign({e:at,w:Math.max(.01,w),ph,k},extra||{});j.pz.push(p);j.pz.sort((a,b)=>a.e-b.e);j.tot+=p.w;CO.winDirty=true;return p}
function coPauseCut(j,p){const e=coNow()-j.t0;if(e>=p.e+p.w)return;const nw=Math.max(0,e-p.e),d=p.w-nw;p.w=nw;j.tot-=d;for(const q of j.pz)if(q!==p&&q.e>p.e)q.e-=d}
function pzLen(j){return (j.pz||[]).reduce((a,p)=>a+p.w,0)}

/* ---------- reroute a road/rail trip from where it stands ---------- */
function incDetour(j,st,toPid){if(j.mode!=="road"&&j.mode!=="rail")return false;const bits=j.mode==="rail"?BOARD.rbits:BOARD.bits;
  const pos=coPosAt(j,st.s),lo=pos[2],vx=j.p[lo*2],vz=j.p[lo*2+1],path=boardPath(nodeAt(vx,vz),PL[toPid].node,bits);if(!path)return false;
  const pts=[pos[0],pos[1],vx,vz];for(let i=2;i<path.length;i+=2)pts.push(path[i],path[i+1]);
  let wl=0;for(let i=2;i<pts.length;i+=2)wl+=Math.hypot(pts[i]-pts[i-2],pts[i+1]-pts[i-1]);const T=VT[j.t],len=wl*CO_DU,tm=len/(T.spd*spdK());
  Object.assign(j,{p:new Float32Array(pts),lead:0,tl:0,len,tm,cont:true,pz:[],t0:coNow(),cust:0});delete j._c;
  j.stops=bCrossings(j.p,CO_DU).filter(c=>c.s>.03).map(c=>({s:c.s,a:c.a,b:c.b,x:c.x,z:c.z,w:cpWait(c.b,j.mode)}));
  j.tot=tm+(j.ret?0:j.hs+j.stops.reduce((a,q)=>a+q.w,0));CO.winDirty=true;return true}
function incCrossNames(j){const s=new Set();for(const q of j.stops||[]){s.add(q.a);s.add(q.b)}return [...s].map(cnm).join(", ")}
/* cargo goes back to the loading point */
function incReturn(j,st,why,comp){if(!incDetour(j,st,j.k.from))return false;j.back=true;j.comp=comp||0;if(comp){CO.cash+=comp;CO.m.contract+=comp}j.ev.push(why);return true}

/* ---------- daily: roll what can go wrong on each trip ---------- */
function coJobsDay(){
  for(const j of CO.jobs.slice()){
    if(j.hold>0){j.hold--;j.t0++;if(j.hold===0&&j.seized){j.seized=false;toast("good","Судно звільнено",`${VT[j.t].n} продовжує рейс`)}continue}
    const e=G.day-j.t0,st=coJobState(j,e),cg=CARGO_I[j.k.cg];
    if(!j.ret&&!j.back&&!j.cx0&&!j.sch&&!st.inc){const cc=G.C[PL[st.s>j.lead+j.len/2?j.k.to:j.k.from].cid];const k=incRoll(j,st,cc,cg);if(k)j.sch={k,at:G.day+R()*.95}}
    if(e>=j.tot&&CO.jobs.includes(j))coComplete(j);
  }
}
function incRoll(j,st,cc,cg){const m=j.mode,dk=DFK(),mt=[1.4,1,.65][CO.maint],mor=1.35-CO.morale/100,dev=1.4-cc.dev*.6,saf=1-.45*msk("coo"),frg=cg.fr*4+.3;const P=[];
  if(m==="road"){P.push(["acc",.006*dk*Math.sqrt(j.n)*saf*mor*dev*mt],["brk",(.008*j.n*mt)*brkK()],["pdr",.011*mor*saf],["fuel",.004*dev*CO.fuel],["dmg",.005*frg*dev*mt],["cxl",.0025]);
    if(st.seg===1&&!j.lost)P.push(["theft",.0016*dk*(cg.theft||.6)*(bur(cc.id)/40)*(1.6-cc.stability/100)*(inConf(cc.id)?2.5:1)*(1-.65*msk("cso"))*incBandK(j,st)])}
  else if(m==="rail"){P.push(["acc",.0015*dk*saf],["brk",(.004*mt)*brkK()],["dmg",.003*frg],["cxl",.002]);if(st.seg===1&&!j.lost)P.push(["theft",.0006*dk*(cg.theft||.6)*(bur(cc.id)/40)*incBandK(j,st)])}
  else if(m==="sea"){P.push(["brk",(.004*mt)*brkK()],["dmg",.003*frg],["cxl",.0015]);if(st.seg===1&&!j.lost&&CO.pir.some(z=>{const q=coPosAt(j,st.s);return Math.hypot(q[0]-z.x,q[1]-z.z)<z.r}))P.push(["pir",DFK()*.08*(1-.6*msk("cso"))])}
  else if(m==="air")P.push(["brk",(.003*mt)*brkK()],["dmg",.002*frg],["cxl",.0015]);
  P.push(["gps",(m==="air"?.002:.004)*gpsK()]);
  for(const [k,p] of P)if(chance(p))return k;return null}
function incBandK(j,st){const q=coPosAt(j,st.s);return CO.band&&CO.band.some(z=>Math.hypot(q[0]-z.x,q[1]-z.z)<z.r)?5:.6}
function coPauseTo(j,p,d){const e=coNow()-j.t0,nw=Math.max(0,e-p.e)+d,dl=nw-p.w;p.w=nw;j.tot+=dl;for(const q of j.pz)if(q!==p&&q.e>p.e)q.e+=dl;CO.winDirty=true}
function incMark(j,st,k,days){const q=coPosAt(j,st.s);CO.imk.push({x:q[0],z:q[1],k,jid:j.id,until:coNow()+days,t:Date.now()})}

/* ---------- one incident ---------- */
function coIncident(j,type,st){
  const T=VT[j.t],cg=CARGO_I[j.k.cg],A=PL[j.k.from],B=PL[j.k.to],vs=CO.veh.filter(v=>j.vids.includes(v.id));st=st||coJobState(j,coNow()-j.t0);
  const here=coPosAt(j,st.s),cid=Math.max(0,bOwn(here[0],here[1])),pk=priceK(G.C[cid]?cid:G.me),where=G.C[cid]?G.C[cid].name:A.name,rt=`${A.name} → ${B.name}`,val=j.k.tons*cg.val;
  const pay=(c,cat)=>{c=Math.round(c);CO.cash-=c;CO.m[cat||"other"]+=c;return c};
  if(type==="acc"){const sev=chance(.35)?2:1,fault=chance(clamp(.45+.25*(1.35-CO.morale/100)-.2*msk("coo"),.15,.85));
    const d=(sev===2?rnd(.15,.5):rnd(.03,.15))*(cg.fr*6+.4);j.dmg=Math.min(1,j.dmg+d);const v=pick(vs);if(v)v.cond=Math.max(0,v.cond-(sev===2?rnd(30,55):rnd(10,25)));
    const fine=fault?Math.round(rnd(200,900)*pk):0,third=fault?Math.round((sev===2?rnd(12000,60000):rnd(1500,8000))*pk*(cg.dg?2.5:1)):0,dl=sev===2?rnd(1,2.5):rnd(.3,.8),rh=fault?(sev===2?.25:.08):.03;
    const ph=sev===2?"ДТП: на місці аварійні служби":"ДТП: оформлення з поліцією";
    const apply=o=>{let f=fine,t=third*(CO.ins?.3:1),w=dl,r=rh;
      if(o===1){pay(900*pk,"claims");w*=.6;t*=.75}
      pay(f+t,"claims");CO.rating=clamp(CO.rating-r,1,5);coPause(j,w,ph,"acc");
      j.ev.push(`ДТП${fault?" з вини водія":""}: пошкоджено ${(d*100).toFixed(0)}% вантажу, ${fault?`штраф і збитки ${fmtUSD(f+t)}, `:""}затримка ${daysS(w)}`)};
    coNews("bad","alert",`${sev===2?"Серйозна ДТП":"ДТП"} за участі техніки ${CO.name} (${where}): ${T.n.toLowerCase()}, маршрут ${rt}`);
    if(sev===2&&coModalOK()&&j.mode==="road"){coModal({icon:"alert",tone:"bad",eyebrow:"ДТП · "+where,title:fault?"Серйозна аварія з вини вашого водія":"Серйозна аварія на трасі",
      body:`<p>${T.n} з вантажем «${esc(cg.n)}» (${fmtUSD(val)}) зіткнувся з іншим авто. Водій живий. Пошкоджено ≈${(d*100).toFixed(0)}% вантажу, техніку сильно побито.</p>${fault?`<div class="hint">${ic("alert")}<div>Винен ваш водій: штраф ${fmtUSD(fine)} і збитки потерпілим ${fmtUSD(third)}${CO.ins?" (страховка покриє 70%)":""}. Рейтинг −${rh.toFixed(2)}.</div></div>`:`<div class="hint">${ic("info")}<div>Винен інший водій, але рейс стоїть, поки триває оформлення.</div></div>`}`,
      choices:[{t:"Чекати поліцію",d:`Безкоштовно · затримка ≈${daysS(dl)}`,f(){apply(0)}},
        {t:"Викликати аварійних комісарів",d:`${fmtUSD(900*pk)} · швидше на 40%, збитки −25%`,f(){apply(1)}}]})}
    else{apply(0);toast("bad","ДТП на маршруті",`${T.n} · ${rt}`)}}
  if(type==="brk"){const ev={road:300+T.cost*.004,rail:2500+T.cost*.002,sea:15000+T.cost*.002,air:8000+T.cost*.001}[j.mode]*pk*repK(),rep=T.cost*rnd(.004,.012)*repK(),dl={road:rnd(.3,1),rail:rnd(.4,1.2),sea:rnd(1,2.5),air:rnd(.2,.6)}[j.mode];
    const nm={road:"Поломка в дорозі",rail:"Несправність локомотива",sea:"Поломка двигуна судна",air:"Технічна несправність літака"}[j.mode],sv={road:"евакуатор",rail:"резервний тягач",sea:"буксир",air:"технічна бригада"}[j.mode];
    vs.forEach(v=>v.cond=Math.max(0,v.cond-rnd(5,12)));
    const apply=o=>{let w=dl,c=ev+rep,t=`${sv} і ремонт ${fmtUSD(ev+rep)}`;
      if(o===1){if(chance(.55)){c=rep*.3;w=dl*.6;t=`водій полагодив сам: ${fmtUSD(c)}`}else{c=rep*.3+ev+rep;w=dl*1.8;t=`ремонт на місці не вдався, потім ${sv}: ${fmtUSD(c)}`}}
      if(o===2){c=rep*1.6;w=dl*.5;t=`мобільна бригада: ${fmtUSD(c)}`}
      pay(c,"upkeep");coPause(j,w,`${nm}: ${o===0?sv:"ремонт"}`,"brk");j.ev.push(`${nm}: ${t}, затримка ${daysS(w)}`)};
    if(j.mode==="road"&&coModalOK()&&chance(.4)){coModal({icon:"gear",tone:"warn",eyebrow:"Поломка · "+where,title:`${T.n} зламався на трасі`,body:`<p>Рейс ${rt} стоїть на узбіччі. Вантаж «${esc(cg.n)}» цілий, водій чекає рішення диспетчерської.</p>`,
      choices:[{t:"Викликати евакуатор і сервіс",d:`${fmtUSD(ev+rep)} · затримка ≈${daysS(dl)}`,f(){apply(0)}},{t:"Ремонт силами водія",d:`${fmtUSD(rep*.3)} · 55% успіху, інакше довше й дорожче`,f(){apply(1)}},{t:"Мобільна ремонтна бригада",d:`${fmtUSD(rep*1.6)} · удвічі швидше`,f(){apply(2)}}]})}
    else{apply(0);toast("warn",nm,`${T.n} · ${rt} · ${sv}`)}}
  if(type==="pdr"){const V=[["перевищення швидкості",1,0],["перевантаження на вагах",2.2,.2],["порушення режиму праці й відпочинку (тахограф)",1.6,.25],["неправильна стоянка",.6,0],["рух смугою громадського транспорту",.8,0],["несправні фари",.5,.05]];const v=pick(V);
    const f=pay(rnd(60,450)*v[1]*pk,"claims");if(v[2])coPause(j,v[2]*rnd(.5,1.2),`Поліція: ${v[0]}`,"pdr");else coPause(j,rnd(.03,.08),"Зупинка поліцією","pdr");
    j.ev.push(`Штраф ПДР: ${v[0]}, ${fmtUSD(f)}`);coNews("warn","gavel",`Водія ${CO.name} оштрафовано (${where}): ${v[0]}, ${fmtUSD(f)}`)}
  if(type==="fuel"){const c=pay((150+j.k.tons*.4)*CO.fuel*pk*rnd(1.2,2.2),"fuel"),w=rnd(.2,.6),why=pick(["на найближчих АЗС немає пального","водій не розрахував запас пального","паливна картка заблокована"]);
    coPause(j,w,"Нестача пального: чекає на паливозаправник","fuel");j.ev.push(`Нестача пального: ${why}, дозаправка ${fmtUSD(c)}`);toast("warn","Нестача пального",`${T.n} · ${rt} · ${fmtUSD(c)}`)}
  if(type==="dmg"){const d=rnd(.05,.25)*(cg.fr*3+.3)*2,why=pick(j.mode==="road"?["вантаж зсунувся під час різкого гальмування","розбита дорога","протікає тент","порушено температурний режим"]:j.mode==="rail"?["жорстке зчеплення вагонів","порушено температурний режим"]:j.mode==="sea"?["хитавиця: контейнери зсунулися","волога в трюмі"]:["груба обробка в аеропорту"]);
    j.dmg=Math.min(1,j.dmg+d);coPause(j,rnd(.08,.25),"Пошкодження вантажу: перекладання","dmg");j.ev.push(`Пошкоджено ${(d*100).toFixed(0)}% вантажу: ${why}`);
    toast("warn","Пошкодження вантажу",`${cg.n}: ${why} · клієнт виставить претензію`)}
  if(type==="cxl")incCancel(j,st);
  if(type==="theft"){
    const big=val>150000&&coModalOK();j.lost=true;CO.rating=clamp(CO.rating-.12,1,5);j.ev.push(j.mode==="rail"?"Бандити пограбували потяг":"Напад бандитів: вантаж викрадено");coPause(j,rnd(.3,.8),"Напад бандитів: поліція на місці","theft");incMark(j,st,"theft",3);
    coNews("bad","skull",`Викрадено вантаж ${CO.name}: «${cg.n}» на ${fmtUSD(val)} (${where})`);
    if(big)coModal({icon:"skull",tone:"bad",eyebrow:"Безпека · "+where,title:"Вантаж захопили на трасі",body:`<p>Озброєні люди зупинили ${T.n.toLowerCase()} з вантажем «${esc(cg.n)}» вартістю <b>${fmtUSD(val)}</b>. Водії живі, машина порожня.</p>${CO.ins?`<div class="hint">${ic("shield")}<div>Страховка покриє 80% претензії клієнта.</div></div>`:`<div class="hint">${ic("alert")}<div>Страховки немає — частину вартості доведеться компенсувати клієнту самим.</div></div>`}`,
      choices:[{t:"Найняти приватних детективів",d:`${fmtUSD(val*.05+8000)} · шанс повернути вантаж ≈${Math.round((.3+msk("cso")*.4)*100)}%`,f(){pay(val*.05+8000);if(chance(.3+msk("cso")*.4)){j.lost=false;j.ev.push("Вантаж повернули детективи");toast("good","Вантаж знайдено","Рейс продовжується")}else toast("bad","Слід загубився","Вантаж втрачено")}},
        {t:"Заява в поліцію",d:`Безкоштовно · шанс ≈${Math.round((G.C[cid]?G.C[cid].stability:50)/4)}%`,f(){if(chance((G.C[cid]?G.C[cid].stability:50)/400)){j.lost=false;j.ev.push("Поліція повернула вантаж");toast("good","Поліція знайшла вантаж","")}}},
        {t:"Списати",d:"Претензія клієнта після завершення рейсу",f(){}}]});
    else toast("bad","Вантаж викрадено",`${cg.n} · ${fmtUSD(val)}`)}
  if(type==="pir"){j.seized=true;const p=coPause(j,rint(6,12),"Захоплено піратами: переговори про викуп","pir",{end:"free"});incMark(j,st,"pir",0);const ransom=Math.round(val*.08+T.cost*.03);
    coNews("bad","skull",`Пірати захопили судно ${CO.name} з вантажем «${cg.n}»`);toast("bad","Пірати захопили судно",`${T.n} · ${cg.n}`);
    coModal({icon:"skull",tone:"bad",eyebrow:"Піратство",title:"Пірати захопили ваше судно",body:`<p>${T.n} з ${(T.crew||1)*j.n} моряками та вантажем «${esc(cg.n)}» (${fmtUSD(val)}) у руках піратів. Судно відвели з курсу, пірати вимагають викуп.</p>`,
      choices:[{t:`Заплатити викуп ${fmtUSD(ransom)}`,d:"Звільнення за тиждень",f(){pay(ransom);coPauseTo(j,p,7);p.ph="Захоплено піратами: викуп сплачено, чекаємо звільнення";j.ev.push("Сплачено викуп")}},
        {t:"Чекати на військовий флот",d:`Шанс ≈${Math.round((.35+msk("cso")*.3)*100)}% звільнення · інакше втрата вантажу і пошкодження судна`,f(){if(chance(.35+msk("cso")*.3)){coPauseTo(j,p,4);p.ph="Військовий флот звільняє судно";toast("good","Флот звільнив судно","Екіпаж цілий")}else{j.lost=true;coPauseTo(j,p,18);vsDamage(vs,40);CO.rating=clamp(CO.rating-.15,1,5);j.ev.push("Штурм провалився: вантаж втрачено")}}},
        {t:"Відмовитися від вантажу",d:"Пірати заберуть вантаж і відпустять судно за 20 днів",f(){j.lost=true;coPauseTo(j,p,20);CO.rating=clamp(CO.rating-.12,1,5)}}]})}
  if(type==="gps"){j.gps={until:coNow()+rnd(.6,2)};const nm=j.mode==="sea"?"AIS-транспондера":"GPS-навігації";j.ev.push(`Збій ${nm}: техніка зникла з карти`);
    if(j.mode==="road"&&chance(.45)){coPause(j,rnd(.08,.25),"Збій GPS: водій заблукав і повертається на маршрут","gps");j.ev.push("Водій заблукав без навігації")}
    coNews("warn","target",`Збій ${nm}: ${T.n.toLowerCase()} ${CO.name} зникає з радарів (${where})`);toast("warn","Збій "+(j.mode==="sea"?"AIS":"GPS"),`${T.n} · ${rt} · сигнал пропадає`)}
  CO.winDirty=true;
}

/* customer cancels: before loading the truck just stops at the loading point; after loading — a long wait, then maybe back to the sender */
function incCancel(j,st){const A=PL[j.k.from],B=PL[j.k.to],cg=CARGO_I[j.k.cg],T=VT[j.t];
  if(st.seg===0&&!j.cont){const fee=Math.round(j.k.pay*rnd(.1,.2));CO.cash+=fee;CO.m.contract+=fee;j.cx0=true;j.tot=j.tl+segW(j,0,j.lead)+pzLen(j);
    j.ev.push(`Замовник скасував рейс до завантаження: компенсація ${fmtUSD(fee)}`);coNews("warn","doc",`Замовник скасував рейс ${CO.name} ${A.name} → ${B.name}`);toast("warn","Замовник скасував рейс",`${A.name} → ${B.name} · компенсація ${fmtUSD(fee)}`);return}
  coPause(j,rnd(1,2.5),"Замовник призупинив рейс: чекаємо рішення","cxw",{end:"cxl"});j.ev.push("Замовник призупинив рейс");
  toast("warn","Замовник призупинив рейс",`${cg.n} · ${A.name} → ${B.name}`)}
function incCancelEnd(j){const A=PL[j.k.from],B=PL[j.k.to],cg=CARGO_I[j.k.cg],st=coJobState(j,coNow()-j.t0);
  if(chance(.5)){j.ev.push("Замовник підтвердив рейс");toast("good","Рейс продовжено","Замовник підтвердив доставку");return}
  const comp=Math.round(j.k.pay*.35),road=j.mode==="road"||j.mode==="rail";
  const doBack=()=>{if(road&&incReturn(j,st,`Замовник скасував рейс: вантаж повертається в ${A.name}, компенсація ${fmtUSD(comp)}`,comp)){toast("warn","Рейс скасовано",`Вантаж повертається в ${A.name} · компенсація ${fmtUSD(comp)}`);coNews("warn","doc",`Замовник скасував рейс ${CO.name}: «${cg.n}» повертається в ${A.name}`)}
    else{j.payK=.4;j.ev.push("Замовник скасував рейс: вантаж залишать на складі в пункті призначення, оплата 40%");toast("warn","Рейс скасовано","Вантаж здадуть на склад, оплата 40%")}};
  if(coModalOK()&&j.k.pay>3000){coModal({icon:"doc",tone:"warn",eyebrow:"Замовник · "+B.name,title:"Замовник відмовився від вантажу",body:`<p>${esc(j.k.ft||"Отримувач")} (${esc(B.name)}) не прийматиме «${esc(cg.n)}». ${road?`Вантаж доведеться везти назад у ${esc(A.name)}.`:"Вантаж можна здати на склад у пункті призначення."} За договором замовник платить штраф за скасування.</p>`,
    choices:[{t:road?"Повернути вантаж відправнику":"Здати вантаж на склад",d:road?`Компенсація ${fmtUSD(comp)} · техніка зайнята дорогою назад`:"Оплата 40% рейсу",f:doBack},
      ...(CO.mgr.clo?[{t:"Подати претензію через юриста",d:`Шанс ≈${Math.round((.45+msk("clo")*.4)*100)}% отримати 80% оплати · судові витрати ${fmtUSD(Math.round(j.k.pay*.08+500))}`,f(){CO.cash-=Math.round(j.k.pay*.08+500);CO.m.other+=Math.round(j.k.pay*.08+500);if(chance(.45+msk("clo")*.4)){const x=Math.round(j.k.pay*.8);CO.cash+=x;CO.m.contract+=x;toast("good","Претензію задоволено",fmtUSD(x));j.payK=0;j.ev.push(`Суд: замовник сплатив ${fmtUSD(x)}`);if(road)incReturn(j,st,"Вантаж повертається відправнику",0)}else doBack()}}]:[])]})}
  else doBack()}

/* ---------- border checkpoint: queue, papers, inspection (sped up by the lawyer & customs broker); closed border → detour or back ---------- */
function cpArrive(j,q,st){const a=q.a,b=q.b,x=q.x??coPosAt(j,st.s)[0],z=q.z??coPosAt(j,st.s)[1],cl=incCrossCl(a,b,x,z);
  if(cl){incBorderHit(j,q,st,cl);return}
  if(j.ret)return;const C=G.C[b],cg=CARGO_I[j.k.cg];if(!chance(.24*(.5+bur(b)/60)*(1-.5*msk("clo"))))return;
  const K=pick(["queue","queue","docs","insp"]),ttl={queue:"Велика черга на кордоні",docs:"Помилка в документах",insp:"Поглиблений митний огляд"}[K];
  const w0={queue:rnd(.3,1.2),docs:rnd(.5,1.8),insp:rnd(.3,1.2)}[K]*(1+bur(b)/100);
  const ph={queue:"Черга на кордоні",docs:"Виправлення документів",insp:"Митний огляд"}[K]+` · ${C.name}`,M=CO.mgr.clo;
  if(M){const f=clamp(.55-.35*msk("clo"),.15,.55);coPause(j,w0*f,ph,"cus");j.ev.push(`${ttl} (${C.name}): юрист і митний брокер${M.name?" "+M.name:""} — оформлення пришвидшено, затримка ${daysS(w0*f)}`);
    toast("",ttl,`${C.name} · оформлення пришвидшено юристом і митним брокером: ${daysS(w0*f)} замість ${daysS(w0)}`);return}
  coPause(j,w0,ph,"cus");j.ev.push(`${ttl} (${C.name}): затримка ${daysS(w0)}`);
  if(K==="insp"&&chance(.25)){j.dmg=Math.min(1,j.dmg+rnd(.02,.06));j.ev.push("Під час огляду пошкоджено упаковку")}
  toast("warn",ttl,`${C.name} · ${VT[j.t].n} · ≈${daysS(w0)}. Пришвидшити митницю може юрист і митний брокер (вікно «Персонал»)`)}
function incBorderHit(j,q,st,cl){const to=j.ret||j.back?(j.back?j.k.from:j.k.to):j.k.to,left=cl.until-coNow(),why=cl.why,nm=cl.kind==="cty"?`${cnm(cl.a)} закрила кордони`:cl.kind==="pair"?`Кордон ${cnm(cl.a)} — ${cnm(cl.b)} закрито`:`Пункт пропуску ${cnm(q.a)} → ${cnm(q.b)} закрито`;
  const save=JSON.stringify([j.p.length,j.len]);
  if(incDetour(j,coJobState(j,coNow()-j.t0),to)){const via=incCrossNames(j);j.ev.push(`${nm}: об'їзд${via?" через "+via:""}`);toast("warn",nm,`${VT[j.t].n}: об'їзд${via?" через "+via:""}`);return}
  if(left<4){coPause(j,left+.02,`${nm}: чекає відкриття`,"cl");q.h=0;j.ev.push(`${nm} (${why.toLowerCase()}): чекаємо відкриття`);toast("warn",nm,`${VT[j.t].n} чекає на кордоні ≈${daysS(left)}`);return}
  if(!j.ret&&!j.back&&incReturn(j,coJobState(j,coNow()-j.t0),`${nm} (${why.toLowerCase()}): вантаж повертається відправнику`,Math.round(j.k.pay*.25))){toast("bad",nm,`Об'їзду немає: вантаж повертається в ${PL[j.k.from].name}`);return}
  coPause(j,1,`${nm}: чекає відкриття`,"cl");q.h=0}

/* ---------- per frame: fire scheduled incidents, checkpoints, weather and traffic ---------- */
let INC_F=0;
function incFrame(T){if(!G.board||!CO.jobs)return;incInit();if(BLK_V!==CO.clV||BLK_W!==G.world)incBlk();
  const dt=clamp(T-(CO.incT??T),0,1);CO.incT=T;if(dt>0){incWorld(T,dt);incJams(T,dt)}else if(!JAM.length)incJams(T,0)
  if((INC_F++)%2)return;
  J:for(const j of CO.jobs.slice()){if(j.hold>0)continue;const e=T-j.t0;let st=coJobState(j,e);
    // a pause that waits for a decision
    if(j.pz)for(const p of j.pz)if(p.end&&!p.done&&e>=p.e+p.w){p.done=1;if(p.end==="cxl")incCancelEnd(j);if(p.end==="free"){j.seized=false;toast("good","Судно звільнено",`${VT[j.t].n} продовжує рейс`)}}
    if(j.gps&&T>=j.gps.until){delete j.gps;j.ev.push("Сигнал GPS відновлено")}
    if(!CO.jobs.includes(j))continue;
    if(j.sch&&T>=j.sch.at){const k=j.sch.k;j.sch=null;if(!st.inc&&(st.seg>=0||k==="cxl"))coIncident(j,k,st);continue}
    if(st.inc)continue;
    if(st.w&&!st.w.h){st.w.h=1;cpArrive(j,st.w,st);continue}
    if(j.mode==="air")incSkyCheck(j,st);
    const pos=coPosAt(j,st.s);
    // weather: vehicles inside a storm stop; planes only on the ground; ships wait at anchor near a closed port
    if(!(T<(j.wxCool||0)))for(const w of CO.wx){const K=WXK[w.k];if(!K[j.mode]||j.wxd===w.id||w.t0>T)continue;if(j.mode==="air"&&st.seg>=0)continue;
      if(Math.hypot(pos[0]-w.x,pos[1]-w.z)<w.r){j.wxd=w.id;const d=Math.max(.05,w.until-T);j.wxCool=w.until+.5;coPause(j,d,`${w.n}: ${{road:"дорогу перекрито",rail:"рух поїздів зупинено",sea:"судно перечікує в укритті",air:"вильоти скасовано"}[j.mode]}`,"wx");continue J}}
    if(st.seg>=0)for(const w of CO.wx){const K=WXK[w.k];if(!K.slow||!K.slow[j.mode]||w.t0>T||(j.drag||[]).some(d=>d.w===w.id))continue;if(Math.hypot(pos[0]-w.x,pos[1]-w.z)<w.r){const f=K.slow[j.mode],Lc=w.r*1.6*(j.p.length>4?(j.lead+j.len)/Math.max(1e-6,(()=>{let L=0;for(let i=2;i<j.p.length;i+=2)L+=Math.hypot(j.p[i]-j.p[i-2],j.p[i+1]-j.p[i-1]);return L})()):CO_DU),sp=VT[j.t].spd*spdK(),e0=T-j.t0,d=Lc/(sp*f);
        (j.drag=j.drag||[]).push({w:w.id,e0,e1:e0+d,f,ph:`${w.n}: рух сповільнено`});j.tot+=d*(1-f);j.ev.push(`${w.n}: рух сповільнено`)}} /* slowed, not stopped */
    if((j.mode==="sea"||j.mode==="air")&&st.seg===1&&st.f>.88&&!(T<(j.wxCool||0))){const u=incPortUntil(PL[j.k.to],j.mode);if(u){const d=clamp(u.until-T,.05,3);j.wxCool=T+d+.5;coPause(j,d,`${j.mode==="sea"?"Порт":"Аеропорт"} закрито (${u.why.toLowerCase()}): ${j.mode==="sea"?"очікування на рейді":"зона очікування"}`,"wx");continue}}
    // traffic jam: stop-and-go at each congested node
    if(j.mode==="road"&&st.seg>=0){const lp=j.jp||pos,eN=T-j.t0,eP=j.je!=null?j.je:eN;j.jp=[pos[0],pos[1]];j.je=eN;if(JAM.length){const J=jamOn(lp[0],lp[1],pos[0],pos[1]);if(J&&j.jn!==J.id){j.jn=J.id;
      const dx=pos[0]-lp[0],dz=pos[1]-lp[1],L2=dx*dx+dz*dz,t=L2>0?clamp(((J.x-lp[0])*dx+(J.z-lp[1])*dz)/L2,0,1):1; /* back to the jam point itself */
      const K=RCK_I[J.kind]||RCK[0],pz=coPause(j,Math.max(.05,J.until-T),`${K.n}: дорогу перекрито, чекає відкриття`,"jam");toast("warn",K.n,`${VT[j.t].n} стоїть перед перекриттям ≈${daysS(Math.max(.05,J.until-T))}`);if(pz)pz.e=Math.max(0,pz.e-(1-t)*Math.max(0,eN-eP))}}}else{j.jp=null;j.je=null}
  }}

/* ---------- world: closures and weather appear and fade ---------- */
function incWorld(T,dt){let ch=false;incZones(T,dt);CO.imk=CO.imk.filter(m=>m.k==="pir"?CO.jobs.some(j=>j.id===m.jid&&j.seized):m.until>T);
  // expire
  for(const c of CO.cls.slice())if(c.until<=T){CO.cls=CO.cls.filter(x=>x!==c);ch=true;coNews("good","handshake",c.kind==="cty"?`${cnm(c.a)} знову відкрила кордони`:c.kind==="pair"?`Кордон ${cnm(c.a)} — ${cnm(c.b)} знову відкрито`:`Пункт пропуску ${cnm(c.a)} → ${cnm(c.b)} знову працює`);if(c.kind==="cty")applyMapColors()}
  for(const w of CO.wx.slice())if(w.until<=T){CO.wx=CO.wx.filter(x=>x!==w);ch=true;if(w.mine)coNews("good","sun",`Негода в районі ${w.near} минула: рух відновлено`)}
  // war conflicts close the border between the two states
  for(const f of CO.conf||[])if(f.until>T&&!CO.cls.some(c=>c.conf&&c.a===f.a&&c.b===f.b)){CO.cls.push({id:CO.uid++,kind:"pair",a:f.a,b:f.b,why:"Воєнний конфлікт",until:f.until,conf:1});ch=true}
  const cps=(BOARD.cps||[]).filter(c=>!c.rail),near=p=>CO.hubs.some(h=>Math.hypot(PL[h.pid].x-p.x,PL[h.pid].z-p.z)<4);
  const scopedF=()=>G.C.filter(c=>c.id!==hqP().cid&&PL.some(p=>p.cid===c.id&&coScope(p)));
  const n=k=>CO.cls.filter(c=>c.kind===k&&!c.conf).length;
  if(CO.tier>=1&&n("cp")<4&&cps.length&&chance(.05*dt)){const c=pick(cps.filter(c=>near(c)).concat(cps.slice(0,3)));if(c&&!CO.cls.some(x=>x.kind==="cp"&&Math.hypot(x.x-c.x,x.z-c.z)<.3)){
    const cl={id:CO.uid++,kind:"cp",a:c.a,b:c.b,x:c.x,z:c.z,why:pick(CL_WHY.cp),until:T+rnd(2,9)};CO.cls.push(cl);ch=true;incTell(cl)}}
  if(CO.tier>=2&&n("pair")<2&&chance(.006*dt)){const scoped=scopedF(),a=pick(scoped.length?scoped:G.C),nb=(a.geo&&a.geo.neighbors||[]).filter(i=>G.C[i]&&i!==hqP().cid);if(nb.length){const b=pick(nb);if(!CO.cls.some(c=>c.kind==="pair"&&(c.a===a.id&&c.b===b||c.a===b&&c.b===a.id))){
    const cl={id:CO.uid++,kind:"pair",a:a.id,b,why:pick(CL_WHY.pair),until:T+rnd(12,45)};CO.cls.push(cl);ch=true;incTell(cl)}}}
  let scoped;if(CO.tier>=2&&n("cty")<1&&chance(.004*dt)&&(scoped=scopedF()).length){const a=pick(scoped);const cl={id:CO.uid++,kind:"cty",a:a.id,why:pick(CL_WHY.cty),until:T+rnd(8,35)};CO.cls.push(cl);ch=true;incTell(cl);applyMapColors()}
  // weather
  if(CO.wx.length<3&&chance(.4*dt)){const k=pick(wxSeason()),K=WXK[k];
    let base=null;const ports=PL.filter(p=>p.port!=null);if(k==="storm"&&ports.length)base=pick(chance(.6)?ports.filter(p=>near(p)).concat(ports.slice(0,2)):ports);
    if(!base){const hubP=CO.hubs.map(h=>PL[h.pid]);base=chance(.6)&&hubP.length?pick(PL.filter(p=>hubP.some(h=>Math.hypot(h.x-p.x,h.z-p.z)<3))):pick(PL)}
    if(base){const r={snow:rnd(.35,.8),storm:rnd(.5,1),hur:rnd(.6,1.1),fog:rnd(.25,.55),flood:rnd(.22,.45),hsnow:rnd(.4,.8),ice:rnd(.35,.7),rain:rnd(.3,.65),tstorm:rnd(.35,.7)}[k],x=base.x+rnd(-.4,.4),z=base.z+rnd(-.4,.4);
      const mine=CO.hubs.some(h=>Math.hypot(PL[h.pid].x-x,PL[h.pid].z-z)<r+.6)||CO.jobs.some(j=>{const q=coPosAt(j,coJobState(j,T-j.t0).s);return Math.hypot(q[0]-x,q[1]-z)<r+.3});
      const t0=T+rnd(.8,2.5),w={id:CO.uid++,k,n:K.n,x,z,r,t0,until:t0+(k==="hur"?rnd(1.5,3.5):rnd(.4,2.5)),near:base.name,mine};CO.wx.push(w);ch=true;
      const cl=wxCl(K);
      if(mine){coNews("warn",K.ic,`Прогноз: ${K.n.toLowerCase()} в районі ${base.name} з ${dayDate(t0)} — ${cl}`);toast("warn",`Прогноз: ${K.n} · район ${base.name}`,`Через ${daysS(t0-T)}: ${cl}`)}}}
  for(const w of CO.wx)if(!w.on&&!(w.t0>T)){w.on=1;ch=true;if(w.mine){const K=WXK[w.k],cl=wxCl(K);coNews("warn",K.ic,`${K.n} в районі ${w.near}: ${cl}`);toast("warn",`${K.n} · район ${w.near}`,cl)}}
  if(ch){incChanged();incBlk();CO.winDirty=true}}
function incZones(T,dt){const shaky=()=>G.C.filter(c=>PL.some(p=>p.cid===c.id)).sort((a,b)=>(a.stability-bur(a.id))-(b.stability-bur(b.id)));
  // pirates: water near ports of the shakiest coastal states
  if(!CO.pirB){CO.pirB=1;if(!CO.pir.length){const S=shaky().filter(c=>PL.some(p=>p.cid===c.id&&p.port!=null)).slice(0,6);for(let i=0;i<3&&S.length;i++){const c=S.splice(Math.floor(Math.random()*S.length),1)[0];const pts=PL.filter(p=>p.cid===c.id&&p.port!=null);const t=BOARD.towns&&BOARD.towns[pick(pts).id];if(!t||!t.wc)continue;
      CO.pir.push({id:CO.uid++,x:-WX/2+(t.wc[0]+.5)*CBL.st+rnd(-.25,.25),z:-WZ/2+(t.wc[1]+.5)*CBL.st+rnd(-.25,.25),r:rnd(.5,.85),cid:c.id,name:"води біля "+c.name})}}}
  // bandits: stretches of road in unstable states, they move around every few weeks
  const bef=CO.band.length;CO.band=CO.band.filter(z=>z.until>T);
  if(CO.band.length<3&&(CO.band.length<bef||!bef&&!CO.bandI||chance(.05*dt))){CO.bandI=1;const S=shaky().slice(0,8);const c=pick(S);if(c){const ps=PL.filter(p=>p.cid===c.id&&p.type!=="cap");if(ps.length){const p=pick(ps);
    CO.band.push({id:CO.uid++,x:p.x+rnd(-.3,.3),z:p.z+rnd(-.3,.3),r:rnd(.35,.7),cid:c.id,until:T+rnd(30,90),name:c.name});if(CO.hubs.some(h=>Math.hypot(PL[h.pid].x-p.x,PL[h.pid].z-p.z)<4))coNews("warn","skull",`Поліція ${c.name} попереджає: на дорогах біля ${p.name} діє банда`)}}}}
function incTell(cl){const t=cl.kind==="cty"?`${cnm(cl.a)} закрила кордони`:cl.kind==="pair"?`Кордон ${cnm(cl.a)} — ${cnm(cl.b)} закрито`:`Пункт пропуску ${cnm(cl.a)} → ${cnm(cl.b)} закрито`;
  coNews("bad",cl.kind==="cp"?"lock":"swords",`${t}: ${cl.why.toLowerCase()}`);toast("bad",t,`${cl.why} · ≈${Math.round(cl.until-coNow())} дн.`)}
function incDay(){}

/* ---------- road closures: a point on a road shut for 2–3 days (repairs, crashes, landslides…); a vehicle reaching it waits for the reopening ---------- */
const RCK=[{k:"repair",n:"Ремонт дороги",ic:"gear",sev:1,w:4,d:"Дорожні роботи: рух перекрито в обидва боки."},{k:"crash",n:"Масштабна ДТП",ic:"alert",sev:2,w:3,d:"Кілька фур зіткнулися — трасу перекрито до прибирання."},
 {k:"slide",n:"Зсув ґрунту",ic:"ore",sev:2,w:1.2,d:"Схил сповз на дорогу: розчищення техніка займе дні."},{k:"flood",n:"Підтоплення",ic:"wave",sev:1,w:1.5,d:"Вода піднялася вище полотна, проїзд закрито."},
 {k:"bridge",n:"Аварійний міст",ic:"alert",sev:2,w:1,d:"Міст закрили після огляду: тріщини в опорах."},{k:"spill",n:"Розлив небезпечного вантажу",ic:"barrel",sev:2,w:.8,d:"Цистерна перекинулася: працюють рятувальники."},
 {k:"protest",n:"Перекриття: акція протесту",ic:"users",sev:1,w:1.2,d:"Учасники акції перекрили трасу."}];
const RCK_I={};RCK.forEach(r=>RCK_I[r.k]=r);
let JAM_HIT=[];const JAM_R=()=>BL.st*.55; // a vehicle passing closer than this to the point is stopped by the closure
const rcTarget=()=>clamp(Math.round(PL.filter(p=>p.type==="cap"||p.type==="big"||p.type==="city").length*.9),10,80);
function incJams(T,dt){if(!BOARD.bits)return;let ch=false;
  const before=JAM.length;JAM=JAM.filter(J=>J.until>T);if(JAM.length!==before)ch=true;
  const D=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]],bits=BOARD.bits;
  const put=(n0,steps)=>{let n=n0;steps=Math.round(steps*CST/BL.st);for(let s=0;s<steps;s++){const o=[];for(let d=0;d<8;d++)if(bits[n]&(1<<d))o.push((((n/BL.nx)|0)+D[d][1])*BL.nx+n%BL.nx+D[d][0]);if(!o.length)break;n=o[Math.floor(Math.random()*o.length)]}
    if(!bits[n]||JAMN.has(n)||JAM.some(J=>Math.hypot(J.x-bXY(n)[0],J.z-bXY(n)[1])<CST*.6))return;let tw=0;for(const r of RCK)tw+=r.w;let r_=Math.random()*tw,K=RCK[0];for(const r of RCK){r_-=r.w;if(r_<=0){K=r;break}}
    const [x,z]=bXY(n);if(PL.some(p=>Math.hypot(p.x-x,p.z-z)<JAM_R()*1.6+(typeof coRad==="function"?coRad(p):0)))return; // never inside a city: it always has other ways in
    const t0=K.k==="repair"?T+rnd(2,5):T;JAM.push({id:CO.uid++,n,x,z,sev:K.sev,kind:K.k,t0,until:t0+rnd(2,3),on:t0<=T?1:0});if(t0<=T)JAMN.set(n,K.sev);ch=true};
  const src=PL.filter(p=>p.node!=null&&p.type!=="vil"),tgt=rcTarget();
  const spawn=()=>{const p=pick(src);if(p)put(p.node,rnd(.6,3.5))};
  if(!JAM.length){for(let i=0;i<tgt*3&&JAM.length<tgt;i++){spawn();const J=JAM[JAM.length-1];if(J&&J.t0===T)J.until=T+rnd(.4,3);else if(J&&chance(.5)){J.t0=T-rnd(0,1.5);J.until=T+rnd(.4,3);J.on=1}}} // the world starts with closures already in place, at different stages
  else if(JAM.length<tgt&&Math.random()<dt*tgt/2.5)spawn();
  for(const J of JAM)if(!J.on&&J.t0<=T){J.on=1;ch=true}
  if(ch){JAMN=new Map();for(const J of JAM)if(J.on)JAMN.set(J.n,Math.max(JAMN.get(J.n)||0,J.sev))}}
/* the jam a vehicle drove into between two positions (segment test: fast vehicles do not skip it) */
function jamOn(x0,z0,x1,z1){if(!JAM.length)return null;const R=JAM_R(),dx=x1-x0,dz=z1-z0,L2=dx*dx+dz*dz,now=coNow();
  for(const J of JAM){if(J.t0>now)continue;const t=L2>0?clamp(((J.x-x0)*dx+(J.z-z0)*dz)/L2,0,1):0;if(Math.hypot(x0+dx*t-J.x,z0+dz*t-J.z)<R)return J}return null}

/* ---------- drawing ---------- */
function incP(dpr){return (x,z)=>{const p=project(x,0,z);return p?[p.x*dpr,p.y*dpr]:null}}
function incBorderPts(cl){const L=G.world&&G.world.lines;if(!L)return [];if(cl._ln&&cl._lw===G.world)return cl._ln;const out=[];
  for(const l of L){if(!l.a||!l.b)continue;const a=l.a-1,b=l.b-1;let ok=false;if(cl.kind==="cty")ok=a===cl.a||b===cl.a;else ok=a===cl.a&&b===cl.b||a===cl.b&&b===cl.a;if(!ok)continue;
    if(cl.kind!=="cp"){out.push(l.p);continue}
    let cur=[];for(let i=0;i<l.p.length;i+=2){const x=l.p[i],z=l.p[i+1];if(Math.hypot(x-cl.x,z-cl.z)<.42)cur.push(x,z);else if(cur.length){if(cur.length>=4)out.push(cur);cur=[]}}if(cur.length>=4)out.push(cur)}
  Object.defineProperty(cl,"_ln",{value:out,enumerable:false,writable:true,configurable:true});Object.defineProperty(cl,"_lw",{value:G.world,enumerable:false,writable:true,configurable:true});return out}
function drawIncBase(g,dpr){if(!G.co||!G.board||!CO.cls)return;const P=incP(dpr),W=g.canvas.width,H=g.canvas.height,zw=clamp(13/Cam.dist,1,3.2),t=performance.now()/1000;
  // pirate and bandit zones
  const zone=(z,col,lbl)=>{const pts=[];for(let i=0;i<=36;i++){const a=i/36*Math.PI*2,q=P(z.x+Math.cos(a)*z.r,z.z+Math.sin(a)*z.r);if(q)pts.push(q)}if(pts.length<10)return;
    g.beginPath();pts.forEach((q,i)=>i?g.lineTo(...q):g.moveTo(...q));g.closePath();g.fillStyle=`rgba(${col},.1)`;g.fill();g.strokeStyle=`rgba(${col},.75)`;g.lineWidth=1.5*dpr;g.stroke();
    const c=P(z.x,z.z);if(c&&Cam.dist<26){const R=10*dpr;g.fillStyle="rgba(8,18,28,.9)";g.strokeStyle=`rgb(${col})`;g.lineWidth=1.4*dpr;g.beginPath();g.arc(c[0],c[1],R,0,7);g.fill();g.stroke();
      drawIcons(g,["skull"],c[0]-R*.62,c[1],R*1.24,`rgb(${col})`)}};
  if(vis("pir"))for(const z of CO.pir||[])zone(z,"240,98,95","");
  if(vis("band"))for(const z of CO.band||[])zone(z,"255,140,60","");
  // weather zones
  if(vis("wx"))for(const w of CO.wx){const K=WXK[w.k],pts=[];for(let i=0;i<=40;i++){const a=i/40*Math.PI*2,q=P(w.x+Math.cos(a)*w.r,w.z+Math.sin(a)*w.r);if(q)pts.push(q)}if(pts.length<10)continue;
    g.save();g.beginPath();pts.forEach((q,i)=>i?g.lineTo(...q):g.moveTo(...q));g.closePath();g.fillStyle=`rgba(${K.col},.17)`;g.fill();g.clip();
    let x0=1e9,x1=-1e9,y0=1e9,y1=-1e9;for(const q of pts){x0=Math.min(x0,q[0]);x1=Math.max(x1,q[0]);y0=Math.min(y0,q[1]);y1=Math.max(y1,q[1])}
    const sp=14*dpr,off=0;g.strokeStyle=`rgba(${K.col},.3)`;g.lineWidth=1.3*dpr;g.beginPath();for(let x=x0-(y1-y0)-sp+off;x<x1;x+=sp){g.moveTo(x,y1);g.lineTo(x+(y1-y0),y0)}g.stroke();g.restore();
    g.strokeStyle=`rgba(${K.col},.95)`;g.lineWidth=1.8*dpr;g.beginPath();pts.forEach((q,i)=>i?g.lineTo(...q):g.moveTo(...q));g.closePath();g.stroke();
    const c=P(w.x,w.z);if(c&&Cam.dist<26){const R=10*dpr,pl=w.t0>coNow(),col=pl?"150,160,172":K.col;g.fillStyle="rgba(8,18,28,.9)";g.strokeStyle=`rgb(${col})`;g.lineWidth=1.4*dpr;g.beginPath();g.arc(c[0],c[1],R,0,7);g.fill();g.stroke();
      drawIcons(g,[K.ic],c[0]-R*.62,c[1],R*1.24,`rgb(${col})`)}}
  // traffic jams
  JAM_HIT=[];if(vis("jam")&&JAM.length&&Cam.dist<26&&(UI.mode==="co"||UI.mode==="grid")){const vb=vbox(),r=clamp(9/Math.sqrt(Cam.dist),2.2,5)*dpr,T_=coNow();
    for(const J of JAM){if(vb&&(J.x<vb.x0||J.x>vb.x1||J.z<vb.z0||J.z>vb.z1))continue;const q=P(J.x,J.z);if(!q||q[0]<-20||q[1]<-20||q[0]>W+20||q[1]>H+20)continue;const pl=J.t0>T_,col=pl?"150,160,172":J.sev>1?"240,68,60":"255,138,42",f=pl?.3:.5+.5*Math.sin(t*4+J.id);
      g.fillStyle=`rgba(${col},${(.18+.14*f).toFixed(2)})`;g.beginPath();g.arc(q[0],q[1],r*(1.9+.4*f),0,7);g.fill();
      g.fillStyle=`rgb(${col})`;g.strokeStyle="#0b1520";g.lineWidth=1.2*dpr;g.beginPath();g.arc(q[0],q[1],r,0,7);g.fill();g.stroke();
      {const K=RCK_I[J.kind]||RCK[0];JAM_HIT.push({x:q[0]/dpr,y:q[1]/dpr,r:r/dpr+5,html:`<div class="row" style="gap:8px"><span class="${pl?"mut":J.sev>1?"bad":"warn"}">${ic(K.ic)}</span><b>${J.kind==="repair"?"Плановий ремонт дороги":K.n}</b></div>${pl?"":`<div class="note" style="margin-top:4px">${K.d}</div>`}<div class="note" style="margin-top:4px">${pl?`<b>Заплановано:</b> з ${dayDate(J.t0)} до ${dayDate(J.until)} (почнеться через ${daysS(J.t0-T_)}). Поки що рух вільний.`:`Дорогу перекрито${J.kind==="repair"?` до ${dayDate(J.until)}`:""} · відкриють через ${daysS(Math.max(0,J.until-T_))}. Техніка стоятиме тут до відкриття — прокладіть маршрут в об'їзд.`}</div>`})}}}
  // closed borders
  if(vis("clb")&&CO.cls.length){const a=.65+.35*Math.sin(t*3);for(const cl of CO.cls){if(cl.kind==="cp")continue; /* a single closed checkpoint: only its square turns red */const L=incBorderPts(cl);if(!L.length)continue;const vb=vbox();g.beginPath();for(const p of L){if(vb&&!inVB(p,p,vb))continue;let pen=false;for(let i=0;i<p.length;i+=2){const q=P(p[i],p[i+1]);if(!q||q[0]<-40*W||q[0]>41*W||q[1]<-40*H||q[1]>41*H){pen=false;continue}if(pen)g.lineTo(...q);else{g.moveTo(...q);pen=true}}}
    g.lineCap="round";g.lineJoin="round";g.strokeStyle="#f0443c";g.lineWidth=1.25*zw*dpr;g.stroke()}}}
/* red-and-white diagonal hatching like barrier tape: tells closed borders apart from traffic jams */
let INC_HP=null;function incHatch(g,dpr){if(INC_HP&&INC_HP.d===dpr)return INC_HP.p;const s=Math.round(8*dpr),c=document.createElement("canvas");c.width=c.height=s;const x=c.getContext("2d");
  const im=x.createImageData(s,s);for(let yy=0;yy<s;yy++)for(let xx=0;xx<s;xx++){const red=((xx+yy)%s)<s/2,i=(yy*s+xx)*4;im.data[i]=red?240:255;im.data[i+1]=red?68:255;im.data[i+2]=red?60:255;im.data[i+3]=255}x.putImageData(im,0,0);
  INC_HP={d:dpr,p:g.createPattern(c,"repeat")};return INC_HP.p}
function drawIncTop(g,dpr){if(!G.co||!G.board||!CO.cls)return;const P=incP(dpr),sz=clamp(13/Cam.dist,.9,1.6);
  if(vis("sky")&&SKY.size){const L=G.world.lines||[],t=performance.now()/1000;g.save();g.setLineDash([7*dpr,6*dpr]);g.lineDashOffset=-t*14*dpr;g.beginPath();
    for(const l of L){const a=l.a-1,b=l.b-1;if(!(SKY.has(a)||SKY.has(b)))continue;let pen=false;for(let i=0;i<l.p.length;i+=2){const q=P(l.p[i],l.p[i+1]);if(!q){pen=false;continue}if(pen)g.lineTo(...q);else{g.moveTo(...q);pen=true}}}
    g.strokeStyle="rgba(214,150,255,.95)";g.lineWidth=2*dpr;g.stroke();g.restore();REDRAW=true;
    for(const cid of SKY){const ps=PL.filter(p=>p.cid===cid);if(!ps.length)continue;const cap=ps.find(p=>p.type==="cap")||ps[0],q=P(cap.x,cap.z+.35);if(!q)continue;
      const txt="ЗАКРИТЕ НЕБО";g.font=`800 ${10*dpr}px "JetBrains Mono",monospace`;const tw=g.measureText(txt).width+28*dpr;g.fillStyle="rgba(40,8,20,.9)";g.fillRect(q[0]-tw/2,q[1]-10*dpr,tw,20*dpr);
      g.strokeStyle="#d696ff";g.lineWidth=1.2*dpr;g.strokeRect(q[0]-tw/2,q[1]-10*dpr,tw,20*dpr);drawIcons(g,["plane"],q[0]-tw/2+5*dpr,q[1],13*dpr,"#f0625f");
      g.strokeStyle="#f0625f";g.lineWidth=1.6*dpr;g.beginPath();g.moveTo(q[0]-tw/2+5*dpr,q[1]+6*dpr);g.lineTo(q[0]-tw/2+18*dpr,q[1]-6*dpr);g.stroke();
      g.fillStyle="#e9c8ff";g.textAlign="left";g.textBaseline="middle";g.fillText(txt,q[0]-tw/2+22*dpr,q[1]+.5*dpr);g.textBaseline="alphabetic"}}
  // closed checkpoints: closed one by one, or all crossings of a closed border / closed country
  INC_HIT=JAM_HIT.slice();
  if(vis("clb")&&CO.cls.length){const W=g.canvas.width,H=g.canvas.height,seen=[];const u0=P(Cam.tx,Cam.tz),u1=P(Cam.tx+1,Cam.tz),pu=u0&&u1?Math.hypot(u1[0]-u0[0],u1[1]-u0[1])/dpr:40,cs=clamp(pu/40,3.5,7)*dpr; /* the same size as an open checkpoint */
    const pts=(BOARD.cps||[]).map(c=>({c,cl:incCrossCl(c.a,c.b,c.x,c.z)})).filter(o=>o.cl);for(const cl of CO.cls)if(cl.kind==="cp"&&!pts.some(o=>Math.hypot(o.c.x-cl.x,o.c.z-cl.z)<.05))pts.push({c:cl,cl});
    for(const {c,cl} of pts){const q=P(c.x,c.z);if(!q||q[0]<-20||q[1]<-20||q[0]>W+20||q[1]>H+20)continue;if(seen.some(s=>Math.hypot(s[0]-q[0],s[1]-q[1])<4*dpr))continue;seen.push(q);const s=cs;
      g.fillStyle="#f0625f";g.strokeStyle="#0b1520";g.lineWidth=1.4*dpr;g.fillRect(q[0]-s,q[1]-s,s*2,s*2);g.strokeRect(q[0]-s,q[1]-s,s*2,s*2);
      g.strokeStyle="#fff";g.lineWidth=2*dpr;g.beginPath();g.moveTo(q[0]-s*.55,q[1]-s*.55);g.lineTo(q[0]+s*.55,q[1]+s*.55);g.moveTo(q[0]+s*.55,q[1]-s*.55);g.lineTo(q[0]-s*.55,q[1]+s*.55);g.stroke();
      const ttl=cl.kind==="cp"?"Пункт пропуску закрито":cl.kind==="pair"?"Кордон закрито":`${cnm(cl.a)} закрила кордони`;
      INC_HIT.push({x:q[0]/dpr,y:q[1]/dpr,r:s/dpr+4,html:`<div class="row" style="gap:8px"><span class="bad">${ic("lock")}</span><b>${ttl}</b></div>
        <div class="note" style="margin-top:4px">${c.rail?"Залізничний перехід":"Автомобільний пункт пропуску"} · ${esc(cnm(c.a))} → ${esc(cnm(c.b))}</div>
        <div style="margin-top:6px;padding-top:6px;border-top:1px solid var(--line)">Причина: <b>${esc(cl.why)}</b></div>
        <div class="note" style="margin-top:4px">${cl.kind==="cp"?"Машини їдуть через сусідні пункти пропуску.":cl.kind==="pair"?"Закриті всі переходи між цими країнами: лише об'їзд через інші держави.":"Не можна в'їхати чи виїхати; порти й аеропорти теж закрито."}</div>
        <div class="row sp" style="margin-top:6px"><span class="note">Відкриття через</span><b class="num warn">≈ ${daysS(Math.max(0,cl.until-coNow()))}</b></div>`})}}
  // closed ports and airports
  {const ev=new Set();if(vis("clp"))for(const p of PL){const sea=p.port!=null&&incPortCl(p,"sea"),air=p.air&&incPortCl(p,"air");if(!sea&&!air)continue;const q0=P(p.x,p.z);if(!q0)continue;const ks=[sea?"anchor":"",air?"plane":""].filter(Boolean),R=8.5*dpr;
    ks.forEach((k,i)=>{const q=[q0[0]+(i-(ks.length-1)/2)*(R*2+3*dpr),q0[1]-R-9*dpr];g.fillStyle="#f0443c";g.strokeStyle="#0b1520";g.lineWidth=1.4*dpr;g.beginPath();g.arc(q[0],q[1],R,0,7);g.fill();g.stroke();
      drawIcons(g,[k],q[0]-R*.6,q[1],R*1.2,"#ffffff");INC_HIT.push({x:q[0]/dpr,y:q[1]/dpr,r:R/dpr+3,html:`<div class="row" style="gap:8px"><span class="bad">${ic(k)}</span><b>${k==="anchor"?"Порт":"Аеропорт"} ${esc(p.name)} закрито</b></div><div style="margin-top:6px;padding-top:6px;border-top:1px solid var(--line)">Причина: <b>${esc(k==="anchor"?sea:air)}</b></div><div class="note" style="margin-top:4px">${k==="anchor"?"Судна чекають на рейді, нові морські рейси звідси й сюди не відправляються.":"Вильоти й посадки скасовано, нові авіарейси недоступні."}</div>`})})}
   CITY_EV=ev;for(const c of CITY_EL){if(!c.cap)continue;const pl=PL.find(q=>q.type==="cap"&&q.cid===c.cid);c.el.classList.toggle("evcap",!!pl&&ev.has(pl.id))}}
}
{const _dl=drawLogistics;drawLogistics=function(g,dpr){_dl(g,dpr);if(G.co&&G.board)guard("Обстановка",()=>drawIncBase(g,dpr))}}
{const _dt=drawBoardTowns;drawBoardTowns=function(g,dpr){_dt(g,dpr);guard("Обстановка",()=>drawIncTop(g,dpr))}}
/* closed countries turn red */
{const _cc=coColors;coColors=function(){const c=_cc();if(CO.cls&&vis("clb"))for(const cl of CO.cls)if(cl.kind==="cty"&&c[cl.a])c[cl.a]=mixc(c[cl.a],[.86,.22,.2],.55);return c}}

/* ---------- window: situation on the routes ---------- */
function incSect(){incInit();const T=coNow(),jf=UI.jfl||"all",rows=[];
  for(const c of CO.cls){const nm=c.kind==="cty"?`${cnm(c.a)}: кордони закрито`:c.kind==="pair"?`Кордон ${cnm(c.a)} — ${cnm(c.b)} закрито`:`Пункт пропуску ${cnm(c.a)} → ${cnm(c.b)} закрито`;
    rows.push([c.kind==="cp"?"lock":"swords","bad",nm,`${c.why} · ${c.kind==="cty"?"не можна в'їхати чи виїхати, порти й аеропорти закрито":c.kind==="pair"?"автодороги й залізниця — лише в об'їзд через інші країни":"машини їдуть через сусідні пункти"}`,c.until-T,"",c.id])}
  if(SKY.size&&(jf==="all"||jf==="air"))rows.push(["plane","bad",`Закрите небо: ${[...SKY].map(cnm).join(", ")}`,"Воєнний стан: аеропорти закрито, літаки облітають цей повітряний простір",Math.max(...CO.cls.filter(c=>c.conf).map(c=>c.until))-T,"",CO.cls.find(c=>c.conf).id]);
  if(jf==="all"||jf==="road"||jf==="rail")for(const z of CO.band)rows.push(["skull","warn",`Бандити на дорогах · ${z.name}`,"Ризик пограбування вантажівок і потягів у зоні вп'ятеро вищий",z.until-T,"",z.id||0]);
  if(jf==="all"||jf==="sea")for(const z of CO.pir)rows.push(["skull","bad",`Піратство · ${z.name}`,"Судна в зоні можуть захопити заради викупу",1e9,"",z.id||-1]);
  for(const w of CO.wx){const K=WXK[w.k];if(jf!=="all"&&!K[jf])continue;const ports=PL.filter(p=>Math.hypot(p.x-w.x,p.z-w.z)<w.r&&(K.sea&&p.port!=null||K.air&&p.air)).map(p=>p.name).slice(0,4);
    rows.push([K.ic,"warn",`${K.n} · район ${w.near}`,`Закрито: ${[K.road?"дороги":"",K.rail?"залізниця":"",K.sea?"порти":"",K.air?"аеропорти":""].filter(Boolean).join(", ")}${ports.length?" · "+ports.join(", "):""}`,w.until-T,"",w.id])}
  const inc=CO.jobs.filter(j=>{const s=coJobState(j,T-j.t0);return s.inc&&(jf==="all"||j.mode===jf)}),red=inc.filter(j=>INC_RED.has(coJobState(j,T-j.t0).inc.k)).length;
  return `${sect("Ситуація на маршрутах")}<div class="grid3" style="margin-bottom:8px">${stat("Інциденти",red,`${inc.length-red} затримок у черзі, огляді, перед перекриттям`,T_("Інциденти","ДТП, поломки, нестача пального. Техніка блимає червоним на карті."))}${stat("Закриття",CO.cls.length,CO.cls.length?"кордони й пункти пропуску":"усі кордони відкриті",T_("Закриті кордони","Червона лінія на карті. Нові рейси прокладаються в об'їзд; машина, що доїхала до закритого кордону, шукає об'їзд, чекає або везе вантаж назад."))}${stat("Затори",JAM.length,"ділянок біля міст і кордонів",T_("Затори","Червоні й помаранчеві відрізки доріг. Вантажівки там рухаються з зупинками."))}</div>
  ${rows.length?rows.map(r=>`<div class="lrow" style="margin-bottom:6px;cursor:pointer" data-act="incGo" data-arg="${r[6]}"><span class="${r[1]}">${ic(r[0])}</span><div style="min-width:0"><b>${esc(r[2])}</b><div class="note">${esc(r[3])}</div></div><span class="num ${r[1]}">${r[4]>1e8?"постійно":"ще "+daysS(Math.max(0,r[4]))}</span></div>`).join(""):`<div class="note">Кордони відкриті, негоди на маршрутах немає.</div>`}`}
const T_=(a,b)=>typeof T==="function"?T(a,b):"";
ACT.incGo=id=>{id=+id;const c=CO.cls.find(x=>x.id===id),w=CO.wx.find(x=>x.id===id)||(CO.band||[]).find(x=>x.id===id)||(CO.pir||[]).find(x=>x.id===id);let x,z,d=5;
  if(w){x=w.x;z=w.z;d=w.r*5+2}else if(c){if(c.kind==="cp"){x=c.x;z=c.z;d=3}else{const ps=PL.filter(p=>p.cid===c.a||c.kind==="pair"&&p.cid===c.b);if(!ps.length)return;x=ps.reduce((a,p)=>a+p.x,0)/ps.length;z=ps.reduce((a,p)=>a+p.z,0)/ps.length;d=8}}else return;
  Cam.ttx=x;Cam.ttz=z+.3;Cam.tdist=clamp(d,2.5,WX*1.1)};

/* attack markers: attackers close in, then a skull stays on the spot */
function drawIncMarks(g,dpr){if(!CO.imk||!CO.imk.length||!vis("mark"))return;const P=incP(dpr),now=Date.now();REDRAW=true;
  for(const m of CO.imk){let x=m.x,z=m.z;if(m.k==="pir"){const j=CO.jobs.find(j=>j.id===m.jid);if(j){const q=coPosAt(j,coJobState(j,coNow()-j.t0).s);x=q[0];z=q[1]}}const c=P(x,z);if(!c)continue;
    const a=(now-m.t)/1000,col=m.k==="pir"?"240,98,95":"255,140,60";
    if(a<4){const k=clamp(a/3,0,1);for(let i=0;i<(m.k==="pir"?2:3);i++){const ang=i*2.1+m.t%7,R=(36-30*k)*dpr,px=c[0]+Math.cos(ang)*R,py=c[1]+Math.sin(ang)*R;
        g.fillStyle="#1a0808";g.strokeStyle=`rgb(${col})`;g.lineWidth=1.4*dpr;g.beginPath();if(m.k==="pir"){g.moveTo(px-5*dpr,py-2*dpr);g.lineTo(px+5*dpr,py-2*dpr);g.lineTo(px+3*dpr,py+3*dpr);g.lineTo(px-3*dpr,py+3*dpr);g.closePath()}else g.arc(px,py,3*dpr,0,7);g.fill();g.stroke()}}
    const f=(now/1000)%1.4/1.4;g.strokeStyle=`rgba(${col},${(.9*(1-f)).toFixed(2)})`;g.lineWidth=2*dpr;g.beginPath();g.arc(c[0],c[1],(10+f*22)*dpr,0,7);g.stroke();
    const y=c[1]-20*dpr,txt=m.k==="pir"?"ПІРАТИ":"НАПАД";g.font=`800 ${9*dpr}px "JetBrains Mono",monospace`;const tw=g.measureText(txt).width+24*dpr;
    g.fillStyle="rgba(26,6,6,.92)";g.fillRect(c[0]-tw/2,y-9*dpr,tw,18*dpr);g.strokeStyle=`rgb(${col})`;g.lineWidth=1.2*dpr;g.strokeRect(c[0]-tw/2,y-9*dpr,tw,18*dpr);
    drawIcons(g,["skull"],c[0]-tw/2+4*dpr,y,12*dpr,`rgb(${col})`);g.fillStyle=`rgb(${col})`;g.textAlign="left";g.textBaseline="middle";g.fillText(txt,c[0]-tw/2+19*dpr,y+.5*dpr);g.textBaseline="alphabetic"}}
/* GPS blackout: blink, vanish for a few seconds, flicker back, vanish again */
function incGpsVis(j){const gp=j.gps;if(!gp||coNow()>=gp.until)return 1;REDRAW=true;const t=(performance.now()/1000+j.id*.73)%7;if(t<1.4)return Math.sin(t*22)>0?1:.12;if(t<5)return 0;return .5}

/* hover card for pirate and bandit zones */
function zoneTip(e){const w=pickPlane(e.clientX,e.clientY);if(!w||!CO.pir)return null;const T=coNow();
  if(vis("wx"))for(const z of CO.wx||[])if(Math.hypot(w[0]-z.x,w[1]-z.z)<z.r){const K=WXK[z.k],pl=z.t0>T,hit=wxCl(K);
    return `<div class="row" style="gap:8px"><span style="color:rgb(${pl?"150,160,172":K.col})">${ic(K.ic)}</span><b>${K.n}</b><span class="note">${esc(z.near?"біля "+z.near:"")}</span></div><div class="note" style="margin-top:6px">${pl?"Прогноз синоптиків: негода ще не почалась, рух поки вільний. Коли почнеться: ":"Зараз: "}${hit}.</div><div class="row" style="margin-top:6px;gap:8px"><span class="note">${pl?"Почнеться через":"Закінчиться через"}</span><b class="num warn">≈ ${daysS(Math.max(0,(pl?z.t0:z.until)-T))}</b></div>${pl?`<div class="row" style="gap:8px"><span class="note">Триватиме</span><b class="num">≈ ${daysS(z.until-z.t0)}</b></div>`:""}`}
  for(const z of CO.band||[])if(Math.hypot(w[0]-z.x,w[1]-z.z)<z.r)return `<div class="row" style="gap:8px"><span style="color:#ff8c3c">${ic("skull")}</span><b>Зона бандитів</b><span class="note">${esc(z.name)}</span></div><div class="note" style="margin-top:6px">На дорогах діє банда: ризик пограбування вантажівок і потягів уп'ятеро вищий. Директор з безпеки знижує ризик.</div><div class="row" style="margin-top:6px;gap:8px"><span class="note">Банду знешкодять через</span><b class="num warn">≈ ${daysS(Math.max(0,z.until-coNow()))}</b></div>`;
  for(const z of CO.pir)if(Math.hypot(w[0]-z.x,w[1]-z.z)<z.r)return `<div class="row" style="gap:8px"><span class="bad">${ic("skull")}</span><b>Зона піратства</b><span class="note">${esc(z.name||"")}</span></div><div class="note" style="margin-top:6px">Судна в цих водах можуть захопити заради викупу. Директор з безпеки знижує ризик.</div>`;
  return null}
