let NW=200,NH=125; // nav / logistics grid size (set by setWorldScale)
/* ================= WORLD GENERATION ================= */
const NEU=120;let MW=1600,MH=1000,WX=16,WZ=10; // texture size, world size (mutable: company mode uses a 2x-area world)
const SECTOR=7.5,BOARD_SIZES={s:{c:2,r:1,n:"Мала"},m:{c:3,r:2,n:"Середня"},l:{c:4,r:3,n:"Велика"},legacy:{c:3.2,r:16/7.5,n:"Стара"}}; // legacy: saves made before map sizes existed (24×16)
function setWorldScale(big){setTriLattice(big==="board"||big==="earth");if(big==="earth"){MW=2560;MH=1200;WX=32;WZ=15;NW=320;NH=150;return}if(big==="board"){const Z=BOARD_SIZES[G.mapSize]||BOARD_SIZES.m;WX=Z.c*SECTOR;WZ=Z.r*SECTOR;MW=Math.round(WX*80);MH=Math.round(WZ*80);NW=Math.round(WX*10);NH=Math.round(WZ*10);return}MW=big?2048:1600;MH=big?1280:1000;WX=big?22.4:16;WZ=big?14:10;NW=big?256:200;NH=big?160:125}
function makePerlin(rng){
  const p=new Uint8Array(512),perm=[...Array(256).keys()];
  for(let i=255;i>0;i--){const j=Math.floor(rng()*(i+1));[perm[i],perm[j]]=[perm[j],perm[i]]}
  for(let i=0;i<512;i++)p[i]=perm[i&255];
  const gx=new Float32Array(16),gy=new Float32Array(16);
  for(let i=0;i<16;i++){const a=i/16*Math.PI*2;gx[i]=Math.cos(a);gy[i]=Math.sin(a)}
  return function(x,y){
    const xi=Math.floor(x),yi=Math.floor(y),xf=x-xi,yf=y-yi,X=xi&255,Y=yi&255;
    const u=xf*xf*xf*(xf*(xf*6-15)+10),v=yf*yf*yf*(yf*(yf*6-15)+10);
    const a=p[p[X]+Y]&15,b=p[p[X+1]+Y]&15,c=p[p[X]+Y+1]&15,d=p[p[X+1]+Y+1]&15;
    const n00=gx[a]*xf+gy[a]*yf,n10=gx[b]*(xf-1)+gy[b]*yf,n01=gx[c]*xf+gy[c]*(yf-1),n11=gx[d]*(xf-1)+gy[d]*(yf-1);
    const x1=n00+(n10-n00)*u,x2=n01+(n11-n01)*u;return x1+(x2-x1)*v;
  };
}
const tick=()=>new Promise(r=>setTimeout(r,0));

const EDT=(F,W,Hh)=>{const N=Math.max(W,Hh),f=new Float64Array(N),d=new Float64Array(N),v=new Int32Array(N),z=new Float64Array(N+1);
    const run=len=>{let k=0;v[0]=0;z[0]=-Infinity;z[1]=Infinity;for(let q=1;q<len;q++){let sx=((f[q]+q*q)-(f[v[k]]+v[k]*v[k]))/(2*q-2*v[k]);while(sx<=z[k]){k--;sx=((f[q]+q*q)-(f[v[k]]+v[k]*v[k]))/(2*q-2*v[k])}k++;v[k]=q;z[k]=sx;z[k+1]=Infinity}k=0;for(let q=0;q<len;q++){while(z[k+1]<q)k++;d[q]=(q-v[k])*(q-v[k])+f[v[k]]}};
    for(let x=0;x<W;x++){for(let y=0;y<Hh;y++)f[y]=F[y*W+x];run(Hh);for(let y=0;y<Hh;y++)F[y*W+x]=d[y]}
    for(let y=0;y<Hh;y++){for(let x=0;x<W;x++)f[x]=F[y*W+x];run(W);for(let x=0;x<W;x++)F[y*W+x]=d[x]}};
