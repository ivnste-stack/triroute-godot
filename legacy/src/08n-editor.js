/* =====================================================================
   MAP EDITOR (logistics board). The world is made of lattice triangles: SQD holds each square's
   diagonal, SQL the owner of each half (-1 = sea). Every tool edits SQL / towns / roads; the world
   textures and borders are then rebuilt from SQL. Opened before the company starts: for a custom
   world (an empty ocean) or to touch up a generated one.
   ===================================================================== */
const ED={on:false,tool:"sel",sel:-1,selT:-1,brush:1,poly:[],road:[],roadMode:"road",townType:"town",undo:[],roadsEdited:false,stroke:null,painting:false,hover:null,busy:false,resolve:null,capFor:-1};
const ED_TOOLS=[["sel","Вибір","eye","Клік по державі чи поселенню: назва, колір, столиця, порти, видалення"],["line","Кордон","pin","Клікайте по вузлах сітки. Коли лінія замкнеться — нова територія"],["state","Створити державу","flag","Клік по території: назвати державу й обрати столицю"],
 ["paint","Пензель держави","plus","Затисніть і ведіть: земля обраної держави"],["sea","Море","wave","Затисніть і ведіть: перетворити сушу на море"],["isl","Острів → державі","anchor","Клік по острову: приєднати його до обраної держави"],["islDel","Стерти острів","trash","Клік по острову: прибрати його"],
 ["town","Поселення","building","Клік по суші: нове поселення"],["townDel","Стерти поселення","close","Клік по поселенню: прибрати"],["road","Дорога","road","Клікайте точки: дорога прокладеться між ними. Esc — завершити"],["roadDel","Стерти дорогу","trash","Клік по дорозі чи колії: прибрати"]];
const edW=(i,j)=>[-WX/2+i*CST,-WZ/2+j*CST];
const edTri=(k,h)=>k*2+h;
function edTriCentre(t){const k=t>>1,h=t&1,i=k%SQW,j=(k/SQW)|0,d=SQD[k],c=d?(h?[1/3,2/3]:[2/3,1/3]):(h?[2/3,2/3]:[1/3,1/3]);return[-WX/2+(i+c[0])*CST,-WZ/2+(j+c[1])*CST]}
function edTriAt(wx,wz){const px=(wx+WX/2)/WX*MW,py=(wz+WZ/2)/WZ*MH;if(px<0||py<0||px>=MW||py>=MH)return -1;const q=sqHalf(px,py);return (q[1]*SQW+q[0])*2+q[3]}
function edTriNb(t){const k=t>>1,h=t&1,i=k%SQW,j=(k/SQW)|0,d=SQD[k],o=[k*2+(1-h)];const sq=(ii,jj)=>ii>=0&&jj>=0&&ii<SQW&&jj<SQH?jj*SQW+ii:-1;
  const sides=d?(h?["b","l"]:["t","r"]):(h?["b","r"]:["t","l"]);
  for(const s of sides){if(s==="t"){const q=sq(i,j-1);if(q>=0)o.push(q*2+1)}if(s==="b"){const q=sq(i,j+1);if(q>=0)o.push(q*2)}
    if(s==="l"){const q=sq(i-1,j);if(q>=0)o.push(q*2+(SQD[q]?0:1))}if(s==="r"){const q=sq(i+1,j);if(q>=0)o.push(q*2+(SQD[q]?1:0))}}return o}
function edIsland(t){const out=[],seen=new Uint8Array(SQL.length);if(t<0||SQL[t]<0)return out;const st=[t];seen[t]=1;while(st.length){const q=st.pop();out.push(q);for(const n of edTriNb(q))if(!seen[n]&&SQL[n]>=0){seen[n]=1;st.push(n)}}return out}

/* ---------- world from triangles ---------- */
function edBlur(A,r,passes,W,Hh){const tmp=new Float32Array(A.length);for(let p=0;p<passes;p++){
  for(let y=0;y<Hh;y++){let acc=0;const row=y*W;for(let x=-r;x<=r;x++)acc+=A[row+clamp(x,0,W-1)];for(let x=0;x<W;x++){tmp[row+x]=acc/(2*r+1);acc+=A[row+Math.min(W-1,x+r+1)]-A[row+Math.max(0,x-r)]}}
  for(let x=0;x<W;x++){let acc=0;for(let y=-r;y<=r;y++)acc+=tmp[clamp(y,0,Hh-1)*W+x];for(let y=0;y<Hh;y++){A[y*W+x]=acc/(2*r+1);acc+=tmp[Math.min(Hh-1,y+r+1)*W+x]-tmp[Math.max(0,y-r)*W+x]}}}}
