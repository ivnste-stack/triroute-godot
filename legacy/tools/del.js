// Delete top-level statements by name: node tools/del.js file.js name1 name2 ...
// names: function name, var/const/let name (any declarator), or assignment target text (ACT.x, WINS.y, MAILACT.z)
const fs=require('fs'),acorn=require('acorn');
const [f,...names]=process.argv.slice(2);const want=new Set(names);
let code=fs.readFileSync(f,'utf8');
const ast=acorn.parse(code,{ecmaVersion:'latest',allowReturnOutsideFunction:true,allowAwaitOutsideFunction:true});
const cuts=[];const found=new Set();
for(const st of ast.body){let ns=[];
  if(st.type==="FunctionDeclaration")ns=[st.id.name];
  else if(st.type==="VariableDeclaration")ns=st.declarations.map(d=>code.slice(d.id.start,d.id.end));
  else if(st.type==="ExpressionStatement"&&st.expression.type==="AssignmentExpression")ns=[code.slice(st.expression.left.start,st.expression.left.end)];
  if(ns.some(n=>want.has(n))){if(ns.length>1&&!ns.every(n=>want.has(n))){console.error("partial multi-declarator, skipped: "+ns.join(","));continue}
    let e=st.end;while(code[e]===";"||code[e]===" ")e++;if(code[e]==="\n")e++;cuts.push([st.start,e]);ns.forEach(n=>found.add(n))}}
for(const n of want)if(!found.has(n))console.error("not found: "+n);
cuts.sort((a,b)=>b[0]-a[0]);for(const [s,e] of cuts)code=code.slice(0,s)+code.slice(e);
fs.writeFileSync(f,code);console.log(f+": removed "+cuts.length);
