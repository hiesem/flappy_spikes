import 'dart:ui';

import '../run/config/tuning_defaults.dart';
import '../run/config/tuning_values.dart';
import '../skins/look.dart';

// region P26-J1
/// A progression reward, with the existing painted-emblem colours for J13.
class LevelDef {
  const LevelDef({
    required this.level,
    required this.name,
    this.legacyThreshold,
    this.legacyReward,
    this.plate = const Color(0xFFF6EBD2),
    this.rim = const Color(0xFFD9C39A),
    this.accent = const Color(0xFFB89A66),
    this.plateGradient,
  });

  final int level;
  final String name;
  final int? legacyThreshold;
  final int? legacyReward;
  final Color plate;
  final Color rim;
  final Color accent;
  final List<Color>? plateGradient;

  int get points => level >= 32
      ? tuning.i('level_eternal_points')
      : tuning.ints('level_points')[level - 1];
  int get coins => level >= 32
      ? tuning.i('level_eternal_coins')
      : tuning.ints('level_coins')[level - 1];

  /// Compatibility with the old progress/UI consumers until J2/J3.
  int get threshold => legacyThreshold ?? points;
  int get defaultReward => legacyReward ?? coins;
  int get reward => legacyReward ?? coins;

  ({SkinLayer? layer, Rarity rarity}) get item {
    if (level >= 32) return (layer: null, rarity: Rarity.common);
    final rows = tuning.raw('level_items') as List;
    final parsed = _parseItem(rows[level - 1] as String);
    if (parsed != null) return parsed;
    final defaults = kTuningDefaults.firstWhere((d) => d.key == 'level_items');
    return _parseItem((defaults.value as List)[level - 1] as String)!;
  }

  SkinLayer? get layer => item.layer;
  Rarity get rarity => item.rarity;
}

const _shopLayers = {
  SkinLayer.bird,
  SkinLayer.hat,
  SkinLayer.gear,
  SkinLayer.hoop,
  SkinLayer.trail,
};

({SkinLayer? layer, Rarity rarity})? _parseItem(String row) {
  final parts = row.split(':');
  if (parts.length != 2) return null;
  final layer = SkinLayer.fromKey(parts[0]);
  if (parts[0] != 'any' && !_shopLayers.contains(layer)) return null;
  for (final rarity in Rarity.values) {
    if (rarity.name == parts[1]) return (layer: layer, rarity: rarity);
  }
  return null;
}

