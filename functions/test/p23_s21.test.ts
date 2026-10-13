/**
 * PRD-2.3 §21.5 versus names, pictures and looks on the backend:
 * - a non-default look in all five layers and the hashed Play Games id `pg`
 *   survive upload → pool → matching, id for id;
 * - the Firestore rules accept `pg` ('' or 64 hex) and refuse other shapes;
 * - the Storage rules of `avatars/{uid}.jpg` (owner-only write / delete,
 *   images ≤ 30 KB, public read);
 * - "Delete my data" removes the picture (functions + storage emulators).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { getStorage } from 'firebase-admin/storage';
import { doc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';
import { avatarBucketName, avatarPath } from '../src/avatars.js';
import { matchCandidates, pickOpponent, MatchEntry } from '../src/matching.js';
import { poolId } from '../src/schema.js';
import { checkRun, encodeDeltas, encodeEntries } from '../src/timeline.js';
import { auth, DAY, fakeJwt, LOOK, LOOK_FANCY, makePlayer, makeRun, poolEntries, processLive, PROJECT, uniq } from './helpers.js';

const PG_A = 'a'.repeat(64);
const PG_B = '0123456789abcdef'.repeat(4);
const BUCKET = avatarBucketName();
let env: RulesTestEnvironment;

const storageHost = (): { host: string; port: number } => {
  const [host, port] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '127.0.0.1:9199').split(':');
  return { host, port: Number(port) };
};

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(join(__dirname, '..', '..', 'firestore.rules'), 'utf8') },
    storage: { ...storageHost(), rules: readFileSync(join(__dirname, '..', '..', 'storage.rules'), 'utf8') },
  });
});

after(async () => {
  await env?.cleanup();
});

describe('PRD-2.3 §21.5 looks and pg: upload → pool → matching', () => {
  it('§21.5 a run in Grape, Shades, Cap, Neon, Bubbles keeps every id (and its pg) in the pool and the match', async () => {
    const uid = uniq('look');
    const run = makeRun({ score: 150, look: LOOK_FANCY, pg: PG_B });
    const r = await processLive(uid, undefined, makePlayer({ best: 150, bestRun: run, recent: [run] }), {
      rand: () => 0,
    });
    assert.deepEqual(r.accepted, [run.runId]);
    const entries = await poolEntries(poolId(3, 0));
    const e = entries.find((x) => x.runId === run.runId)!;
    assert.deepEqual(e.look, LOOK_FANCY);
    assert.equal(e.pg, PG_B);
    // Matching from the real pool doc hands out exactly this run (and its look).
    const me = { uid: uniq('me'), best: 200, level: 3 };
    const pool = entries.filter((x) => x.runId === run.runId) as unknown as MatchEntry[];
    const pick = pickOpponent(pool, me, [], () => 0) as unknown as Record<string, unknown>;
    assert.deepEqual(pick.look, LOOK_FANCY);
  });

  it('§21.4 a run without pg (older uploads) is pooled with pg "" and still matches', async () => {
    const uid = uniq('nopg');
    const run = makeRun({ score: 160 });
    await processLive(uid, undefined, makePlayer({ best: 160, bestRun: run, recent: [run] }), { rand: () => 0 });
    const e = (await poolEntries(poolId(3, 0))).find((x) => x.runId === run.runId)!;
    assert.equal(e.pg, '');
    const { tier } = matchCandidates([e as unknown as MatchEntry], { uid: 'me', best: 200, level: 3, pg: PG_A }, []);
    assert.equal(tier, 'level');
  });

  it('§21.4 a candidate with my pg under another uid is never chosen', () => {
    const pool: MatchEntry[] = [
      { uid: 'old-anon', runId: 'o1', score: 80, level: 3, pg: PG_A },
      { uid: 'b', runId: 'b1', score: 90, level: 3, pg: PG_B },
    ];
    for (let i = 0; i < 20; i++) {
      assert.equal(pickOpponent(pool, { uid: 'me', best: 200, level: 3, pg: PG_A }, [], () => i / 20)!.runId, 'b1');
    }
  });

  it('§21.4 the server check accepts pg "" / 64 hex and refuses other shapes', () => {
    assert.equal(checkRun({ ...makeRun(), pg: '' }, 99), null);
    assert.equal(checkRun({ ...makeRun(), pg: PG_B }, 99), null);
    assert.equal(checkRun({ ...makeRun(), pg: 'A'.repeat(64) }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), pg: 'abc' }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), pg: 7 as unknown as string }, 99), 'shape');
  });
});

describe('PRD-2.3 §21.4 firestore rules: pg', () => {
  function run(o: Record<string, unknown> = {}) {
    return {
      runId: uniq('r'),
      score: 2,
      best: 2,
      ts: Timestamp.now(),
      name: 'SwiftKiwi482',
      avatar: '',
      look: { ...LOOK_FANCY },
      platform: 'android',
      tl: encodeDeltas([120, 120]),
      end: 80,
      fl: encodeEntries([0, 0], [1, 1]),
      ...o,
    };
  }
  function player(r: Record<string, unknown>) {
    return {
      name: 'SwiftKiwi482',
      avatar: 'https://firebasestorage.googleapis.com/v0/b/x/o/avatars%2Fu.jpg?alt=media',
      platform: 'android',
      look: { ...LOOK },
      best: 2,
      level: 0,
      bestRun: null,
      recent: [r],
      uploads: { day: '2026-10-13', count: 1 },
      updatedAt: serverTimestamp(),
      expireAt: Timestamp.fromMillis(Date.now() + 60 * DAY),
    };
  }
  const write = (r: Record<string, unknown>) => {
    const uid = uniq('pg');
    return setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), player(r));
  };

  it('§21.4 accepts a run with pg "" , with a 64-hex pg, and without pg', async () => {
    await assertSucceeds(write(run({ pg: '' })));
    await assertSucceeds(write(run({ pg: PG_B })));
    await assertSucceeds(write(run()));
  });

  it('§21.4 refuses a malformed pg or a 12th key that is not pg', async () => {
    await assertFails(write(run({ pg: 'abc' })));
    await assertFails(write(run({ pg: 'A'.repeat(64) })));
    await assertFails(write(run({ pg: 1 })));
    await assertFails(write(run({ px: '' })));
  });
});

describe('PRD-2.3 §21.5 storage rules: avatars/{uid}.jpg', () => {
  const jpeg = (n: number) => {
    const b = new Uint8Array(n);
    b.set([0xff, 0xd8, 0xff, 0xe0]);
    return b;
  };
  const meta = { contentType: 'image/jpeg' };

  it('§21.3 a player writes, replaces and deletes their own picture; anyone reads it', async () => {
    const uid = uniq('pic');
    const ref = env.authenticatedContext(uid).storage(`gs://${BUCKET}`).ref(avatarPath(uid));
    await assertSucceeds(ref.put(jpeg(2000), meta));
    await assertSucceeds(ref.put(jpeg(30 * 1024), meta));
    await assertSucceeds(env.unauthenticatedContext().storage(`gs://${BUCKET}`).ref(avatarPath(uid)).getMetadata());
    await assertSucceeds(env.authenticatedContext(uniq('x')).storage(`gs://${BUCKET}`).ref(avatarPath(uid)).getMetadata());
    await assertSucceeds(ref.delete());
  });

  it('§21.5 another uid cannot write or delete your picture', async () => {
    const uid = uniq('own');
    await assertSucceeds(
      env.authenticatedContext(uid).storage(`gs://${BUCKET}`).ref(avatarPath(uid)).put(jpeg(1000), meta),
    );
    const other = env.authenticatedContext(uniq('other')).storage(`gs://${BUCKET}`).ref(avatarPath(uid));
    await assertFails(other.put(jpeg(1000), meta));
    await assertFails(other.delete());
    await assertFails(env.unauthenticatedContext().storage(`gs://${BUCKET}`).ref(avatarPath(uid)).put(jpeg(1000), meta));
  });

  it('§21.5 a non-image or a file over 30 KB is refused; other paths are denied', async () => {
    const uid = uniq('big');
    const s = env.authenticatedContext(uid).storage(`gs://${BUCKET}`);
    await assertFails(s.ref(avatarPath(uid)).put(jpeg(30 * 1024 + 1), meta));
    await assertFails(s.ref(avatarPath(uid)).put(jpeg(1000), { contentType: 'text/plain' }));
    await assertFails(s.ref(`avatars/${uid}.png`).put(jpeg(1000), { contentType: 'image/png' }));
    await assertFails(s.ref(`other/${uid}.jpg`).put(jpeg(1000), meta));
  });
});

describe('PRD-2.3 §21.5 deleteMyData removes the picture (emulated callable)', () => {
  const url = `http://127.0.0.1:5001/${PROJECT}/europe-west1/deleteMyData`;
  const idToken = (uid: string) =>
    fakeJwt({ sub: uid, user_id: uid, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: 1, exp: 4e9 });
  const appCheck = fakeJwt({ sub: '1:512525012529:android:8bb85c213b543c6487cf10', aud: [`projects/${PROJECT}`] });

  it('§21.3 "Delete my data" deletes avatars/{uid}.jpg; idempotent without one', async () => {
    const uid = uniq('bye');
    await auth.createUser({ uid });
    const file = getStorage().bucket(BUCKET).file(avatarPath(uid));
    await file.save(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0]), { contentType: 'image/jpeg' });
    assert.equal((await file.exists())[0], true);
    const headers = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${idToken(uid)}`,
      'X-Firebase-AppCheck': appCheck,
    };
    const res = await fetch(url, { method: 'POST', headers, body: '{"data":{}}' });
    assert.equal(res.status, 200, await res.clone().text());
    assert.equal((await file.exists())[0], false);
    const again = await fetch(url, { method: 'POST', headers, body: '{"data":{}}' });
    assert.equal(again.status, 200, await again.clone().text());
  });
});