async function genWorld(seed,N,prog,opts={}){
  const sc=[MW,MH],tick_=async()=>{await tick();if(opts.abort&&opts.abort()||MW!==sc[0]||MH!==sc[1])throw new Error("gen-abort")};
  const rng=mulberry(seed);const noise=makePerlin(rng);
  const fbm=(x,y,o)=>{let s=0,a=1,f=1,n=0;for(let i=0;i<o;i++){s+=a*noise(x*f,y*f);n+=a;a*=.5;f*=2.03}return s/n};
  // world layout: separate continents of any orientation, archipelagos and lone islands
  const BIG=!!opts.big,iS=BIG?2.15:1; // company world: same canvas, physically smaller continents
  const blobs=[],isl=[];const nC=BIG?7+Math.floor(rng()*4):2+Math.floor(rng()*4),centers=[];
  // company world: 2–3 large landmasses first, spread across the map, then ordinary continents between them
  const nMaj=BIG?2+(rng()<.5?1:0):0;
  for(let t=0;centers.length<nMaj&&t<2000;t++){const x=(.42+rng()*.96)*iS,y=(.32+rng()*.36)*iS;if(centers.every(c=>Math.hypot(c[0]-x,c[1]-y)>1.05-t*.0004))centers.push([x,y])}
  for(let t=0;centers.length<nC&&t<1600;t++){const x=(.24+rng()*1.12)*iS,y=(.2+rng()*.6)*iS;if(centers.every((c,i)=>Math.hypot(c[0]-x,c[1]-y)>(i<nMaj?.72:.46)-t*.0003))centers.push([x,y])}
  for(const [ci,[cx,cy]] of centers.entries()){const maj=ci<nMaj;
    const size=maj?.21+rng()*.09:BIG?.08+rng()*.09:.065+rng()*.085;let a=rng()*Math.PI*2,x=cx,y=cy;const k=maj?7+Math.floor(rng()*5):3+Math.floor(rng()*5),stp=maj?.78:1;
    for(let j=0;j<k;j++){const r=size*(.6+rng()*.65);blobs.push({x,y,r,w:.95+rng()*.35});
      if(rng()<.4){const pa=a+(rng()<.5?1:-1)*(.9+rng()*1.1);blobs.push({x:x+Math.cos(pa)*r*1.25,y:y+Math.sin(pa)*r*1.25,r:r*(.3+rng()*.35),w:.95,pen:1})}
      a+=(rng()-.5)*(maj?1.9:1.3);x+=Math.cos(a)*r*stp;y+=Math.sin(a)*r*stp}
  }
  const nA=BIG?6+Math.floor(rng()*4):1+Math.floor(rng()*3);
  for(let t=0,n=0;n<nA&&t<800;t++){const x=(.14+rng()*1.32)*iS,y=(.14+rng()*.72)*iS;if(blobs.some(b=>Math.hypot(b.x-x,b.y-y)<b.r+.12))continue;n++;
    const ang=rng()*Math.PI,el=1.2+rng()*2,ca=Math.cos(ang),sa=Math.sin(ang),put=(g1,g2,r,w)=>isl.push({x:x+ca*g1-sa*g2,y:y+sa*g1+ca*g2,r,w});
    put(0,0,.03+rng()*.035,1.35);
    const mid=2+Math.floor(rng()*4);for(let j=0;j<mid;j++){const d=.05+rng()*.08,a=rng()*6.283;put(Math.cos(a)*d*1.3,Math.sin(a)*d/el,.012+rng()*.012,1.35)}
    const sp=.06+rng()*.08,cnt=16+Math.floor(rng()*26);for(let j=0;j<cnt;j++){put((rng()+rng()-1)*sp*1.6,(rng()+rng()-1)*sp/el,.004+rng()*.009,1.45)}}
  const nI=BIG?28+Math.floor(rng()*16):5+Math.floor(rng()*9);
  for(let t=0,n=0;n<nI&&t<900;t++){const x=(.08+rng()*1.44)*iS,y=(.08+rng()*.84)*iS;if(blobs.some(b=>Math.hypot(b.x-x,b.y-y)<b.r+.07))continue;n++;isl.push({x,y,r:.008+rng()*.026,w:1.3})}
  // curved arms: spits, hooks and long peninsulas growing out of continents
  const arms=[];const mainB=blobs.filter(b=>!b.pen);
  const nArm=BIG?10+Math.floor(rng()*8):3+Math.floor(rng()*5);
  for(let k=0;k<nArm&&mainB.length;k++){const b=mainB[Math.floor(rng()*mainB.length)];let a=rng()*6.283,px=b.x+Math.cos(a)*b.r*.7,py=b.y+Math.sin(a)*b.r*.7;
    const segs=[],n=7+Math.floor(rng()*6),L=.14+rng()*.26,r0=.018+rng()*.022,bend=(rng()-.5)*.9;
    for(let q=0;q<n;q++){a+=bend+(rng()-.5)*.5;const qx=px+Math.cos(a)*L/n,qy=py+Math.sin(a)*L/n;segs.push([px,py,qx,qy,r0*(1-q/n*.6)]);px=qx;py=qy}
    arms.push({segs,bx:Math.min(...segs.map(s=>Math.min(s[0],s[2])))-.05,ex:Math.max(...segs.map(s=>Math.max(s[0],s[2])))+.05,by:Math.min(...segs.map(s=>Math.min(s[1],s[3])))-.05,ey:Math.max(...segs.map(s=>Math.max(s[1],s[3])))+.05})}
  if(opts.dom){blobs.length=0;isl.length=0;arms.length=0;
    let x=.55+rng()*.5,y=.42+rng()*.16,a=rng()*6.283;const k=7+Math.floor(rng()*4);
    for(let j=0;j<k;j++){const r=.15+rng()*.09;blobs.push({x,y,r,w:1.25});a+=(rng()-.5)*1.8;x=clamp(x+Math.cos(a)*r*.85,.42,1.18);y=clamp(y+Math.sin(a)*r*.6,.32,.68)}
    for(let j=0;j<4;j++){const b=blobs[Math.floor(rng()*k)];blobs.push({x:b.x+(rng()-.5)*.3,y:b.y+(rng()-.5)*.25,r:.06+rng()*.06,w:1,pen:1})}
    const ni=12+Math.floor(rng()*14);for(let j=0;j<ni;j++){const b=blobs[Math.floor(rng()*k)];const an=rng()*6.283,d=b.r*(1.1+rng()*.9);isl.push({x:b.x+Math.cos(an)*d,y:b.y+Math.sin(an)*d*.8,r:.006+rng()*.018,w:1.3})}}
  // mountain ranges: curved chains of peaks running across continents
  const ranges=[];
  for(const b of blobs){if(b.pen)continue;const k=rng()<.38?1:0;
    for(let r=0;r<k;r++){let a=rng()*Math.PI*2,px=b.x+(rng()-.5)*b.r,py=b.y+(rng()-.5)*b.r*.8;const segs=[],L=b.r*(1.3+rng()*1.5),n=10;
      for(let q=0;q<n;q++){a+=(rng()-.5)*.65;const qx=px+Math.cos(a)*L/n,qy=py+Math.sin(a)*L/n;segs.push([px,py,qx,qy]);px=qx;py=qy}
      ranges.push({segs,w:.026+rng()*.026,h:.75+rng()*.45,bx:Math.min(...segs.map(s=>Math.min(s[0],s[2])))-.2,ex:Math.max(...segs.map(s=>Math.max(s[0],s[2])))+.2,by:Math.min(...segs.map(s=>Math.min(s[1],s[3])))-.2,ey:Math.max(...segs.map(s=>Math.max(s[1],s[3])))+.2})}}
  // inner seas & gulfs cut into continents
  const seas=[];const nsea=BIG?4+Math.floor(rng()*4):1+Math.floor(rng()*3);
  for(let i=0;i<nsea;i++){const b=blobs[Math.floor(rng()*blobs.length)];const rx=.04+rng()*.1;seas.push({x:b.x+(rng()-.5)*b.r*1.4,y:b.y+(rng()-.5)*b.r*1.2,rx,ry:rx*(.25+rng()*.6),ca:Math.cos(rng()*Math.PI),sa:0,d:.9+rng()*.5});const S=seas[seas.length-1];S.sa=Math.sqrt(1-S.ca*S.ca)*(rng()<.5?1:-1)}
  const segD=(x,y,s)=>{const vx=s[2]-s[0],vy=s[3]-s[1],wx_=x-s[0],wy_=y-s[1];const t=clamp((wx_*vx+wy_*vy)/(vx*vx+vy*vy),0,1);const dx=wx_-vx*t,dy=wy_-vy*t;return dx*dx+dy*dy};
  const seaSides=[];if(opts.dom){const all=["s","e","w","n"];seaSides.push(rng()<.6?"s":all[Math.floor(rng()*4)]);if(rng()<.55){const o=all.filter(x=>!seaSides.includes(x));seaSides.push(o[Math.floor(rng()*o.length)])}}
  // low-res height
  const LW=MW/2,LH=MH/2,low=new Float32Array(LW*LH),lowM=new Float32Array(LW*LH);
  const EM=opts.earth?earthMask(LW,LH):null;if(EM){blobs.length=0;isl.length=0;arms.length=0;seas.length=0;ranges.length=0}
  for(let y=0;y<LH;y++){
    for(let x=0;x<LW;x++){
      const nx=x/LW,ny=y/LH,u=nx*1.6*iS,v=ny*iS;
      const wx0=u+.24*fbm(u*2+5.2,v*2+1.3,4),wy0=v+.24*fbm(u*2+8.1,v*2+2.7,4);
      const wx=wx0+.07*fbm(wx0*7+3,wy0*7+9,3),wy=wy0+.07*fbm(wx0*7+13,wy0*7+1,3);
      let c=0;if(EM){const sx=clamp(Math.round(x+fbm(nx*14+3,ny*14,3)*3),0,LW-1),sy=clamp(Math.round(y+fbm(nx*14,ny*14+7,3)*3),0,LH-1);c=EM[sy*LW+sx]*1.25}for(const b of blobs){const dx=wx-b.x,dy=wy-b.y;c+=b.w*Math.exp(-(dx*dx+dy*dy)/(b.r*b.r))}
      for(const A of arms){if(wx<A.bx||wx>A.ex||wy<A.by||wy>A.ey)continue;for(const sg of A.segs){const d2=segD(wx,wy,sg);if(d2<sg[4]*sg[4]*9)c=Math.max(c,1.15*Math.exp(-d2/(sg[4]*sg[4])))}}
      const ix=u+(wx-u)*.55,iy=v+(wy-v)*.55;for(const b of isl){const dx=ix-b.x,dy=iy-b.y;let q=(dx*dx+dy*dy)/(b.r*b.r);if(q<14){q*=1+1.1*fbm(ix/b.r*.6+b.x*40,iy/b.r*.6+b.y*40,3);c+=b.w*Math.exp(-q)}}
      const cs=sstep(.05,.9,c);
      let h=opts.dom?0:cs*.74+fbm(wx*3.5,wy*3.5,6)*.5+fbm(wx*8+21,wy*8+5,5)*.16+(1-Math.abs(fbm(wx*9+40,wy*9,4)*2))*.06-.07;
      let m=0;
      for(const R of ranges){if(wx<R.bx||wx>R.ex||wy<R.by||wy>R.ey)continue;let d2=1e9;for(const sg of R.segs)d2=Math.min(d2,segD(wx,wy,sg));
        const w2=R.w*R.w;if(d2>w2*14)continue;
        const along=.45+.55*sstep(-.25,.35,fbm(wx*7+R.w*80,wy*7-R.w*50,3));
        const peak=Math.exp(-d2/w2),foot=Math.exp(-d2/(w2*7))*.3;
        const rough=1-Math.abs(fbm(wx*18+R.w*99,wy*18,4)*2);
        m=Math.max(m,(peak*(.35+.65*rough)*along+foot*(.6+.4*along))*R.h)}
      h+=m*.3;
      for(const S of seas){const dx=wx-S.x,dy=wy-S.y,p=dx*S.ca+dy*S.sa,q=-dx*S.sa+dy*S.ca;h-=S.d*Math.exp(-(p*p/(S.rx*S.rx)+q*q/(S.ry*S.ry))*(1+.8*fbm(wx*11+S.rx*90,wy*11,3)))}
      lowM[y*LW+x]=m;
      const ed=Math.min(Math.min(nx,1-nx)*1.6,Math.min(ny,1-ny));
      if(opts.dom){h+=.64+fbm(wx*3.2,wy*3.2,5)*.34+fbm(wx*9+5,wy*9,3)*.06;
        for(const sd of seaSides){const d=sd==="s"?1-ny:sd==="n"?ny:sd==="w"?nx:1-nx;const wv=fbm(wx*4+sd.charCodeAt(0),wy*4,4)*.12+fbm(wx*11,wy*11+3,3)*.04;h-=(1-sstep(.05,.27,d+wv))*1.6}}
      else if(!EM)h-=(1-sstep(0,.1,ed))*1.4;
      low[y*LW+x]=h;
    }
    if(y%50===0){prog(.05+.25*y/LH,"Формування континентів…");await tick_()}
  }
  // upsample + detail
  const H=new Float32Array(MW*MH),Mf=new Float32Array(MW*MH);
  for(let y=0;y<MH;y++){
    const fy=Math.min(y/2,LH-1.001),y0=Math.floor(fy),ty=fy-y0;
    for(let x=0;x<MW;x++){
      const fx=Math.min(x/2,LW-1.001),x0=Math.floor(fx),tx=fx-x0,i=y0*LW+x0;
      const h=(low[i]*(1-tx)+low[i+1]*tx)*(1-ty)+(low[i+LW]*(1-tx)+low[i+LW+1]*tx)*ty;
      H[y*MW+x]=h+noise(x*.02,y*.02)*.05+noise(x*.05+50,y*.05)*.03+noise(x*.12+7,y*.12+3)*.016;
      const mm=(lowM[i]*(1-tx)+lowM[i+1]*tx)*(1-ty)+(lowM[i+LW]*(1-tx)+lowM[i+LW+1]*tx)*ty;
      Mf[y*MW+x]=mm*(1+noise(x*.05+7,y*.05+3)*.35*mm);
    }
    if(y%200===0){prog(.3+.1*y/MH,"Деталізація рельєфу…");await tick_()}
  }
  // threshold to fixed land fraction
  const sample=[];for(let i=0;i<30000;i++)sample.push(H[Math.floor(rng()*H.length)]);sample.sort((a,b)=>a-b);
  let T=.5;if(opts.dom)T=sample[Math.floor(sample.length*.2)];else{const fr=sample.filter(v=>v>T).length/sample.length;if(fr>(BIG?.3:.42))T=sample[Math.floor(sample.length*(BIG?.7:.58))];else if(fr<(BIG?.13:.2))T=sample[Math.floor(sample.length*(BIG?.87:.8))]}const top=sample[sample.length-1]-T,bot=T-sample[0];
  const land=new Uint8Array(MW*MH);let landCount=0;
  for(let i=0;i<H.length;i++){if(H[i]>T){land[i]=1;landCount++}}
  let nbMask=null,nbK=0,mcx=0,mcy=0,nbOff=0;
  if(opts.dom){nbMask=new Uint8Array(MW*MH);mcx=MW*(.42+rng()*.16);mcy=MH*(.42+rng()*.14);const rx=MW*(.29+rng()*.06),ry=MH*(.3+rng()*.06);nbK=2+Math.floor(rng()*3);nbOff=rng()*6.283;
    for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){const i=y*MW+x;if(!land[i])continue;
      const wx=x+noise(x*.004+11,y*.004)*70+noise(x*.013,y*.013+7)*22,wy=y+noise(x*.004,y*.004+23)*70+noise(x*.013+3,y*.013)*22;let dx=(wx-mcx)/rx,dy=(wy-mcy)/ry;
      if(dx>0&&seaSides.includes("e")||dx<0&&seaSides.includes("w"))dx/=1.9;if(dy>0&&seaSides.includes("s")||dy<0&&seaSides.includes("n"))dy/=1.9;
      if(dx*dx+dy*dy>1){nbMask[i]=1+Math.floor((((Math.atan2(wy-mcy,wx-mcx)+nbOff+noise(x*.006,y*.006)*.6)%6.2832+6.2832)%6.2832)/6.2832*nbK);land[i]=0;landCount--}}}
  // seeds
  prog(.42,"Розподіл держав…");await tick_();
  const comp=new Int32Array(MW*MH).fill(-1),comps=[];
  for(let i=0;i<land.length;i++){if(!land[i]||comp[i]>=0)continue;const id=comps.length,st=[i],pix=[];comp[i]=id;let area=0;
    while(st.length){const j=st.pop();area++;if((area&3)===0)pix.push(j);const x=j%MW;for(const n of [x>0?j-1:-1,x<MW-1?j+1:-1,j-MW,j+MW]){if(n>=0&&n<land.length&&land[n]&&comp[n]<0){comp[n]=id;st.push(n)}}}
    comps.push({id,area,pix})}
  let elig=comps.filter(c=>c.area>=Math.max(3000,landCount*.025)).sort((a,b)=>b.area-a.area);
  if(!elig.length)elig=comps.slice().sort((a,b)=>b.area-a.area).slice(0,1);
  if(elig.length>N)elig=elig.slice(0,N);
  {const S=elig.reduce((t,c)=>t+c.area,0);elig.forEach(c=>c.n=Math.max(1,Math.round(N*c.area/S)));let tot=elig.reduce((t,c)=>t+c.n,0);
   while(tot>N){const c=elig.filter(c=>c.n>1).sort((a,b)=>a.area/a.n-b.area/b.n)[0];if(!c)break;c.n--;tot--}
   while(tot<N){const c=elig.slice().sort((a,b)=>b.area/b.n-a.area/a.n)[0];c.n++;tot++}}
  const seeds=[];
  for(const c of elig){let minD=Math.sqrt(c.area/c.n)*.55,got=0;const ring=Math.min(25,Math.sqrt(c.area)/5);
    for(let att=0;got<c.n&&att<6000;att++){if(att%600===599)minD*=.85;const i=c.pix[Math.floor(rng()*c.pix.length)],x=i%MW,y=(i/MW)|0;
      if(x<10||y<10||x>MW-10||y>MH-10||Mf[i]>.45)continue;
      if(seeds.some(s=>(s.x-x)**2+(s.y-y)**2<minD*minD))continue;
      let lc=0;for(let k=0;k<16;k++){const a=k/16*6.283,xx=Math.round(x+Math.cos(a)*ring),yy=Math.round(y+Math.sin(a)*ring);if(xx>=0&&yy>=0&&xx<MW&&yy<MH&&land[yy*MW+xx])lc++}
      if(lc<13)continue;seeds.push({x,y});got++}}
  if(opts.earth){seeds.length=0;EARTH_DATA.seeds.forEach(([sx,sy],k)=>{let x=Math.round((sx+.5)/EARTH_DATA.w*MW),y=Math.round((sy+.5)/EARTH_DATA.h*MH);
      if(!land[y*MW+x]){let bd=1e18;for(let r=1;r<60;r++){for(let dy=-r;dy<=r;dy++)for(let dx=-r;dx<=r;dx++){const X=x+dx,Y=y+dy;if(X<0||Y<0||X>=MW||Y>=MH||!land[Y*MW+X])continue;const d=dx*dx+dy*dy;if(d<bd){bd=d;var bx=X,by=Y}}if(bd<1e18)break}if(bd<1e18){x=bx;y=by}}
      seeds.push({x,y,w:1.4,name:EARTH_DATA.names[k]})})}
  // every state gets its own growth character: power (size), start delay, elongation and direction
  const DX=[1,-1,0,0,1,1,-1,-1],DY=[0,0,1,-1,1,-1,1,-1];
  seeds.forEach(sd=>{
    let lc=0;for(let k=0;k<32;k++){const a=k/32*6.283,xx=Math.round(sd.x+Math.cos(a)*70),yy=Math.round(sd.y+Math.sin(a)*70);if(xx>=0&&yy>=0&&xx<MW&&yy<MH&&land[yy*MW+xx])lc++}
    const interior=lc>=30;let r=rng();if(interior)r*=.75;
    sd.m=sd.w||(r<.2?.8:r<.45?1.25:r<.75?1.9:r<.92?2.8:4.2);
    sd.off=sd.w?0:Math.floor(rng()*rng()*(interior?60:180));
    const ang=rng()*Math.PI,st=1+Math.pow(rng(),1.6)*2.6,px=-Math.sin(ang),py=Math.cos(ang);
    sd.dm=DX.map((dx,j)=>{const dy=DY[j],len=Math.hypot(dx,dy);return sd.m*len*(1+(st-1)*Math.abs((dx*px+dy*py)/len))*3});
  });
  // Dial's algorithm region growing
  const own=new Int8Array(MW*MH).fill(-1),dist=new Int32Array(MW*MH).fill(1e9);
  const buckets=[];const push=(d,i)=>{(buckets[d]||(buckets[d]=[])).push(i)};
  const locked=new Uint8Array(MW*MH);
  seeds.forEach((sd,k)=>{for(let dy=-7;dy<=7;dy++)for(let dx=-7;dx<=7;dx++){if(dx*dx+dy*dy>49)continue;const x=sd.x+dx,y=sd.y+dy;if(x<0||y<0||x>=MW||y>=MH)continue;const i=y*MW+x;if(!land[i]||locked[i])continue;locked[i]=1;own[i]=k;dist[i]=sd.off;push(sd.off,i)}});
  const baseC=new Uint8Array(MW*MH);
  for(let i=0;i<baseC.length;i++){if(!land[i])continue;const x=i%MW,y=(i/MW)|0;const e=Mf[i];baseC[i]=1+Math.floor(Math.max(0,e-.12)*26+(noise(x*.012+90,y*.012+40)+.5)*5+(noise(x*.03+31,y*.03+5)+.5)*7+(noise(x*.07+13,y*.07+77)+.5)*4)}
  for(let d=0;d<buckets.length;d++){
    const b=buckets[d];if(!b)continue;
    for(let q=0;q<b.length;q++){
      const i=b[q];if(dist[i]!==d)continue;const o=own[i],dm=seeds[o].dm;
      const x=i%MW,y=(i/MW)|0;
      for(let j=0;j<8;j++){const nx=x+DX[j],ny=y+DY[j];if(nx<0||ny<0||nx>=MW||ny>=MH)continue;const n=ny*MW+nx;if(!land[n]||(locked[n]&&own[n]!==o))continue;
        const nd=d+Math.max(1,Math.round(baseC[n]*dm[j]));if(nd<dist[n]){dist[n]=nd;own[n]=o;push(nd,n)}}
    }
    buckets[d]=null;
    if(d%6000===0){prog(.45+.15*Math.min(1,d/80000),"Проведення кордонів…");await tick_()}
  }
  // orphan islands → nearest seed
  if(opts.big&&!opts.dom){ // company world: no neutral land — island groups become their own states
    const cid=new Int32Array(MW*MH).fill(-1),comps=[];
    for(let i=0;i<own.length;i++){if(!land[i]||own[i]>=0||cid[i]>=0)continue;const st=[i],px=[];cid[i]=comps.length;let sx=0,sy=0;
      while(st.length){const j=st.pop();px.push(j);const x=j%MW,y=(j/MW)|0;sx+=x;sy+=y;for(const q of [x>0?j-1:-1,x<MW-1?j+1:-1,j-MW,j+MW]){if(q>=0&&q<own.length&&land[q]&&own[q]<0&&cid[q]<0){cid[q]=comps.length;st.push(q)}}}
      comps.push({px,x:sx/px.length,y:sy/px.length,a:px.length})}
    const par=comps.map((_,i)=>i),fd=i=>par[i]===i?i:(par[i]=fd(par[i]));
    for(let a=0;a<comps.length;a++)for(let b=a+1;b<comps.length;b++)if(Math.hypot(comps[a].x-comps[b].x,comps[a].y-comps[b].y)<150)par[fd(a)]=fd(b);
    const groups=new Map();comps.forEach((c,i)=>{const r=fd(i);if(!groups.has(r))groups.set(r,[]);groups.get(r).push(c)});
    const G2=[...groups.values()].map(L=>({L,a:L.reduce((s,c)=>s+c.a,0),x:L.reduce((s,c)=>s+c.x*c.a,0)/L.reduce((s,c)=>s+c.a,0),y:L.reduce((s,c)=>s+c.y*c.a,0)/L.reduce((s,c)=>s+c.a,0)})).sort((a,b)=>b.a-a.a);
    for(const g of G2){let id=-1;
      if(g.a>=700&&seeds.length<46){const big=g.L.slice().sort((a,b)=>b.a-a.a)[0];let best=big.px[0],bd=1e18;for(const j of big.px){const d=(j%MW-big.x)**2+(((j/MW)|0)-big.y)**2;if(d<bd){bd=d;best=j}}seeds.push({x:best%MW,y:(best/MW)|0});id=seeds.length-1}
      else{let bd=1e18;seeds.forEach((sd,k)=>{const d=(sd.x-g.x)**2+(sd.y-g.y)**2;if(d<bd){bd=d;id=k}})}
      for(const c of g.L)for(const j of c.px)own[j]=id}}
  for(let i=0;i<own.length;i++){if(land[i]&&own[i]<0){if(opts.dom){const x=i%MW,y=(i/MW)|0;let b=0,bd=1e18;seeds.forEach((s,k)=>{const d=(s.x-x)**2+(s.y-y)**2;if(d<bd){bd=d;b=k}});own[i]=b}else own[i]=NEU}}
  if(nbMask)for(let i=0;i<own.length;i++)if(nbMask[i])own[i]=NEU+nbMask[i];
  if(opts.earth){for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){const i=y*MW+x;if(!land[i])continue;const v=earthLabelAt(x+.5,y+.5);if(v)own[i]=(v&127)-1}}
  if(opts.tri&&TRI_K===0){const src=own.slice();sqBuild(src);
    for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){const q=sqHalf(x+.5,y+.5);own[y*MW+x]=SQL[(q[1]*SQW+q[0])*2+q[3]]}}
  else if(opts.tri){const src=own.slice();for(let y=0;y<MH;y++)for(let x=0;x<MW;x++)own[y*MW+x]=triLab(src,x+.5,y+.5)}
  // majority filter: removes single-pixel jaggies along borders
  prog(.6,"Згладжування кордонів…");await tick_();
  if(!opts.tri){const cnt=new Int16Array(128);for(let it=0;it<3;it++){const src=own.slice();
    for(let y=1;y<MH-1;y++)for(let x=1;x<MW-1;x++){const i=y*MW+x,o=src[i];if(o<0)continue;
      let diff=false;for(let dy=-1;dy<=1&&!diff;dy++)for(let dx=-1;dx<=1;dx++){const q=src[i+dy*MW+dx];if(q>=0&&q!==o){diff=true;break}}
      if(!diff)continue;const seen=[];
      for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++){const q=src[i+dy*MW+dx];if(q<0)continue;if(!cnt[q])seen.push(q);cnt[q]++}
      let best=o;for(const q of seen){if(cnt[q]>cnt[best])best=q}
      if(cnt[best]>=5)own[i]=best;for(const q of seen)cnt[q]=0;}
    await tick_()}}
  prog(.66,"Рендер текстур…");await tick_();
  // area, centroid, adjacency, border mask
  const n=seeds.length,area=new Float64Array(n),cx=new Float64Array(n),cy=new Float64Array(n);
  const adj=Array.from({length:n},()=>new Map());
  const INF=1e10,bf=new Float32Array(MW*MH);
  for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){
    const i=y*MW+x,o=own[i];bf[i]=INF;if(o<0||o>=NEU)continue;
    area[o]++;cx[o]+=x;cy[o]+=y;
    const nbs=[x>0?own[i-1]:-1,x<MW-1?own[i+1]:-1,y>0?own[i-MW]:-1,y<MH-1?own[i+MW]:-1];
    for(const q of nbs){if(q>=0&&q!==o&&q!==NEU){bf[i]=0;const m=adj[o];m.set(q,(m.get(q)||0)+1)}}
  }
  // exact euclidean distance transform (Felzenszwalb) to border pixels
  const edt=EDT;

  const blur=(A,r,passes,W=MW,Hh=MH)=>{const tmp=new Float32Array(A.length);for(let p=0;p<passes;p++){
    for(let y=0;y<Hh;y++){let acc=0;const row=y*W;for(let x=-r;x<=r;x++)acc+=A[row+clamp(x,0,W-1)];for(let x=0;x<W;x++){tmp[row+x]=acc/(2*r+1);acc+=A[row+Math.min(W-1,x+r+1)]-A[row+Math.max(0,x-r)]}}
    for(let x=0;x<W;x++){let acc=0;for(let y=-r;y<=r;y++)acc+=tmp[clamp(y,0,Hh-1)*W+x];for(let y=0;y<Hh;y++){A[y*W+x]=acc/(2*r+1);acc+=tmp[Math.min(Hh-1,y+r+1)*W+x]-tmp[Math.max(0,y-r)*W+x]}}}};
  // ---- 2x super-resolution country map with gaussian label voting (removes pixel stairs)
  prog(.7,"Векторизація кордонів…");await tick_();
  const HW=MW*2,HH=MH*2,hid=new Uint8Array(HW*HH);
  const near=new Uint8Array(MW*MH);
  for(let y=1;y<MH-1;y++)for(let x=1;x<MW-1;x++){const i=y*MW+x,o=own[i];if(own[i-1]!==o||own[i+1]!==o||own[i-MW]!==o||own[i+MW]!==o)near[i]=1}
  for(let it=0;it<2;it++){const src=near.slice();for(let y=1;y<MH-1;y++)for(let x=1;x<MW-1;x++){const i=y*MW+x;if(!src[i]&&(src[i-1]||src[i+1]||src[i-MW]||src[i+MW]))near[i]=1}}
  {const acc=new Float32Array(128),SG=2*.85*.85;
  for(let Y=0;Y<HH;Y++){const fy=(Y+.5)/2-.5,y0=Math.floor(fy);
    for(let X=0;X<HW;X++){if(opts.tri){const o=triLab(own,(X+.5)/2,(Y+.5)/2);hid[Y*HW+X]=o<0?0:o+1;continue}const fx=(X+.5)/2-.5,x0=Math.floor(fx);const ci=clamp(Math.round(fy),0,MH-1)*MW+clamp(Math.round(fx),0,MW-1);
      if(!near[ci]){hid[Y*HW+X]=own[ci]+1;continue}
      let best=-1,bw=0;const seen=[];
      for(let yy=y0-1;yy<=y0+2;yy++){const cy_=clamp(yy,0,MH-1);for(let xx=x0-1;xx<=x0+2;xx++){const o=own[cy_*MW+clamp(xx,0,MW-1)];if(o<0)continue;const w=Math.exp(-((xx-fx)**2+(yy-fy)**2)/SG);if(!acc[o])seen.push(o);acc[o]+=w}}
      for(const o of seen){if(acc[o]>bw){bw=acc[o];best=o}acc[o]=0}
      hid[Y*HW+X]=own[ci]<0?0:best+1;
    }
    if(Y%250===0)await tick_();
  }}
  prog(.8,"Побудова векторних кордонів…");await tick_();
  const lines=opts.tri?extractTriLines(own):extractLines(hid,HW,HH);
  // border distance field on the 2x grid
  const hb=new Float32Array(HW*HH);
  for(let Y=0;Y<HH;Y++)for(let X=0;X<HW;X++){const i=Y*HW+X,o=hid[i];hb[i]=INF;if(!o)continue;
    if((X>0&&hid[i-1]&&hid[i-1]!==o)||(X<HW-1&&hid[i+1]&&hid[i+1]!==o)||(Y>0&&hid[i-HW]&&hid[i-HW]!==o)||(Y<HH-1&&hid[i+HW]&&hid[i+HW]!==o))hb[i]=0}
  edt(hb,HW,HH);
  for(let i=0;i<hb.length;i++)hb[i]=Math.min(Math.sqrt(hb[i])+.5,24);
  blur(hb,1,1,HW,HH);
  const land2=new Uint8Array(HW*HH);for(let i=0;i<land2.length;i++)land2[i]=hid[i]?1:0;
  for(let it=0;it<8;it++){const src=hid.slice();for(let Y=1;Y<HH-1;Y++)for(let X=1;X<HW-1;X++){const i=Y*HW+X;if(src[i])continue;const q=src[i-1]||src[i+1]||src[i-HW]||src[i+HW];if(q)hid[i]=q}}
  await tick_();
  // smoothed height for relief lighting
  const Hs=new Float32Array(MW*MH);for(let i=0;i<Hs.length;i++)Hs[i]=Math.max(0,(H[i]-T)/top)*.25+Mf[i]*.9*sstep(0,.05,(H[i]-T)/top);blur(Hs,1,2);
  // smooth signed distance to the coastline (removes stairs on every shore and lake)
  const sdl=new Float32Array(MW*MH),sdw=new Float32Array(MW*MH);
  for(let i=0;i<sdl.length;i++){const L_=own[i]>=0;sdl[i]=L_?INF:0;sdw[i]=L_?0:INF}
  edt(sdl,MW,MH);edt(sdw,MW,MH);
  const cs=new Float32Array(MW*MH);for(let i=0;i<cs.length;i++)cs[i]=own[i]>=0?Math.sqrt(sdl[i])-.5:-(Math.sqrt(sdw[i])-.5);
  if(!opts.tri)blur(cs,2,2);
  const EV=new Float32Array(MW*MH);for(let i=0;i<EV.length;i++){const d=(H[i]-T)/top;EV[i]=Math.max(.002,Math.max(0,d)*.12+Mf[i]*.85*sstep(0,.05,d))}
  blur(EV,2,3);
  const tf=new Float32Array(MW*MH*4);
  const Lx=-.55,Ly=-.65,Lz=.52;
  for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){
    const i=y*MW+x,h=H[i];
    const gx=(Hs[y*MW+Math.min(MW-1,x+1)]-Hs[y*MW+Math.max(0,x-1)])*32,gy=(Hs[Math.min(MH-1,y+1)*MW+x]-Hs[Math.max(0,y-1)*MW+x])*32;
    const nl=Math.hypot(gx,gy,1);const lit=(-gx*Lx-gy*Ly+Lz)/nl/Lz;const lit2=(gx*.4-gy*.3+.85)/nl/.85;
    {const ev=EV[i],wv=Math.min((h-T)/bot,-.001),c_=cs[i];tf[i*4]=c_>0?lerp(c_*.004,Math.max(ev,Math.min(c_*.004,.02)),sstep(2,8,c_)):lerp(c_*.004,Math.min(wv,c_*.004),sstep(10,40,-c_));}
    tf[i*4+1]=SQD&&TRI_K===0?SQD[Math.floor(y/TRI_S)*SQW+Math.floor(x/TRI_S)]:0;
    tf[i*4+2]=clamp(.5+(lit*.75+lit2*.25-1)*.85,0,1);
    tf[i*4+3]=noise(x*.006+20,y*.006+11)*.5+noise(x*.018,y*.018+60)*.25+.5;
  }
  const countries=[];
  for(let k=0;k<n;k++){
    let x=cx[k]/area[k],y=cy[k]/area[k];
    let ix=Math.round(x),iy=Math.round(y);
    if(own[iy*MW+ix]!==k){ // snap to nearest owned pixel, prefer interior
      let bd=1e18;for(let yy=0;yy<MH;yy+=3)for(let xx=0;xx<MW;xx+=3){if(own[yy*MW+xx]===k){const d=(xx-x)**2+(yy-y)**2;if(d<bd){bd=d;ix=xx;iy=yy}}}
    }
    if(Math.hypot(ix-seeds[k].x,iy-seeds[k].y)<40){const ny=iy+(iy<seeds[k].y?-34:34);if(ny>0&&ny<MH&&own[ny*MW+ix]===k)iy=ny}
    const nbrs=[...adj[k].entries()].filter(e=>e[1]>6).map(e=>e[0]);
    countries.push({idx:k,name:seeds[k].name,area:area[k],lx:ix,ly:iy,cap:{x:seeds[k].x,y:seeds[k].y},neighbors:nbrs,landShare:area[k]/landCount});
  }
  prog(.75,"Готово");
  const mtn=new Float32Array(NW*NH);for(let cy=0;cy<NH;cy++)for(let cx=0;cx<NW;cx++)mtn[cy*NW+cx]=Mf[Math.floor((cy+.5)*MH/NH)*MW+Math.floor((cx+.5)*MW/NW)];
  return {own,tf,hid,hb,lines,land2,countries,seed,landCount,H,T,top,mtn};
}
let TRI_S=10,TRI_K=.5,TRI_H=TRI_S*Math.sqrt(3)/2;
// sq=true: right triangles = every square of the grid split by its diagonal (logistics board)
function setTriLattice(sq){TRI_K=sq?0:.5;TRI_H=sq?TRI_S:TRI_S*Math.sqrt(3)/2;SQD=null}
/* square lattice with an adaptive diagonal per square: the split ("/" or "\") that best follows the real coastline */
let SQD=null,SQW=0,SQH=0;
let SQL=null;
function sqBuild(src){SQW=Math.ceil(MW/TRI_S);SQH=Math.ceil(MH/TRI_S);SQD=new Uint8Array(SQW*SQH);SQL=new Int16Array(SQW*SQH*2);
  const at=(x,y)=>{x=clamp(Math.floor(x),0,MW-1);y=clamp(Math.floor(y),0,MH-1);return src[y*MW+x]};
  // 1. every square gets the majority label of its area
  const C=new Int16Array(SQW*SQH),m=new Map();
  for(let j=0;j<SQH;j++)for(let i=0;i<SQW;i++){m.clear();let b=-1,bv=-1;for(let v=0;v<4;v++)for(let u=0;u<4;u++){const o=at((i+(u+.5)/4)*TRI_S,(j+(v+.5)/4)*TRI_S);const c=(m.get(o)||0)+1;m.set(o,c);if(c>bv){bv=c;b=o}}C[j*SQW+i]=b}
  let L=(i,j)=>i<0||j<0||i>=SQW||j>=SQH?-1:C[j*SQW+i];
  // 2. clean-up: a square that differs from 3+ of its 4 neighbours (which agree) takes their label — no one-cell spikes or pits
  for(let it=0;it<3;it++){const S=C.slice();const Ls=(i,j)=>i<0||j<0||i>=SQW||j>=SQH?-1:S[j*SQW+i];let ch=0;
    for(let j=0;j<SQH;j++)for(let i=0;i<SQW;i++){const c=S[j*SQW+i],nb=[Ls(i,j-1),Ls(i+1,j),Ls(i,j+1),Ls(i-1,j)];const cnt=new Map();for(const q of nb)if(q!==c)cnt.set(q,(cnt.get(q)||0)+1);
      for(const [q,v] of cnt)if(v>=3){C[j*SQW+i]=q;ch++;break}}if(!ch)break}
  // 3. real staircase corners only: both opposite sides continue this square, and the diagonal neighbour confirms the corner
  for(let j=0;j<SQH;j++)for(let i=0;i<SQW;i++){const k=j*SQW+i,c=C[k],n=L(i,j-1),e=L(i+1,j),so=L(i,j+1),w=L(i-1,j),ne=L(i+1,j-1),se=L(i+1,j+1),sw=L(i-1,j+1),nw=L(i-1,j-1);let d=0,h0=c,h1=c;
    if(n===e&&n<c&&so===c&&w===c&&ne===n){d=1;h0=n}          // top-right half goes to the neighbour
    else if(e===so&&e<c&&n===c&&w===c&&se===e){d=0;h1=e}     // bottom-right
    else if(so===w&&so<c&&n===c&&e===c&&sw===so){d=1;h1=so}  // bottom-left
    else if(w===n&&w<c&&e===c&&so===c&&nw===w){d=0;h0=w}     // top-left
    SQD[k]=d;SQL[k*2]=h0;SQL[k*2+1]=h1}}
