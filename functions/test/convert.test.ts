/** PRD-2.2 §13.5 the v1 → v2 pool conversion (emulator). */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Timestamp } from 'firebase-admin/firestore';
import { convertPools } from '../src/convert.js';
import { checkRun, scoreAt } from '../src/timeline.js';
import type { PoolEntry } from '../src/schema.js';
import { db, LOOK, makeRun } from './helpers.js';

const FX = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'test', 'fixtures', 'versus_timeline_v2.json'), 'utf8'),
);

function entry(runId: string, tl: string, fl: string, score: number, end: number): PoolEntry {
  return {
    runId,
    uid: `u-${runId}`,
    level: 9,
    score,
    best: score,
    ts: Timestamp.now(),
    name: 'OldBird',
    avatar: '',
    look: LOOK,
    platform: 'android',
    tl,
    end,
    fl,
  };
}

describe('PRD-2.2 §13.5 convertPools (emulator)', () => {
  it('§13.7 converts v1 entries in place (value 1, same score, flags kept), leaves v2 alone, is idempotent', async () => {
    // Level 9 shard 3: no other suite writes there.
    const ref = db.collection('pools').doc('9_3');
    const v2 = makeRun({ score: 4 });
    await ref.set({
      level: 9,
      shard: 3,
      updatedAt: Timestamp.now(),
      entries: [
        entry('old-1', FX.v1.tl, FX.v1.fl, FX.v1.score, FX.v1.end),
        entry('new-1', v2.tl, v2.fl, 4, v2.end),
      ],
    });
    const first = await convertPools(db);
    assert.ok(first.converted >= 1);
    const after = (await ref.get()).data()!.entries as PoolEntry[];
    const old = after.find((e) => e.runId === 'old-1')!;
    assert.equal(old.fl, FX.v1Converted.fl);
    assert.equal(old.tl, FX.v1.tl);
    assert.equal(old.score, FX.v1.score);
    assert.equal(checkRun({ ...makeRun({ score: old.score }), tl: old.tl, fl: old.fl, end: old.end }, 99), null);
    for (const [cs, score] of FX.v1Replay as [number, number][]) assert.equal(scoreAt(old.tl, old.fl, cs), score);
    assert.equal(after.find((e) => e.runId === 'new-1')!.fl, v2.fl, 'v2 unchanged');
    assert.equal(after.length, 2, 'nothing deleted');
    const second = await convertPools(db);
    assert.equal(second.converted, 0, 'idempotent');
    assert.ok(second.alreadyV2 >= 2);
  });

  it('§13.5 a dry run writes nothing', async () => {
    const ref = db.collection('pools').doc('9_3');
    await ref.set({
      level: 9,
      shard: 3,
      updatedAt: Timestamp.now(),
      entries: [entry('old-2', FX.v1.tl, FX.v1.fl, FX.v1.score, FX.v1.end)],
    });
    const r = await convertPools(db, { dryRun: true });
    assert.ok(r.converted >= 1);
    const e = ((await ref.get()).data()!.entries as PoolEntry[])[0];
    assert.equal(e.fl, FX.v1.fl);
    await ref.delete();
  });
});
