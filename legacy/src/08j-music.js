/* =====================================================================
   Main-menu music: plays on the start screen and while the world is being generated,
   then fades out smoothly once the map is ready. Browsers only allow sound after the
   player's first click or key press, so playback starts on that gesture if needed.
   ===================================================================== */
const MUS={el:null,want:false,fade:null,get vol(){return .55*musK()}};
const musK=()=>clamp(SET.musVol??.6,0,1); // master music volume from Settings
function musEl(){if(MUS.el)return MUS.el;const a=new Audio("menu-music.mp3");a.loop=true;a.preload="auto";a.volume=0;MUS.el=a;return a}
function musRamp(to,ms,done){const a=musEl();clearInterval(MUS.fade);const from=a.volume,t0=performance.now();
  MUS.fade=setInterval(()=>{const k=Math.min(1,(performance.now()-t0)/ms),e=k*k*(3-2*k);a.volume=Math.max(0,Math.min(1,from+(to-from)*e));if(k>=1){clearInterval(MUS.fade);MUS.fade=null;if(done)done()}},40)}
function musPlay(){if(SET.noMusic)return;MUS.want=true;const a=musEl();if(!a.paused&&!MUS.fade){if(a.volume<MUS.vol)musRamp(MUS.vol,1200);return}
  const p=a.play();if(p&&p.then)p.then(()=>musRamp(MUS.vol,1800)).catch(()=>{});else musRamp(MUS.vol,1800)}
function musStop(ms){MUS.want=false;const a=MUS.el;if(!a||a.paused)return;musRamp(0,ms||3500,()=>{if(!MUS.want){a.pause();a.currentTime=0}})}
/* music belongs to the menu and the loading screen */
function musSync(){const st=$("#start"),ld=$("#loading"),menu=st&&!st.hidden,load=ld&&!ld.hidden;if(menu||load){musPlay();gmStop(1500)}else{musStop(3500);if(G.me!=null)setTimeout(gmPlay,3600)}}
// the first gesture unlocks audio in the browser
["pointerdown","keydown"].forEach(ev=>addEventListener(ev,()=>{if(MUS.want&&MUS.el&&MUS.el.paused)musPlay()},{capture:true,passive:true}));
addEventListener("DOMContentLoaded",()=>{});
setTimeout(()=>{const mo=new MutationObserver(musSync);for(const id of ["start","loading"]){const el=$("#"+id);if(el)mo.observe(el,{attributes:true,attributeFilter:["hidden"]})}MUS.want=true;musSync()},0);
{const _tg=ACT.setTg;ACT.setTg=k=>{_tg(k);if(k==="noMusic"){if(SET.noMusic)musStop(600);else musSync()}}}

/* ---------- in-game music: a shuffled bag of tracks, every track once per round, no track twice in a row ---------- */
const GM={el:null,bag:[],last:[],want:false,fade:null,next:null,tracks:["game-music-1.mp3","game-music-2.mp3","game-music-3.mp3","game-music-4.mp3","game-music-5.mp3"]};
const gmVol=()=>.5*musK();
function gmPick(){if(!GM.bag.length){let b;for(let tries=0;tries<60;tries++){b=GM.tracks.slice();for(let i=b.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[b[i],b[j]]=[b[j],b[i]]}
      // the first two tracks of a new round are not among the last two heard
      if(!GM.last.includes(b[0])&&!GM.last.includes(b[1]))break}GM.bag=b}
  const t=GM.bag.shift();GM.last.push(t);if(GM.last.length>2)GM.last.shift();return t}
function gmRamp(to,ms,done){const a=GM.el;if(!a)return;clearInterval(GM.fade);const from=a.volume,t0=performance.now();
  GM.fade=setInterval(()=>{const k=Math.min(1,(performance.now()-t0)/ms),e=k*k*(3-2*k);a.volume=Math.max(0,Math.min(1,from+(to-from)*e));if(k>=1){clearInterval(GM.fade);GM.fade=null;if(done)done()}},40)}
function gmTrack(){const a=new Audio(gmPick());a.preload="auto";a.volume=0;a.addEventListener("ended",()=>{if(GM.el!==a)return;GM.el=null;clearTimeout(GM.next);GM.next=setTimeout(()=>{if(GM.want)gmTrack()},rint(2500,6000))});
  GM.el=a;const p=a.play();if(p&&p.then)p.then(()=>gmRamp(gmVol(),2500)).catch(()=>{});else gmRamp(gmVol(),2500)}
function gmOn(){const st=$("#start"),ld=$("#loading");return G.me!=null&&!SET.noGameMusic&&!(st&&!st.hidden)&&!(ld&&!ld.hidden)}
function gmPlay(){if(!gmOn())return;GM.want=true;if(GM.el){if(GM.el.paused){const p=GM.el.play();if(p&&p.catch)p.catch(()=>{})}gmRamp(gmVol(),1500);return}if(!GM.next)gmTrack()}
function gmStop(ms){GM.want=false;clearTimeout(GM.next);GM.next=null;const a=GM.el;if(!a)return;gmRamp(0,ms||1500,()=>{if(!GM.want&&GM.el===a){a.pause();GM.el=null}})}
// browsers start audio only after a gesture
["pointerdown","keydown"].forEach(ev=>addEventListener(ev,()=>{if(gmOn()&&(!GM.el||GM.el.paused))gmPlay()},{capture:true,passive:true}));
/* settings: master volume slider and switches */
ACT.musVol=v=>{SET.musVol=clamp(+v/100,0,1);{const l=$("#musVolV");if(l)l.textContent=Math.round(SET.musVol*100)+"%"}if(MUS.el&&!MUS.el.paused&&!MUS.fade)MUS.el.volume=MUS.vol;if(GM.el&&!GM.fade)GM.el.volume=gmVol();clearTimeout(ACT.musVol.t);ACT.musVol.t=setTimeout(saveSettings,300)};
{const _tg=ACT.setTg;ACT.setTg=k=>{_tg(k);if(k==="noGameMusic"){if(SET.noGameMusic)gmStop(600);else gmPlay()}}}
