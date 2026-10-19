import assert from 'node:assert/strict';
import {loadOracle,legacyDigest,runtime} from './lib/legacy-oracle.mjs';
const counted=await loadOracle(), plain=await loadOracle({countRng:false});
counted.initEarth();plain.initEarth();
assert.equal(legacyDigest(counted.evaluate('WD')),legacyDigest(plain.evaluate('WD')));
assert.equal(legacyDigest(counted.evaluate('S')),legacyDigest(plain.evaluate('S')));
for(const oracle of [counted,plain])oracle.evaluate('for(let n=0;n<3;n++)step()');
assert.equal(legacyDigest(counted.evaluate('S')),legacyDigest(plain.evaluate('S')),'El contador alteró el estado');
const position=JSON.parse(counted.evaluate('JSON.stringify(rngPositionOf(S.r))'));
const restored=Array.from(counted.evaluate(`Array.from({length:8},mulberry32(${position.state}))`));
const actual=Array.from(counted.evaluate('Array.from({length:8},()=>S.r())'));
assert.deepEqual(actual,restored);
assert.deepEqual(actual,Array.from(plain.evaluate('Array.from({length:8},()=>S.r())')));
for(const seed of [0,1,0x7fffffff,0xffffffff]){
  counted.context.testSeed=seed;
  counted.evaluate('globalThis.testRng=mulberry32(testSeed)');
  for(const target of [0,1,2,65537]){
    counted.context.target=target;
    counted.evaluate('while(rngPositionOf(testRng).calls<target)testRng()');
    assert.equal(counted.evaluate('rngPositionOf(testRng).calls'),target);
    assert.deepEqual(Array.from(counted.evaluate('Array.from({length:8},mulberry32(rngPositionOf(testRng).state))')),
      Array.from(counted.evaluate('{const r=mulberry32(testSeed);for(let n=0;n<target;n++)r();Array.from({length:8},r)}')));
  }
}
// Caso mínimo de la semántica del iterador de arrays, confirmado en el flujo real de politicsG.
assert.deepEqual(counted.evaluate('JSON.stringify((()=>{const s={alive:[1,2,3]},next=s.alive,seen=[];for(const id of next){seen.push(id);if(id===2)s.alive.push(99)}return seen})())'),'[1,2,3,99]');
console.log(JSON.stringify({ok:true,oracle:runtime,positionAtYearMinus8997:position,continuation:actual,countingTransparent:true,liveArrayIteration:true},null,2));
