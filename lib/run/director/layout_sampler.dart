import 'dart:math';

import '../config/director_tables.dart';
import '../config/layout_config.dart';
import '../config/run_config.dart';
import '../config/tuning_values.dart';
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

  /// PRD-2.6 D2 whether the next Δy follows a moving or ≥30° tilted hoop.
  bool _hardFollowUp = false;

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
    final centreMid = (ctx.topTooth + ctx.floorTooth) / 2;
    final m = opening / 2 + RunConfig.rimRadius + RunConfig.bandMargin + extra;
    // PRD-2.6 D2: the centre rows are fractions of the full band; only the
    // Δy rows use `dyRef = min(band, 540 pt)` (see nextCentre). Above the
    // 711 pt design height the D2 fairness rule (R2 / §3.D) keeps Δy in
    // points identical at 711 and 730 pt. A wider row envelope would clip a
    // step later on the taller screen and change the whole course, so the
    // envelope stays the design band's (623 pt) and is centred in the
    // taller band. At 568 and 711 pt this is the full band.
    final designBand = RunConfig.designHeight - 2 * RunConfig.stripHeight;
    final centreBand = min(ctx.band, designBand);
    var lo = useTable
        ? centreMid + (b.centre.$1 - 0.5) * centreBand
        : ctx.topTooth;
    var hi = useTable
        ? centreMid + (b.centre.$2 - 0.5) * centreBand
        : ctx.floorTooth;
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
    const a = LayoutConfig.dyMedianU, b = LayoutConfig.dyP90U;
    if (u < a) return m * u / a;
    if (u < b) return m + (p90 - m) * (u - a) / (b - a);
    return p90 + (mx - p90) * (u - b) / (1 - b);
  }

  /// §3.0.2 The next centre for slot [hoopIndex].
  double nextCentre(
    int hoopIndex,
    DirectorContext ctx,
    double opening, {
    double extra = 0,
    bool hardFollowUp = false,
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
      // region WP-3c — §3.23 the ring after a spring sits 240 pt away
      // inside the band (band rule), even outside the row's centre range.
      final (flo, fhi) = limits(
        hoopIndex,
        ctx,
        opening,
        extra: extra,
        useTable: false,
      );
      final y = forced.clamp(flo, fhi).toDouble();
      // endregion WP-3c
      lastSign = (y - prev).sign == 0 ? lastSign : (y - prev).sign;
      lastY = y;
      return y;
    }
    final b = tables.bandFor(hoopIndex);
    final hard = hardFollowUp || _hardFollowUp;
    _hardFollowUp = false;
    final dyRef = min(ctx.band, RunConfig.dyRefBand);
    final mag =
        sampleDy(b.dy, random.nextDouble()) *
        dyRef *
        (hard ? RunConfig.hardHoopDyFactor : 1);
    var sign = random.nextDouble() < LayoutConfig.flipChance
        ? -lastSign
        : lastSign;
    var y = prev + sign * mag;
    if (y < lo || y > hi) {
      // PRD-2.6 §11 R2 fairness: Δy in points is identical at 711 and 730
      // when the band is ≥ dyRef. A step that leaves the row is shortened
      // against the edge it crossed; flipping it here would make a taller
      // screen (whose row ends further out) take the unflipped step and
      // change the whole course. The next draw still uses `lastSign` from
      // the actual edge step (the zig-zag direction is not forced).
      y = y < lo ? lo : hi;
    }
    y = y.clamp(lo, hi).toDouble();
    final s = (y - prev).sign;
    lastSign = s == 0 ? sign : s;
    lastY = y;
    return y;
  }

  /// PRD-2.6 D2 take (and clear) the hard-hoop marker before planning the
  /// next centre; the same value also bounds that slot's special checks.
  bool takeHardFollowUp() {
    final value = _hardFollowUp;
    _hardFollowUp = false;
    return value;
  }

  /// PRD-2.6 D2 record the final modifiers of the slot just planned. The
  /// director may call this more than once for a slot (it re-applies the
  /// final tilt after the hazard ledger); the result must describe the final
  /// plan, not just the latest provisional one.
  void noteModifiers({MotionSpec? motion, double tiltDeg = 0}) {
    _hardFollowUp = motion != null || tiltDeg.abs() >= 30;
  }

  /// PRD-2.6 D2 the current row's point-space Δy ceiling.
  double maxDy(
    int hoopIndex,
    DirectorContext ctx, {
    bool hardFollowUp = false,
  }) =>
      tables.bandFor(hoopIndex).dy.$3 *
      min(ctx.band, RunConfig.dyRefBand) *
      (hardFollowUp ? RunConfig.hardHoopDyFactor : 1);

  /// §3.0.2 / §3.10 Tilt roll for a normal hoop (degrees, 0 = upright).
  /// [force] = first-meet / debug: always tilted (from the band's weights,
  /// or the hoop-10 row when the band has none).
  double tilt(
    int hoopIndex, {
    bool force = false,
    double maxTiltDeg = RunConfig.maxTiltDeg,
  }) {
    final roll = random.nextDouble();
    // PRD-2.3 §14.4 the tilt chance by hoop index (`curve_tilt`).
    if (!force && roll >= tables.tiltChance(hoopIndex)) return 0;
    final rawRows = tuning.obj('tilt_rows');
    var rowFrom = 10;
    for (final key in rawRows.keys) {
      final from = int.parse(key.split('_').first);
      if (hoopIndex >= from && from >= rowFrom) rowFrom = from;
    }
    final weights = <int, int>{
      for (final entry in rawRows.entries)
        if (entry.key.split('_').first == '$rowFrom')
          int.parse(entry.key.split('_')[1]): entry.value.toInt(),
    };
    final ang = RunRandom.pickWeighted<int>(random, weights) ?? 0;
    final sign = random.nextBool() ? -1 : 1;
    return (sign * ang).clamp(-maxTiltDeg, maxTiltDeg).toDouble();
  }

  /// PRD-2.6 D2 applies the approach sign to strong tilts and motion/squeeze
  /// magnitude limits.
  double alignedTilt(double tiltDeg, double dy, double maxTiltDeg) {
    final alignMin = tuning.i('tilt_align_min_deg').toDouble();
    final minDy = tuning.d('tilt_align_min_dy');
    var magnitude = tiltDeg.abs();
    final wasStrong = magnitude >= alignMin;
    if (wasStrong && dy.abs() < minDy) magnitude = 15;
    magnitude = min(magnitude, maxTiltDeg);
    if (wasStrong && dy != 0) return dy.sign * magnitude;
    return tiltDeg.sign * magnitude;
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
    final roll = random.nextDouble();
    // PRD-2.3 §14.4 the moving chance by hoop index (`curve_moving`).
    if (!force && roll >= tables.movingChance(hoopIndex)) return null;
    final (lo, hi) = limits(hoopIndex, ctx, opening);
    final room = max(0.0, min(centre - lo, hi - centre));
    // The band rule (not the row's centre range) bounds a slide's travel.
    final (blo, bhi) = limits(hoopIndex, ctx, opening, useTable: false);
    final bandRoom = max(0.0, min(centre - blo, bhi - centre));
    _hardFollowUp = true;
    var row = LayoutConfig.motionRows.first;
    for (final candidate in LayoutConfig.motionRows) {
      if (hoopIndex >= candidate.from) row = candidate;
    }
    final t = RunRandom.pickWeighted<MotionType>(random, row.types)!;
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
          _ => (random.nextDouble() < 0.5 ? -1 : 1) * RunConfig.diagonalAxisDeg,
        };
        final cosA = cos(axis * pi / 180).abs();
        final want = RunRandom.range(
          random,
          row.halfTravel.$1,
          row.halfTravel.$2,
        );
        // §3.11 fairness (WP-1b): the travel is capped so the ring keeps the
        // band rule along its whole path; a slide with less than the minimum
        // travel left rocks in place instead.
        final cap = cosA < 0.2 ? rail.halfTravel.$2 : bandRoom / cosA;
        if (cap < RunConfig.railMinHalfTravel) {
          return MotionSpec(
            type: MotionType.rock,
            amplitudeDeg: RunConfig.rockAmplitudeDeg,
            period: RunConfig.rockPeriod,
            phase: RunRandom.range(random, 0, 2 * pi),
          );
        }
        final half = want.clamp(RunConfig.railMinHalfTravel, cap);
        return MotionSpec(
          type: t,
          axisDeg: axis,
          halfTravel: half.toDouble(),
          speed: RunRandom.range(random, row.speed.$1, row.speed.$2),
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
        final ry = min(RunConfig.orbitRy, room);
        return MotionSpec(
          type: t,
          rx: RunConfig.orbitRx,
          ry: ry,
          omega:
              RunRandom.range(random, row.speed.$1, row.speed.$2) /
              max(RunConfig.orbitRx, ry),
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
