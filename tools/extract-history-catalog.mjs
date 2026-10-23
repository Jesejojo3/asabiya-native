// Extracts the v0.6 data tables used by languages, newHistory and the initial
// climate/carrying-capacity step into internal/sim/catalog_v06.json.
// The HTML is evaluated in memory and never modified. Default mode verifies the
// committed catalog; --write regenerates it (review the diff before committing).
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { loadOracle, root, runtime } from './lib/legacy-oracle.mjs';

const { evaluate } = await loadOracle({ countRng: false });
const catalog = JSON.parse(evaluate(`JSON.stringify({
  styles: Object.keys(STYLES).map(name => {
    const s = STYLES[name];
    return { name, cons: s.cons, cl: s.cl, vow: s.vow, pat: s.pat, coda: s.coda, place: s.place, ppl: s.ppl,
      pers: s.pers, city: s.city, mono: !!s.mono, pre: s.pre ? { ppl: s.pre.ppl, place: s.pre.place } : null, titles: s.t };
  }),
  macros: MACRO_KEYS.map(key => ({ key, styles: MACROS[key] })),
  lex: LEX,
  soundRules: RULES.map(r => Array.isArray(r) ? { from: r[0], to: r[1] } : { kind: r }),
  tech: TECH.map(t => ({ key: t.k, name: t.n, era: t.era, pre: t.pre || [], emergence: t.em || null, pos: t.pos || null,
    synthetic: !!t.synth, description: t.d || '' })),
  eras: ERAS,
  epochKinds: EPOCH_KINDS.map(e => ({ kind: e.k, weight: e.w, amp: e.amp, duration: e.dur, start: e.start, end: e.end })),
  parameters: PDEF.map(d => ({ group: d[0], key: d[1], label: d[2], min: d[3], max: d[4], step: d[5], default: d[6], newWorld: !!d[8] })),
  additionalDefaults: { hearthMode: P.hearthMode, fitClimate: P.fitClimate, shuffleNames: P.shuffleNames, sandbox: P.sandbox }
})`));
const out = { schema: 'asabiya/v06-history-catalog-v1', referenceSha256: runtime.referenceSha256,
  source: 'reference/v0.6 core: PDEF 319-358, STYLES/MACROS/LEX/RULES 659-693, TECH/ERAS 762-800, EPOCH_KINDS 919-923', ...catalog };
const encoded = JSON.stringify(out, null, 1) + '\n';
const path = new URL('internal/sim/catalog_v06.json', root);
if (process.argv.includes('--write')) {
  await fs.writeFile(path, encoded);
  console.log('Wrote internal/sim/catalog_v06.json; review before committing.');
} else {
  assert.equal(await fs.readFile(path, 'utf8'), encoded, 'Catalog differs from the immutable HTML; investigate before editing');
  console.log('v0.6 history catalog verified against the reference HTML.');
}
