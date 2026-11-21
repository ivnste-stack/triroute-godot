/* ================= NEWS / MAIL / MARKERS ================= */
function addNews(cid,tone,icon,text){
  G.news.unshift({d:{...G.date},cid,tone,icon,text,me:cid===G.me||text.includes(G.C[G.me]?.name)});
  if(G.news.length>300)G.news.pop();
  UI.newsDirty=true;UI.feedDirty=true;(G.tq=G.tq||[]).push(G.news[0]);if(G.tq.length>40)G.tq.shift();
}

/* ================= RANDOM EVENTS ================= */

/* ---------- pending player items (minister requests, scandals) ---------- */

/* ---------- advisor ---------- */
