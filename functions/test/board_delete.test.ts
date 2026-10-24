/** PRD-2.6 LB3 Delete My Data and the server-derived name hooks. */
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { deleteBoardData, lbSyncName } from '../src/board_delete.js';
import { lbSubmitRun } from '../src/board_store.js';
import { nameKey } from '../src/nameclaims.js';
import { versusName } from '../src/nickname.js';
import { getCustomName, releaseStaleGuestNames, setCustomName } from '../src/pools.js';
import {
  LB_BEST_COLLECTION,
  LB_FLAGS_COLLECTION,
  LB_GHOST_POOL_COLLECTION,
  LB_GIFTS_COLLECTION,
  LB_GROUPS_COLLECTION,
  LB_OPEN_COLLECTION,
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  MAX_BRACKET,
  NAMES_COLLECTION,
  type LbBestDoc,
  type LbGhostPoolDoc,
  type LbGroupDoc,
  type LbPlayerDoc,
} from '../src/schema.js';
import { encodeDeltas, encodeEntries } from '../src/timeline.js';
import { auth, db, fakeJwt, LOOK, PROJECT, uniq } from './helpers.js';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const T0 = Date.UTC(2026, 9, 20, 12, 0, 0);
const CLAIMS_COLLECTION = 'versusNameClaims';
const CLEARED = [
  LB_BEST_COLLECTION,
  LB_FLAGS_COLLECTION,
  LB_GHOST_POOL_COLLECTION,
  LB_GIFTS_COLLECTION,
  LB_GROUPS_COLLECTION,
  LB_OPEN_COLLECTION,
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  NAMES_COLLECTION,
  CLAIMS_COLLECTION,
];

function at(ms: number): Timestamp {
  return Timestamp.fromMillis(ms);
}

function player(uid: string, groupId: string | null, name: string, best = 900): LbPlayerDoc {
  return {
    best,
    bestAt: at(T0),
    bestShadow: best,
    name,
    look: LOOK,
    platform: 'android',
    bracket: 5,
    groupId,
    groupStart: groupId === null ? null : at(T0),
    groupEnd: groupId === null ? null : at(T0 + DAY),
    hidden: false,
    src: 'play',
    expireAt: at(T0 + 400 * DAY),
  };
}

function group(gid: string, uid: string, other: string, name: string): LbGroupDoc {
  const member = {
    t: 900,
    b: 900,
    n: 1,
    last: at(T0),
    name,
    look: LOOK,
    platform: 'android' as const,
  };
  return {
    bracket: 5,
    start: at(T0),
    end: at(T0 + DAY),
    memberUids: [uid, other],
    members: {
      [uid]: member,
      [other]: { ...member, t: 800, b: 800, name: 'OtherOwl' },
    },
    // Firestore stores `[todSec, score]` as {t, s}; the in-memory schema keeps tuples.
    ghosts: [
      { uid, runs: [{ t: 100, s: 42 }], name, look: LOOK, platform: 'android' },
      { uid: other, runs: [{ t: 200, s: 40 }], name: 'OtherOwl', look: LOOK, platform: 'android' },
    ] as unknown as LbGroupDoc['ghosts'],
    ghostUids: [uid, other],
    settled: false,
    expireAt: at(T0 + 4 * DAY),
  };
}

async function seedBoardPlayer(uid: string, gid: string | null, name: string, best = 900): Promise<void> {
  await db.collection(LB_PLAYERS_COLLECTION).doc(uid).set(player(uid, gid, name, best));
}

function runRequest(score = 70) {
  const deltas = Array.from({ length: score }, () => 140);
  return {
    runs: [{
      id: uniq('bd-run'),
      score,
      hoops: score,
      cs: Math.max(1400, score * 140 + 80),
      endTs: T0,
      mode: 'free',
      tl: encodeDeltas(deltas),
      fl: encodeEntries(deltas.map(() => 0), deltas.map(() => 1)),
    }],
    name: 'BraveOwl123',
    look: LOOK,
    platform: 'android',
  };
}

