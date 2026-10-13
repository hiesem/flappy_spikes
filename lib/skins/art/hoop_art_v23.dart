import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'ctx2d.dart';
import 'shapes.dart';

/// PRD-2.3 §19.2 / §19.4: the 15 new hoops, a 1:1 port of
/// `design/skins_v23/parts/hoops.js` (O1–O15; app id = page id without
/// `n_`). Back half = right side (a −π/2..π/2), front half = left side;
/// `rx = ry × 0.26` unless the caller fixes it (the gameplay ring's fixed
/// width). Decorations are placed by arc length through the page's
/// once-built lookup table.
abstract final class HoopArtV23 {
  /// The new hoop ids in tag order (O1–O15).
  static const List<String> ids = [
    'sunset', 'lemon', 'bamboo', 'rope', 'cloud', //
    'tire', 'melon', 'zipper', 'tape', 'pearls', 'vine',
    'electric', 'water', 'cog', 'aurora',
  ];

  static final Set<String> _set = ids.toSet();

  /// Whether [id] is one of the 2.3 hoops.
  static bool has(String id) => _set.contains(id);
}

typedef _Hoop =
    void Function(
      Ctx2D c,
      double x,
      double y,
      double rx,
      double ry,
      double t,
      bool front,
      double lw,
    );

/// Paints one half of 2.3 hoop [id]; false when [id] is not a 2.3 hoop.
bool paintHoopV23(
  Canvas canvas,
  String id,
  Offset centre,
  double ry,
  double t, {
  required bool front,
  required double lineWidth,
  double? rx,
}) {
  final fn = _hoops[id];
  if (fn == null) return false;
  Ctx2D.run(canvas, (c) {
    c.save();
    fn(c, centre.dx, centre.dy, rx ?? ry * _rxK, ry, t, front, lineWidth);
    c.restore();
  });
  return true;
}

final Map<String, _Hoop> _hoops = {
  'sunset': _sunset,
  'lemon': _lemon,
  'bamboo': _bamboo,
  'rope': _rope,
  'cloud': _cloud,
  'tire': _tire,
  'melon': _melon,
  'zipper': _zipper,
  'tape': _tape,
  'pearls': _pearls,
  'vine': _vine,
  'electric': _electric,
  'water': _water,
  'cog': _cog,
  'aurora': _aurora,
};

const double _pi = math.pi, _tau = math.pi * 2, _rxK = .26;
const Color _white = Color(0xFFFFFFFF);

// arc-length -> angle table for one half (angle -PI/2..PI/2) of the unit
// ellipse (rx = .26, ry = 1)
final (Float32List, double) _table = () {
  const n = 600;
  final cum = Float32List(n + 1);
  var px = 0.0, py = -1.0;
  for (var i = 1; i <= n; i++) {
    final a = -_pi / 2 + i / n * _pi, x = math.cos(a) * _rxK, y = math.sin(a);
    final dx = x - px, dy = y - py;
    cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy);
    px = x;
    py = y;
  }
  final hl = cum[n].toDouble();
  final at = Float32List(129);
  var j = 0;
  for (var k = 0; k <= 128; k++) {
    final L = k / 128 * hl;
    while (j < n && cum[j + 1] < L) {
      j++;
    }
    final f = cum[j + 1] > cum[j] ? (L - cum[j]) / (cum[j + 1] - cum[j]) : 0.0;
    at[k] = -_pi / 2 + (j + f) / n * _pi;
  }
  return (at, hl);
}();

double get _hl => _table.$2;

/// angle at arc fraction [u] (0..1) of a half
double _ang(double u, bool front) {
  final at = _table.$1;
  final f = math.min(128.0, math.max(0.0, u * 128));
  final i = math.min(127, f.truncate()), r = f - i;
  return at[i] + (at[i + 1] - at[i]) * r + (front ? _pi : 0);
}

