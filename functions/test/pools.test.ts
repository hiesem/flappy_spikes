/**
 * §3.13 onPlayerRunWrite logic against the Firestore emulator (direct calls of
 * processPlayerWrite / sweepAllPools / deletePlayerData with a fixed clock and shard).
 */
import assert from 'node:assert/strict';
import { DocumentReference, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { deletePlayerData, processPlayerWrite, sweepAllPools } from '../src/pools.js';
import { POOL_CAP, POOL_MAX_BYTES, poolId, RATE_COLLECTION } from '../src/schema.js';
import { docSize } from '../src/size.js';
import { DAY, db, makePlayer, makeRun, poolEntries, processLive, uniq, waitFor } from './helpers.js';

const shard0 = () => 0;
const rate = async (uid: string) => (await db.collection(RATE_COLLECTION).doc(uid).get()).data();

describe('§3.13 onPlayerRunWrite: accept', () => {
  it('§3.13 a new best run goes to a shard of the server-recomputed level, newest first', async () => {
    const uid = uniq('acc');
    const run = makeRun({ score: 150 });
    const after = { ...makePlayer({ best: 150, bestRun: run, recent: [run] }), level: 9 }; // client level is wrong
    const now = Date.now();
    const r = await processLive(uid, undefined, after, { rand: shard0, nowMs: now });
    assert.deepEqual(r.accepted, [run.runId]);
    assert.equal(r.pool, poolId(3, 0)); // best 150 → FLEDGLING (3)
    const entries = await poolEntries(poolId(3, 0));
    const e = entries[0];
    assert.equal(e.uid, uid);
    assert.equal(e.runId, run.runId);
    assert.equal(e.level, 3);
    assert.equal(e.tl, run.tl);
    assert.equal((e.ts as Timestamp).toMillis(), now); // upload time is the server's
    assert.equal((await rate(uid))?.last?.status, 'accepted');
  });

  it('§3.13 the player older entries are removed from the shard (dedupe per uid)', async () => {
    const uid = uniq('dedupe');
    const r1 = makeRun({ score: 160, tsMs: Date.now() - 1000 });
    const p1 = makePlayer({ best: 160, bestRun: r1, recent: [r1] });
    await processLive(uid, undefined, p1, { rand: shard0 });
    const r2 = makeRun({ score: 170 });
    const p2 = makePlayer({ best: 170, bestRun: r2, recent: [r2, r1] });
    await processLive(uid, p1, p2, { rand: shard0 });
    const mine = (await poolEntries(poolId(3, 0))).filter((e) => e.uid === uid);
    assert.deepEqual(
      mine.map((e) => e.runId),
      [r2.runId],
    );
  });

  it('§3.13 a profile-only write (no new run) touches no pool', async () => {
    const uid = uniq('noop');
    const r = await processLive(uid, undefined, makePlayer({ best: 0 }));
    assert.deepEqual(r, { accepted: [], rejected: [] });
    assert.equal(await rate(uid), undefined);
  });

  it('§3.13 a deleted player doc touches no pool (WP-AV: and no Storage)', async () => {
    const r = await processPlayerWrite(db, uniq('del'), makePlayer({ best: 5 }), undefined);
    assert.deepEqual(r, { accepted: [], rejected: [] });
  });
});

describe('§3.13 onPlayerRunWrite: cheat filter rejects', () => {
  const cases: Array<[string, () => { best: number; run: ReturnType<typeof makeRun> }, string]> = [
    ['timeline length ≠ score', () => ({ best: 250, run: makeRun({ score: 250, deltas: Array(249).fill(120) }) }), 'count'],
    ['two points < 0.9 s apart', () => ({ best: 250, run: makeRun({ score: 250, deltas: [...Array(249).fill(120), 50] }) }), 'gap'],
    ['best < score (player)', () => ({ best: 240, run: makeRun({ score: 250, best: 250 }) }), 'best_below_score'],
    ['best < score (entry)', () => ({ best: 260, run: makeRun({ score: 250, best: 249 }) }), 'best_below_score'],
    ['score under 3', () => ({ best: 250, run: makeRun({ score: 2 }) }), 'low_score'],
  ];
  for (const [name, mk, reason] of cases) {
    it(`§3.13 rejects: ${name}`, async () => {
      const uid = uniq('rej');
      const { best, run } = mk();
      const r = await processLive(uid, undefined, makePlayer({ best, recent: [run] }), { rand: shard0 });
      assert.deepEqual(r.accepted, []);
      assert.deepEqual(r.rejected, [{ runId: run.runId, reason }]);
      assert.equal(r.pool, undefined);
      assert.ok((await poolEntries(poolId(4, 0))).every((e) => e.uid !== uid));
      assert.equal((await rate(uid))?.last?.reason, reason);
    });
  }
});

describe('§3.13 onPlayerRunWrite: upload rate (3 a day, best always)', () => {
  it('§3.13 the 4th non-best run of a UTC day is rejected; a new best still goes; the next day resets', async () => {
    const uid = uniq('rate');
    const day0 = Date.UTC(2026, 9, 8, 12);
    let prev = makePlayer({ best: 300 });
    const recent: ReturnType<typeof makeRun>[] = [];
    const results: string[] = [];
    for (let i = 0; i < 4; i++) {
      const run = makeRun({ score: 200 + i, best: 300 });
      recent.unshift(run);
      const next = makePlayer({ best: 300, recent: recent.slice(0, 5) });
      const r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + i });
      results.push(r.accepted.length ? 'ok' : r.rejected[0].reason);
      prev = next;
    }
    assert.deepEqual(results, ['ok', 'ok', 'ok', 'rate']);
    // A new best is always uploaded.
    const bestRun = makeRun({ score: 310 });
    recent.unshift(bestRun);
    let next = makePlayer({ best: 310, bestRun, recent: recent.slice(0, 5) });
    let r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + 10 });
    assert.deepEqual(r.accepted, [bestRun.runId]);
    prev = next;
    // Marking an old score as "best" does not dodge the limit.
    const fake = makeRun({ score: 250, best: 310 });
    recent.unshift(fake);
    next = makePlayer({ best: 310, bestRun: fake, recent: recent.slice(0, 5) });
    r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + 11 });
    assert.deepEqual(r.rejected, [{ runId: fake.runId, reason: 'rate' }]);
    prev = next;
    // Next UTC day.
    const run = makeRun({ score: 220, best: 310 });
    recent.unshift(run);
    next = makePlayer({ best: 310, bestRun: fake, recent: recent.slice(0, 5) });
    r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + DAY });
    assert.deepEqual(r.accepted, [run.runId]);
  });

  it('§3.13 a retried event (same runId) is not counted twice', async () => {
    const uid = uniq('retry');
    const run = makeRun({ score: 200, best: 300 });
    const before = makePlayer({ best: 300 });
    const after = makePlayer({ best: 300, recent: [run] });
    const a = await processLive(uid, before, after, { rand: shard0 });
    const b = await processLive(uid, before, after, { rand: shard0 });
    assert.deepEqual(a.accepted, [run.runId]);
    assert.deepEqual(b.rejected, [{ runId: run.runId, reason: 'duplicate' }]);
    assert.equal((await rate(uid))?.count, 1);
  });
});

