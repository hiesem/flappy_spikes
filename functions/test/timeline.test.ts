/** §3.13 cheat filter and timeline codec, format v2 (PRD-2.2 §13.5; pure, no emulator writes). */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  checkRun,
  convertV1ToV2,
  decodeDeltas,
  decodeEntries,
  encodeDeltas,
  encodeEntries,
  scoreAt,
} from '../src/timeline.js';
import { FLAG_BONUS, FLAG_GIFT, FLAG_RIDE, FLAG_TRAIN } from '../src/schema.js';
import { makeRun } from './helpers.js';

/** The fixture shared with the Dart client (test/p22/s13_versus_timeline_test.dart). */
const FX = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'test', 'fixtures', 'versus_timeline_v2.json'), 'utf8'),
);

describe('§3.13 / PRD-2.2 §13.5 timeline codec (v2)', () => {
  it('§3.13 tl round-trips uint16 LE centisecond deltas through base64', () => {
    const d = [0, 1, 90, 255, 256, 65535];
    assert.deepEqual(decodeDeltas(encodeDeltas(d)), d);
  });
  it('§3.13 malformed base64 or an odd byte count does not decode', () => {
    assert.equal(decodeDeltas('abc'), null);
    assert.equal(decodeDeltas('AA=='), null); // 1 byte: not a whole uint16
  });
  it('§13.5 fl v2 round-trips flags and uint16 values; v1 / zero values do not decode', () => {
    const flags = [0, FLAG_BONUS, FLAG_GIFT, FLAG_RIDE];
    const values = [1, 250, 5, 65535];
    assert.deepEqual(decodeEntries(encodeEntries(flags, values)), { flags, values });
    assert.equal(decodeEntries(Buffer.from([0, 0, 0]).toString('base64')), null, 'v1: no version byte');
    assert.equal(decodeEntries(encodeEntries([0], [0])), null, 'a zero value');
  });
  it('§13.5 scoreAt sums the values on run time', () => {
    const tl = encodeDeltas([100, 120, 0]);
    const fl = encodeEntries([0, 0, FLAG_BONUS], [1, 2, 25]);
    assert.equal(scoreAt(tl, fl, 99), 0);
    assert.equal(scoreAt(tl, fl, 100), 1);
    assert.equal(scoreAt(tl, fl, 219), 1);
    assert.equal(scoreAt(tl, fl, 220), 28);
  });
  it('§13.7 the shared fixture: the Dart-recorded v2 run validates and replays (Dart record → TS validate → Dart replay)', () => {
    const run = makeRun({ score: FX.run.score });
    const r = { ...run, tl: FX.run.tl, fl: FX.run.fl, end: FX.run.end };
    assert.equal(checkRun(r, FX.run.score), null);
    for (const [cs, score] of FX.replay as [number, number][]) {
      assert.equal(scoreAt(FX.run.tl, FX.run.fl, cs), score, `at ${cs} cs`);
    }
    const meta = decodeEntries(FX.run.fl)!;
    assert.deepEqual(meta.values, (FX.record as { value: number }[]).map((e) => e.value));
    assert.deepEqual(meta.flags, (FX.record as { flag: number }[]).map((e) => e.flag));
  });
});

