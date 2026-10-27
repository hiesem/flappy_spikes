/** PRD-2.6 WP-LB board_store: Firestore transactions and emulated callables. */
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { mock } from 'node:test';
import { readFileSync } from 'node:fs';
import { logger } from 'firebase-functions/v2';
import { Query, Timestamp, type DocumentReference, type DocumentSnapshot, type Firestore, type Transaction } from 'firebase-admin/firestore';
import {
  GIFT_SHOP_ITEMS,
  lbClaimGift,
  lbGetBoard,
  lbSettleGroups,
  lbSubmitRun,
} from '../src/board_store.js';
import {
  LB_GIFTS_COLLECTION,
  LB_GHOST_POOL_COLLECTION,
  LB_GROUPS_COLLECTION,
  LB_GROUP_SIZE,
  LB_BEST_COLLECTION,
  LB_FLAGS_COLLECTION,
  LB_OPEN_COLLECTION,
  LB_MIN_LEFT_MS,
  LB_META_COLLECTION,
  NAMES_COLLECTION,
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  type LbGiftDoc,
  type LbGroupDoc,
  type LbPlayerDoc,
} from '../src/schema.js';
import { encodeDeltas, encodeEntries } from '../src/timeline.js';
import { versusName } from '../src/nickname.js';
import { deleteBoardData, writeHiddenRegistry } from '../src/board_delete.js';
import { docSize } from '../src/size.js';
import { db, fakeJwt, LOOK, PROJECT, uniq } from './helpers.js';

const HOUR = 3600 * 1000;
const T0 = Date.UTC(2026, 9, 20, 12, 0, 0);
const LB_COLLECTIONS_TO_CLEAR = [
  LB_GIFTS_COLLECTION,
  LB_GHOST_POOL_COLLECTION,
  LB_GROUPS_COLLECTION,
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  LB_BEST_COLLECTION,
  LB_FLAGS_COLLECTION,
  LB_OPEN_COLLECTION,
  NAMES_COLLECTION,
  LB_META_COLLECTION,
];

beforeEach(async function clearBoardStoreCollections() {
  if (!this.currentTest?.fullTitle().startsWith('PRD-2.6 LB3')) return;
  for (const name of LB_COLLECTIONS_TO_CLEAR) await db.recursiveDelete(db.collection(name));
});

function submitRun(o: {
  id?: string;
  score?: number;
  hoops?: number;
  endTs?: number;
  cs?: number;
  timeline?: boolean;
} = {}) {
  const score = o.score ?? 120;
  const hoops = o.hoops ?? score;
  const endTs = o.endTs ?? T0;
  const cs = o.cs ?? Math.max(1400, score * 140 + 80);
  const deltas = Array.from({ length: score }, () => 140);
  return {
    id: o.id ?? uniq('lb-run'),
    score,
    hoops,
    cs,
    endTs,
    mode: 'free',
    ...(o.timeline === false
      ? {}
      : {
          tl: encodeDeltas(deltas),
          fl: encodeEntries(deltas.map(() => 0), deltas.map(() => 1)),
        }),
  };
}

function request(runs: unknown[], extra: Record<string, unknown> = {}) {
  return { runs, name: 'BraveOwl123', look: LOOK, platform: 'android', ...extra };
}

async function player(uid: string): Promise<LbPlayerDoc | undefined> {
  const snap = await db.collection(LB_PLAYERS_COLLECTION).doc(uid).get();
  return snap.exists ? (snap.data() as LbPlayerDoc) : undefined;
}

async function group(gid: string): Promise<LbGroupDoc | undefined> {
  const snap = await db.collection(LB_GROUPS_COLLECTION).doc(gid).get();
  return snap.exists ? (snap.data() as LbGroupDoc) : undefined;
}

async function gifts(uid: string): Promise<LbGiftDoc[]> {
  return (await db.collection(LB_GIFTS_COLLECTION).where('uid', '==', uid).get()).docs.map((d) => d.data() as LbGiftDoc);
}

/** Run [after] once, after the next completed transaction (used for races). */
function dbWithAfterTransaction(after: () => Promise<void>): Firestore {
  let ran = false;
  return new Proxy(db, {
    get(target, property) {
      if (property !== 'runTransaction') {
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      }
      const runTransaction = Reflect.get(target, property, target) as (...args: any[]) => any;
      return async (...args: any[]) => {
        const result = await runTransaction.apply(target, args);
        if (!ran) {
          ran = true;
          await after();
        }
        return result;
      };
    },
  }) as Firestore;
}

/** Replays a group snapshot from before cleanup while every later read is fresh. */
function dbWithStaleGroupSnapshot(
  gid: string,
  staleGroup: DocumentSnapshot,
  afterGroupRead?: () => Promise<void>,
): Firestore {
  const groupPath = `${LB_GROUPS_COLLECTION}/${gid}`;
  return new Proxy(db, {
    get(target, property) {
      if (property === 'runTransaction') {
        return async (callback: (tx: Transaction) => Promise<unknown>) => callback({
          async get(ref: DocumentReference) {
            if (ref.path === groupPath) {
              if (afterGroupRead) await afterGroupRead();
              return staleGroup;
            }
            return target.collection(ref.parent.id).doc(ref.id).get();
          },
        } as unknown as Transaction);
      }
      const value = Reflect.get(target, property, target);
      if (property !== 'collection' || typeof value !== 'function') {
        return typeof value === 'function' ? value.bind(target) : value;
      }
      return (name: string) => {
        const collection = value.call(target, name);
        if (name !== LB_GROUPS_COLLECTION) return collection;
        return new Proxy(collection, {
          get(collectionTarget, collectionProperty) {
            const collectionValue = Reflect.get(collectionTarget, collectionProperty, collectionTarget);
            if (collectionProperty !== 'doc' || typeof collectionValue !== 'function') {
              return typeof collectionValue === 'function' ? collectionValue.bind(collectionTarget) : collectionValue;
            }
            return (...args: unknown[]) => {
              const ref = collectionValue.apply(collectionTarget, args as [string?]) as DocumentReference;
              if (ref.path !== groupPath) return ref;
              return new Proxy(ref, {
                get(refTarget, refProperty) {
                  const refValue = Reflect.get(refTarget, refProperty, refTarget);
                  if (refProperty === 'get' && typeof refValue === 'function') return () => staleGroup;
                  return typeof refValue === 'function' ? refValue.bind(refTarget) : refValue;
                },
              });
            };
          },
        });
      };
    },
  }) as Firestore;
}

