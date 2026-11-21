/* =====================================================================
   Gameplay screenshot: F2 (or Ctrl+Shift+S). Only the map — terrain, the grid around the board,
   roads, borders, labels, vehicles — exactly with the layers that are switched on. No interface panels.
   ===================================================================== */
function shotText(g,node,s){const t=node.textContent;if(!t||!t.trim())return;const el=node.parentElement,cs=getComputedStyle(el);
  const rg=document.createRange();rg.selectNodeContents(node);const r=rg.getBoundingClientRect();if(!r.width)return;
  g.font=`${cs.fontStyle} ${cs.fontWeight} ${parseFloat(cs.fontSize)*s}px ${cs.fontFamily}`;g.fillStyle=cs.color;g.textBaseline="middle";g.textAlign="left";
  try{g.letterSpacing=cs.letterSpacing==="normal"?"0px":(parseFloat(cs.letterSpacing)*s)+"px"}catch(e){}
  const txt=cs.textTransform==="uppercase"?t.trim().toUpperCase():t.trim();g.fillText(txt,r.left*s,(r.top+r.height/2)*s);try{g.letterSpacing="0px"}catch(e){}}
function shotEl(g,el,s,op){const cs=getComputedStyle(el);if(cs.display==="none"||cs.visibility==="hidden")return;const o=op*parseFloat(cs.opacity||"1");if(o<=.01)return;const r=el.getBoundingClientRect();
  g.globalAlpha=o;
  if(el.tagName.toLowerCase()==="svg"){const u=el.querySelector("use"),h=u&&(u.getAttribute("href")||u.getAttribute("xlink:href"));const n=h&&h.replace("#i-","");if(n&&ICONS[n]&&r.width)drawIcons(g,[n],r.left*s,(r.top+r.height/2)*s,r.width*s,cs.color);g.globalAlpha=1;return}
  const m=cs.transform&&cs.transform!=="none"&&el.children.length===0?cs.transform.match(/matrix\(([^)]+)\)/):null;
  if(m&&r.width){const [a,b]=m[1].split(",").map(parseFloat),w=parseFloat(cs.width)||0,h=parseFloat(cs.height)||0,bw=parseFloat(cs.borderTopWidth)||0,cx=(r.left+r.width/2)*s,cy=(r.top+r.height/2)*s;
    g.save();g.translate(cx,cy);g.rotate(Math.atan2(b,a));const W=(w+(cs.boxSizing==="border-box"?0:bw*2))*s,H=(h+(cs.boxSizing==="border-box"?0:bw*2))*s;
    g.fillStyle=cs.backgroundColor;g.fillRect(-W/2,-H/2,W,H);if(bw>0){g.strokeStyle=cs.borderTopColor;g.lineWidth=bw*s;g.strokeRect(-W/2+bw*s/2,-H/2+bw*s/2,W-bw*s,H-bw*s)}g.restore();g.globalAlpha=1;return}
  if(r.width&&r.height){const bg=cs.backgroundColor;if(bg&&bg!=="transparent"&&!/rgba\([^)]*,\s*0\)$/.test(bg)){g.fillStyle=bg;g.fillRect(r.left*s,r.top*s,r.width*s,r.height*s)}
    const bw=parseFloat(cs.borderTopWidth)||0;if(bw>0&&cs.borderTopStyle!=="none"){g.strokeStyle=cs.borderTopColor;g.lineWidth=bw*s;g.strokeRect((r.left+bw/2)*s,(r.top+bw/2)*s,(r.width-bw)*s,(r.height-bw)*s)}}
  for(const c of el.childNodes){if(c.nodeType===3){g.globalAlpha=o;shotText(g,c,s)}else if(c.nodeType===1)shotEl(g,c,s,o)}g.globalAlpha=1}