function worldRebuild(seed,nC){
  const own=new Int8Array(MW*MH);
  for(let y=0;y<MH;y++){const j=Math.floor(y/TRI_S),fy=(y+.5)/TRI_S-j;for(let x=0;x<MW;x++){const i=Math.floor(x/TRI_S),fx=(x+.5)/TRI_S-i,k=j*SQW+i,d=SQD[k],h=d?(fx>fy?0:1):(fx+fy<1?0:1);own[y*MW+x]=SQL[k*2+h]}}
  const HW=MW*2,HH=MH*2,hid=new Uint8Array(HW*HH);
  for(let Y=0;Y<HH;Y++){const py=(Y+.5)/2,j=Math.floor(py/TRI_S),fy=py/TRI_S-j;for(let X=0;X<HW;X++){const px=(X+.5)/2,i=Math.floor(px/TRI_S),fx=px/TRI_S-i,k=j*SQW+i,d=SQD[k],h=d?(fx>fy?0:1):(fx+fy<1?0:1),o=SQL[k*2+h];hid[Y*HW+X]=o<0?0:o+1}}
  const lines=extractTriLines(own);
  const INF=1e10,hb=new Float32Array(HW*HH);
  for(let Y=0;Y<HH;Y++)for(let X=0;X<HW;X++){const i=Y*HW+X,o=hid[i];hb[i]=INF;if(!o)continue;
    if((X>0&&hid[i-1]&&hid[i-1]!==o)||(X<HW-1&&hid[i+1]&&hid[i+1]!==o)||(Y>0&&hid[i-HW]&&hid[i-HW]!==o)||(Y<HH-1&&hid[i+HW]&&hid[i+HW]!==o))hb[i]=0}
  EDT(hb,HW,HH);for(let i=0;i<hb.length;i++)hb[i]=Math.min(Math.sqrt(hb[i])+.5,24);edBlur(hb,1,1,HW,HH);
  const land2=new Uint8Array(HW*HH);for(let i=0;i<land2.length;i++)land2[i]=hid[i]?1:0;
  for(let it=0;it<8;it++){const src=hid.slice();for(let Y=1;Y<HH-1;Y++)for(let X=1;X<HW-1;X++){const i=Y*HW+X;if(src[i])continue;const q=src[i-1]||src[i+1]||src[i-HW]||src[i+HW];if(q)hid[i]=q}}
  // relief: land rises gently away from the coast, the sea deepens; light from the north-west
  const sdl=new Float32Array(MW*MH),sdw=new Float32Array(MW*MH);for(let i=0;i<sdl.length;i++){const L=own[i]>=0;sdl[i]=L?INF:0;sdw[i]=L?0:INF}
  EDT(sdl,MW,MH);EDT(sdw,MW,MH);const cs=new Float32Array(MW*MH);for(let i=0;i<cs.length;i++)cs[i]=own[i]>=0?Math.sqrt(sdl[i])-.5:-(Math.sqrt(sdw[i])-.5);
  const nz=makePerlin(mulberry((seed^0x2e11)>>>0)),EV=new Float32Array(MW*MH);
  for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){const i=y*MW+x,c=cs[i];EV[i]=c>0?.004+Math.min(.03,c*.0006)*(.6+.8*Math.max(0,nz(x*.01,y*.01)+.5)):.002}
  edBlur(EV,2,3,MW,MH);const Hs=EV.slice();edBlur(Hs,1,2,MW,MH);
  const tf=new Float32Array(MW*MH*4),Lx=-.55,Ly=-.65,Lz=.52;
  for(let y=0;y<MH;y++)for(let x=0;x<MW;x++){const i=y*MW+x,c_=cs[i],ev=EV[i],wv=-Math.min(.08,.01+(-c_)*.0008);
    tf[i*4]=c_>0?lerp(c_*.004,Math.max(ev,Math.min(c_*.004,.02)),sstep(2,8,c_)):lerp(c_*.004,Math.min(wv,c_*.004),sstep(10,40,-c_));
    tf[i*4+1]=SQD[Math.floor(y/TRI_S)*SQW+Math.floor(x/TRI_S)];
    const gx=(Hs[y*MW+Math.min(MW-1,x+1)]-Hs[y*MW+Math.max(0,x-1)])*32,gy=(Hs[Math.min(MH-1,y+1)*MW+x]-Hs[Math.max(0,y-1)*MW+x])*32,nl=Math.hypot(gx,gy,1),lit=(-gx*Lx-gy*Ly+Lz)/nl/Lz,lit2=(gx*.4-gy*.3+.85)/nl/.85;
    tf[i*4+2]=clamp(.5+(lit*.75+lit2*.25-1)*.85,0,1);tf[i*4+3]=nz(x*.006+20,y*.006+11)*.5+nz(x*.018,y*.018+60)*.25+.5}
  // states: area, centre, neighbours
  const n=nC,area=new Float64Array(n),cx=new Float64Array(n),cy=new Float64Array(n),adj=Array.from({length:n},()=>new Map());let landCount=0;
  for(let y=0;y<MH;y+=2)for(let x=0;x<MW;x+=2){const i=y*MW+x,o=own[i];if(o<0||o>=n)continue;landCount++;area[o]++;cx[o]+=x;cy[o]+=y;
    for(const q of [x>1?own[i-2]:-1,x<MW-2?own[i+2]:-1,y>1?own[i-2*MW]:-1,y<MH-2?own[i+2*MW]:-1])if(q>=0&&q!==o&&q<n)adj[o].set(q,(adj[o].get(q)||0)+1)}
  const countries=[];for(let k=0;k<n;k++){let ix=area[k]?Math.round(cx[k]/area[k]):0,iy=area[k]?Math.round(cy[k]/area[k]):0;
    if(area[k]&&own[iy*MW+ix]!==k){let bd=1e18;for(let yy=0;yy<MH;yy+=4)for(let xx=0;xx<MW;xx+=4)if(own[yy*MW+xx]===k){const d=(xx-ix)**2+(yy-iy)**2;if(d<bd){bd=d;ix=xx;iy=yy}}}
    countries.push({idx:k,area:area[k]*4,lx:ix,ly:iy,cap:{x:ix,y:iy},neighbors:[...adj[k].entries()].filter(e=>e[1]>2).map(e=>e[0]),landShare:landCount?area[k]/landCount:0})}
  return {own,tf,hid,hb,lines,land2,countries,seed,landCount:landCount*4,H:null,T:.5,top:1,mtn:new Float32Array(NW*NH),edited:true}}
/* push a rebuilt world into the existing GL textures */
function glWorldUpload(world){const gl=GL.gl;
  const mip=(tex,unit,w,h,data,ch,intern,fmt)=>{gl.activeTexture(unit);gl.bindTexture(gl.TEXTURE_2D,tex);gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);gl.texImage2D(gl.TEXTURE_2D,0,intern,w,h,0,fmt,gl.FLOAT,data);let l=0;
    while(w>1||h>1){const nw=Math.max(1,w>>1),nh=Math.max(1,h>>1),nd=new Float32Array(nw*nh*ch);for(let y=0;y<nh;y++)for(let x=0;x<nw;x++){const x0=Math.min(w-1,x*2),x1=Math.min(w-1,x*2+1),y0=Math.min(h-1,y*2),y1=Math.min(h-1,y*2+1);
      for(let c=0;c<ch;c++)nd[(y*nw+x)*ch+c]=(data[(y0*w+x0)*ch+c]+data[(y0*w+x1)*ch+c]+data[(y1*w+x0)*ch+c]+data[(y1*w+x1)*ch+c])*.25}data=nd;w=nw;h=nh;l++;gl.texImage2D(gl.TEXTURE_2D,l,intern,w,h,0,fmt,gl.FLOAT,data)}gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAX_LEVEL,l)};
  mip(GL.tx0,gl.TEXTURE0,MW,MH,world.tf,4,gl.RGBA16F,gl.RGBA);mip(GL.txb,gl.TEXTURE2,MW*2,MH*2,world.hb,1,gl.R16F,gl.RED);
  world.hidOrig=world.hid.slice();world.ownOrig=world.own.slice();
  gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,GL.tx1);gl.texImage2D(gl.TEXTURE_2D,0,gl.R8UI,MW*2,MH*2,0,gl.RED_INTEGER,gl.UNSIGNED_BYTE,world.hid);
  gl.activeTexture(gl.TEXTURE3);gl.bindTexture(gl.TEXTURE_2D,GL.tx2);gl.texImage2D(gl.TEXTURE_2D,0,gl.R8UI,MW*2,MH*2,0,gl.RED_INTEGER,gl.UNSIGNED_BYTE,world.hidOrig);
  world.tf=null;world.hb=null;world.txb=GL.txb;REDRAW=true}
