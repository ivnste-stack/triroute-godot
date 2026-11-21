/* =====================================================================
   Start of a logistics game by difficulty:
   Навчальна — the player picks any state on the map; Звичайна — five suggested capitals;
   Жорстка — the game itself puts the headquarters into a hard country.
   ===================================================================== */
function coStartDesc(p){const c=G.C[p.cid];return `Населення міста ${fmtSP(p.pop)} · рівень цін ×${priceK(p.cid).toFixed(2)} · зарплати ×${wageK(p.cid).toFixed(2)} · ризики: ${RISK_N[riskLvl(p.cid)][0].toLowerCase()}`}
function coStartPick(caps,pickN){const d=G.diff??1;
  if(d===0){UI.coPickHQ=true;pickBar(true);
    queueModal({icon:"globe",eyebrow:"Навчальна складність",title:"Оберіть країну старту",body:`<p>Клікніть на мапі на будь-яку державу: штаб відкриється в її столиці. Перед вибором покажемо ціни, зарплати й ризики цієї країни.</p><div class="hint">${ic("bulb")}<div>У <b>багатих</b> країнах доставки дорожчі, але дорожчі й люди. У <b>бідних</b> праця дешева, проте посилки коштують копійки, а ризики вищі. Шар «Ризики перевезень» (клавіша 3) підкаже, де небезпечно.</div></div>`,choices:[{t:"Обрати на мапі",d:"Камера покаже весь світ",f(){Cam.tdist=WX*1.03;Cam.ttx=0;Cam.ttz=.55}}]});return true}
  if(d===2){const p=caps.slice().sort((a,b)=>(coRisk(b.cid)+(1-G.C[b.cid].dev)*.9)-(coRisk(a.cid)+(1-G.C[a.cid].dev)*.9))[0]||pickN[0];coSetHQ(p.id);
    queueModal({icon:"alert",tone:"warn",eyebrow:"Жорстка складність",title:`Штаб у місті ${p.name}`,body:`<p>Компанія стартує в одній з найважчих країн світу — <b>${esc(G.C[p.cid].name)}</b>. Дешева праця, але копійчані доставки, повільна митниця й ризики на дорогах.</p><div class="note">${esc(coStartDesc(p))}</div>`,choices:[{t:"Почати",d:"Удачі",f(){}}]});return true}
  return false}
function pickBar(on){let b=$("#pickBar");if(!on){if(b)b.remove();return}if(b)return;b=document.createElement("div");b.id="pickBar";b.className="glass";
  b.style.cssText="position:fixed;z-index:60;left:50%;top:88px;transform:translateX(-50%);padding:10px 16px;display:flex;align-items:center;gap:10px;font-size:13px";
  b.innerHTML=`${ic("pin")}<span>Клікніть на державу, щоб відкрити в ній штаб</span>`;document.body.appendChild(b)}
{const _cc=coClick;coClick=function(x,y){if(!UI.coPickHQ)return _cc(x,y);const w=pickPlane(x,y),cid=w?worldToCountry(w):-1;if(cid<0||!G.C[cid]){toast("warn","Тут немає держави","Клікніть на сушу");return true}
  const p=PL.find(q=>q.cid===cid&&q.type==="cap")||PL.filter(q=>q.cid===cid).sort((a,b)=>b.pop-a.pop)[0];if(!p){toast("warn","У цій державі немає міст","Оберіть іншу");return true}
  queueModal({icon:"building",eyebrow:"Країна старту",title:`${p.name}, ${G.C[cid].name}`,body:`<p>${esc(coStartDesc(p))}</p>`,choices:[{t:"Відкрити штаб тут",d:"Компанія стартує в цій столиці",hl:1,f(){UI.coPickHQ=false;pickBar(false);coSetHQ(p.id);ACT.coFly(p.id)}},{t:"Обрати іншу країну",d:"Повернутися до мапи",f(){}}]});return true}}

/* start pick: hovering anywhere over a state shows what starting there means */
/* demand for freight: enterprises and people of the state's cities, rich states order more — low / medium / high against the other states */
function coDemand(cid){if(!coDemand.q){const v=G.C.map(c=>PL.filter(p=>p.cid===c.id).reduce((a,p)=>a+firmsOf(p.id).length*Math.sqrt(p.pop+.05),0)*(.5+c.dev));coDemand.v=v;const s=v.slice().sort((a,b)=>a-b);coDemand.q=[s[Math.floor(s.length/3)],s[Math.floor(s.length*2/3)]]}
  const x=coDemand.v[cid]||0,q=coDemand.q;return x>=q[1]?["Високий","good"]:x>=q[0]?["Середній","warn"]:["Низький","bad"]}
function coStartTip(e){const w=pickPlane(e.clientX,e.clientY),cid=w?worldToCountry(w):-1;if(cid<0||!G.C[cid])return null;const c=G.C[cid];
  const p=PL.find(q=>q.cid===cid&&q.type==="cap")||PL.filter(q=>q.cid===cid).sort((a,b)=>b.pop-a.pop)[0];if(!p)return null;const n=PL.filter(q=>q.cid===cid).length,r=RISK_N[riskLvl(cid)];
  return `<div class="row sp" style="gap:12px"><b style="font-size:14px">${esc(c.name)}</b><span class="note">${n} міст</span></div>
   <div class="kv" style="margin-top:8px"><span>Штаб у столиці</span><b>${esc(p.name)}</b><span>Населення столиці</span><b class="num">${fmtSP(p.pop)}</b><span>Ціни на доставку</span><b class="num">×${priceK(cid).toFixed(2)}</b><span>Зарплати</span><b class="num">×${wageK(cid).toFixed(2)}</b><span>Попит на перевезення</span><b class="${coDemand(cid)[1]}">${coDemand(cid)[0]}</b><span>Ризик перевезень</span><b class="${r[1]}">${r[0]}</b></div>
   <div class="note" style="margin-top:8px">Клік — відкрити штаб тут</div>`}
