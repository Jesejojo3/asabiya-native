const fs=require('node:fs');
const acorn=require('internal/deps/acorn/acorn/dist/acorn');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'reference/v0.6/Asabiya History Engine (Copy).html'),'utf8');
const match=/<script id="core">([\s\S]*?)<\/script>/.exec(html),code=match[1];
const offset=html.slice(0,match.index+'<script id="core">'.length).split('\n').length-1;
const ast=acorn.parse(code,{ecmaVersion:'latest',locations:true});
const loops=[];
function walk(n,owner='top-level'){
 if(!n||typeof n!=='object')return;
 if(n.type==='FunctionDeclaration')owner=n.id.name;
 if(n.type==='ForOfStatement'){
   const collection=code.slice(n.right.start,n.right.end);
   loops.push({line:n.loc.start.line+offset,function:owner,collection,iteration:collection.endsWith('.slice()')?'explicit snapshot':'live ECMAScript iterator',portRequirement:'Preserve collection identity, order, and mutation effects; see COLLECTION_SEMANTICS.md'});
 }
 for(const [k,v] of Object.entries(n)){if(k==='loc')continue;if(Array.isArray(v))v.forEach(x=>walk(x,owner));else if(v&&typeof v==='object')walk(v,owner)}
}
walk(ast);
const assert=require('node:assert/strict');
assert.equal(process.versions.node,'24.19.0');
const actual={schemaVersion:1,sourceSha256:'988ce360e70d2d034a3898f60b9a4c38d40b0ab56dd7a147329740f15fa8e9e9',parser:'Node 24.19.0 bundled Acorn '+acorn.version,method:'AST inventory of every ForOfStatement in core, not an alias-analysis proof',loops};
assert.deepEqual(actual,JSON.parse(fs.readFileSync(path.join(root,'docs/phase-0/evidence/collection-iteration-inventory.json'),'utf8')));
console.log(JSON.stringify({ok:true,count:loops.length,parser:acorn.version}));
