import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const {evaluate,runtime}=await annualOracle();
const snapshots=JSON.parse(evaluate(`(()=>{
 const s=S,w=WD,L=w.landIdx;s.year=-4001;w.tcost=new Uint8Array(N).fill(2);P.crisis=20;
 for(const i of L){s.pop[i]=20000;s.K[i]=5000;s.eth[i]=w.cxA[i]<W/2?0:1;s.farm[i]=0.9;s.grain[i]=0.9;s.admin[i]=0.8;s.iron[i]=0.7;s.law[i]=0.8;s.roads[i]=0.6;s.s[i]=0.75;s.integ[i]=0.7}
 newPolity(L.find(i=>w.cxA[i]<W/2),null);newPolity(L.find(i=>w.cxA[i]>=W/2),null);
 for(const i of L)s.pol[i]=w.cxA[i]<W/2?1:2;
 const out=[];
 for(let year=0;year<6;year++){s.year++;const generator=politicsG(),stages=[];for(let state=generator.next();!state.done;state=generator.next())stages.push(rngPositionOf(s.r).calls);out.push({year:s.year,stages,rng:{...rngPositionOf(s.r)},alive:s.alive.slice(),
  polities:s.pols.slice(1).map(o=>({id:o.id,name:o.full,capital:o.capital,core:o.core,kind:o.kind,alive:o.alive,cells:o.cells,pop:o.pop,K:o.K,E:o.E,S:o.S,psi:o.psi,culture:o.cult,reach:o.h,gate:o.gate,mandate:o.mandate,inequality:o.ineq,complexity:o.cplx,treasury:o.treas,integrated:o.integ??null,niche:o.ni||null,fac:o.fac||null,coastN:o.coastN??null,kids:o.kids.slice(),enemies:[...o.enemies],nb:[...o.nb]})),
  cells:Array.from(L,i=>[s.pol[i],s.pop[i],s.s[i],s.integ[i],s.dist[i],s.taken[i],s.fort[i],s.eth[i],s.rel[i],s.uni[i],s.uniFam[i]]),
  wars:s.wars.map(w=>({id:w.id,a:w.a.slice(),d:w.d.slice(),start:w.start,end:w.end,gainA:w.gA,gainD:w.gD,lastGain:w.lastGain||0,civil:w.civil,holy:w.holy,outcome:w.outcome})),
  activeWars:s.activeWars.slice(),figures:s.figs.length});}
 return JSON.stringify(out);
})()`));
assert.ok(snapshots[0].polities.length>2,'Must create and visit rebels live');
assert.ok(snapshots[0].polities.some(p=>p.culture===null),'Must retain undefined/NaN legacy effect');
const data=JSON.stringify({schema:'asabiya/politics-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,snapshots})+'\n';
const path=new URL('tests/native/politics-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created politics contract; review before committing.');}
else{assert.equal(await fs.readFile(path,'utf8'),data,'Original politics contract changed');console.log('Original politics contract verified.');}
