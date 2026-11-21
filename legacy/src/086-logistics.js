/* ================= LOGISTICS LAYER: highways, railways, airports, ports ================= */
const LOG={hw:[],rail:[],air:[],ports:[],cities:[],built:false};
const CITY_A=["Нов","Бер","Гран","Сол","Віл","Мар","Кор","Тал","Ост","Дар","Лім","Сен","Ар","Вест","Річ","Зал"];
const CITY_M=["о","е","ан","ор","ел","ар","ін","ос","ур","ив","ес","ал"];
const CITY_B=["град","порт","бург","ополь","ен","ія","ов","ар","іс","мир","ськ","віль","анда","ехт"];
const VIL_B=["івка","ичі","ине","ове","ка","ці","ин","енки"];
const fmtSP=p=>p>=1?p.toFixed(2)+" млн":p*1000>=10?(p*1000).toFixed(0)+" тис.":(p*1000).toFixed(1)+" тис.";
/* organic routing: noisy terrain cost + strong preference for already-built roads → arterial network */
let LNOISE=null,LUSE=null;
let LOG_RW=1.2;
function drawLogistics(g,dpr){
  if(!LOG.built)return; // roads and railways are drawn on every map layer
  const m=GL.vp,W=g.canvas.width,H=g.canvas.height,sw=W/2,sh=H/2;
  const prj=(x,z)=>{const cw=m[3]*x+m[11]*z+m[15];if(cw<=.05)return null;const X=(m[0]*x+m[8]*z+m[12])/cw*sw+sw,Y=sh-(m[1]*x+m[9]*z+m[13])/cw*sh;if(X<-40*W||X>41*W||Y<-40*H||Y>41*H)return null;return[X,Y]}; // far-off vertices still anchor long straight segments at close zoom
  const vb=G.board?vbox():null;
  const add=(p,o)=>{if(o&&!inVB(o,p,vb))return;clipPath(g,p,m,sw,sh)};
  const zw=clamp(Math.pow(12/Cam.dist,.6),.8,3.6)*dpr;g.lineJoin="round";g.lineCap="round";g.setLineDash([]);
  const V=k=>typeof vis!=="function"||vis(k);
  // logistics company: every road is drawn with one standard width
  if(LOG.rail.length&&V("rail")){g.beginPath();for(const r of LOG.rail)add(r.p,r);
    const rw=1.15*zw;g.strokeStyle="rgba(20,10,4,.55)";g.lineWidth=rw*2.6;g.stroke();g.strokeStyle="#6b3b1a";g.lineWidth=rw*1.85;g.stroke()}
  {LOG_RW=1.15*zw;g.beginPath();for(const h of LOG.hw){if(h.lv>=3)continue;if(V("r2"))add(h.p,h)}g.strokeStyle="rgba(6,12,18,.6)";g.lineWidth=LOG_RW+1.6*dpr;g.stroke();g.strokeStyle="#f4b453";g.lineWidth=LOG_RW;g.stroke();if(V("r3")){g.beginPath();for(const h of LOG.hw)if(h.lv>=3)add(h.p,h);g.strokeStyle="rgba(6,12,18,.55)";g.lineWidth=LOG_RW*2.6;g.stroke();g.strokeStyle="#f6b94f";g.lineWidth=LOG_RW*1.85;g.stroke()}}

  g.globalAlpha=1;
}
function updateLegend(){const el=$("#legend");if(el)el.hidden=true}
