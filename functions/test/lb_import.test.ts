/** PRD-2.6 C8/C9: the verified best-run import and the release-blocking LB-only cleanup. */
import assert from 'node:assert/strict';
import { getApps } from 'firebase-admin/app';
import { getFirestore, Timestamp, type Firestore } from 'firebase-admin/firestore';
import {
  bestDocFromPlayers,
  databaseForProject,
  importLeaderboard,
  runImportCli,
  validCleanupArgs,
  validImportArgs,
  verifiedRunFor,
} from '../scripts/lb_import.js';
import {
  cleanupLeaderboard,
  planCleanup,
  printCleanupPlan,
  pruneGhostEntries,
  pruneGroup,
  runCleanupCli,
} from '../scripts/lb_cleanup_test.js';
import type { LbGhostDay, LbGhostPoolDoc, LbGroupDoc, LbPlayerDoc, PlayerDoc } from '../src/schema.js';
import { DAY, LOOK, makePlayer, makeRun, uniq } from './helpers.js';

const T0 = Date.UTC(2026, 9, 20, 12, 0, 0);
const at = (ms: number) => Timestamp.fromMillis(ms);
const NOW = T0 + 30 * DAY;

/** The demo emulator project; per-test clearing below removes this file's seeded state. */
const db = getFirestore();

async function clearCollection(name: string): Promise<void> {
  for (;;) {
    const snap = await db.collection(name).limit(200).get();
    if (snap.empty) return;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    if (snap.size < 200) return;
  }
}

beforeEach(async () => {
  for (const name of ['players', 'lbPlayers', 'lbBest', 'lbMeta', 'lbGifts', 'lbGhostPool', 'lbGroups']) {
    await clearCollection(name);
  }
});


function player(over: Partial<PlayerDoc> & { best: number }): PlayerDoc {
  return { ...makePlayer({ best: over.best }), ...over };
}

function imported(uid: string, best: number, src: 'import' | 'play' = 'import'): LbPlayerDoc {
  return {
    best,
    bestAt: at(T0),
    bestShadow: best,
    name: `SwiftKiwi${String(best).padStart(3, '0').slice(-3)}`,
    look: LOOK,
    platform: 'android',
    bracket: 0,
    hidden: false,
    src,
    expireAt: at(NOW + 400 * DAY),
  };
}

function interruptImportAfterPlayerWrites(original: Firestore): Firestore {
  return new Proxy(original, {
    get(target, property) {
      const value = Reflect.get(target, property, target);
      if (property !== 'collection') {
        return typeof value === 'function' ? value.bind(target) : value;
      }
      return (path: string) => {
        const collection = value.call(target, path);
        if (path !== 'lbBest') return collection;
        return new Proxy(collection, {
          get(collectionTarget, collectionProperty) {
            const collectionValue = Reflect.get(collectionTarget, collectionProperty, collectionTarget);
            if (collectionProperty !== 'doc' || typeof collectionValue !== 'function') {
              return typeof collectionValue === 'function' ? collectionValue.bind(collectionTarget) : collectionValue;
            }
            return (...args: Parameters<typeof collection.doc>) => {
              const ref = collectionValue.apply(collectionTarget, args);
              return new Proxy(ref, {
                get(refTarget, refProperty) {
                  const refValue = Reflect.get(refTarget, refProperty, refTarget);
                  if (refProperty === 'get') {
                    return async () => {
                      throw new Error('interrupted after imported players committed');
                    };
                  }
                  return typeof refValue === 'function' ? refValue.bind(refTarget) : refValue;
                },
              });
            };
          },
        });
      };
    },
  });
}

