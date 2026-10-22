// Offline analysis of tools/diagnose-render.ps1 results (Phase 2.3).
// Reads raw frames again; never edits inputs and never averages percentiles of
// different captures. Usage: node tools/analyze-render-diagnosis.mjs RESULTS_DIR [--out FILE.md]
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export const BUDGET_MS = 1000 / 30;

export function quantile(values, q) {
  if (!values.length || values.some(v => !Number.isFinite(v))) throw new Error('Missing/nonfinite samples');
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * q) - 1)];
}

const dist = values => ({p50: quantile(values, .5), p95: quantile(values, .95), p99: quantile(values, .99), max: Math.max(...values)});

export function analyzeFrames(columns, rows) {
  if (rows.length < 2) throw new Error('Too few frames');
  const at = name => {
    const i = columns.indexOf(name);
    if (i < 0) throw new Error(`Missing column ${name}`);
    return i;
  };
  let last = -1;
  for (const row of rows) {
    if (row.length !== columns.length || row.some(v => !Number.isFinite(v)) || row[at('frameMs')] <= 0 || row[at('elapsedMs')] <= last) throw new Error('Invalid raw frame');
    last = row[at('elapsedMs')];
  }
  const col = name => rows.map(r => r[at(name)]);
  const frames = col('frameMs');
  const buckets = new Map();
  for (const t of col('elapsedMs')) { const b = Math.floor(t / 1000); buckets.set(b, (buckets.get(b) || 0) + 1); }
  const full = [...buckets].filter(([b]) => b > 0 && b < Math.floor(last / 1000)).map(([, n]) => n);
  const gpu = col('renderGpuMs');
  return {
    samples: rows.length,
    fpsP50: quantile(frames.map(f => 1000 / f), .5),
    frameMs: dist(frames), gpuMs: gpu.every(v => v === 0) ? null : dist(gpu),
    renderCpuMs: dist(col('renderCpuMs')), processMs: dist(col('processMs')),
    drawCalls: quantile(col('drawCalls'), .5), shadowDrawCalls: quantile(col('shadowDrawCalls'), .5),
    primitives: quantile(col('primitives'), .5), shadowPrimitives: quantile(col('shadowPrimitives'), .5),
    over33msPercent: 100 * frames.filter(f => f > BUDGET_MS).length / frames.length,
    minFullSecondFrames: full.length ? Math.min(...full) : null,
  };
}

// Each ablation is compared with the base captures that bracket it in time.
export function compareToBases(experiments, metric = e => e.stats.gpuMs?.p50 ?? e.stats.frameMs.p50) {
  const out = [];
  for (let i = 0; i < experiments.length; i++) {
    const e = experiments[i];
    if (e.name === 'base' || e.name === 'active' || !e.stats) continue;
    let before = null, after = null;
    for (let j = i - 1; j >= 0 && !before; j--) if (experiments[j].name === 'base' && experiments[j].stats) before = experiments[j];
    for (let j = i + 1; j < experiments.length && !after; j++) if (experiments[j].name === 'base' && experiments[j].stats) after = experiments[j];
    const refs = [before, after].filter(Boolean).map(metric);
    if (!refs.length) { out.push({name: e.name, index: e.index, verdict: 'no bracketing base'}); continue; }
    const ref = refs.reduce((a, b) => a + b, 0) / refs.length;
    const drift = refs.length === 2 ? Math.abs(refs[1] - refs[0]) / ref * 100 : null;
    const value = metric(e);
    const deltaPct = (value - ref) / ref * 100;
    const noise = Math.max(drift ?? 0, 3);
    out.push({name: e.name, index: e.index, value, reference: ref, deltaMs: value - ref, deltaPct, baseDriftPct: drift,
      verdict: Math.abs(deltaPct) <= noise ? 'within noise' : (deltaPct < 0 ? 'cheaper' : 'more expensive')});
  }
  return out;
}

