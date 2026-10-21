// Offline analysis only. No Go/Godot process, fixture generation or optimization.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export function quantile(values, q) {
  if (!values.length || values.some(v => !Number.isFinite(v))) throw new Error('Missing/nonfinite samples');
  const sorted = [...values].sort((a,b) => a-b);
  return sorted[Math.max(0, Math.ceil(sorted.length*q)-1)];
}
const max = values => values.reduce((a,b)=>Math.max(a,b),-Infinity);
const distribution = values => ({p50:quantile(values,.5),p95:quantile(values,.95),p99:quantile(values,.99),max:max(values)});

export function analyzeRun(meta, rows) {
  if (meta.schema !== 'asabiya/close-zoom-run-v1' || !meta.valid) throw new Error('Invalid/incomplete graphical run');
  if (rows.length !== meta.samples || rows.length < 2) throw new Error('Sample count mismatch');
  if (meta.renderer !== 'forward_plus' || meta.godot?.major!==4 || meta.godot?.minor!==7 || meta.godot?.patch!==2 || meta.godot?.status!=='stable' || meta.godot?.build!=='official') throw new Error('Unexpected engine/renderer');
  if (!['paused','active'].includes(meta.mode)) throw new Error('Unknown simulation mode');
  if (!meta.initialSHA256?.match(/^[0-9a-f]{64}$/) || !meta.finalSHA256?.match(/^[0-9a-f]{64}$/)) throw new Error('Missing exact state proofs');
  if (meta.mode === 'paused' && (meta.initialSHA256 !== meta.finalSHA256 || meta.initialYear !== meta.finalYear)) throw new Error('Paused state changed');
  let previousYear = meta.initialYear;
  for (const publication of meta.publications) {
    if (publication.year !== previousYear+1) throw new Error('Duplicate/missing annual publication');
    previousYear = publication.year;
  }
  if (meta.mode === 'paused' && meta.publications.length) throw new Error('Publication while paused');
  if (meta.mode === 'active' && !meta.publications.length) throw new Error('Active run made no progress');
  let last = -1;
  for (const row of rows) {
    if (row.length !== meta.columns.length || row.some(v => !Number.isFinite(v)) || row[1] <= 0 || row[0] <= last) throw new Error('Invalid raw frame');
    last = row[0];
  }
  const frames = rows.map(r=>r[1]);
  const seconds = frames.reduce((a,b)=>a+b,0)/1000;
  if (seconds < meta.requestedSeconds*.95 || meta.actualSeconds < meta.requestedSeconds*.95) throw new Error('Truncated measurement window');
  const buckets = new Map();
  for (const row of rows) { const b=Math.floor(row[0]/1000); buckets.set(b,(buckets.get(b)||0)+1); }
  const full = [...buckets].filter(([b])=>b>0 && b<Math.floor(last/1000)).map(([,n])=>n);
  const result = {
    revision:meta.revision, width:meta.width,height:meta.height,mode:meta.mode,diagnostic:meta.diagnostic,
    samples:rows.length,seconds, fpsP50:quantile(frames.map(ms=>1000/ms),.5), fpsMean:rows.length/seconds,
    frameMs:distribution(frames), processMs:distribution(rows.map(r=>r[2])),
    renderCpuMs:distribution(rows.map(r=>r[3])), renderGpuMs:distribution(rows.map(r=>r[4])),
    drawCalls:distribution(rows.map(r=>r[5])),shadowDrawCalls:distribution(rows.map(r=>r[6])),canvasDrawCalls:distribution(rows.map(r=>r[14])),
    primitives:distribution(rows.map(r=>r[7])),shadowPrimitives:distribution(rows.map(r=>r[8])),
    peakStaticBytes:max(rows.map(r=>r[9])),peakRenderVideoEstimateBytes:max(rows.map(r=>r[10])),
    over33msPercent:100*frames.filter(ms=>ms>1000/30).length/frames.length,
    minFullSecondFrames:full.length?Math.min(...full):null,
    initialYear:meta.initialYear,finalYear:meta.finalYear,publications:meta.publications.length,
    gpuTimingAvailable:meta.gpuTiming && quantile(rows.map(r=>r[4]),.5)>0,
    // A strict operational criterion, never a substitute for visual acceptance.
    timingGate30:meta.diagnostic==='none' && distribution(frames).p99<=1000/30 && full.length>0 && Math.min(...full)>=30,
  };
  return result;
}

export function assertComparable(a,b) {
  for (const key of ['width','height','mode','diagnostic','world','historySeed','historyYears','cell','distance','yaw','tilt','layer','quality','uiScale','rate','gpu','vendor','api','driver','renderer','godot','vsync','maxFps','gpuTiming','cpuScopes','initialSHA256']) {
    if (JSON.stringify(a[key])!==JSON.stringify(b[key])) throw new Error(`Cannot compare different ${key}`);
  }
}

