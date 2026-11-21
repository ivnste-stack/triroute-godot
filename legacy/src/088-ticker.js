
/* ================= NEWS TICKER: continuous scroll, new items queue at the end ================= */
const TK={off:0,last:0,cyc:0};
function tickerStep(t){
  const tr=$("#tickTrack"),box=$("#ticker");if(!tr||!box||box.offsetParent===null)return;
  const dt=Math.min(100,t-(TK.last||t));TK.last=t;TK.off+=dt*.045;
  // drop items that scrolled out on the left
  let first=tr.firstElementChild;
  while(first&&first.offsetWidth+28<=TK.off){TK.off-=first.offsetWidth+28;first.remove();first=tr.firstElementChild}
  // append the next queued item once the tail comes into view
  if(tr.scrollWidth-TK.off<box.clientWidth+40){let n=(G.tq||[]).shift();if(!n&&G.news.length){n=G.news[TK.cyc%Math.min(12,G.news.length)];TK.cyc++}
    if(n){const s=document.createElement("span");s.className="ti";s.innerHTML=`<i style="background:${n.tone==="bad"?"var(--bad)":n.tone==="good"?"var(--good)":n.tone==="warn"?"var(--warn)":"var(--accent)"}"></i>${esc(n.text)}`;tr.appendChild(s)}}
  tr.style.transform=`translate3d(${-TK.off.toFixed(1)}px,0,0)`;
}
