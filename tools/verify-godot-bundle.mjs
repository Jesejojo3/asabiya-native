// Independent consumer: Node reads the public files, not Go exporter helpers.
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const directory=path.resolve(process.argv[2]||'tests/integration/godot');
const read=async name=>JSON.parse(await fs.readFile(path.join(directory,name),'utf8'));
const manifest=await read('manifest.json');
assert.equal(manifest.schema,'asabiya/geography-v1');assert.equal(manifest.byteOrder,'little-endian');
const bytes=await fs.readFile(path.join(directory,manifest.file));assert.equal(bytes.length,manifest.bytes);assert.equal(createHash('sha256').update(bytes).digest('hex'),manifest.sha256);
assert.equal(bytes.subarray(0,8).toString('binary'),'ASABGEO\0');assert.equal(bytes.readUInt32LE(8),1);
const layers=new Map();let end=16;
for(const layer of manifest.layers){assert.equal(layer.offset,end);const width=layer.type==='u8'?1:4;assert.ok(['f32','i32','u8'].includes(layer.type));assert.equal(layer.bytes,layer.count*layer.components*width);end+=layer.bytes;assert.ok(end<=bytes.length);assert.ok(!layers.has(layer.name));layers.set(layer.name,layer)}assert.equal(end,bytes.length);
function value(name,index,component=0){const l=layers.get(name);assert.ok(l);assert.ok(index>=0&&index<l.count);assert.ok(component>=0&&component<l.components);const offset=l.offset+(index*l.components+component)*(l.type==='u8'?1:4);return l.type==='u8'?bytes.readUInt8(offset):l.type==='f32'?bytes.readFloatLE(offset):bytes.readInt32LE(offset)}
const {width,height}=manifest.logical,n=width*height;for(let i=0;i<n;i++){const x=i%width,y=Math.floor(i/width);assert.equal(value('neighbors',i,0),y*width+(x+width-1)%width);assert.equal(value('neighbors',i,1),y*width+(x+1)%width);assert.equal(value('neighbors',i,2),y>0?i-width:-1);assert.equal(value('neighbors',i,3),y<height-1?i+width:-1);assert.ok(Number.isFinite(value('elevation',i)));assert.ok(value('latitude',i)>-Math.PI/2&&value('latitude',i)<Math.PI/2)}
for(const cell of await read('control-samples.json')){assert.equal(value('elevation',cell.id),Math.fround(cell.elevationMeters));assert.equal(value('river',cell.id),Math.fround(cell.drainage.river));assert.equal(value('landmass',cell.id),cell.landmass);assert.equal(value('land',cell.id),Number(cell.land));assert.equal(value('coast',cell.id),Number(cell.coast));assert.equal(value('biome',cell.id),cell.ecology.biome)}
const offsets=layers.get('seaOffsets');assert.equal(offsets.count,n+1);for(let i=0;i<n;i++){assert.ok(value('seaOffsets',i)<=value('seaOffsets',i+1))}assert.equal(value('seaOffsets',n),layers.get('seaTargets').count);
if(manifest.fine){assert.equal(manifest.fine.width,width*manifest.world.detail);assert.equal(manifest.fine.height,height*manifest.world.detail);for(const name of ['fineElevation','fineTemperature','finePrecipitation','fineSeasonalAmplitude']){assert.equal(layers.get(name).count,manifest.fine.width*manifest.fine.height)}}
for(const name of ['initial-state.json','state.json']){const state=await read(name);assert.equal(state.schema,'asabiya/state-v1');assert.equal(state.worldSHA256,manifest.worldSHA256);assert.equal(state.provinces.length,n);for(let i=0;i<n;i++){const p=state.provinces[i];assert.equal(p.id,i);assert.equal(p.land,!!value('land',i));assert.equal(p.militaryControllerPolityId,null);assert.equal(p.technology.length,32);assert.ok(p.population>=0&&Number.isFinite(p.population));if(p.ownerPolityId>0)assert.ok(state.entities.polity.some(x=>x.id===p.ownerPolityId))}for(const [kind,records]of Object.entries(state.entities)){const ids=new Set();for(const record of records){assert.equal(record.kind,kind);assert.ok(!ids.has(record.id));ids.add(record.id)}}}
console.log(JSON.stringify({ok:true,schema:manifest.schema,provinces:n,fine:manifest.fine,bytes:bytes.length,sha256:manifest.sha256}));