describe('§3.13 pool shard limits', () => {
  function seedEntry(i: number, level: number, tsMs: number, tlChars = 40) {
    return {
      ...makeRun({ runId: `seed-${i}`, score: 12 }),
      tl: 'A'.repeat(tlChars),
      uid: `seed-uid-${i}`,
      level,
      ts: Timestamp.fromMillis(tsMs),
    };
  }

  it('§3.13 a shard is trimmed to 150 entries, newest first', async () => {
    const pid = poolId(6, 1);
    const now = Date.now();
    const seeded = Array.from({ length: POOL_CAP }, (_, i) => seedEntry(i, 6, now - i * 1000));
    await db.collection('pools').doc(pid).set({ level: 6, shard: 1, updatedAt: Timestamp.now(), entries: seeded });
    const uid = uniq('cap');
    const run = makeRun({ score: 650 });
    await processLive(uid, undefined, makePlayer({ best: 650, bestRun: run, recent: [run] }), {
      rand: () => 0.3,
      nowMs: now,
    });
    const entries = await poolEntries(pid);
    assert.equal(entries.length, POOL_CAP);
    assert.equal(entries[0].uid, uid);
    assert.equal(entries[1].runId, 'seed-0');
    assert.equal(entries[POOL_CAP - 1].runId, `seed-${POOL_CAP - 2}`); // the oldest one dropped
  });

  it('§3.13 a shard stays under 900 KB with long timelines', async () => {
    const pid = poolId(7, 2);
    const now = Date.now();
    const seeded = Array.from({ length: 110 }, (_, i) => seedEntry(i, 7, now - i * 1000, 8400));
    await db.collection('pools').doc(pid).set({ level: 7, shard: 2, updatedAt: Timestamp.now(), entries: seeded });
    const uid = uniq('bytes');
    const run = makeRun({ score: 850 });
    await processLive(uid, undefined, makePlayer({ best: 850, bestRun: run, recent: [run] }), {
      rand: () => 0.6,
      nowMs: now,
    });
    const snap = await db.collection('pools').doc(pid).get();
    const data = snap.data()!;
    assert.equal(data.entries[0].uid, uid);
    assert.ok(data.entries.length < 111);
    assert.ok(docSize(snap.ref.path, data) <= POOL_MAX_BYTES, `size ${docSize(snap.ref.path, data)}`);
  });

  it('§3.13 entries older than 60 days are dropped on write', async () => {
    const pid = poolId(8, 3);
    const now = Date.now();
    const seeded = [seedEntry(1, 8, now - 10 * DAY), seedEntry(2, 8, now - 61 * DAY)];
    await db.collection('pools').doc(pid).set({ level: 8, shard: 3, updatedAt: Timestamp.now(), entries: seeded });
    const run = makeRun({ score: 1500 });
    await processLive(uniq('ttl'), undefined, makePlayer({ best: 1500, bestRun: run, recent: [run] }), {
      rand: () => 0.99,
      nowMs: now,
    });
    const ids = (await poolEntries(pid)).map((e) => e.runId);
    assert.deepEqual(ids.slice(1), ['seed-1']);
  });

  it('§3.13 sweepPools trims > 60-day entries in every shard', async () => {
    const now = Date.now();
    const a = poolId(9, 0);
    const b = poolId(10, 3);
    await db.collection('pools').doc(a).set({ level: 9, shard: 0, updatedAt: Timestamp.now(),
      entries: [seedEntry(1, 9, now - DAY), seedEntry(2, 9, now - 70 * DAY)] });
    await db.collection('pools').doc(b).set({ level: 10, shard: 3, updatedAt: Timestamp.now(),
      entries: [seedEntry(3, 10, now - 61 * DAY)] });
    const removed = await sweepAllPools(db, now);
    assert.ok(removed >= 2);
    assert.deepEqual((await poolEntries(a)).map((e) => e.runId), ['seed-1']);
    assert.deepEqual(await poolEntries(b), []);
  });

  it('§3.13 recent runs older than 60 days are trimmed from the player doc', async () => {
    const uid = uniq('recent');
    const now = Date.now();
    const old = makeRun({ score: 2, tsMs: now - 61 * DAY });
    const fresh = makeRun({ score: 2, tsMs: now - DAY });
    const p = makePlayer({ best: 5, recent: [fresh, old] });
    await db.collection('players').doc(uid).set(p);
    const r = await processLive(uid, undefined, p, { nowMs: now });
    assert.equal(r.trimmedRecent, 1);
    const recent = await waitFor(async () => {
      const d = (await db.collection('players').doc(uid).get()).data();
      return d && d.recent.length === 1 ? d.recent : null;
    });
    assert.equal(recent[0].runId, fresh.runId);
  });
});

