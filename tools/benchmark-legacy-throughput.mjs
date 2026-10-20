// Read-only benchmark of the original immutable HTML v0.6, not a port.
// Runs Node/V8 without the browser UI or Godot. Initialization is excluded.
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { loadOracle, runtime } from './lib/legacy-oracle.mjs';

const args = Object.fromEntries(process.argv.slice(2).map(a => {
  const m = /^--(years|warmup|repeats)=(\d+)$/.exec(a);
  if (!m) throw Error('Expected --years=N, --warmup=N or --repeats=N; received ' + a);
  return [m[1], Number(m[2])];
}));
const years = args.years ?? 100;
const warmup = args.warmup ?? 20;
const repeats = args.repeats ?? 2;
assert.ok(years >= 1 && years <= 400 && warmup >= 0 && warmup <= 100 && repeats >= 1 && repeats <= 3,
  'Bounded benchmark arguments required');

const cases = [];
for (let iteration = 0; iteration < repeats; iteration++) {
  const { evaluate } = await loadOracle({countRng: false});
  const initStarted = performance.now();
  // Go comparison uses DefaultWorldConfig('Asabiya') (400x200, landFraction .33)
  // and NewSimulation(world, '1'). Geography/math are not asserted bit-identical.
  evaluate("WD=genWorld({seed:'Asabiya',landFrac:0.33});newHistory('1')");
  const initializedMs = performance.now() - initStarted;
  const baseline = JSON.parse(evaluate('JSON.stringify({year:S.year,land:WD.landIdx.length,peoples:S.eths.length,states:S.alive.length})'));
  if (warmup) evaluate(`for(let i=0;i<${warmup};i++)step()`);
  const initialYear = evaluate('S.year');
  const rssBefore = process.memoryUsage().rss;
  const measuredStarted = performance.now();
  evaluate(`for(let i=0;i<${years};i++)step()`);
  const elapsedMs = performance.now() - measuredStarted;
  const rssAfter = process.memoryUsage().rss;
  const final = JSON.parse(evaluate('JSON.stringify({year:S.year,peoples:S.eths.length,states:S.alive.length,wars:S.wars.length})'));
  assert.equal(final.year - initialYear, years, 'Year advancement must be exact');
  const item = {
    iteration: iteration + 1, seed: 'Asabiya', historySeed: '1', width: 400, height: 200,
    warmupYears: warmup, measuredYears: years, initializationMs: initializedMs,
    landCells: baseline.land, foundingPeoples: baseline.peoples, initialYear,
    elapsedMs, msPerYear: elapsedMs / years, yearsPerSecond: years * 1000 / elapsedMs,
    rssBeforeBytes: rssBefore, rssAfterBytes: rssAfter, end: final
  };
  cases.push(item);
  console.log('JS_CORE ' + JSON.stringify(item));
}
console.log('JS_SUMMARY ' + JSON.stringify({
  engine: 'original HTML v0.6 in Node.js VM/V8 (no graphics, no serialization)',
  originalSha256: runtime.referenceSha256, node: process.version, v8: process.versions.v8,
  platform: process.platform, arch: process.arch,
  comparisonLimitations: [
    'Equivalent world dimensions/seeds/parameters do not imply identical Go/JS generated maps or causal arithmetic.',
    'Node vm and browser V8 have different execution contexts; this does not measure in-browser UX.',
    'JIT warmup and historical workload change with simulated year.',
    'RSS includes runtime and world; memory delta is not peak use.'
  ],
  averageYearsPerSecond: cases.reduce((sum, x) => sum + x.yearsPerSecond, 0) / cases.length,
  cases
}));
