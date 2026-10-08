// QA only: run the built backend logic over an in-memory Firestore seam.
// No Firebase initialization, credentials, network, or production project.
const fs = require('node:fs');
const backendRequire = require('node:module').createRequire(require.resolve('../../functions/package.json'));
const { Timestamp } = backendRequire('firebase-admin/firestore');
const { processPlayerWrite, deletePlayerData } = require('../../functions/lib/pools.js');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const data = new Map();
function ref(collection, id) { return { path: `${collection}/${id}`, async delete() {
  if (input.mode === 'delete' && collection === 'versusRate') throw Error('injected rate deletion failure');
  data.delete(this.path);
}, async update(v) { data.set(this.path, { ...data.get(this.path), ...v }); } }; }
const DELETE = Symbol('delete');
const db = { collection: c => ({ doc: id => ref(c, id) }), async runTransaction(fn) {
  const writes = [];
  const out = await fn({ async get(r) { return { exists: data.has(r.path), data: () => data.get(r.path) }; },
    set(r, v) { writes.push([r.path, v]); }, update(r, v) { writes.push([r.path, { ...data.get(r.path), ...v }]); },
    delete(r) { writes.push([r.path, DELETE]); } });
  // The same injected fault inside a transaction: the commit fails as a
  // whole (Firestore commits are atomic), so nothing is applied.
  if (input.mode === 'delete' && writes.some(([p, v]) => v === DELETE && p.startsWith('versusRate/'))) {
    throw Error('injected rate deletion failure');
  }
  for (const [path, value] of writes) value === DELETE ? data.delete(path) : data.set(path, value);
  return out;
} };
function hydrate(v) {
  if (Array.isArray(v)) return v.map(hydrate);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) =>
    [k, k === 'ts' ? Timestamp.fromMillis(x) : hydrate(x)]));
  return v;
}
(async () => {
  if (input.mode === 'delete') {
    data.set('players/qa', { name: 'SwiftKiwi482' });
    data.set('versusRate/qa', { count: 1 });
    let failed = false;
    try { await deletePlayerData(db, 'qa'); } catch { failed = true; }
    console.log(JSON.stringify({ failed, playerExists: data.has('players/qa'), rateExists: data.has('versusRate/qa') }));
    return;
  }
  let old;
  const results = [];
  for (const [i, raw] of input.documents.entries()) {
    const next = hydrate(raw);
    data.set('players/qa', next);
    // nowMs: one processing time, or one per document (multi-day backlogs).
    const nowMs = Array.isArray(input.nowMs) ? input.nowMs[i] : input.nowMs;
    results.push(await processPlayerWrite(db, 'qa', old, next, { nowMs, rand: () => 0 }));
    old = next;
  }
  console.log(JSON.stringify({ accepted: results.flatMap(r => r.accepted), rejected: results.flatMap(r => r.rejected) }));
})().catch(e => { console.error(e); process.exitCode = 1; });
