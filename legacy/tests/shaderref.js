// Writes the map shaders exactly as the HTML version builds them for a logistics board (map size "m"),
// plus the per-frame uniform code, as the source for the Godot shader port.
//   node legacy/tests/shaderref.js <outDir>
const {chromium}=require('playwright');const fs=require('fs');const path=require('path');const D=__dirname;
const out=process.argv[2]||path.join(D,'ref','shader');
(async()=>{fs.mkdirSync(out,{recursive:true});
const b=await chromium.launch();const p=await b.newPage();await p.goto('file://'+D+'/t.html');await p.waitForTimeout(500);
const r=await p.evaluate(()=>{G.mapSize="m";setWorldScale("board");return{vs:VS,fs:FSsrc(),render:renderFrame.toString(),consts:{MW,MH,WX,WZ,TRI_S,TRI_K,TRI_H}}});
fs.writeFileSync(path.join(out,'map.vert'),r.vs);fs.writeFileSync(path.join(out,'map.frag'),r.fs);fs.writeFileSync(path.join(out,'renderFrame.js'),r.render);
fs.writeFileSync(path.join(out,'consts.json'),JSON.stringify(r.consts));console.log(out,r.fs.length,JSON.stringify(r.consts));await b.close()})();