function sqHalf(x,y){const i=Math.floor(x/TRI_S),j=Math.floor(y/TRI_S),fx=x/TRI_S-i,fy=y/TRI_S-j,d=SQD&&i>=0&&j>=0&&i<SQW&&j<SQH?SQD[j*SQW+i]:0;
  const h=d?(fx>fy?0:1):(fx+fy<1?0:1);const c=d?(h?[1/3,2/3]:[2/3,1/3]):(h?[2/3,2/3]:[1/3,1/3]);return[i,j,d,h,(i+c[0])*TRI_S,(j+c[1])*TRI_S]}
function triCenter(x,y){if(TRI_K===0&&SQD){const q=sqHalf(x,y);return[q[4],q[5]]}
  const j=y/TRI_H,i=x/TRI_S-j*TRI_K,fi=Math.floor(i),fj=Math.floor(j),up=(i-fi)+(j-fj)>1,ci=fi+(up?2/3:1/3),cj=fj+(up?2/3:1/3);return[(ci+cj*TRI_K)*TRI_S,cj*TRI_H]}
function triLab(own,x,y){const c=triCenter(x,y),X=Math.floor(c[0]),Y=Math.floor(c[1]);if(X<0||Y<0||X>=MW||Y>=MH)return -1;return own[Y*MW+X]}
function extractTriLines(own){
  if(TRI_K===0&&SQD)return extractSqLines(own);
  const J=Math.ceil(MH/TRI_H)+1,I0=-Math.ceil(J*TRI_K)-2,I1=Math.ceil(MW/TRI_S)+2,JW=J+4;
  const lab=(i,j,up)=>{const ci=i+(up?2/3:1/3),cj=j+(up?2/3:1/3);const X=Math.floor((ci+cj*TRI_K)*TRI_S),Y=Math.floor(cj*TRI_H);if(X<0||Y<0||X>=MW||Y>=MH)return 0;const o=own[Y*MW+X];return o<0?0:o+1};
  const vid=(i,j)=>(i-I0+2)*JW+(j+1),vx=v=>{const i=Math.floor(v/JW)-2+I0,j=v%JW-1;return[(i+j*TRI_K)*TRI_S,j*TRI_H]};
  const groups=new Map(),add=(a,b,v1,v2)=>{if(a===b)return;if(a>b){const t=a;a=b;b=t}const k=a*256+b;let g=groups.get(k);if(!g){g=[];groups.set(k,g)}g.push(v1,v2)};
  for(let j=-1;j<=J;j++)for(let i=I0;i<=I1;i++){const L=lab(i,j,0);
    add(L,lab(i,j,1),vid(i+1,j),vid(i,j+1));add(L,lab(i,j-1,1),vid(i,j),vid(i+1,j));add(L,lab(i-1,j,1),vid(i,j),vid(i,j+1))}
  const res=[];
  for(const [key,e] of groups){const a=key>>8,b=key&255,ne=e.length/2,adj=new Map();
    for(let q=0;q<ne;q++)for(const v of [e[q*2],e[q*2+1]]){let l=adj.get(v);if(!l){l=[];adj.set(v,l)}l.push(q)}
    const used=new Uint8Array(ne),chains=[];
    const walk=(start,ei)=>{const pts=[start];let v=start;while(ei>=0&&!used[ei]){used[ei]=1;const nv=e[ei*2]===v?e[ei*2+1]:e[ei*2];pts.push(nv);v=nv;const l=adj.get(v);if(l.length!==2)break;ei=l[0]===ei?l[1]:l[0]}return pts};
    for(const [v,l] of adj)if(l.length!==2)for(const ei of l)if(!used[ei])chains.push(walk(v,ei));
    for(let q=0;q<ne;q++)if(!used[q])chains.push(walk(e[q*2],q));
    for(const ch of chains){const P=ch.map(vx),out=[P[0]];for(let k=1;k<P.length-1;k++){const A=out[out.length-1],B=P[k],C=P[k+1];if(Math.abs((B[0]-A[0])*(C[1]-A[1])-(B[1]-A[1])*(C[0]-A[0]))>1e-3)out.push(B)}out.push(P[P.length-1]);
      const pts=[];for(const [x,y] of out){const w=pxToWorld(clamp(x,0,MW),clamp(y,0,MH));pts.push(w[0],w[1])}res.push({a,b,p:new Float32Array(pts)})}}
  return res;
}
function extractSqLines(own){
  const S=TRI_S,JW=SQH+3,vid=(i,j)=>(i+1)*JW+(j+1),vx=v=>[(Math.floor(v/JW)-1)*S,(v%JW-1)*S];
  const lab=(i,j,h)=>{if(i<0||j<0||i>=SQW||j>=SQH)return 0;const d=SQD[j*SQW+i],c=d?(h?[1/3,2/3]:[2/3,1/3]):(h?[2/3,2/3]:[1/3,1/3]);const X=Math.min(MW-1,Math.floor((i+c[0])*S)),Y=Math.min(MH-1,Math.floor((j+c[1])*S));const o=own[Y*MW+X];return o<0?0:o+1};
  // which half touches each side: "/" (d=0): h0 top+left, h1 bottom+right;  "\" (d=1): h0 top+right, h1 bottom+left
  const side=(i,j,s_)=>{if(i<0||j<0||i>=SQW||j>=SQH)return 0;const d=SQD[j*SQW+i];const h=s_==="t"?0:s_==="b"?1:s_==="l"?(d?1:0):(d?0:1);return lab(i,j,h)};
  const groups=new Map(),add=(a,b,v1,v2)=>{if(a===b)return;if(a>b){const t=a;a=b;b=t}const k=a*256+b;let g=groups.get(k);if(!g){g=[];groups.set(k,g)}g.push(v1,v2)};
  for(let j=-1;j<SQH;j++)for(let i=-1;i<SQW;i++){
    if(i>=0&&j>=0){const d=SQD[j*SQW+i];add(lab(i,j,0),lab(i,j,1),d?vid(i,j):vid(i+1,j),d?vid(i+1,j+1):vid(i,j+1))}
    if(j>=0)add(side(i,j,"r"),side(i+1,j,"l"),vid(i+1,j),vid(i+1,j+1));
    if(i>=0)add(side(i,j,"b"),side(i,j+1,"t"),vid(i,j+1),vid(i+1,j+1))}
  const res=[];
  for(const [key,e] of groups){const a=key>>8,b=key&255,ne=e.length/2,adj=new Map();
    for(let q=0;q<ne;q++)for(const v of [e[q*2],e[q*2+1]]){let l=adj.get(v);if(!l){l=[];adj.set(v,l)}l.push(q)}
    const used=new Uint8Array(ne),chains=[];
    const walk=(start,ei)=>{const pts=[start];let v=start;while(ei>=0&&!used[ei]){used[ei]=1;const nv=e[ei*2]===v?e[ei*2+1]:e[ei*2];pts.push(nv);v=nv;const l=adj.get(v);if(l.length!==2)break;ei=l[0]===ei?l[1]:l[0]}return pts};
    for(const [v,l] of adj)if(l.length!==2)for(const ei of l)if(!used[ei])chains.push(walk(v,ei));
    for(let q=0;q<ne;q++)if(!used[q])chains.push(walk(e[q*2],q));
    for(const ch of chains){const P=ch.map(vx),out=[P[0]];for(let k=1;k<P.length-1;k++){const A=out[out.length-1],B=P[k],C=P[k+1];if(Math.abs((B[0]-A[0])*(C[1]-A[1])-(B[1]-A[1])*(C[0]-A[0]))>1e-3)out.push(B)}out.push(P[P.length-1]);
      const pts=[];for(const [x,y] of out){const w=pxToWorld(clamp(x,0,MW),clamp(y,0,MH));pts.push(w[0],w[1])}res.push({a,b,p:new Float32Array(pts)})}}
  return res;
}
const pxToWorld=(x,y)=>[x/MW*WX-WX/2,y/MH*WZ-WZ/2];
function extractLines(L,W,Hh){
  const VW=W+1,groups=new Map();
  const add=(a,b,v1,v2)=>{if(a>b){const t=a;a=b;b=t}const k=a*256+b;let g=groups.get(k);if(!g){g=[];groups.set(k,g)}g.push(v1,v2)};
  for(let Y=0;Y<Hh;Y++)for(let X=0;X<W;X++){const i=Y*W+X,a=L[i];
    if(X<W-1){const b=L[i+1];if(a!==b)add(a,b,Y*VW+X+1,(Y+1)*VW+X+1)}
    if(Y<Hh-1){const b=L[i+W];if(a!==b)add(a,b,(Y+1)*VW+X,(Y+1)*VW+X+1)}}
  const out=[];
  for(const [key,e] of groups){
    const a=key>>8,b=key&255,ne=e.length/2,adj=new Map();
    for(let j=0;j<ne;j++){for(const v of [e[j*2],e[j*2+1]]){let l=adj.get(v);if(!l){l=[];adj.set(v,l)}l.push(j)}}
    const used=new Uint8Array(ne);
    const walk=(start,ei)=>{const pts=[start];let v=start;while(ei>=0&&!used[ei]){used[ei]=1;const nv=e[ei*2]===v?e[ei*2+1]:e[ei*2];pts.push(nv);v=nv;const l=adj.get(v);if(l.length!==2)break;ei=l[0]===ei?l[1]:l[0]}return pts};
    for(const [v,l] of adj)if(l.length!==2)for(const ei of l)if(!used[ei])out.push({a,b,v:walk(v,ei)});
    for(let ei=0;ei<ne;ei++)if(!used[ei])out.push({a,b,v:walk(e[ei*2],ei)});
  }
  const res=[];
  for(const o of out){
    const n=o.v.length;if(n<2)continue;let xs=new Float32Array(n),ys=new Float32Array(n);
    for(let i=0;i<n;i++){xs[i]=o.v[i]%VW;ys[i]=Math.floor(o.v[i]/VW)}
    const closed=o.v[0]===o.v[n-1]&&n>3;
    for(let it=0;it<12;it++){const nx=xs.slice(),ny=ys.slice();
      for(let i=0;i<n;i++){let p=i-1,q=i+1;if(i===0||i===n-1){if(!closed)continue;p=n-2;q=1}
        nx[i]=xs[i]*.5+(xs[p]+xs[q])*.25;ny[i]=ys[i]*.5+(ys[p]+ys[q])*.25}
      if(closed){nx[n-1]=nx[0];ny[n-1]=ny[0]}xs=nx;ys=ny}
    // Douglas-Peucker simplification
    const keep=new Uint8Array(n);keep[0]=keep[n-1]=1;let st=[[0,n-1]];
    if(closed){let mi=1,md=-1;for(let i=1;i<n-1;i++){const dd=(xs[i]-xs[0])**2+(ys[i]-ys[0])**2;if(dd>md){md=dd;mi=i}}keep[mi]=1;st=[[0,mi],[mi,n-1]]}
    while(st.length){const [i0,i1]=st.pop();let md=0,mi=-1;const dx=xs[i1]-xs[i0],dy=ys[i1]-ys[i0],dl=Math.hypot(dx,dy)||1;
      for(let i=i0+1;i<i1;i++){const dd=Math.abs((xs[i]-xs[i0])*dy-(ys[i]-ys[i0])*dx)/dl;if(dd>md){md=dd;mi=i}}
      if(md>.28){keep[mi]=1;st.push([i0,mi],[mi,i1])}}
    const pts=[];for(let i=0;i<n;i++)if(keep[i])pts.push(xs[i]/W*WX-WX/2,ys[i]/Hh*WZ-WZ/2);
    res.push({a:o.a,b:o.b,p:new Float32Array(pts)});
  }
  return res;
}

