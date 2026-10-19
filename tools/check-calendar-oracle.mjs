import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const scenarios=[];
for(const late of [false,true]){
 const {evaluate,runtime}=await annualOracle();
 const result=JSON.parse(evaluate(`(()=>{
  const s=S,w=WD,L=w.landIdx,late=${late};w.elev=new Float32Array(N).fill(300);w.tcost=new Uint8Array(N).fill(2);
  if(late){s.year=s.start=-40;P.formRate=30;P.warRate=4;s.hearths=[];s.stats=[];for(const i of L){s.pop[i]=500000;s.eth[i]=w.cxA[i]<W/2?0:1;for(const a of s.tk)a[i]=0.9;s.s[i]=0.6;s.integ[i]=0.7}for(let k=0;k<TECH.length;k++)s.firstTech[k]={y:s.year,cell:L[0],eth:0,pol:0};recordStats();s.snap={keys:new Map(),diffs:new Map(),layers:new Map(),last:null};snapshot()}
  const out=[];
  for(let year=1;year<=(late?80:60);year++){step();if(year%20!==0)continue;
   const arrays=[s.pop,s.K,s.s,s.integ,s.fert,s.forest,s.salt,s.adapt,s.dp,s.car,...s.tk];
   const sums=arrays.map(a=>{let v=0;for(const i of L)v+=a[i];return v}),samples=[];for(let k=0;k<L.length;k+=31){const i=L[k];samples.push([i,...arrays.map(a=>a[i])])}
   const layer=layerAt(s.year),ownership=polAt(s.year);
   out.push({year:s.year,rng:{...rngPositionOf(s.r)},favor:s.favor,sums,samples,
    ids:Array.from(L,i=>[s.pol[i],s.eth[i],s.eth2[i],s.rel[i],s.city[i],s.infect[i],s.ob[i]]),
    polities:s.pols.slice(1).map(o=>({id:o.id,name:o.full,alive:o.alive,cells:o.cells,pop:o.pop,core:o.core,capital:o.capital,culture:o.cult})),
    wars:s.wars.map(o=>({id:o.id,a:o.a.slice(),d:o.d.slice(),start:o.start,end:o.end,gainA:o.gA,gainD:o.gD})),
    stats:s.stats.map(st=>({year:st.y,population:st.pop,polities:st.np,hordes:st.nh,people:st.pe,leadingEra:st.lead,eraShare:st.eraPop})),
    ownership:ownership?Array.from(ownership):null,
    layer:layer?{year:layer.y,people:Array.from(layer.eth),religion:Array.from(layer.rel),density:Array.from(layer.pop),cohesion:Array.from(layer.s),era:Array.from(layer.era)}:null});
  }
  return JSON.stringify(out);
 })()`));
 scenarios.push({late,snapshots:result});
}
assert.ok(scenarios[1].snapshots.at(-1).polities.length>0,'Late calendar must create states');
const runtime=(await annualOracle()).runtime;
const data=JSON.stringify({schema:'asabiya/calendar-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,scenarios})+'\n';
const path=new URL('tests/native/calendar-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created calendar contract; review before committing.');}
else{assert.equal(await fs.readFile(path,'utf8'),data,'Original calendar contract changed');console.log('Original calendar contract verified.');}
