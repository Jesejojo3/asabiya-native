import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const {evaluate,runtime}=await annualOracle();
const result=JSON.parse(evaluate(`(()=>{
 const s=S,w=WD,L=w.landIdx;s.year=-4000;w.tcost=new Uint8Array(N).fill(2);
 for(let k=0;k<L.length;k++){const i=L[k];s.pop[i]=20000;s.K[i]=18000;s.eth[i]=w.cxA[i]<W/2?0:1;s.farm[i]=0.9;s.grain[i]=0.9;s.admin[i]=0.8;s.iron[i]=0.7;s.law[i]=0.8;s.roads[i]=0.6;s.s[i]=0.75;s.integ[i]=0.7}
 const a=L.find(i=>w.cxA[i]<W/2),b=L.find(i=>w.cxA[i]>=W/2);
 newPolity(a,null);newPolity(b,null);
 for(const i of L)s.pol[i]=w.cxA[i]<W/2?1:2;
 for(const id of s.alive){const o=s.pols[id],cells=polCells(id);o.cells=cells.length;o.pop=cells.length*20000;o.K=cells.length*18000;o.S=0.75;o.press=o.pop/o.K;o.adm=0.8;o.nomF=0.1;o.coastN=0;o.tax=o.pop*0.1;o.maxCells=o.cells;o.cityPop=o.pop*0.3;o.E=0.3;o.cult=0.8;o.psi=0.3;o.nb.set(id===1?2:1,10);o.tier=tierOf(o);o.full=fullName(o)}
 const captures=[];const capture=phase=>captures.push({phase,rng:{...rngPositionOf(s.r)},
  polities:s.pols.slice(1).map(o=>({id:o.id,base:o.base,full:o.full,peak:o.peak,core:o.core,capital:o.capital,born:o.born,dynasty:o.dyn,generation:o.gen,kind:o.kind,tier:o.tier,from:o.from,kids:o.kids.slice(),rgb:o.rgb,E:o.E,S:o.S,pop:o.pop,K:o.K,cells:o.cells,inequality:o.ineq||0,complexity:o.cplx||0,treasury:o.treas||0,burden:o.burden||0,PT:o.pT||0,PF:o.pF||0,PQ:o.pQ||0,mandate:o.mandate,shock:o.shock,culture:o.cult,goldStart:o.goldStart,fac:o.fac||null,conquests:o.conq,over:o.over,tributaries:o.tribs,crises:o.crises,ruler:{name:o.ruler.name,base:o.ruler.base,birth:o.ruler.birth,death:o.ruler.death,exceptional:o.ruler.exc,figure:o.ruler.fig??-1},enemies:[...o.enemies],truce:[...o.truce]})),
  cells:Array.from(L,i=>[s.pol[i],s.pop[i],s.s[i],s.integ[i],s.dist[i],s.taken[i]]),
  wars:s.wars.map(o=>({id:o.id,name:o.name,attackers:o.a,defenders:o.d,start:o.start,end:o.end,gainA:o.gA,gainD:o.gD,lastGain:o.lastGain||0,civil:o.civil,holy:o.holy,notable:o.notable,outcome:o.outcome,why:o.why||''})),
  figures:s.figs.map(f=>({name:f.name,kind:f.kind,born:f.born,died:f.died,conquests:f.conq,realm:f.realm,works:f.works})),alive:s.alive.slice(),
  migrations:s.migs.map(m=>({id:m.id,people:m.eth,population:m.pop,cell:m.cell,dx:m.dx,dy:m.dy,path:m.path.slice(),steps:m.steps,max:m.max,fails:m.fails,start:m.start,end:m.end||0,done:m.done,result:m.result,settledPolity:m.settledPol||0,broke:m.broke.slice()}))});
 distBFS();capture('foundations');
 for(let year=0;year<12;year++){s.year++;for(const id of s.alive){const o=s.pols[id];statecraft(o,o.capital,s.year);culture(o)}}capture('statecraft');
 for(const id of s.alive)succession(s.pols[id]);capture('succession');
 const war=declareWar([s.pols[1]],[s.pols[2]],null,true,false,false);
 for(let n=0;n<2;n++)for(const i of L){if(s.pol[i]!==1)continue;for(let d=0;d<4;d++){const j=w.nb[i*4+d];if(j>=0&&w.land[j]&&s.pol[j]===2)attack(s.pols[1],i,j,false)}}capture('combat');
 civilWar(s.pols[1],false);capture('civilWar');
 for(const w of s.wars)endWar(w);distBFS();capture('peace');
 const origin=L.find(i=>w.T[i]>5&&s.eth[i]===0);const m=startMigration({eth:0,pop:450000,cell:origin,dx:1,dy:0.2,kind:'people'});
 for(let year=0;year<25&&!m.done;year++){s.year++;migStep(m)}capture('migration');
 for(let year=0;year<8;year++){s.year+=5;diplomacy()}capture('diplomacy');
 return JSON.stringify(captures);
})()`));
assert.ok(result.find(x=>x.phase==='civilWar').polities.length>2,'Must create rebel states');
const data=JSON.stringify({schema:'asabiya/polity-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,snapshots:result})+'\n';
const path=new URL('tests/native/polity-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created polity contract; review before committing.');}
else{assert.equal(await fs.readFile(path,'utf8'),data,'Original polity contract changed');console.log('Original polity contract verified.');}