describe('PRD-2.6 LB3 submit, join and group placement', () => {
  it('creates the first group with back-dated start within 6 h and no own ghost', async () => {
    const uid = uniq('lb-create');
    const result = await lbSubmitRun(db, uid, request([submitRun({ score: 130, endTs: T0 - 2 * HOUR })]), T0);
    assert.equal(result.accepted.length, 1);
    assert.equal(result.dropped.length, 0);
    assert.ok(result.group);
    const gid = result.group!.id;
    assert.match(gid, /^\d+_/);
    const g = await group(gid);
    assert.ok(g);
    assert.equal(g!.memberUids[0], uid);
    assert.ok(g!.start.toMillis() >= T0 - 6 * HOUR);
    assert.ok(g!.start.toMillis() <= T0);
    assert.ok(g!.ghostUids.every((u) => u !== uid));
    const p = await player(uid);
    assert.equal(p?.groupId, gid);
    assert.equal(p?.src, 'play');
    assert.equal(p?.hidden, false);
  });

  it('a second real player joins the open group in the same day', async () => {
    const a = uniq('lb-a');
    const b = uniq('lb-b');
    const ra = await lbSubmitRun(db, a, request([submitRun({ score: 40, endTs: T0 })]), T0 + 1000);
    const gid = ra.group!.id;
    const rb = await lbSubmitRun(db, b, request([submitRun({ score: 35, endTs: T0 + 2000 })]), T0 + 3000);
    assert.equal(rb.group?.id, gid);
    const g = await group(gid);
    assert.deepEqual(new Set(g!.memberUids), new Set([a, b]));
    assert.equal(g!.memberUids.length, 2);
  });

  it('opens a fresh group instead of joining when less than 3 h remain', async () => {
    const a = uniq('lb-old-a');
    const b = uniq('lb-old-b');
    const ra = await lbSubmitRun(db, a, request([submitRun({ score: 65, endTs: T0 })]), T0 + 1000);
    const oldGid = ra.group!.id;
    const late = T0 + 24 * HOUR - LB_MIN_LEFT_MS + 1;
    const rb = await lbSubmitRun(db, b, request([submitRun({ score: 60, endTs: late })]), late + 1000);
    assert.ok(rb.group);
    assert.notEqual(rb.group!.id, oldGid);
    const fresh = await group(rb.group!.id);
    assert.ok(fresh!.end.toMillis() - (late + 1000) >= LB_MIN_LEFT_MS);
  });

  it('keeps the group at most LB_GROUP_SIZE real members', async () => {
    const first = uniq('lb-full-first');
    const r0 = await lbSubmitRun(db, first, request([submitRun({ score: 2000, endTs: T0 })]), T0 + 1000);
    const gid = r0.group!.id;
    const g0 = await group(gid);
    const members = [...g0!.memberUids];
    for (let i = members.length; i < LB_GROUP_SIZE; i++) members.push(uniq(`lb-fill-${i}`));
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).update({
      memberUids: members,
      members: Object.fromEntries(members.map((uid, i) => [uid, {
        t: 10 + i,
        b: 10,
        n: 1,
        last: Timestamp.fromMillis(T0),
        name: 'SwiftKiwi482',
        look: LOOK,
        platform: 'android',
      }])),
    });
    const extra = uniq('lb-full-extra');
    const r = await lbSubmitRun(db, extra, request([submitRun({ score: 2000, endTs: T0 + 2000 })]), T0 + 3000);
    assert.ok(r.group);
    assert.notEqual(r.group!.id, gid);
  });

  it('a t:1 submit is stored hidden and absent from boards, ghosts and prizes', async () => {
    const uid = uniq('lb-hidden');
    const r = await lbSubmitRun(db, uid, request([submitRun({ score: 900, endTs: T0 })], { t: 1 }), T0 + 1000);
    assert.equal(r.accepted.length, 1);
    assert.equal(r.group, null);
    const p = await player(uid);
    assert.equal(p?.hidden, true);
    assert.equal(p?.groupId, null);
    const board = await lbGetBoard(db, uid, { tab: 'today' }, T0 + 5000);
    assert.equal(board.today.rows.length, 0);
    assert.equal(board.best.rows.some((row) => row.points === 900), false);
    const ghostPools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
    assert.equal(ghostPools.docs.some((d) => (d.data().entries as any[]).some((e) => e.uid === uid)), false);
    const settled = await lbSettleGroups(db, T0 + 30 * HOUR);
    assert.equal(settled.groups, 0);
    assert.equal((await gifts(uid)).length, 0);
  });
});

describe('PRD-2.6 LB3 settlement and gifts', () => {
  it('submit then settle writes each podium gift once; repeat settlement changes nothing', async () => {
    const a = uniq('lb-gold');
    const b = uniq('lb-silver');
    const c = uniq('lb-bronze');
    const t = T0;
    const ra = await lbSubmitRun(db, a, request([submitRun({ score: 1200, endTs: t })]), t + 1000);
    const gid = ra.group!.id;
    await lbSubmitRun(db, b, request([submitRun({ score: 1100, endTs: t + 1000 })]), t + 2000);
    await lbSubmitRun(db, c, request([submitRun({ score: 1000, endTs: t + 2000 })]), t + 3000);
    const end = (await group(gid))!.end.toMillis();
    const first = await lbSettleGroups(db, end + 1000, gid);
    assert.equal(first.groups, 1);
    assert.equal(first.gifts, 3);
    const ga = await gifts(a);
    const gb = await gifts(b);
    const gc = await gifts(c);
    assert.deepEqual(ga.map((g) => g.tier), ['gold']);
    assert.deepEqual(gb.map((g) => g.tier), ['silver']);
    assert.deepEqual(gc.map((g) => g.tier), ['bronze']);
    const before = await db.collection(LB_GIFTS_COLLECTION).get();
    const second = await lbSettleGroups(db, end + 2000, gid);
    assert.equal(second.groups, 0);
    assert.equal(second.gifts, 0);
    const after = await db.collection(LB_GIFTS_COLLECTION).get();
    assert.equal(after.size, before.size);
    assert.equal((await group(gid))?.settled, true);
    for (const g of [...ga, ...gb, ...gc]) assert.equal(g.claimedAt, undefined);
  });

  it('lazy lbGetBoard settlement equals the scheduled settlement and records TOP BIRD', async () => {
    const lazy = uniq('lb-lazy');
    const sched = uniq('lb-sched');
    const lazyRun = await lbSubmitRun(db, lazy, request([submitRun({ score: 700, endTs: T0 })]), T0 + 1000);
    const scheduledRun = await lbSubmitRun(db, sched, request([submitRun({ score: 900, endTs: T0 + 5 * HOUR })]), T0 + 5 * HOUR + 1000);
    const lazyGid = lazyRun.group!.id;
    const schedGid = scheduledRun.group!.id;
    assert.notEqual(lazyGid, schedGid);
    const lazyEnd = (await group(lazyGid))!.end.toMillis();
    const schedEnd = (await group(schedGid))!.end.toMillis();
    const now = Math.max(lazyEnd, schedEnd) + 1000;
    await lbGetBoard(db, lazy, { tab: 'today' }, now);
    await lbSettleGroups(db, now, schedGid);
    const lg = await group(lazyGid);
    const sg = await group(schedGid);
    assert.equal(lg?.settled, true);
    assert.equal(sg?.settled, true);
    assert.equal((await gifts(lazy))[0]?.tier, 'gold');
    assert.equal((await gifts(sched))[0]?.tier, 'gold');
    assert.equal(((await player(lazy)) as any)?.topBird, true);
    assert.equal(((await player(sched)) as any)?.topBird, true);
  });

  it('writes ghost days into shards capped at 200 entries / 900 KB', async () => {
    const uid = uniq('lb-ghost');
    const r = await lbSubmitRun(db, uid, request([submitRun({ score: 800, endTs: T0 })]), T0 + 1000);
    const gid = r.group!.id;
    const end = (await group(gid))!.end.toMillis();
    await lbSettleGroups(db, end + 1000, gid);
    const pools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
    const entries = pools.docs.flatMap((d) => (d.data() as any).entries as any[]);
    const mine = entries.find((e) => e.uid === uid);
    assert.ok(mine);
    assert.equal(mine!.runs.length <= 48, true);
    for (const doc of pools.docs) assert.ok(((doc.data() as any).entries as any[]).length <= 200);
  });

  it('a hidden member on the podium leaves that prize to nobody', async () => {
    const real = uniq('lb-real-podium');
    const hidden = uniq('lb-hidden-podium');
    const rr = await lbSubmitRun(db, real, request([submitRun({ score: 900, endTs: T0 })]), T0 + 1000);
    const gid = rr.group!.id;
    await lbSubmitRun(db, hidden, request([submitRun({ score: 1900, endTs: T0 + 1000 })], { t: 1 }), T0 + 2000);
    // Force the hidden tester into the group so the O65 place-keeping rule is
    // exercised; a real hidden submission never joins by itself.
    const g = (await group(gid))!;
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).update({
      memberUids: [...g.memberUids, hidden],
      members: {
        ...g.members,
        [hidden]: { t: 1900, b: 1900, n: 1, last: Timestamp.fromMillis(T0), name: 'Hidden', look: LOOK, platform: 'android' },
      },
    });
    const end = g.end.toMillis();
    const settled = await lbSettleGroups(db, end + 1000, gid);
    assert.equal(settled.groups, 1);
    assert.equal((await group(gid))?.settled, true);
    assert.equal((await gifts(hidden)).length, 0);
    const realGifts = await gifts(real);
    assert.equal(realGifts.length, 1);
    assert.equal(realGifts[0]?.tier, 'silver');
    assert.equal(realGifts[0]?.boardRank, 2);
  });
});

