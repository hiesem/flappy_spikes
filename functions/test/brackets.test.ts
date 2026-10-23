/** ARCH §6.3: functions/src/brackets.ts must equal lib/versus/brackets.dart. */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { BEST_BRACKETS, bracketFor } from '../src/brackets.js';

function dartBrackets(): number[] {
  const dart = readFileSync(join(__dirname, '..', '..', 'lib', 'versus', 'brackets.dart'), 'utf8');
  const list = dart.match(/kBestBrackets\s*=\s*(?:const\s*)?\[([\s\S]*?)\];/);
  assert.ok(list, 'kBestBrackets found in lib/versus/brackets.dart');
  return [...list![1].matchAll(/\d+/g)].map((m) => Number(m[0]));
}

function bracketOf(best: number, brackets: readonly number[]): number {
  let bracket = 0;
  brackets.forEach((threshold, i) => {
    if (best >= threshold) bracket = i + 1;
  });
  return bracket;
}

describe('§3.13 best-score brackets (brackets.ts ↔ brackets.dart)', () => {
  it('§3.13 BEST_BRACKETS equals kBestBrackets in lib/versus/brackets.dart', () => {
    const dart = dartBrackets();
    assert.equal(dart.length, 10);
    assert.deepEqual([...BEST_BRACKETS], dart);
  });

  it('§3.13 bracketFor matches Dart bracketFor at every boundary (0–10)', () => {
    const dart = dartBrackets();
    const cases = [0, ...dart.flatMap((t) => [t - 1, t]), dart[dart.length - 1] + 1];
    for (const best of cases) {
      assert.equal(bracketFor(best), bracketOf(best, dart), `best ${best}`);
    }
    assert.equal(bracketFor(0), 0);
    assert.equal(bracketFor(24), 0);
    assert.equal(bracketFor(25), 1);
    assert.equal(bracketFor(49), 1);
    assert.equal(bracketFor(50), 2);
    assert.equal(bracketFor(4999), 9);
    assert.equal(bracketFor(5000), 10);
    assert.equal(bracketFor(99999), 10);
  });
});