/// loop position s -> u inside this half, or -1 if s lies on the other half
double _inHalf(double s, bool front) {
  s = ((s % 1) + 1) % 1;
  return front ? (s >= .5 ? (s - .5) * 2 : -1) : (s < .5 ? s * 2 : -1);
}

/// translate + rotate so local +x = direction of travel, local -y = outward
void _at(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double a, [
  double d = 0,
]) {
  final co = math.cos(a), sn = math.sin(a);
  var nx = co * ry, ny = sn * rx;
  var nl = math.sqrt(nx * nx + ny * ny);
  if (nl == 0) nl = 1;
  nx /= nl;
  ny /= nl;
  c.translate(x + co * rx + nx * d, y + sn * ry + ny * d);
  c.rotate(math.atan2(co * ry, -sn * rx));
}

void _band(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  bool front,
  double d,
  double w,
  Object col,
) {
  c.lineWidth = w;
  c.strokeStyle = col;
  final a0 = front ? _pi / 2 : -_pi / 2;
  c.beginPath();
  c.ellipse(x, y, math.max(.5, rx + d), math.max(.5, ry + d), 0, a0, a0 + _pi);
  c.stroke();
}

/// point on ring + outward offset d (no allocation: one shared record)
final class _Pt {
  double x = 0, y = 0, nx = 0, ny = 0;
}

final _Pt _p = _Pt();

_Pt _pt(double x, double y, double rx, double ry, double a, [double d = 0]) {
  final co = math.cos(a), sn = math.sin(a);
  final nx = co * ry, ny = sn * rx;
  var nl = math.sqrt(nx * nx + ny * ny);
  if (nl == 0) nl = 1;
  _p.nx = nx / nl;
  _p.ny = ny / nl;
  _p.x = x + co * rx + _p.nx * d;
  _p.y = y + sn * ry + _p.ny * d;
  return _p;
}

/// how many items of spacing [sp] fit on one half
int _cnt(double ry, double sp) => math.max(3, (_hl * ry / sp).round());

/// back halves are drawn a touch darker, like the base hoops
const Color _shade = Color.fromRGBO(50, 0, 35, .2);

// O1 sunset: five flat horizontal bands top -> bottom
const List<Color> _sun = [
  Color(0xFFFFD23F), Color(0xFFFFA62B), Color(0xFFFF6B4A), //
  Color(0xFFEC2F7B), Color(0xFF8E2A8C),
];

void _sunset(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final top = y - ry - lw, H = (ry + lw) * 2;
  for (var i = 0; i < 5; i++) {
    c.save();
    c.beginPath();
    c.rect(
      x - rx - lw * 2,
      top + H * i / 5 - (i != 0 ? .5 : 0),
      rx * 2 + lw * 4,
      H / 5 + (i < 4 ? 1 : 0),
    );
    c.clip();
    _band(c, x, y, rx, ry, front, 0, lw, _sun[i]);
    c.restore();
  }
  if (!front) {
    _band(c, x, y, rx, ry, front, 0, lw, _shade);
  } else {
    c.lineCap = StrokeCap.round;
    c.lineWidth = lw * .22;
    c.strokeStyle = rgba(255, 255, 255, .75);
    c.beginPath();
    c.ellipse(x, y, rx - lw * .1, ry - lw * .1, 0, _pi * 1.12, _pi * 1.3);
    c.stroke();
  }
}

// O2 lemon
void _lemon(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    lw * .12,
    lw * 1.2,
    front ? const Color(0xFFF2B705) : const Color(0xFFD99A00),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    lw * .2,
    lw * .6,
    front ? const Color(0xFFFFDA1F) : const Color(0xFFF2C200),
  );
  _band(c, x, y, rx, ry, front, -lw * .12, lw * .16, const Color(0xFFFFFDE7));
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    -lw * .38,
    lw * .38,
    front ? const Color(0xFFFFF176) : const Color(0xFFF5E04E),
  );
  final n = _cnt(ry, lw * 1.25);
  c.fillStyle = const Color(0xFFFFFDE7);
  for (var i = 0; i < n; i++) {
    c.save();
    _at(c, x, y, rx, ry, _ang((i + .5) / n, front), -lw * .38);
    c.fillRect(-lw * .07, -lw * .2, lw * .14, lw * .4);
    c.restore();
  }
  if (front) {
    c.save();
    _at(c, x, y, rx, ry, _ang(.72, true), lw * .2);
    c.fillStyle = _white;
    c.fillRect(-lw * .35, -lw * .1, lw * .7, lw * .2);
    c.restore();
  }
}

