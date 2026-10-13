/// PRD-2 §3.0.2 / §3.0.3 run-director tables as data (ARCH §4).
///
/// Mirrors `design/reference/data/spawn_tables.json` (copied to
/// `test/fixtures/spawn_tables.json`; `tables_mirror_test.dart` checks
/// every value). Pure Dart.
library;

import '../director/plans.dart';
import '../elements.dart';
import 'layout_config.dart';
import 'tuning_types.dart';
import 'tuning_values.dart';

/// §3.0.2 One row of the hoop layout ramp (fractions of the band).
class LayoutBand {
  const LayoutBand({
    required this.from,
    required this.centre,
    required this.dy,
    required this.tilt,
    required this.tiltWeights,
    required this.moving,
  });

  /// §3.0.2 First hoop index of the row.
  final int from;

  /// §3.0.2 Centre range (fractions of the band).
  final (double, double) centre;

  /// §3.0.2 |Δy| (median, p90, max) as fractions of the band.
  final (double, double, double) dy;

  /// §3.0.2 Chance a normal hoop is tilted.
  final double tilt;

  /// §3.0.2 Tilt steps (degrees, positive = top leans right) → weight.
  final Map<int, int> tiltWeights;

  /// §3.0.2 Chance a normal hoop moves.
  final double moving;
}

/// §3.0.3 Budget row: chance a slot is special / a gap gets an optional item.
class BudgetRow {
  const BudgetRow(this.from, this.special, this.gap);

  /// §3.0.3 First hoop index of the row.
  final int from;

  /// §3.0.3 Special hoop chance per slot.
  final double special;

  /// §3.0.3 Optional gap item chance per gap.
  final double gap;
}

/// §3.0.3 Special-hoop row.
class SpecialRule {
  const SpecialRule({
    required this.from,
    required this.weight,
    this.weightFrom45,
    required this.minSince,
    required this.cooldown,
    this.allowedInSqueeze = false,
    this.blockedNearPortal = 0,
  });

  /// §3.0.3 From hoop.
  final int from;

  /// §3.0.3 Weight.
  final int weight;

  /// §3.0.3 Weight from hoop 45 (saw: 26).
  final int? weightFrom45;

  /// §3.0.3 Min hoops since the same type.
  final int minSince;

  /// §3.0.3 Normal slots after it.
  final int cooldown;

  /// §3.0.3 Allowed in the squeeze window (bullseye, FEVER, saw).
  final bool allowedInSqueeze;

  /// §3.0.3 Not within this many hoops of the portal (saw, FEVER, switch).
  final int blockedNearPortal;

  int weightAt(int hoopIndex) =>
      hoopIndex >= 45 && weightFrom45 != null ? weightFrom45! : weight;
}

/// §3.0.3 Optional gap item row.
class GapItemRule {
  const GapItemRule({
    required this.from,
    required this.weight,
    required this.minSince,
    this.maxPerRun,
    this.allowedInSqueeze = false,
  });

  /// §3.0.3 From gap.
  final int from;

  /// §3.0.3 Weight.
  final int weight;

  /// §3.0.3 Min gaps since the same type.
  final int minSince;

  /// §3.0.3 Max per run (shield: 1).
  final int? maxPerRun;

  /// §3.0.3 Allowed in a squeeze (Star Trail).
  final bool allowedInSqueeze;
}

/// §3.0.3 A fixed schedule: first at a random index in [first], then every
/// [then] after the previous one (both inclusive ranges).
class Schedule {
  const Schedule({required this.first, required this.then});
  final (int, int) first;
  final (int, int) then;
}

/// PRD-2.3 §14.5 the comet: a [chance] per eligible normal hoop from hoop
/// [from], at least [spacing] hoops after the previous comet (replaces the
/// 2.2 schedule "first at 10–30, then every 45–60").
class CometRule {
  const CometRule({
    required this.chance,
    required this.from,
    required this.spacing,
  });

  /// PRD-2.3 §14.5 chance per eligible normal hoop (`ride_comet_chance`).
  final double chance;