const List<LevelDef> _paintedLevels = [
  LevelDef(
    level: 1,
    name: 'EGG',
    legacyThreshold: 25, // owner 2026-10-17 (was 10)
    legacyReward: 25, // owner 2026-10-17 (was 50)
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  LevelDef(
    level: 2,
    name: 'CHICK',
    legacyThreshold: 50,
    legacyReward: 50, // owner 2026-10-17 (was 100)
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  LevelDef(
    level: 3,
    name: 'FLEDGLING',
    legacyThreshold: 100,
    legacyReward: 100, // owner 2026-10-17 (was 150)
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  LevelDef(
    level: 4,
    name: 'FLAPPER',
    legacyThreshold: 200,
    legacyReward: 200, // owner 2026-10-17 (was 250)
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  LevelDef(
    level: 5,
    name: 'GLIDER',
    legacyThreshold: 400,
    legacyReward: 400,
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  LevelDef(
    level: 6,
    name: 'FALCON',
    legacyThreshold: 600,
    legacyReward: 600,
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  LevelDef(
    level: 7,
    name: 'HAWK',
    legacyThreshold: 800,
    legacyReward: 800,
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  LevelDef(
    level: 8,
    name: 'SPIKE ACE',
    legacyThreshold: 1000,
    legacyReward: 1000,
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  LevelDef(
    level: 9,
    name: 'PHOENIX',
    legacyThreshold: 2000,
    legacyReward: 2000,
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  LevelDef(
    level: 10,
    name: 'LEGEND',
    legacyThreshold: 5000,
    legacyReward: 5000,
    plate: Color(0xFF2A1260),
    rim: Color(0xFFFFB529),
    accent: Color(0xFF7C4DFF),
    plateGradient: [Color(0xFF5B2DC8), Color(0xFF2A1260), Color(0xFF120634)],
  ),
];

/// PRD-2.6 J1: finite named ranks, followed by endless ETERNAL WING.
const List<LevelDef> kLevels = [
  LevelDef(
    level: 1,
    name: 'HATCHLING',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  LevelDef(
    level: 2,
    name: 'FLUFFBALL',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  LevelDef(
    level: 3,
    name: 'NEST HOPPER',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  LevelDef(
    level: 4,
    name: 'FIRST FLAP',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  LevelDef(
    level: 5,
    name: 'FLEDGLING',
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  LevelDef(
    level: 6,
    name: 'WING WOBBLER',
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  LevelDef(
    level: 7,
    name: 'HOOP ROOKIE',
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  LevelDef(
    level: 8,
    name: 'FEATHERWEIGHT',
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  LevelDef(
    level: 9,
    name: 'SWALLOW',
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  LevelDef(
    level: 10,
    name: 'HUMMINGBIRD',
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  LevelDef(
    level: 11,
    name: 'KINGFISHER',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  LevelDef(
    level: 12,
    name: 'RIM SKIMMER',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  LevelDef(
    level: 13,
    name: 'STARLING',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  LevelDef(
    level: 14,
    name: 'SHRIKE',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  LevelDef(
    level: 15,
    name: 'SWIFT',
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  LevelDef(
    level: 16,
    name: 'TAILWIND',
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  LevelDef(
    level: 17,
    name: 'HAWKEYE',
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  LevelDef(
    level: 18,
    name: 'CANNONBALL',
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  LevelDef(
    level: 19,
    name: 'STORM PETREL',
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  LevelDef(
    level: 20,
    name: 'FEVER FINCH',
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  LevelDef(
    level: 21,
    name: 'SKYLARK',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  LevelDef(
    level: 22,
    name: 'PEREGRINE',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  LevelDef(
    level: 23,
    name: 'PORTAL PIGEON',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  LevelDef(
    level: 24,
    name: 'COMET CONDOR',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  LevelDef(
    level: 25,
    name: 'GOLDEN EAGLE',
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  LevelDef(
    level: 26,
    name: 'NIGHT OWL',
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  LevelDef(
    level: 27,
    name: 'MOONBIRD',
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  LevelDef(
    level: 28,
    name: 'ALBATROSS',
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  LevelDef(
    level: 29,
    name: 'PHOENIX',
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  LevelDef(
    level: 30,
    name: 'SPIKE LEGEND',
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  LevelDef(
    level: 31,
    name: 'THUNDERBIRD',
    plate: Color(0xFF2A1260),
    rim: Color(0xFFFFB529),
    accent: Color(0xFF7C4DFF),
    plateGradient: [Color(0xFF5B2DC8), Color(0xFF2A1260), Color(0xFF120634)],
  ),
];
const kEternalWing = LevelDef(
  level: 32,
  name: 'ETERNAL WING',
  plate: Color(0xFF2A1260),
  rim: Color(0xFFFFB529),
  accent: Color(0xFF7C4DFF),
);

/// Temporary compatibility for the 2.5 progress consumer; J2 retires it.
const int kMaxLevel = 10;

/// Painted emblem index, spread across the 31 named levels (J13).
int paintedEmblemFor(int level) => level <= 0
    ? 0
    : level >= 32
    ? 10
    : 1 + (level - 1) * 9 ~/ 30;

LevelDef? levelDef(int level) {
  if (level <= 0) return null;
  if (level <= 31) return kLevels[level - 1];
  return LevelDef(
    level: level,
    name: kEternalWing.name,
    plate: kEternalWing.plate,
    rim: kEternalWing.rim,
    accent: kEternalWing.accent,
  );
}

/// Points required to advance from current index [level].
int needFor(int level) => levelDef(level + 1)!.points;
LevelDef? nextLevel(int level) => levelDef(level < 0 ? 1 : level + 1);

/// Legacy pool brackets, preserved until E1 removes this API.
int levelFor(int best) {
  var level = 0;
  for (final def in _paintedLevels) {
    if (best >= def.threshold) level = def.level;
  }
  return level;
}

/// Legacy single-run rule; cumulative progression uses LevelTrack instead.
int levelAfterRun(int level, int score) =>
    level < 10 && score >= _paintedLevels[level < 0 ? 0 : level].threshold
    ? (level < 0 ? 1 : level + 1)
    : level;
// endregion
