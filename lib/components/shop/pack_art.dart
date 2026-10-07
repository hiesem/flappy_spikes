import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

/// The Shop's coin-pack drawings (PRD-menu-v4 §2.1, approved 2026-10-07):
/// a Canvas port of `design/menu_v2/build82.py` `A_NEW` (helpers from
/// build80 / build81). Tier 0..3 = 1 000 / 10 000 / 17 000 / 100 000.
///
/// Coordinates are the mock's: a `viewBox="0 0 120 66"` drawn into the
/// 120 x 68 art box (centred, so 1 pt lower), never clipped. Everything
/// except the sparkles is recorded once per tier as a [Picture].
abstract final class PackArtPainter {
  /// The art box inside a pack tile (mock `.packart`).
  static const Size size = Size(120, 68);

  /// `xMidYMid meet` centring of the 66 pt tall viewBox in the 68 pt box.
  static const double viewBoxDy = 1;

  /// The sparkle loop (mock `.tw`, 2.4 s, staggered 0 / 0.8 / 1.6 s).
  static const double twinkleLoop = 2.4;

  static final List<Picture?> _cache = List.filled(4, null);

  /// Paints [tier]'s art in art-box coordinates (0,0 = the box's top-left)
  /// at idle time [t]; [still] = reduce motion (sparkles at rest, shown).
  static void paint(Canvas canvas, int tier, double t, {bool still = false}) {
    canvas
      ..save()
      ..translate(0, viewBoxDy)
      ..drawPicture(_cache[tier] ??= _record(tier));
    for (final s in _sparks[tier]) {
      _spark(canvas, s, t, still);
    }
    canvas.restore();
  }

  /// Top of the heap in art-box coordinates: the coin-pack celebration's
  /// coins burst out of this box's top centre (PRD-home-v3 §5).
  static Rect heapBox(int tier) => switch (tier) {
    0 => const Rect.fromLTRB(32, 36, 88, 67),
    1 => const Rect.fromLTRB(12, 6, 112, 67),
    2 => const Rect.fromLTRB(4, 29, 118, 67),
    _ => const Rect.fromLTRB(4, 30, 118, 67),
  };

  static Picture _record(int tier) {
    final recorder = PictureRecorder();
    final c = Canvas(recorder);
    switch (tier) {
      case 0:
        _tier0(c);
      case 1:
        _tier1(c);
      case 2:
        _tier2(c);
      default:
        _tier3(c);
    }
    return recorder.endRecording();
  }

  // --- the four drawings (build82 A_NEW) ----------------------------------

  /// 1 000 — a small heap: a short stack, a leaning stack and coins at
  /// different angles.
  static void _tier0(Canvas c) {
    _lean(c, 48, 62, 3, -12);
    _stack(c, 66, 4, w: 18);
    _tilt(c, 80, 58, 8, 18, .45);
    _tilt(c, 40, 61, 8, -8, .4);
    _coin(c, 58, 52, 7);
    _tilt(c, 62, 63, 9, 0, .35);
  }

  /// 10 000 — a bigger heap: stacks of different heights, leaning stacks
  /// and many coins at all angles.
  static void _tier1(Canvas c) {
    _lean(c, 28, 62, 4, -18);
    _stack(c, 46, 7, w: 17);
    _stack(c, 64, 9, w: 17);
    _lean(c, 84, 62, 6, 14);
    _stack(c, 98, 3, w: 15);
    _tilt(c, 20, 60, 8, -20, .45);
    _tilt(c, 104, 59, 8, 25, .45);
    _coin(c, 40, 52, 7);
    _coin(c, 76, 50, 7);
    _tilt(c, 56, 63, 10, 4, .35);
    _tilt(c, 86, 63, 9, -6, .35);
    _tilt(c, 64, 7, 7, 30, .5);
    _tilt(c, 32, 63, 8, 0, .35);
  }

  /// 17 000 — the piggy bank with heaps on both sides, a coin dropping in.
  static void _tier2(Canvas c) {
    _lean(c, 14, 62, 4, -14, w: 14);
    _stack(c, 28, 3, w: 14);
    _tilt(c, 10, 61, 7, -10, .4);
    _tilt(c, 30, 63, 8, 6, .35);
    _tilt(c, 22, 46, 6, -30, .5);
    _stack(c, 100, 4, w: 14);
    _lean(c, 112, 62, 3, 16, w: 13);
    _tilt(c, 92, 62, 8, -4, .35);
    _tilt(c, 110, 63, 7, 10, .35);
    _piggy(c, 60, 60, .92);
    _tilt(c, 44, 63, 7, 0, .35);
    _tilt(c, 78, 63, 7, -8, .35);
  }

