/** §3.13 cheat filter and timeline codec (pure, no emulator writes). */
import assert from 'node:assert/strict';
import { checkRun, decodeDeltas, encodeDeltas, scoreAt } from '../src/timeline.js';
import { FLAG_GIFT, FLAG_RIDE, FLAG_TRAIN } from '../src/schema.js';
import { makeRun } from './helpers.js';

describe('§3.13 timeline codec', () => {
  it('§3.13 tl round-trips uint16 LE centisecond deltas through base64', () => {
    const d = [0, 1, 90, 255, 256, 65535];
    assert.deepEqual(decodeDeltas(encodeDeltas(d)), d);
  });
  it('§3.13 malformed base64 or an odd byte count does not decode', () => {
    assert.equal(decodeDeltas('abc'), null);
    assert.equal(decodeDeltas('AA=='), null); // 1 byte: not a whole uint16
  });
  it('§3.13 scoreAt replays the timeline on run time', () => {
    const tl = encodeDeltas([100, 120, 0]);
    assert.equal(scoreAt(tl, 99), 0);
    assert.equal(scoreAt(tl, 100), 1);
    assert.equal(scoreAt(tl, 219), 1);
    assert.equal(scoreAt(tl, 220), 3);
  });
});

describe('§3.13 cheat filter (checkRun)', () => {
  it('§3.13 a plain run with points ≥ 0.9 s apart passes', () => {
    assert.equal(checkRun(makeRun({ score: 10 }), 10), null);
  });
  it('§3.13 malformed display fields are rejected (the function re-checks what the rules bound loosely)', () => {
    assert.equal(checkRun({ ...makeRun(), look: { bird: 'x'.repeat(41), gear: '', hat: '', hoop: '', trail: '' } }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), look: { bird: 1 } as any }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), name: '' }, 99), 'shape');
    assert.equal(checkRun({ ...makeRun(), platform: 'web' as any }, 99), 'shape');
  });
  it('§3.13 runs under score 3 are rejected', () => {
    assert.equal(checkRun(makeRun({ score: 2 }), 10), 'low_score');
  });
  it('§3.13 timeline length ≠ score is rejected', () => {
    const r = makeRun({ score: 10, deltas: Array(9).fill(120) });
    assert.equal(checkRun(r, 10), 'count');
  });
  it('§3.13 fl length ≠ tl length is rejected', () => {
    const r = makeRun({ score: 5, flags: [0, 0, 0] });
    assert.equal(checkRun(r, 5), 'timeline');
  });
  it('§3.13 two plain points < 0.9 s apart are rejected', () => {
    assert.equal(checkRun(makeRun({ score: 5, deltas: [120, 120, 89, 120, 120] }), 5), 'gap');
    assert.equal(checkRun(makeRun({ score: 5, deltas: [120, 120, 90, 120, 120] }), 5), null);
  });
  it('§3.13 the first point has no gap check (time from run start)', () => {
    assert.equal(checkRun(makeRun({ score: 4, deltas: [10, 120, 120, 120] }), 4), null);
  });
  it('§3.13 ride / train / gift points are exempt from the 0.9 s gap', () => {
    const deltas = [120, 30, 30, 120, 40, 120, 0, 0, 0, 0];
    const flags = [0, FLAG_RIDE, FLAG_RIDE, 0, FLAG_TRAIN, 0, FLAG_GIFT, FLAG_GIFT, FLAG_GIFT, FLAG_GIFT];
    assert.equal(checkRun(makeRun({ score: 10, deltas, flags }), 10), null);
  });
  it('§3.13 best < score is rejected (entry best and player best)', () => {
    assert.equal(checkRun(makeRun({ score: 10, best: 9 }), 20), 'best_below_score');
    assert.equal(checkRun(makeRun({ score: 10, best: 10 }), 9), 'best_below_score');
  });
});
