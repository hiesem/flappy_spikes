/**
 * PRD-2.6 E4 best-score brackets (R3): the pool brackets are decoupled from
 * the player level, but the thresholds and ids stay unchanged.
 *
 * Wave-0 stub: this bridge keeps the deployed matcher's exact behaviour until
 * the bracket work package moves the table here and removes `levelFor`.
 */
import { LEVEL_THRESHOLDS, levelFor } from './levels.js';

export const BEST_BRACKETS: readonly number[] = LEVEL_THRESHOLDS;

/** Highest bracket whose threshold [best] reaches; 0 = unranked. */
export const bracketFor: (best: number) => number = levelFor;