describe('§3.13 / PRD-2.2 §13.5 cheat filter (checkRun)', () => {
  it('§3.13 a plain run with entries ≥ 0.9 s apart passes', () => {
    assert.equal(checkRun(makeRun({ score: 10 }), 10), null);
  });
  it('§3.13 malformed display fields are rejected (the function re-checks what the rules bound loosely)', () => {
    assert.equal(checkRun({ ...makeRun(), look: { bird: 'x'.repeat(41), gear: '', hat: '', hoop: '', trail: '' } }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), look: { bird: 1 } as any }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), name: '' }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), platform: 'web' as any }, 99), 'shape');
  });
  it('§3.13 runs under score 3 are rejected (3 points)', () => {
    assert.equal(checkRun(makeRun({ score: 2 }), 10), 'low_score');
  });
  it('§13.5 a v1 upload (one flag byte per point) is rejected', () => {
    const v1 = { ...makeRun({ score: FX.v1.score }), tl: FX.v1.tl, fl: FX.v1.fl, end: FX.v1.end };
    assert.equal(checkRun(v1, 99), 'version');
  });
  it('§13.5 sum of values ≠ score is rejected', () => {
    const r = makeRun({ score: 10, deltas: Array(9).fill(120) });
    assert.equal(checkRun(r, 10), 'count');
    assert.equal(checkRun(makeRun({ score: 5, deltas: [120, 120, 120], values: [1, 2, 2] }), 5), null);
  });
  it('§3.13 fl entry count ≠ tl entry count is rejected', () => {
    const r = makeRun({ score: 5, flags: [0, 0, 0], values: [1, 2, 2] });
    assert.equal(checkRun(r, 5), 'timeline');
  });
  it('§3.13 two plain entries < 0.9 s apart are rejected', () => {
    assert.equal(checkRun(makeRun({ score: 5, deltas: [120, 120, 89, 120, 120] }), 5), 'gap');
    assert.equal(checkRun(makeRun({ score: 5, deltas: [120, 120, 90, 120, 120] }), 5), null);
  });
  it('§3.13 the first entry has no gap check (time from run start)', () => {
    assert.equal(checkRun(makeRun({ score: 4, deltas: [10, 120, 120, 120] }), 4), null);
  });
  it('§3.13 / §13.5 ride / train / gift / bonus entries are exempt from the 0.9 s gap', () => {
    const deltas = [120, 30, 30, 120, 40, 120, 0, 0];
    const flags = [0, FLAG_RIDE, FLAG_RIDE, 0, FLAG_TRAIN, 0, FLAG_GIFT, FLAG_BONUS];
    const values = [1, 2, 3, 1, 2, 2, 5, 3];
    const score = values.reduce((a, b) => a + b, 0);
    assert.equal(checkRun(makeRun({ score, deltas, flags, values }), score), null);
  });
  for (const f of FX.forged as { name: string; deltas: number[]; flags: number[]; values: number[]; score?: number; expect: string | null }[]) {
    it(`§13.5 plausibility: ${f.name} → ${f.expect ?? 'accepted'}`, () => {
      const score = f.score ?? f.values.reduce((a, b) => a + b, 0);
      const r = makeRun({ score, deltas: f.deltas, flags: f.flags, values: f.values });
      assert.equal(checkRun(r, score), f.expect);
    });
  }
  it('§3.13 best < score is rejected (entry best and player best)', () => {
    assert.equal(checkRun(makeRun({ score: 10, best: 9 }), 20), 'best_below_score');
    assert.equal(checkRun(makeRun({ score: 10, best: 10 }), 9), 'best_below_score');
  });
});

describe('PRD-2.2 §13.5 v1 → v2 pool conversion', () => {
  it('§13.7 the fixture v1 run becomes the v2 run: value 1 per entry, same score, flags kept, same replay', () => {
    const fl = convertV1ToV2(FX.v1);
    assert.equal(fl, FX.v1Converted.fl);
    const converted = { ...makeRun({ score: FX.v1.score }), tl: FX.v1.tl, fl: fl!, end: FX.v1.end };
    assert.equal(checkRun(converted, 99), null);
    for (const [cs, score] of FX.v1Replay as [number, number][]) {
      assert.equal(scoreAt(FX.v1.tl, fl!, cs), score, `at ${cs} cs`);
    }
    assert.deepEqual(decodeEntries(fl!)!.flags, Array.from(Buffer.from(FX.v1.fl, 'base64')));
  });
  it('§13.5 idempotent: a v2 run is left alone; a malformed run is skipped', () => {
    assert.equal(convertV1ToV2(FX.v1Converted), null);
    assert.equal(convertV1ToV2(FX.run), null);
    assert.equal(convertV1ToV2({ tl: FX.v1.tl, fl: encodeEntries([0], [1]).slice(0, 4) }), null);
  });
});