// O3 bamboo
void _bamboo(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw,
    front ? const Color(0xFF8BC34A) : const Color(0xFF689F38),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    -lw * .22,
    lw * .2,
    front ? const Color(0xFFC5E1A5) : const Color(0xFF9CCC65),
  );
  final n = math.max(3, _cnt(ry, lw * 2.6));
  for (var i = 0; i < n; i++) {
    c.save();
    _at(c, x, y, rx, ry, _ang((i + .5) / n, front));
    c.fillStyle = front ? const Color(0xFF33691E) : const Color(0xFF2A5418);
    c.fillRect(-lw * .17, -lw * .6, lw * .34, lw * 1.2);
    c.fillStyle = const Color(0xFFAED581);
    c.fillRect(lw * .17, -lw * .5, lw * .12, lw * 1);
    c.restore();
  }
  if (front) {
    c.save();
    _at(c, x, y, rx, ry, _ang(.86, true), lw * .4);
    c.rotate(-.5);
    c.fillStyle = const Color(0xFF558B2F);
    c.beginPath();
    c.moveTo(0, 0);
    c.quadraticCurveTo(lw * .9, -lw * .8, lw * 2.2, -lw * .9);
    c.quadraticCurveTo(lw * 1.1, lw * .2, 0, 0);
    c.fill();
    c.restore();
  }
}

// O4 rope
void _rope(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * 1.08,
    front ? const Color(0xFF8D5E2A) : const Color(0xFF6E4620),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * .86,
    front ? const Color(0xFFD9A55C) : const Color(0xFFB9874A),
  );
  final n = _cnt(ry, lw * .62);
  c.lineCap = StrokeCap.round;
  for (var i = 0; i < n; i++) {
    c.save();
    _at(c, x, y, rx, ry, _ang((i + .5) / n, front));
    c.strokeStyle = front ? const Color(0xFF8D5E2A) : const Color(0xFF6E4620);
    c.lineWidth = lw * .17;
    c.beginPath();
    c.moveTo(-lw * .26, -lw * .38);
    c.lineTo(lw * .26, lw * .38);
    c.stroke();
    c.strokeStyle = front ? const Color(0xFFF3D19A) : const Color(0xFFD4AE70);
    c.lineWidth = lw * .09;
    c.beginPath();
    c.moveTo(-lw * .06, -lw * .36);
    c.lineTo(lw * .14, -lw * .06);
    c.stroke();
    c.restore();
  }
}

// O5 cloud
void _cloud(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final n = _cnt(ry, lw * .95);
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < n; i++) {
      final a = _ang((i + .5) / n, front), h = artHash(i * 3 + (front ? 1 : 7));
      final r = lw * (.58 + .22 * h);
      final p = _pt(x, y, rx, ry, a, lw * .08 * (h - .3));
      c.circ(
        p.x,
        p.y,
        pass != 0 ? r : r + lw * .13,
        pass != 0
            ? (front ? _white : const Color(0xFFE3ECF6))
            : (front ? const Color(0xFF9CC6EC) : const Color(0xFF8DB3D6)),
      );
    }
  }
  if (front) {
    for (var i = 1; i < n; i += 3) {
      final a = _ang((i + .5) / n, true), p = _pt(x, y, rx, ry, a, -lw * .2);
      c.circ(p.x, p.y, lw * .2, const Color(0xFFDCEBF8));
    }
  }
}

