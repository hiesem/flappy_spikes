import 'dart:ui';

import '../run/config/tuning_defaults.dart';
import '../run/config/tuning_values.dart';
import '../skins/look.dart';

// region P26-J1
/// A progression reward, with the existing painted-emblem colours for J13.
class TrackLevelDef {
  const TrackLevelDef({
    required this.level,
    required this.name,
    this.plate = const Color(0xFFF6EBD2),
    this.rim = const Color(0xFFD9C39A),
    this.accent = const Color(0xFFB89A66),
    this.plateGradient,
  });

  final int level;
  final String name;
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

/// PRD-2.6 J1: finite named ranks, followed by endless ETERNAL WING.
const List<TrackLevelDef> kTrackLevels = [
  TrackLevelDef(
    level: 1,
    name: 'HATCHLING',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  TrackLevelDef(
    level: 2,
    name: 'FLUFFBALL',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  TrackLevelDef(
    level: 3,
    name: 'NEST HOPPER',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  TrackLevelDef(
    level: 4,
    name: 'FIRST FLAP',
    plate: Color(0xFFF6EBD2),
    rim: Color(0xFFD9C39A),
    accent: Color(0xFFB89A66),
  ),
  TrackLevelDef(
    level: 5,
    name: 'FLEDGLING',
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  TrackLevelDef(
    level: 6,
    name: 'WING WOBBLER',
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  TrackLevelDef(
    level: 7,
    name: 'HOOP ROOKIE',
    plate: Color(0xFFFFE58A),
    rim: Color(0xFFFFB300),
    accent: Color(0xFFE07B00),
  ),
  TrackLevelDef(
    level: 8,
    name: 'FEATHERWEIGHT',
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  TrackLevelDef(
    level: 9,
    name: 'SWALLOW',
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  TrackLevelDef(
    level: 10,
    name: 'HUMMINGBIRD',
    plate: Color(0xFFB9F3E1),
    rim: Color(0xFF13B48D),
    accent: Color(0xFF00796B),
  ),
  TrackLevelDef(
    level: 11,
    name: 'KINGFISHER',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  TrackLevelDef(
    level: 12,
    name: 'RIM SKIMMER',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  TrackLevelDef(
    level: 13,
    name: 'STARLING',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  TrackLevelDef(
    level: 14,
    name: 'SHRIKE',
    plate: Color(0xFFC8ECFD),
    rim: Color(0xFF1E9BE0),
    accent: Color(0xFF01579B),
  ),
  TrackLevelDef(
    level: 15,
    name: 'SWIFT',
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  TrackLevelDef(
    level: 16,
    name: 'TAILWIND',
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  TrackLevelDef(
    level: 17,
    name: 'HAWKEYE',
    plate: Color(0xFFEBD3F5),
    rim: Color(0xFF9B30D9),
    accent: Color(0xFF5E1A8C),
  ),
  TrackLevelDef(
    level: 18,
    name: 'CANNONBALL',
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  TrackLevelDef(
    level: 19,
    name: 'STORM PETREL',
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  TrackLevelDef(
    level: 20,
    name: 'FEVER FINCH',
    plate: Color(0xFFFCD9EE),
    rim: Color(0xFFEC008C),
    accent: Color(0xFF7A0044),
  ),
  TrackLevelDef(
    level: 21,
    name: 'SKYLARK',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  TrackLevelDef(
    level: 22,
    name: 'PEREGRINE',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  TrackLevelDef(
    level: 23,
    name: 'PORTAL PIGEON',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  TrackLevelDef(
    level: 24,
    name: 'COMET CONDOR',
    plate: Color(0xFFFFD6D6),
    rim: Color(0xFFD32F2F),
    accent: Color(0xFF7F1028),
  ),
  TrackLevelDef(
    level: 25,
    name: 'GOLDEN EAGLE',
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  TrackLevelDef(
    level: 26,
    name: 'NIGHT OWL',
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  TrackLevelDef(
    level: 27,
    name: 'MOONBIRD',
    plate: Color(0xFFFFF1C9),
    rim: Color(0xFFFFB529),
    accent: Color(0xFFB07800),
  ),
  TrackLevelDef(
    level: 28,
    name: 'ALBATROSS',
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  TrackLevelDef(
    level: 29,
    name: 'PHOENIX',
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  TrackLevelDef(
    level: 30,
    name: 'SPIKE LEGEND',
    plate: Color(0xFFFFD3A8),
    rim: Color(0xFFFF5722),
    accent: Color(0xFFB23000),
    plateGradient: [Color(0xFFFFAB76), Color(0xFFFFE3B8)],
  ),
  TrackLevelDef(
    level: 31,
    name: 'THUNDERBIRD',
    plate: Color(0xFF2A1260),
    rim: Color(0xFFFFB529),
    accent: Color(0xFF7C4DFF),
    plateGradient: [Color(0xFF5B2DC8), Color(0xFF2A1260), Color(0xFF120634)],
  ),
];
const kEternalWing = TrackLevelDef(
  level: 32,
  name: 'ETERNAL WING',
  plate: Color(0xFF2A1260),
  rim: Color(0xFFFFB529),
  accent: Color(0xFF7C4DFF),
);

/// Painted emblem index, spread across the 31 named levels (J13).
int paintedEmblemFor(int level) => level <= 0
    ? 0
    : level >= 32
    ? 10
    : 1 + (level - 1) * 9 ~/ 30;

TrackLevelDef? trackLevelDef(int level) {
  if (level <= 0) return null;
  if (level <= 31) return kTrackLevels[level - 1];
  return TrackLevelDef(
    level: level,
    name: kEternalWing.name,
    plate: kEternalWing.plate,
    rim: kEternalWing.rim,
    accent: kEternalWing.accent,
  );
}

/// Points required to advance from current index [level].
int needFor(int level) => trackLevelDef(level + 1)!.points;

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
// endregion
