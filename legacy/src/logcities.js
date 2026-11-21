
/* ================= MAP LABELS: country blocks, big cities, settlements ================= */
let CITY_EL=[],CITY_KEY="";
function buildCityLabels(){
  const box=$("#cities");if(!box||!LOG.built)return;box.innerHTML="";CITY_EL=[];CITY_KEY="";
  const add=(x,z,html,cls,cid,pr,w)=>{const d=document.createElement("div");d.className="city "+cls;d.innerHTML=html;d.style.display="none";box.appendChild(d);CITY_EL.push({el:d,x,z,cap:cls==="cap",town:cls.startsWith("town"),cid,pr,w,vis:false})};
  G.C.forEach(c=>{const [x,z]=pxToWorld(c.geo.cap.x,c.geo.cap.y);add(x,z,`<i></i><span class="cb"><b>${esc(c.name)}</b><em>${ic("crown")}${esc(c.capName||"")}</em></span>`,"cap",c.id,3,Math.max(c.name.length*8.6,(c.capName||"").length*6.5+16)+30)});
  CITY_EL.sort((a,b)=>b.pr-a.pr);
}
function updateCities(){
  if(!CITY_EL.length)return;const d=Cam.dist,mode=UI.mode;
  for(const c of CITY_EL)if(c.cap){const gd=G.C[c.cid].dead;if(c.gd!==gd){c.gd=gd;if(gd){c.el.className="city big";c.el.innerHTML=`<i></i><span>${esc(G.C[c.cid].capName||"")}</span>`;c.cap=false;c.pr=2}CITY_KEY=""}const me=c.cid===G.me,sel=c.cid===UI.sel;if(c.me!==me){c.me=me;c.el.classList.toggle("me",me)}if(c.sl!==sel){c.sl=sel;c.el.classList.toggle("sel",sel)}}
  const key=[Cam.tx,Cam.tz,d,Cam.yaw,innerWidth,innerHeight,mode].map(v=>typeof v==="number"?v.toFixed(4):v).join("|");
  if(key===CITY_KEY)return;CITY_KEY=key;
  const box=$("#cities"),log=mode==="log",set=mode==="set",far=d>(log?14:11);
  box.classList.toggle("log",log);box.classList.toggle("set",set);box.classList.toggle("far",far);box.classList.toggle("tfar",d>13.5);
  const cityOn=set?d<17.5:log?d<13:d<9,townOn=set&&d<17.5||G.co&&d<4.2,vilOn=G.co&&d<2.3,showTownTxt=d<=13.5;
  const boxes=[];
  for(const c of CITY_EL){
    const on=c.cap||(c.vil?vilOn:c.town?townOn:cityOn);let p=on?project(c.x,0,c.z):null;
    if(p&&(p.x<-80||p.x>innerWidth+80||p.y<-40||p.y>innerHeight+40))p=null;
    let ok=!!p;
    if(ok){const w=c.town&&!showTownTxt?8:c.cap&&far?c.w*.8:c.w,h=c.cap&&!far?36:20;const bx=[p.x-6,p.y-h/2,p.x+w,p.y+h/2];
      for(const o of boxes){if(bx[0]<o[2]&&bx[2]>o[0]&&bx[1]<o[3]&&bx[3]>o[1]){ok=c.cap;break}}
      if(ok)boxes.push(bx)}
    if(!ok){if(c.vis){c.el.style.display="none";c.vis=false}continue}
    if(!c.vis){c.el.style.display="";c.vis=true}
    c.el.style.transform=`translate3d(${(p.x-(c.cap?5.5:4.5)).toFixed(1)}px,${(p.y).toFixed(1)}px,0) translateY(-50%)`}
}
