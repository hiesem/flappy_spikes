/// PRD-2 §3.0.2 hoop layout ramp, §3.10 angled rings and §3.11 / §5.12
/// moving rings as data (ARCH §1.3, WP-1b). Pure Dart.
///
/// The ramp rows, the moving-type weights and the slide / swing tables live
/// here; `DirectorTables.prd2` points at them, so the director, the layout
/// sampler and the mirror test (`spawn_tables.json`) all read one source.
library;

import '../director/plans.dart';
import 'director_tables.dart';
import 'tuning_values.dart';

abstract final class LayoutConfig {
  // --- §3.0.2 the ramp -------------------------------------------------------

  /// §3.0.2 / PRD-2.6 D2 hoop layout ramp, one row per hoop-index band
  /// (ascending `from`): centre range as a fraction of the band and |Δy|
  /// (median, p90, max) as a fraction of `dyRefBand`.
  static const List<LayoutBand> bands = [
    LayoutBand(from: 0, centre: (0.45, 0.55), dy: (0.03, 0.06, 0.07)),
    LayoutBand(from: 3, centre: (0.33, 0.67), dy: (0.11, 0.27, 0.35)),
    LayoutBand(from: 20, centre: (0.27, 0.70), dy: (0.12, 0.31, 0.38)),
    LayoutBand(from: 40, centre: (0.24, 0.73), dy: (0.14, 0.33, 0.42)),
    LayoutBand(from: 65, centre: (0.20, 0.76), dy: (0.15, 0.35, 0.46)),
    LayoutBand(from: 100, centre: (0.16, 0.78), dy: (0.15, 0.37, 0.50)),
  ];

  // region P26-D-TABLES
  /// Compatibility views for existing table consumers; tuning owns the values.
  static Map<int, Map<int, int>> get tiltRows {
    final rows = <int, Map<int, int>>{};
    for (final entry in tuning.obj('tilt_rows').entries) {
      final parts = entry.key.split('_');
      (rows[int.parse(parts[0])] ??= {})[int.parse(parts[1])] = entry.value
          .toInt();
    }
    return rows;
  }

  static double get dyRefBand => tuning.d('dy_ref_band');
  static double get hardHoopDyFactor => tuning.d('dy_hard_factor');
  // endregion

  /// PRD-2.6 D2 the moving-ring rendered-angle cap before hoop 150.
  static const double movingTiltCapBefore150Deg = 15;

  /// PRD-2.6 D2 the moving-ring rendered-angle cap from hoop 150.
  static const double movingTiltCapFrom150Deg = 30;

  /// PRD-2.6 D2 the hoop index where moving rings get the wider tilt cap.
  static const int movingTiltCapFromHoop = 150;

  /// PRD-2.6 D2 the largest allowed motion speed (pt/s).
  static const double motionSpeedCap = 42;

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

  /// PRD-2.6 D2 one motion-type / speed row.
  static const List<
    ({
      int from,
      Map<MotionType, int> types,
      (double, double) halfTravel,
      (double, double) speed,
    })
  >
  motionRows = [
    (
      from: 25,
      types: {MotionType.rail: 100},
      halfTravel: (30, 45),
      speed: (22, 28),
    ),
    (
      from: 35,
      types: {MotionType.rail: 75, MotionType.swing: 25},
      halfTravel: (40, 60),
      speed: (26, 34),
    ),
    (
      from: 70,
      types: {
        MotionType.rail: 55,
        MotionType.swing: 15,
        MotionType.horizontal: 15,
        MotionType.diagonal: 15,
      },
      halfTravel: (40, 60),
      speed: (30, 39),
    ),
    (
      from: 90,
      types: {
        MotionType.rail: 45,
        MotionType.swing: 15,
        MotionType.horizontal: 10,
        MotionType.diagonal: 10,
        MotionType.orbit: 10,
        MotionType.rock: 10,
      },
      halfTravel: (40, 60),
      speed: (30, 39),
    ),
    (
      from: 120,
      types: {
        MotionType.rail: 45,
        MotionType.swing: 15,
        MotionType.horizontal: 10,
        MotionType.diagonal: 10,
        MotionType.orbit: 10,
        MotionType.rock: 10,
      },
      halfTravel: (40, 60),
      speed: (34, 42),
    ),
  ];

  /// §3.11 Rail slide geometry; PRD-2.6 D2 supplies the row-specific travel
  /// and speed ranges (horizontal / diagonal slides share them).
  static const RailTable rail = RailTable(
    axisDeg: (-25, 25),
    halfTravel: (40, 60),
    speed: (30, 39),
  );

  /// §3.11 Swing: ±15°; the 1.8 s value is the legacy fallback for specs
  /// without a director-issued row speed.
  static const SwingTable swing = SwingTable(amplitudeDeg: 15, period: 1.8);

  /// §3.11 Orbit: the ring's angle changes ±22° along the path.
  static const double orbitTiltDeg = 22;

  /// PRD-2.6 D2 before hoop 150 an orbit's own angle is capped at 15°.
  static const double orbitTiltBefore150Deg = 15;

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
