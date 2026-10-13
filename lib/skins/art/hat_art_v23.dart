import 'dart:math' as math;
import 'dart:ui';

import 'bird_art.dart';
import 'ctx2d.dart';
import 'shapes.dart';

/// PRD-2.3 §19.2 / §19.4: the 15 new hats, a 1:1 port of
/// `design/skins_v23/parts/hats.js` (H1–H15; app id = page id without
/// `n_`). Same anchors as [paintHat] (`s.hx`, `s.top`), same numbers,
/// colours and timings; drawn through [Ctx2D] so every canvas call maps
/// one-to-one. Glow and gradients only on the epic / legendary items.
abstract final class HatArtV23 {
  /// The new hat ids in tag order (H1–H15).
  static const List<String> ids = [
    'sprout', 'cone', 'egg', 'paperboat', 'phones', //
    'fishbowl', 'cupcake', 'raincloud', 'antennae', 'sharkfin',
    'volcano', 'ufo', 'bdaycake', 'planet', 'sunburst',
  ];

  static final Set<String> _set = ids.toSet();

  /// Whether [id] is one of the 2.3 hats.
  static bool has(String id) => _set.contains(id);
}

const double _tau = math.pi * 2;
const Color _w85 = Color.fromRGBO(255, 255, 255, .85);

void _hi(Ctx2D c, double x, double y, [double w = 1.6, double h = 1.6]) {
  c.fillStyle = _w85;
  c.fillRect(x, y, w, h);
}

/// Paints 2.3 hat [id] on shape [s] at time [t]; false when [id] is not a
/// 2.3 hat.
bool paintHatV23(Canvas canvas, String id, BirdShape s, double t) {
  final fn = _hats[id];
  if (fn == null) return false;
  Ctx2D.run(canvas, (c) => fn(c, s, t));
  return true;
}

final Map<String, void Function(Ctx2D, BirdShape, double)> _hats = {
  'sprout': _sprout,
  'cone': _cone,
  'egg': _egg,
  'paperboat': _paperboat,
  'phones': _phones,
  'fishbowl': _fishbowl,
  'cupcake': _cupcake,
  'raincloud': _raincloud,
  'antennae': _antennae,
  'sharkfin': _sharkfin,
  'volcano': _volcano,
  'ufo': _ufo,
  'bdaycake': _bdaycake,
  'planet': _planet,
  'sunburst': _sunburst,
};

// H1 sprout: stem + two leaves, sways from the base
void _sprout(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top + 1;
  c.save();
  c.translate(x, y);
  c.rotate(math.sin(t * 2.4) * .16);
  c.fp(const Color(0xFF5D4037), c.oct(-4, -2, 8, 4, 1.5));
  c.strokeStyle = const Color(0xFF388E3C);
  c.lineWidth = 2.2;
  c.lineCap = StrokeCap.round;
  c.beginPath();
  c.moveTo(0, -1);
  c.quadraticCurveTo(1.5, -6, 0, -11);
  c.stroke();
  void lf(double dir, Color col) {
    c.save();
    c.translate(0, -11);
    c.rotate(dir * (.5 + math.sin(t * 2.4 + 1) * .08));
    c.fillStyle = col;
    c.beginPath();
    c.moveTo(0, 0);
    c.quadraticCurveTo(dir * 5, -6.5, dir * 11, -2);
    c.quadraticCurveTo(dir * 6, 3, 0, 0);
    c.fill();
    c.fillStyle = rgba(255, 255, 255, .55);
    c.beginPath();
    c.moveTo(dir * 2, -.6);
    c.quadraticCurveTo(dir * 5, -3.6, dir * 8.5, -2.2);
    c.quadraticCurveTo(dir * 5, -2.2, dir * 2, -.6);
    c.fill();
    c.restore();
  }

  lf(-1, const Color(0xFF7CB342));
  lf(1, const Color(0xFF8BC34A));
  c.restore();
}

