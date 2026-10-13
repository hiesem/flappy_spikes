import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'bird_art.dart';
import 'gear_art_v23.dart';
import 'shapes.dart';

/// Port of the accessories (gear) of `design/menu_v2/skin_art.js`
/// (`accBack` / `accFront`). The JS `angel` branch is dead code and skipped.
abstract final class GearArt {
  /// All gear ids in grid order (without `none`; PRD-2.3 §19.3: the 2.3
  /// items of [GearArtV23] mixed in by rarity).
  static const List<String> ids = [
    'shades', 'bowtie', 'stache', 'scarf', 'bandana', //
    'snorkel', 'necktie', 'bandaid', 'gum', 'lei',
    'hearts', 'monocle', 'sneakers', 'windup', 'carpet',
    'balloon', 'backpack', 'skates', 'swimring', 'cape',
    'chain', 'mask', 'patch', 'butterfly', 'drone',
    'jetpack', 'crystal', 'atom', 'disco',
  ];
}

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF111111);
const _ink = Color(0xFF212121);
const _red = Color(0xFFE53935);

final Path _scratch = Path();
Path _poly(List<double> pts) => addPoly(_scratch..reset(), pts);

/// Wind-up key bow in its own coordinates (two octagon loops with square
/// holes, a stem), filled even-odd.
final Path _keyBow =
    (Path()
        ..addPath(octPath(-12, -7.5, 8, 7, 2), Offset.zero)
        ..addPath(octPath(-12, .5, 8, 7, 2), Offset.zero)
        ..addRect(const Rect.fromLTWH(-4, -1.8, 4, 3.6))
        ..addRect(const Rect.fromLTWH(-10, -5.2, 4, 2.4))
        ..addRect(const Rect.fromLTWH(-10, 2.8, 4, 2.4)))
      ..fillType = PathFillType.evenOdd;

/// Bold 4 px "$" glyph centred at the origin (drawn as strokes, no font).
final Path _dollar = Path()
  ..moveTo(1.05, -1.0)
  ..cubicTo(.6, -1.55, -1.1, -1.55, -1.05, -.55)
  ..cubicTo(-1.0, .15, 1.05, -.15, 1.05, .6)
  ..cubicTo(1.05, 1.6, -.6, 1.6, -1.1, .95)
  ..moveTo(0, -1.95)
  ..lineTo(0, 1.95);

final Map<BirdShape, Path> _chainCache = {};
Path _chain(BirdShape s) => _chainCache[s] ??= dashPath(
  Path()
    ..moveTo(s.l + 6, s.neck - 4)
    ..quadraticBezierTo(s.r - 8, s.neck + 6, s.r - 2, s.neck - 4),
  const [2, 1.2],
);

final Map<BirdShape, Path> _stacheCache = {};
Path _stache(BirdShape s) => _stacheCache[s] ??= () {
  Path ellipse(double cx, double cy, double rot) {
    final m = Float64List(16)
      ..[0] = math.cos(rot)
      ..[1] = math.sin(rot)
      ..[4] = -math.sin(rot)
      ..[5] = math.cos(rot)
      ..[10] = 1
      ..[12] = cx
      ..[13] = cy
      ..[15] = 1;
    return (Path()..addOval(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 4.4),
        ))
        .transform(m);
  }

  final ey = s.eye.dy;
  return Path()
    ..addPath(ellipse(s.r - 1, ey + 9, .2), Offset.zero)
    ..addPath(ellipse(s.r + 4, ey + 9.5, -.2), Offset.zero);
}();

const _heartRows = [
  '.XX.XX.',
  'XXXXXXX',
  'XXXXXXX',
  '.XXXXX.',
  '..XXX..',
  '...X...',
];

