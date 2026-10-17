/**
 * PRD-2.3 §21.5 versus names, pictures and looks on the backend:
 * - a non-default look in all five layers and the hashed Play Games id `pg`
 *   survive upload → pool → matching, id for id;
 * - the Firestore rules accept `pg` ('' or 64 hex) and refuse other shapes.
 * (WP-AV removed the versus pictures: the Storage tests moved to
 * `p24_av.test.ts`, which checks that Storage is closed.)
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
import { doc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';
import { matchCandidates, pickOpponent, MatchEntry } from '../src/matching.js';
import { poolId } from '../src/schema.js';
import { checkRun, encodeDeltas, encodeEntries } from '../src/timeline.js';
import { DAY, LOOK, LOOK_FANCY, makePlayer, makeRun, poolEntries, processLive, PROJECT, uniq } from './helpers.js';

const PG_A = 'a'.repeat(64);
const PG_B = '0123456789abcdef'.repeat(4);
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
