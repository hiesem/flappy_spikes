/** PRD-2.6 WP-LB: server limits mirror the Dart client and the approved fixture. */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { LB_GIFTS, LB_MAX_SCORE } from '../src/schema.js';

const ROOT = join(__dirname, '..', '..');

describe('PRD-2.6 WP-LB limit mirrors', () => {
  it('LB_MAX_SCORE equals kLeaderboardMaxScore in lib/services/leaderboard_limits.dart', () => {
    const dart = readFileSync(join(ROOT, 'lib', 'services', 'leaderboard_limits.dart'), 'utf8');
    const match = /const\s+int\s+kLeaderboardMaxScore\s*=\s*(\d+)\s*;/.exec(dart);
    assert.ok(match, 'kLeaderboardMaxScore is present');
    assert.equal(LB_MAX_SCORE, Number(match[1]));
  });

  it('test/fixtures/lb_gifts.json equals LB_GIFTS exactly', () => {
    const fixture = JSON.parse(readFileSync(join(ROOT, 'test', 'fixtures', 'lb_gifts.json'), 'utf8'));
    assert.deepEqual(fixture, LB_GIFTS);
  });
});