describe('§3.13 deleteMyData (data part)', () => {
  it('§3.13 removes the player doc, the rate doc and the entries in every shard; idempotent', async () => {
    const uid = uniq('wipe');
    const now = Date.now();
    for (const s of [0, 1, 2, 3]) {
      const run = makeRun({ score: 120 + s });
      await processLive(uid, undefined, makePlayer({ best: 120 + s, bestRun: run, recent: [run] }), {
        rand: () => s / 4,
        nowMs: now,
      });
    }
    await db.collection('players').doc(uid).set({ marker: true });
    const removed = await deletePlayerData(db, uid);
    assert.equal(removed, 4);
    for (const s of [0, 1, 2, 3]) assert.ok((await poolEntries(poolId(3, s))).every((e) => e.uid !== uid));
    assert.equal((await db.collection('players').doc(uid).get()).exists, false);
    assert.equal(await rate(uid), undefined);
    assert.equal(await deletePlayerData(db, uid), 0);
  });

  it('S6-61 a failure inside the deletion deletes nothing; a retry completes it', async () => {
    const uid = uniq('atomic');
    const now = Date.now();
    for (const s of [0, 1]) {
      const run = makeRun({ score: 130 + s });
      await processLive(uid, undefined, makePlayer({ best: 130 + s, bestRun: run, recent: [run] }), {
        rand: () => s / 4,
        nowMs: now,
      });
    }
    await db.collection('players').doc(uid).set({ marker: true });
    // The same emulator, with the rate-doc delete failing inside the transaction.
    const faulty = {
      collection: (c: string) => db.collection(c),
      runTransaction: <T>(fn: (tx: Transaction) => Promise<T>) =>
        db.runTransaction((tx) =>
          fn(
            new Proxy(tx, {
              get(t, k) {
                if (k === 'delete') {
                  return (ref: DocumentReference) => {
                    if (ref.path.startsWith(`${RATE_COLLECTION}/`)) throw new Error('injected rate deletion failure');
                    return t.delete(ref);
                  };
                }
                const v = Reflect.get(t, k, t);
                return typeof v === 'function' ? v.bind(t) : v;
              },
            }),
          ),
        ),
    } as unknown as Firestore;
    await assert.rejects(deletePlayerData(faulty, uid), /injected/);
    assert.equal((await db.collection('players').doc(uid).get()).exists, true);
    assert.notEqual(await rate(uid), undefined);
    for (const s of [0, 1]) assert.ok((await poolEntries(poolId(3, s))).some((e) => e.uid === uid));
    // Re-run: the complete end state.
    assert.equal(await deletePlayerData(db, uid), 2);
    assert.equal((await db.collection('players').doc(uid).get()).exists, false);
    assert.equal(await rate(uid), undefined);
    for (const s of [0, 1]) assert.ok((await poolEntries(poolId(3, s))).every((e) => e.uid !== uid));
  });
});