  /// 100 000 — the open treasure chest with gold bars and coins at all
  /// angles inside, a small heap on each side (all 4 pt lower).
  static void _tier3(Canvas c) {
    c
      ..save()
      ..translate(0, 4);
    _poly(c, const [(26, 26), (94, 26), (89, 6), (31, 6)], _wd);
    _rect(c, 31, 6, 58, 3, _g);
    _bar(c, 36, 16, 28, 11);
    _bar(c, 58, 18, 26, 10);
    _tilt(c, 36, 29, 7, -20, .5);
    _tilt(c, 50, 25, 7, 15, .5);
    _coin(c, 62, 28, 7);
    _tilt(c, 74, 25, 7, -10, .5);
    _tilt(c, 86, 30, 7, 25, .5);
    _tilt(c, 44, 33, 7, 5, .4);
    _tilt(c, 68, 34, 7, -15, .45);
    _tilt(c, 80, 35, 6, 0, .4);
    _rect(c, 24, 36, 72, 27, _w);
    _rect(c, 24, 36, 72, 5, _wd);
    _rect(c, 24, 49, 72, 3, _g);
    _rect(c, 34, 36, 5, 27, _g);
    _rect(c, 81, 36, 5, 27, _g);
    _rect(c, 54, 43, 12, 12, _g);
    _rect(c, 58, 46, 4, 6, _wd);
    _lean(c, 10, 62, 4, -14, w: 13);
    _tilt(c, 16, 61, 7, 12, .4);
    _stack(c, 110, 4, w: 13);
    _tilt(c, 102, 62, 7, -8, .38);
    _tilt(c, 60, 64, 8, 0, .3);
    c.restore();
  }

  /// Sparkles per tier: (x, y, size, delay) in viewBox coordinates (the
  /// 100 000's include its 4 pt shift).
  static const List<List<(double, double, double, double)>> _sparks = [
    [],
    [],
    [(86, 10, 4, 0)],
    [(30, 16, 5, 0), (92, 18, 4, .8), (60, 6, 5, 1.6)],
  ];

  // --- palette (build80 / build81) ----------------------------------------

  static const Color _g = Color(0xFFFFB529);
  static const Color _gl = Color(0xFFFFE082);
  static const Color _gd = Color(0xFFE69500);
  static const Color _gdd = Color(0xFFC47A00);
  static const Color _w = Color(0xFF8D5A2B);
  static const Color _wd = Color(0xFF5D3A1A);
  static const Color _ring = Color(0xBFFFFFFF); // #fff at .75
  static const Color _pink = Color(0xFFF48FB1);
  static const Color _pinkDark = Color(0xFFEC407A);
  static const Color _plum = Color(0xFF7A0044);

  static final Paint _fill = Paint()..isAntiAlias = true;
  static final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  // --- helpers (build80 / build81 / build82) ------------------------------

  /// Python's `f'{v:.1f}'`.
  static double _d1(double v) => (v * 10).round() / 10;

  static void _rect(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    Color k,
  ) => c.drawRect(Rect.fromLTWH(x, y, w, h), _fill..color = k);

  static void _poly(Canvas c, List<(double, double)> pts, Color k) {
    final path = Path()..moveTo(pts.first.$1, pts.first.$2);
    for (final (x, y) in pts.skip(1)) {
      path.lineTo(x, y);
    }
    c.drawPath(path..close(), _fill..color = k);
  }

  /// Coin stack seen from the side: n coins of 6 pt, alternating gold /
  /// dark gold with a 1 pt darker seam, light top face.
  static void _stack(
    Canvas c,
    double x,
    int n, {
    double y0 = 62,
    double w = 22,
  }) {
    const lh = 6.0;
    for (var i = 0; i < n; i++) {
      final y = y0 - lh * (i + 1);
      _rect(c, x - w / 2, y, w, lh, i.isEven ? _g : _gd);
      _rect(c, x - w / 2, y + lh - 1, w, 1, _gdd);
    }
    _rect(c, x - w / 2, y0 - lh * n - 3, w, 3, _gl);
  }

  /// A coin stack leaning by [a] degrees (pivot at its foot).
  static void _lean(
    Canvas c,
    double x,
    double base,
    int n,
    double a, {
    double w = 16,
  }) {
    c
      ..save()
      ..translate(x, base)
      ..rotate(a * math.pi / 180)
      ..translate(-x, -base);
    _stack(c, x, n, y0: base, w: w);
    c.restore();
  }

  /// Standing coin facing us (the game's coin: gold disc + light ring).
  static void _coin(Canvas c, double x, double y, double r) {
    c.drawCircle(Offset(x, y), r, _fill..color = _g);
    c.drawCircle(
      Offset(x, y),
      _d1(r * .65),
      _stroke
        ..color = _ring
        ..strokeWidth = _d1(r * .18),
    );
  }

