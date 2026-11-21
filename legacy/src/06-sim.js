/* ================= GAME STATE & SIM ================= */
const G={C:[],me:null,date:{d:1,m:0,y:2026},day:0,speed:0,world:null,rel:null,esc:null,treaties:[],sanctions:new Set(),orgs:[],deals:[],market:null,news:[],inbox:[],events:[],markers:[],pc:40,diff:1,over:false,resolutions:[],cooldown:{}};
const COUNTRY_COLS=["#3f7f5a","#c27a3a","#3a6fa6","#8b6bb0","#4d9a8f","#b5904a","#6f8f3c","#b2584f","#4b8bbd","#8a7a4e","#5b6fb5","#2f8f73","#a8743a","#7e5a8f","#5f9a52","#b16a6a","#3d7d9a","#9a8a3a"];

function newMinister(mid,qBias=0,cp=.18){
  const comp=clamp(rnd(2,9)+qBias,1,10);
  return{name:personName(),age:rint(34,68),comp:+comp.toFixed(1),loyal:rint(30,90),corrupt:chance(cp)?rnd(.3,.8):rnd(0,.12),revealed:false,months:0};
}
function makeCountry(geo,i,used){
  const ide=pick(IDEOL),tr=pick(TRAITS);
  const sizeF=Math.sqrt(geo.landShare*15);
  const pop=clamp(rnd(8,70)*sizeF*rnd(.6,1.6),2,400);
  const dev=rnd(.15,1);
  const gdpPc=lerp(3,62,dev*dev)*1000;
  const gdp=pop*gdpPc/1000; // $B per year
  const name=genCountryName(used);
  const c={
    id:i,name,full:ide.gov+" "+name,geo,flag:genFlag(),ide,trait:tr,
    leader:{name:personName(),title:ide.title,age:rint(42,74),trait:tr},
    pop,gdp,gdp0:gdp,dev,growth:2,treasury:gdp*rnd(.02,.06),debt:gdp*rnd(.2,.9),
    tax:{income:rint(12,28),vat:rint(12,22),corp:rint(12,28),tariff:rint(2,10)},
    budget:MIN.map(m=>m.sh*.72*rnd(.8,1.2)*(m.id==="defense"&&tr.a>.5?1.6:1)),
    quality:MIN.map(()=>rnd(35,65)),
    min:MIN.map(m=>newMinister(m.id,0,.06+(1-tr.c)*.28)),
    laws:new Set(),
    mood:GROUPS.map(()=>rnd(40,60)),moodMod:GROUPS.map(()=>0),
    approval:50,stability:rnd(45,70),infl:rnd(2,7),unemp:rnd(3.5,11),corr:0,hdi:0,tech:dev*60+rnd(0,15),
    mil:0,res:{prod:[],dem:[],stock:[],auto:[],deposit:[]},
    hist:{gdp:[],pop:[],approval:[],treasury:[],growth:[]},
    mods:[],intel:0,shortage:{energy:0,food:0,ind:0,tech:0},lastBal:0,revenue:0,spend:0,tradeBal:0,
    color:null,dead:false,electionIn:rint(12,48),embargo:new Set(),
  };
  c.corr=clamp(10+(1-tr.c)*34+rnd(-6,8),5,70);
  // geology
  RES.forEach((r,k)=>{
    let dep=chance(.45)?0:rnd(.2,1.3);
    if(chance(.16))dep=rnd(2,4.2);
    if(r.cat==="tech")dep=dev>.55?rnd(.4,2.5)*(dev):rnd(0,.3);
    if(r.id==="grain"||r.id==="timber")dep=rnd(.3,2.4);
    if(r.id==="steel")dep=rnd(.2,1.8)*(.5+dev*.5);
    c.res.deposit[k]=dep;
    c.res.stock[k]=0;c.res.auto[k]=true;
  });
  if(chance(.15))c.laws.add(pick(["censor","policestate","conscription"]));
  if(ide.id==="dem"||ide.id==="soc")c.laws.add(pick(["press","egov","free_med","nabu"]));
  if(ide.id==="aut"||ide.id==="jun"){c.laws.add("policestate");if(chance(.6))c.laws.add("censor")}
  if(chance(.3))c.laws.add(pick(["nuclear","green","util_sub","min_wage"]));
  c.mil=(c.budget[MIDX.defense]*gdp)*rnd(8,14)+(c.laws.has("conscription")?20:0);
  return c;
}
function calibrateResources(){
  RES.forEach((r,k)=>{
    let D=0,S=0;
    G.C.forEach(c=>{const d=demandOf(c,k);c.res.dem[k]=d;D+=d;S+=d*c.res.deposit[k]});
    const f=S>0?D*rnd(.98,1.06)/S:1;
    G.C.forEach(c=>{c.res.base=c.res.base||[];c.res.base[k]=c.res.dem[k]*c.res.deposit[k]*f;c.res.prod[k]=c.res.base[k];c.res.stock[k]=c.res.dem[k]*rnd(1,3)});
  });
}
function demandOf(c,k){
  const r=RES[k];let d=c.gdp*r.share/12/r.p*1000; // units per month, gdp in $B, price in $M
  if(r.cat==="energy"){
    let f=1-(c.quality[MIDX.energy]-50)*.003;
    if(r.id!=="uranium"){f*=1+lawSum(c,"fossil")}else f*=c.laws.has("nuclear")?3.5:.4;
    d*=f;
  }
  if(r.id==="copper"||r.id==="lithium")d*=1+lawSum(c,r.id);
  return Math.max(0,d);
}
function lawSum(c,key){let s=0;c.laws.forEach(l=>{const L=LAWS[LIDX[l]];if(L.eff[key])s+=L.eff[key]});return s}

