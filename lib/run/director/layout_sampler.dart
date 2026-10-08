import 'dart:math';

import '../config/director_tables.dart';
import '../config/run_config.dart';
import 'director_context.dart';
import 'plans.dart';
import 'rng.dart';

/// §3.0.2 hoop layout: centre heights by |Δy| quantile sampling with
/// zig-zag direction, the band rule, tilt and motion picks. Pure Dart; all
/// draws come from the run's `layout` stream.
class LayoutSampler {
  LayoutSampler(this.tables, this.random);

  final DirectorTables tables;
  final Random random;

  /// Previous centre (null before the first slot → exact band centre).
  double? lastY;
  double lastSign = 1;

  /// A forced next centre (spring launch target, §3.23).
  double? forceY;

  /// §3.0.2 band rule: the centre range for a hoop with [opening] at
  /// [hoopIndex] — the table's fractions of the band, at least
  /// opening/2 + 7 + 18 (+ [extra]) from each tooth line; the squeezed band
  /// during the squeeze window. Returns (lo, hi) with lo ≤ hi.
  (double, double) limits(
    int hoopIndex,
    DirectorContext ctx,
    double opening, {
    double extra = 0,
    bool useTable = true,
  }) {
    final b = tables.bandFor(hoopIndex);
    final band = ctx.band;
    final m = opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin + extra;
    var lo = useTable ? ctx.topTooth + b.centre.$1 * band : ctx.topTooth;
    var hi = useTable ? ctx.topTooth + b.centre.$2 * band : ctx.floorTooth;
    if (ctx.squeezeWindow) {
      lo = ctx.squeezeTopTooth + m;
      hi = ctx.squeezeFloorTooth - m;
    }
    lo = max(lo, (ctx.squeezeWindow ? ctx.squeezeTopTooth : ctx.topTooth) + m);
    hi = min(
      hi,
      (ctx.squeezeWindow ? ctx.squeezeFloorTooth : ctx.floorTooth) - m,
    );
    if (lo > hi) {
      final mid = (lo + hi) / 2;
      return (mid, mid);
    }
    return (lo, hi);
  }

  /// §3.0.2 |Δy| draw: u < 0.5 → 0…median; u < 0.9 → median…p90;
  /// else p90…max (fractions of the band).
  static double sampleDy((double, double, double) q, double u) {
    final (m, p90, mx) = q;
    if (u < 0.5) return m * u / 0.5;
    if (u < 0.9) return m + (p90 - m) * (u - 0.5) / 0.4;
    return p90 + (mx - p90) * (u - 0.9) / 0.1;
  }

  /// §3.0.2 The next centre for slot [hoopIndex].
  double nextCentre(
    int hoopIndex,
    DirectorContext ctx,
    double opening, {
    double extra = 0,
  }) {
    final (lo, hi) = limits(hoopIndex, ctx, opening, extra: extra);
    final prev = lastY;
    if (prev == null) {
      // Hoop 0 (and the first slot of a startHoopIndex run): exact centre.
      final y = ((ctx.topTooth + ctx.floorTooth) / 2).clamp(lo, hi);
      lastY = y;
      return y;
    }
    final forced = forceY;
    if (forced != null) {
      forceY = null;
      final y = forced.clamp(lo, hi).toDouble();
      lastSign = (y - prev).sign == 0 ? lastSign : (y - prev).sign;
      lastY = y;
      return y;
    }
    final b = tables.bandFor(hoopIndex);
    final mag = sampleDy(b.dy, random.nextDouble()) * ctx.band;
    var sign = random.nextDouble() < 0.65 ? -lastSign : lastSign;
    var y = prev + sign * mag;
    if (y < lo || y > hi) {
      sign = -sign;
      y = prev + sign * mag;
    }
    y = y.clamp(lo, hi).toDouble();
    final s = (y - prev).sign;
    lastSign = s == 0 ? sign : s;
    lastY = y;
    return y;
  }

  /// §3.0.2 / §3.10 Tilt roll for a normal hoop (degrees, 0 = upright).
  /// [force] = first-meet / debug: always tilted (from the band's weights,
  /// or the hoop-10 row when the band has none).
  double tilt(int hoopIndex, {bool force = false}) {
    final b = tables.bandFor(hoopIndex);
    final roll = random.nextDouble();
    if (!force && roll >= b.tilt) return 0;
    final weights = b.tiltWeights.isNotEmpty
        ? b.tiltWeights
        : tables.bandFor(10).tiltWeights;
    final ang = RunRandom.pickWeighted<int>(random, weights) ?? 0;
    return ang.toDouble().clamp(-RunConfig.maxTiltDeg, RunConfig.maxTiltDeg);
  }

  /// §3.0.2 / §3.11 Motion roll for a normal hoop at [centre]. Never during
  /// the squeeze window. [force] = first-meet / debug.
  MotionSpec? motion(
    int hoopIndex,
    DirectorContext ctx,
    double centre,
    double opening, {
    bool force = false,
  }) {
    if (ctx.squeezeWindow) return null;
    final b = tables.bandFor(hoopIndex);
    final roll = random.nextDouble();
    if (!force && roll >= b.moving) return null;
    final (lo, hi) = limits(hoopIndex, ctx, opening);
    final room = max(0.0, min(centre - lo, hi - centre));
    final types = hoopIndex >= 45 ? tables.movingTypes45 : tables.movingTypes20;
    final t = RunRandom.pickWeighted<MotionType>(random, types)!;
    final rail = tables.rail;
    switch (t) {
      case MotionType.rail:
      case MotionType.horizontal:
      case MotionType.diagonal:
        final axis = switch (t) {
          MotionType.rail => RunRandom.range(
            random,
            rail.axisDeg.$1,
            rail.axisDeg.$2,
          ),
          MotionType.horizontal => RunConfig.horizontalAxisDeg,
          _ =>
            (random.nextDouble() < 0.5 ? -1 : 1) * RunConfig.diagonalAxisDeg,
        };
        final cosA = cos(axis * pi / 180).abs();
        final want = RunRandom.range(
          random,
          rail.halfTravel.$1,
          rail.halfTravel.$2,
        );
        final cap = cosA < 0.2 ? rail.halfTravel.$2 : room / cosA;
        final half = want.clamp(
          RunConfig.railMinHalfTravel,
          max(RunConfig.railMinHalfTravel, cap),
        );
        return MotionSpec(
          type: t,
          axisDeg: axis,
          halfTravel: half.toDouble(),
          speed: RunRandom.range(random, rail.speed.$1, rail.speed.$2),
          phase: random.nextDouble(),
        );
      case MotionType.swing:
        return MotionSpec(
          type: t,
          amplitudeDeg: tables.swing.amplitudeDeg,
          period: tables.swing.period,
          rope: max(
            RunConfig.swingMinRope,
            centre - ctx.topTooth + RunConfig.swingPivotAbove,
          ),
          phase: RunRandom.range(random, 0, 2 * pi),
        );
      case MotionType.orbit:
        return MotionSpec(
          type: t,
          rx: RunConfig.orbitRx,
          ry: min(RunConfig.orbitRy, room),
          omega: RunConfig.orbitOmega,
          phase: RunRandom.range(random, 0, 2 * pi),
        );
      case MotionType.rock:
        return MotionSpec(
          type: t,
          amplitudeDeg: RunConfig.rockAmplitudeDeg,
          period: RunConfig.rockPeriod,
          phase: RunRandom.range(random, 0, 2 * pi),
        );
    }
  }
}