  /// A coin seen at an angle: dark rim under a gold face (ellipse rx = r,
  /// ry = r * k), light ring, rotated [a] degrees.
  static void _tilt(
    Canvas c,
    double x,
    double y,
    double r,
    double a,
    double k,
  ) {
    final ry = _d1(r * k);
    c
      ..save()
      ..translate(x, y)
      ..rotate(a * math.pi / 180)
      ..drawOval(
        Rect.fromCenter(
          center: Offset(0, _d1(r * .22)),
          width: 2 * r,
          height: 2 * ry,
        ),
        _fill..color = _gd,
      )
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: 2 * r, height: 2 * ry),
        _fill..color = _g,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 2 * _d1(r * .62),
          height: 2 * _d1(r * k * .62),
        ),
        _stroke
          ..color = _ring
          ..strokeWidth = 1.4,
      )
      ..restore();
  }

  /// Gold bar: trapezoid, light top bevel, dark base.
  static void _bar(Canvas c, double x, double y, double w, double h) {
    const i = 6.0;
    _poly(c, [(x, y + h), (x + w, y + h), (x + w - i, y), (x + i, y)], _g);
    _poly(c, [
      (x + i, y),
      (x + w - i, y),
      (x + w - i - 3, y + 4),
      (x + i + 3, y + 4),
    ], _gl);
    _rect(c, x, y + h - 3, w, 3, _gdd);
  }

  /// Octagon: a w x h box with k-cut corners (build81 `oct_`).
  static void _oct(
    Canvas c,
    double x,
    double y,
    double w,
    double h,
    double k,
    Color color,
  ) => _poly(c, [
    (x + k, y),
    (x + w - k, y),
    (x + w, y + k),
    (x + w, y + h - k),
    (x + w - k, y + h),
    (x + k, y + h),
    (x, y + h - k),
    (x, y + k),
  ], color);

  /// The pink piggy bank with a coin dropping into its slot (build81).
  static void _piggy(Canvas c, double cx, double base, double s) {
    _poly(c, [
      (cx - 26 * s, base - 22 * s),
      (cx - 32 * s, base - 26 * s),
      (cx - 30 * s, base - 19 * s),
    ], _pinkDark); // tail
    _rect(c, cx - 18 * s, base - 6 * s, 8 * s, 6 * s, _pinkDark); // legs
    _rect(c, cx + 10 * s, base - 6 * s, 8 * s, 6 * s, _pinkDark);
    _oct(c, cx - 26 * s, base - 34 * s, 52 * s, 30 * s, 10 * s, _pink);
    _poly(c, [
      (cx + 8 * s, base - 34 * s),
      (cx + 14 * s, base - 42 * s),
      (cx + 18 * s, base - 32 * s),
    ], _pinkDark); // ear
    _rect(c, cx + 24 * s, base - 24 * s, 7 * s, 10 * s, _pinkDark); // snout
    _rect(c, cx + 12 * s, base - 27 * s, 4 * s, 4 * s, const Color(0xFFFFFFFF));
    _rect(c, cx - 8 * s, base - 34 * s, 14 * s, 3 * s, _plum); // slot
    _coin(c, cx - 1 * s, base - 44 * s, 6 * s); // dropping in
  }

  static final Paint _sparkPaint = Paint()..isAntiAlias = true;

  /// A white four-point sparkle twinkling on the mock's `tw` keyframes:
  /// hidden 0–60 %, scale 1 / 45° / opacity 1 at 75 %, 0.6 / 90° / 0.8
  /// at 90 %, gone at 100 % (ease-in-out per segment). [still] draws it
  /// at rest at full size.
  static void _spark(
    Canvas c,
    (double, double, double, double) spark,
    double t,
    bool still,
  ) {
    final (x, y, s, delay) = spark;
    double scale, deg, alpha;
    if (still) {
      (scale, deg, alpha) = (1, 0, 1);
    } else {
      final p = ((t - delay) % twinkleLoop) / twinkleLoop;
      if (p < .6) return;
      double lerp(double a, double b, double u) => a + (b - a) * u;
      if (p < .75) {
        final u = Curves.easeInOut.transform((p - .6) / .15);
        (scale, deg, alpha) = (u, 45 * u, u);
      } else if (p < .9) {
        final u = Curves.easeInOut.transform((p - .75) / .15);
        (scale, deg, alpha) = (lerp(1, .6, u), lerp(45, 90, u), lerp(1, .8, u));
      } else {
        final u = Curves.easeInOut.transform((p - .9) / .1);
        (scale, deg, alpha) = (lerp(.6, 0, u), lerp(90, 0, u), lerp(.8, 0, u));
      }
      if (scale <= 0 || alpha <= 0) return;
    }
    final path = Path()
      ..moveTo(0, -s)
      ..lineTo(s * .3, -s * .3)
      ..lineTo(s, 0)
      ..lineTo(s * .3, s * .3)
      ..lineTo(0, s)
      ..lineTo(-s * .3, s * .3)
      ..lineTo(-s, 0)
      ..lineTo(-s * .3, -s * .3)
      ..close();
    c
      ..save()
      ..translate(x, y)
      ..scale(scale)
      ..rotate(deg * math.pi / 180)
      ..drawPath(
        path,
        _sparkPaint..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0, 1)),
      )
      ..restore();
  }
}

/// A pack tile's art box ([PackArtPainter.size]) drawing [tier]'s art at
/// the Shop clock's time [t]; [still] = reduce motion.
class PackArt extends PositionComponent {
  PackArt({required this.tier, super.position})
    : super(
        size: Vector2(PackArtPainter.size.width, PackArtPainter.size.height),
      );

  final int tier;
  double t = 0;
  bool still = false;

  @override
  void render(Canvas canvas) =>
      PackArtPainter.paint(canvas, tier, t, still: still);
}
