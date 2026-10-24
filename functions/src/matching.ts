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
  /** The best-score bracket stored in a pool entry's `level` field. */
  bracket: number;
  /** PRD-2.3 §21.4 hashed Play Games id ('' / absent = none). */
  pg?: string;
}

export interface Me {
  uid: string;
  best: number;
  /** PRD-2.6 E4 `bracketFor(best)`, never the player level. */
  bracket: number;
  /** PRD-2.3 §21.4 my hashed Play Games id ('' / absent = none). */
  pg?: string;
}

/** PRD-2.3 §25.2 adds 'rematch': every run that is not mine was met; the one met longest ago. */
export type Tier = 'bracket' | 'any' | 'rematch' | 'solo';

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
 * runs that are not mine and not met yet, 1. same bracket and score below my
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
  const atBracket = fresh.filter((e) => e.bracket === me.bracket && e.score < me.best);
  if (atBracket.length) return { tier: 'bracket', candidates: atBracket };
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

/** PRD-2.2 §3: at most every shard of every bracket per search (44). */
export const MAX_SEARCH_READS = (MAX_BRACKET + 1) * SHARDS;

function shardsOf(bracket: number, rand: () => number): string[] {
  const s = Array.from({ length: SHARDS }, (_, i) => i);
  for (let i = s.length - 1; i > 0; i--) {
    const j = Math.min(i, Math.floor(rand() * (i + 1)));
    [s[i], s[j]] = [s[j], s[i]];
  }
  return s.map((x) => poolId(bracket, x));
}

/**
 * PRD-2.2 §3 the opponent search order (replaces the 2.1 `poolReadPlan`):
 * all shards of my own bracket in random order, then the other brackets nearest
 * first (distance 1, 2, … up to MAX_BRACKET; at each distance the lower bracket
 * before the higher one), every shard of each bracket in random order. Every
 * pool document exactly once (≤ MAX_SEARCH_READS).
 */
export function poolSearchOrder(bracket: number, rand: () => number = Math.random): string[] {
  const own = Math.max(0, Math.min(MAX_BRACKET, bracket));
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

/** PRD-2.6 E5 `duelStep` starts here and may move within [−4, +8]. */
export const DUEL_STEP_START = -2;
export const DUEL_STEP_MIN = -4;
export const DUEL_STEP_MAX = 8;

/** The three duel outcomes; only the result moves the staircase (WP-E E5). */
export type DuelOutcome = 'win' | 'loss' | 'draw';

/** Which rule of E5 picked the opponent inside the found pool document. */
export type DuelPickTier = 'band' | 'closest' | 'rematch' | 'solo';

export interface DuelPick {
  tier: DuelPickTier;
  /** The chosen run, or null for solo. */
  entry: MatchEntry | null;
  /** The target score T = clamp(0.8 + 0.1·duelStep, 0.4, 1.6) × median(recentScores). */
  target: number;
}

function clamp(x: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, x));
}

/** Arithmetic median of the last 10 scores; 0 for an empty history. */
export function duelMedian(recentScores: readonly number[]): number {
  const s = recentScores.slice(-10).sort((a, b) => a - b);
  if (!s.length) return 0;
  const mid = s.length >> 1;
  return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/** PRD-2.6 E5: the step after a duel result (draw leaves it unchanged). */
export function duelStepAfter(step: number, result: DuelOutcome): number {
  const delta = result === 'win' ? 1 : result === 'loss' ? -2 : 0;
  return clamp(step + delta, DUEL_STEP_MIN, DUEL_STEP_MAX);
}

/** PRD-2.6 E5: T = clamp(0.8 + 0.1·duelStep, 0.4, 1.6) × median(recentScores). */
export function duelTarget(step: number, recentScores: readonly number[]): number {
  return duelTargetTenths(step, recentScores) / 10;
}

function duelTargetTenths(step: number, recentScores: readonly number[]): number {
  // Scores are integers, so their median is an integer or half-integer.
  // Keep the factor in tenths until the final division to avoid rounding
  // 0.8 + 0.1 * -2 above 0.6 (and excluding an inclusive band endpoint).
  return clamp(8 + step, 4, 16) * duelMedian(recentScores);
}

/**
 * PRD-2.6 E5 the pick inside the found pool document: a fresh run in the
 * target band [0.75T, 1.25T], else the closest fresh run, else a rematch
 * (the run met longest ago), else solo. `met` is ordered oldest first.
 * This is reference logic only: the live client performs the pick; the
 * deployed server matcher (`matchCandidates` / `pickOpponent`) is unchanged.
 */
export function pickDuelOpponent(
  pool: MatchEntry[],
  me: { uid: string; pg?: string },
  step: number,
  recentScores: readonly number[],
  met: Iterable<string>,
  rand: () => number = Math.random,
): DuelPick {
  const targetTenths = duelTargetTenths(step, recentScores);
  const target = targetTenths / 10;
  const lo = (3 * targetTenths) / 40;
  const hi = (5 * targetTenths) / 40;
  const metList = [...met];
  const metSet = new Set(metList);
  const open = pool.filter((e) => isOtherPlayer(e, me));
  const fresh = open.filter((e) => !metSet.has(e.runId));
  const inBand = fresh.filter((e) => e.score >= lo && e.score <= hi);
  if (inBand.length) {
    return {
      tier: 'band',
      entry: inBand[Math.min(inBand.length - 1, Math.floor(rand() * inBand.length))],
      target,
    };
  }
  if (fresh.length) {
    let closest = fresh[0];
    for (const e of fresh.slice(1)) {
      if (Math.abs(e.score - target) < Math.abs(closest.score - target)) closest = e;
    }
    return { tier: 'closest', entry: closest, target };
  }
  const oldest = metLongestAgo(open, metList);
  if (oldest !== null) {
    return { tier: 'rematch', entry: open.find((e) => e.runId === oldest)!, target };
  }
  return { tier: 'solo', entry: null, target };
}

/**
 * PRD-2.2 §3 / PRD-2.3 §25.2 reads the pools in `order` in rounds of
 * `parallel` documents (the 4 shards of a bracket read together) and stops
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
