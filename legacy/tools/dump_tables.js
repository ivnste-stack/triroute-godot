// Loads the built HTML game (legacy/dist/all.js) in Node with a stub DOM and writes the game tables as JSON.
//   node legacy/tools/dump_tables.js <out.json>      (then native/tools/gen_game_data.py -> godot/scripts/logistics/game_data.gd)
const fs=require("fs"),vm=require("vm"),path=require("path");
const src=fs.readFileSync(path.join(__dirname,"..","dist","all.js"),"utf8");
const mk=()=>new Proxy(function(){},{get:(t,k)=>k===Symbol.toPrimitive?()=>"":k==="length"?0:mk(),apply:()=>mk(),construct:()=>mk(),set:()=>true});
const el=mk();
const ctx={document:el,console:{log(){},warn(){},error(){}},localStorage:{getItem:()=>null,setItem(){},removeItem(){}},sessionStorage:{getItem:()=>null,setItem(){}},
  navigator:{userAgent:""},screen:{},addEventListener(){},requestAnimationFrame(){},setTimeout(){},setInterval(){},clearTimeout(){},performance:{now:()=>0},
  innerWidth:1600,innerHeight:900,devicePixelRatio:1,Image:function(){},Audio:function(){return el},matchMedia:()=>({matches:false,addEventListener(){}}),
  ResizeObserver:function(){return{observe(){}}},PerformanceObserver:function(){return{observe(){}}}};
ctx.window=ctx;vm.createContext(ctx);vm.runInContext(src,ctx);
const names=["VT","CARGO","LIC","MG","MG_TR","ROLE","HAND","HUB_LV","HUB_UP","HUB_RENT","HUB_VEH","HUB_STAFF","HUB_HAND","HUB_ORD","CH_RATE","CH_BASE","CH_SPD",
  "CO_NAMES_A","CO_NAMES_B","COMP_N","PERM","UPG","IND","CG_IND","WXK","RCK","CL_WHY","GRADES","MODE_N","TINY_ISL","KM","FIRST","LAST","RES"];
const out={};for(const n of names){try{out[n]=vm.runInContext(n,ctx)}catch(e){}}
fs.writeFileSync(process.argv[2]||"tables.json",JSON.stringify(out,(k,v)=>typeof v==="function"?undefined:v));