/* ================= WEBGL RENDERER ================= */
const VS=`#version 300 es
in vec2 a;uniform mat4 vp;out vec3 wp;
void main(){wp=vec3(a.x,0.,a.y);gl_Position=vp*vec4(wp,1.);}`;
const glf=v=>{const s=String(+(+v).toFixed(6));return s.includes(".")||s.includes("e")?s:s+"."};
const FSsrc=()=>`#version 300 es
precision highp float;precision highp usampler2D;
in vec3 wp;out vec4 o;
uniform sampler2D t0;uniform sampler2D tb;uniform usampler2D t1;uniform usampler2D t2;uniform float flash[48];uniform float triS;uniform float lgrid;uniform float wallOff;uniform float hasOcc;
uniform vec3 col[120];uniform int hov,sel,me;uniform vec3 eye;uniform float time;uniform float wfx;
const vec2 TS=vec2(${glf(MW*2)},${glf(MH*2)});
float gridl(vec2 p,float s,float w){vec2 q=p/s;vec2 g=abs(fract(q-.5)-.5)/fwidth(q);return 1.-min(min(g.x,g.y)/w,1.);}
float lgr(vec2 p,float s,float w){vec2 q=p/s;vec2 fw=fwidth(q);float fade=1.-smoothstep(.12,.33,max(fw.x,fw.y));vec2 g=abs(fract(q-.5)-.5)/max(fw,vec2(1e-5));return (1.-min(min(g.x,g.y)/w,1.))*fade;}
uint idAt(vec2 uv){return texture(t1,uv).r&127u;}
float hsh(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);vec2 u=f*f*(3.-2.*f);return mix(mix(hsh(i),hsh(i+vec2(1,0)),u.x),mix(hsh(i+vec2(0,1)),hsh(i+vec2(1,1)),u.x),u.y);}
// procedural micro-relief: ridged + smooth octaves, each faded out once it would be smaller than a pixel
float relief(vec2 p,float pw,float ridge){
  vec2 q=p+vec2(vn(p*3.1),vn(p*3.1+7.3))*.18;
  float s=0.,a=.5,f=1.;
  for(int i=0;i<6;i++){
    float w=1.-smoothstep(.2,.55,pw*9.*f);
    float n=vn(q*9.*f);
    float r=1.-abs(n*2.-1.);
    s+=a*w*mix(n,r,ridge*.85);
    q=mat2(.8,-.6,.6,.8)*q+vec2(3.1,1.7);f*=2.03;a*=.5;
  }
  return s;
}
vec3 cc(uint id){return id>=122u?vec3(.36,.385,.41):id==121u?vec3(.50,.50,.47):id>0u?col[int(id)-1]:vec3(.42,.45,.48);}
${TRI_K===0?`vec3 triInfo(vec2 uv){vec2 MWH=vec2(${glf(MW)},${glf(MH)});vec2 q=uv*MWH/triS;vec2 fl=floor(q),fr=q-fl;float dg=textureLod(t0,(fl+.5)*triS/MWH,0.).g;float up;vec2 c;if(dg>.5){up=step(fr.y,fr.x);c=mix(vec2(1./3.,2./3.),vec2(2./3.,1./3.),up);}else{up=step(1.,fr.x+fr.y);c=mix(vec2(1./3.),vec2(2./3.),up);}return vec3((fl+c)*triS/MWH,up);}
vec2 triCuv(vec2 q){return triInfo(q).xy;}
vec2 triCuvOld(vec2 q){vec2 pp=q*vec2(${glf(MW)},${glf(MH)});`:`vec2 triCuv(vec2 q){vec2 pp=q*vec2(${glf(MW)},${glf(MH)});`}float th=triS*${glf(TRI_H/TRI_S)};float tj=pp.y/th,ti=pp.x/triS-tj*${glf(TRI_K)};vec2 fl=floor(vec2(ti,tj));float up=step(1.,ti-fl.x+tj-fl.y);vec2 c2=fl+mix(vec2(1./3.),vec2(2./3.),up);return vec2((c2.x+c2.y*${glf(TRI_K)})*triS,c2.y*th)/vec2(${glf(MW)},${glf(MH)});}
void main(){
  vec2 uv=(wp.xz+vec2(${glf(WX/2)},${glf(WZ/2)}))/vec2(${glf(WX)},${glf(WZ)});
  vec3 bg=vec3(.022,.038,.055);
  vec3 c;
  vec2 gq=wp.xz+vec2(${glf(WX/2)},${glf(WZ/2)});float g1=gridl(gq,.5,1.),g2=gridl(gq,2.5,1.2);
  vec2 e2=min(uv,1.-uv)*vec2(${glf(WX)},${glf(WZ)});float sd=min(e2.x,e2.y);float fe=max(fwidth(sd),1e-5);
  float mask=smoothstep(-fe*.6,fe*.6,sd);
  vec3 cf;
  {vec2 d=max(abs(wp.xz)-vec2(${glf(WX/2)},${glf(WZ/2)}),0.);float dd=length(d);
   cf=bg+vec3(.25,.45,.6)*(g1*.05+g2*.1);
   cf*=.35+.65*smoothstep(0.,.9,dd);
   cf+=vec3(.05,.12,.18)*exp(-dd*1.2)*.6;}
  c=cf;
  if(sd>-fe*2.){
    uv=clamp(uv,0.,1.);
    vec4 t=texture(t0,uv);
    float h=t.r,bd=texture(tb,uv).r;
    vec2 tcuv=uv;float tH=.5;
    ${TRI_K===0?`if(triS>0.){vec3 ti_=triInfo(uv);vec2 fl=floor(uv*vec2(${glf(MW)},${glf(MH)})/triS);float up=ti_.z;tcuv=ti_.xy;tH=hsh(fl*vec2(1.13,.91)+up*vec2(.37,.71));h=texture(t0,tcuv).r;}
    else `:""}if(triS>0.){vec2 pp=uv*vec2(${glf(MW)},${glf(MH)});float th=triS*${glf(TRI_H/TRI_S)};float tj=pp.y/th,ti=pp.x/triS-tj*${glf(TRI_K)};vec2 fl=floor(vec2(ti,tj)),fr=vec2(ti,tj)-fl;float up=step(1.,fr.x+fr.y);
      vec2 c2=fl+mix(vec2(1./3.),vec2(2./3.),up);tcuv=vec2((c2.x+c2.y*${glf(TRI_K)})*triS,c2.y*th)/vec2(${glf(MW)},${glf(MH)});tH=hsh(fl*vec2(1.13,.91)+up*vec2(.37,.71));h=texture(t0,tcuv).r;}
    float ha=max(length(vec2(dFdx(h),dFdy(h))),1e-5);
    float land=smoothstep(-ha*.9,ha*.9,h);${TRI_K===0?"\n    if(triS>0.)land=step(0.,h);":""}
    // ---- sea
    float depth=clamp(-h,0.,1.);
    vec3 deep=vec3(.03,.13,.24),mid=vec3(.06,.27,.42),shal=vec3(.16,.52,.66);
    vec3 w=mix(shal,mid,smoothstep(0.,.18,depth));w=mix(w,deep,smoothstep(.18,.85,depth));
    float q=depth*7.;float qd=min(fract(q),1.-fract(q));float ql=1.-smoothstep(0.,fwidth(q)*1.1,qd);
    w+=vec3(.05,.09,.11)*ql*(1.-smoothstep(.1,.9,depth))*step(.02,depth)*(1.-step(.5,triS));
    w+=vec3(.12,.22,.24)*exp(-depth*45.);
    if(triS>0.){w=w*(.84+.32*tH)+vec3(0.,.035,.045)*(tH-.5);
      /* sun glints: a few water triangles here and there light up for a moment, like ripples catching the sun */
      if(wfx>0.){float s2=hsh(tcuv*vec2(917.3,613.7)+tH);float on=step(1.-.09*wfx,s2);
        float ph=fract(time*(.18+.22*fract(s2*13.7))+tH*7.3);float gl=pow(max(0.,1.-abs(ph-.5)*9.),2.);
        w+=vec3(.42,.62,.72)*gl*on*(.55+.45*wfx)*smoothstep(.0,.04,depth);}}
    // ---- land: supersampled country fill (antialiased edges at any zoom)
    vec2 fw=fwidth(uv)*TS;float rr=max(max(fw.x,fw.y)*.5,.55);
    vec2 o1=vec2(.25,.75)*rr/TS,o2=vec2(-.75,.25)*rr/TS;
    uint i0,i1,i2,i3,id;
    if(triS>0.){id=idAt(tcuv);i0=id;i1=id;i2=id;i3=id;}else{i0=idAt(uv+o1);i1=idAt(uv-o1);i2=idAt(uv+o2);i3=idAt(uv-o2);id=idAt(uv);}
    vec3 L=(cc(i0)+cc(i1)+cc(i2)+cc(i3))*.25;
    int k=id>0u?int(id)-1:-1;
    uint su=uint(sel+1),hu=uint(hov+1);
    float fs=sel<0?0.:(float(i0==su)+float(i1==su)+float(i2==su)+float(i3==su))*.25;
    if(id==121u){vec2 hp=wp.xz*vec2(1.,1.)*55.;float st=abs(fract((hp.x+hp.y)*.5)-.5);float sw=fwidth((hp.x+hp.y)*.5);L*=1.-.14*(1.-smoothstep(.12,.12+sw*1.5,st))*(1.-smoothstep(.15,.4,sw));}
    if(hasOcc>0.){uint og=texture(t2,uv).r;
     float ofr=(float(texture(t1,uv+o1).r>=128u)+float(texture(t1,uv-o1).r>=128u)+float(texture(t1,uv+o2).r>=128u)+float(texture(t1,uv-o2).r>=128u))*.25;
     if(ofr>0.){vec3 oc=mix(L,cc(og),.32)*.86;float sv=(wp.x-wp.z)*9.;float st=abs(fract(sv)-.5);float sw=fwidth(sv);float m=(1.-smoothstep(.1-sw,.1+sw,st))*(1.-smoothstep(.3,.6,sw));oc=mix(oc,oc*.78,m);L=mix(L,oc,ofr);}
     if(og>0u&&og<121u){float f=flash[int(og)-1];if(f>0.)L=mix(L,vec3(.92,.14,.1),f*(.32+.24*sin(time*4.)));}}
    float fh=hov<0?0.:(float(i0==hu)+float(i1==hu)+float(i2==hu)+float(i3==hu))*.25;
    L*=mix(.88,1.,smoothstep(1.6,12.,bd));
    if(triS>0.)L*=.95+.1*tH;
    L+=vec3(.06)*fh;
    L=mix(L,L*1.08+vec3(.03,.05,.07)+vec3(.35,.7,.9)*(1.-smoothstep(1.2,14.,bd))*(.35+.12*sin(time*3.)),fs);
    if(lgrid>0.){float a1=lgr(wp.xz,lgrid,1.),a2=lgr(wp.xz,lgrid*5.,1.4);L=mix(L,L*.66,clamp(a1*.42+a2*.55,0.,.8));}
    c=mix(w,L,land);
    // ---- extruded land slab: visible side wall on south-facing coasts + soft drop shadow on the water
    float tpp=max(fwidth(uv).x*${glf(MW)},fwidth(uv).y*${glf(MH)});
    if(wallOff<.5&&land<.995&&triS>0.&&h>-.12&&tpp<3.){const int NS=${TRI_K===0?8:10};vec2 st=vec2(0.,.065/${glf(WZ)})/float(NS);float hit=-1.;
      for(int i=1;i<=NS;i++){if(texture(t0,triCuv(uv-st*float(i))).r>0.){hit=float(i)/float(NS);break;}}
      if(hit>0.){float f=hit;
        // faceted wall: a row of small triangles, the lower half sits under water
        float n1=vn(wp.xz*vec2(22.,9.)),n2=vn(wp.xz*vec2(61.,27.)+4.);vec3 sc=mix(vec3(.29,.22,.16),vec3(.35,.28,.21),smoothstep(.25,.75,n1*.7+n2*.3));sc=mix(sc,sc*1.18,(1.-smoothstep(0.,.12,f))*.6);
        float sub=smoothstep(.47,.53,f);sc=mix(sc,mix(sc*.7,w*.85,.5),sub);
        c=mix(c,sc,1.-land);}
}
    else if(land<.995&&triS==0.&&h>-.09&&tpp<3.){const int NS=12;vec2 st=vec2(0.,.065/${glf(WZ)})/float(NS);float hit=-1.,hp=h,hl=0.;
      for(int i=1;i<=NS;i++){float hi=texture(t0,uv-st*float(i)).r;if(hi>0.){hit=(float(i-1)+clamp(hp/(hp-hi),0.,1.))/float(NS);break;}hp=hi;hl=hi;}
      float wa=hit>0.?1.:smoothstep(-ha*1.6,0.,hl);if(hit<0.)hit=1.;
      if(wa>0.){float f=hit;float n=vn(wp.xz*vec2(7.,16.))*.65+vn(wp.xz*26.+3.)*.35;vec3 sc=mix(vec3(.36,.27,.19),vec3(.45,.41,.36),n);
        sc*=mix(1.,.5,smoothstep(0.,1.,f));sc=mix(sc,vec3(.6,.54,.46),(1.-smoothstep(0.,.1,f))*.5);c=mix(c,sc,wa*(1.-land));}
      if(wa<1.){float sh=0.;for(int i=1;i<=6;i++){float hs=texture(t0,uv-st*float(NS)*(1.+float(i)*.35)).r;if(hs>0.){sh=1.-float(i)/7.;break;}}c=mix(c,c*.55,sh*.5*(1.-wa)*(1.-land));}}
    // ---- country border: SDF line, crisp at every zoom
    float bl=max(bd-.78,0.);
    float px=max(fwidth(bd),1e-4);
    float lw=max(.75,px*.62);
    float line=1.-smoothstep(lw-px*.55,lw+px*.55,bl);
    float halo=(1.-smoothstep(lw,lw+px*2.5+1.2,bl))*.25;
    c=mix(c,c*.72,halo*land);
    // ---- coastline
    c+=vec3(.6,.8,1.)*g1*.03*(1.-land*.75)+vec3(.6,.8,1.)*g2*.05*(1.-land*.6);
    c=mix(cf,c,mask);
  }
  float fd=length(wp-eye);
  c=mix(c,bg,smoothstep(14.,34.,fd));
  o=vec4(pow(c,vec3(.95)),1.);
}`;
const Cam={tx:0,tz:.4,dist:13,yaw:0,tdist:13,ttx:0,ttz:.4};
let GL=null;
function initGL(world){
  const cv=$("#gl");const gl=cv.getContext("webgl2",{antialias:true,preserveDrawingBuffer:true});
  if(!gl){alert("WebGL2 недоступний");return}
  const sh=(t,s)=>{const o=gl.createShader(t);gl.shaderSource(o,s);gl.compileShader(o);if(!gl.getShaderParameter(o,gl.COMPILE_STATUS))console.error(gl.getShaderInfoLog(o));return o};
  const pr=gl.createProgram();gl.attachShader(pr,sh(gl.VERTEX_SHADER,VS));gl.attachShader(pr,sh(gl.FRAGMENT_SHADER,FSsrc()));gl.linkProgram(pr);
  if(!gl.getProgramParameter(pr,gl.LINK_STATUS))console.error(gl.getProgramInfoLog(pr));
  gl.useProgram(pr);
  const S=60,buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);
  gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-S,-S,S,-S,-S,S,-S,S,S,-S,S,S]),gl.STATIC_DRAW);
  const loc=gl.getAttribLocation(pr,"a");gl.enableVertexAttribArray(loc);gl.vertexAttribPointer(loc,2,gl.FLOAT,false,0,0);
  const tx0=gl.createTexture();gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,tx0);
  let data=world.tf,w=MW,h=MH,lvl=0;
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA16F,w,h,0,gl.RGBA,gl.FLOAT,data);
  while(w>1||h>1){const nw=Math.max(1,w>>1),nh=Math.max(1,h>>1),nd=new Float32Array(nw*nh*4);
    for(let y=0;y<nh;y++)for(let x=0;x<nw;x++){const x0=Math.min(w-1,x*2),x1=Math.min(w-1,x*2+1),y0=Math.min(h-1,y*2),y1=Math.min(h-1,y*2+1);
      for(let ch=0;ch<4;ch++)nd[(y*nw+x)*4+ch]=(data[(y0*w+x0)*4+ch]+data[(y0*w+x1)*4+ch]+data[(y1*w+x0)*4+ch]+data[(y1*w+x1)*4+ch])*.25}
    data=nd;w=nw;h=nh;lvl++;gl.texImage2D(gl.TEXTURE_2D,lvl,gl.RGBA16F,w,h,0,gl.RGBA,gl.FLOAT,data)}
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAX_LEVEL,lvl);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  const ext=gl.getExtension("EXT_texture_filter_anisotropic");if(ext)gl.texParameterf(gl.TEXTURE_2D,ext.TEXTURE_MAX_ANISOTROPY_EXT,4);
  world.tf=null;
  const txb=gl.createTexture();world.txb=txb;gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,txb);
  {let d=world.hb,w=MW*2,h=MH*2,l=0;gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);gl.texImage2D(gl.TEXTURE_2D,0,gl.R16F,w,h,0,gl.RED,gl.FLOAT,d);
   while(w>1||h>1){const nw=Math.max(1,w>>1),nh=Math.max(1,h>>1),nd=new Float32Array(nw*nh);
     for(let y=0;y<nh;y++)for(let x=0;x<nw;x++){const x0=Math.min(w-1,x*2),x1=Math.min(w-1,x*2+1),y0=Math.min(h-1,y*2),y1=Math.min(h-1,y*2+1);nd[y*nw+x]=(d[y0*w+x0]+d[y0*w+x1]+d[y1*w+x0]+d[y1*w+x1])*.25}
     d=nd;w=nw;h=nh;l++;gl.texImage2D(gl.TEXTURE_2D,l,gl.R16F,w,h,0,gl.RED,gl.FLOAT,d)}
   gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAX_LEVEL,l)}
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  if(ext)gl.texParameterf(gl.TEXTURE_2D,ext.TEXTURE_MAX_ANISOTROPY_EXT,4);
  world.hb=null;
  const tx1=gl.createTexture();gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,tx1);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);
  world.hidOrig=world.hid.slice();world.ownOrig=world.own.slice();gl.texImage2D(gl.TEXTURE_2D,0,gl.R8UI,MW*2,MH*2,0,gl.RED_INTEGER,gl.UNSIGNED_BYTE,world.hid);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  const U=n=>gl.getUniformLocation(pr,n);
  gl.uniform1i(U("t0"),0);gl.uniform1i(U("t1"),1);gl.uniform1i(U("tb"),2);
  GL={tx0,txb,gl,pr,cv,u:{vp:U("vp"),col:U("col"),hov:U("hov"),sel:U("sel"),me:U("me"),eye:U("eye"),time:U("time")},vp:null,eye:[0,0,0],hover:-1};
  {const tx2=gl.createTexture();gl.activeTexture(gl.TEXTURE3);gl.bindTexture(gl.TEXTURE_2D,tx2);gl.texImage2D(gl.TEXTURE_2D,0,gl.R8UI,MW*2,MH*2,0,gl.RED_INTEGER,gl.UNSIGNED_BYTE,world.hidOrig);
   gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
   gl.uniform1i(gl.getUniformLocation(pr,"t2"),3);GL.tx1=tx1;GL.tx2=tx2;GL.u.flash=gl.getUniformLocation(pr,"flash");GL.u.triS=gl.getUniformLocation(pr,"triS");GL.u.wfx=gl.getUniformLocation(pr,"wfx");GL.u.wallOff=gl.getUniformLocation(pr,"wallOff");GL.u.lgrid=gl.getUniformLocation(pr,"lgrid");GL.u.hasOcc=gl.getUniformLocation(pr,"hasOcc");}
  bindMapInput();
}
function setMapColors(arr){REDRAW=true;if(!GL)return;const f=new Float32Array(120*3);arr.forEach((c,i)=>{f[i*3]=c[0];f[i*3+1]=c[1];f[i*3+2]=c[2]});GL.gl.uniform3fv(GL.u.col,f)}
function hex3(h){const n=parseInt(h.slice(1),16);return[(n>>16&255)/255,(n>>8&255)/255,(n&255)/255]}

