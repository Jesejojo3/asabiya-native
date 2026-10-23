import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {loadOracle,root,runtime} from './lib/legacy-oracle.mjs';
const {evaluate}=await loadOracle({countRng:false});
const values=JSON.parse(evaluate(`JSON.stringify({omens:Object.entries(OMENS).map(([key,o])=>({key,...o})),cataclysms:Object.entries(CATA).map(([key,c])=>({key,...c}))})`));
const data=JSON.stringify({schema:'asabiya/v06-interventions-v1',referenceSha256:runtime.referenceSha256,...values},null,1)+'\n';
const path=new URL('internal/sim/interventions_v06.json',root);
if(process.argv.includes('--write')){await fs.writeFile(path,data);console.log('Created intervention catalog; review before committing.');}
else{assert.equal(await fs.readFile(path,'utf8'),data,'Intervention catalog changed');console.log('Original intervention catalog verified.');}