  /// PRD-2.3 §14.5 first hoop index (`ride_comet_from`).
  final int from;

  /// PRD-2.3 §14.5 min hoops after the previous comet
  /// (`ride_comet_spacing`).
  final int spacing;
}

/// §3.0.2 / §3.0.3 All director tables.
class DirectorTables {
  const DirectorTables({
    required this.bands,
    required this.budget,
    required this.specials,
    required this.gapItems,
    required this.portal,
    required this.comet,
    required this.heart,
    required this.featherWindow,
    required this.pieceWindow,
    this.featherChance = 1,
    this.pieceChance = 1,
    this.earlyPool,
    this.tiltCurve,
    this.movingCurve,
    required this.pairWeights,
    required this.capsuleWeights,
    required this.movingTypes20,
    required this.movingTypes45,
    required this.rail,
    required this.swing,
  });

  /// §3.0.2 Layout ramp rows, ascending `from`.
  final List<LayoutBand> bands;

  /// §3.0.3 Budget rows, ascending `from`.
  final List<BudgetRow> budget;

  /// §3.0.3 Special hoops (insertion order = weighted pick order).
  final Map<HoopKindId, SpecialRule> specials;

  /// §3.0.3 Optional gap items (insertion order = weighted pick order).
  final Map<ElementId, GapItemRule> gapItems;

  /// §3.0.3 Portal schedule. PRD-2.3 §14.5: first at 40–60, then +60–80
  /// (`ride_portal_first` / `ride_portal_then`; was 25–50, then +40–60).
  final Schedule portal;

  /// §3.0.3 Comet hoop. PRD-2.3 §14.5: 2 % per eligible normal hoop from
  /// hoop 10, ≥ 25 hoops apart (was the schedule 10–30, then +45–60).
  final CometRule comet;

  /// §3.0.3 Heart schedule. PRD-2.2 §19.1: first at a random gap 5–27,
  /// then every 17–27 gaps (was: exactly gap 3).
  final Schedule heart;

  /// §3.15 Golden feather window. PRD-2.2 §19.3: a random gap 3–40 (was
  /// 3–12), at most once per run.
  final (int, int) featherWindow;

  /// §3.16 Puzzle piece window. PRD-2.2 §19.3: a random gap 3–40 (was
  /// 14–25), at most once per run.
  final (int, int) pieceWindow;

  /// PRD-2.2 §19.3 Chance (rolled at run start) that the golden feather
  /// appears this run (≈ 60 %).
  final double featherChance;

  /// PRD-2.2 §19.3 Chance (rolled at run start) that a puzzle piece appears
  /// this run (≈ 60 %).
  final double pieceChance;

  /// PRD-2.2 §19.2 The early random pool (indices 4–9); null = none.
  final EarlyPool? earlyPool;

  /// PRD-2.3 §14.4 tilted-hoop chance by hoop index (`curve_tilt`); null =
  /// the layout row's [LayoutBand.tilt].
  final Keyframes? tiltCurve;

  /// PRD-2.3 §14.4 moving-hoop chance by hoop index (`curve_moving`); null
  /// = the layout row's [LayoutBand.moving].
  final Keyframes? movingCurve;

  /// §3.0.2 / PRD-2.3 §14.4 the chance a normal hoop at [hoopIndex] is
  /// tilted.
  double tiltChance(int hoopIndex) =>
      tiltCurve?.at(hoopIndex) ?? bandFor(hoopIndex).tilt;

  /// §3.0.2 / PRD-2.3 §14.4 the chance a normal hoop at [hoopIndex] moves.
  double movingChance(int hoopIndex) =>
      movingCurve?.at(hoopIndex) ?? bandFor(hoopIndex).moving;

  /// §3.21 Pair gift weights.
  final Map<PairReward, int> pairWeights;

  /// §3.30 Capsule type weights.
  final Map<CapsuleType, int> capsuleWeights;

  /// §3.0.2 Moving types for hoops 20–44.
  final Map<MotionType, int> movingTypes20;

