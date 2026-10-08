/**
 * §3.13 end to end through the emulated functions: a client write to
 * players/{uid} (through the rules) fires onPlayerRunWrite, and the callable
 * deleteMyData with App Check enforced.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';
import { poolId, RATE_COLLECTION, SHARDS } from '../src/schema.js';
import { encodeDeltas, encodeFlags } from '../src/timeline.js';
import { auth, DAY, db, fakeJwt, LOOK, PROJECT, uniq, waitFor } from './helpers.js';

const LEVEL = 5; // best 400..599: no other suite writes this level
let env: RulesTestEnvironment;

function clientRun(score: number, deltas?: number[]) {
  const d = deltas ?? Array.from({ length: score }, () => 110);
  return {
    runId: uniq('e2e'),
    score,
    best: score,
    ts: Timestamp.now(),
    name: 'BraveOwl123',
    avatar: '',
    look: { ...LOOK },
    platform: 'ios',
    tl: encodeDeltas(d),
    end: 64,
    fl: encodeFlags(d.map(() => 0)),
  };
}

function clientPlayer(best: number, bestRun: unknown, recent: unknown[]) {
  return {
    name: 'BraveOwl123',
    avatar: '',
    platform: 'ios',
    look: { ...LOOK },
    best,
    level: 5,
    bestRun,
    recent,
    uploads: { day: '2026-10-08', count: 0 },
    updatedAt: serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + 60 * DAY),
  };
}

async function findEntry(uid: string, runId: string) {
  for (let s = 0; s < SHARDS; s++) {
    const snap = await db.collection('pools').doc(poolId(LEVEL, s)).get();
    const e = (snap.data()?.entries ?? []).find((x: any) => x.uid === uid && x.runId === runId);
    if (e) return { shard: s, entry: e };
  }
  return null;
}

async function lastResult(uid: string, runId: string) {
  return waitFor(async () => {
    const d = (await db.collection(RATE_COLLECTION).doc(uid).get()).data();
    return d?.last?.runId === runId ? d.last : null;
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8') },
  });
});

after(async () => {
  await env?.cleanup();
});

describe('§3.13 onPlayerRunWrite (emulated trigger)', () => {
  it('§3.13 a client upload of a new best lands in the pool of its level', async () => {
    const uid = uniq('live');
    const run = clientRun(450);
    await setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), clientPlayer(450, run, [run]));
    const last = await lastResult(uid, run.runId);
    assert.equal(last.status, 'accepted');
    const found = await findEntry(uid, run.runId);
    assert.ok(found, 'entry in a level-5 shard');
    assert.equal(found!.entry.platform, 'ios'); // stored, never used for matching
    assert.equal(found!.entry.level, LEVEL);
  });

  it('§3.13 a cheated timeline (points 0.5 s apart) is rejected and never reaches a pool', async () => {
    const uid = uniq('cheat');
    const run = clientRun(450, Array(450).fill(50));
    await setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), clientPlayer(450, run, [run]));
    const last = await lastResult(uid, run.runId);
    assert.equal(last.status, 'rejected');
    assert.equal(last.reason, 'gap');
    assert.equal(await findEntry(uid, run.runId), null);
  });
});

describe('§3.13 deleteMyData (emulated callable, App Check enforced)', () => {
  const url = `http://127.0.0.1:5001/${PROJECT}/europe-west1/deleteMyData`;
  const call = (headers: Record<string, string>) =>
    fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: '{"data":{}}' });
  const idToken = (uid: string) =>
    fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
  const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });

  it('§3.13 refuses a call without an App Check token', async () => {
    const res = await call({ Authorization: `Bearer ${idToken('nobody')}` });
    assert.equal(res.status, 401);
  });

  it('§3.13 refuses a call without auth', async () => {
    const res = await call({ 'X-Firebase-AppCheck': appCheck });
    assert.equal(res.status, 401);
  });

  it('§3.13 deletes the player doc, their pool entries and the Auth user; idempotent', async () => {
    const uid = uniq('bye');
    await auth.createUser({ uid });
    const run = clientRun(500);
    await setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), clientPlayer(500, run, [run]));
    await lastResult(uid, run.runId);
    assert.ok(await findEntry(uid, run.runId));

    const headers = { Authorization: `Bearer ${idToken(uid)}`, 'X-Firebase-AppCheck': appCheck };
    const res = await call(headers);
    assert.equal(res.status, 200, await res.clone().text());
    const body = (await res.json()) as { result: { ok: boolean; removed: number } };
    assert.equal(body.result.ok, true);
    assert.equal(body.result.removed, 1);
    assert.equal(await findEntry(uid, run.runId), null);
    assert.equal((await db.collection('players').doc(uid).get()).exists, false);
    await assert.rejects(auth.getUser(uid), (e: any) => e.code === 'auth/user-not-found');

    const again = await call(headers);
    assert.equal(again.status, 200);
  });
});