// H2 traffic cone
void _cone(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  final cone = c.poly([
    x - 9,
    y - 1,
    x - 2.6,
    y - 20,
    x + 2.6,
    y - 20,
    x + 9,
    y - 1,
  ]);
  c.fp(const Color(0xFFFF7A1A), cone);
  c.save();
  c.clip(cone);
  c.fillStyle = const Color(0xFFFFFFFF);
  c.fillRect(x - 12, y - 14.5, 24, 3.6);
  c.fillRect(x - 12, y - 7.5, 24, 3.6);
  c.fp(
    rgba(196, 62, 0, .45),
    c.poly([x + 1.5, y - 20, x + 3, y - 20, x + 10, y, x + 3, y]),
  );
  c.restore();
  c.fillStyle = const Color(0xFFC43E00);
  c.rr(x - 13, y - 1.5, 26, 3.6, 1.2);
  c.fill();
  _hi(c, x - 3.6, y - 18, 1.4, 3);
}

// H3 fried egg: flat white splat + yolk
const List<double> _eggW = [
  -11, -2, 3.4, -6, -4, 4, 0, -4.6, 4.6, 6, -4, 4.2, //
  11, -2.2, 3.2, -2, -1.5, 4, 5, -1.2, 3.6,
];

void _egg(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  c.fillStyle = const Color(0xFFD8C7A4);
  c.beginPath();
  for (var i = 0; i < _eggW.length; i += 3) {
    final a = _eggW[i], b = _eggW[i + 1], r = _eggW[i + 2];
    c.moveTo(x + a + r + 1, y + b + .8);
    c.arc(x + a, y + b + .8, r + 1, 0, _tau);
  }
  c.fill();
  c.fillStyle = const Color(0xFFFFFFFF);
  c.beginPath();
  for (var i = 0; i < _eggW.length; i += 3) {
    final a = _eggW[i], b = _eggW[i + 1], r = _eggW[i + 2];
    c.moveTo(x + a + r, y + b);
    c.arc(x + a, y + b, r, 0, _tau);
  }
  c.fill();
  c.fillRect(x - 11, y - 2, 22, 2.2);
  c.circ(x + 1, y - 4.2, 4.4, const Color(0xFFFF9800));
  c.circ(x + .6, y - 4.8, 3.9, const Color(0xFFFFC107));
  _hi(c, x - 1.6, y - 7, 1.8, 1.8);
}

// H4 paper boat (folded newspaper)
void _paperboat(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  c.fp(const Color(0xFFD9D6C8), c.poly([x - 8, y - 6, x, y - 19, x, y - 6]));
  c.fp(const Color(0xFFF4F2E8), c.poly([x, y - 19, x + 8, y - 6, x, y - 6]));
  final hull = c.poly([
    x - 15,
    y - 7,
    x + 15,
    y - 7,
    x + 10,
    y + 1,
    x - 10,
    y + 1,
  ]);
  c.fp(const Color(0xFFF4F2E8), hull);
  c.save();
  c.clip(hull);
  c.fp(
    const Color(0xFFD9D6C8),
    c.poly([x - 15, y - 7, x - 6, y - 7, x - 8, y + 1, x - 12, y + 1]),
  );
  c.fillStyle = const Color(0xFF8A8A8A);
  for (var j = 0; j < 3; j++) {
    c.fillRect(x - 4, y - 4.8 + j * 2.2, 13.0 - j * 2, 1.1);
  }
  c.fillStyle = const Color(0xFFE53935);
  c.fillRect(x - 4, y - 6.6, 6, 1.2);
  c.restore();
  c.fillStyle = const Color(0xFF8A8A8A);
  c.fillRect(x + 1.6, y - 13, 3, 1.1);
  c.fillRect(x + 1.6, y - 10.8, 4.6, 1.1);
}

// H5 headphones
void _phones(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top, l = s.l + 1.5, r = s.r - 1.5, cy = y + 9;
  c.strokeStyle = const Color(0xFF37474F);
  c.lineWidth = 3;
  c.lineCap = StrokeCap.round;
  c.beginPath();
  c.moveTo(l, cy - 3);
  c.bezierCurveTo(l, y - 9, r, y - 9, r, cy - 3);
  c.stroke();
  c.strokeStyle = const Color(0xFF90A4AE);
  c.lineWidth = 1.1;
  c.beginPath();
  c.moveTo(x - 6, y - 3.4);
  c.quadraticCurveTo(x, y - 5.6, x + 6, y - 3.4);
  c.stroke();
  for (final (cx, d) in [(l, -1.0), (r, 1.0)]) {
    c.fillStyle = artPlum;
    c.rr(cx - 2.5 - (d > 0 ? 0 : 1), cy - 6, 5, 12, 2);
    c.fill();
    c.fillStyle = artPink;
    c.rr(cx + d * 1.2 - 2.6, cy - 5.5, 5.2, 11, 2.4);
    c.fill();
    _hi(c, cx + d * 1.2 - 1.2, cy - 4, 1.3, 2.6);
  }
}

