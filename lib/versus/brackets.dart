/// PRD-2.6 E4 (R3) the best-score brackets of versus matching.
///
/// The thresholds are the 2.5 pool thresholds, unchanged; only the source
/// moved off the level table. Pool ids stay `{bracket}_{shard}`. Mirrored by
/// `BEST_BRACKETS` in `functions/src/brackets.ts` (parsed by the server test).
const kBestBrackets = [25, 50, 100, 200, 400, 600, 800, 1000, 2000, 5000];

/// Highest bracket whose threshold [best] reaches; 0 = unranked.
int bracketFor(int best) {
  var bracket = 0;
  for (var i = 0; i < kBestBrackets.length; i++) {
    if (best >= kBestBrackets[i]) bracket = i + 1;
  }
  return bracket;
}
