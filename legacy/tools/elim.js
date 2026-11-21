// Iteratively remove top-level functions / ACT.x / WINS.x / MAILACT.x / plain consts that nothing references.
// node tools/elim.js [--dry] [--keep=a,b]   (files from build.sh; HTML in g/01-head.html and g/02-body.html counts as references)
const fs=require('fs'),path=require('path'),acorn=require('acorn');
const D=path.join(__dirname,'..');const dry=process.argv.includes('--dry');
const keep=new Set((process.argv.find(a=>a.startsWith('--keep='))||'--keep=').slice(7).split(',').filter(Boolean));
const files=fs.readFileSync(D+'/build.sh','utf8').match(/JS="([^"]+)"/)[1].split(/\s+/).map(f=>f.replace('$G',D+'/g').replace('$D',D)).filter(f=>!f.endsWith('logcities.js'));
const html=['g/01-head.html','g/02-body.html'].map(f=>fs.readFileSync(D+'/'+f,'utf8')).join('\n');
const esc=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
let round=0,total=[];
for(;;){round++;
  const src=files.map(f=>fs.readFileSync(f,'utf8'));
  const cands=[];
  src.forEach((code,fi)=>{const ast=acorn.parse(code,{ecmaVersion:'latest',allowReturnOutsideFunction:true,allowAwaitOutsideFunction:true});
    for(const st of ast.body){let name=null,kind=null;
      if(st.type==="FunctionDeclaration"){name=st.id.name;kind="fn"}
      else if(st.type==="ExpressionStatement"&&st.expression.type==="AssignmentExpression"&&st.expression.left.type==="MemberExpression"&&st.expression.left.object.type==="Identifier"&&["ACT","WINS","MAILACT"].includes(st.expression.left.object.name)&&!st.expression.left.computed){name=st.expression.left.object.name+"."+st.expression.left.property.name;kind="key"}
      else if(st.type==="VariableDeclaration"&&st.declarations.length===1&&st.declarations[0].id.type==="Identifier"){const init=st.declarations[0].init;
        if(init&&["ArrowFunctionExpression","FunctionExpression","ArrayExpression","ObjectExpression","Literal","TemplateLiteral"].includes(init.type)){name=st.declarations[0].id.name;kind="var"}}
      if(name&&!keep.has(name))cands.push({fi,name,kind,start:st.start,end:st.end})}});
  const dead=[];
  for(const c of cands){const short=c.kind==="key"?c.name.split(".")[1]:c.name;
    const re=c.kind==="key"?new RegExp(`\\b${esc(c.name)}\\b|["'\`]${esc(short)}["'\`:]|[=:]${esc(short)}\\b|\\[["']${esc(short)}`):new RegExp(`(^|[^\\w$.])${esc(c.name)}(?![\\w$])`);
    let used=false;
    for(let i=0;i<src.length&&!used;i++){const code=i===c.fi?src[i].slice(0,c.start)+src[i].slice(c.end):src[i];if(re.test(code))used=true}
    if(!used&&re.test(html))used=true;
    if(!used)dead.push(c)}
  if(!dead.length)break;
  total.push(...dead.map(d=>path.basename(files[d.fi])+":"+d.name));
  if(dry){console.log(dead.map(d=>path.basename(files[d.fi])+":"+d.name).join("\n"));break}
  const byF={};for(const d of dead)(byF[d.fi]=byF[d.fi]||[]).push(d);
  for(const fi in byF){let code=src[fi];for(const d of byF[fi].sort((a,b)=>b.start-a.start)){let e=d.end;while(code[e]===";"||code[e]===" ")e++;if(code[e]==="\n")e++;code=code.slice(0,d.start)+code.slice(e)}fs.writeFileSync(files[fi],code)}
  if(round>40)break}
if(!dry)console.log("removed "+total.length+" in "+round+" rounds:\n"+total.join(" "));