// H6 fishbowl: goldfish swims laps, bubbles rise
void _fishbowl(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top, cy = y - 9;
  const R = 10.0;
  c.save();
  c.beginPath();
  c.arc(x, cy, R, 0, _tau);
  c.clip();
  c.fillStyle = rgba(225, 245, 254, .55);
  c.fillRect(x - R, cy - R, 2 * R, 2 * R);
  c.fillStyle = rgba(41, 182, 246, .55);
  c.fillRect(x - R, cy - 3.5, 2 * R, R + 4);
  c.fillStyle = rgba(255, 255, 255, .6);
  c.fillRect(x - R, cy - 3.5, 2 * R, 1.1);
  c.fillStyle = const Color(0xFFFFE082);
  c.beginPath();
  c.ellipse(x, cy + R, R, 3.6, 0, 0, _tau);
  c.fill();
  final ph = t * .9, u = math.sin(ph), dir = math.cos(ph) >= 0 ? 1.0 : -1.0;
  final fx = x + u * 5.2, fy = cy + 2.4 + math.sin(t * 3) * .8;
  c.save();
  c.translate(fx, fy);
  c.scale(dir, 1);
  final wg = math.sin(t * 12) * 1.1;
  c.fp(
    const Color(0xFFFF7A1A),
    c.poly([-3.4, 0, -6.4, -2.6 + wg * .4, -6.4, 2.6 + wg * .4]),
  );
  c.fillStyle = const Color(0xFFFF7A1A);
  c.beginPath();
  c.ellipse(0, 0, 3.8, 2.5, 0, 0, _tau);
  c.fill();
  c.fp(const Color(0xFFE65100), c.poly([-1, -2.2, 1, -3.6, 1.6, -2]));
  c.fillStyle = const Color(0xFF212121);
  c.fillRect(1.6, -1, 1.1, 1.1);
  c.restore();
  for (var i = 0; i < 3; i++) {
    final p = (t * .7 + i / 3) % 1;
    final bx = x + (artHash(i + 2) - .5) * 8 + math.sin(t * 4 + i) * .6;
    final by = cy + 4 - p * 8;
    c.globalAlpha = 1 - p * .6;
    c.strokeStyle = const Color(0xFFFFFFFF);
    c.lineWidth = .8;
    c.beginPath();
    c.arc(bx, by, .9 + p * .5, 0, _tau);
    c.stroke();
  }
  c.restore();
  c.strokeStyle = const Color(0xFF81D4FA);
  c.lineWidth = 1.6;
  c.beginPath();
  c.arc(x, cy, R, 0, _tau);
  c.stroke();
  c.fillStyle = const Color(0xFFB3E5FC);
  c.rr(x - 7, cy - R - 1.2, 14, 2.4, 1.2);
  c.fill();
  c.fillStyle = _w85;
  c.beginPath();
  c.ellipse(x - 5.5, cy - 4, 1.3, 3.4, .45, 0, _tau);
  c.fill();
}

// H7 cupcake
const List<(double, double, Color)> _sprinkles = [
  (-7, -7.7, Color(0xFFFFEB3B)),
  (-2, -8.2, Color(0xFF4CAF50)),
  (4, -7.5, Color(0xFF7E57C2)),
  (7, -8.2, Color(0xFFFFEB3B)),
  (-5, -11.6, Color(0xFF7E57C2)),
  (1, -11.8, Color(0xFF29B6F6)),
  (5, -11.4, Color(0xFF4CAF50)),
  (-2, -15, Color(0xFFFFEB3B)),
  (3, -14.8, Color(0xFF29B6F6)),
];