// CSV emitted by Export-Csv (quoted fields, escaped quotes, BOM and CRLF).
export function csv(text) {
  const records=[]; let row=[], field='', quoted=false;
  text=text.replace(/^\uFEFF/,'');
  for(let i=0;i<text.length;i++) {
    const c=text[i];
    if(c==='"') { if(quoted&&text[i+1]==='"') {field+='"';i++;} else quoted=!quoted; }
    else if(c===','&&!quoted) {row.push(field);field='';}
    else if(c==='\n'&&!quoted) {row.push(field.replace(/\r$/,''));records.push(row);row=[];field='';}
    else field+=c;
  }
  if(field||row.length){row.push(field.replace(/\r$/,''));records.push(row);}
  const headers=records.shift()||[];
  return records.filter(r=>r.length===headers.length).map(r=>Object.fromEntries(headers.map((h,i)=>[h,r[i]])));
}

async function load(root) {
  const entries=(await fs.readdir(root,{withFileTypes:true})).filter(e=>e.isDirectory()).sort((a,b)=>a.name.localeCompare(b.name));
  const runs=[];
  for(const entry of entries) {
    const dir=path.join(root,entry.name);
    let raw;
    try {raw=await fs.readFile(path.join(dir,'run.json'),'utf8');} catch(e) {
      if(e.code==='ENOENT' && /^\d+x\d+-/.test(entry.name)) throw new Error(`Incomplete condition ${entry.name}`);
      if(e.code==='ENOENT')continue; throw e;
    }
    const meta=JSON.parse(raw.replace(/^\uFEFF/,''));
    const rows=(await fs.readFile(path.join(dir,'frames.jsonl'),'utf8')).trim().split(/\r?\n/).map(s=>JSON.parse(s));
    const summary=analyzeRun(meta,rows);
    const processes=csv(await fs.readFile(path.join(dir,'processes.csv'),'utf8')).filter(r=>{
      const t=Date.parse(r.utc)/1000;return t>=meta.measuredStartedUnixSeconds&&t<=meta.measuredFinishedUnixSeconds;
    });
    summary.processes={};
    for(const [name,pid] of [['godot',meta.clientPid],['go',meta.serverPid]]) {
      const selected=processes.filter(r=>Number(r.pid)===pid);
      summary.processes[name]=selected.length?{samples:selected.length,peakWorkingSetBytes:Math.max(...selected.map(r=>Number(r.workingSetBytes))),peakPrivateBytes:Math.max(...selected.map(r=>Number(r.privateBytes))),maxCpuCores:Math.max(...selected.filter(r=>r.cpuCores!=='').map(r=>Number(r.cpuCores)))}:null;
    }
    runs.push({condition:entry.name,meta,summary});
  }
  if(!runs.length)throw new Error('No completed graphical measurements');
  if(runs.some(r=>r.meta.initialSHA256!==runs[0].meta.initialSHA256))throw new Error('Campaign starts from different causal states');
  return runs;
}

async function main() {
  const [root,comparison]=process.argv.slice(2);
  if(!root)throw new Error('Usage: node tools/summarize-close-zoom.mjs RESULTS [COMPARISON_RESULTS]');
  const runs=await load(root);
  const output={schema:'asabiya/close-zoom-analysis-v1',runs:runs.map(r=>({condition:r.condition,...r.summary})),comparisons:[]};
  if(comparison) {
    const machine=JSON.parse((await fs.readFile(path.join(root,'machine.json'),'utf8')).replace(/^\uFEFF/,''));
    const otherMachine=JSON.parse((await fs.readFile(path.join(comparison,'machine.json'),'utf8')).replace(/^\uFEFF/,''));
    for(const key of ['gpu','cpu','computer','os','power']) {
      const select=value=>key==='os'?{Caption:value.Caption,Version:value.Version,BuildNumber:value.BuildNumber}:value;
      if(JSON.stringify(select(machine[key]))!==JSON.stringify(select(otherMachine[key])))throw new Error(`Cannot compare different machine ${key}`);
    }
    if(machine.kit.serverSHA256!==otherMachine.kit.serverSHA256)throw new Error('Go server changed between captures');
    const other=await load(comparison);
    if(other.length!==runs.length)throw new Error('Different condition/repeat counts');
    for(const before of runs) {
      const after=other.find(r=>r.condition===before.condition);
      if(!after)throw new Error(`Missing comparison ${before.condition}`);
      assertComparable(before.meta,after.meta);
      const a=before.summary,b=after.summary;
      output.comparisons.push({condition:before.condition,fpsP50ChangePercent:100*(b.fpsP50/a.fpsP50-1),frameP95ChangeMs:b.frameMs.p95-a.frameMs.p95,frameP99ChangeMs:b.frameMs.p99-a.frameMs.p99});
    }
  }
  await fs.writeFile(path.join(root,'analysis.json'),JSON.stringify(output,null,2)+'\n',{flag:'wx'});
  console.log('| Condition | FPS P50 | Frame P95 ms | Frame P99 ms | >33.33 ms % | Minimum full second |');
  console.log('|---|---:|---:|---:|---:|---:|');
  for(const r of output.runs)console.log(`| ${r.condition} | ${r.fpsP50.toFixed(2)} | ${r.frameMs.p95.toFixed(2)} | ${r.frameMs.p99.toFixed(2)} | ${r.over33msPercent.toFixed(2)} | ${r.minFullSecondFrames} |`);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) main().catch(e=>{console.error(e.message);process.exitCode=1;});