async function takeShot(){if(G.me==null||!GL||($("#start")&&!$("#start").hidden))return;
  const sv={res:SET.res,eco:SET.eco},s=clamp(Math.round(Math.max(devicePixelRatio||1,2)),1,3),W=Math.round(innerWidth*s),H=Math.round(innerHeight*s);
  const out=document.createElement("canvas");out.width=W;out.height=H;const g=out.getContext("2d");
  try{SET.eco=false;SET.res=innerWidth*s;guard("Скріншот",()=>renderFrame(performance.now()));
    g.fillStyle=getComputedStyle(document.body).backgroundColor||"#060b11";g.fillRect(0,0,W,H);
    g.drawImage(GL.cv,0,0,W,H);const bcv=$("#bcv");if(bcv)g.drawImage(bcv,0,0,W,H);
    const svg=$("#ovsvg");if(svg&&svg.innerHTML.trim()){const xml=new XMLSerializer().serializeToString(svg).replace("<svg",`<svg xmlns="http://www.w3.org/2000/svg" width="${innerWidth}" height="${innerHeight}"`);
      await new Promise(res=>{const im=new Image();im.onload=()=>{g.drawImage(im,0,0,W,H);res()};im.onerror=res;im.src="data:image/svg+xml;charset=utf-8,"+encodeURIComponent(xml)})}
    const cit=$("#cities");if(cit&&getComputedStyle(cit).display!=="none")for(const c of cit.children)shotEl(g,c,s,1);
    const vcv=$("#vcv");if(vcv&&vcv.width)g.drawImage(vcv,0,0,W,H)}
  finally{SET.res=sv.res;SET.eco=sv.eco;REDRAW=true;guard("Скріншот",()=>renderFrame(performance.now()))}
  const blob=await new Promise(r=>out.toBlob(r,"image/png"));if(!blob)return toast("bad","Не вдалося зробити скріншот","");
  const d=G.date||{y:0,m:0,d:1},nm=`TriRoute_${d.y}-${String(d.m+1).padStart(2,"0")}-${String(d.d).padStart(2,"0")}_${new Date().toTimeString().slice(0,8).replace(/:/g,"")}.png`;
  shotShow(blob,nm,W,H)}
function shotShow(blob,nm,W,H){const url=URL.createObjectURL(blob);let m=$("#shotBox");if(m)m.remove();m=document.createElement("div");m.id="shotBox";m.className="glass";
  m.style.cssText="position:fixed;z-index:400;right:16px;bottom:96px;width:min(380px,calc(100vw - 32px));padding:12px;display:flex;flex-direction:column;gap:10px";
  m.innerHTML=`<div class="row sp"><b>${ic("eye")} Скріншот мапи</b><button class="xbtn" aria-label="Закрити" data-shotx>${ic("close")}</button></div>
   <img src="${url}" alt="Скріншот мапи" style="width:100%;border:1px solid var(--line-hi);display:block">
   <div class="note">${W}×${H} px · тільки мапа з увімкненими шарами</div>
   <div class="row" style="gap:8px;flex-wrap:wrap"><button class="btn sm pri" data-shots>${ic("down")}Зберегти PNG</button><button class="btn sm" data-shotc>${ic("doc")}Копіювати</button></div>`;
  document.body.appendChild(m);
  m.querySelector("[data-shotx]").onclick=()=>{m.remove();setTimeout(()=>URL.revokeObjectURL(url),1000)};
  m.querySelector("[data-shotc]").onclick=async()=>{try{await navigator.clipboard.write([new ClipboardItem({"image/png":blob})]);toast("good","Скопійовано","Скріншот у буфері обміну")}catch(e){toast("warn","Браузер не дозволив копіювати","Збережіть PNG кнопкою")}};
  m.querySelector("[data-shots]").onclick=async()=>{const dl=window.claude&&window.claude.use?await window.claude.use("downloads").catch(()=>null):null;
    if(dl){try{const r=await dl.save({filename:nm,data:blob});if(r!=="declined")toast("good","Скріншот збережено",nm)}catch(e){if(e&&e.code==="declined")return;toast("warn","Не вдалося зберегти",e&&e.message||"Спробуйте ще раз")}return}
    try{const a=document.createElement("a");a.href=url;a.download=nm;document.body.appendChild(a);a.click();a.remove()}catch(e){toast("warn","Браузер не дозволив зберегти","Клацніть по зображенню правою кнопкою → «Зберегти як»")}};
  toast("good","Скріншот готовий",nm)}
addEventListener("keydown",e=>{if(e.target&&(e.target.tagName==="INPUT"||e.target.tagName==="TEXTAREA"))return;
  if((e.ctrlKey||e.metaKey)&&e.shiftKey&&(e.key==="S"||e.key==="s"||e.code==="KeyS")){e.preventDefault();e.stopPropagation();guard("Скріншот",takeShot)}},true);
