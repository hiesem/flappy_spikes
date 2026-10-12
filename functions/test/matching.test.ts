/**
 * §3.13 matching: the reference matcher against the fixture shared with the
 * Dart matcher (test/fixtures/versus_matching.json), plus matching on pools the
 * real function built (level, shards, no self-match).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  matchCandidates,
  pickOpponent,
  poolSearchOrder,
  searchPools,
  MAX_SEARCH_READS,
  MatchEntry,
} from '../src/matching.js';
import { MAX_LEVEL, poolId, SHARDS } from '../src/schema.js';
import { makePlayer, makeRun, poolEntries, processLive, uniq } from './helpers.js';

const fixture = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'test', 'fixtures', 'versus_matching.json'), 'utf8'),
) as {
  cases: Array<{ name: string; me: any; seen: string[]; pool: MatchEntry[]; expect: { tier: string; runIds: string[] } }>;
  search: Array<{
    name: string;
    me: any;
    seen: string[];
    pools: Record<string, MatchEntry[]>;
    expect: { pool: string | null; tier: string; runIds: string[]; minReads: number; maxReads: number };
  }>;
};

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

describe('PRD-2.2 §3 search order', () => {
  const levelOf = (id: string) => Number(id.split('_')[0]);
  it('§3 every shard of my level first, then the other levels nearest first (lower before higher); 44 ids, each once', () => {
    for (let level = 0; level <= MAX_LEVEL; level++) {
      for (const seed of [0, 0.3, 0.6, 0.999]) {
        let x = seed;
        const rand = () => (x = (x * 9301 + 0.49297) % 1);
        const order = poolSearchOrder(level, rand);
        assert.equal(order.length, MAX_SEARCH_READS);
        assert.equal(MAX_SEARCH_READS, 44);
        assert.equal(new Set(order).size, 44);
        assert.deepEqual(order.slice(0, SHARDS).map(levelOf), [level, level, level, level]);
        const levels = order.map(levelOf).filter((_, i) => i % SHARDS === 0);
        for (let i = 0; i < order.length; i++) assert.equal(levelOf(order[i]), levels[Math.floor(i / SHARDS)]);
        for (let i = 1; i < levels.length; i++) {
          const a = Math.abs(levels[i - 1] - level);
          const b = Math.abs(levels[i] - level);
          assert.ok(a < b || (a === b && levels[i - 1] < levels[i]), `nearest first at ${i}: ${levels}`);
        }
      }
    }
  });
});

describe('PRD-2.2 §3 search fixture (shared with the Dart matcher)', () => {
  for (const c of fixture.search) {
    it(`§3 ${c.name}`, () => {
      for (const seed of [0.01, 0.37, 0.73, 0.99]) {
        let x = seed;
        const rand = () => (x = (x * 9301 + 0.49297) % 1);
        const order = poolSearchOrder(c.me.level, rand);
        const r = searchPools(order, c.pools, c.me, c.seen);
        assert.equal(r.poolId, c.expect.pool);
        assert.ok(r.reads >= c.expect.minReads && r.reads <= c.expect.maxReads, `reads ${r.reads}`);
        assert.ok(r.reads <= MAX_SEARCH_READS);
        const m = matchCandidates(r.pool, c.me, c.seen);
        assert.equal(m.tier, c.expect.tier);
        assert.deepEqual(m.candidates.map((e) => e.runId).sort(), [...c.expect.runIds].sort());
      }
    });
  }

  it('§3 the read cap stops a search early', () => {
    const order = poolSearchOrder(3, () => 0.5);
    const r = searchPools(order, {}, { uid: 'me', best: 0, level: 3 }, [], 5);
    assert.equal(r.reads, 5);
    assert.equal(r.poolId, null);
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
      await processLive(uid, undefined, makePlayer({ best: 60, bestRun: run, recent: [run] }), {
        rand: () => (s + 0.5) / SHARDS,
      });
    }
    const mine = makeRun({ score: 70 });
    await processLive(me, undefined, makePlayer({ best: 70, bestRun: mine, recent: [mine] }), {
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
