import 'dart:math' as math;
import 'dart:ui';

import '../config/handover_config.dart';
import '../director/plans.dart';

double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _smooth(double x) {
  final k = _clamp01(x);
  return k * k * (3 - 2 * k);
}

double _smoother(double x) {
  final k = _clamp01(x);
  return k * k * k * (k * (k * 6 - 15) + 10);
}

double _lerp(double a, double b, double k) => a + (b - a) * k;
double _mod(double a, double n) => ((a % n) + n) % n;

/// PRD-2.4 §3.5 the way back of the five themed rides (`REVEAL`,
/// `sceneClip`, `sceneEdge` of `docs/p24/ride_landings.html`): from the
/// launch the ride's scene leaves in its own direction behind a leaving
/// edge in the ride's look, and the world arrives behind it, layer by
/// layer. The cannon has none (it keeps its tint and its camera).
///
/// The prototype's 320 × 568 view: `VW` is the view width, `VH` the view
/// height (WP-R call: on taller views the scene leaves over the whole
/// height, so it always clears the screen).
class RideReveal {
  const RideReveal._(this.dirX, this.dirY, this.distance);

  /// Where the world comes from (unit-ish vector, `REVEAL[id].dir`).
  final double dirX, dirY;

  /// How far each layer travels (pt; sky, far, mid, near — `REVEAL[id].D`).
  final List<double> distance;

  /// PRD-2.4 §3.5 table (space, sea, volcano, pinball, storm).
  static const RideReveal space = RideReveal._(0, 1, [120, 260, 420, 560]);
  static const RideReveal sea = RideReveal._(1, 0, [90, 220, 360, 500]);
  static const RideReveal volcano = RideReveal._(0, -1, [100, 220, 340, 460]);
  static const RideReveal pinball = RideReveal._(.6, -.8, [100, 220, 340, 460]);
  static const RideReveal storm = RideReveal._(0, 1, [60, 140, 220, 300]);

  /// The reveal of ride [id] (null: the cannon).
  static RideReveal? of(RideId id) => switch (id) {
    RideId.cannon => null,
    RideId.space => space,
    RideId.sea => sea,
    RideId.volcano => volcano,
    RideId.pinball => pinball,
    RideId.storm => storm,
  };

  /// How far the scene has left, [tau] s after the launch (0 before it,
  /// 1 from [HandoverConfig.sceneLeave] on): `smooth(τ / 1.7)`.
  static double progress(double tau) =>
      tau < 0 ? 0 : _smooth(tau / HandoverConfig.sceneLeave);

  /// How much of layer [band]'s travel is still ahead, [tau] s after the
  /// launch: `1 − smoother((τ − lag) / 1.9)` (1 before the layer starts,
  /// 0 once it has arrived).
  static double remaining(int band, double tau) =>
      1 -
      _smoother(
        (tau - HandoverConfig.arriveLag[band]) / HandoverConfig.arriveTime,
      );

  /// The time after the launch by which every layer has arrived (s).
  static double get arrived =>
      HandoverConfig.arriveLag.reduce(math.max) + HandoverConfig.arriveTime;

  // ------------------------------------------------------------------ clip

  /// `sceneClip`: adds to [path] the part of the [w] × [h] screen ride
  /// [id]'s scene still covers at progress [p] and clock [t].
  static void sceneClip(Path path, RideId id, double p, double t, double w, double h) {
    switch (id) {
      case RideId.space:
        final yb = _lerp(h + 40, -110, p);
        path
          ..moveTo(-10, -10)
          ..lineTo(w + 10, -10);
        for (var x = w + 10; x >= -10; x -= 10) {
          path.lineTo(x, _spaceY(yb, x));
        }
        path.close();
      case RideId.sea:
        final xb = _lerp(w + 40, -70, p);
        path.moveTo(-10, -10);
        for (var y = -10.0; y <= h + 10; y += 8) {
          path.lineTo(_seaX(xb, y, t), y);
        }
        path
          ..lineTo(-10, h + 10)
          ..close();
      case RideId.volcano:
        final yb = _lerp(-50, h + 110, p);
        path.moveTo(-10, h + 10);
        for (var x = -10.0; x <= w + 10; x += 10) {
          path.lineTo(x, _volcanoY(yb, x, t));
        }
        path
          ..lineTo(w + 10, h + 10)
          ..close();
      case RideId.pinball:
        final k = _lerp(-120, h + 260, p), tn = math.tan(.42);
        path
          ..moveTo(-10, k + 170 * tn)
          ..lineTo(w + 10, k - 170 * tn)
          ..lineTo(w + 10, h + 300)
          ..lineTo(-10, h + 300)
          ..close();
      case RideId.storm:
        final g = _lerp(0, 250, p);
        path
          ..addRect(Rect.fromLTRB(math.min(-10, 160 - g), -10, math.max(-10, 160 - g), h + 10))
          ..addRect(Rect.fromLTRB(math.min(160 + g, w + 10), -10, math.max(160 + g, w + 10), h + 10));
      case RideId.cannon:
        break;
    }
  }

  static double _spaceY(double yb, double x) =>
      yb + ((x - 160) / 160) * ((x - 160) / 160) * 30;
  static double _seaX(double xb, double y, double t) =>
      xb + math.sin(y / 38 + t * 3) * 9 + math.sin(y / 13 - t * 5) * 3;
  static double _volcanoY(double yb, double x, double t) =>
      yb + math.sin(x / 31 + t * 2) * 6;

