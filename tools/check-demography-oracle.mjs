import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const {evaluate,runtime}=await annualOracle();
// Controlled dense input exercises diffusion, migration, conversion, immunity,
// newly seeded outbreaks and an existing virgin-soil outbreak. Not a balance run.
const result=JSON.parse(evaluate(`(()=>{
  const s=S,w=WD,L=w.landIdx;
  s.year=-8995;
  s.rels.push({id:0,name:'Contract religion',kind:'universal',fam:0,miss:0.7,cent:0.6});
  for(let k=0;k<32;k++)s.firstTech[k]={y:s.year,cell:L[0],pol:0,eth:0};
  for(let k=0;k<L.length;k++){const i=L[k];
    s.pop[i]=k%5===0?0:Math.max(100,s.K[i])*(k%3===0?1.8:0.9);
    s.eth[i]=k%s.eths.length;s.rel[i]=k%3===0?0:-1;s.immune[i]=(k%5)*0.12;s.dp[i]=(k%7)*0.1;
    s.forest[i]=w.forest0[i]*0.1;s.rp[i]=0.25;
    for(let t=0;t<32;t++)s.tk[t][i]=(k+t)%7/6;
  }
  const origin=L.find(i=>s.pop[i]>0);s.infect[origin]=3;s.ob[origin]=0;s.inf.push(origin);
  s.outbreaks.push({id:0,name:'Contract fever',origin,year:s.year-1,deaths:0,vir:0.23,cells:1,active:1,done:false,spread:[[0,origin]],hit:new Set(),virgin:true,from:0,dp:0.7});
  const snapshots=[];
  const capture=phase=>{
    const fields=[s.pop,s.fert,s.forest,s.salt,s.adapt,s.rp,s.mix,s.immune,s.dp,...s.tk];
    const sums=fields.map(a=>{let sum=0;for(const i of L)sum+=a[i];return sum});
    const samples=[];for(let k=0;k<L.length;k+=23){const i=L[k];samples.push([i,...fields.map(a=>a[i])])}
    snapshots.push({phase,rng:{...rngPositionOf(s.r)},sums,samples,
      identities:Array.from(L,i=>[s.eth[i],s.eth2[i],s.rel[i],s.mixT[i],s.infect[i],s.ob[i]]),
      infections:s.inf.slice(),outbreaks:s.outbreaks.map(o=>({id:o.id,name:o.name,origin:o.origin,year:o.year,end:o.end||0,deaths:o.deaths,virulence:o.vir,pool:o.dp||0,cells:o.cells,active:o.active,done:o.done,virgin:!!o.virgin,from:o.from||0,spread:o.spread,hit:[...o.hit]})),migrations:s.migs.length});
  };
  growth();capture('growth');migrate();capture('migrate');seaHop();capture('seaHop');
  techStep(0,0.34);techStep(0.34,0.67);techStep(0.67,1);capture('technology');
  for(let j=0;j<5;j++){disease();s.year++}capture('disease');
  return JSON.stringify(snapshots);
})()`));
const data=JSON.stringify({schema:'asabiya/demography-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,snapshots:result})+'\n';
const path=new URL('tests/native/demography-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created demography contract; review before committing.');}
else {assert.equal(await fs.readFile(path,'utf8'),data,'Original demography contract changed');console.log('Original demography contract verified.');}
