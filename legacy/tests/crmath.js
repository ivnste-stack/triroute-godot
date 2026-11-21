/* Correctly rounded Math.pow for the reference runs: the same double-double algorithm as
   native/src/core/crmath.h (Chromium's own Math.pow is within ~0.5 ulp, not correctly rounded, and
   the Godot version must be platform independent). Load it before the game: Math.pow = CR.pow */
(function(){
const SPLIT=134217729;
const qts=(a,b)=>{const s=a+b;return[s,b-(s-a)]};
const ts=(a,b)=>{const s=a+b,bb=s-a;return[s,(a-(s-bb))+(b-bb)]};
const tp=(a,b)=>{const p=a*b;let t=SPLIT*a;const ah=t-(t-a),al=a-ah;t=SPLIT*b;const bh=t-(t-b),bl=b-bh;return[p,((ah*bh-p)+ah*bl+al*bh)+al*bl]};
const add=(a,b)=>{let s=ts(a[0],b[0]);const t=ts(a[1],b[1]);s[1]+=t[0];s=qts(s[0],s[1]);s[1]+=t[1];return qts(s[0],s[1])};
const sub=(a,b)=>add(a,[-b[0],-b[1]]);
const mul=(a,b)=>{const p=tp(a[0],b[0]);p[1]+=a[0]*b[1]+a[1]*b[0];return qts(p[0],p[1])};
const muld=(a,b)=>{const p=tp(a[0],b);p[1]+=a[1]*b;return qts(p[0],p[1])};
const div=(a,b)=>{const q1=a[0]/b[0];let r=sub(a,muld(b,q1));const q2=r[0]/b[0];r=sub(r,muld(b,q2));const q3=r[0]/b[0];return add(qts(q1,q2),[q3,0])};
const LN2=[0.6931471805599453,2.3190468138462996e-17];
const N=Math.pow,MIN=2.2250738585072014e-308;
const ldx=(x,e)=>x*N(2,e); /* exact: the native pow is exact for powers of two */
function expdd(a){/* k = nearbyint(q): ties to even */
  const q=a[0]/LN2[0];let kk=Math.round(q);if(q-Math.floor(q)===.5&&Math.floor(q)%2===0)kk=Math.floor(q);
  let r=sub(a,muld(LN2,kk));r=[ldx(r[0],-10),ldx(r[1],-10)];let s=r,term=r;
  for(let i=2;i<=12;i++){term=div(mul(term,r),[i,0]);s=add(s,term);if(Math.abs(term[0])<1e-36)break}
  for(let i=0;i<10;i++)s=add(muld(s,2),mul(s,s));const e=add([1,0],s);return[ldx(e[0],kk),ldx(e[1],kk)]}
function logdd(x){const y0=Math.log(x);const t=muld(expdd([-y0,0]),x);return add([y0,0],sub(t,[1,0]))}
const plain=x=>isFinite(x)&&x>0&&x>=MIN;
function pow(x,y){if(y===0)return 1;if(x!==x||y!==y)return NaN;if(y===1)return x;if(y===2)return x*x;if(y===.5&&x>=0&&isFinite(x))return Math.sqrt(x);if(y===-1)return 1/x;
  if(!plain(x)||!isFinite(y)||x===1)return N(x,y);let t=logdd(x);t=muld(t,y);if(t[0]>709||t[0]<-708)return N(x,y);return expdd(t)[0]}
window.CRMATH={pow,nativePow:N};
})();