// O6 tire
void _tire(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final n = _cnt(ry, lw * .85) * 2, off = t * .04;
  c.fillStyle = front ? const Color(0xFF1B1B1B) : const Color(0xFF111111);
  for (var i = 0; i < n; i++) {
    final u = _inHalf(i / n + off, front);
    if (u < 0) continue;
    c.save();
    _at(c, x, y, rx, ry, _ang(u, front));
    c.fillRect(-lw * .22, -lw * .78, lw * .44, lw * .3);
    c.restore();
  }
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * 1.12,
    front ? const Color(0xFF3A3A3A) : const Color(0xFF262626),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    -lw * .28,
    lw * .13,
    front ? rgba(255, 255, 255, .75) : rgba(255, 255, 255, .4),
  );
  c.strokeStyle = front ? const Color(0xFF555555) : const Color(0xFF3A3A3A);
  c.lineWidth = lw * .12;
  c.lineCap = StrokeCap.round;
  for (var i = 0; i < n; i++) {
    final u = _inHalf(i / n + off, front);
    if (u < 0) continue;
    c.save();
    _at(c, x, y, rx, ry, _ang(u, front));
    final k = i.isOdd ? 1 : -1;
    c.beginPath();
    c.moveTo(-lw * .15 * k, -lw * .48);
    c.lineTo(lw * .15 * k, -lw * .12);
    c.stroke();
    c.restore();
  }
}

// O7 watermelon
void _melon(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    lw * .32,
    lw * .42,
    front ? const Color(0xFF2E7D32) : const Color(0xFF1B5E20),
  );
  c.save();
  c.setLineDash([lw * .6, lw * .7]);
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    lw * .32,
    lw * .42,
    front ? const Color(0xFF66BB6A) : const Color(0xFF43A047),
  );
  c.restore();
  _band(c, x, y, rx, ry, front, lw * .06, lw * .14, const Color(0xFFE8F5C8));
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    -lw * .25,
    lw * .56,
    front ? const Color(0xFFFF4D5E) : const Color(0xFFD9304A),
  );
  final n = _cnt(ry, lw * 1.4);
  for (var i = 0; i < n; i++) {
    c.save();
    _at(
      c,
      x,
      y,
      rx,
      ry,
      _ang((i + .5) / n, front),
      -lw * .25 + (i.isOdd ? -.08 : .08) * lw,
    );
    c.fillStyle = const Color(0xFF2B1B1B);
    c.beginPath();
    c.ellipse(0, 0, lw * .16, lw * .09, 0, 0, _tau);
    c.fill();
    c.fillStyle = rgba(255, 255, 255, .7);
    c.fillRect(-lw * .08, -lw * .05, lw * .05, lw * .04);
    c.restore();
  }
}

// O8 zipper
void _zipper(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * 1.1,
    front ? artPink : const Color(0xFFB0006B),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * .42,
    front ? artPlum : const Color(0xFF55002F),
  );
  final n = _cnt(ry, lw * .36);
  c.fillStyle = front ? artGold : const Color(0xFFD99412);
  for (var i = 0; i < n; i++) {
    c.save();
    _at(c, x, y, rx, ry, _ang((i + .5) / n, front), (i.isOdd ? .1 : -.1) * lw);
    c.fillRect(-lw * .13, -lw * .19, lw * .26, lw * .38);
    c.restore();
  }
  final u = _inHalf(t * .09, front);
  if (u >= 0) {
    c.save();
    _at(c, x, y, rx, ry, _ang(u, front));
    c.fillStyle = const Color(0xFFC98A00);
    c.rr(-lw * .55, -lw * .55, lw * 1.1, lw * 1.1, lw * .25);
    c.fill();
    c.fillStyle = artGold;
    c.rr(-lw * .42, -lw * .42, lw * .84, lw * .84, lw * .2);
    c.fill();
    final sw = math.sin(t * 5) * .25;
    c.rotate(sw);
    c.fillStyle = const Color(0xFFC98A00);
    c.rr(-lw * .22, -lw * 1.45, lw * .44, lw * 1.05, lw * .2);
    c.fill();
    c.fillStyle = _white;
    c.fillRect(-lw * .07, -lw * 1.3, lw * .14, lw * .3);
    c.restore();
  }
}

