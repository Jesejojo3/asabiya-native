import assert from 'node:assert/strict';
import test from 'node:test';
import {analyzeRun,assertComparable,csv,quantile} from './summarize-close-zoom.mjs';

function fixture() {
  const rows=Array.from({length:100},(_,i)=>[(i+1)*100,100,5,2,80,30,15,1000,500,100000,90000,100,-9000,1000,20]);
  return {rows,meta:{schema:'asabiya/close-zoom-run-v1',valid:true,samples:100,columns:Array(15),renderer:'forward_plus',godot:{major:4,minor:7,patch:2,status:'stable',build:'official'},mode:'paused',diagnostic:'none',initialYear:-9000,finalYear:-9000,initialSHA256:'a'.repeat(64),finalSHA256:'a'.repeat(64),publications:[],requestedSeconds:10,actualSeconds:10,gpuTiming:true}};
}
test('raw percentiles include slow tail rather than averaging window percentiles',()=>{
  const {meta,rows}=fixture(); rows[99][1]=1000;
  const r=analyzeRun(meta,rows);
  assert.equal(r.fpsP50,10);assert.equal(r.frameMs.p95,100);assert.equal(r.frameMs.p99,100);assert.equal(r.frameMs.max,1000);
  assert.equal(r.over33msPercent,100);assert.equal(r.timingGate30,false);
  assert.equal(quantile([1,2,3,4],.5),2);
});
test('reject missing frames, truncated windows, nonfinite data and a changed paused state',()=>{
  const {meta,rows}=fixture();
  assert.throws(()=>analyzeRun(meta,rows.slice(1)),/count/);
  assert.throws(()=>analyzeRun({...meta,requestedSeconds:60},rows),/Truncated/);
  assert.throws(()=>analyzeRun({...meta,finalSHA256:'b'.repeat(64)},rows),/Paused state/);
  rows[0][1]=NaN;assert.throws(()=>analyzeRun(meta,rows),/Invalid raw/);
});
test('active capture must progress through every consecutive year',()=>{
  const {meta,rows}=fixture();meta.mode='active';
  assert.throws(()=>analyzeRun(meta,rows),/no progress/);
  meta.publications=[{year:-8999},{year:-8997}];assert.throws(()=>analyzeRun(meta,rows),/annual publication/);
  meta.publications=[{year:-8999},{year:-8998}];assert.equal(analyzeRun(meta,rows).publications,2);
});
test('zero GPU timing is unavailable; diagnostic ablations cannot pass acceptance',()=>{
  const {meta,rows}=fixture();for(const row of rows){row[1]=10;row[4]=0;}
  meta.requestedSeconds=1;meta.diagnostic='terrain-hidden';
  const r=analyzeRun(meta,rows);assert.equal(r.gpuTimingAvailable,false);assert.equal(r.timingGate30,false);
});
test('comparison rejects a different camera, state, driver API or instrumentation',()=>{
  for(const key of ['distance','initialSHA256','api','gpuTiming','cell','quality'])assert.throws(()=>assertComparable({[key]:1},{[key]:2}),/Cannot compare/);
  assert.doesNotThrow(()=>assertComparable({revision:'before'},{revision:'after'}));
});
test('Windows CSV preserves quoted commas, quotes, BOM and CRLF',()=>{
  assert.deepEqual(csv('\uFEFF"name","pid"\r\n"GPU, \"\"name\"\"","4"\r\n'),[{name:'GPU, "name"',pid:'4'}]);
});