function interruptCleanupAfterFirstCommittedBatch(original: Firestore): Firestore {
  let batchCalls = 0;
  return new Proxy(original, {
    get(target, property) {
      const value = Reflect.get(target, property, target);
      if (property !== 'batch') {
        return typeof value === 'function' ? value.bind(target) : value;
      }
      return () => {
        batchCalls++;
        const batch = target.batch();
        if (batchCalls === 1) return batch;
        return new Proxy(batch, {
          get(batchTarget, batchProperty) {
            if (batchProperty === 'delete') {
              return () => {
                throw new Error('interrupted after first cleanup batch committed');
              };
            }
            const batchValue = Reflect.get(batchTarget, batchProperty, batchTarget);
            return typeof batchValue === 'function' ? batchValue.bind(batchTarget) : batchValue;
          },
        });
      };
    },
  });
}

function group(_gid: string, members: string[], ghosts: string[]): LbGroupDoc {
  return {
    bracket: 0,
    start: at(T0),
    end: at(T0 + DAY),
    memberUids: members,
    members: Object.fromEntries(
      members.map((uid) => [uid, { t: 1, b: 1, n: 1, last: at(T0), name: uid, look: LOOK, platform: 'android' as const }]),
    ),
    ghosts: ghosts.map((uid) => ({ uid, runs: [], name: uid, look: LOOK, platform: 'android' as const })),
    ghostUids: ghosts,
    settled: false,
    expireAt: at(T0 + 4 * DAY),
  };
}

async function seedPlayers(db: Firestore, docs: Array<[string, PlayerDoc]>): Promise<void> {
  const batch = db.batch();
  for (const [uid, doc] of docs) batch.set(db.collection('players').doc(uid), doc);
  await batch.commit();
}

async function seedLb(db: Firestore, docs: Array<[string, LbPlayerDoc]>, gifts: string[], groups: Array<[string, LbGroupDoc]>, pools: Array<[string, LbGhostPoolDoc]>): Promise<void> {
  const batch = db.batch();
  for (const [uid, doc] of docs) batch.set(db.collection('lbPlayers').doc(uid), doc);
  for (const uid of gifts) {
    batch.set(db.collection('lbGifts').doc(`${uid}_g1`), {
      uid,
      gid: 'g1',
      tier: 'gold',
      boardRank: 1,
      expireAt: at(NOW + 400 * DAY),
    });
  }
  for (const [gid, doc] of groups) batch.set(db.collection('lbGroups').doc(gid), doc);
  for (const [id, doc] of pools) batch.set(db.collection('lbGhostPool').doc(id), doc);
  await batch.commit();
}

async function seedCleanupRetryData(keep: string, count: number): Promise<string[]> {
  const uids = Array.from({ length: count }, (_, index) => `cleanup-retry-${String(index).padStart(3, '0')}`);
  for (let offset = 0; offset < uids.length; offset += 200) {
    const batch = db.batch();
    for (const uid of uids.slice(offset, offset + 200)) {
      batch.set(db.collection('lbPlayers').doc(uid), imported(uid, 100));
      batch.set(db.collection('lbGifts').doc(`${uid}_g1`), {
        uid,
        gid: 'retry-g1',
        tier: 'gold',
        boardRank: 1,
        expireAt: at(NOW + 400 * DAY),
      });
    }
    await batch.commit();
  }
  await db.collection('lbPlayers').doc(keep).set(imported(keep, 500));
  return uids;
}