// O9 tape measure
void _tape(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * 1.05,
    front ? const Color(0xFFD9A400) : const Color(0xFFB88A00),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * .85,
    front ? const Color(0xFFFFD600) : const Color(0xFFE6C000),
  );
  final n = _cnt(ry, lw * .4);
  for (var i = 0; i < n; i++) {
    final k = front ? i + n : i;
    c.save();
    _at(c, x, y, rx, ry, _ang((i + .5) / n, front));
    final big = k % 5 == 0, red = k % 10 == 0;
    c.fillStyle = red ? const Color(0xFFE53935) : const Color(0xFF2B2B2B);
    c.fillRect(-lw * .06, -lw * .42, lw * .12, big ? lw * .6 : lw * .3);
    c.restore();
  }
  if (front) {
    final cx = x, cy = y + ry + lw * .2, s = lw * 1.25;
    c.fillStyle = const Color(0xFFB71C1C);
    c.rr(cx - s, cy - s * .75, s * 2, s * 1.6, s * .45);
    c.fill();
    c.fillStyle = const Color(0xFFE53935);
    c.rr(cx - s * .86, cy - s * .65, s * 1.72, s * 1.36, s * .38);
    c.fill();
    c.circ(cx, cy + s * .06, s * .42, const Color(0xFFB71C1C));
    c.circ(cx, cy + s * .06, s * .22, const Color(0xFFECEFF1));
    c.fillStyle = _white;
    c.fillRect(cx - s * .66, cy - s * .5, s * .36, s * .18);
  }
}

// O10 pearls
void _pearls(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final n = _cnt(ry, lw * .98);
  _band(c, x, y, rx, ry, front, 0, lw * .14, const Color(0xFFC98A00));
  final g = (t * .35) % 1;
  for (var i = 0; i < n; i++) {
    final u = (i + .5) / n, s = front ? .5 + u / 2 : u / 2;
    final a = _ang(u, front);
    final p = _pt(x, y, rx, ry, a);
    final px = p.x, py = p.y;
    final r = lw * .5, pk = (i + (front ? 1 : 0)) % 5 == 0;
    c.circ(
      px,
      py,
      r + lw * .06,
      front
          ? (pk ? const Color(0xFFC2185B) : const Color(0xFFB79E86))
          : (pk ? const Color(0xFF9C1450) : const Color(0xFF9C836C)),
    );
    c.circ(
      px,
      py,
      r,
      front
          ? (pk ? const Color(0xFFF8A5CE) : const Color(0xFFF3E6D6))
          : (pk ? const Color(0xFFE57FB0) : const Color(0xFFDDCDBA)),
    );
    c.circ(
      px - r * .18,
      py - r * .2,
      r * .62,
      front
          ? (pk ? const Color(0xFFFFD3E8) : const Color(0xFFFFFBF3))
          : (pk ? const Color(0xFFF6B2D2) : const Color(0xFFF0E5D8)),
    );
    final dd = (((s - g + 1.5) % 1) - .5).abs(),
        gl = math.max(0.0, 1 - dd * 14);
    c.circ(px - r * .35, py - r * .38, r * (.2 + .12 * gl), _white);
    if (gl > .5) {
      c.star(px - r * .35, py - r * .38, lw * (.5 + .5 * gl), _white, t * 2);
    }
  }
}

