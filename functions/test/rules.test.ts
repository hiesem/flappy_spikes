/** §3.13 / ARCH §6.2 security rules against the Firestore emulator. */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, Timestamp, updateDoc } from 'firebase/firestore';
import { encodeDeltas, encodeFlags } from '../src/timeline.js';
import { DAY, LOOK, PROJECT, uniq } from './helpers.js';

let env: RulesTestEnvironment;

// Rules tests use score-2 runs so the live trigger rejects them (low_score) and never touches a pool.
function run(o: Record<string, unknown> = {}) {
  return {
    runId: uniq('r'),
    score: 2,
    best: 2,
    ts: Timestamp.now(),
    name: 'SwiftKiwi482',
    avatar: '',
    look: { ...LOOK },
    platform: 'android',
    tl: encodeDeltas([120, 120]),
    end: 80,
    fl: encodeFlags([0, 0]),
    ...o,
  };
}

function player(o: Record<string, unknown> = {}) {
  return {
    name: 'SwiftKiwi482',
    avatar: '',
    platform: 'android',
    look: { ...LOOK },
    best: 2,
    level: 0,
    bestRun: null,
    recent: [run()],
    uploads: { day: '2026-10-08', count: 1 },
    updatedAt: serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + 60 * DAY),
    ...o,
  };
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