void _cupcake(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  final wrap = c.poly([x - 9, y - 6, x + 9, y - 6, x + 7, y + 1, x - 7, y + 1]);
  c.fp(const Color(0xFF29B6F6), wrap);
  c.save();
  c.clip(wrap);
  c.fillStyle = const Color(0xFF0288D1);
  for (var i = -4; i <= 4; i += 2) {
    c.fill(
      c.poly([
        x + i * 1.9 - .6, y - 6, x + i * 1.9 + .6, y - 6, //
        x + i * 1.5 + .5, y + 1, x + i * 1.5 - .5, y + 1,
      ]),
    );
  }
  c.restore();
  c.fillStyle = const Color(0xFFF8BBD9);
  for (final (a, b, w, h) in const [
    (-11.0, -9.0, 22.0, 5.0),
    (-9.0, -13.0, 18.0, 5.0),
    (-6.0, -16.5, 12.0, 4.5),
  ]) {
    c.rr(x + a, y + b, w, h, 2.4);
    c.fill();
  }
  c.fillStyle = const Color(0xFFF06292);
  c.fillRect(x - 10, y - 5.6, 20, 1.3);
  c.fillRect(x - 8, y - 9.4, 16, 1.1);
  c.fillRect(x - 5, y - 13, 10, 1);
  for (final (a, b, col) in _sprinkles) {
    c.fillStyle = col;
    c.fillRect(x + a, y + b, 1.8, 1.1);
  }
  c.strokeStyle = const Color(0xFF33691E);
  c.lineWidth = 1.1;
  c.beginPath();
  c.moveTo(x + .8, y - 19.5);
  c.quadraticCurveTo(x + 2, y - 23, x + 4.5, y - 23.4);
  c.stroke();
  c.circ(x, y - 18.6, 3, const Color(0xFFE53935));
  _hi(c, x - 1.4, y - 20, 1.2, 1.2);
}

// H8 rain cloud: bobbing cloud, drops fall onto the head and splash
const List<double> _cloudPuffs = [
  -7,
  1.3,
  4,
  -2,
  -1.2,
  5,
  4,
  -.2,
  4.6,
  8,
  1.6,
  3.4,
];

void _raincloud(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top, cy = y - 16 + math.sin(t * 2) * 1;
  for (var i = 0; i < 4; i++) {
    final p = (t * 1.6 + i * .25) % 1;
    final dx = x - 6 + i * 4 + (i % 2) * .8, dy = cy + 3 + p * (y - cy - 3);
    if (p < .86) {
      c.fillStyle = const Color(0xFF29B6F6);
      c.beginPath();
      c.moveTo(dx, dy - 2.2);
      c.quadraticCurveTo(dx + 1.3, dy, dx, dy + .9);
      c.quadraticCurveTo(dx - 1.3, dy, dx, dy - 2.2);
      c.fill();
    } else {
      final q = (p - .86) / .14;
      c.globalAlpha = 1 - q;
      c.fillStyle = const Color(0xFF4FC3F7);
      c.fillRect(dx - 1 - q * 2.4, y - 1 - q * 1.4, 1.2, 1.2);
      c.fillRect(dx + q * 2.4, y - 1 - q * 1.4, 1.2, 1.2);
      c.globalAlpha = 1;
    }
  }
  c.fillStyle = const Color(0xFF78909C);
  c.beginPath();
  for (var i = 0; i < _cloudPuffs.length; i += 3) {
    final a = _cloudPuffs[i], b = _cloudPuffs[i + 1], r = _cloudPuffs[i + 2];
    c.moveTo(x + a + r, cy + b + 1);
    c.arc(x + a, cy + b + 1, r, 0, _tau);
  }
  c.fill();
  c.fillStyle = const Color(0xFFB0BEC5);
  c.beginPath();
  for (var i = 0; i < _cloudPuffs.length; i += 3) {
    final a = _cloudPuffs[i], b = _cloudPuffs[i + 1], r = _cloudPuffs[i + 2];
    c.moveTo(x + a + r, cy + b);
    c.arc(x + a, cy + b, r, 0, _tau);
  }
  c.fill();
  c.fillRect(x - 7, cy + 1, 15, 3.2);
  c.fillStyle = const Color(0xFF546E7A);
  c.fillRect(x - 4.2, cy - .4, 1.4, 1.4);
  c.fillRect(x + 1.6, cy - .4, 1.4, 1.4);
  c.fillRect(x - 1.8, cy + 1.8, 2.4, .9);
  c.fillStyle = rgba(255, 255, 255, .8);
  c.fillRect(x - 4.2, cy - 4.6, 2.4, 1.2);
}

