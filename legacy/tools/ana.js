// Map coverage to top-level declarations per source file.
// node tools/ana.js  → prints, per file, top-level functions / ACT / WINS entries with call counts
const fs=require('fs'),path=require('path'),acorn=require('acorn');
const D=path.join(__dirname,'..');
const B=process.env.B||D;const files=fs.readFileSync(B+'/build.sh','utf8').match(/JS="([^"]+)"/)[1].split(/\s+/).map(f=>f.replace('$G',B+'/g').replace('$D',D));
const src=fs.readFileSync(D+'/covsrc.js','utf8'),all=fs.readFileSync(B+'/all.js','utf8');
const base0=src.indexOf(all.slice(0,300));if(base0<0)throw "all.js not found in coverage source";
const fn=JSON.parse(fs.readFileSync(D+'/covfun.json','utf8')).sort((a,b)=>a.s-b.s);
function cov(s,e){let best=null;for(const f of fn){if(f.s<s)continue;if(f.s>e)break;if(f.e<=e+1&&(!best||f.e-f.s>best.e-best.s))best=f}return best?best.c:null}
let off=0;const out=[];
for(const f of files){const code=fs.readFileSync(f,'utf8');const b=base0+off;off+=code.length;
  let ast;try{ast=acorn.parse(code,{ecmaVersion:'latest',allowReturnOutsideFunction:true,allowAwaitOutsideFunction:true})}catch(e){out.push({file:path.basename(f),err:e.message});continue}
  for(const st of ast.body){let name=null,kind=st.type;
    if(st.type==="FunctionDeclaration")name=st.id.name;
    else if(st.type==="ExpressionStatement"&&st.expression.type==="AssignmentExpression"&&st.expression.left.type==="MemberExpression"){const L=st.expression.left;name=(L.object.name||"?")+"."+(L.property.name||L.property.value);kind="assign"}
    else if(st.type==="VariableDeclaration")name=st.declarations.map(d=>d.id.name||"{}").join(",");
    const c=(kind==="FunctionDeclaration"||kind==="assign")?cov(b+st.start,b+st.end):null;
    out.push({file:path.basename(f),name,kind,c,len:st.end-st.start,start:st.start,end:st.end})}}
fs.writeFileSync(D+'/ana.json',JSON.stringify(out));
const by={};for(const o of out){const k=o.file;by[k]=by[k]||{tot:0,dead:0,live:0,deadLen:0,liveLen:0};by[k].tot+=o.len;if(o.c===0){by[k].dead++;by[k].deadLen+=o.len}else if(o.c>0){by[k].live++;by[k].liveLen+=o.len}}
for(const k in by)console.log(k.padEnd(20),"bytes",String(by[k].tot).padStart(7),"| live fn",String(by[k].live).padStart(4),String(by[k].liveLen).padStart(7),"| zero fn",String(by[k].dead).padStart(4),String(by[k].deadLen).padStart(7));
