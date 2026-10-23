// Exact contract for v0.6 languages and names (lines 694–760): sound rules,
// tidy/join, makeLang, childLang, hybridLang, personName, placeWord and cityWord,
// with the number of RNG draws each consumes. Only integer RNG and string
// operations are involved, so the Go port must match exactly.
// Default mode verifies tests/native/language-contract.v06.json; --write creates it.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { loadOracle, root, runtime } from './lib/legacy-oracle.mjs';

const { evaluate } = await loadOracle({ countRng: true });
const result = JSON.parse(evaluate(`(() => {
  const words = ['papa','atipa','akite','kitchen','stampa','ssskaa','wwyya','hhaba','aeiou','baaaab','tatata','sun','smart',
    'ciel','tiki','kanon','dramen','abbbbc','yyyar','eiaouk','xxo','pakatan'];
  const rules = RULES.map(r => Array.isArray(r) ? {from:r[0],to:r[1]} : {kind:r});
  const ruleCases = [];
  for (const w of words) for (let k = 0; k < RULES.length; k++) ruleCases.push({word:w, rule:k, out:applyRule(w, RULES[k])});
  const tidyCases = words.map(w => ({word:w, out:tidy(w)}));
  const joinPairs = [['bar','s'],['bal','s'],['tala','ia'],['ana','yo'],['dun','na'],['kas','sa'],['', 'ia'],['ri','']];
  const joinCases = joinPairs.map(([a,b]) => ({a, b, out:join(a,b)}));
  const lang = L => ({style:L.style, macro:L.macro, rules:L.rules.map(r => Array.isArray(r) ? r[0]+'>'+r[1] : r),
    lex:LEX.map(k => L.lex[k]), place:L.lex.place, people:L.lex.people, land:L.lex.land,
    placeSuffix:L.placeSuf, peopleSuffix:L.pplSuf, prePeople:L.prePpl, prePlace:L.prePlace});
  const cases = [];
  for (const m of MACRO_KEYS) for (const style of MACROS[m]) for (let rep = 0; rep < 3; rep++) {
    const r = mulberry32(hashStr('lang:' + style + ':' + rep));
    const L = makeLang(r, style, m);
    const C = childLang(L, r);
    const G = childLang(C, r);
    const other = makeLang(r, MACROS[m][0], m);
    const H = hybridLang(G, other, r);
    const names = {person:[personName(L,r),personName(G,r)], place:[placeWord(L,r),placeWord(H,r)], city:[cityWord(L,r),cityWord(C,r)]};
    cases.push({seed:'lang:' + style + ':' + rep, macro:m, style, lang:lang(L), child:lang(C), grandchild:lang(G), other:lang(other),
      hybrid:lang(H), names, calls:rngPositionOf(r).calls});
  }
  return JSON.stringify({rules, ruleCases, tidyCases, joinCases, cases});
})()`));
const fixture = { schema: 'asabiya/language-contract-v1', referenceSha256: runtime.referenceSha256, node: runtime.node, ...result };
const encoded = JSON.stringify(fixture) + '\n';
const path = new URL('tests/native/language-contract.v06.json', root);
if (process.argv.includes('--write')) {
  await fs.writeFile(path, encoded);
  console.log(`Wrote language contract with ${result.cases.length} language cases; review before committing.`);
} else {
  assert.equal(await fs.readFile(path, 'utf8'), encoded, 'Language contract differs from the immutable HTML; investigate before editing');
  console.log('Original language/name contract verified.');
}
