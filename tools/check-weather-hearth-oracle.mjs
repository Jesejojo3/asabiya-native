import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {annualOracle} from './lib/annual-oracle.mjs';
import {root} from './lib/legacy-oracle.mjs';
const {evaluate,runtime}=await annualOracle();
const result=JSON.parse(evaluate(`(()=>{
  S.year++;for(const h of S.hearths)h.year=S.year;
  S.epoch={k:'dry',start:S.year-10,end:S.year+20,amp:-1.2,cx:0,cy:H/2,rad:10};
  const before=S.chron.length;
  weather();hearthCheck();
  return JSON.stringify({rng:rngPositionOf(S.r),ag:Array.from(S.AG),
    weather:Array.from(WD.landIdx,i=>[i,S.anom[i],S.wm[i]]),
    hearths:S.hearths.map(h=>({kind:h.kind,cell:h.cell??-1,year:h.year,done:!!h.done})),
    discoveries:S.firstTech.map(x=>x?{year:x.y,cell:x.cell,polity:x.pol||0,people:x.eth??S.eth[x.cell]}:null),
    tech:S.tk.map(f=>Array.from(f,(v,i)=>[i,v]).filter(x=>x[1]!==0)),
    chronicle:S.chron.slice(before).map(c=>({year:c.y,kind:c.t,text:c.txt,cell:c.cell}))});
})()`));
const fixture={schema:'asabiya/weather-hearth-v1',referenceSha256:runtime.referenceSha256,node:runtime.node,...result};
const data=JSON.stringify(fixture)+'\n',path=new URL('tests/native/weather-hearth-contract.v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created weather/hearth contract; review before committing.');}
else {assert.equal(await fs.readFile(path,'utf8'),data,'Original weather/hearth contract changed');console.log('Original weather/hearth contract verified.');}