// H9 antennae: springy stalks with bobbles, damped-spring wobble
void _antennae(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  c.fillStyle = const Color(0xFF212121);
  c.rr(x - 10, y - 1, 20, 3, 1.5);
  c.fill();
  for (final (d, ph, col) in const [
    (-1.0, 0.0, artPink),
    (1.0, 1.7, Color(0xFF29B6F6)),
  ]) {
    final bx = x + d * 5, k = (t * 1.3 + ph * .3) % 1;
    final w = math.sin(t * 9 + ph) * (1.2 + 2.2 * math.exp(-k * 3));
    final tx = bx + d * 4 + w, ty = y - 17 + math.cos(t * 9 + ph) * .8;
    c.strokeStyle = const Color(0xFF212121);
    c.lineWidth = 1.5;
    c.lineCap = StrokeCap.round;
    c.beginPath();
    c.moveTo(bx, y);
    for (var i = 1; i <= 8; i++) {
      final u = i / 8, zz = (i.isOdd ? 1 : -1) * 1.3 * (1 - u * .4);
      c.lineTo(bx + (tx - bx) * u * u + zz, y + (ty - y) * u);
    }
    c.stroke();
    c.circ(tx, ty, 3.2, col);
    _hi(c, tx - 1.6, ty - 1.8, 1.4, 1.4);
  }
}

// H10 shark fin: fin glides back and forth through scrolling waves
void _sharkfin(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top, fx = x + math.sin(t * 1.6) * 2.5;
  final bob = math.sin(t * 3.2) * .6;
  final fin = c.newPath()
    ..moveTo(fx + 7, y - 1 + bob)
    ..quadraticBezierTo(fx + 4, y - 12 + bob, fx - 6, y - 17 + bob)
    ..quadraticBezierTo(fx - 5, y - 8 + bob, fx - 8, y - 1 + bob)
    ..close();
  c.fp(const Color(0xFF607D8B), fin);
  c.save();
  c.clip(fin);
  c.fp(
    const Color(0xFF90A4AE),
    c.poly([fx - 9, y - 18, fx - 4, y - 18, fx - 1, y, fx - 9, y]),
  );
  c.restore();
  _hi(c, fx - 5, y - 14 + bob, 1.3, 2.6);
  final w = c.newPath(), o = (t * 8) % 6;
  w.moveTo(x - 13, y + 2);
  for (var X = -13 - o; X <= 13; X += 6) {
    w.quadraticBezierTo(x + X + 1.5, y - 5, x + X + 3, y - 2.4);
    w.quadraticBezierTo(x + X + 4.5, y - .2, x + X + 6, y - 2.4);
  }
  w
    ..lineTo(x + 13, y + 2)
    ..close();
  c.save();
  c.beginPath();
  c.rect(x - 13, y - 8, 26, 12);
  c.clip();
  c.fp(const Color(0xFF29B6F6), w);
  c.fillStyle = const Color(0xFF0288D1);
  c.fillRect(x - 13, y, 26, 2);
  c.fillStyle = const Color(0xFFFFFFFF);
  for (var X = -13 - o; X <= 13; X += 6) {
    c.fillRect(x + X + 1.6, y - 3.8, 1.6, 1.1);
  }
  c.restore();
}

// H11 volcano: smoke puffs, lava drips, glowing crater
void _volcano(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  for (var i = 0; i < 3; i++) {
    final p = (t * .55 + i / 3) % 1;
    final px = x + math.sin(p * 5 + i) * 2 + p * 3, py = y - 14 - p * 6.5;
    final r = 1.5 + p * 2.6;
    c.globalAlpha = (1 - p) * .9;
    c.circ(
      px,
      py,
      r,
      i.isOdd ? const Color(0xFF90A4AE) : const Color(0xFFB0BEC5),
    );
    c.circ(px - r * .3, py - r * .3, r * .45, rgba(255, 255, 255, .55));
  }
  c.globalAlpha = 1;
  final cone = c.poly([
    x - 13,
    y + 1,
    x - 4,
    y - 13,
    x + 4,
    y - 13,
    x + 13,
    y + 1,
  ]);
  c.fp(const Color(0xFF6D4C41), cone);
  c.save();
  c.clip(cone);
  c.fp(
    const Color(0xFF4E342E),
    c.poly([x + 1, y - 13, x + 5, y - 13, x + 14, y + 2, x + 4, y + 2]),
  );
  final g = .6 + .4 * math.sin(t * 5);
  c.save();
  c.shadowColor = rgba(255, 109, 0, .9);
  c.shadowBlur = 4 + g * 3;
  c.fillStyle = const Color(0xFFFF6D00);
  c.fill(
    c.poly([
      x - 4.4, y - 13, x + 4.4, y - 13, x + 3.2, y - 10.6, x - 3.2, y - 10.6, //
    ]),
  );
  for (final (d, ph, len) in const [
    (-2.6, 0.0, 6.0),
    (1.8, .45, 8.5),
    (-.2, .8, 4.5),
  ]) {
    final L = len * (.55 + .45 * math.sin(t * 1.8 + ph * 7));
    c.fillRect(x + d - .9, y - 11.5, 1.8, L);
    c.beginPath();
    c.arc(x + d, y - 11.5 + L, 1.3, 0, _tau);
    c.fill();
  }
  c.restore();
  c.fillStyle = const Color(0xFFFFEB3B);
  c.fillRect(x - 2.4, y - 12.8, 2, 1);
  c.fillRect(x + 1, y - 12.8, 1.4, 1);
  c.restore();
  c.fillStyle = const Color(0xFF8D6E63);
  c.fillRect(x - 8, y - 5, 3, 1.3);
  c.fillRect(x - 5, y - 8.6, 2.2, 1.2);
}

