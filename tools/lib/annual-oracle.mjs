// Reuse the immutable native-world/newHistory input for focused yearly-system
// contracts. The old oracle and its fixtures are not changed.
import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {root,runtime,requireOracleRuntime} from './legacy-oracle.mjs';

export async function annualOracle(){
  requireOracleRuntime();
  const html=await fs.readFile(new URL('reference/v0.6/Asabiya History Engine (Copy).html',root),'utf8');
  assert.equal(createHash('sha256').update(html).digest('hex'),runtime.referenceSha256);
  const input=JSON.parse(await fs.readFile(new URL('tests/native/history-contract-input.v06.json',root),'utf8'));
  const core=html.match(/<script id="core">([\s\S]*?)<\/script>/)[1];
  assert.equal(core.split('const W=400,H=200,').length,2);
  const context=vm.createContext({input});
  new vm.Script(core.replace('const W=400,H=200,',`const W=${input.width},H=${input.height},`)).runInContext(context,{timeout:10000});
  const evaluate=code=>vm.runInContext(code,context,{timeout:30000});
  evaluate(`{
    const original=mulberry32,positions=new WeakMap();globalThis.rngPositionOf=r=>positions.get(r);
    mulberry32=function(seed){const p={seed:seed>>>0,calls:0},raw=original(seed);const counted=()=>{p.calls++;return raw()};positions.set(counted,p);return counted};
  }`);
  evaluate(`{
    const I=input,n=W*H,f32=a=>Float32Array.from(a),u8=a=>Uint8Array.from(a),land=u8(I.land),coast=u8(I.coast),landIdx=[],coastIdx=[];
    for(let i=0;i<n;i++)if(land[i]){landIdx.push(i);if(coast[i])coastIdx.push(i)}
    const cxA=new Int16Array(n),cyA=new Int16Array(n);for(let i=0;i<n;i++){cxA[i]=i%W;cyA[i]=(i/W)|0}
    WD={seed:I.seed,isEarth:false,ecoReady:true,land,coast,landIdx:Int32Array.from(landIdx),coastIdx:Int32Array.from(coastIdx),
      lm:Int32Array.from(I.lm),lmSize:I.lmSize,lmCount:I.lmSize.length,nb:Int32Array.from(I.nb),cxA,cyA,
      T:f32(I.T),Pr:f32(I.Pr),amp:f32(I.amp),area:f32(I.area),rv:f32(I.rv),lat:f32(I.lat),x3:f32(I.x3),y3:f32(I.y3),z3:f32(I.z3),
      sF:f32(I.sF),sH:f32(I.sH),desert:u8(I.desert),nomad:u8(I.nomad),tsetse:u8(I.tsetse),monZone:f32(I.monZone),
      heavy:f32(I.heavy),leach:f32(I.leach),trop:f32(I.trop),oncho:f32(I.oncho),mal:f32(I.mal),forest0:f32(I.forest0),circ:f32(I.circ)};
    newHistory(I.historySeed);
  }`);
  // The old fixture predates weather/roughness exports. Interpolation is rebuilt
  // by the original code; roughness is an explicit controlled test input.
  const interpolation=core.slice(core.indexOf('  // weather interpolation'),core.indexOf('  // sea links'));
  assert.match(interpolation,/w\.wi=wi/);
  evaluate(`{const w=WD;${interpolation} WD.rough=new Float32Array(N).fill(0.4);}`);
  // Rebuild original sea-link order without generation or additional draws.
  const links=core.slice(core.indexOf('  // sea links:'),core.indexOf('  if(w.isEarth){',core.indexOf('  // sea links:')));
  evaluate(`{const w=WD,{land,coast,nb,lm}=w,q=new Int32Array(N);
    const n8=(i,fn)=>{const x=i%W,y=(i/W)|0;for(let dy=-1;dy<=1;dy++){const yy=y+dy;if(yy<0||yy>=H)continue;for(let dx=-1;dx<=1;dx++){if(!dx&&!dy)continue;fn(yy*W+(x+dx+W)%W)}}};
    ${links}
    WD.cosLat=Float32Array.from(WD.lat,x=>Math.max(0.2,Math.cos(x)));
  }`);
  return {evaluate,input,runtime};
}
