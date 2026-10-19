import fs from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { inflateSync } from 'node:zlib';
import vm from 'node:vm';
import os from 'node:os';
import assert from 'node:assert/strict';
export const root = new URL('../../', import.meta.url);
export const runtime = JSON.parse(await fs.readFile(new URL('../oracle-runtime.json', import.meta.url)));
export function requireOracleRuntime() {
  assert.equal(process.versions.node, runtime.node, 'Versión de Node distinta del oráculo fijado');
  assert.equal(process.versions.v8, runtime.v8, 'Versión V8 distinta del oráculo fijado');
  assert.equal(process.arch, runtime.arch);
  assert.equal(os.endianness(), runtime.endianness);
}
// Mantiene la codificación histórica de los hashes publicados; no es el formato de guardado.
export function normalizeLegacy(v) {
  if (typeof v === 'function') return '<function:excluded>';
  if (v === undefined) return '<undefined>';
  if (typeof v === 'number' && !Number.isFinite(v)) return `<${v}>`;
  if (ArrayBuffer.isView(v)) return { type: v.constructor.name, bytes: Buffer.from(v.buffer,v.byteOffset,v.byteLength).toString('base64') };
  const type=Object.prototype.toString.call(v);
  if(type==='[object Map]')return {map:[...v].map(([k,x])=>[normalizeLegacy(k),normalizeLegacy(x)])};
  if(type==='[object Set]')return {set:[...v].map(normalizeLegacy)};
  if(Array.isArray(v))return v.map(normalizeLegacy);
  if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,normalizeLegacy(v[k])]));
  return v;
}
export const legacyDigest=v=>createHash('sha256').update(JSON.stringify(normalizeLegacy(v))).digest('hex');
export async function loadOracle({countRng=true}={}) {
  requireOracleRuntime();
  const html=await fs.readFile(new URL('reference/v0.6/Asabiya History Engine (Copy).html',root),'utf8');
  assert.equal(createHash('sha256').update(html).digest('hex'),runtime.referenceSha256);
  const assets=html.match(/<script id="assets">([\s\S]*?)<\/script>/)[1];
  const core=html.match(/<script id="core">([\s\S]*?)<\/script>/)[1];
  const context=vm.createContext({});
  new vm.Script(assets+'\n'+core).runInContext(context,{timeout:10000});
  const evaluate=code=>vm.runInContext(code,context,{timeout:120000});
  if(countRng)evaluate(`{
    const original=mulberry32, positions=new WeakMap();
    globalThis.rngPositionOf=r=>{const p=positions.get(r);if(!p)throw Error('RNG no registrado');return {...p,state:(p.seed+Math.imul(p.calls>>>0,0x6D2B79F5))>>>0}};
    mulberry32=function(seed){const p={seed:seed>>>0,calls:0};const raw=original(seed);const counted=function(){p.calls++;return raw()};positions.set(counted,p);return counted};
  }`);
  const initEarth=()=>{
    const packed=JSON.parse(evaluate('JSON.stringify([EARTH_ELEV_B64,KOPPEN_B64])'));
    context.elevBytes=new Uint8Array(inflateSync(Buffer.from(packed[0],'base64')));
    context.kgBytes=new Uint8Array(inflateSync(Buffer.from(packed[1],'base64')));
    evaluate("{const e=decodeEarth(elevBytes,kgBytes);WD=genWorld({seed:'Earth',earth:true,height:e.height,kg:e.kg,fit:true});newHistory('1')}");
  };
  return {context,evaluate,initEarth};
}
