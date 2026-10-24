/** PRD-2.6 WP-LB board_store: Firestore transactions and emulated callables. */
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import {
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
  LB_MIN_LEFT_MS,
  LB_PLAYERS_COLLECTION,
  LB_TOMB_COLLECTION,
  type LbGiftDoc,
  type LbGroupDoc,
  type LbPlayerDoc,
} from '../src/schema.js';
import { encodeDeltas, encodeEntries } from '../src/timeline.js';
import { db, fakeJwt, LOOK, PROJECT, uniq } from './helpers.js';

const HOUR = 3600 * 1000;
const T0 = Date.UTC(2026, 9, 20, 12, 0, 0);

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
  const cs = o.cs ?? Math.max(1200, score * 120 + 80);
  const deltas = Array.from({ length: score }, () => 120);
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
    const r0 = await lbSubmitRun(db, first, request([submitRun({ score: 2100, endTs: T0 })]), T0 + 1000);
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
    const scheduledRun = await lbSubmitRun(db, sched, request([submitRun({ score: 600, endTs: T0 + 5 * HOUR })]), T0 + 5 * HOUR + 1000);
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
    await lbSubmitRun(db, hidden, request([submitRun({ score: 300, endTs: T0 + 1000 })], { t: 1 }), T0 + 2000);
    // Force the hidden tester into the group so the O65 place-keeping rule is
    // exercised; a real hidden submission never joins by itself.
    const g = (await group(gid))!;
    await db.collection(LB_GROUPS_COLLECTION).doc(gid).update({
      memberUids: [...g.memberUids, hidden],
      members: {
        ...g.members,
        [hidden]: { t: 300, b: 300, n: 1, last: Timestamp.fromMillis(T0), name: 'Hidden', look: LOOK, platform: 'android' },
      },
    });
    const end = g.end.toMillis();
    await lbSettleGroups(db, end + 1000, gid);
    assert.equal((await gifts(hidden)).length, 0);
    assert.equal((await gifts(real)).length, 0);
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
      customName: 'Brave Lark',
      updatedAt: Timestamp.fromMillis(T0),
    });
    const r = await lbSubmitRun(db, uid, request([submitRun({ score: 75, endTs: T0 })], { name: 'Dev Platform Name' }), T0 + 1000);
    assert.equal(r.board?.rows.some((row) => row.name === 'Brave Lark'), true);
    assert.equal((await player(uid))?.name, 'Brave Lark');
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
