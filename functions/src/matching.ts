/**
 * Reference matcher (PRD-2 §3.13 "Matching", ARCH §6.4). Not deployed logic:
 * the Dart client (`lib/versus/matcher.dart`, WP-5b) must give the same
 * answers on the shared fixture `test/fixtures/versus_matching.json`.
 */
import { MAX_LEVEL, poolId, SHARDS } from './schema.js';

export interface MatchEntry {
  uid: string;
  runId: string;
  score: number;
  level: number;
}

export interface Me {
  uid: string;
  best: number;
  level: number;
}

export type Tier = 'level' | 'any' | 'solo';

/**
 * The candidates the client picks from at random:
 * 1. same level and score below my best; else 2. any run; else solo.
 * Never my own runs, never a run already met this session.
 */
export function matchCandidates(
  pool: MatchEntry[],
  me: Me,
  seenRunIds: Iterable<string>,
): { tier: Tier; candidates: MatchEntry[] } {
  const seen = new Set(seenRunIds);
  const open = pool.filter((e) => e.uid !== me.uid && !seen.has(e.runId));
  const atLevel = open.filter((e) => e.level === me.level && e.score < me.best);
  if (atLevel.length) return { tier: 'level', candidates: atLevel };
  if (open.length) return { tier: 'any', candidates: open };
  return { tier: 'solo', candidates: [] };
}

export function pickOpponent(
  pool: MatchEntry[],
  me: Me,
  seenRunIds: Iterable<string>,
  rand: () => number = Math.random,
): MatchEntry | null {
  const { candidates } = matchCandidates(pool, me, seenRunIds);
  if (!candidates.length) return null;
  return candidates[Math.min(candidates.length - 1, Math.floor(rand() * candidates.length))];
}

/** PRD-2.2 §3: at most every shard of every level per search (44). */
export const MAX_SEARCH_READS = (MAX_LEVEL + 1) * SHARDS;

function shardsOf(level: number, rand: () => number): string[] {
  const s = Array.from({ length: SHARDS }, (_, i) => i);
  for (let i = s.length - 1; i > 0; i--) {
    const j = Math.min(i, Math.floor(rand() * (i + 1)));
    [s[i], s[j]] = [s[j], s[i]];
  }
  return s.map((x) => poolId(level, x));
}

/**
 * PRD-2.2 §3 the opponent search order (replaces the 2.1 `poolReadPlan`):
 * all shards of my own level in random order, then the other levels nearest
 * first (distance 1, 2, … up to MAX_LEVEL; at each distance the lower level
 * before the higher one), every shard of each level in random order. Every
 * pool document exactly once (≤ MAX_SEARCH_READS).
 */
export function poolSearchOrder(level: number, rand: () => number = Math.random): string[] {
  const own = Math.max(0, Math.min(MAX_LEVEL, level));
  const order = shardsOf(own, rand);
  for (let d = 1; d <= MAX_LEVEL; d++) {
    for (const l of [own - d, own + d]) {
      if (l >= 0 && l <= MAX_LEVEL) order.push(...shardsOf(l, rand));
    }
  }
  return order;
}

/** A usable opponent: not mine, not met this session (matchCandidates is not solo). */
export function hasUsableOpponent(pool: MatchEntry[], myUid: string, seenRunIds: Iterable<string>): boolean {
  const seen = new Set(seenRunIds);
  return pool.some((e) => e.uid !== myUid && !seen.has(e.runId));
}

export interface PoolSearch {
  poolId: string | null;
  pool: MatchEntry[];
  reads: number;
}

/**
 * PRD-2.2 §3 reads the pools in `order` and stops at the first one with a
 * usable opponent; at most `maxReads` reads. `pools` maps a pool id to its
 * entries (a missing id = an empty / absent document).
 */
export function searchPools(
  order: string[],
  pools: Record<string, MatchEntry[] | undefined>,
  me: Me,
  seenRunIds: Iterable<string>,
  maxReads: number = MAX_SEARCH_READS,
): PoolSearch {
  const seen = [...seenRunIds];
  let reads = 0;
  for (const id of order) {
    if (reads >= maxReads) break;
    reads++;
    const entries = pools[id] ?? [];
    if (hasUsableOpponent(entries, me.uid, seen)) return { poolId: id, pool: entries, reads };
  }
  return { poolId: null, pool: [], reads };
}
