// Caracterización del JavaScript existente. No es una implementación del port.
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { inflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';
import os from 'node:os';
import assert from 'node:assert/strict';

await import('./verify-reference.mjs');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const html = await readFile(path.join(root, 'reference/v0.6/Asabiya History Engine (Copy).html'), 'utf8');
const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)];
assert.equal(scripts.length, 3);
for (const [, , code] of scripts) new vm.Script(code); // Sólo compilar la interfaz; no necesita DOM.
const core = scripts.find(s => s[1].includes('id="core"'))[2];
const assets = scripts.find(s => s[1].includes('id="assets"'))[2];
assert.ok(!/\b(document|window|performance|Date)\b|Math\.random/.test(core));

function normalize(value) {
  if (typeof value === 'function') return '<function:excluded>';
  if (value === undefined) return '<undefined>';
  if (typeof value === 'number' && !Number.isFinite(value)) return `<${value}>`;
  if (ArrayBuffer.isView(value)) return { type: value.constructor.name, bytes: Buffer.from(value.buffer, value.byteOffset, value.byteLength).toString('base64') };
  const type = Object.prototype.toString.call(value);
  if (type === '[object Map]') return { map: [...value].map(([k, v]) => [normalize(k), normalize(v)]) };
  if (type === '[object Set]') return { set: [...value].map(normalize) };
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, normalize(value[k])]));
  return value;
}
const digest = value => createHash('sha256').update(JSON.stringify(normalize(value))).digest('hex');

function run(kind) {
  const started = performance.now();
  const context = vm.createContext({});
  new vm.Script(assets + '\n' + core).runInContext(context, { timeout: 10000 });
  const evaluate = code => vm.runInContext(code, context, { timeout: 120000 });
  if (kind === 'earth') {
    const packed = JSON.parse(evaluate('JSON.stringify([EARTH_ELEV_B64,KOPPEN_B64])'));
    context.elevBytes = new Uint8Array(inflateSync(Buffer.from(packed[0], 'base64')));
    context.kgBytes = new Uint8Array(inflateSync(Buffer.from(packed[1], 'base64')));
    evaluate("{ const earth=decodeEarth(elevBytes,kgBytes); WD=genWorld({seed:'Earth',earth:true,height:earth.height,kg:earth.kg,fit:true}); }");
  } else evaluate("WD=genWorld({seed:'atlas-7',landFrac:P.landFrac})");
  evaluate("newHistory('1')");
  const worldDigest = digest(evaluate('WD'));
  const initialDigest = digest(evaluate('S'));
  evaluate('for(let i=0;i<3;i++)step()');
  const annualDigest = digest(evaluate('S'));
  const target = evaluate('WD.landIdx.find(i=>S.pop[i]>=1)');
  assert.ok(Number.isInteger(target));
  context.target = target;
  const cast = evaluate("castOmen('drought',target)");
  assert.equal(cast.ok, true);
  const castYear = evaluate('S.year');
  const afterCastDigest = digest(evaluate('S'));
  // Incluye el seguimiento a los 50 años y ventanas periódicas de 3, 10 y 20 años.
  evaluate('for(let i=0;i<51;i++)step()');
  assert.equal(evaluate('S.omens[0].followed'), true);
  assert.ok(evaluate('S.pop.every(v=>Number.isFinite(v)&&v>=0)'));
  assert.equal(evaluate('S.year'), -9000 + 54);
  const finalDigest = digest(evaluate('S'));
  // La clausura del RNG no se serializa. Muestra de continuación al final de cada corrida.
  const nextRandom = Array.from(evaluate('Array.from({length:8},()=>S.r())'));
  return { kind, worldSeed: kind === 'earth' ? 'Earth' : 'atlas-7', historySeed: '1', years: 54,
    drought: { target, castYear }, worldDigest, initialDigest, annualDigest, afterCastDigest, finalDigest, nextRandom,
    final: JSON.parse(evaluate('JSON.stringify({year:S.year,peoples:S.eths.length,states:S.alive.length,wars:S.wars.length,omens:S.omens.length,followed:S.omens[0].followed})')),
    elapsedMs: Math.round(performance.now() - started) };
}

const cases = [];
for (const kind of ['generated', 'earth']) {
  const first = run(kind), second = run(kind);
  const { elapsedMs: a, ...firstStable } = first;
  const { elapsedMs: b, ...secondStable } = second;
  assert.deepEqual(firstStable, secondStable, `La repetición ${kind} divergió`);
  cases.push({ ...firstStable, elapsedMs: [a, b], repetitionsMatch: true });
}
console.log(JSON.stringify({ schemaVersion: 1, sourceSha256: createHash('sha256').update(html).digest('hex'),
  runtime: { node: process.version, platform: process.platform, arch: process.arch, endianness: os.endianness() },
  scriptsSyntaxChecked: scripts.length, cases,
  limitations: ['Sólo JavaScript original; no equivalencia Go/JS.', 'Dos escenarios iniciales de 54 años; no cubre guerras tardías ni todos los presagios.',
    'Hashes binarios ligados a la endianidad registrada; RNG observado mediante continuación, sin serializar su clausura.',
    'Tiempo de caracterización con generación y hashing; no constituye benchmark del motor.'] }, null, 2));
