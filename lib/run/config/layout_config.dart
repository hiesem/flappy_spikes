/// PRD-2 §3.0.2 hoop layout ramp, §3.10 angled rings and §3.11 / §5.12
/// moving rings as data (ARCH §1.3, WP-1b). Pure Dart.
///
/// The ramp rows, the moving-type weights and the slide / swing tables live
/// here; `DirectorTables.prd2` points at them, so the director, the layout
/// sampler and the mirror test (`spawn_tables.json`) all read one source.
library;

import '../director/plans.dart';
import 'director_tables.dart';

abstract final class LayoutConfig {
  // --- §3.0.2 the ramp -------------------------------------------------------

  /// §3.0.2 Hoop layout ramp, one row per hoop-index band (ascending `from`):
  /// centre range and |Δy| (median, p90, max) as fractions of the band
  /// between the tooth lines, tilt chance + tilt-step weights (degrees,
  /// positive = top leans right), moving chance.
  static const List<LayoutBand> bands = [
    LayoutBand(
      from: 0,
      centre: (0.45, 0.55),
      dy: (0.03, 0.06, 0.07),
      tilt: 0,
      tiltWeights: {},
      moving: 0,
    ),
    LayoutBand(
      from: 3,
      centre: (0.33, 0.67),
      dy: (0.11, 0.27, 0.35),
      tilt: 0,
      tiltWeights: {},
      moving: 0,
    ),
    LayoutBand(
      from: 10,
      centre: (0.30, 0.69),
      dy: (0.09, 0.30, 0.38),
      tilt: 0.30,
      tiltWeights: {-10: 6, 15: 4},
      moving: 0,
    ),
    LayoutBand(
      from: 20,
      centre: (0.27, 0.69),
      dy: (0.12, 0.31, 0.38),
      tilt: 0.50,
      tiltWeights: {-10: 35, 15: 30, 30: 25, -20: 10},
      moving: 0.06,
    ),
    LayoutBand(
      from: 35,
      centre: (0.24, 0.72),
      dy: (0.14, 0.33, 0.42),
      tilt: 0.60,
      tiltWeights: {-10: 25, 15: 20, 30: 30, -20: 10, 45: 15},
      moving: 0.15,
    ),
    LayoutBand(
      from: 45,
      centre: (0.16, 0.76),
      dy: (0.15, 0.38, 0.52),
      tilt: 0.78,
      tiltWeights: {-20: 20, -10: 10, 15: 10, 30: 30, 45: 30},
      moving: 0.40,
    ),
  ];

  /// §3.0.2 The ramp row for [hoopIndex].
  static LayoutBand bandFor(int hoopIndex) {
    var b = bands.first;
    for (final x in bands) {
      if (hoopIndex >= x.from) b = x;
    }
    return b;
  }

  /// §3.0.2 Direction: flip relative to the previous step with this chance.
  static const double flipChance = 0.65;

  /// §3.0.2 |Δy| quantile pieces: u below this → 0…median.
  static const double dyMedianU = 0.5;

  /// §3.0.2 |Δy| quantile pieces: u below this → median…p90, else p90…max.
  static const double dyP90U = 0.9;

  // --- §3.0.2 / §3.11 moving types --------------------------------------------

  /// §3.0.2 Moving types for hoops 20–44: rail slide 80 %, swing 20 %.
  static const Map<MotionType, int> movingTypes20 = {
    MotionType.rail: 80,
    MotionType.swing: 20,
  };

  /// §3.0.2 Moving types from hoop 45: rail 50, swing 15, horizontal 10,
  /// diagonal 10, orbit 8, rock 7.
  static const Map<MotionType, int> movingTypes45 = {
    MotionType.rail: 50,
    MotionType.swing: 15,
    MotionType.horizontal: 10,
    MotionType.diagonal: 10,
    MotionType.orbit: 8,
    MotionType.rock: 7,
  };

  /// §3.11 Every slide type joins from this hoop index (before: rail + swing).
  static const int allMotionTypesFrom = 45;

  /// §3.11 Rail slide: axis up to ±25° off vertical, ±40–60 pt, constant
  /// 30–39 pt/s (horizontal / diagonal slides use the same travel + speed).
  static const RailTable rail = RailTable(
    axisDeg: (-25, 25),
    halfTravel: (40, 60),
    speed: (30, 39),
  );

  /// §3.11 Swing: ±15°, period 1.8 s.
  static const SwingTable swing = SwingTable(amplitudeDeg: 15, period: 1.8);

  /// §3.11 Orbit: the ring's angle changes ±22° along the path.
  static const double orbitTiltDeg = 22;

  // --- §5.12 guides ------------------------------------------------------------

  /// §5.12 Guide line width (pt) — the shared dashed path (2.5 pt, 6 / 6).
  static const double guideWidth = 2.5;

  /// §5.12 Guide line opacity (fg × 0.75).
  static const double guideOpacity = 0.75;

  /// §5.12 Arrowhead opacity (fg × 0.9, mock).
  static const double arrowOpacity = 0.9;

  /// §5.12 Arrowhead width (pt; 13 × 12 triangles).
  static const double arrowWidth = 13;

  /// §5.12 Arrowhead length (pt; 13 × 12 triangles).
  static const double arrowLength = 12;

  /// §5.12 Arrowheads sit this far past the guide's end (pt, mock: 4).
  static const double arrowGap = 4;

  /// §5.12 End-cap length (pt), across the line.
  static const double capLength = 16;

  /// §5.12 Rock: the curved arrows sit this far outside the ring's rim end
  /// (pt; mock radius 80 for a 60 pt ring half height).
  static const double rockArcGap = 20;

  /// §5.12 Rock: half the angle the curved arrow spans (degrees, mock ≈ 28°).
  static const double rockArcHalfDeg = 28;

  /// §5.12 Rock: the dotted centre line (width pt, dash on / off, opacity).
  static const double rockAxisWidth = 2;

  /// §5.12 Rock: the dotted centre line dash (on, off).
  static const List<double> rockAxisDash = [3, 6];

  /// §5.12 Rock: the dotted centre line opacity.
  static const double rockAxisOpacity = 0.5;

  /// §5.12 Swing: the rope (solid, width pt).
  static const double ropeWidth = 2;

  /// §5.12 Swing: the rope opacity.
  static const double ropeOpacity = 0.5;
}