describe('§3.13 rules: players/{uid}', () => {
  it('§3.13 a player can create, read, update and delete their own doc', async () => {
    const uid = uniq('own');
    const db = env.authenticatedContext(uid).firestore();
    const ref = doc(db, 'players', uid);
    await assertSucceeds(setDoc(ref, player()));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { name: 'HappyRobin007', updatedAt: serverTimestamp() }));
    await assertSucceeds(deleteDoc(ref));
  });

  it('§3.13 a player cannot read or write another player doc', async () => {
    const owner = uniq('owner');
    await assertSucceeds(setDoc(doc(env.authenticatedContext(owner).firestore(), 'players', owner), player()));
    const other = env.authenticatedContext(uniq('other')).firestore();
    await assertFails(getDoc(doc(other, 'players', owner)));
    await assertFails(setDoc(doc(other, 'players', owner), player()));
    await assertFails(deleteDoc(doc(other, 'players', owner)));
  });

  it('§3.13 unauthenticated clients are denied', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, 'players', 'x'), player()));
    await assertFails(getDoc(doc(db, 'players', 'x')));
  });

  const bad: Array<[string, Record<string, unknown>]> = [
    ['an unknown field', { cheat: true }],
    ['an empty name', { name: '' }],
    ['a name over 32 chars', { name: 'x'.repeat(33) }],
    ['level 11', { level: 11 }],
    ['an unknown platform', { platform: 'web' }],
    ['a look with a missing id', { look: { bird: 'a', gear: 'b', hat: 'c', hoop: 'd' } }],
    ['a client-chosen updatedAt', { updatedAt: Timestamp.now() }],
    ['no expireAt', { expireAt: null }],
    ['an expireAt not ~60 days ahead', { expireAt: Timestamp.fromMillis(Date.now() + 365 * DAY) }],
    ['6 recent runs', { recent: [run(), run(), run(), run(), run(), run()] }],
    ['a bestRun that is not recent[0]', { bestRun: run(), recent: [run()] }],
    ['a recent run with an extra field', { recent: [run({ x: 1 })] }],
    ['a recent run with best < score', { recent: [run({ score: 3, best: 2 })] }],
    ['a recent run above the player best', { recent: [run({ score: 5, best: 5 })] }],
    ['a bestRun above the player best', { best: 2, bestRun: run({ score: 9, best: 9 }) }],
    ['a timeline over 16 KB', { recent: [run({ tl: 'A'.repeat(16388) })] }],
    ['flags over 8 KB', { recent: [run({ fl: 'A'.repeat(8196) })] }],
    ['a run name over 32 chars', { recent: [run({ name: 'y'.repeat(33) })] }],
    ['a non-int score', { best: 2.5 }],
  ];
  for (const [name, patch] of bad) {
    it(`§3.13 rejects a player doc with ${name}`, async () => {
      const uid = uniq('bad');
      const data = player(patch);
      if (patch.expireAt === null) delete (data as Record<string, unknown>).expireAt;
      await assertFails(setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), data));
    });
  }

  it('§3.13 accepts a create holding one run (bestRun == recent[0]) with a long timeline', async () => {
    const uid = uniq('full');
    const big = run({ score: 3000, best: 3000, tl: 'A'.repeat(16000), fl: 'A'.repeat(8000) });
    const data = player({ best: 3000, level: 9, bestRun: big, recent: [big] });
    await assertSucceeds(setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), data));
  });

  it('§3.13 one new run per write: a create with two runs is rejected', async () => {
    const uid = uniq('two');
    await assertFails(setDoc(doc(env.authenticatedContext(uid).firestore(), 'players', uid), player({ recent: [run(), run()] })));
  });

  it('§3.13 a long series of single-run updates stays valid (5 recent + a best, long timelines)', async () => {
    const uid = uniq('series');
    const ref = doc(env.authenticatedContext(uid).firestore(), 'players', uid);
    let recent: ReturnType<typeof run>[] = [];
    let bestRun: ReturnType<typeof run> | null = null;
    for (let i = 0; i < 8; i++) {
      const r = run({ tl: 'A'.repeat(16000), fl: 'A'.repeat(8000) });
      recent = [r, ...recent].slice(0, 5);
      if (i % 3 === 0) bestRun = r;
      await assertSucceeds(setDoc(ref, player({ bestRun, recent })));
    }
    // Two new runs at once, a new run anywhere but recent[0], or a new best run not in recent[0]: rejected.
    await assertFails(setDoc(ref, player({ bestRun, recent: [run(), run(), ...recent.slice(0, 3)] })));
    await assertFails(setDoc(ref, player({ bestRun, recent: [recent[0], run(), ...recent.slice(1, 4)] })));
    await assertFails(setDoc(ref, player({ bestRun: run(), recent })));
    // A new run that breaks the shape is rejected.
    await assertFails(setDoc(ref, player({ bestRun, recent: [run({ x: 1 }), ...recent.slice(0, 4)] })));
    // The server trimming recent (dropping old entries) leaves a valid doc for the next write.
    await assertSucceeds(setDoc(ref, player({ bestRun, recent: [run(), recent[0]] })));
  });

  it('§3.13 the best score cannot go down', async () => {
    const uid = uniq('best');
    const ref = doc(env.authenticatedContext(uid).firestore(), 'players', uid);
    await assertSucceeds(setDoc(ref, player({ best: 50 })));
    await assertFails(setDoc(ref, player({ best: 40 })));
    await assertSucceeds(setDoc(ref, player({ best: 60 })));
  });
});

describe('§3.13 rules: pools and everything else', () => {
  it('§3.13 signed-in clients can read a pool but never write one', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'pools', '0_0'), { level: 0, shard: 0, entries: [] }, { merge: true });
    });
    const db = env.authenticatedContext(uniq('reader')).firestore();
    await assertSucceeds(getDoc(doc(db, 'pools', '0_0')));
    await assertFails(setDoc(doc(db, 'pools', '0_0'), { entries: [] }));
    await assertFails(setDoc(doc(db, 'pools', '9_9'), { entries: [] }));
    await assertFails(deleteDoc(doc(db, 'pools', '0_0')));
  });

  it('§3.13 unauthenticated clients cannot read pools', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'pools', '0_0')));
  });

  it('§3.13 the server rate docs and unknown collections are denied', async () => {
    const uid = uniq('srv');
    const db = env.authenticatedContext(uid).firestore();
    await assertFails(getDoc(doc(db, 'versusRate', uid)));
    await assertFails(setDoc(doc(db, 'versusRate', uid), { count: 0 }));
    await assertFails(setDoc(doc(db, 'anything', 'x'), { a: 1 }));
    assert.ok(true);
  });
});
