/**
 * §3.13 onPlayerRunWrite logic against the Firestore emulator (direct calls of
 * processPlayerWrite / sweepAllPools / deletePlayerData with a fixed clock and shard).
 */
import assert from 'node:assert/strict';
import { DocumentReference, Firestore, Timestamp, Transaction } from 'firebase-admin/firestore';
import { deletePlayerData, flagId, processPlayerWrite, sweepAllPools } from '../src/pools.js';
import { DAILY_BEST_UPLOADS, FLAGS_COLLECTION, POOL_CAP, POOL_MAX_BYTES, poolId, RATE_COLLECTION } from '../src/schema.js';
import { docSize } from '../src/size.js';
import { DAY, LOOK, db, makePlayer, makeRun, poolEntries, processLive, uniq, waitFor } from './helpers.js';

const shard0 = () => 0;
const rate = async (uid: string) => (await db.collection(RATE_COLLECTION).doc(uid).get()).data();

describe('§3.13 onPlayerRunWrite: accept', () => {
  it('§3.13 a new best run goes to a shard of the server-computed bracket, newest first', async () => {
    const uid = uniq('acc');
    const run = makeRun({ score: 150 });
    const after = { ...makePlayer({ best: 150, bestRun: run, recent: [run] }), level: 9 }; // client level is wrong
    const now = Date.now();
    const r = await processLive(uid, undefined, after, { rand: shard0, nowMs: now });
    assert.deepEqual(r.accepted, [run.runId]);
    assert.equal(r.pool, poolId(3, 0)); // best 150 → bracket 3
    const entries = await poolEntries(poolId(3, 0));
    const e = entries[0];
    assert.equal(e.uid, uid);
    assert.equal(e.runId, run.runId);
    assert.equal(e.level, 3); // the stored pool `level` field is the bracket
    assert.equal(e.plv, 9); // PRD-2.6 R4 the player's level is copied, not used for filing
    assert.equal(e.tl, run.tl);
    assert.equal((e.ts as Timestamp).toMillis(), now); // upload time is the server's
    assert.equal((await rate(uid))?.last?.status, 'accepted');
  });

  it('§3.13 pool filing uses the best-score bracket and copies plv/space from the player', async () => {
    const cases: Array<{ level: number; plv: number; space?: boolean }> = [
      { level: 25, plv: 25 },
      { level: 12000, plv: 9999 },
      { level: undefined as unknown as number, plv: 0 },
      { level: 0, plv: 0, space: true },
    ];
    for (const c of cases) {
      const uid = uniq('bracket');
      const run = makeRun({ score: 80 });
      const player = makePlayer({ best: 80, bestRun: run, recent: [run] });
      if (c.level === undefined) delete (player as Partial<typeof player>).level;
      else player.level = c.level;
      if (c.space) (player as typeof player & { space?: boolean }).space = true;
      const r = await processLive(uid, undefined, player, { rand: shard0 });
      assert.deepEqual(r.accepted, [run.runId]);
      assert.equal(r.pool, poolId(2, 0)); // best 80 → bracket 2
      const e = (await poolEntries(poolId(2, 0))).find((x) => x.runId === run.runId)!;
      assert.equal(e.level, 2);
      assert.equal(e.plv, c.plv, `level ${c.level}`);
      assert.equal(e.space, c.space === true ? true : undefined, `space for level ${c.level}`);
    }
  });

  // region P26-S1
  it('F9 preserves a valid run card and keeps a 2.5 run card-less', async () => {
    for (const card of ['f_orbit|n_fire|s_fireworks', '|n_ocean|', '||', undefined]) {
      const uid = uniq('card');
      const run = makeRun({ score: 80 });
      run.look = { ...run.look };
      if (card !== undefined) run.look.card = card;
      const player = makePlayer({ best: 80, bestRun: run, recent: [run] });
      // Copy the run's look, even when the current player look differs.
      player.look = { ...player.look, card: 'pecking||' };
      const r = await processLive(uid, undefined, player, { rand: shard0 });
      assert.deepEqual(r.accepted, [run.runId]);
      const entry = (await poolEntries(poolId(2, 0))).find((e) => e.runId === run.runId)!;
      assert.deepEqual(entry.look, run.look);
      assert.equal(Object.hasOwn(entry.look, 'card'), card !== undefined);
    }
  });

  it('F9 rejects an invalid run card before it reaches a pool', async () => {
    const uid = uniq('badcard');
    const run = makeRun({ score: 80 });
    run.look = { ...run.look, card: 'f_unknown|n_fire|s_fireworks' };
    const r = await processLive(uid, undefined, makePlayer({ best: 80, bestRun: run, recent: [run] }), { rand: shard0 });
    assert.deepEqual(r.accepted, []);
    assert.deepEqual(r.rejected, [{ runId: run.runId, reason: 'shape' }]);
    assert.ok((await poolEntries(poolId(2, 0))).every((e) => e.uid !== uid));
  });
  // endregion

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

  it('audit 17: a forged client raising best by 1 per write pools at most 20 new bests a UTC day', async () => {
    const uid = uniq('bestcap');
    const day0 = Date.UTC(2026, 9, 9, 12);
    let prev = makePlayer({ best: 10 });
    const results: string[] = [];
    for (let i = 0; i < DAILY_BEST_UPLOADS + 2; i++) {
      const run = makeRun({ score: 11 + i });
      const next = makePlayer({ best: 11 + i, bestRun: run, recent: [run] });
      const r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + i });
      results.push(r.accepted.length ? 'ok' : r.rejected[0].reason);
      prev = next;
    }
    assert.deepEqual(results, [...Array(DAILY_BEST_UPLOADS).fill('ok'), 'rate', 'rate']);
    // The non-best allowance is separate and untouched.
    assert.equal((await rate(uid))?.count, 0);
    // The next UTC day resets the cap.
    const run = makeRun({ score: 100 });
    const next = makePlayer({ best: 100, bestRun: run, recent: [run] });
    const r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + DAY });
    assert.deepEqual(r.accepted, [run.runId]);
    assert.equal((await rate(uid))?.bestCount, 1);
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
      // region P26-S1
      look: { ...LOOK, card: 'f_orbit|n_fire|s_fireworks' },
      // endregion
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