/* --- matrix helpers --- */
function persp(f,a,n,fa){const t=1/Math.tan(f/2);return[t/a,0,0,0,0,t,0,0,0,0,(fa+n)/(n-fa),-1,0,0,2*fa*n/(n-fa),0]}
function sub(a,b){return[a[0]-b[0],a[1]-b[1],a[2]-b[2]]}
function cross(a,b){return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
function norm(a){const l=Math.hypot(...a);return[a[0]/l,a[1]/l,a[2]/l]}
function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]}
function lookAt(e,t,u){const z=norm(sub(e,t)),x=norm(cross(u,z)),y=cross(z,x);return[x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dot(x,e),-dot(y,e),-dot(z,e),1]}
function mul(a,b){const o=new Array(16);for(let i=0;i<4;i++)for(let j=0;j<4;j++){let s=0;for(let k=0;k<4;k++)s+=a[k*4+j]*b[i*4+k];o[i*4+j]=s}return o}
const FOV=38*Math.PI/180;
function camPitch(){return lerp(.8,1.1,clamp((Cam.dist-3)/15,0,1))}
function camEye(){const p=camPitch();return[Cam.tx+Math.sin(Cam.yaw)*Math.cos(p)*Cam.dist,Math.sin(p)*Cam.dist,Cam.tz+Math.cos(Cam.yaw)*Math.cos(p)*Cam.dist]}
function project(x,y,z){const m=GL.vp;const cx=m[0]*x+m[4]*y+m[8]*z+m[12],cy=m[1]*x+m[5]*y+m[9]*z+m[13],cw=m[3]*x+m[7]*y+m[11]*z+m[15];if(!(cw>1e-4))return null;const px=(cx/cw*.5+.5)*innerWidth,py=(1-(cy/cw*.5+.5))*innerHeight;if(!(Math.abs(px)<4e5&&Math.abs(py)<4e5))return null;return{x:px,y:py,w:cw}}
function pickPlane(sx,sy){
  const e=camEye(),f=norm(sub([Cam.tx,0,Cam.tz],e)),r=norm(cross(f,[0,1,0])),u=cross(r,f);
  const th=Math.tan(FOV/2),asp=innerWidth/innerHeight,nx=sx/innerWidth*2-1,ny=1-sy/innerHeight*2;
  const d=[f[0]+r[0]*nx*th*asp+u[0]*ny*th,f[1]+r[1]*nx*th*asp+u[1]*ny*th,f[2]+r[2]*nx*th*asp+u[2]*ny*th];
  if(d[1]>=-1e-4)return null;const t=-e[1]/d[1];return[e[0]+d[0]*t,e[2]+d[2]*t];
}
let VB_K="",VB=null;
function vbox(){const k=Cam.tx.toFixed(4)+","+Cam.tz.toFixed(4)+","+Cam.dist.toFixed(4)+","+Cam.yaw.toFixed(4)+","+innerWidth+"x"+innerHeight;if(k===VB_K)return VB;VB_K=k;
  let x0=1e9,x1=-1e9,z0=1e9,z1=-1e9;for(const [sx,sy] of [[0,0],[innerWidth,0],[0,innerHeight],[innerWidth,innerHeight],[innerWidth/2,0]]){const p=pickPlane(sx,sy);if(!p){VB=null;return null}x0=Math.min(x0,p[0]);x1=Math.max(x1,p[0]);z0=Math.min(z0,p[1]);z1=Math.max(z1,p[1])}
  const mx=(x1-x0)*.08+.3,mz=(z1-z0)*.08+.3;VB={x0:x0-mx,x1:x1+mx,z0:z0-mz,z1:z1+mz};return VB}
