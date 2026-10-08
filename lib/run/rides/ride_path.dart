import 'dart:math' as math;

import 'package:flame/components.dart';

/// One piece of a ride path (PRD-2 §7: "path from arc/line segments").
class RideSeg {
  /// A straight line of [length] pt along the current heading.
  const RideSeg.line(this.length) : radius = 0, turnDeg = 0;

  /// An arc of [radius] pt turning by [turnDeg]° (positive = clockwise on
  /// screen, i.e. toward +y when heading right; negative = up).
  const RideSeg.arc(this.radius, this.turnDeg) : length = 0;

  final double length;
  final double radius;
  final double turnDeg;

  bool get isLine => radius == 0;
}

/// A sampled point of a [RidePath]: position, heading (rad, screen: 0 =
/// right, +π/2 = down), arc length and depth (storm funnel: −1 back … +1
/// front).
class RidePoint {
  RidePoint(this.x, this.y, {this.h, this.d = 0});
  final double x, y;
  double? h;
  double s = 0;
  final double d;
}

/// A ride path (PRD-2 §3.12, §7; `rides84.js` `buildPath` / `atS`): a
/// polyline sampled every ≤ 8 pt on lines and every 2° on arcs, or any
/// sampled curve (the storm corkscrew). Starts at (0, 0) heading right
/// unless a pre-path is given. [at] / [headingAt] / [depthAt] interpolate
/// by arc length.
class RidePath {
  RidePath._(this.points) {
    _measure();
  }

  /// Builds the path from [segs] (after the optional [pre] points).
  factory RidePath.segments(List<RideSeg> segs, {List<RidePoint>? pre}) =>
      RidePath._(_build(segs, pre));

  /// A sampled curve (headings from the chords where missing).
  factory RidePath.sampled(List<RidePoint> points) => RidePath._(points);

  final List<RidePoint> points;
  late final double length;

  /// Extra data a theme may attach (the storm's funnel axis).
  double axisX = 0;

  static List<RidePoint> _build(List<RideSeg> segs, List<RidePoint>? pre) {
    final p = pre != null ? [...pre] : [RidePoint(0, 0, h: 0)];
    var x = p.last.x, y = p.last.y, h = p.last.h ?? 0;
    for (final g in segs) {
      if (g.isLine) {
        final n = (g.length / 8).ceil();
        for (var i = 0; i < n; i++) {
          x += g.length / n * math.cos(h);
          y += g.length / n * math.sin(h);
          p.add(RidePoint(x, y, h: h));
        }
      } else {
        final sg = g.turnDeg.sign;
        final tot = g.turnDeg.abs() * math.pi / 180;
        final n = (tot / (2 * math.pi / 180)).ceil();
        final cx = x + g.radius * math.cos(h + sg * math.pi / 2);
        final cy = y + g.radius * math.sin(h + sg * math.pi / 2);
        for (var i = 1; i <= n; i++) {
          final h2 = h + sg * tot * i / n;
          p.add(
            RidePoint(
              cx + g.radius * math.cos(h2 - sg * math.pi / 2),
              cy + g.radius * math.sin(h2 - sg * math.pi / 2),
              h: h2,
            ),
          );
        }
        x = p.last.x;
        y = p.last.y;
        h = p.last.h!;
      }
    }
    return p;
  }

  void _measure() {
    var s = 0.0;
    points.first.s = 0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      s += math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
      b.s = s;
      b.h ??= math.atan2(b.y - a.y, b.x - a.x);
    }
    if (points.length > 1) points.first.h ??= points[1].h;
    points.first.h ??= 0;
    length = s;
  }

  (RidePoint, RidePoint, double) _bracket(double s) {
    final c = s.clamp(0.0, length);
    var lo = 0, hi = points.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) >> 1;
      if (points[m].s < c) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final a = points[lo], b = points[hi];
    final span = b.s - a.s;
    return (a, b, span <= 0 ? 0 : (c - a.s) / span);
  }

  /// The point at arc length [s] (clamped to the path).
  Vector2 at(double s) {
    final (a, b, k) = _bracket(s);
    return Vector2(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k);
  }

  /// The heading at [s] (rad, unwrapped between the two samples).
  double headingAt(double s) {
    final (a, b, k) = _bracket(s);
    var dh = b.h! - a.h!;
    while (dh > math.pi) {
      dh -= 2 * math.pi;
    }
    while (dh < -math.pi) {
      dh += 2 * math.pi;
    }
    return a.h! + dh * k;
  }

  /// The funnel depth at [s] (0 on flat paths).
  double depthAt(double s) {
    final (a, b, k) = _bracket(s);
    return a.d + (b.d - a.d) * k;
  }

  /// The last point.
  Vector2 get end => Vector2(points.last.x, points.last.y);

  /// [n] stations at equal arc length from [first] to `length − endMargin`
  /// (`rides84.js`: 11 rings from 190 to L − 260).
  List<double> equalStations(int n, {double first = 190, double endMargin = 260}) {
    final last = length - endMargin;
    final step = (last - first) / (n - 1);
    return [for (var k = 0; k < n; k++) first + k * step];
  }

  /// [n] stations every [step] pt from [first] (the cannon ride: 190 + 380k).
  static List<double> everyStep(int n, {double first = 190, double step = 380}) =>
      [for (var k = 0; k < n; k++) first + k * step];

  /// The axis-aligned bounds of the path.
  (double, double, double, double) get bounds {
    var x0 = double.infinity, y0 = double.infinity;
    var x1 = -double.infinity, y1 = -double.infinity;
    for (final p in points) {
      x0 = math.min(x0, p.x);
      y0 = math.min(y0, p.y);
      x1 = math.max(x1, p.x);
      y1 = math.max(y1, p.y);
    }
    return (x0, y0, x1, y1);
  }
}