  /// §3.0.2 Moving types from hoop 45.
  final Map<MotionType, int> movingTypes45;

  /// §3.11 Rail slide parameters.
  final RailTable rail;

  /// §3.11 Swing parameters.
  final SwingTable swing;

  LayoutBand bandFor(int hoopIndex) {
    var b = bands.first;
    for (final x in bands) {
      if (hoopIndex >= x.from) b = x;
    }
    return b;
  }

  BudgetRow budgetFor(int hoopIndex) {
    var b = budget.first;
    for (final x in budget) {
      if (hoopIndex >= x.from) b = x;
    }
    return b;
  }

  /// §3.0.2 / §3.0.3 The run's tables: the PRD-2 launch tables with the
  /// PRD-2.2 §19 changes and the PRD-2.3 §14 / §15 values, read from the
  /// tuning layer ([TuningValues.current], set at run start). The §3.0.2
  /// layout rows and the §3.11 motion tables come from `LayoutConfig`.
  static DirectorTables get prd2 => fromTuning(TuningValues.current);

  /// PRD-2.3 §15.3 the tables for the tuning set [t] (spawn rows, heart,
  /// feather / piece, comet, portal, pair and capsule weights, tilt and
  /// moving curves).
  static DirectorTables fromTuning(TuningValues t) {
    SpecialRule special(String key) {
      final o = t.obj(key);
      return SpecialRule(
        from: o['from']!.toInt(),
        weight: o['weight']!.toInt(),
        weightFrom45: o['weight_from_45']?.toInt(),
        minSince: o['min_since']!.toInt(),
        cooldown: o['cooldown']!.toInt(),
        allowedInSqueeze: _specialInSqueeze.contains(key),
        blockedNearPortal: _specialNearPortal.contains(key) ? 3 : 0,
      );
    }

    GapItemRule gap(String key) {
      final o = t.obj(key);
      return GapItemRule(
        from: o['from']!.toInt(),
        weight: o['weight']!.toInt(),
        minSince: o['min_since']!.toInt(),
        maxPerRun: o['max_per_run']?.toInt(),
        allowedInSqueeze: key == 'spawn_star_trail',
      );
    }

    Schedule schedule(String first, String then) =>
        Schedule(first: t.range(first), then: t.range(then));

    final pair = t.obj('spawn_pair_gifts');
    final caps = t.obj('spawn_capsules');
    return DirectorTables(
      bands: LayoutConfig.bands,
      budget: _budget,
      specials: {
        HoopKindId.bullseye: special('spawn_bullseye'),
        HoopKindId.train: special('spawn_train'),
        HoopKindId.spring: special('spawn_spring'),
        HoopKindId.switchRing: special('spawn_switch'),
        HoopKindId.pair: special('spawn_pair'),
        HoopKindId.fever: special('spawn_fever'),
        HoopKindId.luckySpin: special('spawn_lucky_spin'),
        HoopKindId.saw: special('spawn_saw'),
      },
      gapItems: {
        ElementId.starTrail: gap('spawn_star_trail'),
        ElementId.capsule: gap('spawn_capsule'),
        ElementId.egg: gap('spawn_egg'),
        ElementId.piggy: gap('spawn_piggy'),
        ElementId.jar: gap('spawn_jar'),
        ElementId.shield: gap('spawn_shield'),
      },
      portal: schedule('ride_portal_first', 'ride_portal_then'),
      comet: CometRule(
        chance: t.d('ride_comet_chance'),
        from: t.i('ride_comet_from'),
        spacing: t.i('ride_comet_spacing'),
      ),
      // PRD-2.2 §19 (supersedes the PRD-2 §3.0.3 / §3.15 / §3.16 values);
      // PRD-2.3 §14.2: the feather and the piece from gap 10.
      heart: schedule('spawn_heart_first', 'spawn_heart_then'),
      featherWindow: t.range('bonus_feather_gaps'),
      pieceWindow: t.range('puzzle_gaps'),
      featherChance: t.d('bonus_feather_chance'),
      pieceChance: t.d('puzzle_chance'),
      earlyPool: _earlyPool,
      tiltCurve: t.curve('curve_tilt'),
      movingCurve: t.curve('curve_moving'),
      pairWeights: {
        PairReward.shield: pair['shield']!.toInt(),
        PairReward.comet: pair['comet']!.toInt(),
        PairReward.coins: pair['coins']!.toInt(),
        PairReward.score: pair['score']!.toInt(),
        PairReward.fever: pair['fever']!.toInt(),
      },
      capsuleWeights: {
        CapsuleType.hourglass: caps['hourglass']!.toInt(),
        CapsuleType.miniBird: caps['mini_bird']!.toInt(),
        CapsuleType.coinFrenzy: caps['coin_frenzy']!.toInt(),
      },
      movingTypes20: LayoutConfig.movingTypes20,
      movingTypes45: LayoutConfig.movingTypes45,
      rail: LayoutConfig.rail,
      swing: LayoutConfig.swing,
    );
  }

