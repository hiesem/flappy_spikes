/**
 * §3.13 matching: the reference matcher against the fixture shared with the
 * Dart matcher (test/fixtures/versus_matching.json), plus matching on pools the
 * real function built (level, shards, no self-match).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { matchCandidates, pickOpponent, poolReadPlan, MatchEntry } from '../src/matching.js';
import { processPlayerWrite } from '../src/pools.js';
import { poolId, SHARDS } from '../src/schema.js';
import { db, makePlayer, makeRun, poolEntries, uniq } from './helpers.js';

const fixture = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'test', 'fixtures', 'versus_matching.json'), 'utf8'),
) as { cases: Array<{ name: string; me: any; seen: string[]; pool: MatchEntry[]; expect: { tier: string; runIds: string[] } }> };

describe('§3.13 matching fixture (shared with the Dart matcher)', () => {
  for (const c of fixture.cases) {
    it(`§3.13 ${c.name}`, () => {
      const r = matchCandidates(c.pool, c.me, c.seen);
      assert.equal(r.tier, c.expect.tier);
      assert.deepEqual(r.candidates.map((e) => e.runId).sort(), [...c.expect.runIds].sort());
      const pick = pickOpponent(c.pool, c.me, c.seen, () => 0.999);
      if (c.expect.tier === 'solo') assert.equal(pick, null);
      else assert.ok(c.expect.runIds.includes(pick!.runId));
    });
  }
});

describe('§3.13 pool read plan', () => {
  it('§3.13 reads its own level first, then a random other level', () => {
    for (let level = 0; level <= 10; level++) {
      for (const r of [0, 0.3, 0.6, 0.999]) {
        const plan = poolReadPlan(level, () => r);
        assert.match(plan.first, new RegExp(`^${level}_[0-3]$`));
        const other = Number(plan.fallback.split('_')[0]);
        assert.notEqual(other, level);
        assert.ok(other >= 0 && other <= 10);
      }
    }
  });
});

describe('§3.13 matching on server-built pools', () => {
  const level = 2; // best 50..99
  it('§3.13 runs land in a shard of the uploader level; all 4 shards are used; no self-match', async () => {
    const me = uniq('me');
    const others: string[] = [];
    // One run per shard from others, plus one of mine in shard 0.
    for (let s = 0; s < SHARDS; s++) {
      const uid = uniq(`opp${s}`);
      others.push(uid);
      const run = makeRun({ score: 60 });
      await processPlayerWrite(db, uid, undefined, makePlayer({ best: 60, bestRun: run, recent: [run] }), {
        rand: () => (s + 0.5) / SHARDS,
      });
    }
    const mine = makeRun({ score: 70 });
    await processPlayerWrite(db, me, undefined, makePlayer({ best: 70, bestRun: mine, recent: [mine] }), {
      rand: () => 0,
    });
    for (let s = 0; s < SHARDS; s++) {
      const entries = await poolEntries(poolId(level, s));
      assert.ok(entries.some((e) => e.uid === others[s]), `shard ${s} holds opp${s}`);
      assert.ok(entries.every((e) => e.level === level));
    }
    const shard0 = (await poolEntries(poolId(level, 0))) as MatchEntry[];
    assert.ok(shard0.some((e) => e.uid === me));
    const r = matchCandidates(shard0, { uid: me, best: 70, level }, []);
    assert.equal(r.tier, 'level');
    assert.ok(r.candidates.every((e) => e.uid !== me));
    assert.ok(r.candidates.some((e) => e.uid === others[0]));
  });
});