describe('PRD-2.6 C8 verified best-run import', () => {
  it('uses a verified bestRun, ignores forged best, falls back to the max verified recent and skips the rest', async () => {
    const bestUid = uniq('import-best');
    const forgedUid = uniq('import-forged');
    const recentUid = uniq('import-recent');
    const skippedUid = uniq('import-skip');

    const verifiedBest = makeRun({ runId: uniq('run'), score: 40, tsMs: T0, best: 40 });
    const forgedOnly = makeRun({ runId: uniq('run'), score: 30, tsMs: T0 + 1000 });
    const recentLow = makeRun({ runId: uniq('run'), score: 20, tsMs: T0 + 2000 });
    const recentHigh = makeRun({ runId: uniq('run'), score: 35, tsMs: T0 + 3000 });
    const broken = makeRun({ runId: uniq('run'), score: 99, tsMs: T0 + 4000, deltas: [1] });

    await seedPlayers(db, [
      [bestUid, player({ best: 999, bestRun: verifiedBest, recent: [] })],
      [forgedUid, player({ best: 800, bestRun: forgedOnly, recent: [] })],
      [recentUid, player({ best: 700, bestRun: null, recent: [recentLow, broken, recentHigh] })],
      [skippedUid, player({ best: 600, bestRun: broken, recent: [broken] })],
    ]);
    // A forged `best` is deliberately much larger than every verified score.
    await db.collection('players').doc(forgedUid).update({ best: 9999 });

    const result = await importLeaderboard(db, {
      keepUids: ['owner-a', 'owner-b'],
      apply: true,
      nowMs: NOW,
      log: () => {},
    });
    assert.equal(result.imported, 3);
    assert.equal(result.fromBestRun, 2);
    assert.equal(result.fromRecent, 1);
    assert.equal(result.skipped, 1);
    assert.deepEqual(result.importedUids, [bestUid, forgedUid, recentUid].sort());

    const best = (await db.collection('lbPlayers').doc(bestUid).get()).data() as LbPlayerDoc;
    assert.equal(best.best, 40);
    assert.equal(best.bestShadow, 40);
    assert.equal(best.bestAt.toMillis(), T0);
    assert.equal(best.src, 'import');
    assert.equal(best.expireAt.toMillis(), NOW + 400 * DAY);

    const forged = (await db.collection('lbPlayers').doc(forgedUid).get()).data() as LbPlayerDoc;
    assert.equal(forged.best, 30, 'players.best=9999 is never imported');

    const recent = (await db.collection('lbPlayers').doc(recentUid).get()).data() as LbPlayerDoc;
    assert.equal(recent.best, 35);
    assert.equal(recent.bestAt.toMillis(), T0 + 3000);

    assert.equal((await db.collection('lbPlayers').doc(skippedUid).get()).exists, false);

    const bestDoc = (await db.collection('lbBest').doc('global').get()).data() as { rows: Array<{ uid: string; best: number }>; floor: number };
    assert.deepEqual(
      bestDoc.rows.filter((row) => [bestUid, forgedUid, recentUid, skippedUid].includes(row.uid)).map((row) => [row.uid, row.best]),
      [[bestUid, 40], [recentUid, 35], [forgedUid, 30]],
    );
    assert.equal(bestDoc.floor, 30);

    const meta = (await db.collection('lbMeta').doc('import').get()).data();
    assert.equal(meta?.count, 3);
    assert.deepEqual(meta?.keepUids, ['owner-a', 'owner-b']);
    assert.equal(meta?.ranAt.toMillis(), NOW);
    assert.equal(meta?.cleanedAt, undefined);
  });

  it('prefers a verified bestRun over a higher verified recent run', () => {
    const bestRun = makeRun({ score: 20, tsMs: T0 });
    const recent = makeRun({ score: 80, tsMs: T0 + 1000 });
    const choice = verifiedRunFor(player({ best: 100, bestRun, recent: [recent] }));
    assert.equal(choice?.source, 'bestRun');
    assert.equal(choice?.run.score, 20);
  });

  it('a dry run writes neither lbPlayers, lbBest nor lbMeta', async () => {
    const uid = uniq('import-dry');
    await seedPlayers(db, [[uid, player({ best: 12, bestRun: makeRun({ score: 12, tsMs: T0 }), recent: [] })]]);
    // Dry run is the default; --apply is the only mode that writes.
    const result = await importLeaderboard(db, { keepUids: [], nowMs: NOW, log: () => {} });
    assert.ok(result.imported >= 1);
    assert.equal((await db.collection('lbPlayers').doc(uid).get()).exists, false);
    assert.equal((await db.collection('lbMeta').doc('import').get()).exists, false);
    assert.equal((await db.collection('lbBest').doc('global').get()).exists, false);
  });

  it('is idempotent: a second --apply leaves lbPlayers, lbBest and lbMeta byte-for-byte stable', async () => {
    const uid = uniq('import-idempotent');
    await seedPlayers(db, [
      [
        uid,
        player({
          best: 42,
          bestRun: makeRun({ score: 42, tsMs: T0, best: 42 }),
          recent: [],
          expireAt: at(NOW + 30 * DAY),
        }),
      ],
    ]);

    const first = await importLeaderboard(db, {
      keepUids: ['owner-a'],
      apply: true,
      nowMs: NOW,
      log: () => {},
    });
    assert.equal(first.imported, 1);
    assert.equal(first.unchanged, 0);
    const player1 = (await db.collection('lbPlayers').doc(uid).get()).data() as LbPlayerDoc;
    const best1 = (await db.collection('lbBest').doc('global').get()).data() as Record<string, any>;
    const meta1 = (await db.collection('lbMeta').doc('import').get()).data() as Record<string, any>;

    const second = await importLeaderboard(db, {
      keepUids: ['owner-a'],
      apply: true,
      nowMs: NOW + DAY,
      log: () => {},
    });
    assert.equal(second.imported, 1);
    assert.equal(second.unchanged, 1);

    const player2 = (await db.collection('lbPlayers').doc(uid).get()).data() as LbPlayerDoc;
    const best2 = (await db.collection('lbBest').doc('global').get()).data() as Record<string, any>;
    const meta2 = (await db.collection('lbMeta').doc('import').get()).data() as Record<string, any>;
    assert.equal(player2.best, player1.best);
    assert.equal(player2.bestAt.toMillis(), player1.bestAt.toMillis());
    assert.equal(player2.expireAt.toMillis(), player1.expireAt.toMillis(), 'a rerun must not renew the TTL');
    assert.equal(best2.updatedAt.toMillis(), best1.updatedAt.toMillis());
    assert.deepEqual(best2.rows, best1.rows);
    assert.equal(meta2.ranAt.toMillis(), meta1.ranAt.toMillis());
    assert.equal(meta2.count, meta1.count);

    // A completed cleanup gate stays valid when a rerun changes nothing.
    const cleanedAt = at(NOW + DAY);
    await db.collection('lbMeta').doc('import').set({ cleanedAt }, { merge: true });
    const third = await importLeaderboard(db, {
      keepUids: ['owner-a'],
      apply: true,
      nowMs: NOW + 2 * DAY,
      log: () => {},
    });
    assert.equal(third.unchanged, 1);
    const meta3 = (await db.collection('lbMeta').doc('import').get()).data();
    assert.equal(meta3?.cleanedAt.toMillis(), cleanedAt.toMillis());
  });

  it('invalidates cleanedAt before imported players commit, so an interrupted apply remains cleanup-gated', async () => {
    const uid = uniq('import-interrupted');
    await seedPlayers(db, [
      [uid, player({ best: 33, bestRun: makeRun({ score: 33, tsMs: T0, best: 33 }), recent: [] })],
    ]);
    await db.collection('lbMeta').doc('import').set({
      ranAt: at(T0),
      count: 0,
      keepUids: [],
      cleanedAt: at(T0),
    });

    await assert.rejects(
      importLeaderboard(interruptImportAfterPlayerWrites(db), {
        keepUids: [],
        apply: true,
        nowMs: NOW,
        log: () => {},
      }),
      /interrupted after imported players committed/,
    );
    assert.equal((await db.collection('lbPlayers').doc(uid).get()).exists, true);
    assert.equal((await db.collection('lbBest').doc('global').get()).exists, false);
    assert.equal((await db.collection('lbMeta').doc('import').get()).data()?.cleanedAt, undefined);

    const retry = await importLeaderboard(db, {
      keepUids: [],
      apply: true,
      nowMs: NOW,
      log: () => {},
    });
    assert.equal(retry.unchanged, 1);
    assert.equal((await db.collection('lbMeta').doc('import').get()).data()?.cleanedAt, undefined);

    await cleanupLeaderboard(db, { keepUids: [], apply: true, nowMs: NOW, log: () => {} });
    assert.equal((await db.collection('lbMeta').doc('import').get()).data()?.cleanedAt.toMillis(), NOW);
  });

  it('imports a player close to the 60-day source expiry but skips an already-expired source doc', async () => {
    const near = uniq('import-near-expiry');
    const stale = uniq('import-expired');
    await seedPlayers(db, [
      [
        near,
        player({
          best: 21,
          bestRun: makeRun({ score: 21, tsMs: T0 }),
          recent: [],
          expireAt: at(NOW + 3600_000),
        }),
      ],
      [
        stale,
        player({
          best: 88,
          bestRun: makeRun({ score: 88, tsMs: T0 }),
          recent: [],
          expireAt: at(NOW),
        }),
      ],
    ]);

    const result = await importLeaderboard(db, {
      keepUids: ['owner-a'],
      apply: true,
      nowMs: NOW,
      log: () => {},
    });
    assert.equal(result.imported, 1);
    assert.equal(result.expired, 1);
    assert.deepEqual(result.importedUids, [near]);
    assert.equal((await db.collection('lbPlayers').doc(near).get()).exists, true);
    assert.equal((await db.collection('lbPlayers').doc(stale).get()).exists, false);
  });

  it('rebuilds lbBest from bestShadow, excluding hidden players and keeping only the top 50', () => {
    const rows = Array.from({ length: 55 }, (_, i) => ({
      uid: `u${i}`,
      data: { ...imported(`u${i}`, i + 1), bestShadow: i + 1 },
    }));
    rows.push({ uid: 'hidden', data: { ...imported('hidden', 999), hidden: true } });
    const doc = bestDocFromPlayers(rows, NOW);
    assert.equal(doc.rows.length, 50);
    assert.equal(doc.rows[0].uid, 'u54');
    assert.equal(doc.floor, 6);
  });
});