/* ---------- relations ---------- */
function initRelations(){
  const n=G.C.length;G.rel=[...Array(n)].map(()=>new Float32Array(n));G.esc=[...Array(n)].map(()=>new Uint8Array(n));
  for(let i=0;i<n;i++)for(let j=0;j<n;j++){if(i===j)continue;G.rel[i][j]=baseRel(i,j)+rnd(-20,20)}
}
function baseRel(i,j){
  const a=G.C[i],b=G.C[j];let r=0;
  if(a.ide.id===b.ide.id)r+=15;
  const auth=x=>["aut","jun"].includes(x.ide.id),dem=x=>["dem","soc","tec","mon"].includes(x.ide.id);
  if(auth(a)&&dem(b)||dem(a)&&auth(b))r-=15;
  if(a.geo.neighbors.includes(j))r-=6*a.trait.a;
  r+=(a.trait.f-.5)*20;
  if(dem(a))r+=lawSum(b,"demRel")*.6;
  return r;
}
function worldTension(){
  let s=0,n=0;const N=G.C.length;
  for(let i=0;i<N;i++)for(let j=i+1;j<N;j++){s+=G.esc[i][j]*G.esc[i][j]*3;const r=(G.rel[i][j]+G.rel[j][i])/2;if(r<-30)s+=(-30-r)*.12;n++}
  return clamp(12+s/Math.max(1,n)*8+G.sanctions.size*.8+(G.wars?G.wars.length*10:0),0,100);
}

/* ---------- market ---------- */
function initMarket(){
  G.market={price:RES.map(r=>r.p),hist:RES.map(r=>Array(24).fill(r.p)),shock:RES.map(()=>1),press:RES.map(()=>0),vol:RES.map(()=>0)};
}
function updateMarketDaily(){
  const m=G.market;const ten=worldTension();
  RES.forEach((r,k)=>{
    let S=0,D=0;G.C.forEach(c=>{S+=c.res.prod[k];D+=c.res.dem[k]});
    let ratio=D/Math.max(S,1e-6);
    let target=r.p*Math.pow(ratio,2.2)*m.shock[k];
    if(r.cat==="energy")target*=1+(ten-30)*.004;
    if(cartelActive&&r.cat==="energy"&&(r.id==="oil"||r.id==="gas"))target*=1.12;
    target*=1+m.press[k];
    m.press[k]*=.9;
    m.shock[k]=1+(m.shock[k]-1)*.985;
    const noise=1+(R()-.5)*.012;
    m.price[k]=clamp(m.price[k]+(target-m.price[k])*.06,r.p*.25,r.p*5)*noise;
  });
}
let cartelActive=false;

/* ---------- economy: monthly ---------- */


/* ---------- player monthly hooks ---------- */

/* ---------- bots: monthly governance ---------- */

/* ---------- daily tick ---------- */
function dayTick(){if(G.over)return;coDay()}

/* ---------- diplomacy monthly drift ---------- */

/* ---------- AI daily diplomatic behaviour ---------- */

/* ---------- organizations ---------- */