function bbOf(o,p){if(!o._bb){let a=1e9,b=-1e9,c=1e9,d=-1e9;for(let i=0;i<p.length;i+=2){const x=p[i],z=p[i+1];if(x<a)a=x;if(x>b)b=x;if(z<c)c=z;if(z>d)d=z}Object.defineProperty(o,"_bb",{value:[a,b,c,d],enumerable:false,writable:true})}return o._bb}
function inVB(o,p,vb){if(!vb)return true;const b=bbOf(o,p);return !(b[1]<vb.x0||b[0]>vb.x1||b[3]<vb.z0||b[2]>vb.z1)}
function worldToCountry(p){if(!p)return -1;const r_=worldToCountryRaw(p);return r_===NEU?-2:r_}
function worldToCountryRaw(p){const x=Math.floor((p[0]+WX/2)/WX*MW),y=Math.floor((p[1]+WZ/2)/WZ*MH);if(x<0||y<0||x>=MW||y>=MH)return -1;return G.world.own[y*MW+x]}

function bindMapInput(){
  if(window.__mapBound)return;window.__mapBound=true;
  const cv=GL.cv;let down=null,moved=false;
  cv.addEventListener("pointerdown",e=>{down={x:e.clientX,y:e.clientY,lx:e.clientX,ly:e.clientY};moved=false;cv.setPointerCapture(e.pointerId)});
  cv.addEventListener("pointermove",e=>{
    if(down){
      if(Math.hypot(e.clientX-down.x,e.clientY-down.y)>4){moved=true;cv.classList.add("drag")}
      if(moved){const p0=pickPlane(down.lx,down.ly),p1=pickPlane(e.clientX,e.clientY);down.lx=e.clientX;down.ly=e.clientY;
        if(p0&&p1){let dx=p0[0]-p1[0],dz=p0[1]-p1[1];const l=Math.hypot(dx,dz),mx=Cam.dist*.12;if(l>mx){dx*=mx/l;dz*=mx/l}
          const mx_=Math.min(WX/2-.5,Cam.dist*.28),mz_=Math.min(WZ/2-.4,Cam.dist*.2);Cam.tx=clamp(Cam.tx+dx,-WX/2+mx_,WX/2-mx_);Cam.tz=clamp(Cam.tz+dz,-WZ/2+mz_,WZ/2-mz_*.3);Cam.ttx=Cam.tx;Cam.ttz=Cam.tz}}
    }else{const k=worldToCountry(pickPlane(e.clientX,e.clientY));GL.hover=k;cv.style.cursor=k>=0?"pointer":"grab"}
  });
  cv.addEventListener("pointerup",e=>{cv.classList.remove("drag");if(down&&!moved){if(coClick(e.clientX,e.clientY))return void(down=null);const k=worldToCountry(pickPlane(e.clientX,e.clientY));onMapClick(k)}down=null});
  cv.addEventListener("pointerleave",()=>{GL.hover=-1});
  cv.addEventListener("wheel",e=>{e.preventDefault();Cam.tdist=clamp(Cam.tdist*(e.deltaY>0?1.12:.89),G.co?.55:4,WX*1.25)},{passive:false});
  addEventListener("keydown",e=>{if(e.target.tagName==="INPUT")return;const s=Cam.dist*.06;if(e.key==="ArrowLeft"||e.key==="a")Cam.ttx-=s;if(e.key==="ArrowRight"||e.key==="d")Cam.ttx+=s;if(e.key==="ArrowUp"||e.key==="w")Cam.ttz-=s;if(e.key==="ArrowDown"||e.key==="s")Cam.ttz+=s;if(e.key==="q")Cam.yaw-=.08;if(e.key==="e")Cam.yaw+=.08;});
}
function flyTo(k){const c=G.C[k];const [x,z]=pxToWorld(c.geo.lx,c.geo.ly);Cam.ttx=x;Cam.ttz=z+.3;Cam.tdist=Math.min(Cam.tdist,8)}