async function edBlankWorld(){SQW=Math.ceil(MW/TRI_S);SQH=Math.ceil(MH/TRI_S);SQD=new Uint8Array(SQW*SQH);SQL=new Int16Array(SQW*SQH*2).fill(-1);
  const r=mulberry((SEED^0x1d3)>>>0);for(let k=0;k<SQD.length;k++)SQD[k]=r()<.5?1:0;await tick();return worldRebuild(SEED,0)}
/* rebuild after an edit: own raster, borders, textures, colours */
function edCommit(){const w=worldRebuild(SEED,G.C.length);const keepTx=G.world&&G.world.txb;G.world=w;glWorldUpload(w);G.C.forEach((c,i)=>{if(c.geo&&w.countries[i]){const g=w.countries[i];Object.assign(c.geo,{area:g.area,lx:g.lx,ly:g.ly,neighbors:g.neighbors,landShare:g.landShare});if(!c.capT)c.geo.cap=g.cap}});
  BOARD.nown=null;edTownsFix();if(edPruneRoads())edRoadsSync();applyMapColors();REDRAW=true}
/* roads and tracks are cut where the land under them was erased */
function edPruneRoads(){let ch=false;const onLand=(x0,z0,x1,z1)=>{for(const t of [.25,.5,.75])if(bOwn(x0+(x1-x0)*t,z0+(z1-z0)*t)<0)return false;return true};
  const cut=L=>{const out=[];for(const h of L){const p=h.p;let run=[p[0],p[1]];for(let k=2;k<p.length;k+=2){if(onLand(p[k-2],p[k-1],p[k],p[k+1]))run.push(p[k],p[k+1]);else{ch=true;if(run.length>=4)out.push({...h,p:new Float32Array(run)});run=[p[k],p[k+1]]}}if(run.length>=4)out.push(run.length===p.length?h:{...h,p:new Float32Array(run)})}return out};
  LOG.hw=cut(LOG.hw);LOG.rail=cut(LOG.rail);return ch}
function edSnap(){ED.undo.push({SQL:SQL.slice(),SQD:SQD.slice(),towns:JSON.stringify(BOARD.towns||[]),hw:LOG.hw.map(h=>({lv:h.lv,p:Array.from(h.p)})),rail:LOG.rail.map(r=>Array.from(r.p)),C:G.C.map(c=>({name:c.name,color:c.color,dead:!!c.edDead,unnamed:!!c.unnamed,light:!!c.light}))});if(ED.undo.length>25)ED.undo.shift()}
function edUndo(){const s=ED.undo.pop();if(!s)return toast("","Нічого скасовувати","");SQL=s.SQL;SQD=s.SQD;BOARD.towns=JSON.parse(s.towns);LOG.hw=s.hw.map(h=>({lv:h.lv,p:new Float32Array(h.p)}));LOG.rail=s.rail.map(p=>({p:new Float32Array(p)}));
  G.C.length=s.C.length;s.C.forEach((c,i)=>{if(!G.C[i])G.C[i]=edNewC(i,c.color);Object.assign(G.C[i],{name:c.name,color:c.color,edDead:c.dead,unnamed:c.unnamed})});edCommit();edRoadsSync();edPanel()}
function edNewC(i,color){const used=new Set(G.C.map(c=>c&&c.color));const col=color||COUNTRY_COLS.find(x=>!used.has(x))||`#${((Math.random()*0xffffff)|0).toString(16).padStart(6,"0")}`;
  return {id:i,name:"Нова територія "+(i+1),color:col,unnamed:true,light:true,geo:{idx:i,area:0,lx:0,ly:0,cap:{x:0,y:0},neighbors:[],landShare:0},corr:20,stability:60,dev:.5,pop:10,flag:""}}

/* ---------- settlements and roads ---------- */
const edNodeOwn=(x,z)=>{const q=CST*.3,c=new Map();for(const [dx,dz] of [[q,q],[-q,q],[q,-q],[-q,-q]]){const o=bOwn(x+dx,z+dz);if(o>=0)c.set(o,(c.get(o)||0)+1)}let b=-1,bv=0;for(const [k,v] of c)if(v>bv){bv=v;b=k}return b};
function edTownsFix(){if(!BOARD.towns)return;BOARD.towns=BOARD.towns.filter(t=>{const o=edNodeOwn(t.x,t.z);if(o<0)return false;t.cid=o;return true})}
function edTownName(){const A=typeof CITY_A!=="undefined"?CITY_A:["Нов","Віл","Остр","Сол","Бер","Дар"],B=typeof CITY_B!=="undefined"?CITY_B:["град","поль","ськ","ів","ине"];const used=new Set((BOARD.towns||[]).map(t=>t.name));
  for(let k=0;k<60;k++){const n=pick(A)+pick(B);if(!used.has(n))return n}return pick(A)+pick(B)+" "+rint(2,9)}
function edAddTown(wx,wz,type,cidForce){const i=Math.round((wx+WX/2)/CST),j=Math.round((wz+WZ/2)/CST),[x,z]=edW(i,j),o=cidForce??edNodeOwn(x,z);if(o<0){toast("warn","Тут море","Поселення ставиться на суходіл");return null}
  if((BOARD.towns||[]).some(t=>Math.hypot(t.x-x,t.z-z)<CST*.9)){toast("warn","Тут уже є поселення","");return null}
  const pop=type==="vil"?.02+Math.random()*.04:type==="town"?.15+Math.random()*.35:type==="cap"?1.5+Math.random()*2:.6+Math.random()*1.6;
  const t={x,z,node:j*CBL.nx+i,type,pop,cid:o,name:edTownName()};BOARD.towns.push(t);return t}
