import 'dart:ui';

import '../run/config/tuning_values.dart';

/// One bird rank of PRD-home-v3 §4.1 (owner 2026-10-17: reached one step
/// per run, see [levelAfterRun]), with its
/// emblem colours from §4.2 / `design/menu_v2/emblem_art.js` (LEVELS).
class LevelDef {
  const LevelDef({
    required this.level,
    required this.name,
    required this.threshold,
    required int reward,
    required this.plate,
    required this.rim,
    required this.accent,
    this.plateGradient,
  }) : defaultReward = reward;

  /// 1..10.
  final int level;

  /// Rank name as shown ("SPIKE ACE").
  final String name;

  /// The score a single run needs to step up to this level from the one
  /// below it (owner 2026-10-17; it used to be the best score).
  final int threshold;

  /// The in-app default of [reward] (PRD-home-v3 §4.1).
  final int defaultReward;

  /// One-time coin reward for reaching it (PRD-2.3 §15.1: tunable,
  /// `level_rewards[level − 1]`; the defaults are unchanged, §14.2).
  int get reward {
    final l = TuningValues.current.ints('level_rewards');
    return level - 1 < l.length ? l[level - 1] : defaultReward;
  }

  /// Flat plate colour (`plate` in emblem_art.js; the fallback / LEVELS
  /// list tint for the gradient plates).
  final Color plate;
  final Color rim;
  final Color accent;

  /// PHOENIX / LEGEND only: the plate gradient stops of §4.2
  /// (PHOENIX bottom -> top linear, LEGEND centre -> edge radial).
  final List<Color>? plateGradient;
}

/// The ten ranks, EGG first (PRD-home-v3 §4.1 table).
const List<LevelDef> kLevels = [
  LevelDef(
    level: 1,
    name: 'EGG',
    threshold: 25, // owner 2026-10-17 (was 10)
    reward: 25, // owner 2026-10-17 (was 50)
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  LevelDef(
    level: 2,
    name: 'CHICK',
    threshold: 50,
    reward: 50, // owner 2026-10-17 (was 100)
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  LevelDef(
    level: 3,
    name: 'FLEDGLING',
    threshold: 100,
    reward: 100, // owner 2026-10-17 (was 150)
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  LevelDef(
    level: 4,
    name: 'FLAPPER',
    threshold: 200,
    reward: 200, // owner 2026-10-17 (was 250)
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  LevelDef(
    level: 5,
    name: 'GLIDER',
    threshold: 400,
    reward: 400,
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  LevelDef(
    level: 6,
    name: 'FALCON',
    threshold: 600,
    reward: 600,
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  LevelDef(
    level: 7,
    name: 'HAWK',
    threshold: 800,
    reward: 800,
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  LevelDef(
    level: 8,
    name: 'SPIKE ACE',
    threshold: 1000,
    reward: 1000,
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  LevelDef(
    level: 9,
    name: 'PHOENIX',
    threshold: 2000,
    reward: 2000,
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  LevelDef(
    level: 10,
    name: 'LEGEND',
    threshold: 5000,
    reward: 5000,
    plate: Color(0xFF2A1260),
    rim: Color(0xFFFFB529),
    accent: Color(0xFF7C4DFF),
    plateGradient: [Color(0xFF5B2DC8), Color(0xFF2A1260), Color(0xFF120634)],
  ),
];

/// Highest level number.
const int kMaxLevel = 10;

/// The highest rank whose threshold <= [best]; 0 = unranked.
///
/// Owner 2026-10-17 (WP-L): this is NOT the player's level any more (that
/// is stored, `GameStorage.playerLevel`, and steps up one per run, see
/// [levelAfterRun]). It only mirrors the server's pool level
/// (`functions/src/levels.ts`) for versus matching and for opponents.
int levelFor(int best) {
  var level = 0;
  for (final def in kLevels) {
    if (best >= def.threshold) level = def.level;
  }
  return level;
}

/// Owner 2026-10-17 (WP-L): the level after a run of [score] at [level]:
/// one step up when the score reaches the next level's threshold (never
/// more than one, however high the score), else unchanged. LEGEND stays.
int levelAfterRun(int level, int score) {
  final next = nextLevel(level);
  return next != null && score >= next.threshold ? next.level : level;
}

/// The definition of [level] (1..10), null for unranked / out of range.
LevelDef? levelDef(int level) =>
    level >= 1 && level <= kLevels.length ? kLevels[level - 1] : null;

/// The rank after [level] (EGG after unranked), null at LEGEND.
LevelDef? nextLevel(int level) => levelDef(level < 0 ? 1 : level + 1);
