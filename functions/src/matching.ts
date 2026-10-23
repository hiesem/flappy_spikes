/**
 * Reference matcher (PRD-2 §3.13 "Matching", ARCH §6.4). Not deployed logic:
 * the Dart client (`lib/versus/matcher.dart`, WP-5b) must give the same
 * answers on the shared fixture `test/fixtures/versus_matching.json`.
 */
import { MAX_BRACKET, poolId, SHARDS } from './schema.js';

export interface MatchEntry {
  uid: string;
  runId: string;
  score: number;
  level: number;
  /** PRD-2.3 §21.4 hashed Play Games id ('' / absent = none). */
  pg?: string;
}

export interface Me {
  uid: string;
  best: number;
  level: number;
  /** PRD-2.3 §21.4 my hashed Play Games id ('' / absent = none). */
  pg?: string;
}

/** PRD-2.3 §25.2 adds 'rematch': every run that is not mine was met; the one met longest ago. */
export type Tier = 'level' | 'any' | 'rematch' | 'solo';

/** PRD-2.3 §21.4 not my uid and, when I have a pg, not my pg under another uid. */
export function isOtherPlayer(e: MatchEntry, me: { uid: string; pg?: string }): boolean {
  const myPg = me.pg ?? '';
  return e.uid !== me.uid && (myPg === '' || (e.pg ?? '') !== myPg);
}

/** PRD-2.3 §25.2 the run id in `pool` met longest ago (`met` is ordered oldest first). */
export function metLongestAgo(pool: MatchEntry[], met: Iterable<string>): string | null {
  const ids = new Set(pool.map((e) => e.runId));
  for (const id of met) if (ids.has(id)) return id;
  return null;
}

/**
 * The candidates the client picks from at random (PRD-2.3 §25.2): among the
 * runs that are not mine and not met yet, 1. same level and score below my
 * best; else 2. any of them; else 3. the run met longest ago (rematch); else
 * solo (only my own runs, or nothing).
 */
export function matchCandidates(
  pool: MatchEntry[],
  me: Me,
  met: Iterable<string>,
): { tier: Tier; candidates: MatchEntry[] } {
  const metList = [...met];
  const metSet = new Set(metList);
  const open = pool.filter((e) => isOtherPlayer(e, me));
  const fresh = open.filter((e) => !metSet.has(e.runId));
  const atLevel = fresh.filter((e) => e.level === me.level && e.score < me.best);
  if (atLevel.length) return { tier: 'level', candidates: atLevel };
  if (fresh.length) return { tier: 'any', candidates: fresh };
  const oldest = metLongestAgo(open, metList);
  if (oldest !== null) return { tier: 'rematch', candidates: [open.find((e) => e.runId === oldest)!] };
  return { tier: 'solo', candidates: [] };
}

export function pickOpponent(
  pool: MatchEntry[],
  me: Me,
  met: Iterable<string>,
  rand: () => number = Math.random,
): MatchEntry | null {
  const { candidates } = matchCandidates(pool, me, met);
  if (!candidates.length) return null;
  return candidates[Math.min(candidates.length - 1, Math.floor(rand() * candidates.length))];
}

/** PRD-2.2 §3: at most every shard of every level per search (44). */
export const MAX_SEARCH_READS = (MAX_BRACKET + 1) * SHARDS;

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
 * first (distance 1, 2, … up to MAX_BRACKET; at each distance the lower bracket
 * before the higher one), every shard of each level in random order. Every
 * pool document exactly once (≤ MAX_SEARCH_READS).
 */
export function poolSearchOrder(level: number, rand: () => number = Math.random): string[] {
  const own = Math.max(0, Math.min(MAX_BRACKET, level));
  const order = shardsOf(own, rand);
  for (let d = 1; d <= MAX_BRACKET; d++) {
    for (const l of [own - d, own + d]) {
      if (l >= 0 && l <= MAX_BRACKET) order.push(...shardsOf(l, rand));
    }
  }
  return order;
}

/** A usable opponent: a run that is not mine (met runs count: matchCandidates is not solo). */
export function hasUsableOpponent(pool: MatchEntry[], me: { uid: string; pg?: string }): boolean {
  return pool.some((e) => isOtherPlayer(e, me));
}

/** PRD-2.3 §25.2 a usable run not met yet (the search stops at the first round with one). */
export function hasFreshOpponent(pool: MatchEntry[], me: { uid: string; pg?: string }, met: Iterable<string>): boolean {
  const m = new Set(met);
  return pool.some((e) => isOtherPlayer(e, me) && !m.has(e.runId));
}

export interface PoolSearch {
  poolId: string | null;
  pool: MatchEntry[];
  reads: number;
}

/**
 * PRD-2.2 §3 / PRD-2.3 §25.2 reads the pools in `order` in rounds of
 * `parallel` documents (the 4 shards of a level read together) and stops
 * after the first round holding a usable run not met yet (the first such
 * document in `order` wins). If the whole search finds only met runs, the
 * document holding the one met longest ago is the result (a rematch). At
 * most `maxReads` reads. `pools` maps a pool id to its entries (a missing
 * id = an empty / absent document).
 */
export function searchPools(
  order: string[],
  pools: Record<string, MatchEntry[] | undefined>,
  me: Me,
  met: Iterable<string>,
  maxReads: number = MAX_SEARCH_READS,
  parallel: number = SHARDS,
): PoolSearch {
  const metList = [...met];
  const metIndex = new Map(metList.map((id, i) => [id, i] as const));
  let reads = 0;
  let fallback: { id: string; pool: MatchEntry[]; age: number } | null = null;
  const step = Math.max(1, parallel);
  for (let i = 0; i < order.length; i += step) {
    if (reads >= maxReads) break;
    const round = order.slice(i, i + step).slice(0, maxReads - reads);
    reads += round.length;
    for (const id of round) {
      const entries = pools[id] ?? [];
      if (hasFreshOpponent(entries, me, metList)) return { poolId: id, pool: entries, reads };
    }
    for (const id of round) {
      const entries = pools[id] ?? [];
      for (const e of entries) {
        if (!isOtherPlayer(e, me)) continue;
        const age = metIndex.get(e.runId);
        if (age !== undefined && (fallback === null || age < fallback.age)) fallback = { id, pool: entries, age };
      }
    }
  }
  return fallback ? { poolId: fallback.id, pool: fallback.pool, reads } : { poolId: null, pool: [], reads };
}