function edNearTown(x,y){let best=-1,bd=16;(BOARD.towns||[]).forEach((t,i)=>{const q=project(t.x,0,t.z);if(!q)return;const d=Math.hypot(q.x-x,q.y-y);if(d<bd){bd=d;best=i}});return best}
/* road between two lattice nodes over land: A* on the square lattice */
function edPath(a,b){const NX=CBL.nx,NZ=CBL.nz,N=NX*NZ,D=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]],g=new Float32Array(N).fill(1e9),prev=new Int32Array(N).fill(-1),hk=[],hv=[];
  const XY=n=>edW(n%NX,(n/NX)|0),land=(x,z)=>bOwn(x,z)>=0,bx=b%NX,bz=(b/NX)|0;
  const ok=(n,m)=>{const [x1,z1]=XY(n),[x2,z2]=XY(m);for(const t of [.25,.5,.75]){const x=x1+(x2-x1)*t,z=z1+(z2-z1)*t,px=-(z2-z1)*.2,pz=(x2-x1)*.2;if(!land(x+px,z+pz)&&!land(x-px,z-pz))return false}return true};
  const push=(f,s)=>{hk.push(f);hv.push(s);let k=hk.length-1;while(k>0){const p=(k-1)>>1;if(hk[p]<=hk[k])break;[hk[p],hk[k]]=[hk[k],hk[p]];[hv[p],hv[k]]=[hv[k],hv[p]];k=p}};
  const pop=()=>{const s=hv[0],lk=hk.pop(),lv=hv.pop();if(hk.length){hk[0]=lk;hv[0]=lv;let k=0;for(;;){const l=k*2+1,r=l+1;let m=k;if(l<hk.length&&hk[l]<hk[m])m=l;if(r<hk.length&&hk[r]<hk[m])m=r;if(m===k)break;[hk[m],hk[k]]=[hk[k],hk[m]];[hv[m],hv[k]]=[hv[k],hv[m]];k=m}}return s};
  g[a]=0;push(0,a);let it=0;while(hk.length&&it++<400000){const n=pop();if(n===b)break;const x=n%NX,z=(n/NX)|0;for(const [dx,dz] of D){const nx=x+dx,nz=z+dz;if(nx<0||nz<0||nx>=NX||nz>=NZ)continue;const m=nz*NX+nx;if(!ok(n,m))continue;
    const ng=g[n]+(dx&&dz?1.4142:1);if(ng<g[m]){g[m]=ng;prev[m]=n;push(ng+Math.hypot(nx-bx,nz-bz),m)}}}
  if(g[b]>=1e9)return null;const nodes=[];for(let n=b;n>=0;n=prev[n]){nodes.push(n);if(n===a)break}nodes.reverse();const pts=[];
  for(let k=0;k<nodes.length;k++){if(k>0&&k<nodes.length-1&&nodes[k]-nodes[k-1]===nodes[k+1]-nodes[k])continue;pts.push(...XY(nodes[k]))}return new Float32Array(pts)}
/* lattice bits from the drawn polylines (routing uses them) */
function edRoadsSync(){const NX=CBL.nx,N=NX*CBL.nz,D=[[1,0],[1,1],[0,1],[-1,1],[-1,0],[-1,-1],[0,-1],[1,-1]];BL.st=CST;BL.nx=CBL.nx;BL.nz=CBL.nz;
  const fill=(L,bits)=>{for(const h of L){const p=h.p;for(let k=2;k<p.length;k+=2){let i0=Math.round((p[k-2]+WX/2)/CST),j0=Math.round((p[k-1]+WZ/2)/CST);const i1=Math.round((p[k]+WX/2)/CST),j1=Math.round((p[k+1]+WZ/2)/CST),sx=Math.sign(i1-i0),sz=Math.sign(j1-j0),d=D.findIndex(q=>q[0]===sx&&q[1]===sz);if(d<0)continue;
    let g=0;while((i0!==i1||j0!==j1)&&g++<5000){const n=j0*NX+i0;bits[n]|=1<<d;i0+=sx;j0+=sz;bits[j0*NX+i0]|=1<<((d+4)%8)}}}};
  const bits=new Uint8Array(N),rbits=new Uint8Array(N);fill(LOG.hw,bits);fill(LOG.rail,rbits);BOARD.bits=bits;BOARD.rbits=rbits;
  const comp=new Int32Array(N).fill(-1);let c=0;for(let n=0;n<N;n++){if(comp[n]>=0||!(bits[n]|rbits[n]))continue;const st=[n];comp[n]=c;while(st.length){const m=st.pop();for(let d=0;d<8;d++)if((bits[m]|rbits[m])&(1<<d)){const q=m+D[d][1]*NX+D[d][0];if(comp[q]<0){comp[q]=c;st.push(q)}}}c++}
  for(let n=0;n<N;n++)if(comp[n]<0)comp[n]=c++;BOARD.comp=comp;LOG.built=true;
  try{boardPorts();boardCheckpoints()}catch(e){}BOARD.rnodes=new Set((BOARD.towns||[]).filter(t=>rbits[t.node]).map(t=>t.node));CO_ROUTES.clear();coPlaces();REDRAW=true}

/* ---------- tools ---------- */
function edBrushTris(wx,wz){const out=[],r=ED.brush,i0=Math.floor((wx+WX/2)/CST)-r-1,j0=Math.floor((wz+WZ/2)/CST)-r-1;
  for(let j=j0;j<=j0+2*r+2;j++)for(let i=i0;i<=i0+2*r+2;i++){if(i<0||j<0||i>=SQW||j>=SQH)continue;for(let h=0;h<2;h++){const t=(j*SQW+i)*2+h,c=edTriCentre(t);if(Math.hypot(c[0]-wx,c[1]-wz)<=(r-.35)*CST+CST*.45)out.push(t)}}return out}
function edPaintAt(e){const w=pickPlane(e.clientX,e.clientY);if(!w)return;const v=ED.tool==="sea"?-1:ED.sel;for(const t of edBrushTris(w[0],w[1]))ED.stroke.set(t,v);REDRAW=true}
function edNodeAt(x,y){const w=pickPlane(x,y);if(!w)return null;const i=clamp(Math.round((w[0]+WX/2)/CST),0,CBL.nx-1),j=clamp(Math.round((w[1]+WZ/2)/CST),0,CBL.nz-1);return[i,j]}
/* lattice path between two nodes: diagonal steps first, then straight */
function edSteps(a,b){const out=[];let [i,j]=a;while(i!==b[0]||j!==b[1]){i+=Math.sign(b[0]-i);j+=Math.sign(b[1]-j);out.push([i,j])}return out}
function edClosePoly(){const P=ED.poly;if(P.length<4)return;edSnap();
  // diagonal sides follow the square diagonals so the border runs exactly along the drawn line
  for(let k=1;k<P.length;k++){const [i0,j0]=P[k-1],[i1,j1]=P[k],di=i1-i0,dj=j1-j0;if(di&&dj){const ci=Math.min(i0,i1),cj=Math.min(j0,j1);if(ci>=0&&cj>=0&&ci<SQW&&cj<SQH){const q=cj*SQW+ci,nd=di*dj>0?1:0;if(SQD[q]!==nd){const a=SQL[q*2],b=SQL[q*2+1];SQD[q]=nd;if(a!==b){SQL[q*2]=a;SQL[q*2+1]=b}}}}}
  const id=G.C.length;if(id>=118){toast("warn","Забагато держав","Не більше 118");ED.poly=[];return}G.C.push(edNewC(id));
  const xs=P.map(p=>p[0]),ys=P.map(p=>p[1]),inside=(x,y)=>{let c=false;for(let a=0,b=P.length-1;a<P.length;b=a++){const [xi,yi]=P[a],[xj,yj]=P[b];if(((yi>y)!==(yj>y))&&x<(xj-xi)*(y-yi)/(yj-yi)+xi)c=!c}return c};
  let n=0;for(let j=Math.min(...ys);j<Math.max(...ys);j++)for(let i=Math.min(...xs);i<Math.max(...xs);i++){if(i<0||j<0||i>=SQW||j>=SQH)continue;for(let h=0;h<2;h++){const t=(j*SQW+i)*2+h,c=edTriCentre(t),cx=(c[0]+WX/2)/CST,cz=(c[1]+WZ/2)/CST;if(inside(cx,cz)){SQL[t]=id;n++}}}
  ED.poly=[];if(!n){G.C.pop();return toast("warn","Порожня область","")}ED.sel=id;edCommit();edPanel();toast("good","Нова територія","Інструмент «Створити державу» дасть їй назву й столицю")}