// H12 UFO: hovering saucer, chasing rim lights, flickering tractor beam
void _ufo(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top, cy = y - 13 + math.sin(t * 2.4) * 1.4;
  final tilt = math.sin(t * 1.2) * .08;
  final bf = .65 + .35 * math.sin(t * 7);
  // createLinearGradient(0, cy, 0, y + 2): drawn in a frame where the
  // gradient runs over the unit 0..1 (so it is cached; the beam alpha bf is
  // quantised to 1/64).
  final span = y + 2 - cy, q = (bf * 64).round() / 64;
  final g = Ctx2D.linearGradient(
    ('ufo', q),
    0,
    0,
    0,
    1,
    [(0, rgba(118, 255, 3, .85 * q)), (1, rgba(118, 255, 3, .18))],
  );
  c.save();
  c.translate(0, cy);
  c.scale(1, span);
  c.fillStyle = g;
  c.fill(
    c.poly([
      x - 4, 2 / span, x + 4, 2 / span, x + 10, 1, x - 10, 1, //
    ]),
  );
  c.restore();
  c.fillStyle = rgba(255, 255, 255, .5 * bf);
  for (var i = 0; i < 3; i++) {
    final p = (t * .9 + i / 3) % 1;
    c.fillRect(x - 5 + i * 4.2, y + 1 - p * (y - cy - 1), 1.3, 1.3);
  }
  c.save();
  c.translate(x, cy);
  c.rotate(tilt);
  c.fillStyle = rgba(128, 222, 234, .9);
  c.beginPath();
  c.ellipse(0, -2, 5.4, 5.2, 0, math.pi, 0);
  c.fill();
  c.fillStyle = _w85;
  c.fillRect(-3.2, -5.4, 1.6, 2.2);
  c.fillStyle = const Color(0xFF78909C);
  c.beginPath();
  c.ellipse(0, 0, 13, 3.6, 0, 0, _tau);
  c.fill();
  c.fillStyle = const Color(0xFFB0BEC5);
  c.beginPath();
  c.ellipse(0, -1, 13, 2.6, 0, math.pi, 0);
  c.fill();
  c.fillRect(-13, -1, 26, 1);
  c.fillStyle = const Color(0xFF546E7A);
  c.beginPath();
  c.ellipse(0, 2.2, 5, 1.6, 0, 0, math.pi);
  c.fill();
  final k = (t * 6).floor();
  for (var i = 0; i < 5; i++) {
    final on = (i + k) % 5;
    final col = on == 0
        ? artGold
        : on == 2
        ? artPink
        : const Color(0xFF455A64);
    final lx = -10.0 + i * 5;
    c.save();
    if (on == 0 || on == 2) {
      c.shadowColor = col;
      c.shadowBlur = 4;
    }
    c.circ(lx, .4, 1.3, col);
    c.restore();
  }
  c.restore();
}