describe('PRD-2.6 LB3 claim, tombstone and response shapes', () => {
  it('claims a gift once and returns the same stored roll on repeat', async () => {
    const uid = uniq('lb-claim');
    const r = await lbSubmitRun(db, uid, request([submitRun({ score: 1300, endTs: T0 })]), T0 + 1000);
    const gid = r.group!.id;
    const end = (await group(gid))!.end.toMillis();
    await lbSettleGroups(db, end + 1000, gid);
    const gift = (await gifts(uid))[0];
    assert.ok(gift);
    const first = await lbClaimGift(db, uid, { id: gift!.gid }, end + 2000);
    const second = await lbClaimGift(db, uid, { id: gift!.gid }, end + 3000);
    assert.equal(first.ok, true);
    assert.equal(second.ok, true);
    assert.deepEqual(first.prize, second.prize);
    assert.equal(first.tier, 'gold');
    const other = uniq('lb-claim-other');
    const refused = await lbClaimGift(db, other, { id: gift!.gid }, end + 4000);
    assert.equal(refused.ok, false);
    assert.equal((await gifts(uid))[0].claimedAt !== undefined, true);
  });

  it('refuses a tombstoned uid submit', async () => {
    const uid = uniq('lb-tomb');
    await db.collection(LB_TOMB_COLLECTION).doc(uid).set({
      uid,
      deletedAt: Timestamp.fromMillis(T0),
      expireAt: Timestamp.fromMillis(T0 + 7 * 24 * HOUR),
    });
    await assert.rejects(
      lbSubmitRun(db, uid, request([submitRun({ endTs: T0 })]), T0 + 1000),
      (err: any) => err.code === 'permission-denied',
    );
    assert.equal(await player(uid), undefined);
  });

  it('TODAY rows carry no uid and no ghost marker; BEST returns 50 + exact caller rank', async () => {
    const owner = uniq('lb-board-owner');
    const r = await lbSubmitRun(db, owner, request([submitRun({ score: 333, endTs: T0 })]), T0 + 1000);
    assert.ok(r.board);
    assert.equal(r.board!.rows.every((row) => typeof row.rid === 'string'), true);
    assert.equal(JSON.stringify(r.board!.rows).includes(owner), false);
    assert.equal(JSON.stringify(r.board!.rows).includes('ghost'), false);
    const board = await lbGetBoard(db, owner, { tab: 'today' }, T0 + 2000);
    assert.equal(board.today.rows.every((row) => Object.keys(row).includes('best') === false), true);
    const best = await lbGetBoard(db, owner, { tab: 'best' }, T0 + 3000);
    assert.ok(best.best.rows.length <= 50);
    assert.ok(best.best.me);
    assert.equal(best.best.me!.rank, 1);
    assert.equal(best.best.me!.points >= 333, true);
  });

  it('duplicate run ids are dropped idempotently', async () => {
    const uid = uniq('lb-dup');
    const run = submitRun({ score: 210, endTs: T0 });
    const first = await lbSubmitRun(db, uid, request([run]), T0 + 1000);
    assert.equal(first.accepted.length, 1);
    assert.equal(first.accepted[0], run.id);
    const second = await lbSubmitRun(db, uid, request([run]), T0 + 2000);
    assert.equal(second.accepted.length, 0);
    assert.equal(second.dropped[0].reason, 'duplicate');
  });

  it('uses custom versusNames, never a platform name', async () => {
    const uid = uniq('lb-name');
    await db.collection('versusNames').doc(uid).set({
      customName: 'BraveLark',
      updatedAt: Timestamp.fromMillis(T0),
    });
    const r = await lbSubmitRun(db, uid, request([submitRun({ score: 75, endTs: T0 })], { name: 'Dev Platform Name' }), T0 + 1000);
    assert.equal(r.board?.rows.some((row) => row.name === 'BraveLark'), true);
    assert.equal((await player(uid))?.name, 'BraveLark');
  });

  it('emulated callables accept an anonymous App Check user and expose the PRD shapes', async () => {
    const uid = uniq('lb-callable');
    const base = `http://127.0.0.1:5001/${PROJECT}/europe-west1`;
    const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });
    const token = fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
    const headers = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Firebase-AppCheck': appCheck,
    };
    const call = async (name: string, body: unknown) => {
      const res = await fetch(`${base}/${name}`, { method: 'POST', headers, body: JSON.stringify({ data: body }) });
      assert.equal(res.status, 200, `${name}: ${await res.clone().text()}`);
      return (await res.json()) as { result: any };
    };
    const submit = await call('lbSubmitRun', request([submitRun({ score: 111, endTs: Date.now() - 1000 })]));
    assert.ok(Array.isArray(submit.result.accepted));
    assert.ok(Array.isArray(submit.result.dropped));
    const board = await call('lbGetBoard', { tab: 'today' });
    assert.equal(board.result.today.tab, 'today');
    assert.equal(board.result.best.tab, 'best');
    assert.equal('bestAllTime' in board.result, true);
    const claim = await call('lbClaimGift', { id: 'not-a-gift' });
    assert.equal(claim.result.ok, false);
  });
});