function edClick(x,y){const w=pickPlane(x,y);if(!w)return true;const tool=ED.tool,t=edTriAt(w[0],w[1]);
  if(ED.capFor>=0){const c=ED.capFor,ti=edNearTown(x,y);ED.capFor=-1;edSnap();let tw=ti>=0?BOARD.towns[ti]:null;if(tw&&tw.cid!==c)tw=null;if(!tw){tw=edAddTown(w[0],w[1],"cap");if(!tw)return true;if(tw.cid!==c){BOARD.towns.pop();toast("warn","Столиця має бути на землі держави","");return true}}
    for(const o of BOARD.towns)if(o.cid===c&&o.type==="cap"&&o!==tw)o.type="city";tw.type="cap";G.C[c].capT=tw.name;edRoadsSync();edPanel();toast("good","Столицю призначено",tw.name);return true}
  if(tool==="line"){const nd=edNodeAt(x,y);if(!nd)return true;if(ED.poly.length>2&&nd[0]===ED.poly[0][0]&&nd[1]===ED.poly[0][1]){ED.poly.push(...edSteps(ED.poly[ED.poly.length-1],nd));ED.poly.pop();edClosePoly();return true}
    if(!ED.poly.length)ED.poly.push(nd);else ED.poly.push(...edSteps(ED.poly[ED.poly.length-1],nd));REDRAW=true;return true}
  if(tool==="sel"||tool==="state"){const ti=tool==="sel"?edNearTown(x,y):-1;if(ti>=0){ED.selT=ti;ED.sel=-1}else{ED.selT=-1;ED.sel=t>=0?SQL[t]:-1;if(tool==="state"&&ED.sel>=0){ED.stateEdit=ED.sel}}edPanel();return true}
  if(tool==="isl"){if(ED.sel<0)return toast("warn","Спершу оберіть державу","Інструментом «Вибір»"),true;const L=edIsland(t);if(!L.length)return true;edSnap();for(const q of L)SQL[q]=ED.sel;edCommit();edPanel();return true}
  if(tool==="islDel"){const L=edIsland(t);if(!L.length)return true;edSnap();for(const q of L)SQL[q]=-1;edCommit();edRoadsSync();edPanel();return true}
  if(tool==="town"){edSnap();if(edAddTown(w[0],w[1],ED.townType)){edRoadsSync();edPanel()}else ED.undo.pop();return true}
  if(tool==="townDel"){const ti=edNearTown(x,y);if(ti<0)return true;edSnap();BOARD.towns.splice(ti,1);edRoadsSync();edPanel();return true}
  if(tool==="road"){const nd=edNodeAt(x,y);if(!nd)return true;const n=nd[1]*CBL.nx+nd[0];if(ED.road.length){const a=ED.road[ED.road.length-1],p=edPath(a,n);if(!p){toast("warn","Дорогу не прокласти","Між точками море");return true}edSnap();
      if(ED.roadMode==="rail")LOG.rail.push({p});else LOG.hw.push({lv:ED.roadMode==="main"?3:2,p});ED.roadsEdited=true;edRoadsSync()}ED.road.push(n);REDRAW=true;return true}
  if(tool==="roadDel"){let best=null,bd=10;for(const L of [LOG.hw,LOG.rail])L.forEach((h,i)=>{const p=h.p;for(let k=2;k<p.length;k+=2){const a=project(p[k-2],0,p[k-1]),b=project(p[k],0,p[k+1]);if(!a||!b)continue;const dx=b.x-a.x,dy=b.y-a.y,l2=dx*dx+dy*dy||1,tt=clamp(((x-a.x)*dx+(y-a.y)*dy)/l2,0,1),d=Math.hypot(a.x+dx*tt-x,a.y+dy*tt-y);if(d<bd){bd=d;best=[L,i]}}});
    if(best){edSnap();best[0].splice(best[1],1);ED.roadsEdited=true;edRoadsSync()}return true}
  return true}

