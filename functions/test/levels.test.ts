/** ARCH §6.3: functions/src/levels.ts thresholds must equal lib/levels/levels.dart. */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { LEVEL_THRESHOLDS, levelFor } from '../src/levels.js';

describe('§3.13 level recompute (levels.ts ↔ levels.dart)', () => {
  it('§3.13 thresholds equal kLevels in lib/levels/levels.dart', () => {
    const dart = readFileSync(join(__dirname, '..', '..', 'lib', 'levels', 'levels.dart'), 'utf8');
    const list = dart.slice(dart.indexOf('const List<LevelDef> kLevels'));
    const levels = [...list.matchAll(/level:\s*(\d+),[\s\S]*?threshold:\s*(\d+),/g)].map((m) => [
      Number(m[1]),
      Number(m[2]),
    ]);
    assert.equal(levels.length, 10);
    assert.deepEqual(
      levels.map((l) => l[0]),
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
    );
    assert.deepEqual(
      levels.map((l) => l[1]),
      [...LEVEL_THRESHOLDS],
    );
  });
  it('§3.13 levelFor matches Dart levelFor at the boundaries', () => {
    assert.equal(levelFor(0), 0);
    assert.equal(levelFor(24), 0);
    assert.equal(levelFor(25), 1);
    assert.equal(levelFor(49), 1);
    assert.equal(levelFor(50), 2);
    assert.equal(levelFor(4999), 9);
    assert.equal(levelFor(5000), 10);
    assert.equal(levelFor(99999), 10);
  });
});
