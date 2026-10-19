import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const {evaluate,runtime}=await annualOracle();
const result=JSON.parse(evaluate(`(()=>{
 const s=S,w=WD,L=w.landIdx;s.year=-1000;P.sandbox=true;P.cataclysms=0;w.elev=new Float32Array(N).fill(300);
 for(const i of L){s.pop[i]=500000;s.K[i]=600000;s.eth[i]=0;s.farm[i]=0.9;s.herd[i]=0.7;s.metal[i]=0.8;s.admin[i]=0.8;s.s[i]=0.6;s.integ[i]=0.7;s.fort[i]=0.5}
 const origin=L.find(i=>w.T[i]>5);newPolity(origin,null);const o=s.pols[1];for(const i of L)s.pol[i]=1;o.cells=L.length;o.pop=L.length*500000;o.maxCells=o.cells;o.tier=tierOf(o);o.full=fullName(o);
 const snapshots=[],capture=phase=>snapshots.push({phase,rng:{...rngPositionOf(s.r)},favor:s.favor,
  cells:Array.from(L,i=>[s.pop[i],s.s[i],s.integ[i],s.fort[i],s.kMod[i],s.kModUntil[i],s.rel[i],s.infect[i],s.ob[i]]),
  tech:s.tk.map(a=>Array.from(L,i=>a[i])),
  state:{mandate:o.mandate,shock:o.shock,E:o.E,culture:o.cult,rel:o.rel},
  omens:s.omens.map(om=>({id:om.id,type:om.type,cell:om.k,year:om.y,owner:om.owner,place:om.place,populationBefore:om.popBefore,followed:om.followed,cells:om.cells,km:om.km,religion:om.rel??-1,plague:om.plague??-1,cataclysm:om.cata??-1})),
  cataclysms:s.cataclysms.map(c=>({id:c.id,kind:c.kind,name:c.name,year:c.y,cell:c.cell,km:c.km,scope:c.scope,deaths:c.deaths,omen:c.omen,hit:c.hit.slice(),eraFrom:c.eraFrom,eraTo:c.eraTo})),
  religions:s.rels.map(r=>({id:r.id,name:r.name,founder:r.founder,kind:r.kind,miss:r.miss,cent:r.cent,states:r.states.slice()})),
  outbreaks:s.outbreaks.map(p=>({name:p.name,vir:p.vir,origin:p.origin})),figures:s.figs.map(f=>({name:f.name,kind:f.kind,born:f.born,died:f.died}))});
 for(const type of Object.keys(OMENS)){const result=castOmen(type,origin);if(!result.ok)throw new Error(type+': '+result.msg)}capture('eightOmens');
 for(const a of s.tk)for(const i of L)a[i]=1;castOmen('spark',origin);capture('sparkFallback');
 for(const key of Object.keys(CATA))cataclysm(key,origin,false);capture('sevenCataclysms');
 s.year+=50;omenPass();capture('followup');
 const checkRng=rngPositionOf(s.r).calls,invalid=[omenCheck('unknown',origin),omenCheck('kindle',-1),omenCheck('plague',origin)];
 if(checkRng!==rngPositionOf(s.r).calls)throw new Error('Checks consumed RNG');
 const volcanoes=[];for(let n=0;n<20;n++){volcano();volcanoes.push({rng:{...rngPositionOf(s.r)},dT:s.dT,years:s.dTt,mandate:o.mandate,shock:o.shock,outbreaks:s.outbreaks.map(p=>({name:p.name,origin:p.origin,vir:p.vir}))})}
 return JSON.stringify({origin,invalid,snapshots,volcanoes});
})()`));
assert.equal(result.snapshots[0].omens.length,8);
assert.ok(result.snapshots[2].cataclysms.length>=8);
assert.ok(result.volcanoes.some(x=>x.dT===-2.3)&&result.volcanoes.some(x=>x.dT!==-2.3),'Must exercise both eruption branches');
const data=JSON.stringify({schema:'asabiya/interventions-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,...result})+'\n';
const path=new URL('tests/native/interventions-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created interventions contract; review before committing.');}
else{assert.equal(await fs.readFile(path,'utf8'),data,'Original interventions contract changed');console.log('Original interventions contract verified.');}