/// Gear drawn behind the bird (wind-up key, jetpack, scarf tails).
void paintGearBack(Canvas c, String id, BirdShape s, double t, bool flap) {
  if (paintGearBackV23(c, id, s, t, flap)) return;
  switch (id) {
    case 'windup':
      // Clockwork half-turns: turn 40 % of each 1/1.2 s beat, rest 60 %.
      final k = (t * 1.2).floor();
      final f = math.min(1.0, (t * 1.2 - k) / .4);
      final a = (k + f * f * (3 - 2 * f)) * math.pi;
      final cs = math.cos(a);
      final sc = (cs == 0 ? 1.0 : cs.sign) * math.max(.12, cs.abs());
      final x = s.bl, y = s.bot - 8;
      fillRect(c, x - 4, y - 1.3, 6, 2.6, const Color(0xFFA8741A));
      fillRect(c, x - 5.5, y - 2.6, 2, 5.2, const Color(0xFFA8741A));
      c.save();
      c.translate(x - 5.5, y);
      c.scale(1, sc);
      c.drawPath(
        _keyBow,
        fillPaint(k.isOdd ? const Color(0xFFC98B22) : const Color(0xFFF2B33D)),
      );
      fillRect(c, -11, -6.6, 5, 1.1, const Color.fromRGBO(255, 236, 160, .9));
      fillRect(c, -11, 1.4, 5, 1.1, const Color.fromRGBO(255, 236, 160, .9));
      c.restore();
    case 'jetpack':
      fillRoundRect(c, s.l - 8, s.neck - 17, 9, 17, 2, const Color(0xFF90A4AE));
      fillRect(c, s.l - 7, s.neck, 7, 3, const Color(0xFF607D8B));
      // JS uses Math.random(); a hash of the 60 fps frame index keeps the
      // flicker but makes painting reproducible.
      final f = 4 + artHash((t * 60).floor()) * 4;
      final y = s.neck + 3;
      c.drawPath(
        _poly([s.l - 7, y, s.l - 3.5, y + f + 3, s.l, y]),
        fillPaint(artGold),
      );
      c.drawPath(
        _poly([s.l - 6, y, s.l - 3.5, y + f, s.l - 1, y]),
        fillPaint(const Color(0xFFFFF59D)),
      );
    case 'scarf':
      final w = math.sin(t * 10) * 2;
      c.drawPath(
        _poly([
          s.l + 2,
          s.neck - 3,
          s.l - 9,
          s.neck + 1 + w,
          s.l - 11,
          s.neck + 5 + w,
          s.l + 2,
          s.neck + 3,
        ]),
        fillPaint(_red),
      );
  }
}

