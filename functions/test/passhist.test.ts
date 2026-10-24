/**
 * PRD-2.6 E6: the server-only versusRate.passHist (last 10 accepted pass
 * counts), maintained next to the score history. Clients cannot read it.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { Timestamp } from 'firebase-admin/firestore';
import { flagId } from '../src/pools.js';
import { FLAGS_COLLECTION, RATE_COLLECTION, RunEntry } from '../src/schema.js';
import { DAY, PROJECT, db, makePlayer, makeRun, processLive, uniq } from './helpers.js';

const shard0 = () => 0;
const passRun = (passes: number, best: number, values?: number[]): RunEntry => {
  const v = values ?? Array.from({ length: passes }, () => 1);
  return makeRun({
    score: v.reduce((a, b) => a + b, 0),
    best,
    deltas: v.map(() => 170),
    values: v,
  });
};
const rate = async (uid: string) => (await db.collection(RATE_COLLECTION).doc(uid).get()).data();

describe('PRD-2.6 E6 versusRate.passHist', () => {
  for (const counts of [[150, 10], [10, 150]]) {
    it(`judges batched passes ${counts.join(' → ')} against only earlier accepted runs`, async () => {
      const uid = uniq('passbatch');
      const nowMs = Date.UTC(2026, 9, 24, 12);
      await db.collection(RATE_COLLECTION).doc(uid).set({
        day: '', count: 0, seen: [], passHist: [10, 10, 10, 10],
      });
      const runs = counts.map((count, i) => ({
        ...passRun(count, 300), ts: Timestamp.fromMillis(nowMs - 2000 + i * 1000),
      }));
      const r = await processLive(uid, undefined, makePlayer({ best: 300, recent: [...runs].reverse() }), {
        rand: shard0, nowMs,
      });
      assert.deepEqual(r.accepted, [...runs].reverse().map((run) => run.runId));
      assert.deepEqual(r.flagged ?? [], counts[1] === 150 ? [runs[1].runId] : []);
      if (counts[1] === 150) {
        const flag = await db.collection(FLAGS_COLLECTION).doc(flagId(uid, runs[1].runId)).get();
        assert.deepEqual(flag.data()?.signals, { jump: 10 });
        assert.equal(flag.data()?.soft, true);
      }
      assert.deepEqual((await rate(uid))?.passHist, [10, 10, 10, 10, ...counts]);
      const entries = (await db.collection('pools').doc(r.pool!).get()).data()?.entries;
      assert.equal(entries[0].runId, runs[1].runId);
    });
  }

  it('caps history between runs within a batch before computing the next median', async () => {
    const uid = uniq('passbatchcap');
    const nowMs = Date.UTC(2026, 9, 24, 12);
    const history = [10, 10, 10, 10, 10, 100, 100, 100, 100, 100];
    await db.collection(RATE_COLLECTION).doc(uid).set({ day: '', count: 0, seen: [], passHist: history });
    const runs = [10, 150].map((count, i) => ({
      ...passRun(count, 300), ts: Timestamp.fromMillis(nowMs - 2000 + i * 1000),
    }));
    const r = await processLive(uid, undefined, makePlayer({ best: 300, recent: [...runs].reverse() }), {
      rand: shard0, nowMs,
    });
    // Last 10 earlier counts have median 55; an uncapped 11-count history
    // would have median 10 and would incorrectly flag the 150-pass run.
    assert.deepEqual(r.flagged ?? [], []);
    assert.deepEqual((await rate(uid))?.passHist, [...history, 10, 150].slice(-10));
  });

  it('preserves newest-first upload limits and pool selection for a batch', async () => {
    const uid = uniq('passbatchrate');
    const nowMs = Date.UTC(2026, 9, 24, 12);
    const runs = [10, 20, 30, 40].map((count, i) => ({
      ...passRun(count, 300), ts: Timestamp.fromMillis(nowMs - 4000 + i * 1000),
    }));
    const r = await processLive(uid, undefined, makePlayer({ best: 300, recent: [...runs].reverse() }), {
      rand: shard0, nowMs,
    });
    assert.deepEqual(r.accepted, [runs[3].runId, runs[2].runId, runs[1].runId]);
    assert.deepEqual(r.rejected, [{ runId: runs[0].runId, reason: 'rate' }]);
    assert.deepEqual((await rate(uid))?.passHist, [20, 30, 40]);
    const entries = (await db.collection('pools').doc(r.pool!).get()).data()?.entries;
    assert.equal(entries[0].runId, runs[3].runId);
  });

  it('appends the pass count of every accepted run and keeps the last 10', async () => {
    const uid = uniq('passhist');
    const day0 = Date.UTC(2026, 9, 24, 12);
    let prev = makePlayer({ best: 300 });
    const counts = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];
    for (let i = 0; i < counts.length; i++) {
      const run = passRun(counts[i], 300);
      const next = makePlayer({ best: 300, recent: [run, ...(prev.recent ?? [])].slice(0, 5) });
      const r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + i * DAY });
      assert.deepEqual(r.accepted, [run.runId]);
      prev = next;
    }
    assert.deepEqual((await rate(uid))?.passHist, counts.slice(-10));
  });

  it('does not append rejected or rate-limited runs, but still judges a rate-limited run', async () => {
    const uid = uniq('passskip');
    const day0 = Date.UTC(2026, 9, 24, 13);
    await db.collection(RATE_COLLECTION).doc(uid).set({
      day: '',
      count: 0,
      seen: [],
      passHist: [5, 6, 7, 8, 9],
    });
    const bad = makeRun({ score: 15, best: 300, deltas: [200, 180, 180], values: [2, 3, 9] });
    const rejected = await processLive(uid, undefined, makePlayer({ best: 300, recent: [bad] }), {
      rand: shard0,
      nowMs: day0,
    });
    assert.deepEqual(rejected.rejected, [{ runId: bad.runId, reason: 'count' }]);
    assert.deepEqual((await rate(uid))?.passHist, [5, 6, 7, 8, 9]);

    // The 4th non-best run of the day is not accepted, so it never enters the history.
    let prev = makePlayer({ best: 300, recent: [bad] });
    for (let i = 0; i < 3; i++) {
      const run = passRun(10 + i, 300);
      const next = makePlayer({ best: 300, recent: [run, ...(prev.recent ?? [])].slice(0, 5) });
      await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + 1 + i });
      prev = next;
    }
    const limited = passRun(150, 300);
    const next = makePlayer({ best: 300, recent: [limited, ...(prev.recent ?? [])].slice(0, 5) });
    const r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + 5 });
    assert.deepEqual(r.rejected, [{ runId: limited.runId, reason: 'rate' }]);
    // The run is judged against the five earlier accepted counts: it is a soft jump
    // and gets a flag, while the history itself stays accepted-runs only.
    assert.deepEqual(r.flagged, [limited.runId]);
    assert.deepEqual((await rate(uid))?.passHist, [5, 6, 7, 8, 9, 10, 11, 12]);
  });

  it('ignores malformed stored entries and survives the UTC-day reset', async () => {
    const uid = uniq('passbad');
    const day0 = Date.UTC(2026, 9, 24, 14);
    await db.collection(RATE_COLLECTION).doc(uid).set({
      day: '2026-10-23',
      count: 3,
      bestCount: 2,
      seen: [],
      passHist: [4, 'x', -1, 6, null],
    });
    const run = passRun(7, 7);
    const r = await processLive(uid, undefined, makePlayer({ best: 7, bestRun: run, recent: [run] }), {
      rand: shard0,
      nowMs: day0,
    });
    assert.deepEqual(r.accepted, [run.runId]);
    const docData = await rate(uid);
    assert.equal(docData?.day, '2026-10-24');
    assert.equal(docData?.count, 0);
    assert.deepEqual(docData?.passHist, [4, 6, 7]);
  });

  it('the pass history advances only on an accepted run in the same write', async () => {
    const uid = uniq('passonce');
    const day0 = Date.UTC(2026, 9, 24, 15);
    const run = passRun(8, 8);
    const before = makePlayer({ best: 0 });
    const after = makePlayer({ best: 8, bestRun: run, recent: [run] });
    await processLive(uid, before, after, { rand: shard0, nowMs: day0 });
    assert.deepEqual((await rate(uid))?.passHist, [8]);
    // A retried event is a duplicate and must not append a second count.
    await processLive(uid, before, after, { rand: shard0, nowMs: day0 + 1 });
    assert.deepEqual((await rate(uid))?.passHist, [8]);
  });
});

describe('PRD-2.6 E6 rules: versusRate is server-only', () => {
  let env: RulesTestEnvironment;

  before(async () => {
    env = await initializeTestEnvironment({
      projectId: PROJECT,
      firestore: { rules: readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8') },
    });
  });

  after(async () => {
    await env?.cleanup();
  });

  it('denies client reads and writes, including passHist', async () => {
    const uid = uniq('rate-rules');
    await env.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection(RATE_COLLECTION).doc(uid).set({ day: '', count: 0, seen: [], passHist: [150] });
    });
    for (const authed of [true, false]) {
      const client = authed ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
      const ref = doc(client, RATE_COLLECTION, uid);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { passHist: [1, 2, 3] }, { merge: true }));
      await env.withSecurityRulesDisabled(async (ctx) => {
        assert.equal((await ctx.firestore().collection(RATE_COLLECTION).doc(uid).get()).exists, true);
      });
    }
  });

  it('keeps passHist tied to the uid and never exposes it through a pool entry', async () => {
    const uid = uniq('poolread');
    const day0 = Date.UTC(2026, 9, 24, 16);
    const run = passRun(21, 21);
    const r = await processLive(uid, undefined, makePlayer({ best: 130, bestRun: run, recent: [run] }), {
      rand: shard0,
      nowMs: day0,
    });
    const hist = (await rate(uid))?.passHist;
    assert.deepEqual(hist, [21]);
    // The only client-readable versus data is pools/{id}; its entries carry no history.
    const entries = (await db.collection('pools').doc(r.pool!).get()).data()?.entries ?? [];
    const entry = entries.find((entry: { uid: string }) => entry.uid === uid);
    assert.ok(entry, 'accepted run is present in the selected pool');
    assert.equal(entry.passHist, undefined);
  });
});