describe('PRD-2.5 §3.6 anomaly flags (D3: flag only)', () => {
  const flagDoc = async (uid: string, runId: string) =>
    (await db.collection(FLAGS_COLLECTION).doc(flagId(uid, runId)).get()).data();
  const flagsOf = async (uid: string) => (await db.collection(FLAGS_COLLECTION).where('uid', '==', uid).get()).docs;
  /** An honest-paced run (plain passes 1.7 s apart, streak values). */
  const honest = (o: { score?: number; best?: number } = {}) => {
    const n = 20;
    const values = Array.from({ length: n }, (_, i) => Math.max(2, i + 1)); // Σ = 211
    return makeRun({ ...o, score: 211, best: o.best ?? 211, deltas: values.map(() => 170), values });
  };
  /** A streak_jump cheat that the old filter accepts: 2, 3, 9. */
  const cheat = (o: { best?: number } = {}) =>
    makeRun({ score: 14, best: o.best ?? 14, deltas: [200, 180, 180], flags: [0, 0, 0], values: [2, 3, 9] });

  it('a flagged run is pooled exactly like before and gets one versusFlags doc', async () => {
    const uid = uniq('flag');
    const run = cheat();
    const now = Date.now();
    const r = await processLive(uid, undefined, makePlayer({ best: 14, bestRun: run, recent: [run] }), {
      rand: shard0,
      nowMs: now,
    });
    assert.deepEqual(r.accepted, [run.runId]);
    assert.equal(r.pool, poolId(0, 0));
    assert.deepEqual(r.flagged, [run.runId]);
    const entry = (await poolEntries(poolId(0, 0))).find((e) => e.runId === run.runId);
    assert.ok(entry, 'pooled');
    assert.equal(entry!.uid, uid);
    assert.equal(entry!.score, 14);
    assert.equal(entry!.tl, run.tl);
    assert.equal(entry!.fl, run.fl);
    assert.equal((await rate(uid))?.last?.status, 'accepted');
    const f = await flagDoc(uid, run.runId);
    assert.ok(f, 'flag written');
    assert.equal(f!.uid, uid);
    assert.equal(f!.runId, run.runId);
    assert.equal(f!.score, 14);
    assert.deepEqual(f!.signals, { streak_jump: 9 });
    assert.equal(f!.soft, false);
    assert.equal(f!.pool, poolId(0, 0));
    assert.equal(f!.level, 0);
    assert.equal(f!.passes, 3);
    assert.equal(f!.durationCs, 200 + 180 + 180 + 80);
    assert.equal(f!.platform, 'android');
    assert.equal((f!.ts as Timestamp).toMillis(), now);
    assert.equal((f!.expireAt as Timestamp).toMillis(), now + 60 * DAY);
    // Idempotent: a retried event writes no second doc.
    await processLive(uid, undefined, makePlayer({ best: 14, bestRun: run, recent: [run] }), { rand: shard0, nowMs: now });
    assert.equal((await flagsOf(uid)).length, 1);
  });

  it('an honest run writes no flag', async () => {
    const uid = uniq('noflag');
    const run = honest();
    const r = await processLive(uid, undefined, makePlayer({ best: 211, bestRun: run, recent: [run] }), { rand: shard0 });
    assert.deepEqual(r.accepted, [run.runId]);
    assert.equal(r.flagged, undefined);
    assert.equal((await flagsOf(uid)).length, 0);
  });

  it('a rate-limited run is still judged (flag with pool null); a rejected run is not', async () => {
    const uid = uniq('flagrate');
    const day0 = Date.UTC(2026, 9, 21, 12);
    let prev = makePlayer({ best: 300 });
    const recent: ReturnType<typeof makeRun>[] = [];
    for (let i = 0; i < 3; i++) {
      const run = honest({ best: 300 });
      recent.unshift(run);
      const next = makePlayer({ best: 300, recent: recent.slice(0, 5) });
      await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + i });
      prev = next;
    }
    const run = cheat({ best: 300 });
    recent.unshift(run);
    const next = makePlayer({ best: 300, recent: recent.slice(0, 5) });
    const r = await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + 3 });
    assert.deepEqual(r.rejected, [{ runId: run.runId, reason: 'rate' }]);
    assert.deepEqual(r.flagged, [run.runId]);
    assert.equal((await flagDoc(uid, run.runId))!.pool, null);
    // A run the cheat filter rejects (sum ≠ score) is not judged.
    const bad = { ...cheat({ best: 300 }), score: 15 };
    recent.unshift(bad);
    const next2 = makePlayer({ best: 300, recent: recent.slice(0, 5) });
    const r2 = await processLive(uid, next, next2, { rand: shard0, nowMs: day0 + 4 });
    assert.deepEqual(r2.rejected, [{ runId: bad.runId, reason: 'count' }]);
    assert.equal(r2.flagged, undefined);
  });

  it('RateDoc.scores keeps the last 10 scores of runs that passed checkRun', async () => {
    const uid = uniq('hist');
    const day0 = Date.UTC(2026, 9, 22, 12);
    let prev = makePlayer({ best: 0 });
    for (let i = 0; i < 12; i++) {
      const run = makeRun({ score: 10 + i, deltas: Array.from({ length: 10 + i }, () => 170) });
      const next = makePlayer({ best: 10 + i, bestRun: run, recent: [run] });
      await processLive(uid, prev, next, { rand: shard0, nowMs: day0 + i });
      prev = next;
    }
    assert.deepEqual((await rate(uid))?.scores, [12, 13, 14, 15, 16, 17, 18, 19, 20, 21]);
  });

  it('deletePlayerData removes the uid flags (and only theirs)', async () => {
    const uid = uniq('flagdel');
    const other = uniq('flagkeep');
    for (const u of [uid, other]) {
      const run = cheat();
      await processLive(u, undefined, makePlayer({ best: 14, bestRun: run, recent: [run] }), { rand: shard0 });
    }
    assert.equal((await flagsOf(uid)).length, 1);
    await db.collection('players').doc(uid).set({ marker: true });
    await deletePlayerData(db, uid);
    assert.equal((await flagsOf(uid)).length, 0);
    assert.equal((await flagsOf(other)).length, 1);
    await deletePlayerData(db, uid); // idempotent
  });
});