// H13 birthday cake: two tiers, drip frosting, three flickering candles
void _bdaycake(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, y = s.top;
  c.fillStyle = const Color(0xFFEC407A);
  c.rr(x - 12, y - 7, 24, 8, 1.5);
  c.fill();
  c.fillStyle = const Color(0xFFF8BBD9);
  c.rr(x - 8, y - 13, 16, 6.4, 1.5);
  c.fill();
  void drip(double x0, double x1, double yy, int n) {
    c.fillStyle = const Color(0xFFFFFFFF);
    c.fillRect(x0, yy, x1 - x0, 1.8);
    final w = (x1 - x0) / n;
    for (var i = 0; i < n; i++) {
      final L = 1.6 + artHash(i + x0) * 2.2;
      c.beginPath();
      c.arc(x0 + w * (i + .5), yy + 1.4 + L, w * .32, 0, _tau);
      c.fill();
      c.fillRect(x0 + w * (i + .5) - w * .32, yy + 1, w * .64, L + .4);
    }
  }

  drip(x - 12, x + 12, y - 7, 6);
  drip(x - 8, x + 8, y - 13, 4);
  c.fillStyle = const Color(0xFFFFEB3B);
  for (final dx in const [-7.0, -2.0, 3.0, 8.0]) {
    c.fillRect(x + dx - .7, y - 1.6, 1.4, 1.4);
  }
  const candles = [
    (-4.5, Color(0xFF29B6F6)),
    (0.0, Color(0xFFFFB529)),
    (4.5, Color(0xFF7CB342)),
  ];
  for (var i = 0; i < 3; i++) {
    final (dx, col) = candles[i];
    final cx = x + dx;
    c.fillStyle = col;
    c.fillRect(cx - 1, y - 19, 2, 6);
    c.fillStyle = const Color(0xFFFFFFFF);
    c.fillRect(cx - 1, y - 17.4, 2, 1);
    c.fillRect(cx - 1, y - 15, 2, 1);
    final f = 1 + .22 * math.sin(t * 13 + i * 2.1) + .12 * math.sin(t * 23 + i);
    final sw = math.sin(t * 9 + i * 1.3) * .7;
    c.save();
    c.shadowColor = rgba(255, 181, 41, .9);
    c.shadowBlur = 5;
    c.fillStyle = const Color(0xFFFF9800);
    c.beginPath();
    c.moveTo(cx - 1.7, y - 20);
    c.quadraticCurveTo(
      cx - 1.7,
      y - 22.2 * f + (f - 1) * -2,
      cx + sw,
      y - 19 - 5 * f,
    );
    c.quadraticCurveTo(cx + 1.7, y - 22, cx + 1.7, y - 20);
    c.quadraticCurveTo(cx, y - 18.7, cx - 1.7, y - 20);
    c.fill();
    c.restore();
    c.fillStyle = const Color(0xFFFFF59D);
    c.beginPath();
    c.ellipse(cx + sw * .3, y - 20.6, .8, 1.4 * f, 0, 0, _tau);
    c.fill();
  }
}

// H14 ringed planet: floats, ring split behind / in front, moon orbits through
const List<double> _planetStarsX = [-15, 13, -10, 16];
const List<double> _planetStarsY = [-8, -9, 6, 4];

