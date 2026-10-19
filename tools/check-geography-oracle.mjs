// Small mechanical contracts, not a V8/Go numerical equivalence campaign.
// Evaluate immutable source slices; never modify the HTML or older fixtures.
import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {root, runtime, requireOracleRuntime} from './lib/legacy-oracle.mjs';

requireOracleRuntime();
const html=await fs.readFile(new URL('reference/v0.6/Asabiya History Engine (Copy).html',root),'utf8');
assert.equal(createHash('sha256').update(html).digest('hex'),runtime.referenceSha256);
const lines=html.split('\n');
const source=(first,last)=>lines.slice(first-1,last).join('\n');
const begin=html.indexOf('  const lat=new Float32Array(N)');
const end=html.indexOf('  if(w.isEarth){',begin);
assert.ok(begin>0 && end>begin);
const geography=html.slice(begin,end);
const heap=geography.slice(geography.indexOf('  const hpush='),geography.indexOf('  const n8='));
assert.match(heap,/hk\[p\]<=hk\[n\]/);
const common=source(385,385)+'\n'+source(407,411)+'\n'+source(504,507)+'\n'+source(1927,1943);
assert.match(common,/const clamp/);assert.match(common,/ecoReady:true/);
const width=16,height=12,input={width,height,elevation:[],land:[],temperature:[],precipitation:[],amplitude:[],roughness:[]};
for(let y=0;y<height;y++)for(let x=0;x<width;x++){
  const i=y*width+x;
  const land=(x>=2&&x<=6&&y>=2&&y<=10)||(x>=10&&x<=12&&y>=5&&y<=8)||((x===0||x>=14)&&y>=4&&y<=8)||(x>=5&&x<=7&&y<=1);
  input.land.push(+land);
  input.elevation.push(land?(x>=10?100:(x===4&&y===7?5:(y===6?200:5))):-100);
  input.temperature.push(-15+i%45);input.precipitation.push(100+(i*97)%2100);
  input.amplitude.push(Math.fround(.25+(i%17)*2.5));input.roughness.push(Math.fround((i%11)/10));
}
const context=vm.createContext({input});
const output=vm.runInContext(`const W=input.width,H=input.height,N=W*H,AGW=40,AGH=20;\n`+common+`\n(function(){
 const elev=Float32Array.from(input.elevation),land=Uint8Array.from(input.land),T=Float32Array.from(input.temperature),Pr=Float32Array.from(input.precipitation),amp=Float32Array.from(input.amplitude),rough=Float32Array.from(input.roughness);
 const w={elev,land,T,Pr,amp,rough};
 ${geography}
 prepEco(w);
 const keys=['lat','area','x3','y3','z3','cosLon','sinLon','cosLat','nb','coast','lm','lmSize','down','acc','rv','sF','sH','nomad','biome','gs','leach','trop','tcost','tsetse','monZone','desert','wi','wf','ls','lt','ld','forest0','heavy','mal','oncho','circ','nT','nM','nN','nD'];
 return Object.fromEntries([...keys.map(k=>[k,Array.from(w[k]||[])]),['filled',Array.from(filled)],['order',order]]);
})()`,context,{timeout:5000});
const operations=[['push',1,5],['push',2,5],['push',3,5],['push',4,5],['pop'],['push',5,4],['push',6,5],['pop'],['pop'],['push',7,5],['push',8,5],['pop'],['pop'],['pop'],['pop'],['pop']];
const heapPops=vm.runInContext(`(()=>{const hk=[],hv=[],pops=[];${heap}
 for(const op of ${JSON.stringify(operations)}){if(op[0]==='push')hpush(op[1],op[2]);else pops.push(hpop())}return pops})()`,context);
const fixture={schema:'asabiya/geography-contract-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,heap:{operations,pops:Array.from(heapPops)},input,output:JSON.parse(JSON.stringify(output))};
const path=new URL('tests/native/geography-contract.v06.json',root);
const encoded=JSON.stringify(fixture)+'\n';
if(process.argv.includes('--write')){await fs.writeFile(path,encoded);console.log('Created new geography contract fixture; review before committing.');}
else {assert.equal(await fs.readFile(path,'utf8'),encoded,'Geography source contract changed; investigate before editing fixtures');console.log('Original geography/heap fixture verified.');}
