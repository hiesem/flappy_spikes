import '../director/plans.dart' show RideId;
import 'tuning_values.dart';

/// PRD-2.6 WP-B constants for the invisible showcase safety net.
///
/// This file is the B3 script table only: every scripted position is a hoop
/// slot or gap index, never a screen position, so a plan is identical at every
/// view height. The stateful planner lives in `showcase_plan.dart`.
abstract final class ShowcaseConfig {
  /// Highlight ids in step order; internal only, never player-facing.
  static const List<String> highlightIds = ['portal', 'comet', 'fever'];

  /// Every showcase run arms Big Hoops and a shield.
  static const List<String> starters = ['bigHoops', 'shield'];

  /// Big Hoops duration in seconds for scripted step 1.
  static const double portalBigHoopsSeconds = 60;

  /// B1 the safety net's hard end (`showcase_max_games`, default 6).
  static int get maxGames => TuningValues.current.i('showcase_max_games');

  /// B1 a showcase run that passes this many hoops ends the safety net
  /// (`showcase_fast_hoops`, default 40).
  static int get fastHoops => TuningValues.current.i('showcase_fast_hoops');

  /// B1 storage bit 7 means done; bits 0–2 are the three highlights.
  static const int doneBit = 7;

  /// B1 the mask of the three highlight bits.
  static const int highlightMask = 0x7;

  /// The start-gate for testers / existing installs: with at least this many
  /// finished games and no showcase key, the safety net counts as done.
  static const int testerGamesPlayed = 3;

  /// The highlight hoop by attempt (`1`, `2`, `3+`): portal, comet and
  /// FEVER. The full per-step script is [`gapItems`], [`hearts`],
  /// [`spacePortalHoops`] and [`bullseyeHoops`].
  static const Map<String, Map<String, List<int>>> scripts = {
    'portal': {
      '1': [7],
      '2': [5],
      '3': [3],
    },
    'comet': {
      '1': [9],
      '2': [6],
      '3': [4],
    },
    'fever': {
      '1': [5],
      '2': [4],
      '3': [3],
    },
  };

  /// B3 the portal ride's theme in step 1 (Cannon; the "roller-coaster").
  static const RideId portalTheme = RideId.cannon;

  /// B3 the second portal ride's theme in step 3 (Space, never Cannon).
  static const RideId feverPortalTheme = RideId.space;

  /// B3 the portal hoop slots by attempt (`1`, `2`, `3+`).
  static Map<String, List<int>> get portalHoops => scripts['portal']!;

  /// B3 the Space portal hoop slots by attempt (`1`, `2`, `3+`).
  static Map<String, List<int>> get spacePortalHoops => _spacePortalHoops;

  static const Map<String, List<int>> _spacePortalHoops = {
    '1': [15],
    '2': [13],
    '3': [11],
  };

  /// B3 the comet-star hoop slots by attempt (`1`, `2`, `3+`).
  static Map<String, List<int>> get cometHoops => scripts['comet']!;

  /// B3 the FEVER-ring hoop slots by attempt (`1`, `2`, `3+`).
  static Map<String, List<int>> get feverHoops => scripts['fever']!;

  /// B3 the Bullseye hoop slots by attempt (always hoop 14).
  static const Map<String, List<int>> bullseyeHoops = {
    '1': [14],
    '2': [14],
    '3': [14],
  };

  /// B3 gap items by highlight -> attempt -> `(item id, gap index)`.
  ///
  /// `feather` is the golden feather, `puzzle_piece` the puzzle piece and
  /// `star_trail`, `coin_frenzy` and `hourglass` the named gap items. The
  /// portal and comet Star Trails deliberately have separate rows: the
  /// portal uses gaps 2, 5 and the comet gaps 6 / 5 / none.
  static const Map<String, Map<String, List<(String, int)>>> gapItems = {
    'portal': {
      '1': [('star_trail', 2), ('star_trail', 5), ('feather', 4)],
      '2': [('star_trail', 2), ('feather', 3)],
      '3': [('star_trail', 2), ('feather', 2)],
    },
    'comet': {
      '1': [('coin_frenzy', 3), ('star_trail', 6)],
      '2': [('coin_frenzy', 3), ('star_trail', 5)],
      '3': [('coin_frenzy', 2)],
    },
    'fever': {
      '1': [('puzzle_piece', 8), ('hourglass', 11)],
      '2': [('puzzle_piece', 6), ('hourglass', 11)],
      '3': [('puzzle_piece', 5), ('hourglass', 9)],
    },
  };

  /// B3 the hearts by step and attempt (the same gaps in every attempt).
  static const Map<String, Map<String, List<int>>> hearts = {
    'portal': {
      '1': [10, 13, 16],
      '2': [10, 13, 16],
      '3': [10, 13, 16],
    },
    'comet': {
      '1': [12, 15, 18],
      '2': [12, 15, 18],
      '3': [12, 15, 18],
    },
    'fever': {'1': [], '2': [], '3': []},
  };

  /// B3 the script attempt band: `1`, `2`, or `3` for every attempt ≥ 3.
  static String attemptKey(int attempt) => attempt <= 1
      ? '1'
      : attempt == 2
      ? '2'
      : '3';
}