  // ------------------------------------------------------------------ edge

  static final Paint _fill = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  static final Path _path = Path();

  static void _circ(Canvas c, double x, double y, double r, Color col) {
    _fill
      ..shader = null
      ..color = col;
    c.drawCircle(Offset(x, y), r, _fill);
  }

  /// `sceneEdge`: the leaving edge of ride [id]'s scene in its own look,
  /// drawn while 0 < [p] < 1 ([t]: the ride clock; [w] × [h]: the view).
  static void paintEdge(Canvas c, RideId id, double p, double t, double w, double h) {
    if (p <= 0 || p >= 1) return;
    c.save();
    switch (id) {
      case RideId.space:
        // a glowing atmosphere under the curved edge
        final yb = _lerp(h + 40, -110, p);
        _fill.shader = Gradient.linear(
          Offset(0, yb - 10),
          Offset(0, yb + 80),
          const [Color(0xF2C9E7F6), Color(0x80CFC8F2), Color(0x00CFC8F2)],
          const [0, .35, 1],
        );
        _path.reset();
        for (var x = -10.0; x <= w + 10; x += 10) {
          final y = _spaceY(yb, x) - 2;
          x == -10 ? _path.moveTo(x, y) : _path.lineTo(x, y);
        }
        _path
          ..lineTo(w + 10, yb + 100)
          ..lineTo(-10, yb + 100)
          ..close();
        c.drawPath(_path, _fill);
        _fill.shader = null;
        _path.reset();
        for (var x = -10.0; x <= w + 10; x += 10) {
          final y = _spaceY(yb, x);
          x == -10 ? _path.moveTo(x, y) : _path.lineTo(x, y);
        }
        _stroke
          ..color = const Color(0xE6FFFFFF)
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.miter;
        c.drawPath(_path, _stroke);
      case RideId.sea:
        // foam and bubbles on the water's edge
        final xb = _lerp(w + 40, -70, p);
        _path.reset();
        for (var y = -10.0; y <= h + 10; y += 8) {
          final x = _seaX(xb, y, t);
          y == -10 ? _path.moveTo(x, y) : _path.lineTo(x, y);
        }
        _stroke
          ..color = const Color(0xF2FFFFFF)
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round;
        c.drawPath(_path, _stroke);
        for (var i = 0; i < 18; i++) {
          final y = _mod(i * 41 - t * 60, h + 40) - 20;
          _circ(c, _seaX(xb, y, t) + 6 + (i % 4) * 5, y, 2.0 + (i % 3), const Color(0xD9FFFFFF));
        }
      case RideId.volcano:
        // the eruption's steam: a pale billowing bank over the sinking
        // edge, wisps rising off it
        final yb = _lerp(-50, h + 110, p);
        for (var i = 0; i < 9; i++) {
          final a = _mod(t * .45 + i / 9, 1);
          final x = _mod(i * 47 + math.sin(t * .7 + i) * 10, w + 40) - 20;
          _circ(
            c,
            x,
            _volcanoY(yb, x, t) - 30 - a * 120,
            10 + a * 22,
            Color.fromRGBO(255, 246, 236, .8 * (1 - a)),
          );
        }
        const rows = [
          (-26.0, 34.0, Color(0xFFFFEBCD)),
          (-8.0, 30.0, Color(0xFFFFF4EA)),
          (10.0, 26.0, Color(0xFFFFFFFF)),
        ];
        for (var j = 0; j < rows.length; j++) {
          final (dy, r0, col) = rows[j];
          for (var i = -1; i < 12; i++) {
            final x = i * 30 + (j % 2) * 15 + math.sin(t * .8 + i + j) * 5;
            // JS `%` keeps the sign: (−1) % 3 = −1
            final r = r0 + (i + j).remainder(3) * 6 + math.sin(t * 1.3 + i * 2 + j) * 3;
            _circ(c, x, _volcanoY(yb, x, t) + dy, r, col);
          }
        }
      case RideId.pinball:
        // a chrome rail with running lights
        final k = _lerp(-120, h + 260, p);
        c
          ..translate(-10, k + 170 * math.tan(.42))
          ..rotate(-.42);
        _fill
          ..shader = null
          ..color = const Color(0xFFB8B8C8);
        c.drawRect(const Rect.fromLTWH(0, -7, 420, 14), _fill);
        _fill.color = const Color(0xFFE8E8F2);
        c.drawRect(const Rect.fromLTWH(0, -6, 420, 3), _fill);
        for (var i = 0; i < 14; i++) {
          final lit = (t * 8 - i).floor().remainder(3) == 0;
          _circ(c, 15 + i * 30.0, 0, 3, lit ? const Color(0xFFFFD54A) : const Color(0xFF7C4DFF));
        }
      case RideId.storm:
        // puffy dark cloud edges, parting
        final g = _lerp(0, 250, p);
        // 16 puffs at 568 (WP-R call: as many as fill a taller view)
        final n = ((h + 40) / 38).ceil();
        for (final s in const [-1, 1]) {
          for (var i = 0; i < n; i++) {
            final y = i * 38.0 - 10, r = 20.0 + (i % 3) * 7;
            _circ(
              c,
              160 + s * (g - r * .35) + math.sin(t * 1.5 + i) * 3,
              y,
              r,
              i.isOdd ? const Color(0xFF4A5366) : const Color(0xFF59627A),
            );
          }
        }
      case RideId.cannon:
        break;
    }
    c.restore();
  }
}
