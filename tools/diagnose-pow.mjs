import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {requireOracleRuntime,root} from './lib/legacy-oracle.mjs';
requireOracleRuntime();
const data=JSON.parse(await fs.readFile(new URL('docs/phase-0/evidence/math-pow.quick.windows-node24.json',root)));
const decode=s=>s==='nan'?NaN:Buffer.from(s,'hex').readDoubleBE();
const encode=n=>{if(Number.isNaN(n))return 'nan';const b=Buffer.alloc(8);b.writeDoubleBE(n);return b.toString('hex')};
const mismatches=[];
for(let i=0;i<data.vectors.length;i++){
  const v=data.vectors[i],actual=encode(Math.pow(...v.input.map(decode)));
  if(actual!==v.output)mismatches.push({index:i,input:v.input,inputDecimal:v.input.map(decode).map(String),expected:v.output,actual});
}
console.log(JSON.stringify({platform:process.platform,arch:process.arch,node:process.version,checked:data.vectors.length,mismatches:mismatches.length,first:mismatches.slice(0,10)},null,2));
assert.equal(mismatches.length,0,'Pow difiere del oráculo Windows: conservar evidencia y limitar portabilidad');