  /// §3.0.3 Special hoops allowed in the squeeze window (bullseye, FEVER,
  /// saw) — a rule, not a tuning value.
  static const Set<String> _specialInSqueeze = {
    'spawn_bullseye',
    'spawn_fever',
    'spawn_saw',
  };

  /// §3.0.3 Special hoops not within 3 hoops of the portal (switch, FEVER,
  /// saw) — a rule, not a tuning value.
  static const Set<String> _specialNearPortal = {
    'spawn_switch',
    'spawn_fever',
    'spawn_saw',
  };

  /// §3.0.3 Budget rows (not tunable).
  static const List<BudgetRow> _budget = [
    BudgetRow(0, 0, 0),
    BudgetRow(5, 0, 0.25),
    BudgetRow(8, 0.25, 0.25),
    BudgetRow(20, 0.35, 0.33),
    BudgetRow(35, 0.45, 0.33),
    BudgetRow(50, 0.60, 0.33),
  ];

  /// PRD-2.2 §19.2 the early random pool (not tunable).
  static const EarlyPool _earlyPool = EarlyPool(
    from: 4,
    to: 9,
    weights: {
      EarlyPick.starTrail: 1,
      EarlyPick.bullseye: 1,
      EarlyPick.angled: 1,
      EarlyPick.nothing: 1,
    },
  );
}

/// PRD-2.2 §19.2 one option of the early random pool.
enum EarlyPick {
  /// A Star Trail in the gap after the slot.
  starTrail,

  /// The slot is a Bullseye Ring.
  bullseye,

  /// The slot is an angled (tilted) normal ring.
  angled,

  /// Nothing extra (a quiet index).
  nothing,
}

/// PRD-2.2 §19.2 For slot / gap indices [from]–[to] the director makes one
/// equal-chance draw per index from [weights] instead of the special-hoop
/// and optional-gap-item rolls. Bullseye and the angled ring may come from
/// index [from] here (their normal unlocks stay for the regular tables);
/// the usual exclusivity and cooldowns still apply.
class EarlyPool {
  const EarlyPool({required this.from, required this.to, required this.weights});

  /// PRD-2.2 §19.2 First index of the pool (4).
  final int from;

  /// PRD-2.2 §19.2 Last index of the pool (9).
  final int to;

  /// PRD-2.2 §19.2 The options, equal weight.
  final Map<EarlyPick, int> weights;

  bool covers(int i) => i >= from && i <= to;
}

/// §3.11 Rail slide: axis range (deg), half travel (pt), speed (pt/s).
class RailTable {
  const RailTable({
    required this.axisDeg,
    required this.halfTravel,
    required this.speed,
  });
  final (double, double) axisDeg;
  final (double, double) halfTravel;
  final (double, double) speed;
}

/// §3.11 Swing: amplitude (deg) and period (s).
class SwingTable {
  const SwingTable({required this.amplitudeDeg, required this.period});
  final double amplitudeDeg;
  final double period;
}