/* ---------- panel ---------- */
function edPanel(){let el=$("#edPanel");if(!ED.on){if(el)el.remove();return}if(!el){el=document.createElement("div");el.id="edPanel";el.className="glass";document.body.appendChild(el)}
  const tool=ED_TOOLS.find(t=>t[0]===ED.tool),c=ED.sel>=0?G.C[ED.sel]:null,tw=ED.selT>=0?BOARD.towns[ED.selT]:null;
  const states=G.C.filter((c,i)=>c&&!c.edDead&&c.geo&&c.geo.area>0);
  el.innerHTML=`<div class="row sp"><b style="font-size:15px">${ic("gear")} Редактор мапи</b><span class="note">${states.length} держ. · ${(BOARD.towns||[]).length} посел.</span></div>
   <div class="edtools">${ED_TOOLS.map(([id,n,i,d])=>`<button class="edt ${ED.tool===id?"on":""}" data-act="edTool" data-arg="${id}" data-tip="${T(n,d)}">${ic(i)}<span>${n}</span></button>`).join("")}</div>
   <div class="note" style="margin:6px 0 8px">${tool?tool[3]:""}</div>
   ${ED.tool==="paint"||ED.tool==="sea"?`<div class="row sp"><span class="lbl">Розмір пензля</span><div class="seg">${[1,2,3,5].map(b=>`<button class="${ED.brush===b?"on":""}" data-act="edBrush" data-arg="${b}">${b}</button>`).join("")}</div></div>`:""}
   ${ED.tool==="town"?`<div class="seg" style="flex-wrap:wrap">${[["cap","Столиця"],["big","Велике місто"],["city","Середнє місто"],["town","Мале місто"]].map(([k,n])=>`<button class="${ED.townType===k?"on":""}" data-act="edTownType" data-arg="${k}">${n}</button>`).join("")}</div>`:""}
   ${ED.tool==="road"?`<div class="seg">${[["road","Дорога"],["main","Магістраль"],["rail","Залізниця"]].map(([k,n])=>`<button class="${ED.roadMode===k?"on":""}" data-act="edRoadMode" data-arg="${k}">${n}</button>`).join("")}</div>`:""}
   ${ED.tool==="line"&&ED.poly.length?`<div class="note warn" style="margin-top:6px">Точок: ${ED.poly.length}. Клікніть на першу, щоб замкнути. Esc — скасувати.</div>`:""}
   ${c?`<div class="blk" style="margin-top:10px"><div class="row" style="gap:8px"><input type="color" value="${c.color}" data-edcol="${ED.sel}" style="width:34px;height:26px;border:0;background:none;padding:0"><input class="edin" value="${esc(c.unnamed?"":c.name)}" placeholder="Назва держави" data-edname="${ED.sel}"></div>
     <div class="note" style="margin-top:6px">Столиця: <b>${esc((BOARD.towns||[]).find(t=>t.cid===ED.sel&&t.type==="cap")?.name||"немає")}</b></div>
     <div class="row wrap" style="gap:6px;margin-top:8px"><button class="btn sm pri" data-act="edCap" data-arg="${ED.sel}">${ic("star")}Обрати столицю</button><button class="btn sm" data-act="edColRnd" data-arg="${ED.sel}">${ic("refresh")}Колір</button><button class="btn sm" data-act="edDelState" data-arg="${ED.sel}">${ic("trash")}Стерти державу</button></div>
     ${ED.capFor>=0?`<div class="note warn" style="margin-top:6px">Клікніть на поселення або місце для столиці</div>`:""}</div>`:""}
   ${tw?`<div class="blk" style="margin-top:10px"><input class="edin" value="${esc(tw.name)}" data-edtown="${ED.selT}"><div class="seg" style="margin-top:6px;flex-wrap:wrap">${[["cap","Столиця"],["big","Велике"],["city","Середнє"],["town","Мале"]].map(([k,n])=>`<button class="${tw.type===k?"on":""}" data-act="edTType" data-arg="${k}">${n}</button>`).join("")}</div>
     <div class="row wrap" style="gap:6px;margin-top:8px"><button class="btn sm ${tw.portOv?"pri":""}" data-act="edTFlag" data-arg="portOv">${ic("anchor")}Порт${tw.portOv===false?" ✕":""}</button><button class="btn sm ${tw.airOv?"pri":""}" data-act="edTFlag" data-arg="airOv">${ic("plane")}Аеропорт${tw.airOv===false?" ✕":""}</button><button class="btn sm" data-act="edTDel">${ic("trash")}Стерти</button></div>
     <div class="note" style="margin-top:6px">Порт працює лише біля моря. Залізнична станція з'являється, коли до поселення підходить колія.</div></div>`:""}
   <div class="row wrap" style="gap:6px;margin-top:12px"><button class="btn sm" data-act="edUndo">${ic("refresh")}Скасувати (Ctrl+Z)</button><button class="btn sm" data-act="edAutoRoads">${ic("road")}Прокласти дороги автоматично</button></div>
   <button class="btn pri" style="width:100%;margin-top:10px" data-act="edDone">${ic("play","fill")}Почати гру</button>`;
  el.querySelectorAll("[data-edname]").forEach(i=>i.oninput=()=>{const c=G.C[+i.dataset.edname];c.name=i.value.trim()||c.name;c.unnamed=!i.value.trim();REDRAW=true});
  el.querySelectorAll("[data-edtown]").forEach(i=>i.oninput=()=>{const t=BOARD.towns[+i.dataset.edtown];if(t&&i.value.trim()){t.name=i.value.trim();coPlaces();REDRAW=true}});
  el.querySelectorAll("[data-edcol]").forEach(i=>i.oninput=()=>{G.C[+i.dataset.edcol].color=i.value;applyMapColors()});
  el.querySelectorAll("input").forEach(i=>i.addEventListener("keydown",e=>e.stopPropagation()))}
ACT.edTool=t=>{ED.tool=t;ED.poly=[];ED.road=[];ED.capFor=-1;edPanel();REDRAW=true};
ACT.edBrush=b=>{ED.brush=+b;edPanel()};ACT.edTownType=k=>{ED.townType=k;edPanel()};ACT.edRoadMode=k=>{ED.roadMode=k;ED.road=[];edPanel()};
ACT.edCap=c=>{ED.capFor=+c;edPanel()};ACT.edColRnd=c=>{G.C[+c].color=pick(COUNTRY_COLS.concat(["#7a5c9e","#5e9e6e","#a0704a","#4e7fa0","#9e4e5e"]));applyMapColors();edPanel()};
ACT.edDelState=c=>{c=+c;edSnap();for(let t=0;t<SQL.length;t++)if(SQL[t]===c)SQL[t]=-1;G.C[c].edDead=true;ED.sel=-1;edCommit();edRoadsSync();edPanel()};
ACT.edTType=k=>{const t=BOARD.towns[ED.selT];if(!t)return;edSnap();if(k==="cap")for(const o of BOARD.towns)if(o.cid===t.cid&&o.type==="cap")o.type="city";t.type=k;edRoadsSync();edPanel()};
ACT.edTFlag=f=>{const t=BOARD.towns[ED.selT];if(!t)return;edSnap();t[f]=t[f]===true?false:t[f]===false?undefined:true;edRoadsSync();edPanel()};
ACT.edTDel=()=>{if(ED.selT<0)return;edSnap();BOARD.towns.splice(ED.selT,1);ED.selT=-1;edRoadsSync();edPanel()};
ACT.edUndo=()=>edUndo();
ACT.edAutoRoads=async()=>{edSnap();toast("","Прокладаємо дороги…","");await tick();ED.roadsEdited=false;await boardRoads();edRoadsSyncKeep();toast("good","Дороги прокладено",`${LOG.hw.length} доріг · ${LOG.rail.length} залізниць`)};
function edRoadsSyncKeep(){BOARD.rnodes=new Set((BOARD.towns||[]).filter(t=>BOARD.rbits&&BOARD.rbits[t.node]).map(t=>t.node));CO_ROUTES.clear();coPlaces();REDRAW=true}
ACT.edDone=()=>{const alive=G.C.filter(c=>!c.edDead&&c.geo&&c.geo.area>0);if(!alive.length)return toast("warn","Немає жодної держави","Намалюйте кордон і замкніть лінію");
  const noCap=alive.filter(c=>!(BOARD.towns||[]).some(t=>t.cid===c.id&&t.type==="cap"));if(noCap.length&&!ED.capWarned){ED.capWarned=true;return toast("warn","Не в усіх держав є столиця",`${noCap.slice(0,3).map(c=>c.name).join(", ")}${noCap.length>3?"…":""}: столицю поставимо автоматично. Натисніть ще раз, щоб почати`)}
  edFinish()};

/* ---------- input: brush strokes, clicks, keys ---------- */
addEventListener("pointerdown",e=>{if(!ED.on||!GL||e.target!==GL.cv||e.button!==0)return;if(ED.tool!=="paint"&&ED.tool!=="sea")return;
  if(ED.tool==="paint"&&ED.sel<0){toast("warn","Спершу оберіть державу","Інструментом «Вибір» клікніть по ній");return}
  e.stopImmediatePropagation();e.preventDefault();ED.painting=true;ED.stroke=new Map();edPaintAt(e)},true);
addEventListener("pointermove",e=>{if(!ED.on)return;ED.hover={x:e.clientX,y:e.clientY};if(ED.painting){e.stopImmediatePropagation();edPaintAt(e)}REDRAW=true},true);
addEventListener("pointerup",e=>{if(!ED.on||!ED.painting)return;e.stopImmediatePropagation();ED.painting=false;if(!ED.stroke||!ED.stroke.size)return;edSnap();for(const [t,v] of ED.stroke)SQL[t]=v;ED.stroke=null;edCommit();if(ED.tool==="sea")edRoadsSync();edPanel()},true);
addEventListener("keydown",e=>{if(!ED.on)return;if(e.target&&(e.target.tagName==="INPUT"))return;
  if(e.key==="Escape"){ED.poly=[];ED.road=[];ED.capFor=-1;edPanel();REDRAW=true;e.stopImmediatePropagation()}
  if((e.ctrlKey||e.metaKey)&&e.code==="KeyZ"){e.preventDefault();e.stopImmediatePropagation();edUndo()}},true);
{const _cc=coClick;coClick=function(x,y){if(ED.on)return edClick(x,y);return _cc(x,y)}}

/* ---------- drawing ---------- */
function drawEditor(g,dpr){if(!ED.on)return;const P=(x,z)=>{const q=project(x,0,z);return q?[q.x*dpr,q.y*dpr]:null};
  // state names
  g.textAlign="center";g.textBaseline="middle";
  G.C.forEach((c,i)=>{if(c.edDead||!c.geo||!c.geo.area)return;const x=c.geo.lx/MW*WX-WX/2,z=c.geo.ly/MH*WZ-WZ/2,q=P(x,z);if(!q)return;g.font=`${c.unnamed?"italic 600":"800"} ${12*dpr}px "Inter",sans-serif`;const t=(c.unnamed?c.name:c.name.toUpperCase()),w=g.measureText(t).width+14*dpr;
    g.fillStyle="rgba(8,18,28,.82)";g.fillRect(q[0]-w/2,q[1]-10*dpr,w,20*dpr);g.strokeStyle=i===ED.sel?"#5cc8f2":c.color;g.lineWidth=(i===ED.sel?2:1)*dpr;g.strokeRect(q[0]-w/2,q[1]-10*dpr,w,20*dpr);g.fillStyle="#e8eef4";g.fillText(t,q[0],q[1]+.5*dpr)});
  g.textBaseline="alphabetic";
  // brush preview / stroke
  if(ED.stroke&&ED.stroke.size){for(const [t,v] of ED.stroke){const k=t>>1,h=t&1,i=k%SQW,j=(k/SQW)|0,d=SQD[k];const V=d?(h?[[0,0],[1,1],[0,1]]:[[0,0],[1,0],[1,1]]):(h?[[1,0],[1,1],[0,1]]:[[0,0],[1,0],[0,1]]);
    g.fillStyle=v<0?"rgba(40,120,200,.75)":(G.C[v]?G.C[v].color:"#888");g.beginPath();V.forEach((p,n)=>{const q=P(-WX/2+(i+p[0])*CST,-WZ/2+(j+p[1])*CST);if(q)n?g.lineTo(...q):g.moveTo(...q)});g.closePath();g.fill()}}
  if((ED.tool==="paint"||ED.tool==="sea")&&ED.hover&&!ED.painting){const w=pickPlane(ED.hover.x,ED.hover.y);if(w){const c=P(w[0],w[1]),e=P(w[0]+ED.brush*CST,w[1]);if(c&&e){g.strokeStyle="rgba(255,255,255,.8)";g.lineWidth=1.5*dpr;g.beginPath();g.arc(c[0],c[1],Math.hypot(e[0]-c[0],e[1]-c[1]),0,7);g.stroke()}}}
  // border line in progress
  const node=(i,j)=>P(...edW(i,j));
  if(ED.tool==="line"){const hv=ED.hover?edNodeAt(ED.hover.x,ED.hover.y):null;const pts=ED.poly.slice();if(hv&&pts.length)pts.push(...edSteps(pts[pts.length-1],hv));
    if(pts.length){g.strokeStyle="#05080c";g.lineWidth=3.2*dpr;g.lineJoin="round";g.beginPath();pts.forEach((p,n)=>{const q=node(p[0],p[1]);if(q)n?g.lineTo(...q):g.moveTo(...q)});g.stroke()}
    if(ED.poly.length){const q=node(...ED.poly[0]);if(q){g.fillStyle="#ffb347";g.strokeStyle="#05080c";g.lineWidth=1.5*dpr;g.beginPath();g.arc(q[0],q[1],6*dpr,0,7);g.fill();g.stroke()}}
    if(hv){const q=node(...hv);if(q){g.fillStyle="#fff";g.beginPath();g.arc(q[0],q[1],3.5*dpr,0,7);g.fill()}}}
  if(ED.tool==="road"&&ED.road.length){const n=ED.road[ED.road.length-1],q=node(n%CBL.nx,(n/CBL.nx)|0);if(q){g.fillStyle="#ffb347";g.strokeStyle="#05080c";g.lineWidth=1.5*dpr;g.beginPath();g.arc(q[0],q[1],5*dpr,0,7);g.fill();g.stroke()}}
  if(ED.tool==="road"&&ED.hover){const hv=edNodeAt(ED.hover.x,ED.hover.y);if(hv){const q=node(...hv);if(q){g.fillStyle="#fff";g.beginPath();g.arc(q[0],q[1],3.5*dpr,0,7);g.fill()}}}
  REDRAW=true}
{const _dt=drawBoardTowns;drawBoardTowns=function(g,dpr){_dt(g,dpr);if(ED.on)guard("Редактор",()=>drawEditor(g,dpr))}}

/* ---------- open / finish ---------- */
function editorRun(){return new Promise(res=>{ED.on=true;ED.resolve=res;ED.tool=G.custom?"line":"sel";ED.undo=[];ED.roadsEdited=false;ED.capWarned=false;G.me=null;
  document.body.classList.add("editing");if(!window.__loopOn){window.__loopOn=true;requestAnimationFrame(loop)}UI.mode="grid";try{buildModeDD()}catch(e){}try{updateLegend()}catch(e){}applyMapColors();
  if(typeof CITY_EL!=="undefined"){CITY_EL.length=0}const ct=$("#cities");if(ct)ct.innerHTML="";
  edRoadsSync();edPanel();Cam.ttx=0;Cam.ttz=.4;Cam.tdist=WX*1.03;
  queueModal({icon:"gear",eyebrow:"Редактор мапи",title:G.custom?"Створіть свій світ":"Відредагуйте мапу",body:`<p>${G.custom?"Перед вами порожній океан.":"Мапу згенеровано, її можна змінити."} Інструменти — на панелі зліва.</p><ul style="margin:8px 0 0 18px;line-height:1.6"><li><b>Кордон</b> — клікайте вузли сітки; замкнена лінія стає новою територією з випадковим кольором.</li><li><b>Створити державу</b> — клік по території: назва і столиця.</li><li><b>Пензель / Море</b> — малюйте сушу держави або стирайте її.</li><li><b>Острів → державі</b> — приєднати острів до обраної держави.</li><li><b>Поселення, Дорога</b> — міста й села, дороги, магістралі, колії. Порти й аеропорти — у картці поселення.</li></ul><div class="note" style="margin-top:8px">Ctrl+Z — скасувати крок. Камера: WASD, колесо миші.</div>`,choices:[{t:"До роботи",d:"",f(){}}]})})}
async function edFinish(){
  // drop erased states, renumber the rest
  const map=new Int16Array(G.C.length).fill(-1),alive=[];G.C.forEach((c,i)=>{if(!c.edDead&&c.geo&&c.geo.area>0){map[i]=alive.length;alive.push(c)}});
  for(let t=0;t<SQL.length;t++)SQL[t]=SQL[t]>=0?map[SQL[t]]:-1;
  const w=worldRebuild(SEED,alive.length);G.world=w;glWorldUpload(w);edTownsFix();
  // every state needs a capital
  alive.forEach((c,i)=>{const own=BOARD.towns.filter(t=>t.cid===i);if(own.some(t=>t.type==="cap"))return;const best=own.sort((a,b)=>({big:0,city:1,town:2,vil:3}[a.type]??4)-({big:0,city:1,town:2,vil:3}[b.type]??4)||b.pop-a.pop)[0];
    if(best){best.type="cap";best.pop=Math.max(best.pop,1.2);return}const g=w.countries[i];edAddTown(g.lx/MW*WX-WX/2,g.ly/MH*WZ-WZ/2,"cap",i)});
  // full states rebuilt from the edited geography, names and colours kept
  const used=new Set(alive.map(c=>c.name));G.C=alive.map((old,i)=>{const geo=w.countries[i];const c=makeCountry(geo,i,used);c.name=old.unnamed?genCountryName(used):old.name;used.add(c.name);c.full=c.ide.gov+" "+c.name;c.color=old.color;
    const cap=BOARD.towns.find(t=>t.cid===i&&t.type==="cap");if(cap){c.capName=cap.name;geo.cap={x:(cap.x+WX/2)/WX*MW,y:(cap.z+WZ/2)/WZ*MH}}return c});
  initRelations();calibrateResources();initMarket();
  ED.on=false;document.body.classList.remove("editing");edPanel();G.wmod=true;
  if(ED.roadsEdited)edRoadsSync();else{BL.st=CST;BL.nx=CBL.nx;BL.nz=CBL.nz;for(const t of BOARD.towns){t.node=Math.round((t.z+WZ/2)/CST)*CBL.nx+Math.round((t.x+WX/2)/CST);delete t.cnode}await boardRoads()}
  buildOverlay();buildCityLabels();UI.mode="co";try{buildModeDD()}catch(e){}coPlaces();applyMapColors();try{updateLegend()}catch(e){}
  const r=ED.resolve;ED.resolve=null;if(r)r()}

/* ---------- saving an edited world ---------- */
const rle=a=>{const o=[];for(let i=0;i<a.length;){let j=i;while(j<a.length&&a[j]===a[i])j++;o.push(a[i],j-i);i=j}return o};
const unrle=(o,T)=>{let n=0;for(let i=1;i<o.length;i+=2)n+=o[i];const a=new T(n);let p=0;for(let i=0;i<o.length;i+=2){a.fill(o[i],p,p+o[i+1]);p+=o[i+1]}return a};
function edSerialize(){return{sqd:rle(SQD),sql:rle(SQL),towns:(BOARD.towns||[]).map(t=>({x:+t.x.toFixed(4),z:+t.z.toFixed(4),type:t.type,pop:+t.pop.toFixed(3),cid:t.cid,name:t.name,portOv:t.portOv,airOv:t.airOv})),
  rd:ED.roadsEdited||G.edRoads?{hw:LOG.hw.map(h=>({lv:h.lv,p:Array.from(h.p,v=>+v.toFixed(4))})),rail:LOG.rail.map(r=>Array.from(r.p,v=>+v.toFixed(4)))}:null}}
async function edLoadWorld(S){SQW=Math.ceil(MW/TRI_S);SQH=Math.ceil(MH/TRI_S);SQD=unrle(S.sqd,Uint8Array);SQL=unrle(S.sql,Int16Array);await tick();return worldRebuild(SEED,(G.C||[]).length)}
function edLoadTowns(S){BL.st=CST;BL.nx=Math.round(WX/CST)+1;BL.nz=Math.round(WZ/CST)+1;CBL.nx=BL.nx;CBL.nz=BL.nz;
  BOARD.towns=S.towns.map(t=>({...t,node:Math.round((t.z+WZ/2)/CST)*CBL.nx+Math.round((t.x+WX/2)/CST)}))}
function edLoadRoads(S){LOG.hw=S.rd.hw.map(h=>({lv:h.lv,p:new Float32Array(h.p)}));LOG.rail=S.rd.rail.map(p=>({p:new Float32Array(p)}));G.edRoads=true;edRoadsSync()}