// O11 vine
void _vine(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final n = _cnt(ry, lw * 1.05);
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * .42,
    front ? const Color(0xFF558B2F) : const Color(0xFF3E6B20),
  );
  for (var i = 0; i < n; i++) {
    final k = i + (front ? n : 0);
    if (k % 4 == 1) continue;
    c.save();
    _at(c, x, y, rx, ry, _ang((i + .5) / n, front));
    final side = k.isOdd ? 1.0 : -1.0;
    c.rotate(side * (.75 + math.sin(t * 2.2 + k) * .18));
    c.scale(1, side);
    c.fillStyle = front
        ? (k % 3 != 0 ? const Color(0xFF7CB342) : const Color(0xFF43A047))
        : (k % 3 != 0 ? const Color(0xFF5E8F2E) : const Color(0xFF2E7D32));
    c.beginPath();
    c.moveTo(0, 0);
    c.quadraticCurveTo(lw * .55, -lw * .6, 0, -lw * 1.15);
    c.quadraticCurveTo(-lw * .55, -lw * .6, 0, 0);
    c.fill();
    c.fillStyle = rgba(255, 255, 255, .35);
    c.fillRect(-lw * .04, -lw * .95, lw * .08, lw * .6);
    c.restore();
  }
  for (var i = 0; i < n; i++) {
    final k = i + (front ? n : 0);
    if (k % 4 != 1) continue;
    final p = _pt(x, y, rx, ry, _ang((i + .5) / n, front), -lw * .05);
    final px = p.x, py = p.y, r = lw * .24, rot = t * .6 + k;
    for (var j = 0; j < 5; j++) {
      final b = rot + j * _tau / 5;
      c.circ(
        px + math.cos(b) * r,
        py + math.sin(b) * r,
        r * .85,
        front ? const Color(0xFFF06292) : const Color(0xFFC2185B),
      );
    }
    c.circ(px, py, r * .7, const Color(0xFFFFD54F));
  }
}

// O12 electric
void _electric(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final seed = (t * 16).floor();
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw,
    front ? const Color(0xFF1A1F5C) : const Color(0xFF0F1240),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * .3,
    front ? const Color(0xFF3D5AFE) : const Color(0xFF283593),
  );
  final m = math.max(8, _cnt(ry, lw * .9));
  c.lineJoin = StrokeJoin.round;
  c.lineCap = StrokeCap.round;
  c.shadowColor = const Color(0xFF00B0FF);
  c.shadowBlur = lw * 1.4;
  for (var k = 0; k < 2; k++) {
    c.strokeStyle = k != 0 ? _white : const Color(0xFF80D8FF);
    c.lineWidth = k != 0 ? lw * .13 : lw * .3;
    c.beginPath();
    for (var i = 0; i <= m; i++) {
      final j = (i == 0 || i == m)
          ? 0.0
          : (artHash(i * 7 + seed * 13 + (front ? 3 : 0)) - .5) * lw * 1.2;
      final p = _pt(x, y, rx, ry, _ang(i / m, front), j);
      c.lineTo(p.x, p.y);
    }
    c.stroke();
  }
  c.strokeStyle = const Color(0xFFE1F5FE);
  c.lineWidth = lw * .13;
  for (var s = 0; s < 2; s++) {
    final h = artHash(seed * 5 + s + (front ? 11 : 0));
    if (h < .35) continue;
    final u = artHash(seed * 3 + s * 17 + (front ? 2 : 9)) * .8 + .1;
    final a = _ang(u, front);
    final p = _pt(x, y, rx, ry, a, lw * .5);
    final px = p.x, py = p.y, ox = p.nx, oy = p.ny;
    c.beginPath();
    c.moveTo(px, py);
    for (var q = 1; q <= 3; q++) {
      final sx = (artHash(seed + q * 31 + s) - .5) * lw * .9;
      c.lineTo(
        px + ox * lw * .55 * q - oy * sx,
        py + oy * lw * .55 * q + ox * sx,
      );
    }
    c.stroke();
  }
  c.shadowBlur = 0;
}