function idToken(uid: string): string {
  return fakeJwt({
    sub: uid,
    user_id: uid,
    aud: PROJECT,
    iss: `https://securetoken.google.com/${PROJECT}`,
    iat: 1,
    exp: 4e9,
  });
}

const APP_CHECK = fakeJwt({
  sub: '1:512525012529:android:8bb85c213b543c6487cf10',
  aud: [`projects/${PROJECT}`],
});

async function callable(name: string, uid: string, data: unknown): Promise<{ status: number; json: any; text: string }> {
  const res = await fetch(`http://127.0.0.1:5001/${PROJECT}/europe-west1/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken(uid)}`,
      'X-Firebase-AppCheck': APP_CHECK,
    },
    body: JSON.stringify({ data }),
  });
  const text = await res.clone().text();
  return { status: res.status, json: await res.json(), text };
}

async function boardDocsReferencingUid(uid: string): Promise<string[]> {
  const found: string[] = [];
  const players = await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get();
  if (players.exists) found.push(`${LB_PLAYERS_COLLECTION}/${uid}`);

  const groups = await db.collection(LB_GROUPS_COLLECTION).get();
  for (const doc of groups.docs) {
    const g = doc.data() as LbGroupDoc;
    if (
      (g.memberUids ?? []).includes(uid) ||
      Object.prototype.hasOwnProperty.call(g.members ?? {}, uid) ||
      (g.ghostUids ?? []).includes(uid) ||
      (g.ghosts ?? []).some((ghost) => ghost.uid === uid)
    ) {
      found.push(`${LB_GROUPS_COLLECTION}/${doc.id}`);
    }
  }

  const pools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
  for (const doc of pools.docs) {
    if (((doc.data() as LbGhostPoolDoc).entries ?? []).some((entry) => entry.uid === uid)) {
      found.push(`${LB_GHOST_POOL_COLLECTION}/${doc.id}`);
    }
  }

  for (const collection of [LB_GIFTS_COLLECTION, LB_FLAGS_COLLECTION]) {
    const snap = await db.collection(collection).where('uid', '==', uid).get();
    for (const doc of snap.docs) found.push(`${collection}/${doc.id}`);
  }

  const best = await db.collection(LB_BEST_COLLECTION).doc('global').get();
  if (best.exists && ((best.data() as LbBestDoc).rows ?? []).some((row) => row.uid === uid)) {
    found.push(`${LB_BEST_COLLECTION}/global`);
  }
  return found;
}

beforeEach(async () => {
  for (const name of CLEARED) await db.recursiveDelete(db.collection(name));
});

