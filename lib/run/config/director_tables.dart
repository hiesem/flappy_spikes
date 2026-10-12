/// PRD-2 §3.0.2 / §3.0.3 run-director tables as data (ARCH §4).
///
/// Mirrors `design/reference/data/spawn_tables.json` (copied to
/// `test/fixtures/spawn_tables.json`; `tables_mirror_test.dart` checks
/// every value). Pure Dart.
library;

import '../director/plans.dart';
import '../elements.dart';
import 'layout_config.dart';

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

  /// §3.0.3 Portal schedule (25–50, then +40–60).
  final Schedule portal;

  /// §3.0.3 Comet hoop schedule (10–30, then +45–60).
  final Schedule comet;

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

  /// §3.0.2 / §3.0.3 The PRD-2 launch tables (the §3.0.2 layout rows and
  /// the §3.11 motion tables come from `LayoutConfig`, WP-1b).
  static const DirectorTables prd2 = DirectorTables(
    bands: LayoutConfig.bands,
    budget: [
      BudgetRow(0, 0, 0),
      BudgetRow(5, 0, 0.25),
      BudgetRow(8, 0.25, 0.25),
      BudgetRow(20, 0.35, 0.33),
      BudgetRow(35, 0.45, 0.33),
      BudgetRow(50, 0.60, 0.33),
    ],
    specials: {
      HoopKindId.bullseye: SpecialRule(
        from: 6,
        weight: 20,
        minSince: 6,
        cooldown: 1,
        allowedInSqueeze: true,
      ),
      HoopKindId.train: SpecialRule(
        from: 8,
        weight: 14,
        minSince: 10,
        cooldown: 2,
      ),
      HoopKindId.spring: SpecialRule(
        from: 10,
        weight: 12,
        minSince: 10,
        cooldown: 2,
      ),
      HoopKindId.switchRing: SpecialRule(
        from: 12,
        weight: 14,
        minSince: 8,
        cooldown: 1,
        blockedNearPortal: 3,
      ),
      HoopKindId.pair: SpecialRule(
        from: 12,
        weight: 10,
        minSince: 15,
        cooldown: 2,
      ),
      HoopKindId.fever: SpecialRule(
        from: 15,
        weight: 6,
        minSince: 20,
        cooldown: 1,
        allowedInSqueeze: true,
        blockedNearPortal: 3,
      ),
      HoopKindId.luckySpin: SpecialRule(
        from: 15,
        weight: 8,
        minSince: 18,
        cooldown: 1,
      ),
      HoopKindId.saw: SpecialRule(
        from: 20,
        weight: 18,
        weightFrom45: 26,
        minSince: 3,
        cooldown: 1,
        allowedInSqueeze: true,
        blockedNearPortal: 3,
      ),
    },
    gapItems: {
      ElementId.starTrail: GapItemRule(
        from: 5,
        weight: 30,
        minSince: 8,
        allowedInSqueeze: true,
      ),
      ElementId.capsule: GapItemRule(from: 10, weight: 20, minSince: 20),
      ElementId.egg: GapItemRule(from: 10, weight: 12, minSince: 15),
      ElementId.piggy: GapItemRule(from: 12, weight: 10, minSince: 30),
      ElementId.jar: GapItemRule(from: 15, weight: 10, minSince: 30),
      ElementId.shield: GapItemRule(
        from: 12,
        weight: 6,
        minSince: 0,
        maxPerRun: 1,
      ),
    },
    portal: Schedule(first: (25, 50), then: (40, 60)),
    comet: Schedule(first: (10, 30), then: (45, 60)),
    // PRD-2.2 §19 (supersedes the PRD-2 §3.0.3 / §3.15 / §3.16 values).
    heart: Schedule(first: (5, 27), then: (17, 27)),
    featherWindow: (3, 40),
    pieceWindow: (3, 40),
    featherChance: 0.6,
    pieceChance: 0.6,
    earlyPool: EarlyPool(
      from: 4,
      to: 9,
      weights: {
        EarlyPick.starTrail: 1,
        EarlyPick.bullseye: 1,
        EarlyPick.angled: 1,
        EarlyPick.nothing: 1,
      },
    ),
    pairWeights: {
      PairReward.shield: 25,
      PairReward.comet: 20,
      PairReward.coins: 25,
      PairReward.score: 15,
      PairReward.fever: 15,
    },
    capsuleWeights: {
      CapsuleType.hourglass: 35,
      CapsuleType.miniBird: 35,
      CapsuleType.coinFrenzy: 30,
    },
    movingTypes20: LayoutConfig.movingTypes20,
    movingTypes45: LayoutConfig.movingTypes45,
    rail: LayoutConfig.rail,
    swing: LayoutConfig.swing,
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
