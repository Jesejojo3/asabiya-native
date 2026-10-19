import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {loadOracle,legacyDigest,runtime} from './lib/legacy-oracle.mjs';
const args=process.argv.slice(2), output=args[args.indexOf('--out')+1], expectedPath=args[args.indexOf('--verify')+1];
assert.ok(args.includes('--out')||args.includes('--verify'),'Usar --out ARCHIVO o --verify FIXTURE');
const oracle=await loadOracle();oracle.initEarth();const e=oracle.evaluate;
const worldDigest=legacyDigest(e('WD'));
e('globalThis.firstState=null;globalThis.firstWar=null');
while(e('S.year') < -3500){
  e('for(let n=0;n<100&&S.year < -3500;n++){step();if(firstState===null&&S.alive.length)firstState=S.year;if(firstWar===null&&S.wars.length)firstWar=S.year}');
  if(e('S.year')%500===0)console.error(JSON.stringify({year:e('S.year'),states:e('S.alive.length'),wars:e('S.wars.length')}));
}
assert.ok(e('S.alive.length')>0,'Fixture sin estados');assert.ok(e('S.wars.length')>0,'Fixture sin guerras');
const stateDigest=legacyDigest(e('S')),position=JSON.parse(e('JSON.stringify(rngPositionOf(S.r))'));
const reconstructed=e(`Array.from({length:8},mulberry32(${position.state}))`);
const next=Array.from(e('Array.from({length:8},()=>S.r())'));
assert.deepEqual(Array.from(reconstructed),next,'La posición RNG no reproduce la continuación');
const fixture={schemaVersion:1,profile:'v06-compat',scenario:{world:'Earth',historySeed:'1',fitClimate:true,startYear:-9000,endYear:-3500,commands:[]},oracle:runtime,
  worldDigest,stateDigest,position,nextRandom:next,firstState:e('firstState'),firstWar:e('firstWar'),final:JSON.parse(e('JSON.stringify({year:S.year,states:S.alive.length,wars:S.wars.length,peoples:S.eths.length})'))};
if(args.includes('--verify'))assert.deepEqual(fixture,JSON.parse(await fs.readFile(expectedPath,'utf8')),'El fixture tardío divergió');
if(args.includes('--out'))await fs.writeFile(output,JSON.stringify(fixture,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({ok:true,...fixture},null,2));