function renderFrame(t){
  if(!GL)return;const gl=GL.gl,cv=GL.cv;
  const dpr=renderDpr(),W=window.FORCE_RES?FORCE_RES[0]:Math.floor(innerWidth*dpr),H=window.FORCE_RES?FORCE_RES[1]:Math.floor(innerHeight*dpr);
  if(cv.width!==W||cv.height!==H){cv.width=W;cv.height=H}
  {const dt=clamp(t-(GL.camT||t-16.7),1,50);GL.camT=t;const k=window.FORCE_RES?.15:1-Math.pow(.85,dt/16.7); /* the same glide per second at any frame rate */
   Cam.dist+=(Cam.tdist-Cam.dist)*k;Cam.tx+=(Cam.ttx-Cam.tx)*k;Cam.tz+=(Cam.ttz-Cam.tz)*k;}
  const e=camEye();GL.eye=e;
  const v=lookAt(e,[Cam.tx,0,Cam.tz],[0,1,0]),p=persp(FOV,W/H,.1,100);GL.vp=mul(p,v);
  gl.viewport(0,0,W,H);gl.uniformMatrix4fv(GL.u.vp,false,new Float32Array(GL.vp));
  gl.uniform3fv(GL.u.eye,e);gl.uniform1f(GL.u.time,t/1000);if(GL.u.wfx)gl.uniform1f(GL.u.wfx,G.tri&&G.co?clamp(SET.wfx??.5,0,1):0);
  if(GL.u.triS)gl.uniform1f(GL.u.triS,G.tri?TRI_S:0);
  if(GL.u.hasOcc){if(!GL.occT||performance.now()-GL.occT>1000){GL.occT=performance.now();GL.occ=Object.values(G.flash||{}).some(v=>v>G.day)}gl.uniform1f(GL.u.hasOcc,GL.occ?1:0)}
  if(GL.u.wallOff)gl.uniform1f(GL.u.wallOff,G.co&&G.board?1:0);
  if(GL.u.lgrid)gl.uniform1f(GL.u.lgrid,G.co&&!G.board&&UI.mode==="grid"?.08:0);
  
  gl.uniform1i(GL.u.hov,GL.hover);gl.uniform1i(GL.u.sel,UI.selP!=null?-1:(UI.sel??-1));gl.uniform1i(GL.u.me,G.me??-1);
  gl.drawArrays(gl.TRIANGLES,0,6);
  guard("Підписи мапи",updateOverlay);
}