/// Gear drawn in front of the bird. [dead] turns the mask's eye into an X.
void paintGearFront(
  Canvas c,
  String id,
  BirdShape s,
  double t,
  bool flap, {
  bool dead = false,
}) {
  if (paintGearFrontV23(c, id, s, t, flap)) return;
  final ex = s.eye.dx, ey = s.eye.dy;
  switch (id) {
    case 'carpet':
      const n = 10;
      final x0 = s.l - 8, x1 = s.r + 6, y = s.bot - .5;
      double wv(int i) => math.sin(t * 6 - i * .9) * 1.6;
      double X(int i) => x0 + (x1 - x0) * i / n;
      Path band(double h) {
        final p = _scratch..reset();
        p.moveTo(X(0), y + wv(0));
        for (var i = 1; i <= n; i++) {
          p.lineTo(X(i), y + wv(i));
        }
        for (var i = n; i >= 0; i--) {
          p.lineTo(X(i), y + h + wv(i));
        }
        return p..close();
      }

      c.drawPath(band(5), fillPaint(const Color(0xFF8E1B3A)));
      for (var i = 0; i < n; i++) {
        final xm = (X(i) + X(i + 1)) / 2,
            ym = y + 2.5 + (wv(i) + wv(i + 1)) / 2;
        fillRect(c, xm - .9, ym - .9, 1.8, 1.8, artGold);
      }
      fillRect(c, x0 - .5, y + wv(0) - .5, (x1 - x0) * .08, 1, artGold);
      for (final i in const [0, n]) {
        final yy = y + wv(i);
        for (var k = 0; k < 3; k++) {
          fillRect(
            c,
            X(i) + (i != 0 ? 0 : -2.2),
            yy + .5 + k * 1.7,
            2.2,
            .9,
            artGold,
          );
        }
      }
      c.drawPath(
        band(1.2),
        fillPaint(const Color.fromRGBO(255, 255, 255, .18)),
      );
    case 'shades':
      const u = 1.5;
      final x0 = ex - 5, y0 = ey - 3;
      fillRect(c, s.l + 6, y0, x0 - s.l - 6, u, _black);
      fillRect(c, x0 - u, y0, 10 * u, u, _black);
      fillRect(c, x0, y0 + u, 8 * u, u, _black);
      fillRect(c, x0, y0 + 2 * u, 8 * u, u, _black);
      fillRect(c, x0 + u, y0 + 3 * u, 6 * u, u, _black);
      fillRect(c, x0 + 2 * u, y0 + 4 * u, 4 * u, u, _black);
      fillRect(c, x0 + u, y0 + u, u, u, _white);
      fillRect(c, x0 + 2 * u, y0 + 2 * u, u, u, _white);
      fillRect(c, x0 + 4 * u, y0 + u, u, u, _white);
      fillRect(c, x0 + 5 * u, y0 + 2 * u, u, u, _white);
    case 'hearts':
      const u = 1.6;
      final x0 = ex - 3.5 * u + .5, y0 = ey - 3 * u;
      fillRect(c, s.l + 6, y0 + u, x0 - s.l - 6, u, _black);
      for (var j = 0; j < _heartRows.length; j++) {
        for (var i = 0; i < 7; i++) {
          if (_heartRows[j][i] == 'X') {
            fillRect(
              c,
              x0 + i * u - .6 * u,
              y0 + j * u - .6 * u,
              2.2 * u,
              2.2 * u,
              _black,
            );
          }
        }
      }
      for (var j = 0; j < _heartRows.length; j++) {
        for (var i = 0; i < 7; i++) {
          if (_heartRows[j][i] == 'X') {
            fillRect(
              c,
              x0 + i * u,
              y0 + j * u,
              u + .05,
              u + .05,
              const Color(0xFFFF1F64),
            );
          }
        }
      }
      fillRect(c, x0 + 5 * u, y0 + 2 * u, u, u, const Color(0xFFB0003A));
      fillRect(c, x0 + 4 * u, y0 + 3 * u, u, u, const Color(0xFFB0003A));
      fillRect(c, x0 + u, y0 + u, u, u, _white);
      fillRect(c, x0 + 2 * u, y0 + u, u * .9, u * .9, _white);
    case 'monocle':
      c.drawCircle(Offset(ex, ey), 4.6, strokePaint(artGold, 1.4));
      c.drawCircle(
        Offset(ex, ey),
        4.6,
        fillPaint(const Color.fromRGBO(200, 230, 255, .35)),
      );
      c.drawPath(
        _scratch
          ..reset()
          ..moveTo(ex - 1, ey + 4.6)
          ..quadraticBezierTo(ex - 3, ey + 12, ex - 8, ey + 13),
        strokePaint(artGold, .8),
      );
    case 'mask':
      fillRect(c, s.l, ey - 3.5, s.r - s.l, 7, _ink);
      c.drawPath(
        _poly([s.l, ey - 3, s.l - 6, ey - 6, s.l - 4, ey, s.l, ey + 3]),
        fillPaint(_ink),
      );
      if (dead) {
        paintDeadEye(c, ex, ey, _white);
      } else {
        fillRect(c, ex - 2, ey - 2, 4, 4, _white);
      }
    case 'patch':
      c.drawLine(
        Offset(s.l, ey - 6),
        Offset(s.r, ey + 3),
        strokePaint(_ink, 1.2),
      );
      circ(c, ex, ey, 4.4, _ink);
    case 'stache':
      c.drawPath(_stache(s), fillPaint(const Color(0xFF4E342E)));
    case 'bowtie':
      final x = s.r - 6, y = s.neck;
      c.drawPath(_poly([x - 5, y - 4, x, y, x - 5, y + 4]), fillPaint(_red));
      c.drawPath(_poly([x + 5, y - 4, x, y, x + 5, y + 4]), fillPaint(_red));
      circ(c, x, y, 1.8, const Color(0xFFB71C1C));
    case 'scarf':
      fillRect(c, s.l, s.neck - 3, s.r - s.l, 6, _red);
      for (var x = s.l + 3; x < s.r; x += 6) {
        fillRect(c, x, s.neck - 3, 2, 6, _white);
      }
    case 'bandana':
      c.drawPath(
        _poly([s.l + 4, s.neck - 3, s.r, s.neck - 3, s.r - 10, s.neck + 7]),
        fillPaint(const Color(0xFF1E88E5)),
      );
      circ(c, s.r - 16, s.neck - 1, .9, _white);
      circ(c, s.r - 9, s.neck, .9, _white);
      circ(c, s.r - 12, s.neck + 3, .9, _white);
    case 'chain':
      c.drawPath(_chain(s), strokePaint(artGold, 1.6));
      final sw = math.sin(t * 5) * .8;
      circ(c, s.r - 9 + sw, s.neck + 3, 3.4, artGold);
      c.save();
      c.translate(s.r - 9 + sw, s.neck + 3.3);
      c.drawPath(_dollar, strokePaint(_white, .65));
      c.restore();
    case 'sneakers':
      final sw = flap ? -.5 : .4;
      for (final (k, x) in [(0, s.r - 16), (1, s.r - 7)]) {
        c.save();
        c.translate(x, s.bot);
        c.rotate(sw * (k == 1 ? 1 : .6));
        fillRect(c, -.6, 0, 1.2, 4, artGold);
        c.drawRRect(
          RRect.fromLTRBAndCorners(
            -3,
            3.5,
            5,
            7.5,
            topLeft: const Radius.circular(2),
            topRight: const Radius.circular(3),
            bottomRight: const Radius.circular(1),
            bottomLeft: const Radius.circular(1),
          ),
          fillPaint(_red),
        );
        fillRect(c, -3, 6.5, 8, 1.5, _white);
        c.restore();
      }
    case 'jetpack':
      fillRect(c, s.l, s.neck - 14, 2.5, 12, const Color(0xFF455A64));
  }
}
