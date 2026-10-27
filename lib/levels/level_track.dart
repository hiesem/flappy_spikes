import 'levels.dart';

/// PRD-2.6 J3: one step per finished, eligible run. The caller filters
/// debug runs and never calls this for a killed run (J2).
abstract final class LevelTrack {
  static ({int index, int points, bool levelledUp, int surplus}) step(
    int index,
    int points,
    int score,
  ) {
    if (index < 0 || points < 0 || score < 0) {
      throw ArgumentError('Level index, points and score must be nonnegative');
    }
    final total = points + score;
    final need = needFor(index);
    if (total < need) {
      return (index: index, points: total, levelledUp: false, surplus: 0);
    }
    return (
      index: index + 1,
      points: 0,
      levelledUp: true,
      surplus: total - need,
    );
  }
}
