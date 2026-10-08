import 'dart:math' as math;
import 'dart:ui';

import '../ring_painter.dart';

/// Small drawing helpers shared by the WP-3d ring designs (saw, switch and
/// pair rings; PRD-2 §5.17, §5.19, §5.20). They port the mocks' canvas
/// helpers (`rarc`, `ellPt`, `isFront`, `glowShell`, `fpoly`, `rnd`, `mul`,
/// `lseg` / `lightning`) so the designs read like the mock code. All in
/// ring-local coordinates (centre 0, 0; the hoop component carries the
/// position). Rings are ellipses of half width [rx] (12, master #3) and a
/// design-given half height.
abstract final class RingArcs {
  static const double rx = RingPainter.rx;
  static const double tau = math.pi * 2;

  /// The front half is the left half (cos a < 0), drawn over the bird.
  static bool isFront(double a) => math.cos(a) < 0;

  /// A point on the ring ellipse at angle [a], pushed [o] pt outward.
  static Offset ellPt(double ry, double a, [double o = 0, double x = rx]) =>
      Offset((x + o) * math.cos(a), (ry + o) * math.sin(a));

  /// The outward normal direction (rad) of the ellipse at angle [a].
  static double normal(double ry, double a) =>
      math.atan2(math.sin(a) / ry, math.cos(a) / rx);

