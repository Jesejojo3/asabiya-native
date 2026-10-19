// Runs the ORIGINAL v0.6 newHistory (lines 864–916, with makeLang, newEth,
// climateStep, computeK, ethPass and recordStats) on a small native world
// exported by the Go tests (tests/native/history-contract-input.v06.json).
// The HTML is read immutably; only the in-memory map-size constants W/H are set
// to the fixture size so the legacy functions index the same grid.
// Default mode verifies tests/native/history-contract.v06.json; --write creates it.
import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { root, runtime, requireOracleRuntime } from './lib/legacy-oracle.mjs';

requireOracleRuntime();
const html = await fs.readFile(new URL('reference/v0.6/Asabiya History Engine (Copy).html', root), 'utf8');
assert.equal(createHash('sha256').update(html).digest('hex'), runtime.referenceSha256);
const input = JSON.parse(await fs.readFile(new URL('tests/native/history-contract-input.v06.json', root), 'utf8'));
const core = html.match(/<script id="core">([\s\S]*?)<\/script>/)[1];
const header = 'const W=400,H=200,';
assert.equal(core.split(header).length, 2, 'unexpected core header');
const sized = core.replace(header, `const W=${input.width},H=${input.height},`);
const context = vm.createContext({ input });
new vm.Script(sized).runInContext(context, { timeout: 10000 });
const evaluate = code => vm.runInContext(code, context, { timeout: 120000 });
evaluate(`{
  const original = mulberry32, positions = new WeakMap();
  globalThis.rngPositionOf = r => positions.get(r);
  mulberry32 = function(seed){ const p = {seed: seed>>>0, calls: 0}; const raw = original(seed);
    const counted = function(){ p.calls++; return raw() }; positions.set(counted, p); return counted };
}`);
const output = JSON.parse(evaluate(`(() => {
  const I = input, n = W*H, f32 = a => Float32Array.from(a), u8 = a => Uint8Array.from(a);
  const land = u8(I.land), coast = u8(I.coast), landIdx = [], coastIdx = [];
  for (let i = 0; i < n; i++) if (land[i]) { landIdx.push(i); if (coast[i]) coastIdx.push(i) }
  const cxA = new Int16Array(n), cyA = new Int16Array(n);
  for (let i = 0; i < n; i++) { cxA[i] = i % W; cyA[i] = (i / W) | 0 }
  WD = {seed: I.seed, isEarth: false, ecoReady: true, land, coast, landIdx: Int32Array.from(landIdx), coastIdx: Int32Array.from(coastIdx),
    lm: Int32Array.from(I.lm), lmSize: I.lmSize, lmCount: I.lmSize.length, nb: Int32Array.from(I.nb), cxA, cyA,
    T: f32(I.T), Pr: f32(I.Pr), amp: f32(I.amp), area: f32(I.area), rv: f32(I.rv), lat: f32(I.lat), x3: f32(I.x3), y3: f32(I.y3), z3: f32(I.z3),
    sF: f32(I.sF), sH: f32(I.sH), desert: u8(I.desert), nomad: u8(I.nomad), tsetse: u8(I.tsetse), monZone: f32(I.monZone),
    heavy: f32(I.heavy), leach: f32(I.leach), trop: f32(I.trop), oncho: f32(I.oncho), mal: f32(I.mal), forest0: f32(I.forest0), circ: f32(I.circ)};
  newHistory(I.historySeed);
  const s = S, lang = L => ({style: L.style, macro: L.macro, rules: L.rules.map(r => Array.isArray(r) ? r[0]+'>'+r[1] : r),
    lex: LEX.map(k => L.lex[k]), place: L.lex.place, people: L.lex.people, land: L.lex.land,
    placeSuffix: L.placeSuf, peopleSuffix: L.pplSuf, prePeople: L.prePpl, prePlace: L.prePlace});
  const places = [];
  for (const i of WD.landIdx) if (s.eth[i] >= 0 && places.length < 12) places.push([i, placeName(i)]);
  return JSON.stringify({rng: rngPositionOf(s.r), year: s.year, gT: s.gT, orb0: s.orb0, orbM: s.orbM, famN: s.famN,
    ag: Array.from(s.AG), K: Array.from(s.K), pop: Array.from(s.pop), eth: Array.from(s.eth), sail: Array.from(s.sail),
    adapt: Array.from(s.adapt), lmFound: Array.from(s.lmFound),
    peoples: s.eths.map(e => ({name: e.name, lang: lang(e.lang), culture: Array.from(e.cult), family: e.fam, parent: e.parent,
      parent2: e.parent2, depth: e.depth, born: e.born, hue: e.hue, sat: e.sat, lit: e.lit, rgb: e.rgb, alive: e.alive, cells: e.cells,
      pop: e.pop, peak: e.peak, lon: e.lon, lat: e.la, kids: e.kids, died: e.died ?? null})),
    hearths: s.hearths.map(h => ({kind: h.kind, cell: h.cell ?? -1, year: h.year})),
    chronicle: s.chron.map(c => ({year: c.y, kind: c.t, text: c.txt, cell: c.cell})),
    stats: s.stats.map(x => ({year: x.y, pop: x.pop, pe: x.pe, lead: x.lead, gT: x.gT, orb: x.orb})),
    epochs: s.epochs.map(e => ({kind: e.k, start: e.start, end: e.end})), places});
})()`));
const fixture = { schema: 'asabiya/history-contract-v1', referenceSha256: runtime.referenceSha256, node: runtime.node,
  inputSha256: createHash('sha256').update(JSON.stringify(input)).digest('hex'), ...output };
const encoded = JSON.stringify(fixture) + '\n';
const path = new URL('tests/native/history-contract.v06.json', root);
if (process.argv.includes('--write')) {
  await fs.writeFile(path, encoded);
  console.log(`Wrote history contract: ${output.peoples.length} peoples, ${output.rng.calls} draws; review before committing.`);
} else {
  assert.equal(await fs.readFile(path, 'utf8'), encoded, 'History contract differs from the immutable HTML; investigate before editing');
  console.log('Original newHistory contract verified.');
}
