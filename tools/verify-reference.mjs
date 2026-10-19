import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'reference', 'v0.6');
const manifest = JSON.parse(await readFile(path.join(dir, 'manifest.json'), 'utf8'));
const bytes = await readFile(path.join(root, manifest.repositoryPath));
const sha256 = createHash('sha256').update(bytes).digest('hex');
const blob = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
assert.equal(bytes.length, manifest.bytes, 'Cambió el tamaño del original');
assert.equal(sha256, manifest.sha256, 'Cambió SHA-256 del original');
assert.equal(blob, manifest.gitBlobSha1, 'Cambió el blob Git del original');
assert.equal(await readFile(path.join(dir, 'SHA256SUMS'), 'utf8'), `${sha256}  ${manifest.sourceFilename}\n`);
if (process.argv[2]) {
  assert.ok(bytes.equals(await readFile(process.argv[2])), 'El archivo aportado difiere de la referencia');
}
if (path.resolve(process.argv[1] || '') === fileURLToPath(import.meta.url)) {
  console.log(JSON.stringify({ ok: true, bytes: bytes.length, sha256, gitBlobSha1: blob }, null, 2));
}