describe('PRD-2.6 LB3 regression fixes', () => {
  it('starts fresh totals and history in the next group and preserves TOP BIRD', async () => {
    for (const lazy of [false, true]) {
      const uid = uniq('lb-next-day');
      const start = T0 + (lazy ? 72 * HOUR : 0);
      const first = await lbSubmitRun(db, uid, request([submitRun({ score: 40, endTs: start })]), start + 1000);
      await db.collection(LB_GROUPS_COLLECTION).doc(first.group!.id).update({ ghosts: [], ghostUids: [] });
      const old = (await group(first.group!.id))!;
      const end = old.end.toMillis();
      if (!lazy) await lbSettleGroups(db, end + 1000, first.group!.id);
      const next = await lbSubmitRun(db, uid, request([submitRun({ score: 15, endTs: end + HOUR })]), end + HOUR + 1000);
      assert.notEqual(next.group!.id, first.group!.id);
      const member = (await group(next.group!.id))!.members[uid] as any;
      assert.equal(member.t, 15);
      assert.equal(member.b, 15);
      assert.equal(member.n, 1);
      assert.equal(member.runs.length, 1);
      assert.equal(member.runs[0].s, 15);
      const p = await player(uid) as any;
      assert.equal(p.topBird, true);
      assert.equal(p.topBirdAt.toMillis(), end);
      assert.equal(p.bestShadow, 40);
    }
  });

  it('removes a newly hidden player from cached BEST and the histogram and refills place 50', async () => {
    const uid = uniq('lb-was-visible');
    await lbSubmitRun(db, uid, request([submitRun({ score: 130 })]), T0 + 1000);
    const template = (await player(uid))!;
    // 50 lower public scores: hiding the leader must promote the old #51.
    const batch = db.batch();
    for (let i = 1; i <= 50; i++) {
      batch.set(db.collection(LB_PLAYERS_COLLECTION).doc(`rank-${i}`), {
        ...template, name: `Rank${i}`, best: 130 - i, bestShadow: 130 - i,
      });
    }
    await batch.commit();
    const viewer = uniq('lb-viewer');
    assert.equal((await lbGetBoard(db, viewer, { tab: 'best' }, T0 + HOUR + 500)).best.rows[0].points, 130);
    await lbSubmitRun(db, uid, request([submitRun({ score: 15, endTs: T0 + HOUR })], { t: 1 }), T0 + HOUR + 1000);
    const board = (await lbGetBoard(db, viewer, { tab: 'best' }, T0 + HOUR + 2000)).best;
    assert.equal(board.rows.length, 50);
    assert.equal(board.rows[0].points, 129);
    assert.equal(board.rows[49].points, 80);
    const hist = (await db.collection(LB_BEST_COLLECTION).doc('hist').get()).data()!;
    assert.equal(hist.bins['100'], undefined);
    assert.equal((await group(template.groupId!))!.memberUids.includes(uid), false);
  });

  it('removes a player turned hidden from every embedded ghost and pool after settlement', async () => {
    const vanished = uniq('lb-hidden-after-settle');
    const peer = uniq('lb-hidden-peer');
    const picked = uniq('lb-hidden-picked');
    for (const [uid, name] of [[vanished, 'HiddenOwl'], [peer, 'PeerOwl'], [picked, 'PickedOwl']]) {
      await db.collection(NAMES_COLLECTION).doc(uid).set({ customName: name, updatedAt: Timestamp.fromMillis(T0) });
    }
    const first = await lbSubmitRun(db, vanished, request([submitRun({ score: 900, endTs: T0 })]), T0 + 1000);
    const firstGid = first.group!.id;
    await lbSubmitRun(db, peer, request([submitRun({ score: 800, endTs: T0 + 1000 })]), T0 + 2000);
    const end = (await group(firstGid))!.end.toMillis();
    await lbSettleGroups(db, end + 1000, firstGid);

    const pools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
    assert.equal(
      pools.docs.some((doc) => (doc.data().entries as any[]).some((entry) => entry.uid === vanished)),
      true,
    );

    // A later group selects the vanished player's earlier day as a ghost.
    const nextStart = end + HOUR;
    const next = await lbSubmitRun(db, picked, request([submitRun({ score: 700, endTs: nextStart })]), nextStart + 1000);
    const nextGid = next.group!.id;
    const nextGroup = (await group(nextGid))!;
    assert.equal(nextGroup.ghosts.some((ghost) => ghost.uid === vanished), true);
    const beforeHide = (await lbGetBoard(db, picked, { tab: 'today' }, nextStart + 1500)).today;
    assert.equal(beforeHide.rows.some((row) => row.name === 'HiddenOwl'), true);

    await lbSubmitRun(db, vanished, request([submitRun({ score: 10, endTs: nextStart + 1000 })], { t: 1 }), nextStart + 2000);

    const hiddenGroup = (await group(nextGid))!;
    assert.equal(hiddenGroup.memberUids.includes(vanished), false);
    assert.equal(hiddenGroup.ghostUids.includes(vanished), false);
    assert.equal(hiddenGroup.ghosts.some((ghost) => ghost.uid === vanished), false);
    const afterPools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
    assert.equal(
      afterPools.docs.some((doc) => (doc.data().entries as any[]).some((entry) => entry.uid === vanished)),
      false,
    );

    const today = (await lbGetBoard(db, picked, { tab: 'today' }, nextStart + 3000)).today;
    assert.equal(today.rows.some((row) => row.name === 'HiddenOwl'), false);
    assert.equal(today.rows.length, beforeHide.rows.length - 1);
    assert.equal(today.me!.points, 700);

    const settleEnd = hiddenGroup.end.toMillis();
    await lbSettleGroups(db, settleEnd + 1000, nextGid);
    assert.equal((await gifts(vanished)).some((gift) => gift.gid === nextGid), false);
    assert.deepEqual((await gifts(picked)).filter((gift) => gift.gid === nextGid).map((gift) => gift.tier), ['silver']);
  });

  it('excludes a hidden ghost raced into settlement before the cleanup sweep', async () => {
    const vanished = uniq('lb-race-hidden');
    const peer = uniq('lb-race-peer');
    const picked = uniq('lb-race-picked');
    for (const [uid, name] of [[vanished, 'GhostOwl'], [peer, 'PeerOwl'], [picked, 'PickedOwl']]) {
      await db.collection(NAMES_COLLECTION).doc(uid).set({ customName: name, updatedAt: Timestamp.fromMillis(T0) });
    }
    const source = await lbSubmitRun(db, vanished, request([submitRun({ score: 900, endTs: T0 })]), T0 + 1000);
    const sourceGid = source.group!.id;
    await lbSubmitRun(db, peer, request([submitRun({ score: 800, endTs: T0 + 1000 })]), T0 + 2000);
    const sourceEnd = (await group(sourceGid))!.end.toMillis();
    await lbSettleGroups(db, sourceEnd + 1000, sourceGid);

    // A later group embeds the earlier day as a ghost. The owner then hides:
    // its player doc commits hidden before the cleanup can strip this group.
    const nextStart = sourceEnd + HOUR;
    const next = await lbSubmitRun(db, picked, request([submitRun({ score: 700, endTs: nextStart })]), nextStart + 1000);
    const nextGid = next.group!.id;
    const nextGroup = (await group(nextGid))!;
    assert.equal(nextGroup.ghosts.some((ghost) => ghost.uid === vanished), true);

    let settledRace = false;
    let raceBoard: Awaited<ReturnType<typeof lbGetBoard>>['today'] | null = null;
    const racingDb = dbWithAfterTransaction(async () => {
      if (settledRace) return;
      const live = (await group(nextGid))!;
      if (!live.ghosts.some((ghost) => ghost.uid === vanished)) return;
      settledRace = true;
      const end = live.end.toMillis();
      await lbSettleGroups(db, end + 1000, nextGid);
      raceBoard = (await lbGetBoard(db, picked, { tab: 'today' }, end + 2000)).today;
    });
    await lbSubmitRun(
      racingDb,
      vanished,
      request([submitRun({ score: 10, endTs: nextStart + 2000 })], { t: 1 }),
      nextStart + 2000,
    );
    assert.equal(settledRace, true, 'settlement ran between the hidden commit and the cleanup sweep');
    const settledBoard = raceBoard as Awaited<ReturnType<typeof lbGetBoard>>['today'] | null;
    assert.ok(settledBoard);
    assert.equal(settledBoard!.rows.some((row) => row.name === 'GhostOwl'), false);

    const settledGroup = (await group(nextGid))!;
    assert.equal(settledGroup.settled, true);
    assert.equal((await gifts(vanished)).some((gift) => gift.gid === nextGid), false);
    assert.deepEqual((await gifts(picked)).filter((gift) => gift.gid === nextGid).map((gift) => gift.tier), ['silver']);
  });

  it('leaves a hidden ghost out of a submit response raced in before the cleanup sweep', async () => {
    const vanished = uniq('lb-race-submit-hidden');
    const peer = uniq('lb-race-submit-peer');
    const picked = uniq('lb-race-submit-picked');
    const viewer = uniq('lb-race-submit-viewer');
    for (const [uid, name] of [[vanished, 'GhostOwl'], [peer, 'PeerOwl'], [picked, 'PickedOwl'], [viewer, 'ViewerOwl']]) {
      await db.collection(NAMES_COLLECTION).doc(uid).set({ customName: name, updatedAt: Timestamp.fromMillis(T0) });
    }
    const source = await lbSubmitRun(db, vanished, request([submitRun({ score: 900, endTs: T0 })]), T0 + 1000);
    const sourceGid = source.group!.id;
    await lbSubmitRun(db, peer, request([submitRun({ score: 800, endTs: T0 + 1000 })]), T0 + 2000);
    const sourceEnd = (await group(sourceGid))!.end.toMillis();
    await lbSettleGroups(db, sourceEnd + 1000, sourceGid);

    const nextStart = sourceEnd + HOUR;
    const next = await lbSubmitRun(db, picked, request([submitRun({ score: 700, endTs: nextStart })]), nextStart + 1000);
    const nextGid = next.group!.id;
    assert.equal((await group(nextGid))!.ghosts.some((ghost) => ghost.uid === vanished), true);

    let flaggedDuringSweep = false;
    let during: Awaited<ReturnType<typeof lbSubmitRun>> | null = null;
    const racingDb = dbWithAfterTransaction(async () => {
      if (!(await group(nextGid))!.ghosts.some((ghost) => ghost.uid === vanished)) return;
      flaggedDuringSweep = (await db.collection(LB_PLAYERS_COLLECTION).doc(vanished).get()).data()?.cleanupPending === true;
      during = await lbSubmitRun(db, viewer, request([submitRun({ score: 700, endTs: nextStart + 3000 })]), nextStart + 3000);
    });
    await lbSubmitRun(
      racingDb,
      vanished,
      request([submitRun({ score: 10, endTs: nextStart + 2000 })], { t: 1 }),
      nextStart + 2000,
    );

    assert.equal(flaggedDuringSweep, true, 'the hide committed the cleanup marker while the ghost was still embedded');
    const response = during as Awaited<ReturnType<typeof lbSubmitRun>> | null;
    assert.ok(response);
    assert.equal(response!.group?.id, nextGid);
    assert.equal(response!.board!.rows.some((row) => row.name === 'GhostOwl'), false);
    assert.equal(response!.rank!.after, response!.board!.me!.rank);
    assert.equal((await db.collection(LB_PLAYERS_COLLECTION).doc(vanished).get()).data()?.cleanupPending, false);
    assert.equal((await group(nextGid))!.ghosts.some((ghost) => ghost.uid === vanished), false);
  });

  it('checks ghost owners again when a stale TODAY group outlives its cleanup marker', async () => {
    const vanished = uniq('lb-stale-read-hidden');
    const picked = uniq('lb-stale-read-picked');
    for (const [uid, name] of [[vanished, 'GhostOwl'], [picked, 'PickedOwl']]) {
      await db.collection(NAMES_COLLECTION).doc(uid).set({ customName: name, updatedAt: Timestamp.fromMillis(T0) });
    }

    const source = await lbSubmitRun(db, vanished, request([submitRun({ score: 900, endTs: T0 })]), T0 + 1000);
    const sourceEnd = (await group(source.group!.id))!.end.toMillis();
    await lbSettleGroups(db, sourceEnd + 1000, source.group!.id);
    const nextStart = sourceEnd + HOUR;
    const next = await lbSubmitRun(db, picked, request([submitRun({ score: 700, endTs: nextStart })]), nextStart + 1000);
    const nextGid = next.group!.id;
    assert.equal((await group(nextGid))!.ghosts.some((ghost) => ghost.uid === vanished), true);

    let staleGroup: DocumentSnapshot | null = null;
    let boardPromise: ReturnType<typeof lbGetBoard> | null = null;
    let cleanupClearedBetweenReads = false;
    const racingDb = dbWithAfterTransaction(async () => {
      if (!(await group(nextGid))!.ghosts.some((ghost) => ghost.uid === vanished)) return;
      staleGroup = await db.collection(LB_GROUPS_COLLECTION).doc(nextGid).get();
      boardPromise = lbGetBoard(
        dbWithStaleGroupSnapshot(nextGid, staleGroup, async () => {
          for (let attempt = 0; attempt < 200; attempt++) {
            if ((await db.collection(LB_PLAYERS_COLLECTION).doc(vanished).get()).data()?.cleanupPending !== true) {
              cleanupClearedBetweenReads = true;
              return;
            }
            await new Promise((resolve) => setTimeout(resolve, 10));
          }
          throw new Error('cleanup did not finish between the group and eligibility reads');
        }),
        picked,
        { tab: 'today' },
        nextStart + 3000,
      );
    });
    await lbSubmitRun(
      racingDb,
      vanished,
      request([submitRun({ score: 10, endTs: nextStart + 2000 })], { t: 1 }),
      nextStart + 2000,
    );

    assert.ok(staleGroup, 'captured the stale group after hidden committed but before cleanup');
    assert.ok(boardPromise, 'started the board read before cleanup could run');
    const board = (await boardPromise as Awaited<ReturnType<typeof lbGetBoard>>).today;
    assert.equal(cleanupClearedBetweenReads, true, 'cleanup cleared the marker between the group and eligibility reads');
    assert.equal(board.rows.some((row) => row.name === 'GhostOwl'), false);
    assert.equal((await db.collection(LB_PLAYERS_COLLECTION).doc(vanished).get()).data()?.cleanupPending, false);
    assert.equal((await group(nextGid))!.ghosts.some((ghost) => ghost.uid === vanished), false);
  });

  it('keeps tie timestamps public and accepts a verified improvement below a private anomaly', async () => {
    const a = uniq('lb-tie-first');
    const b = uniq('lb-tie-second');
    await lbSubmitRun(db, a, request([submitRun({ score: 100 })]), T0 + 1000);
    await lbSubmitRun(db, b, request([submitRun({ score: 100, endTs: T0 + HOUR })]), T0 + HOUR + 1000);
    const anomaly = submitRun({ score: 200, endTs: T0 + 2 * HOUR });
    // Valid bounds/gaps, but a median pace below 1.35 s is a hard anomaly.
    anomaly.tl = encodeDeltas(Array(200).fill(100));
    await lbSubmitRun(db, a, request([anomaly]), T0 + 2 * HOUR + 1000);
    assert.equal((await player(a))!.best, 200);
    assert.equal((await player(a))!.bestShadow, 100);
    assert.equal((await player(a))!.bestAt.toMillis(), T0);
    const board = await lbGetBoard(db, a, { tab: 'best' }, T0 + 2 * HOUR + 2000);
    assert.equal(board.best.me!.rank, 1);
    assert.equal(board.best.rows[0].rid, board.best.me!.rid);
    await lbSubmitRun(db, a, request([submitRun({ score: 150, endTs: T0 + 3 * HOUR })]), T0 + 3 * HOUR + 1000);
    const p = (await player(a))!;
    assert.equal(p.best, 200);
    assert.equal(p.bestShadow, 150);
    assert.equal(p.bestAt.toMillis(), T0 + 3 * HOUR);
    assert.equal((await lbGetBoard(db, b, { tab: 'best' }, T0 + 3 * HOUR + 2000)).best.rows[0].points, 150);
  });

  it('shows the owner their private anomaly best but keeps public rows and rank verified', async () => {
    const owner = uniq('lb-private-owner');
    const other = uniq('lb-private-other');
    await lbSubmitRun(db, owner, request([submitRun({ score: 100, endTs: T0 })]), T0 + 1000);
    await lbSubmitRun(db, other, request([submitRun({ score: 90, endTs: T0 + 1000 })]), T0 + 2000);
    const anomaly = submitRun({ score: 200, endTs: T0 + HOUR });
    anomaly.tl = encodeDeltas(Array(200).fill(100));
    await lbSubmitRun(db, owner, request([anomaly]), T0 + HOUR + 1000);

    const own = (await lbGetBoard(db, owner, { tab: 'best' }, T0 + HOUR + 2000)).best;
    assert.equal(own.me!.points, 200);
    assert.equal(own.me!.best, 200);
    assert.equal(own.me!.rank, 1);
    assert.equal(own.rows.find((row) => row.rid === own.me!.rid)!.points, 100);

    const publicView = (await lbGetBoard(db, other, { tab: 'best' }, T0 + HOUR + 2000)).best;
    assert.equal(publicView.rows[0].points, 100);
    assert.equal(publicView.rows[0].name, versusName('BraveOwl123', owner));
    assert.equal(publicView.me!.points, 90);
    assert.equal(publicView.me!.rank, 2);
  });

  it('pins a first-ever hard anomaly for its owner without publishing a row', async () => {
    const owner = uniq('lb-private-only-owner');
    const other = uniq('lb-private-only-other');
    const anomaly = submitRun({ score: 200, endTs: T0 });
    anomaly.tl = encodeDeltas(Array(200).fill(100));
    await lbSubmitRun(db, owner, request([anomaly]), T0 + 1000);

    const stored = (await player(owner))!;
    assert.equal(stored.best, 200);
    assert.equal(stored.bestShadow, 0);

    const own = (await lbGetBoard(db, owner, { tab: 'best' }, T0 + 2000)).best;
    assert.equal(own.rows.some((row) => row.points === 200), false);
    assert.ok(own.me);
    assert.equal(own.me!.points, 200);
    assert.equal(own.me!.best, 200);
    assert.equal(own.me!.rank, 0);
    assert.equal(own.me!.lastAt, T0);
    assert.equal(own.floor ?? 0, 0);

    await lbSubmitRun(db, other, request([submitRun({ score: 10, endTs: T0 + 3000 })]), T0 + 4000);
    const publicView = (await lbGetBoard(db, other, { tab: 'best' }, T0 + 5000)).best;
    assert.equal(publicView.rows.some((row) => row.points === 200), false);
    assert.equal(publicView.me!.points, 10);
    assert.equal((await lbGetBoard(db, owner, { tab: 'best' }, T0 + 5000)).best.me!.points, 200);
  });

  it('persists timestamps and history from the accepted duplicate run, not a malformed namesake', async () => {
    const uid = uniq('lb-duplicate-order');
    const id = uniq('lb-duplicate-order-run');
    const accepted = submitRun({ id, score: 60, endTs: T0 });
    const malformed = { ...submitRun({ id, score: 300, endTs: T0 + 2 * HOUR }), cs: 'broken' };
    const result = await lbSubmitRun(db, uid, request([accepted, malformed, submitRun({ score: 5, endTs: T0 - HOUR })]), T0 + 1000);
    assert.deepEqual(result.dropped, [{ id: '', reason: 'shape' }]);

    const p = (await player(uid))!;
    assert.deepEqual(p.hist, [5, 60]);
    const member = (await group(result.group!.id))!.members[uid] as any;
    assert.equal(member.last.toMillis(), T0);
    assert.deepEqual(member.runs.map((point: any) => point.s), [5, 60]);
    assert.equal(member.n, 2);
  });

  it('keeps the earlier validated run from an out-of-order duplicate batch', async () => {
    const uid = uniq('lb-duplicate-out-of-order');
    const id = uniq('lb-duplicate-out-of-order-run');
    const earlier = submitRun({ id, score: 60, endTs: T0 });
    const later = submitRun({ id, score: 80, endTs: T0 + 2 * HOUR });
    const result = await lbSubmitRun(db, uid, request([later, earlier]), T0 + 2 * HOUR + 1000);
    assert.deepEqual(result.accepted, [id]);
    assert.deepEqual(result.dropped, [{ id, reason: 'duplicate' }]);

    const p = (await player(uid))!;
    assert.deepEqual(p.hist, [60]);
    const member = (await group(result.group!.id))!.members[uid] as any;
    assert.equal(member.last.toMillis(), T0);
    assert.deepEqual(member.runs.map((point: any) => point.s), [60]);
  });

  it('mirrors the eligible paid common/rare shop catalog', () => {
    const catalog = readFileSync('../lib/skins/catalog.dart', 'utf8');
    const expected = [...catalog.matchAll(/SkinItem\(layer: SkinLayer\.(\w+), id: '([^']+)'.*?rarity: Rarity\.(common|rare), price: (\d+)/g)]
      .filter((m) => Number(m[4]) > 0 && Number(m[4]) <= 750)
      .map((m) => ({ id: `${m[1]}:${m[2]}`, rarity: m[3], price: Number(m[4]) }));
    assert.deepEqual([...GIFT_SHOP_ITEMS].sort((a, b) => a.id.localeCompare(b.id)), expected.sort((a, b) => a.id.localeCompare(b.id)));
  });

  it('persists an item-class gold claim with fallback coins and repeats it unchanged', async () => {
    const uid = uniq('lb-item-claim');
    const id = uniq('lb-item-gift');
    await db.collection(LB_GIFTS_COLLECTION).doc(id).set({ uid, gid: id, tier: 'gold', boardRank: 1, expireAt: Timestamp.fromMillis(T0 + 400 * 24 * HOUR) });
    const rng = mock.method(crypto, 'randomInt', () => 1530780169);
    try {
      const claim = await lbClaimGift(db, uid, { id }, T0);
      assert.equal(claim.prize!.kind, 'item');
      assert.ok(GIFT_SHOP_ITEMS.some((item) => item.id === claim.prize!.item));
      assert.equal(claim.prize!.coins, 290);
      assert.equal(claim.prize!.seed, '1530780169');
      const repeat = await lbClaimGift(db, uid, { id }, T0 + 1000);
      assert.deepEqual(repeat, claim);
      assert.equal(rng.mock.callCount(), 1);
      assert.equal((await lbClaimGift(db, uniq('lb-other-claim'), { id }, T0)).ok, false);
    } finally { rng.mock.restore(); }
  });

  it('logs each committed settlement once for lazy reads, lazy submits and the scheduler', async () => {
    const info = mock.method(logger, 'info', () => {});
    try {
      for (const [index, route] of ['read', 'submit', 'scheduled'].entries()) {
        const uid = uniq(`lb-log-${route}`);
        const start = T0 + index * 72 * HOUR;
        const first = await lbSubmitRun(db, uid, request([submitRun({ score: 40, endTs: start })]), start + 1000);
        const gid = first.group!.id;
        await db.collection(LB_GROUPS_COLLECTION).doc(gid).update({ ghosts: [], ghostUids: [] });
        const end = (await group(gid))!.end.toMillis();
        if (route === 'read') await lbGetBoard(db, uid, { tab: 'today' }, end + 1000);
        else if (route === 'submit') await lbSubmitRun(db, uid, request([submitRun({ score: 15, endTs: end + HOUR })]), end + HOUR + 1000);
        else await lbSettleGroups(db, end + 1000, gid);
        await lbSettleGroups(db, end + 2000, gid);
        const logs = info.mock.calls.filter((call) => call.arguments[0] === 'lbSettle' && (call.arguments[1] as any).gid === gid);
        assert.equal(logs.length, 1);
        const metrics = logs[0].arguments[1] as any;
        assert.equal(metrics.groups, 1);
        assert.equal(metrics.gifts, 1);
        assert.equal(metrics.ghostDays, 1);
        assert.equal(metrics.gifts_lost_to_ghosts, 0);
      }
    } finally { info.mock.restore(); }
  });
});

// region P26-S2
describe('PRD-2.6 LB3 bounded leaderboard reads', () => {
  it('ranks 300 tied players with counts and never fetches the player collection', async () => {
    const uid = 'tie-150';
    await lbSubmitRun(db, uid, request([submitRun({ score: 100 })]), T0 + 1000);
    const template = (await player(uid))!;
    const batch = db.batch();
    for (let i = 0; i < 300; i++) {
      // 100 earlier, 100 same-timestamp (uid order), 100 later ties.
      batch.set(db.collection(LB_PLAYERS_COLLECTION).doc(`tie-${String(i).padStart(3, '0')}`), {
        ...template, bestAt: Timestamp.fromMillis(T0 + (Math.floor(i / 100) - 1) * 1000),
      });
    }
    batch.set(db.collection(LB_PLAYERS_COLLECTION).doc('greater'), { ...template, best: 101, bestShadow: 101 });
    batch.set(db.collection(LB_PLAYERS_COLLECTION).doc('hidden-tie'), { ...template, hidden: true });
    batch.set(db.collection(LB_PLAYERS_COLLECTION).doc('hidden-greater'), { ...template, bestShadow: 102, hidden: true });
    await batch.commit();
    const original = Query.prototype.get;
    let queryGets = 0;
    const spy = mock.method(Query.prototype, 'get', async function (this: Query) {
      queryGets++;
      return original.call(this);
    });
    try {
      const board = await lbGetBoard(db, uid, { tab: 'best' }, T0 + 2000);
      assert.equal(board.best.me!.rank, 152); // 1 greater + 100 earlier + 50 same-time predecessors + self.
      assert.equal(board.best.approximate, false);
      assert.equal(queryGets, 1, 'only gifts use Query.get; ranks must use aggregation counts');
    } finally { spy.mock.restore(); }
  });

  it('reads one suppression doc with the group for both opens and submits with 49 ghosts', async () => {
    const uid = uniq('bounded-viewer');
    const first = await lbSubmitRun(db, uid, request([submitRun({ score: 100 })]), T0 + 1000);
    const ghosts = Array.from({ length: 49 }, (_, i) => ({
      uid: `ghost-${i}`, name: `Ghost${i}`, look: LOOK, platform: 'android',
      runs: [{ t: 0, s: 200 }],
    }));
    await db.collection(LB_GROUPS_COLLECTION).doc(first.group!.id).update({ ghosts, ghostUids: ghosts.map((g) => g.uid) });
    await db.collection(LB_META_COLLECTION).doc('hidden').set({
      entries: { 'ghost-0': { until: Timestamp.fromMillis(T0 + 18 * 24 * HOUR), pending: true } },
    });
    const reads: string[] = [];
    const instrumented = new Proxy(db, {
      get(target, property) {
        if (property === 'runTransaction') return (callback: (tx: Transaction) => Promise<unknown>) =>
          target.runTransaction((tx) => callback(new Proxy(tx, {
            get(transaction, key) {
              if (key === 'get') return (ref: DocumentReference) => {
                reads.push(ref.path);
                return transaction.get(ref);
              };
              const value = Reflect.get(transaction, key, transaction);
              return typeof value === 'function' ? value.bind(transaction) : value;
            },
          })));
        const value = Reflect.get(target, property, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    }) as Firestore;
    const original = Query.prototype.get;
    let queryGets = 0;
    const spy = mock.method(Query.prototype, 'get', async function (this: Query) {
      queryGets++;
      return original.call(this);
    });
    try {
      const opened = await lbGetBoard(instrumented, uid, { tab: 'today' }, T0 + 2000);
      assert.equal(opened.today.rows.length, 49);
      assert.equal(opened.today.rows.some((row) => row.name === 'Ghost0'), false);
      assert.deepEqual(reads, [`${LB_GROUPS_COLLECTION}/${first.group!.id}`, `${LB_META_COLLECTION}/hidden`]);
      reads.length = 0;
      const submitted = await lbSubmitRun(instrumented, uid,
        request([submitRun({ score: 10, endTs: T0 + HOUR })]), T0 + HOUR + 1000);
      assert.equal(submitted.board!.rows.some((row) => row.name === 'Ghost0'), false);
      assert.equal(reads.filter((path) => path === `${LB_META_COLLECTION}/hidden`).length, 1);
      assert.deepEqual(reads.filter((path) => path.startsWith(`${LB_PLAYERS_COLLECTION}/`)), [`${LB_PLAYERS_COLLECTION}/${uid}`]);
      assert.equal(queryGets, 1, 'only the board gifts query: no cleanupPending collection scan');
    } finally { spy.mock.restore(); }
  });

  it('suppresses a deleted ghost before its cleanup sweep and after a stale group read', async () => {
    const owner = uniq('deleted-ghost');
    const viewer = uniq('deleted-viewer');
    const first = await lbSubmitRun(db, owner, request([submitRun({ score: 100 })]), T0 + 1000);
    const end = (await group(first.group!.id))!.end.toMillis();
    await lbSettleGroups(db, end + 1000, first.group!.id);
    const next = await lbSubmitRun(db, viewer,
      request([submitRun({ score: 90, endTs: end + HOUR })]), end + HOUR + 1000);
    const gid = next.group!.id;
    const stale = await db.collection(LB_GROUPS_COLLECTION).doc(gid).get();
    assert.equal((await lbGetBoard(db, viewer, {}, end + HOUR + 2000)).today.rows.length, 2);
    let raced = false;
    await deleteBoardData(dbWithAfterTransaction(async () => {
      raced = true;
      assert.equal((await lbGetBoard(db, viewer, {}, end + HOUR + 2000)).today.rows.length, 1);
    }), owner, end + HOUR + 2000);
    assert.equal(raced, true);
    assert.equal((await lbGetBoard(dbWithStaleGroupSnapshot(gid, stale), viewer, {}, end + HOUR + 3000)).today.rows.length, 1);
    assert.equal((await db.collection(LB_META_COLLECTION).doc('hidden').get()).data()!.entries[owner].pending, false);
  });

  it('retains failed cleanup markers and prunes only completed entries past the ghost horizon', async () => {
    const hidden = db.collection(LB_META_COLLECTION).doc('hidden');
    const expired = Timestamp.fromMillis(T0 - 1);
    await hidden.set({ entries: {
      failed: { until: expired, pending: true }, completed: { until: expired, pending: false },
      recent: { until: Timestamp.fromMillis(T0 + HOUR), pending: false },
    } });
    const uid = uniq('registry-prune');
    await lbSubmitRun(db, uid, request([submitRun({ score: 10 })], { t: 1 }), T0 + 1000);
    const entries = (await hidden.get()).data()!.entries;
    assert.deepEqual(Object.keys(entries).sort(), ['failed', 'recent', uid].sort());
    assert.equal(entries[uid].pending, false);
    assert.equal(entries[uid].until.toMillis(), T0 + 1000 + 18 * 24 * HOUR);
  });

  it('keeps registry size bounded across writes containing hundreds of expired entries', async () => {
    const ref = db.collection(LB_META_COLLECTION).doc('hidden');
    let retainedBytes: number | undefined;
    let entries: Record<string, unknown> = {
      failed: { until: Timestamp.fromMillis(T0 - 1), pending: true },
    };
    for (let round = 0; round < 4; round++) {
      const nowMs = T0 + round * 19 * 24 * HOUR;
      const expired = Object.fromEntries(Array.from({ length: 500 }, (_, i) => [
        `expired-${round}-${i}`, { until: Timestamp.fromMillis(nowMs - 1), pending: false },
      ]));
      await ref.set({ entries: { ...entries, ...expired } });
      const before = (await ref.get()).data()!;
      assert.equal(Object.keys(before.entries).length >= 501, true);
      await db.runTransaction(async (tx) => {
        const snapshot = await tx.get(ref);
        writeHiddenRegistry(tx, db, snapshot, 'current', nowMs, round % 2 === 0);
      });
      const after = (await ref.get()).data()!;
      entries = after.entries;
      assert.deepEqual(Object.keys(entries).sort(), ['current', 'failed']);
      assert.equal(after.entries.failed.pending, true, 'failed sweeps must remain suppressed');
      assert.equal(after.entries.current.pending, round % 2 === 0);
      retainedBytes ??= docSize(ref.path, after);
      assert.equal(docSize(ref.path, after), retainedBytes, 'expired entries must not increase retained doc size');
      assert.ok(docSize(ref.path, after) < docSize(ref.path, before), 'every write prunes the expired completed entries');
    }
  });

});
// endregion

// region P26-S4
describe('PRD-2.6 LB3 S4 hardening', () => {
  it('persists old BEST intervals and ids across separate submissions', async () => {
    const uid = uniq('old-best-overlap');
    const joined = await lbSubmitRun(db, uid, request([submitRun({ score: 40 })]), T0 + 1000);
    const start = (await group(joined.group!.id))!.start.toMillis();
    const old = submitRun({ score: 60, endTs: start - 1000 });
    const first = await lbSubmitRun(db, uid, request([old]), T0 + 2000);
    assert.deepEqual(first.dropped, [{ id: old.id, reason: 'old' }]);
    const stored = (await player(uid))!;
    assert.equal(stored.bestShadow, 60);
    assert.ok((stored.rate as any).runIds.includes(old.id));
    const next = submitRun({ score: 80, endTs: start + 1000 });
    const second = await lbSubmitRun(db, uid, request([next]), T0 + 3000);
    assert.deepEqual(second.dropped, [{ id: next.id, reason: 'overlap' }]);
  });

  it('keeps both ghost days when a newer group settles before an older group', async () => {
    const uid = uniq('settle-days');
    const older = await lbSubmitRun(db, uid, request([submitRun({ score: 40 })]), T0 + 1000);
    const newerTime = T0 + 26 * HOUR;
    const newer = await lbSubmitRun(db, uid, request([submitRun({ score: 40, endTs: newerTime })]), newerTime + 1000);
    const olderRef = db.collection(LB_GROUPS_COLLECTION).doc(older.group!.id);
    // The second submit lazily settles the first; reopen it to model a delayed scheduler.
    await olderRef.update({ settled: false });
    const now = newerTime + 26 * HOUR;
    await lbSettleGroups(db, now, newer.group!.id);
    await lbSettleGroups(db, now, older.group!.id);
    const pools = await db.collection(LB_GHOST_POOL_COLLECTION).get();
    const days = pools.docs.flatMap((doc) => doc.data().entries).filter((entry) => entry.uid === uid).map((entry) => entry.day);
    assert.equal(new Set(days).size, 2);
  });

  it('claims the only unowned eligible shop item and stores the same roll for retries', async () => {
    const uid = uniq('owned-claim');
    const id = uniq('owned-gift');
    const remaining = GIFT_SHOP_ITEMS.find((item) => item.rarity === 'common')!;
    await db.collection(LB_GIFTS_COLLECTION).doc(id).set({ uid, gid: id, tier: 'gold', boardRank: 1, expireAt: Timestamp.fromMillis(T0 + 400 * 24 * HOUR) });
    const rng = mock.method(crypto, 'randomInt', () => 1530780169);
    try {
      const claim = await lbClaimGift(db, uid, { id, owned: GIFT_SHOP_ITEMS.filter((item) => item.id !== remaining.id).map((item) => item.id) }, T0);
      assert.equal(claim.prize?.kind, 'item');
      assert.equal(claim.prize?.item, remaining.id);
      assert.deepEqual(await lbClaimGift(db, uid, { id, owned: [] }, T0 + 1000), claim);
    } finally { rng.mock.restore(); }
  });

  it('persists pass counts separately from scores for later soft jump checks', async () => {
    const uid = uniq('pass-history');
    for (let i = 0; i < 5; i++) {
      const endTs = T0 + i * HOUR;
      const deltas = Array.from({ length: 30 }, () => 140);
      const run = { ...submitRun({ score: 60, endTs }), hoops: 30, cs: 30 * 140 + 80,
        tl: encodeDeltas(deltas), fl: encodeEntries(deltas.map(() => 0), deltas.map(() => 2)) };
      await lbSubmitRun(db, uid, request([run]), endTs + 1000);
    }
    const p = (await player(uid))! as any;
    assert.deepEqual(p.hist, [60, 60, 60, 60, 60]);
    assert.deepEqual(p.passHist, [30, 30, 30, 30, 30]);
    const jump = submitRun({ score: 150, endTs: T0 + 6 * HOUR });
    await lbSubmitRun(db, uid, request([jump]), T0 + 6 * HOUR + 1000);
    const flag = (await db.collection(LB_FLAGS_COLLECTION).doc(`${uid}_${jump.id}`).get()).data();
    assert.equal(flag?.signals.jump, 30);
    assert.equal(flag?.soft, true);
  });

  it('uses read-only transactions when opening TODAY', async () => {
    const uid = uniq('readonly');
    await lbSubmitRun(db, uid, request([submitRun()]), T0 + 1000);
    let readOnly = 0;
    const wrapped = new Proxy(db, {
      get(target, prop) {
        if (prop === 'runTransaction') return (fn: any, opts: any) => {
          if (opts?.readOnly) readOnly++;
          return target.runTransaction(fn, opts);
        };
        const value = Reflect.get(target, prop, target);
        return typeof value === 'function' ? value.bind(target) : value;
      },
    });
    await lbGetBoard(wrapped, uid, { tab: 'today' }, T0 + 2000);
    assert.equal(readOnly, 1);
  });
});
// endregion