describe('PRD-2.6 C9 release-blocking LB cleanup', () => {
  it('keeps the keep-list, deletes other imported rows and their gifts/ghost/group rows, and leaves pools untouched', async () => {
    const keepA = uniq('keep-a');
    const keepB = uniq('keep-b');
    const test = uniq('test-player');
    const play = uniq('play-player');

    await seedLb(
      db,
      [
        [keepA, imported(keepA, 500)],
        [keepB, imported(keepB, 400)],
        [test, imported(test, 300)],
        [play, imported(play, 200, 'play')],
      ],
      [test, play, keepA],
      [
        ['g1', group('g1', [keepA, test], [test, keepB])],
        ['g2', group('g2', [play], [play])],
      ],
      [
        [
          '0_0',
          {
            bracket: 0,
            shard: 0,
            updatedAt: at(T0),
            entries: [
              { uid: test, day: '2026-10-19', runs: [], name: test, look: LOOK, platform: 'android' },
              { uid: keepB, day: '2026-10-19', runs: [], name: keepB, look: LOOK, platform: 'android' },
              { uid: play, day: '2026-10-19', runs: [], name: play, look: LOOK, platform: 'android' },
            ],
          },
        ],
      ],
    );
    const versus = db.collection('pools').doc('0_0');
    await versus.set({ level: 0, shard: 0, updatedAt: at(T0), entries: [{ uid: test, score: 300 }, { uid: play, score: 200 }] });

    const result = await cleanupLeaderboard(db, { keepUids: [keepA, keepB], apply: true, nowMs: NOW, log: () => {} });
    assert.deepEqual(result.removedPlayers, [test]);
    assert.equal(result.keptImported, 2);
    assert.equal(result.keptPlay, 1);
    assert.equal(result.gifts, 1);
    assert.equal(result.ghostEntries, 1);
    assert.equal(result.groupRows, 2);
    assert.equal(result.groupsChanged, 1);

    assert.equal((await db.collection('lbPlayers').doc(test).get()).exists, false);
    assert.equal((await db.collection('lbPlayers').doc(keepA).get()).exists, true);
    assert.equal((await db.collection('lbPlayers').doc(keepB).get()).exists, true);
    assert.equal((await db.collection('lbPlayers').doc(play).get()).exists, true);

    assert.equal((await db.collection('lbGifts').doc(`${test}_g1`).get()).exists, false);
    assert.equal((await db.collection('lbGifts').doc(`${play}_g1`).get()).exists, true);
    assert.equal((await db.collection('lbGifts').doc(`${keepA}_g1`).get()).exists, true);

    const pool = (await db.collection('lbGhostPool').doc('0_0').get()).data() as LbGhostPoolDoc;
    assert.deepEqual(pool.entries.map((entry) => entry.uid).sort(), [keepB, play].sort());

    const g1 = (await db.collection('lbGroups').doc('g1').get()).data() as LbGroupDoc;
    assert.deepEqual(g1.memberUids, [keepA]);
    assert.deepEqual(Object.keys(g1.members), [keepA]);
    assert.deepEqual(g1.ghosts.map((ghost) => ghost.uid), [keepB]);
    assert.deepEqual(g1.ghostUids, [keepB]);
    const g2 = (await db.collection('lbGroups').doc('g2').get()).data() as LbGroupDoc;
    assert.deepEqual(g2.memberUids, [play]);
    assert.deepEqual(g2.ghosts.map((ghost) => ghost.uid), [play]);

    const versusData = (await versus.get()).data();
    assert.equal(versusData?.entries.length, 2, 'versus pools keep their test runs (O7)');

    const best = (await db.collection('lbBest').doc('global').get()).data() as { rows: Array<{ uid: string }> };
    assert.equal(best.rows.some((row) => row.uid === test), false);
    const meta = (await db.collection('lbMeta').doc('import').get()).data();
    assert.equal(meta?.cleanedAt.toMillis(), NOW);
    assert.deepEqual(meta?.keepUids, [keepA, keepB]);
  });

  it('resumes safely after a committed 400-deletion batch without losing its cleanup targets', async () => {
    const keep = uniq('cleanup-retry-keep');
    const removed = await seedCleanupRetryData(keep, 400);

    await assert.rejects(
      cleanupLeaderboard(interruptCleanupAfterFirstCommittedBatch(db), {
        keepUids: [keep],
        apply: true,
        nowMs: NOW,
        log: () => {},
      }),
      /interrupted after first cleanup batch committed/,
    );

    assert.equal((await db.collection('lbGifts').limit(1).get()).size, 0, 'the first committed batch removes gifts');
    const surviving = await db.collection('lbPlayers').get();
    const survivingUids = new Set(surviving.docs.map((doc) => doc.id));
    assert.equal(survivingUids.has(keep), true);
    assert.deepEqual(
      removed.filter((uid) => !survivingUids.has(uid)),
      [],
      'target players stay durable until their dependent artifacts are gone',
    );

    const retry = await cleanupLeaderboard(db, {
      keepUids: [keep],
      apply: true,
      nowMs: NOW,
      log: () => {},
    });
    assert.deepEqual(retry.removedPlayers, removed.sort());
    assert.equal(retry.keptImported, 1);
    assert.equal((await db.collection('lbPlayers').doc(keep).get()).exists, true);
    for (const uid of removed) {
      assert.equal((await db.collection('lbPlayers').doc(uid).get()).exists, false);
    }
    assert.equal((await db.collection('lbGifts').limit(1).get()).size, 0);
    assert.equal((await db.collection('lbMeta').doc('import').get()).data()?.cleanedAt.toMillis(), NOW);
  });

  it('a dry run writes nothing, including no cleanedAt', async () => {
    const test = uniq('test-dry');
    await seedLb(db, [[test, imported(test, 100)]], [test], [], []);
    const previous = at(T0);
    await db.collection('lbMeta').doc('import').set({
      ranAt: at(T0 - DAY),
      count: 1,
      keepUids: [],
      cleanedAt: previous,
    });
    const result = await cleanupLeaderboard(db, { keepUids: [], apply: false, nowMs: NOW, log: () => {} });
    assert.deepEqual(result.removedPlayers, [test]);
    assert.equal((await db.collection('lbPlayers').doc(test).get()).exists, true);
    assert.equal((await db.collection('lbGifts').doc(`${test}_g1`).get()).exists, true);
    const meta = (await db.collection('lbMeta').doc('import').get()).data();
    assert.equal(meta?.cleanedAt.toMillis(), previous.toMillis());
  });

  it('prints the dry-run deletions and the remaining best board', async () => {
    const test = uniq('test-print');
    const keep = uniq('keep-print');
    await seedLb(db, [[test, imported(test, 100)], [keep, imported(keep, 200)]], [test], [], []);
    const plan = await planCleanup(db, { keepUids: [keep], apply: false, nowMs: NOW, log: () => {} });
    const lines: string[] = [];
    printCleanupPlan('demo-project', false, plan, (line) => lines.push(line));
    const text = lines.join('\n');
    assert.match(text, /LB cleanup DRY RUN/);
    assert.match(text, new RegExp(`DELETE lbPlayers/${test}`));
    assert.match(text, new RegExp(`DELETE lbGifts/${test}_g1`));
    assert.match(text, /DRY RUN — nothing written/);
    assert.match(text, /Top 50/);
    assert.match(text, new RegExp(keep));
    assert.doesNotMatch(text.split('Top 50')[1], new RegExp(test));
  });

  it('prunes only the removed uids from ghost pools and group rows', () => {
    const entries = [
      { uid: 'a', day: '2026-10-18', runs: [[1, 1]], name: 'a', look: LOOK, platform: 'android' },
      { uid: 'b', day: '2026-10-19', runs: [[2, 2]], name: 'b', look: LOOK, platform: 'android' },
    ] satisfies LbGhostDay[];
    assert.deepEqual(pruneGhostEntries(entries, new Set(['a'])).map((entry) => entry.uid), ['b']);
    const g = group('g', ['a', 'b'], ['a', 'b']);
    const change = pruneGroup(g, new Set(['a']));
    assert.deepEqual(change, { gid: '', removeMembers: ['a'], removeGhosts: ['a'], removeGhostUids: ['a'] });
    const inconsistent = { ...g, memberUids: [], members: { a: g.members.a }, ghosts: [], ghostUids: ['a'] };
    assert.deepEqual(pruneGroup(inconsistent, new Set(['a'])), {
      gid: '',
      removeMembers: ['a'],
      removeGhosts: [],
      removeGhostUids: ['a'],
    });
  });
});

