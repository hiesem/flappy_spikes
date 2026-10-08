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

/**
 * The pool document the client reads first (own level, random shard) and the
 * fallback on a miss (a random shard of a random other level).
 */
export function poolReadPlan(level: number, rand: () => number = Math.random): { first: string; fallback: string } {
  const shard = () => Math.min(SHARDS - 1, Math.floor(rand() * SHARDS));
  const first = poolId(level, shard());
  let other = Math.min(MAX_LEVEL - 1, Math.floor(rand() * MAX_LEVEL));
  if (other >= level) other++;
  return { first, fallback: poolId(other, shard()) };
}
