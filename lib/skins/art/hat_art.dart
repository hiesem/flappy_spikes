import 'dart:math' as math;
import 'dart:ui';

import 'bird_art.dart';
import 'shapes.dart';

/// Port of the hats of `design/menu_v2/skin_art.js` (`hat`). Every hat is
/// anchored at the shape's head top (`hx`, `top`); the paths below are in
/// that local frame and cached once. The JS `astro` branch is dead code.
abstract final class HatArt {
  /// All hat ids in grid order (without `none`).
  static const List<String> ids = [
    'cap', 'beanie', 'party', 'band', 'bucket', //
    'tophat', 'cowboy', 'prop', 'chef', 'viking',
    'pirate', 'wizard', 'crown', 'halo',
  ];
}

const _white = Color(0xFFFFFFFF);
const _red = Color(0xFFE53935);
const _blue = Color(0xFF1E88E5);
const _yellow = Color(0xFFFFEB3B);
const _ink = Color(0xFF212121);

Path _dome(double cy, double r) => Path()
  ..addArc(Rect.fromCircle(center: Offset(0, cy), radius: r), math.pi, math.pi)
  ..close();

final Path _capDome = _dome(2, 10);
final Path _beanieDome = _dome(2, 11);
final Path _partyCone = polyPath([-8, 0, 0, -20, 8, 0]);
final Path _bucketCrown = polyPath([-8, -9, 8, -9, 10, 1, -10, 1]);
final RRect _bucketBrim = RRect.fromRectAndRadius(
  const Rect.fromLTWH(-15, 0, 30, 3.6),
  const Radius.circular(2),
);
final Path _cowboy = polyPath([-18, -7, -14, 0, 14, 0, 18, -7, 13, -3, -13, -3])
  ..addPath(
    polyPath([-9, -3, -8, -14, -3, -12, 0, -14, 3, -12, 8, -14, 9, -3]),
    Offset.zero,
  );
final Path _chefPuff = octPath(-12, -19, 24, 13, 4);
final Path _chefPleats = Path()
  ..moveTo(-4, -19)
  ..lineTo(-4, -12)
  ..moveTo(4, -19)
  ..lineTo(4, -12);
final Path _vikingHorns = polyPath([-9, -3, -16, -15, -13, -15, -12, -6])
  ..addPath(polyPath([9, -3, 16, -15, 13, -15, 12, -6]), Offset.zero);
final Path _vikingHelm = polyPath([
  -11,
  1,
  -10,
  -7,
  -5,
  -11,
  5,
  -11,
  10,
  -7,
  11,
  1,
]);
final Path _pirateHat = polyPath([
  -17,
  1,
  -13,
  -12,
  -5,
  -9,
  0,
  -15,
  5,
  -9,
  13,
  -12,
  17,
  1,
]);
final Path _pirateTrim = polyPath([-17, 1, -16, -2, 16, -2, 17, 1]);
final Path _wizardCone = polyPath([
  -11,
  0,
  -4,
  -14,
  0,
  -22,
  8,
  -26,
  4,
  -19,
  11,
  0,
]);
final Path _crown = polyPath([
  -11,
  1,
  -11,
  -10,
  -6,
  -4,
  0,
  -13,
  6,
  -4,
  11,
  -10,
  11,
  1,
]);
final Rect _haloOval = Rect.fromCenter(
  center: Offset.zero,
  width: 22,
  height: 6.8,
);
final Paint _haloGlow = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2.6
  ..color = const Color.fromRGBO(255, 214, 0, .9)
  // canvas shadowBlur 6 (device px) ≈ Gaussian sigma 3 px; ~1 art unit at
  // the typical 2-3x preview scale.
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

final Path _scratch = Path();