describe('C8/C9 CLI contract', () => {
  it('validates flags and refuses a missing --project before touching Firestore', async () => {
    assert.equal(validImportArgs(['--dry-run']), true);
    assert.equal(validImportArgs(['--apply']), true);
    assert.equal(validImportArgs(['--execute']), false);
    assert.equal(validImportArgs(['--project']), false);
    assert.equal(validCleanupArgs(['--keep', 'a', '--apply']), true);
    assert.equal(validCleanupArgs(['--keep', 'a', '--execute']), false);

    const appsBefore = getApps().length;
    const errors: string[] = [];
    const original = console.error;
    console.error = (line: unknown) => errors.push(String(line));
    try {
      assert.equal(await runImportCli([]), 2);
      assert.equal(await runCleanupCli(['--keep', 'owner-a']), 2);
    } finally {
      console.error = original;
    }
    assert.equal(errors.filter((line) => line.includes('--project is required')).length, 2);
    assert.equal(getApps().length, appsBefore, 'a rejected CLI must not initialize another Firebase app');
  });

  it('binds the admin database to the explicit demo project, not an existing default app', () => {
    const project = 'demo-flappy-spikes';
    const explicitDb = databaseForProject(project);
    const adminApp = getApps().find((app) => app.name === `lb-tools-${project}`);
    assert.ok(adminApp, 'the tools use a project-named app');
    assert.equal(adminApp?.options.projectId, project);
    assert.notEqual(explicitDb, db, 'the tools never reuse the default Admin app');
  });
});
