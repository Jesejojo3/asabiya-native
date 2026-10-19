// Corpus de resultados de V8, no implementación de matemáticas en Go ni prueba de equivalencia.
import fs from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {requireOracleRuntime,runtime} from './lib/legacy-oracle.mjs';
requireOracleRuntime();
const args=process.argv.slice(2);
const arg=(name,fallback)=>args.includes(name)?args[args.indexOf(name)+1]:fallback;
const count=Number(arg('--count','2048'));
assert.ok(Number.isSafeInteger(count)&&count>=1&&count<=1000000);
let state=0x5a17c9e3;
const u32=()=>{state^=state<<13;state^=state>>>17;state^=state<<5;return state>>>0};
const buf=Buffer.alloc(8);
const bits=x=>{buf.writeDoubleBE(x);return Number.isNaN(x)?'nan':buf.toString('hex')};
const edges=[0,-0,Number.MIN_VALUE,-Number.MIN_VALUE,Number.MAX_VALUE,-Number.MAX_VALUE,Infinity,-Infinity,NaN,1,-1,0.5,-0.5,Math.PI,7.388074];
const broad=()=>{buf.writeUInt32BE(u32(),0);buf.writeUInt32BE(u32(),4);return buf.readDoubleBE()};
const unit=()=>u32()/4294967296;
const specs=[['sin',1],['cos',1],['exp',1],['log',1],['log10',1],['pow',2],['atan2',2],['asin',1],['acos',1],['sqrt',1],['hypot2',2],['hypot3',3],['hypot4',4]];
const summaries=[];let output;
if(args.includes('--vectors-out'))output=await fs.open(arg('--vectors-out'), 'wx');
for(const [name,arity] of specs){
  const hash=createHash('sha256');let total=0;
  const record=async input=>{const fn=name.startsWith('hypot')?Math.hypot:Math[name];const line=JSON.stringify({fn:name,input:input.map(bits),output:bits(fn(...input))})+'\n';hash.update(line);if(output)await output.write(line);total++};
  for(let i=0;i<edges.length;i++)for(let j=0;j<(arity>1?edges.length:1);j++)await record(Array.from({length:arity},(_,k)=>edges[k===0?i:(j+k-1)%edges.length]));
  for(let i=0;i<count;i++){
    let input;
    if(name==='asin'||name==='acos')input=[unit()*2-1];
    else if(name==='exp')input=[unit()*1500-750];
    else if(name==='pow')input=[i%2?Math.abs(broad()):unit()*16,unit()*40-20];
    else if(name==='log'||name==='log10'||name==='sqrt')input=[Math.abs(broad())];
    else input=Array.from({length:arity},()=>i%2?broad():unit()*20000-10000);
    await record(input);
  }
  summaries.push({fn:name,vectors:total,sha256:hash.digest('hex')});
}
if(output)await output.close();
const summary={schemaVersion:1,generator:'xorshift32/0x5a17c9e3, function-order v1, binary64 big-endian hex; NaN canonical',oracle:runtime,countPerFunction:count,summaries,
  limitations:['Sólo V8 fijado; comparación con Go/jsmath pendiente.','Los vectores no demuestran equivalencia para todo binary64.','NaN se compara por clasificación; signo de cero y bits finitos/infinito son estrictos.']};
if(args.includes('--verify'))assert.deepEqual(summary,JSON.parse(await fs.readFile(arg('--verify'),'utf8')),'Cambió el corpus matemático');
if(args.includes('--out'))await fs.writeFile(arg('--out'),JSON.stringify(summary,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(summary,null,2));