/// Hat [id] on shape [s]; unknown ids (and `none`) draw nothing.
void paintHat(Canvas c, String id, BirdShape s, double t) {
  c.save();
  c.translate(s.hx, s.top);
  // Shape edges relative to the hat anchor (sweatband).
  final l = s.l - s.hx, r = s.r - s.hx;
  switch (id) {
    case 'cap':
      c.drawPath(_capDome, fillPaint(_blue));
      fillRect(c, 0, -1, 17, 3, _blue);
      circ(c, 0, -8, 1.6, const Color(0xFF0D47A1));
      fillRect(c, -3, -6, 5, 3, _white);
    case 'beanie':
      c.drawPath(_beanieDome, fillPaint(_red));
      fillRect(c, -12, -1, 24, 4.5, _white);
      circ(c, 0, -10, 3.4, _white);
    case 'party':
      c.save();
      c.translate(0, 1);
      c.rotate(.2);
      c.save();
      c.drawPath(_partyCone, fillPaint(const Color(0xFF29B6F6)));
      c.clipPath(_partyCone);
      for (var i = 0; i < 4; i++) {
        fillRect(c, -10, -4.0 - i * 6, 20, 2.5, _yellow);
      }
      c.restore();
      circ(c, 0, -20, 2.6, artPink);
      c.restore();
    case 'band':
      fillRect(c, l, 2, r - l, 4.5, _red);
      fillRect(c, l, 3.5, r - l, 1.4, _white);
      c.drawPath(
        addPoly(_scratch..reset(), [
          l,
          3,
          l - 8,
          1 + math.sin(t * 8),
          l - 7,
          6,
          l,
          6.5,
        ]),
        fillPaint(_red),
      );
    case 'bucket':
      c.drawPath(_bucketCrown, fillPaint(const Color(0xFFC5B358)));
      c.drawRRect(_bucketBrim, fillPaint(const Color(0xFFA1903A)));
      fillRect(c, -9, -3, 18, 2, const Color(0xFFA1903A));
    case 'tophat':
      fillRect(c, -8, -16, 16, 16, _ink);
      fillRect(c, -13, -1, 26, 3, _ink);
      fillRect(c, -8, -5, 16, 3, artPink);
    case 'cowboy':
      c.drawPath(_cowboy, fillPaint(const Color(0xFF8D5A2B)));
      fillRect(c, -9, -6, 18, 3, const Color(0xFF5D3A1A));
    case 'prop':
      fillRect(c, -10, -6, 7, 7, _red);
      fillRect(c, -3, -6, 6, 7, _yellow);
      fillRect(c, 3, -6, 7, 7, _blue);
      fillRect(c, -6, -9, 12, 3, _red);
      fillRect(c, 8, -1, 9, 2.5, _blue);
      fillRect(c, -.8, -14, 1.6, 5, const Color(0xFF555555));
      final w = (math.cos(t * 22) * 12).abs();
      fillRect(c, -w - .5, -15.5, w * 2 + 1, 2.6, _red);
      fillRect(c, -1.5, -15.8, 3, 3.2, _yellow);
    case 'chef':
      final edge = strokePaint(const Color(0xFFD0D0D0), .8);
      const band = Rect.fromLTWH(-8, -7, 16, 8);
      c.drawRect(band, fillPaint(_white));
      c.drawRect(band, edge);
      c.drawPath(_chefPuff, fillPaint(_white));
      c.drawPath(_chefPuff, edge);
      fillRect(c, -7.6, -8, 15.2, 3, _white);
      c.drawPath(_chefPleats, strokePaint(const Color(0xFFD0D0D0), .8));
    case 'viking':
      c.drawPath(_vikingHorns, fillPaint(const Color(0xFFF5F5DC)));
      c.drawPath(_vikingHelm, fillPaint(const Color(0xFF90A4AE)));
      fillRect(c, -12, -1, 24, 3.5, const Color(0xFF607D8B));
      fillRect(c, -1.5, -11, 3, 10, const Color(0xFF607D8B));
      for (final dx in const [-8.0, -4.0, 4.0, 8.0]) {
        fillRect(c, dx - .8, -.3, 1.6, 1.6, const Color(0xFF607D8B));
      }
    case 'pirate':
      c.drawPath(_pirateHat, fillPaint(_ink));
      c.drawPath(_pirateTrim, fillPaint(artGold));
      fillRect(c, -3, -10, 6, 5, _white);
      fillRect(c, -2, -5, 4, 1.5, _white);
      fillRect(c, -2, -9, 1.6, 1.6, _ink);
      fillRect(c, .4, -9, 1.6, 1.6, _ink);
    case 'wizard':
      c.drawPath(_wizardCone, fillPaint(const Color(0xFF5E35B1)));
      fillRect(c, -15, -1, 30, 3.5, const Color(0xFF4527A0));
      fillRect(c, -10, -5, 20, 2.5, _yellow);
      for (var i = 0; i < 3; i++) {
        final tw = math.sin(t * 3 + i * 2).abs();
        paintStar(
          c,
          -4 + i * 3.5,
          -8.0 - i * 5,
          1.4 + tw * 1.4,
          _yellow,
          rot: t + i,
        );
      }
    case 'crown':
      c.drawPath(_crown, fillPaint(artGold));
      circ(c, 0, -3, 2, _red);
      circ(c, -7, -2, 1.4, _blue);
      circ(c, 7, -2, 1.4, const Color(0xFF43A047));
      final sh = (t * .6) % 2;
      if (sh < 1) {
        paintStar(
          c,
          -11 + sh * 22,
          -11 + math.sin(sh * math.pi) * -2,
          2.4,
          _white,
          rot: t,
        );
      }
    case 'halo':
      final b = math.sin(t * 3) * 1.5;
      final oval = _haloOval.shift(Offset(0, -9 + b));
      c.drawOval(oval, _haloGlow);
      c.drawOval(oval, strokePaint(const Color(0xFFFFD600), 2.6));
  }
  c.restore();
}