void _planet(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, cy = s.top - 11 + math.sin(t * 1.8) * 1;
  const R = 7.0, ra = -.32;
  final ma = t * 1.5, mx = x + math.cos(ma) * 15;
  final my = cy + math.sin(ma) * 4 - math.cos(ma) * 2.5;
  final mBack = math.sin(ma) < 0;
  void moon() {
    c.circ(mx, my, 2.3, const Color(0xFFECEFF1));
    c.circ(mx + .6, my + .5, .7, const Color(0xFFB0BEC5));
    _hi(c, mx - 1.3, my - 1.3, 1, 1);
  }

  void ring(bool front) {
    c.save();
    c.translate(x, cy);
    c.rotate(ra);
    c.lineWidth = 2.4;
    c.strokeStyle = front ? artSoft : const Color(0xFFD18AB4);
    c.beginPath();
    c.ellipse(0, 0, 13.5, 3.6, 0, front ? 0 : math.pi, front ? math.pi : _tau);
    c.stroke();
    c.lineWidth = 1;
    c.strokeStyle = front ? artPink : const Color(0xFF9C2C6C);
    c.beginPath();
    c.ellipse(0, 0, 11.2, 2.9, 0, front ? 0 : math.pi, front ? math.pi : _tau);
    c.stroke();
    c.restore();
  }

  for (var i = 0; i < 4; i++) {
    final tw = math.sin(t * 2.2 + i * 1.9).abs();
    c.star(
      x + _planetStarsX[i],
      cy + _planetStarsY[i],
      .8 + tw * 1.3,
      const Color(0xFFFFF59D),
      t * .5 + i,
    );
  }
  if (mBack) moon();
  ring(false);
  c.save();
  c.shadowColor = rgba(255, 181, 41, .7);
  c.shadowBlur = 6;
  // createRadialGradient(x-2.5, cy-2.5, 1, x, cy, R), drawn about the disc
  // centre so the cached gradient is position-independent.
  c.translate(x, cy);
  c.fillStyle = Ctx2D.radialGradient('planet', -2.5, -2.5, 1, 0, 0, R, const [
    (0, Color(0xFFFFE082)),
    (.55, Color(0xFFFFB529)),
    (1, Color(0xFFF57C00)),
  ]);
  c.beginPath();
  c.arc(0, 0, R, 0, _tau);
  c.fill();
  c.restore();
  c.save();
  c.beginPath();
  c.arc(x, cy, R, 0, _tau);
  c.clip();
  c.translate(x, cy);
  c.rotate(ra);
  c.fillStyle = rgba(216, 67, 21, .55);
  final sh = (t * 2) % 14;
  c.fillRect(-8, -4.2, 16, 1.6);
  c.fillRect(-8, 1.2, 16, 2);
  c.fillStyle = rgba(255, 255, 255, .35);
  c.fillRect(-8, -1.4, 16, 1);
  c.fillStyle = rgba(191, 54, 12, .6);
  c.beginPath();
  c.ellipse(-7 + sh, 1.9, 1.6, .9, 0, 0, _tau);
  c.fill();
  c.restore();
  _hi(c, x - 4.4, cy - 4.6, 1.8, 1.8);
  ring(true);
  if (!mBack) moon();
}

// H15 sunburst: rotating long/short rays, pulsing glow, bright disc
void _sunburst(Ctx2D c, BirdShape s, double t) {
  final x = s.hx, cy = s.top - 10, p = .5 + .5 * math.sin(t * 3), rot = t * .6;
  c.save();
  c.translate(x, cy);
  c.save();
  c.rotate(rot);
  c.fillStyle = const Color(0xFFFF7043);
  c.beginPath();
  for (var i = 0; i < 8; i++) {
    final a = i / 8 * _tau + _tau / 16, L = 10.5 + p * 1.5;
    c.moveTo(math.cos(a - .17) * 6, math.sin(a - .17) * 6);
    c.lineTo(math.cos(a) * L, math.sin(a) * L);
    c.lineTo(math.cos(a + .17) * 6, math.sin(a + .17) * 6);
  }
  c.fill();
  c.fillStyle = artGold;
  c.beginPath();
  for (var i = 0; i < 8; i++) {
    final a = i / 8 * _tau, L = 13 + p * 1.8;
    c.moveTo(math.cos(a - .22) * 6, math.sin(a - .22) * 6);
    c.lineTo(math.cos(a) * L, math.sin(a) * L);
    c.lineTo(math.cos(a + .22) * 6, math.sin(a + .22) * 6);
  }
  c.fill();
  c.restore();
  c.shadowColor = rgba(255, 213, 79, .95);
  c.shadowBlur = 6 + p * 6;
  c.fillStyle = Ctx2D.radialGradient('sunburst', -2, -2, .5, 0, 0, 7.4, const [
    (0, Color(0xFFFFFDE7)),
    (.45, Color(0xFFFFEB3B)),
    (1, Color(0xFFFFA000)),
  ]);
  c.beginPath();
  c.arc(0, 0, 7.4, 0, _tau);
  c.fill();
  c.shadowBlur = 0;
  for (var i = 0; i < 3; i++) {
    final a = rot * -1.4 + i * _tau / 3, f = (t * 1.1 + i / 3) % 1;
    final r = 9.5 + f * 6;
    c.globalAlpha = 1 - f;
    c.circ(math.cos(a) * r, math.sin(a) * r, .9, const Color(0xFFFFF59D));
  }
  c.globalAlpha = 1;
  c.fillStyle = rgba(255, 255, 255, .9);
  c.fillRect(-3.8, -4.2, 2, 2);
  c.fillRect(-1.6, -4.8, 1, 1);
  c.restore();
}
