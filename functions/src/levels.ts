/**
 * Level thresholds of PRD-home-v3 §4.1 (EGG .. LEGEND). Must equal
 * `kLevels[i].threshold` in `lib/levels/levels.dart`; the emulator test
 * `levels.test.ts` parses the Dart file and compares (ARCH §6.3).
 */
export const LEVEL_THRESHOLDS: readonly number[] = [
  25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000,
];

/** Highest level whose threshold [best] reaches; 0 = unranked. Mirrors Dart `levelFor`. */
export function levelFor(best: number): number {
  let level = 0;
  LEVEL_THRESHOLDS.forEach((t, i) => {
    if (best >= t) level = i + 1;
  });
  return level;
}
