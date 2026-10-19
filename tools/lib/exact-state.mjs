import os from 'node:os';
// Formato de comparación v2: conserva identidad, orden de propiedades y bits numéricos.
// No reemplaza la codificación histórica del smoke ni implementa guardar/restaurar partidas.
export function encodeExactState(root) {
  const seen=new Map();let nextId=0;
  function encode(v){
    if(typeof v==='number'){const b=Buffer.alloc(8);b.writeDoubleBE(v);return {number:Number.isNaN(v)?'nan':b.toString('hex')}}
    if(v===undefined)return {undefined:true};
    if(typeof v==='function')throw Error('Sustituir RNG por su posición antes de comparar');
    if(v===null||typeof v!=='object')return v;
    if(seen.has(v))return {ref:seen.get(v)};
    const id=nextId++;seen.set(v,id);
    if(ArrayBuffer.isView(v)){
      const bytes=Buffer.from(new Uint8Array(v.buffer,v.byteOffset,v.byteLength));
      const width=v.BYTES_PER_ELEMENT||1;
      if(os.endianness()==='BE')for(let i=0;i<bytes.length;i+=width)bytes.subarray(i,i+width).reverse();
      return {id,type:v.constructor.name,length:v.length,encoding:'little-endian',bytes:bytes.toString('hex')};
    }
    const type=Object.prototype.toString.call(v);
    if(type==='[object Map]')return {id,map:[...v].map(([k,x])=>[encode(k),encode(x)])};
    if(type==='[object Set]')return {id,set:[...v].map(encode)};
    // Object.keys conserva el orden ECMAScript (índices enteros antes de las otras claves).
    return {id,type:Array.isArray(v)?'Array':'Object',length:Array.isArray(v)?v.length:undefined,entries:Object.keys(v).map(k=>[k,encode(v[k])])};
  }
  return JSON.stringify({schemaVersion:2,value:encode(root)});
}