// O13 water
void _water(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * 1.1,
    front ? const Color(0xFF1565C0) : const Color(0xFF0D47A1),
  );
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * .82,
    front ? const Color(0xFF1E88E5) : const Color(0xFF1565C0),
  );
  c.save();
  c.lineCap = StrokeCap.round;
  c.setLineDash([lw * 1.6, lw * 1.1]);
  c.lineDashOffset = -t * lw * 4;
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    -lw * .1,
    lw * .34,
    front ? const Color(0xFF64B5F6) : const Color(0xFF42A5F5),
  );
  c.setLineDash([lw * .7, lw * 2.4]);
  c.lineDashOffset = -t * lw * 6;
  _band(c, x, y, rx, ry, front, lw * .22, lw * .16, rgba(255, 255, 255, .9));
  c.restore();
  for (var i = 0; i < 10; i++) {
    final sp = .05 + artHash(i) * .05;
    final u = _inHalf(artHash(i + 40) + t * sp, front);
    if (u < 0) continue;
    final wob = math.sin(t * 3 + i * 2) * lw * .25;
    final r = lw * (.17 + .15 * artHash(i + 9));
    final p = _pt(
      x,
      y,
      rx,
      ry,
      _ang(u, front),
      wob + (artHash(i + 3) - .5) * lw * .4,
    );
    final px = p.x, py = p.y;
    c.strokeStyle = rgba(255, 255, 255, .95);
    c.lineWidth = math.max(1.2, lw * .1);
    c.beginPath();
    c.arc(px, py, r, 0, _tau);
    c.stroke();
    c.circ(px - r * .35, py - r * .35, r * .3, _white);
  }
  if (front) {
    c.save();
    c.lineCap = StrokeCap.round;
    c.lineWidth = lw * .18;
    c.strokeStyle = rgba(255, 255, 255, .8);
    c.beginPath();
    c.ellipse(x, y, rx - lw * .15, ry - lw * .15, 0, _pi * 1.14, _pi * 1.3);
    c.stroke();
    c.restore();
  }
}

// O14 cogwheel
void _cog(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  final n = _cnt(ry, lw * 1.45) * 2, off = t * .035;
  c.fillStyle = front ? const Color(0xFFB87800) : const Color(0xFF8C5A00);
  for (var i = 0; i < n; i++) {
    final u = _inHalf(i / n + off, front);
    if (u < 0) continue;
    c.save();
    _at(c, x, y, rx, ry, _ang(u, front));
    c.beginPath();
    c.moveTo(-lw * .42, -lw * .3);
    c.lineTo(lw * .42, -lw * .3);
    c.lineTo(lw * .28, -lw * .95);
    c.lineTo(-lw * .28, -lw * .95);
    c.fill();
    c.restore();
  }
  // createLinearGradient(x-rx-lw, y-ry, x+rx+lw, y+ry), drawn about the ring
  // centre so the cached gradient depends on the ring size only.
  final g = Ctx2D.linearGradient(
    ('cog', front, rx, ry, lw),
    -rx - lw,
    -ry,
    rx + lw,
    ry,
    front
        ? const [
            (0, Color(0xFFFFE08A)),
            (.5, Color(0xFFFFB529)),
            (1, Color(0xFFD99412)),
          ]
        : const [
            (0, Color(0xFFE0A92E)),
            (.5, Color(0xFFC98A00)),
            (1, Color(0xFF9A6400)),
          ],
  );
  c.save();
  c.translate(x, y);
  _band(c, 0, 0, rx, ry, front, 0, lw * 1.05, g);
  c.restore();
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    -lw * .3,
    lw * .16,
    front ? const Color(0xFFB87800) : const Color(0xFF7A4E00),
  );
  for (var i = 0; i < n; i += 3) {
    final u = _inHalf(i / n + off + .5 / n, front);
    if (u < 0) continue;
    final p = _pt(x, y, rx, ry, _ang(u, front), lw * .08);
    final px = p.x, py = p.y;
    c.circ(
      px,
      py,
      lw * .2,
      front ? const Color(0xFF8C5A00) : const Color(0xFF6A4300),
    );
    c.circ(
      px - lw * .06,
      py - lw * .06,
      lw * .08,
      front ? const Color(0xFFFFE7A8) : const Color(0xFFC9A04A),
    );
  }
  if (front) {
    c.save();
    c.lineCap = StrokeCap.round;
    c.lineWidth = lw * .16;
    c.strokeStyle = rgba(255, 255, 255, .75);
    c.beginPath();
    c.ellipse(x, y, rx + lw * .18, ry + lw * .18, 0, _pi * 1.12, _pi * 1.28);
    c.stroke();
    c.restore();
  }
}