  /// The half ellipse path ([front] = left half), or the full ellipse.
  static Path half(
    double ry, {
    required bool front,
    double x = rx,
    double cx = 0,
    double cy = 0,
    bool full = false,
  }) {
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: 2 * x,
      height: 2 * ry,
    );
    if (full) return Path()..addOval(rect);
    return Path()
      ..arcTo(rect, front ? math.pi / 2 : -math.pi / 2, math.pi, true);
  }

  static final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _fill = Paint();

  /// Strokes [path] ([blur] > 0 adds a soft glow in [glow], the canvas
  /// `shadowBlur` of the mocks).
  static void stroke(
    Canvas canvas,
    Path path,
    Color color,
    double width, {
    double blur = 0,
    Color? glow,
    StrokeCap cap = StrokeCap.round,
  }) {
    if (color.a <= 0 || width <= 0) return;
    if (blur > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = cap
          ..strokeWidth = width * 1.6
          ..color = (glow ?? color).withValues(alpha: (glow ?? color).a * .55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
      );
    }
    _stroke
      ..strokeWidth = width
      ..strokeCap = cap
      ..color = color;
    canvas.drawPath(path, _stroke);
  }

  /// The mocks' `glowShell`: soft wide strokes along one half.
  static void glowShell(
    Canvas canvas,
    double ry,
    bool front,
    List<(double, double)> layers,
    Color color,
  ) {
    final p = half(ry, front: front);
    for (final (w, a) in layers) {
      stroke(canvas, p, color.withValues(alpha: a.clamp(0.0, 1.0)), w);
    }
  }

  /// A filled polygon.
  static void poly(Canvas canvas, List<Offset> pts, Color color) {
    if (pts.length < 3) return;
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    p.close();
    canvas.drawPath(p, _fill..color = color);
  }

  /// A radial halo (the mocks' `halo`): [color] at [alpha] fading to 0.
  static void halo(
    Canvas canvas,
    Offset c,
    double r,
    Color color,
    double alpha, {
    double sy = 1,
  }) {
    if (r <= 0 || alpha <= 0) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (sy != 1) canvas.scale(1, sy);
    final a = alpha.clamp(0.0, 1.0);
    _fill.shader = Gradient.radial(Offset.zero, r, [
      color.withValues(alpha: a),
      color.withValues(alpha: 0),
    ]);
    canvas.drawRect(Rect.fromCircle(center: Offset.zero, radius: r), _fill);
    _fill.shader = null;
    canvas.restore();
  }

  /// A four-point star (the mocks' `star4`).
  static void star4(Canvas canvas, Offset c, double s, Color color) {
    final x = c.dx, y = c.dy;
    poly(canvas, [
      Offset(x, y - s),
      Offset(x + s * .22, y),
      Offset(x, y + s),
      Offset(x - s * .22, y),
    ], color);
    poly(canvas, [
      Offset(x - s, y),
      Offset(x, y + s * .22),
      Offset(x + s, y),
      Offset(x, y - s * .22),
    ], color);
  }

  /// The mocks' deterministic `rnd(n)` (cosmetic only).
  static double rnd(num n) {
    final v = math.sin(n * 127.1 + 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  /// Ease in-out (the mocks' `io`).
  static double io(double u) =>
      u < .5 ? 2 * u * u : 1 - math.pow(-2 * u + 2, 2) / 2;

  /// Back-out overshoot (the mocks' `back`).
  static double back(double u) {
    const k = 1.9;
    return 1 + (k + 1) * math.pow(u - 1, 3) + k * math.pow(u - 1, 2);
  }

  static double clamp01(double u) => u.clamp(0.0, 1.0);
}

/// The mocks' seeded `mul` (mulberry32) — redraw-stable random numbers.
class Mulberry {
  Mulberry(int seed) : _a = seed & 0xFFFFFFFF;
  int _a;

  double call() {
    _a = (_a + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _imul(_a ^ (_a >>> 15), 1 | _a);
    t = (t + _imul(t ^ (t >>> 7), 61 | t)) & 0xFFFFFFFF ^ t;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296;
  }

  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;
}

/// One lightning segment (x0, y0, x1, y1) of fork [depth].
typedef BoltSeg = (double, double, double, double, int);

/// Midpoint-displacement lightning with forks (the Live Wire mock's
/// `lseg` / `lightning`).
abstract final class Lightning {
  static void seg(
    double x0,
    double y0,
    double x1,
    double y1,
    double disp,
    Mulberry r,
    List<BoltSeg> out,
    int dep,
  ) {
    if (disp < 2) {
      out.add((x0, y0, x1, y1, dep));
      return;
    }
    final mx = (x0 + x1) / 2 + (r() - .5) * disp;
    final my = (y0 + y1) / 2 + (r() - .5) * disp;
    seg(x0, y0, mx, my, disp / 2, r, out, dep);
    seg(mx, my, x1, y1, disp / 2, r, out, dep);
    if (dep < 2 && disp > 5 && r() < .3) {
      final a = math.atan2(y1 - y0, x1 - x0) + (r() - .5) * 1.9;
      final l =
          math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2)) *
          (.5 + r() * .6);
      seg(
        mx,
        my,
        mx + math.cos(a) * l,
        my + math.sin(a) * l,
        disp / 2,
        r,
        out,
        dep + 1,
      );
    }
  }

  static final Paint _p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Glow pass (cyan, blur 24), body `#7DF9FF`, white core; [k] scales the
  /// widths.
  static void paint(
    Canvas canvas,
    List<BoltSeg> segs, {
    double k = 1,
    Color glow = const Color(0x613CC8FF),
    Color body = const Color(0xFF7DF9FF),
  }) {
    if (segs.isEmpty) return;
    for (final (col, w, blur) in [
      (glow, 10.0, 24.0),
      (body, 3.4, 10.0),
      (const Color(0xFFFFFFFF), 1.5, 0.0),
    ]) {
      _p
        ..color = col
        ..maskFilter = blur > 0
            ? MaskFilter.blur(BlurStyle.normal, blur / 3)
            : null;
      for (var dep = 0; dep < 3; dep++) {
        final path = Path();
        var any = false;
        for (final s in segs) {
          if (s.$5 != dep) continue;
          path
            ..moveTo(s.$1, s.$2)
            ..lineTo(s.$3, s.$4);
          any = true;
        }
        if (!any) continue;
        _p.strokeWidth = math.max(.5, w * k * (1 - dep * .33));
        canvas.drawPath(path, _p);
      }
    }
    _p.maskFilter = null;
  }
}
