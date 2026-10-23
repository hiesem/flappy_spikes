/**
 * PRD-2.6 E4 best-score brackets (R3): the pool brackets are decoupled from
 * the player level, but the thresholds and ids stay unchanged. Must equal
 * `kBestBrackets` in `lib/versus/brackets.dart`; `brackets.test.ts` parses
 * the Dart file and compares (ARCH §6.3).
 */
export const BEST_BRACKETS: readonly number[] = [
  25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000,
];

/** Highest bracket whose threshold [best] reaches; 0 = unranked. Mirrors Dart `bracketFor`. */
export function bracketFor(best: number): number {
  let bracket = 0;
  BEST_BRACKETS.forEach((threshold, i) => {
    if (best >= threshold) bracket = i + 1;
  });
  return bracket;
}