// O15 aurora
const List<Color> _aur = [
  Color(0xFF2BFFA8), Color(0xFF19D3FF), Color(0xFF8C5CFF), Color(0xFFFF4FB7), //
];

Color _aurC(double v) {
  v = ((v % 4) + 4) % 4;
  final i = v.truncate();
  return lerpC(_aur[i], _aur[(i + 1) % 4], v - i);
}

void _aurora(
  Ctx2D c,
  double x,
  double y,
  double rx,
  double ry,
  double t,
  bool front,
  double lw,
) {
  const m = 22;
  // curtains: three soft bands outside the ring whose brightness ripples
  for (var k = 0; k < 3; k++) {
    final d = lw * (.75 + k * .5);
    c.lineWidth = lw * (.95 - k * .22);
    for (var i = 0; i < m; i++) {
      final s = front ? .5 + (i + .5) / m / 2 : (i + .5) / m / 2;
      final f = .5 + .5 * math.sin(s * _tau * 3 + t * (1.3 + k * .5) + k * 2.1);
      c.globalAlpha = (.1 + .38 * f * f) * (1 - k * .28);
      c.strokeStyle = _aurC(s * 4 - t * .5 + k * .5);
      c.beginPath();
      c.ellipse(
        x,
        y,
        rx + d,
        ry + d,
        0,
        _ang(i / m, front),
        math.min(_ang(1, front), _ang((i + 1.08) / m, front)),
      );
      c.stroke();
    }
  }
  c.globalAlpha = 1;
  c.lineCap = StrokeCap.butt;
  _band(
    c,
    x,
    y,
    rx,
    ry,
    front,
    0,
    lw * 1.12,
    front ? const Color(0xFF0E1A4A) : const Color(0xFF08102E),
  );
  // glowing colour band, one segment at a time
  c.shadowBlur = lw * .9;
  c.lineWidth = lw * .62;
  for (var i = 0; i < m; i++) {
    final u0 = i / m, u1 = (i + 1.08) / m;
    final s = front ? .5 + (i + .5) / m / 2 : (i + .5) / m / 2;
    final col = _aurC(s * 4 - t * .5);
    c.strokeStyle = col;
    c.shadowColor = col;
    c.globalAlpha = front ? 1 : .85;
    c.beginPath();
    c.ellipse(
      x,
      y,
      rx,
      ry,
      0,
      _ang(u0, front),
      math.min(_ang(1, front), _ang(u1, front)),
    );
    c.stroke();
  }
  c.shadowBlur = 0;
  c.globalAlpha = .7;
  _band(c, x, y, rx, ry, front, -lw * .12, lw * .12, _white);
  c.globalAlpha = 1;
  // drifting, twinkling stars
  for (var i = 0; i < 7; i++) {
    final u = _inHalf(artHash(i + 70) + t * .04 * (1 + artHash(i)), front);
    if (u < 0) continue;
    final tw = math.sin(t * 3 + i * 1.7).abs();
    final p = _pt(
      x,
      y,
      rx,
      ry,
      _ang(u, front),
      (artHash(i + 5) - .35) * lw * 2.2,
    );
    if (i.isEven) {
      c.star(p.x, p.y, lw * (.3 + .35 * tw), _white, t * .8 + i);
    } else {
      c.circ(p.x, p.y, lw * (.08 + .1 * tw), rgba(255, 255, 255, .5 + .5 * tw));
    }
  }
}
