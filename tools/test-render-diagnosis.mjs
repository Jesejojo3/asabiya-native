// Controlled samples for the Phase 2.3 analyzer; these are not game measurements.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {analyzeFrames, analyzeSession, compareToBases, gate, quantile, report} from './analyze-render-diagnosis.mjs';

const COLUMNS = ['elapsedMs', 'frameMs', 'processMs', 'renderCpuMs', 'renderGpuMs', 'drawCalls', 'shadowDrawCalls',
  'primitives', 'shadowPrimitives', 'staticBytes', 'renderVideoBytes', 'nodes', 'year', 'terrainAssignedTriangles',
  'canvasDrawCalls', 'renderTextureBytes', 'renderBufferBytes'];
const frames = (ms, seconds, gpu = ms - 1) => {
  const rows = [];
  for (let t = ms; t <= seconds * 1000; t += ms) rows.push([t, ms, 1, 1, gpu, 24, 28, 746557, 1001232, 1, 1, 1, 1000, 1, 113, 1, 1]);
  return rows;
};

test('quantile uses nearest rank and rejects nonfinite data', () => {
  assert.equal(quantile([4, 1, 3, 2], 0.5), 2);
  assert.equal(quantile([4, 1, 3, 2], 0.99), 4);
  assert.throws(() => quantile([1, NaN], 0.5));
});

test('frame analysis reports budget and full-second minimum', () => {
  const s = analyzeFrames(COLUMNS, frames(60, 10));
  assert.equal(s.over33msPercent, 100);
  assert.equal(s.minFullSecondFrames, 16);
  assert.ok(Math.abs(s.fpsP50 - 1000 / 60) < 1e-9);
  assert.equal(s.gpuMs.p50, 59);
  const fast = analyzeFrames(COLUMNS, frames(20, 10, 0));
  assert.equal(fast.gpuMs, null, 'zero GPU timers mean unavailable, not free');
  assert.equal(fast.over33msPercent, 0);
});

test('frame analysis rejects truncated or nonmonotonic rows', () => {
  const rows = frames(60, 5);
  rows[2] = rows[2].slice(0, 5);
  assert.throws(() => analyzeFrames(COLUMNS, rows));
  const back = frames(60, 5);
  back[3][0] = back[2][0];
  assert.throws(() => analyzeFrames(COLUMNS, back));
});

test('ablations are compared with bracketing bases and drift sets the noise floor', () => {
  const e = (index, name, gpu) => ({index, name, stats: {gpuMs: {p50: gpu}, frameMs: {p50: gpu + 1}}});
  const result = compareToBases([e(1, 'base', 60), e(2, 'shadows-off', 45), e(3, 'ssao-off', 59), e(4, 'base', 62)]);
  assert.equal(result[0].verdict, 'cheaper');
  assert.equal(result[0].reference, 61);
  assert.equal(result[1].verdict, 'within noise');
  assert.ok(Math.abs(result[1].baseDriftPct - 200 / 61) < 1e-9);
  assert.equal(compareToBases([e(1, 'shadows-off', 40)])[0].verdict, 'no bracketing base');
});

test('strict gate needs P99 and every full second', () => {
  const ok = {name: 'base', tag: '01-base', stats: {frameMs: {p99: 30}, minFullSecondFrames: 31}};
  const late = {name: 'active', tag: '02-active', stats: {frameMs: {p99: 34}, minFullSecondFrames: 31}};
  assert.deepEqual(gate([ok]), {evaluated: true, pass: true, failures: []});
  assert.deepEqual(gate([ok, late]).failures, ['02-active']);
  assert.equal(gate([{name: 'shadows-off', stats: ok.stats}]).evaluated, false, 'ablations never count for acceptance');
});

test('session analysis rereads raw frames and reports mismatched states', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'render-diag-'));
  for (const [name, sha] of [['a', 'aa'], ['b', 'bb']]) {
    const dir = path.join(root, name);
    fs.mkdirSync(dir);
    const rows = frames(60, 6);
    fs.writeFileSync(path.join(dir, 'frames-01-base.jsonl'), rows.map(r => JSON.stringify(r)).join('\n') + '\n');
    fs.writeFileSync(path.join(dir, 'experiments.json'), JSON.stringify({experiments: [{index: 1, name: 'base', tag: '01-base', samples: rows.length, valid: true}]}));
    fs.writeFileSync(path.join(dir, 'run.json'), '﻿' + JSON.stringify({schema: 'asabiya/render-diagnosis-v1', valid: true, columns: COLUMNS, initialSHA256: sha, renderer: 'forward_plus'}));
  }
  assert.equal(analyzeSession(path.join(root, 'a')).experiments[0].stats.samples, 100);
  assert.match(report(root), /not comparable/);
  fs.writeFileSync(path.join(root, 'a', 'frames-01-base.jsonl'), '[1,2]\n');
  assert.throws(() => analyzeSession(path.join(root, 'a')), /sample count mismatch/);
});