describe('PRD-2.6 LB3 Delete My Data', () => {
  it('deleteMyData removes every lb trace, refills lbBest and is idempotent', async () => {
    const uid = uniq('bd-delete');
    const other = uniq('bd-other');
    const gid = uniq('bd-group');
    await auth.createUser({ uid });

    await seedBoardPlayer(uid, gid, 'WiseOwl', 900);
    await seedBoardPlayer(other, gid, 'OtherOwl', 800);
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).set(group(gid, uid, other, 'WiseOwl'));

    const poolBatch = db.batch();
    for (let bracket = 0; bracket <= MAX_BRACKET; bracket++) {
      for (let shard = 0; shard < 4; shard++) {
        poolBatch.set(db.collection(LB_GHOST_POOL_COLLECTION).doc(`${bracket}_${shard}`), {
          bracket,
          shard,
          updatedAt: at(T0),
          entries: [
            { uid, day: '2026-10-19', runs: [{ t: 100, s: 42 }], name: 'WiseOwl', look: LOOK, platform: 'android' },
            { uid: other, day: '2026-10-19', runs: [{ t: 200, s: 40 }], name: 'OtherOwl', look: LOOK, platform: 'android' },
          ],
        });
      }
    }
    poolBatch.set(db.collection(LB_GIFTS_COLLECTION).doc(`${uid}_g1`), {
      uid, gid: 'g1', tier: 'gold', boardRank: 1, expireAt: at(T0 + 400 * DAY),
    });
    poolBatch.set(db.collection(LB_GIFTS_COLLECTION).doc(`${other}_g1`), {
      uid: other, gid: 'g1', tier: 'silver', boardRank: 2, expireAt: at(T0 + 400 * DAY),
    });
    poolBatch.set(db.collection(LB_FLAGS_COLLECTION).doc(`${uid}_run`), {
      uid, runId: 'run', score: 900, best: 900, signals: { gap: 1 }, ts: at(T0), expireAt: at(T0 + 60 * DAY),
    });
    poolBatch.set(db.collection(LB_FLAGS_COLLECTION).doc(`${other}_run`), {
      uid: other, runId: 'run', score: 800, best: 800, signals: { gap: 1 }, ts: at(T0), expireAt: at(T0 + 60 * DAY),
    });
    const best: LbBestDoc = {
      rows: [
        { uid, best: 900, bestAt: at(T0), name: 'WiseOwl', look: LOOK, platform: 'android', bracket: 5 },
        { uid: other, best: 800, bestAt: at(T0 + 1000), name: 'OtherOwl', look: LOOK, platform: 'android', bracket: 5 },
      ],
      floor: 800,
      updatedAt: at(T0),
    };
    poolBatch.set(db.collection(LB_BEST_COLLECTION).doc('global'), best);
    poolBatch.set(db.collection(LB_BEST_COLLECTION).doc('hist'), {
      bins: { '900': 1, '800': 1 },
      updatedAt: at(T0),
    });
    await poolBatch.commit();

    const first = await callable('deleteMyData', uid, {});
    assert.equal(first.status, 200, first.text);
    assert.equal(first.json.result.ok, true);
    assert.deepEqual(await boardDocsReferencingUid(uid), []);

    const tomb = await db.collection(LB_TOMB_COLLECTION).doc(uid).get();
    assert.equal(tomb.exists, true);
    const tombData = tomb.data()!;
    assert.equal(tombData.uid, uid);
    assert.equal(tombData.expireAt.toMillis() - tombData.deletedAt.toMillis(), 7 * DAY);

    const keptGroup = (await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data() as LbGroupDoc;
    assert.deepEqual(keptGroup.memberUids, [other]);
    assert.equal(Object.prototype.hasOwnProperty.call(keptGroup.members, uid), false);
    assert.deepEqual(keptGroup.ghostUids, [other]);
    assert.deepEqual(keptGroup.ghosts.map((ghost) => ghost.uid), [other]);

    const pools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
    assert.equal(pools.size, 44);
    for (const doc of pools.docs) {
      const entries = (doc.data() as LbGhostPoolDoc).entries;
      assert.deepEqual(entries.map((entry) => entry.uid), [other], doc.id);
    }
    assert.equal((await db.collection(LB_GIFTS_COLLECTION).where('uid', '==', uid).get()).empty, true);
    assert.equal((await db.collection(LB_GIFTS_COLLECTION).where('uid', '==', other).get()).size, 1);
    assert.equal((await db.collection(LB_FLAGS_COLLECTION).where('uid', '==', uid).get()).empty, true);
    assert.equal((await db.collection(LB_FLAGS_COLLECTION).where('uid', '==', other).get()).size, 1);

    const keptBest = (await db.collection(LB_BEST_COLLECTION).doc('global').get()).data() as LbBestDoc;
    assert.deepEqual(keptBest.rows.map((row) => row.uid), [other]);
    assert.equal(keptBest.floor, 0);
    const hist = (await db.collection(LB_BEST_COLLECTION).doc('hist').get()).data()!;
    assert.deepEqual(hist.bins, { '800': 1 });

    const beforeSecond = {
      tomb: tombData,
      group: keptGroup,
      best: keptBest,
      gifts: (await db.collection(LB_GIFTS_COLLECTION).get()).size,
      flags: (await db.collection(LB_FLAGS_COLLECTION).get()).size,
    };
    const second = await callable('deleteMyData', uid, {});
    assert.equal(second.status, 200, second.text);
    assert.equal(second.json.result.ok, true);
    assert.equal(second.json.result.removed, 0);
    assert.deepEqual((await db.collection(LB_TOMB_COLLECTION).doc(uid).get()).data(), beforeSecond.tomb);
    assert.deepEqual((await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data(), beforeSecond.group);
    assert.deepEqual((await db.collection(LB_BEST_COLLECTION).doc('global').get()).data(), beforeSecond.best);
    assert.equal((await db.collection(LB_GIFTS_COLLECTION).get()).size, beforeSecond.gifts);
    assert.equal((await db.collection(LB_FLAGS_COLLECTION).get()).size, beforeSecond.flags);

    await assert.rejects(
      lbSubmitRun(db, uid, runRequest(), T0 + 1000),
      (err: any) => err.code === 'permission-denied',
    );
  });

  it('deleteBoardData is idempotent without a player and leaves a reusable tombstone', async () => {
    const uid = uniq('bd-direct');
    await deleteBoardData(db, uid, T0);
    const first = (await db.collection(LB_TOMB_COLLECTION).doc(uid).get()).data()!;
    assert.equal(first.deletedAt.toMillis(), T0);
    assert.equal(first.expireAt.toMillis(), T0 + 7 * DAY);
    await deleteBoardData(db, uid, T0 + HOUR);
    assert.deepEqual((await db.collection(LB_TOMB_COLLECTION).doc(uid).get()).data(), first);
    await assert.rejects(
      lbSubmitRun(db, uid, runRequest(), T0 + 2 * HOUR),
      (err: any) => err.code === 'permission-denied',
    );
  });

  it('decrements the histogram for a player outside the cached BEST top 50 once', async () => {
    const uid = uniq('bd-hist');
    const other = uniq('bd-hist-other');
    await seedBoardPlayer(uid, null, 'WiseOwl', 900);
    await db.collection(LB_BEST_COLLECTION).doc('global').set({
      rows: [{ uid: other, best: 800, bestAt: at(T0), name: 'OtherOwl', look: LOOK, platform: 'android', bracket: 5 }],
      floor: 800,
      updatedAt: at(T0),
    } satisfies LbBestDoc);
    await db.collection(LB_BEST_COLLECTION).doc('hist').set({
      bins: { '900': 1, '800': 1 },
      updatedAt: at(T0),
    });

    await deleteBoardData(db, uid, T0);
    assert.deepEqual((await db.collection(LB_BEST_COLLECTION).doc('hist').get()).data()!.bins, { '800': 1 });
    assert.deepEqual(
      ((await db.collection(LB_BEST_COLLECTION).doc('global').get()).data() as LbBestDoc).rows.map((row) => row.uid),
      [other],
    );

    await deleteBoardData(db, uid, T0 + HOUR);
    assert.deepEqual((await db.collection(LB_BEST_COLLECTION).doc('hist').get()).data()!.bins, { '800': 1 });
  });

  it('prunes drifted group ghost arrays by uid without dropping another player', async () => {
    const uid = uniq('bd-drift');
    const other = uniq('bd-drift-other');
    const gid = uniq('bd-drift-group');
    const groupDoc = group(gid, uid, other, 'WiseOwl');
    groupDoc.members = { [other]: groupDoc.members[other] };
    groupDoc.memberUids = [other];
    groupDoc.ghosts = [groupDoc.ghosts[1]];
    groupDoc.ghostUids = [uid, other];
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).set(groupDoc);

    await deleteBoardData(db, uid, T0);
    const kept = (await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data() as LbGroupDoc;
    assert.deepEqual(kept.ghosts.map((ghost) => ghost.uid), [other]);
    assert.deepEqual(kept.ghostUids, [other]);
    assert.deepEqual(kept.memberUids, [other]);
  });
});

describe('PRD-2.6 LB3 name hooks', () => {
  it('setVersusName updates lbPlayers, the open group and the BEST row', async () => {
    const uid = uniq('bd-name-set');
    const gid = uniq('bd-name-group');
    await auth.createUser({ uid });
    await seedBoardPlayer(uid, gid, 'OldOwl');
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).set(group(gid, uid, uniq('bd-name-other'), 'OldOwl'));
    await db.collection(LB_BEST_COLLECTION).doc('global').set({
      rows: [{ uid, best: 900, bestAt: at(T0), name: 'OldOwl', look: LOOK, platform: 'android', bracket: 5 }],
      floor: 900,
      updatedAt: at(T0),
    } satisfies LbBestDoc);

    const set = await callable('setVersusName', uid, { name: 'WiseOwl' });
    assert.equal(set.status, 200, set.text);
    assert.deepEqual(set.json.result, { ok: true, name: 'WiseOwl', updated: 0 });
    assert.equal(((await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get()).data() as LbPlayerDoc).name, 'WiseOwl');
    assert.equal(
      ((await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data() as LbGroupDoc).members[uid].name,
      'WiseOwl',
    );
    assert.equal(
      ((await db.collection(LB_BEST_COLLECTION).doc('global').get()).data() as LbBestDoc).rows[0].name,
      'WiseOwl',
    );

    const cleared = await callable('setVersusName', uid, { name: '' });
    assert.equal(cleared.status, 200, cleared.text);
    const generated = versusName('', uid);
    assert.equal(((await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get()).data() as LbPlayerDoc).name, generated);
    assert.equal(
      ((await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data() as LbGroupDoc).members[uid].name,
      generated,
    );
  });

  it('the stale-guest release updates lbPlayers and the open group', async () => {
    const uid = uniq('bd-name-guest');
    const gid = uniq('bd-name-guest-group');
    await seedBoardPlayer(uid, gid, 'GuestOwl');
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).set(group(gid, uid, uniq('bd-name-guest-other'), 'GuestOwl'));
    await setCustomName(db, uid, 'GuestOwl', T0);
    assert.equal(((await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get()).data() as LbPlayerDoc).name, 'GuestOwl');

    const released = await releaseStaleGuestNames(db, async () => false, T0 + 31 * DAY, 10);
    assert.deepEqual(released, [uid]);
    const generated = versusName('', uid);
    assert.equal(((await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get()).data() as LbPlayerDoc).name, generated);
    assert.equal(
      ((await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data() as LbGroupDoc).members[uid].name,
      generated,
    );
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).exists, false);
  });

  it('the lost-name path clears the board name with the versus name', async () => {
    const uid = uniq('bd-name-lost');
    const other = uniq('bd-name-owner');
    const gid = uniq('bd-name-lost-group');
    await seedBoardPlayer(uid, gid, 'LostOwl');
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).set(group(gid, uid, uniq('bd-name-lost-other'), 'LostOwl'));
    await setCustomName(db, uid, 'LostOwl', T0);
    await db.collection(CLAIMS_COLLECTION).doc(nameKey('LostOwl')).set({ uid: other, name: 'LostOwl', updatedAt: at(T0) });
    // Put the stale custom name back: the hook itself must be the operation under test.
    await db.collection(LB_PLAYERS_COLLECTION).doc(uid).update({ name: 'LostOwl' });
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).update({ [`members.${uid}.name`]: 'LostOwl' });

    assert.deepEqual(await getCustomName(db, uid, T0 + HOUR), { ok: true, name: '' });
    const generated = versusName('', uid);
    assert.equal(((await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get()).data() as LbPlayerDoc).name, generated);
    assert.equal(
      ((await db.collection(LB_GROUPS_COLLECTION).doc(gid).get()).data() as LbGroupDoc).members[uid].name,
      generated,
    );
    assert.equal((await db.collection(NAMES_COLLECTION).doc(uid).get()).exists, false);
  });

  it('lbSyncName is a no-op when the uid has no board data', async () => {
    const uid = uniq('bd-name-none');
    await lbSyncName(db, uid, 'NobodyOwl', T0);
    assert.equal((await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get()).exists, false);
  });
});
