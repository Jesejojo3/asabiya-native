import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const {evaluate,runtime}=await annualOracle();
const result=JSON.parse(evaluate(`(()=>{
 const s=S,L=WD.landIdx;s.year=-4500;P.mixing=10;P.faith=10;
 const firstPeople=s.eths.length;
 s.pols.push({id:1,kind:'state',full:'Contract kingdom',capital:L[0],core:0,alive:true,rel:-1,cityPop:0,mp:200000});s.alive.push(1);
 for(let k=0;k<L.length;k++){const i=L[k];s.pop[i]=200000;s.eth[i]=0;s.eth2[i]=1;s.mix[i]=0.4;s.mixT[i]=15;s.pol[i]=1;s.farm[i]=1;s.paper[i]=1;s.admin[i]=0.8}
 mixPass();cityPass();foundReligion(s.pols[1]);
 for(const i of L)s.rel[i]=0;s.pols[1].rel=0;
 for(let j=0;j<8;j++){s.year+=20;relPass()}
 exitPass(0,0.5);exitPass(0.5,1);poolPass();caravanPass();
 return JSON.stringify({rng:rngPositionOf(s.r),firstPeople,
  people:s.eths.slice(firstPeople).map(e=>({id:e.id,name:e.name,parent:e.parent,parent2:e.parent2,alive:e.alive,stillborn:!!e.stillborn})),
  cells:Array.from(L,i=>[s.eth[i],s.eth2[i],s.mix[i],s.mixT[i],s.city[i],s.rel[i],s.exit[i],s.circE[i],s.dp[i]]),
  cities:s.cities.map((c,id)=>({id,name:c.name,cell:c.cell,born:c.born,people:c.eth,peak:c.peak,holy:!!c.holy})),
  religions:s.rels.map(R=>({id:R.id,name:R.name,founder:R.founder,born:R.born,origin:R.origin,holy:R.holy,polity:R.pol,people:R.eth,family:R.fam,kind:R.kind,missionary:R.miss,centralization:R.cent,holder:R.holder,rgb:R.rgb,parent:R.parent,kids:R.kids,cells:R.cells,population:R.pop,peak:R.peak,alive:R.alive,states:R.states,councils:R.councils,died:R.died||0,lon:R.lon||0,lat:R.la||0})),
  rulers:s.figs.map(f=>({name:f.name,kind:f.kind,born:f.born,died:f.died,polity:f.pol,people:f.eth,religion:f.rel})),
  routes:s.routes.length});
})()`));
const {evaluate:tradeEvaluate}=await annualOracle();
const trade=JSON.parse(tradeEvaluate(`(()=>{
 const s=S,w=WD;w.land.fill(0);w.coast.fill(0);w.landIdx=Int32Array.from({length:W},(_,x)=>(H/2|0)*W+x);
 s.year=27;s.pols.push({id:1,full:'West kingdom'},{id:2,full:'East kingdom'});
 for(let x=0;x<W;x++){const i=w.landIdx[x];w.land[i]=1;w.desert[i]=x>=10&&x<=20?1:0;w.Pr[i]=w.desert[i]?100:800;w.area[i]=100;s.pop[i]=10000;s.pol[i]=x<16?1:2;s.eth[i]=x<16?0:1;s.camel[i]=1}
 caravanPass();const created=s.routes.map(r=>({id:r.id,key:r.key,born:r.born,last:r.last,a:r.a,b:r.b,path:r.path}));
 const intensities=Array.from(w.landIdx,i=>s.car[i]);s.year=107;s.camel.fill(0);caravanPass();
 return JSON.stringify({rng:rngPositionOf(s.r),created,intensities,remaining:s.routes.length});
})()`));
assert.ok(trade.created.length>0,'Trade fixture must exercise a real route');
const data=JSON.stringify({schema:'asabiya/society-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,...result,trade})+'\n';
const path=new URL('tests/native/society-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created society contract; review before committing.');}
else{assert.equal(await fs.readFile(path,'utf8'),data,'Original society contract changed');console.log('Original society contract verified.');}
