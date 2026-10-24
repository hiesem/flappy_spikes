/**
 * PRD-2.5 §3.6 WP-VERSUS anomaly signals (owner decision D3: flag only —
 * a flagged run is pooled exactly as before; the flag is a log + a
 * `versusFlags` doc for a human to review).
 *
 * Pure (no Firestore): [scoreRun] judges one run that already passed
 * `checkRun`, against the player's recent pass history. What a run carries
 * (schema.ts `RunEntry`): per timeline entry a cs delta, a flag byte and a
 * value; "passes" are the entries without the gift / bonus flag, the
 * duration is Σ deltas + `end`.
 *
 * Signals (thresholds in schema.ts):
 * - `streak_jump` (hard): a pass worth more than max(previous pass + 3, 8)
 *   (PRD: + 2, 7; one point of headroom, see schema.ts);
 * - `pace` (hard): median gap between consecutive plain passes < 1.32 s
 *   over ≥ 10 gaps;
 * - `passes` (hard): more passes than the scroll can bring even if every
 *   slot were a 3-ring train;
 * - `jump` (soft): passes ≥ 150 and > 4 × the median of ≥ 5 earlier pass
 *   counts (PRD-2.6 E6; points jump on honest progress as the streak grows).
 */
import {
  FLAG_BONUS,
  FLAG_GIFT,
  JUMP_MIN_HISTORY,
  JUMP_MIN_PASSES,
  JUMP_PASS_FACTOR,
  PACE_MIN_GAPS,
  PACE_MIN_MEDIAN_CS,
  PASS_EXTRA,
  PASS_MAX_SPEED,
  PASS_RINGS_PER_SLOT,
  PASS_SPACING,
  RunEntry,
  STREAK_FLOOR_MAX,
  STREAK_STEP_MAX,
} from './schema.js';
import { decodeDeltas, decodeEntries } from './timeline.js';

export type Signal = 'streak_jump' | 'pace' | 'passes' | 'jump';

export interface Anomaly {
  /** Signal → the measured value (the offending pass value, the median gap cs, the pass count, the history median). */
  signals: Partial<Record<Signal, number>>;
  /** Only the soft `jump` fired. */
  soft: boolean;
  durationCs: number;
  passes: number;
}

/** Facts of a run's timeline the signals use (null for a malformed run). */
export interface RunFacts {
  durationCs: number;
  passes: number;
  /** The first pass whose value breaks the streak rule (null if none). */
  streakJump: number | null;
  /** Median gap between consecutive plain passes (cs) and how many gaps there were. */
  paceMedianCs: number | null;
  paceGaps: number;
  /** The `passes` bound for this duration. */
  passBound: number;
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 === 1 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** Whether an entry with flag byte [f] is a pass (not a pair gift, not a coin bonus). */
export function isPass(f: number): boolean {
  return (f & (FLAG_GIFT | FLAG_BONUS)) === 0;
}

/** Most passes a run of [durationCs] can honestly hold. */
export function passBound(durationCs: number): number {
  const slots = Math.ceil(((durationCs / 100) * PASS_MAX_SPEED) / PASS_SPACING);
  return PASS_RINGS_PER_SLOT * slots + PASS_EXTRA;
}

export function runFacts(run: RunEntry): RunFacts | null {
  const deltas = decodeDeltas(run.tl);
  const meta = decodeEntries(run.fl);
  if (deltas === null || meta === null || meta.flags.length !== deltas.length) return null;
  let t = 0;
  let passes = 0;
  let prevPass = 0;
  let streakJump: number | null = null;
  let lastPlain: number | null = null;
  const gaps: number[] = [];
  for (let i = 0; i < deltas.length; i++) {
    t += deltas[i];
    const f = meta.flags[i];
    const v = meta.values[i];
    if (!isPass(f)) continue;
    passes++;
    if (streakJump === null && v > Math.max(prevPass + STREAK_STEP_MAX, STREAK_FLOOR_MAX)) streakJump = v;
    prevPass = v;
    if (f === 0) {
      if (lastPlain !== null) gaps.push(t - lastPlain);
      lastPlain = t;
    }
  }
  const durationCs = t + (Number.isFinite(run.end) ? run.end : 0);
  return {
    durationCs,
    passes,
    streakJump,
    paceMedianCs: gaps.length > 0 ? median(gaps) : null,
    paceGaps: gaps.length,
    passBound: passBound(durationCs),
  };
}

/**
 * The anomaly of [run] (already accepted by `checkRun`), or null for an
 * unremarkable run. [passHist] = the player's earlier pass counts (oldest
 * first). Score history is deliberately not used: the uncapped streak makes
 * honest points jump as a player improves.
 */
export function scoreRun(run: RunEntry, passHist: number[]): Anomaly | null {
  const facts = runFacts(run);
  if (facts === null) return null;
  const signals: Partial<Record<Signal, number>> = {};
  if (facts.streakJump !== null) signals.streak_jump = facts.streakJump;
  if (facts.paceGaps >= PACE_MIN_GAPS && facts.paceMedianCs !== null && facts.paceMedianCs < PACE_MIN_MEDIAN_CS) {
    signals.pace = facts.paceMedianCs;
  }
  if (facts.passes > facts.passBound) signals.passes = facts.passes;
  const h = passHist.filter((x) => Number.isInteger(x) && x >= 0);
  if (facts.passes >= JUMP_MIN_PASSES && h.length >= JUMP_MIN_HISTORY) {
    const m = median(h);
    if (facts.passes > JUMP_PASS_FACTOR * m) signals.jump = m;
  }
  const names = Object.keys(signals);
  if (names.length === 0) return null;
  return {
    signals,
    soft: names.every((n) => n === 'jump'),
    durationCs: facts.durationCs,
    passes: facts.passes,
  };
}