export function gate(experiments) {
  // Strict reference gate: every capture P99 <= 33.33 ms and no full second < 30 frames.
  const relevant = experiments.filter(e => (e.name === 'base' || e.name === 'active') && e.stats);
  if (!relevant.length) return {evaluated: false};
  const failures = relevant.filter(e => e.stats.frameMs.p99 > BUDGET_MS || (e.stats.minFullSecondFrames ?? 0) < 30).map(e => e.tag);
  return {evaluated: true, pass: failures.length === 0, failures};
}

function readJson(file) { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')); }

export function analyzeSession(dir) {
  const runFile = path.join(dir, 'run.json');
  const run = fs.existsSync(runFile) ? readJson(runFile) : null;
  const expFile = path.join(dir, 'experiments.json');
  const error = fs.existsSync(path.join(dir, 'error.txt')) ? fs.readFileSync(path.join(dir, 'error.txt'), 'utf8').trim()
    : fs.existsSync(path.join(dir, 'session-error.txt')) ? fs.readFileSync(path.join(dir, 'session-error.txt'), 'utf8').trim() : null;
  if (!run || !fs.existsSync(expFile)) return {dir, valid: false, error: error ?? 'incomplete session'};
  if (run.schema !== 'asabiya/render-diagnosis-v1') return {dir, valid: false, error: `unexpected schema ${run.schema}`};
  const experiments = readJson(expFile).experiments.map(e => {
    if (!e.tag) return {...e, stats: null};
    const file = path.join(dir, `frames-${e.tag}.jsonl`);
    const rows = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map(l => JSON.parse(l));
    if (rows.length !== e.samples) throw new Error(`${file}: sample count mismatch`);
    return {...e, stats: e.valid ? analyzeFrames(run.columns, rows) : null};
  });
  return {dir, valid: run.valid === true, error, label: run.label, renderer: run.renderer, gpu: run.gpu, driver: run.driver,
    exported: run.exported, productSync: run.productSync, initialSHA256: run.initialSHA256, prepareSeconds: run.prepareSeconds,
    width: run.width, height: run.height, experiments, comparisons: compareToBases(experiments), gate: gate(experiments)};
}

export function analyzeProcesses(file) {
  if (!fs.existsSync(file)) return null;
  const [header, ...lines] = fs.readFileSync(file, 'utf8').replace(/^﻿/, '').trim().split(/\r?\n/);
  const names = header.split(',').map(h => h.replace(/"/g, ''));
  const rows = lines.map(l => Object.fromEntries(l.split(',').map((v, i) => [names[i], v.replace(/"/g, '')])));
  const byRole = {};
  for (const r of rows) {
    const key = `${r.role}|${(r.phase || '').split(':')[0]}`;
    (byRole[key] ??= []).push(r);
  }
  const num = v => (v === '' || v === undefined ? NaN : Number(v));
  return Object.fromEntries(Object.entries(byRole).map(([k, rs]) => {
    const pick = f => rs.map(r => num(r[f])).filter(Number.isFinite);
    const summary = f => { const v = pick(f); return v.length ? {p50: quantile(v, .5), max: Math.max(...v)} : null; };
    return [k, {samples: rs.length, cpuCores: summary('cpuCores'), workingSetBytes: summary('workingSetBytes'), privateBytes: summary('privateBytes'),
      gpu3dPercent: summary('gpu3dPercent'), gpuSharedBytes: summary('gpuSharedBytes'), gpuDedicatedBytes: summary('gpuDedicatedBytes')}];
  }));
}

const f1 = v => (v === null || v === undefined ? '—' : Number(v).toFixed(1));

export function report(resultsDir) {
  const sessions = fs.readdirSync(resultsDir, {withFileTypes: true}).filter(d => d.isDirectory()).map(d => path.join(resultsDir, d.name)).sort();
  const lines = [`# Render diagnosis analysis: ${path.basename(resultsDir)}`, ''];
  const proofs = new Set();
  for (const dir of sessions) {
    const s = analyzeSession(dir);
    lines.push(`## ${path.basename(dir)}`, '');
    if (!s.valid && !s.experiments) { lines.push(`Invalid: ${s.error}`, ''); continue; }
    proofs.add(s.initialSHA256);
    lines.push(`${s.renderer} · ${s.gpu} · ${s.width}x${s.height} · exported=${s.exported} · productSync=${s.productSync} · prepare ${f1(s.prepareSeconds)} s · SHA ${s.initialSHA256?.slice(0, 12)}`, '');
    lines.push('| # | experiment | FPS P50 | frame P50/P95/P99 ms | GPU P50/P95/P99 ms | render CPU P50 | draws (shadow) | primitives (shadow) | >33 ms % | min frames/s |', '|---|---|---|---|---|---|---|---|---|---|');
    for (const e of s.experiments) {
      if (!e.stats) { lines.push(`| ${e.index} | ${e.name} | ${e.unavailable ?? e.invalidReason ?? 'invalid'} | | | | | | | |`); continue; }
      const t = e.stats;
      lines.push(`| ${e.index} | ${e.name} | ${f1(t.fpsP50)} | ${f1(t.frameMs.p50)}/${f1(t.frameMs.p95)}/${f1(t.frameMs.p99)} | ${t.gpuMs ? `${f1(t.gpuMs.p50)}/${f1(t.gpuMs.p95)}/${f1(t.gpuMs.p99)}` : 'n/a'} | ${f1(t.renderCpuMs.p50)} | ${t.drawCalls} (${t.shadowDrawCalls}) | ${t.primitives} (${t.shadowPrimitives}) | ${f1(t.over33msPercent)} | ${t.minFullSecondFrames ?? '—'} |`);
    }
    if (s.comparisons.length) {
      lines.push('', '| experiment | GPU P50 ms | bracketing base ms | Δ ms | Δ % | base drift % | verdict |', '|---|---|---|---|---|---|---|');
      for (const c of s.comparisons) lines.push(`| ${c.name} | ${f1(c.value)} | ${f1(c.reference)} | ${f1(c.deltaMs)} | ${f1(c.deltaPct)} | ${f1(c.baseDriftPct)} | ${c.verdict} |`);
    }
    if (s.gate.evaluated) lines.push('', `Strict gate (P99 ≤ 33.33 ms, every full second ≥ 30 frames): ${s.gate.pass ? 'PASS' : 'FAIL ' + s.gate.failures.join(', ')}`);
    const processes = analyzeProcesses(path.join(dir, 'processes.csv'));
    if (processes) {
      lines.push('', '| role · phase | samples | CPU cores P50/max | working set max MB | private max MB | GPU 3D % P50 | GPU shared max MB |', '|---|---|---|---|---|---|---|');
      const mb = v => (v ? (v.max / 1048576).toFixed(0) : '—');
      for (const [k, p] of Object.entries(processes)) lines.push(`| ${k.replace('|', ' · ')} | ${p.samples} | ${p.cpuCores ? `${p.cpuCores.p50.toFixed(2)}/${p.cpuCores.max.toFixed(2)}` : '—'} | ${mb(p.workingSetBytes)} | ${mb(p.privateBytes)} | ${p.gpu3dPercent ? f1(p.gpu3dPercent.p50) : '—'} | ${mb(p.gpuSharedBytes)} |`);
    }
    lines.push('');
  }
  if (proofs.size > 1) lines.push('**Sessions started from different historical states; they are not comparable.**', '');
  return lines.join('\n');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const [dir, flag, out] = process.argv.slice(2);
  if (!dir) { console.error('usage: analyze-render-diagnosis.mjs RESULTS_DIR [--out FILE.md]'); process.exit(2); }
  const text = report(dir);
  if (flag === '--out' && out) {
    if (fs.existsSync(out)) throw new Error('Refusing to overwrite an existing analysis');
    fs.writeFileSync(out, text);
  } else console.log(text);
}
