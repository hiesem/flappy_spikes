import 'dart:math' as math;
import 'dart:ui';

import 'bird_art.dart';
import 'ctx2d.dart';
import 'shapes.dart';

/// PRD-2.3 §19.2 / §19.4: the 15 new gear items, a 1:1 port of
/// `design/skins_v23/parts/gear.js` (G1–G15; app id = page id without
/// `n_`). Back and front layers as `accBack` / `accFront` (the drawing order
/// in `LookPainter` is unchanged); drawn through [Ctx2D] so every canvas
/// call maps one-to-one.
abstract final class GearArtV23 {
  /// The new gear ids in tag order (G1–G15).
  static const List<String> ids = [
    'snorkel', 'necktie', 'bandaid', 'gum', 'lei', //
    'balloon', 'backpack', 'skates', 'swimring', 'cape',
    'butterfly', 'drone', 'crystal', 'atom', 'disco',
  ];

  static final Set<String> _set = ids.toSet();

  /// Whether [id] is one of the 2.3 gear items.
  static bool has(String id) => _set.contains(id);
}

typedef _Gear = void Function(Ctx2D c, BirdShape s, double t, bool flap);

/// Back layer of 2.3 gear [id]; false when [id] is not a 2.3 item (a 2.3
/// item without a back layer draws nothing and returns true).
bool paintGearBackV23(
  Canvas canvas,
  String id,
  BirdShape s,
  double t,
  bool flap,
) {
  if (!GearArtV23.has(id)) return false;
  final fn = _back[id];
  if (fn != null) Ctx2D.run(canvas, (c) => fn(c, s, t, flap));
  return true;
}

/// Front layer of 2.3 gear [id]; false when [id] is not a 2.3 item.
bool paintGearFrontV23(
  Canvas canvas,
  String id,
  BirdShape s,
  double t,
  bool flap,
) {
  if (!GearArtV23.has(id)) return false;
  final fn = _front[id];
  if (fn != null) Ctx2D.run(canvas, (c) => fn(c, s, t, flap));
  return true;
}

final Map<String, _Gear> _back = {
  'balloon': _balloonBack,
  'backpack': _backpackBack,
  'swimring': (c, s, t, f) => _ringHalf(c, s, t, false),
  'cape': _capeBack,
  'butterfly': _butterflyBack,
  'drone': _droneBack,
  'crystal': _crystalBack,
  'atom': (c, s, t, f) => _atomPass(c, s, t, false),
};

final Map<String, _Gear> _front = {
  'snorkel': _snorkel,
  'necktie': _necktie,
  'bandaid': _bandaid,
  'gum': _gum,
  'lei': _lei,
  'backpack': _backpackFront,
  'skates': _skates,
  'swimring': (c, s, t, f) => _ringHalf(c, s, t, true),
  'cape': _capeFront,
  'atom': (c, s, t, f) => _atomPass(c, s, t, true),
  'disco': _disco,
};

const double _tau = math.pi * 2;
const Color _white = Color(0xFFFFFFFF);

// anchors shared by several items
double _bx0(BirdShape s) => s.beak[0];

/// `tipOf(s)`: the beak point furthest right (first on ties).
(double, double) _tipOf(BirdShape s) {
  var mx = s.beak[0], my = s.beak[1];
  for (var i = 0; i < s.beak.length; i += 2) {
    if (s.beak[i] > mx) {
      mx = s.beak[i];
      my = s.beak[i + 1];
    }
  }
  return (mx, my);
}

/// `mouthY(s)`: the mean beak y.
double _mouthY(BirdShape s) {
  var sum = 0.0;
  for (var i = 1; i < s.beak.length; i += 2) {
    sum += s.beak[i];
  }
  return sum / (s.beak.length / 2);
}

double _ease(double u) => 1 - (1 - u) * (1 - u);

// ---------------- G1 snorkel ----------------
void _snorkel(Ctx2D c, BirdShape s, double t, bool flap) {
  final ex = s.eye.dx, ey = s.eye.dy, bx = _bx0(s), my = _mouthY(s);
  final tx = ex - 8;
  // tube: mouthpiece at the beak, back under the eye, up past the head
  c.lineCap = StrokeCap.round;
  c.lineJoin = StrokeJoin.round;
  c.strokeStyle = const Color(0xFFC43E00);
  c.lineWidth = 4.2;
  void tube() {
    c.beginPath();
    c.moveTo(bx, my);
    c.lineTo(tx + 3, my);
    c.quadraticCurveTo(tx, my, tx, my - 3);
    c.lineTo(tx, s.top - 8);
  }

  tube();
  c.stroke();
  c.strokeStyle = const Color(0xFFFF7A1A);
  c.lineWidth = 2.8;
  tube();
  c.stroke();
  c.fillStyle = const Color(0xFFFFE03A);
  c.fillRect(tx - 2.1, s.top - 9.5, 4.2, 3);
  c.fillStyle = rgba(255, 255, 255, .75);
  c.fillRect(tx - 1.2, my - 2, 1, -(my - s.top - 4));
  c.fillStyle = const Color(0xFF263238);
  c.rr(bx - 2.5, my - 2.2, 3.5, 4.4, 1.2);
  c.fill();
  // mask strap + frame + glass
  c.fillStyle = const Color(0xFF00838F);
  c.fillRect(s.l, ey - 1.4, ex - 5 - s.l, 2.8);
  c.fillStyle = const Color(0xFF00ACC1);
  c.rr(ex - 6, ey - 5, 12, 10, 3.5);
  c.fill();
  c.fillStyle = rgba(200, 240, 255, .6);
  c.rr(ex - 4.3, ey - 3.4, 8.6, 6.8, 2.4);
  c.fill();
  c.fillStyle = _white;
  c.fillRect(ex - 3.3, ey - 2.6, 1.6, 1.6);
  c.fillRect(ex - 1.4, ey - 2.6, .9, .9);
  c.lineCap = StrokeCap.butt;
}

// ---------------- G2 necktie ----------------
void _necktie(Ctx2D c, BirdShape s, double t, bool flap) {
  final x = math.min(s.r - 8, _bx0(s) - 8);
  final y = math.min(s.neck - 2, s.eye.dy + 8);
  final L = math.min(15.0, s.bot - y + 3);
  c.fp(_white, c.poly([x - 6, y - 2.6, x, y + .6, x - 4, y + 3.4]));
  c.fp(_white, c.poly([x + 6, y - 2.6, x, y + .6, x + 4, y + 3.4]));
  final blade = c.poly([
    x - 2, y + 1.5, x + 2, y + 1.5, x + 4, y + L - 3.4, x, y + L, //
    x - 4, y + L - 3.4,
  ]);
  c.fillStyle = const Color(0xFF1E5BC6);
  c.fill(blade);
  c.save();
  c.clip(blade);
  c.fillStyle = artGold;
  for (var i = 0; i < 5; i++) {
    final yy = y + 2.4 + i * 3.4;
    c.fill(
      c.poly([
        x - 5, yy + 2, x + 5, yy - 1.4, x + 5, yy + .2, x - 5, yy + 3.6, //
      ]),
    );
  }
  c.restore();
  c.fp(
    const Color(0xFF12408F),
    c.poly([
      x - 2.8, y - 1.6, x + 2.8, y - 1.6, x + 2, y + 2.4, x - 2, y + 2.4, //
    ]),
  );
  c.fillStyle = rgba(255, 255, 255, .5);
  c.fillRect(x - 1.4, y - .9, 1.2, 1.2);
}

// ---------------- G3 band-aid ----------------
void _bandaid(Ctx2D c, BirdShape s, double t, bool flap) {
  final ex = s.eye.dx, sc = math.min(1.0, (ex - 3 - s.l) / 13);
  final cx = s.l + .5 + 6.5 * sc, cy = s.top + 6 * sc + .5;
  for (final a in const [.62, -.62]) {
    c.save();
    c.translate(cx, cy);
    c.scale(sc, sc);
    c.rotate(a);
    c.fillStyle = const Color(0xFFE0A56A);
    c.rr(-6.3, -2.5, 12.6, 5, 2.4);
    c.fill();
    c.fillStyle = const Color(0xFFF6CB96);
    c.rr(-5.8, -2, 11.6, 4, 2);
    c.fill();
    c.fillStyle = const Color(0xFFE7AE74);
    c.fillRect(-1.8, -2, 3.6, 4);
    c.fillStyle = const Color(0xFFC98A4E);
    for (final dx in const [-4.3, -3.1, 3.1, 4.3]) {
      c.fillRect(dx - .35, -.35, .7, .7);
    }
    c.restore();
  }
}

// ---------------- G4 bubble gum ----------------
void _gum(Ctx2D c, BirdShape s, double t, bool flap) {
  final (tpx, _) = _tipOf(s);
  final my = _mouthY(s);
  const P = 2.8;
  final u = (t % P) / P, x0 = tpx - 1.5, y0 = my + .5;
  const pink = Color(0xFFFF7EC2);
  if (u < .72) {
    final g = _ease(u / .72), r = 1.8 + 5.4 * g + math.sin(t * 9) * .25 * g;
    final cx = x0 + r * .8;
    c.fillStyle = pink;
    c.beginPath();
    c.arc(cx, y0, r, 0, _tau);
    c.fill();
    c.strokeStyle = const Color(0xFFE0479C);
    c.lineWidth = .9;
    c.stroke();
    c.fillStyle = rgba(255, 255, 255, .85);
    c.beginPath();
    c.ellipse(cx - r * .38, y0 - r * .42, r * .26, r * .15, -.6, 0, _tau);
    c.fill();
    c.fillRect(cx + r * .3, y0 - r * .5, r * .14, r * .14);
  } else if (u < .84) {
    final v = (u - .72) / .12, R = 7.2 + v * 4, cx = x0 + 5.8;
    c.globalAlpha = 1 - v * .6;
    for (var i = 0; i < 7; i++) {
      final a = i / 7 * _tau + .4;
      c.circ(
        cx + math.cos(a) * R * .85,
        y0 + math.sin(a) * R * .85,
        1.5 - v * .6,
        pink,
      );
    }
    c.strokeStyle = _white;
    c.lineWidth = 1;
    c.beginPath();
    for (var i = 0; i < 4; i++) {
      final a = i / 4 * _tau + .8;
      c.moveTo(cx + math.cos(a) * R * .35, y0 + math.sin(a) * R * .35);
      c.lineTo(cx + math.cos(a) * R * .6, y0 + math.sin(a) * R * .6);
    }
    c.stroke();
    c.globalAlpha = 1;
  } else {
    final v = (u - .84) / .16;
    c.fillStyle = pink;
    c.beginPath();
    c.ellipse(
      x0 + 1.2,
      y0 + .6,
      3 * (1 - v * .5),
      1.8 * (1 - v * .3),
      .2,
      0,
      _tau,
    );
    c.fill();
    c.circ(x0 - .6, y0 + 2.2, 1 * (1 - v), pink);
  }
}

// ---------------- G5 flower lei ----------------
const List<Color> _leiColors = [
  Color(0xFFEC008C), Color(0xFFFFB529), Color(0xFFFFFFFF), //
  Color(0xFFFF7043), Color(0xFF9B30D9), Color(0xFFFFE03A),
];

void _flower(Ctx2D c, double x, double y, double r, Color col) {
  c.fillStyle = col;
  for (var i = 0; i < 5; i++) {
    final a = i / 5 * _tau - .3;
    c.beginPath();
    c.arc(
      x + math.cos(a) * r * .62,
      y + math.sin(a) * r * .62,
      r * .48,
      0,
      _tau,
    );
    c.fill();
  }
  c.circ(
    x,
    y,
    r * .34,
    col == const Color(0xFFFFE03A) || col == artGold
        ? const Color(0xFFFF7043)
        : const Color(0xFFFFE03A),
  );
}

void _lei(Ctx2D c, BirdShape s, double t, bool flap) {
  final x0 = s.l + 2.5, x1 = math.min(s.r - 1, _bx0(s) - 2);
  final y = s.neck - 2.5;
  const n = 6;
  double px(int i) => x0 + (x1 - x0) * (i / (n - 1));
  double py(int i) => y + math.sin(i / (n - 1) * math.pi) * 4.2;
  c.fillStyle = const Color(0xFF43A047);
  for (var i = 0; i < n - 1; i++) {
    final mx = (px(i) + px(i + 1)) / 2, my = (py(i) + py(i + 1)) / 2;
    c.beginPath();
    c.ellipse(mx, my + 1.2, 2.4, 1.1, i.isOdd ? .5 : -.5, 0, _tau);
    c.fill();
  }
  for (var i = 0; i < n; i++) {
    _flower(c, px(i), py(i), 3.3, _leiColors[i % _leiColors.length]);
  }
}

// ---------------- G6 balloon ----------------
void _balloonBack(Ctx2D c, BirdShape s, double t, bool flap) {
  final sw = math.sin(t * 1.9), ax = s.l + 3, ay = s.neck - 7;
  final bx = s.l - 7 + sw * 1.6, by = s.top - 4 + math.cos(t * 2.3) * .8;
  const ry = 7.0, rx = 6.0;
  c.strokeStyle = const Color(0xFF5D4037);
  c.lineWidth = 1.1;
  c.beginPath();
  c.moveTo(ax, ay);
  c.bezierCurveTo(
    ax - 6,
    ay - 2 + sw,
    bx + 2 - sw * 2,
    by + ry + 6,
    bx,
    by + ry + 1.5,
  );
  c.stroke();
  c.save();
  c.translate(bx, by);
  c.rotate(sw * .12);
  c.fp(
    const Color(0xFFB71C1C),
    c.poly([-1.6, ry + 2.2, 0, ry - .5, 1.6, ry + 2.2]),
  );
  c.fillStyle = const Color(0xFFE53935);
  c.beginPath();
  c.ellipse(0, 0, rx, ry, 0, 0, _tau);
  c.fill();
  c.fillStyle = const Color(0xFFC62828);
  c.beginPath();
  c.ellipse(1.6, 1.6, rx - 2.2, ry - 2.2, 0, -.3, 1.9);
  c.lineTo(1.6, 1.6);
  c.fill();
  c.fillStyle = rgba(255, 255, 255, .85);
  c.beginPath();
  c.ellipse(-2.4, -3.2, 1.3, 2.3, .45, 0, _tau);
  c.fill();
  c.fillRect(-3.6, .2, 1, 1);
  c.restore();
}

// ---------------- G7 backpack ----------------
(double, double) _packPos(BirdShape s) => s.hasBl
    ? (s.bl + 15, s.top + 5)
    : (s.l + 2, math.max(s.top + 4, s.neck - 19));

void _backpackBack(Ctx2D c, BirdShape s, double t, bool flap) {
  final (px, py) = _packPos(s);
  final x = px - 12;
  // charm swinging under the pack
  final a = math.sin(t * 3.4) * .5;
  c.save();
  c.translate(x + 3, py + 14.2);
  c.rotate(a);
  c.strokeStyle = const Color(0xFFFFB529);
  c.lineWidth = .9;
  c.beginPath();
  c.moveTo(0, 0);
  c.lineTo(0, 3.4);
  c.stroke();
  c.star(0, 5.2, 2.8, const Color(0xFF1E9BE0), t * .6);
  c.circ(0, 5.2, .8, _white);
  c.restore();
  const dark = Color(0xFFE65100);
  c.fillStyle = dark;
  c.rr(x, py, 10.5, 15, 3.2);
  c.fill();
  c.fillStyle = const Color(0xFFFF7A1A);
  c.rr(x + .8, py + .8, 9.2, 13.6, 2.6);
  c.fill();
  c.fillStyle = dark;
  c.rr(x, py, 10.5, 5.5, const [3.2, 3.2, 1.6, 1.6]);
  c.fill();
  c.fillStyle = const Color(0xFFFFB529);
  c.rr(x + 3.3, py + 4, 3, 2.6, .8);
  c.fill();
  c.fillStyle = dark;
  c.rr(x + 1.6, py + 8.4, 6.2, 4.6, 1.4);
  c.fill();
  c.fillStyle = const Color(0xFFFFCC80);
  c.fillRect(x + 2.4, py + 9.1, 4.6, 1);
  c.fillStyle = rgba(255, 255, 255, .55);
  c.fillRect(x + 1.6, py + 1.2, 1.6, 1.6);
}

void _backpackFront(Ctx2D c, BirdShape s, double t, bool flap) {
  final (px, p0) = _packPos(s);
  final py = s.hasBl ? p0 + 5 : p0, L = s.hasBl ? 9.0 : 13.6, k = L / 13.6;
  c.fp(
    const Color(0xFFC43E00),
    c.poly([
      px - 2.4, py + 1, px + 1.6, py + 1, px + 1.6 + 5.6 * k, py + L, //
      px - 2.4 + 6.4 * k, py + L + .6,
    ]),
  );
  final bx = px + .2 + 2.8 * k, by = py + 1 + 5.8 * k;
  c.fillStyle = const Color(0xFFFFB529);
  c.fillRect(bx - 1.6, by - 1.2, 3.2, 2.4);
  c.fillStyle = const Color(0xFFE65100);
  c.fillRect(bx - .6, by - .6, 1.2, 1.2);
}

// ---------------- G8 roller skates ----------------
void _skates(Ctx2D c, BirdShape s, double t, bool flap) {
  final sw = flap ? -.5 : .4;
  for (final (k, x) in [(0, s.r - 17), (1, s.r - 7)]) {
    c.save();
    c.translate(x, s.bot);
    c.rotate(sw * (k == 1 ? 1 : .6));
    c.fillStyle = const Color(0xFFFFB529);
    c.fillRect(-.6, 0, 1.2, 2.4);
    c.fillStyle = _white;
    c.rr(-2.8, 1.6, 6.6, 5.4, const [2.4, 2.4, 1, 1]);
    c.fill();
    c.rr(-2.8, 4.2, 9, 2.8, const [1, 2.4, 1, 1]);
    c.fill();
    c.fillStyle = artPink;
    c.fillRect(-2.8, 2, 6.6, 1.6);
    c.fillRect(1.2, 4.6, 1.1, 1.1);
    c.fillRect(3, 4.6, 1.1, 1.1);
    c.fillStyle = const Color(0xFF455A64);
    c.fillRect(-3, 7, 9.6, 1.2);
    for (final wx in const [-1.0, 4.4]) {
      c.circ(wx, 9.6, 2.1, const Color(0xFF00BCD4));
      c.fillStyle = _white;
      c.save();
      c.translate(wx, 9.6);
      c.rotate(t * 18 + wx);
      c.fillRect(-1.5, -.4, 3, .8);
      c.restore();
      c.circ(wx, 9.6, .55, const Color(0xFF006064));
    }
    c.restore();
  }
}

// ---------------- G9 swim ring ----------------
void _ringHalf(Ctx2D c, BirdShape s, double t, bool front) {
  final l = (s.hasBl ? s.bl + 1 : s.l) - 1, r = s.r + (s.hasBl ? 3 : 1);
  final cx = (l + r) / 2, cy = s.bot - 6.5 + math.sin(t * 3) * .7;
  final rx = (r - l) / 2 + 3.8;
  const ry = 4.8, n = 10;
  final a0 = front ? 0.0 : math.pi;
  c.lineWidth = 5.6;
  for (var i = 0; i < n / 2; i++) {
    final red = (i % 2 == 0) == front;
    c.strokeStyle = front
        ? (red ? const Color(0xFFE53935) : _white)
        : (red ? const Color(0xFFB71C1C) : const Color(0xFFE0E0E0));
    c.beginPath();
    c.ellipse(
      cx,
      cy,
      rx,
      ry,
      0,
      a0 + i * _tau / n - .01,
      a0 + (i + 1) * _tau / n + .01,
    );
    c.stroke();
  }
  if (front) {
    c.strokeStyle = rgba(255, 255, 255, .75);
    c.lineWidth = 1;
    c.beginPath();
    c.ellipse(cx, cy + .6, rx, ry, 0, .5, 1.25);
    c.stroke();
  }
}

// ---------------- G10 cape ----------------
(double, double) _capeAt(BirdShape s) =>
    s.hasBl ? (s.l + 3, s.neck - 7) : (s.l + 5, s.top + 3);

void _capeBack(Ctx2D c, BirdShape s, double t, bool flap) {
  final (ax, y0) = _capeAt(s);
  const L = 19.0, n = 10;
  // streams back from the shoulders: narrow at the neck, flaring to a
  // rippling hem
  double w(double u, double ph) => math.sin(t * 8 - u * 6 + ph) * u * 2.6;
  final top = List<double>.filled((n + 1) * 2, 0);
  final bot = List<double>.filled((n + 1) * 2, 0);
  for (var i = 0; i <= n; i++) {
    final u = i / n;
    top[i * 2] = ax - u * L;
    top[i * 2 + 1] = y0 - u * 1.5 + w(u, 0);
    bot[i * 2] = ax - u * (L - 1.5);
    bot[i * 2 + 1] = y0 + 6 + u * 9 + w(u, .8);
  }
  final cape = c.newPath()..moveTo(top[0], top[1]);
  for (var i = 1; i <= n; i++) {
    cape.lineTo(top[i * 2], top[i * 2 + 1]);
  }
  for (var i = n; i >= 0; i--) {
    cape.lineTo(bot[i * 2], bot[i * 2 + 1]);
  }
  cape.close();
  c.fp(const Color(0xFF6A1B9A), cape);
  c.save();
  c.clip(cape);
  c.fillStyle = const Color(0xFF4A148C);
  for (final v in const [.4, .7]) {
    final i = (v * n).round();
    final x = top[i * 2], y = top[i * 2 + 1];
    final x2 = bot[i * 2], y2 = bot[i * 2 + 1];
    c.fill(c.poly([x + .8, y, x2 + 1.6, y2, x2 - 1.2, y2]));
  }
  c.fillStyle = artPink;
  c.beginPath();
  for (var i = 0; i <= n; i++) {
    c.lineTo(bot[i * 2], bot[i * 2 + 1] - 2.4);
  }
  for (var i = n; i >= 0; i--) {
    c.lineTo(bot[i * 2], bot[i * 2 + 1] + 1);
  }
  c.fill();
  c.restore();
  c.strokeStyle = artGold;
  c.lineWidth = 1.3;
  c.lineJoin = StrokeJoin.round;
  c.beginPath();
  c.moveTo(top[n * 2], top[n * 2 + 1]);
  c.lineTo(bot[n * 2], bot[n * 2 + 1]);
  c.stroke();
  c.strokeStyle = const Color(0xFF9C4DCC);
  c.lineWidth = 1;
  c.beginPath();
  for (var i = 0; i <= n; i++) {
    c.lineTo(top[i * 2], top[i * 2 + 1] + .7);
  }
  c.stroke();
}

void _capeFront(Ctx2D c, BirdShape s, double t, bool flap) {
  final (cx, y0) = _capeAt(s);
  final ax = cx - 2;
  c.fp(
    const Color(0xFF6A1B9A),
    c.poly([
      ax - 1,
      y0 - .5,
      ax + 3.5,
      y0 + 1.5,
      ax + 2.5,
      y0 + 5.5,
      ax - 1,
      y0 + 6, //
    ]),
  );
  c.fp(
    artGold,
    c.poly([
      ax + 2.2,
      y0 + 1.4,
      ax + 3.6,
      y0 + 3.2,
      ax + 2.2,
      y0 + 5,
      ax + .8,
      y0 + 3.2, //
    ]),
  );
}

// ---------------- G11 butterfly wings ----------------
void _bfWing(Ctx2D c, double up, bool far) {
  final top = Ctx2D.radialGradient('bfT', 0, 0, 1, -6, -8, 16, const [
    (0, Color(0xFFFFE03A)),
    (.35, Color(0xFFFF4FB7)),
    (1, Color(0xFF9B30D9)),
  ]);
  c.save();
  c.rotate(up);
  if (far) {
    c.globalAlpha *= .75;
    c.scale(.85, .85);
  }
  // lower wing
  c.fillStyle = const Color(0xFF4A0E6B);
  c.beginPath();
  c.moveTo(0, 0);
  c.bezierCurveTo(-4, 5, -12, 7, -12, 2);
  c.bezierCurveTo(-12, -2, -6, -2, 0, 0);
  c.fill();
  c.fillStyle = top;
  c.beginPath();
  c.moveTo(-.6, .4);
  c.bezierCurveTo(-4, 4.2, -10.6, 5.6, -10.6, 2);
  c.bezierCurveTo(-10.6, -1, -6, -1.2, -.6, .4);
  c.fill();
  // upper wing
  c.fillStyle = const Color(0xFF4A0E6B);
  c.beginPath();
  c.moveTo(0, 0);
  c.bezierCurveTo(-2, -9, -10, -17, -16, -14);
  c.bezierCurveTo(-19, -11, -12, -3, 0, 0);
  c.fill();
  c.fillStyle = top;
  c.beginPath();
  c.moveTo(-.8, -.8);
  c.bezierCurveTo(-2.6, -8.4, -10, -15.4, -15, -13);
  c.bezierCurveTo(-17.2, -10.6, -11.4, -3.6, -.8, -.8);
  c.fill();
  c.circ(-12.6, -11.6, 1.3, _white);
  c.circ(-9.6, -12.2, .9, _white);
  c.circ(-7, 2.6, 1.1, _white);
  c.restore();
}

void _butterflyBack(Ctx2D c, BirdShape s, double t, bool flap) {
  final fl = math.sin(t * 16) * .12, a = (flap ? .55 : -.2) + fl;
  c.save();
  c.translate(s.wing[0] + 3, s.wing[1] - 6);
  _bfWing(c, a - .45, true);
  _bfWing(c, a, false);
  c.restore();
}

// ---------------- G12 drone buddy ----------------
void _droneBack(Ctx2D c, BirdShape s, double t, bool flap) {
  final x = s.l - 6 + math.sin(t * 1.3) * 2;
  final y = s.top - 7 + math.sin(t * 2.7) * 1.6;
  c.save();
  c.translate(x, y);
  c.rotate(math.sin(t * 1.3 + .6) * .1);
  c.fillStyle = const Color(0xFF37474F);
  c.fillRect(-8, -3.2, 16, 1.6);
  c.fillRect(-7.4, -4.6, 1.4, 2);
  c.fillRect(6, -4.6, 1.4, 2);
  for (final rx in const [-6.7, 6.7]) {
    c.fillStyle = rgba(176, 190, 197, .55);
    c.beginPath();
    c.ellipse(rx, -5, 4.6, 1.1, 0, 0, _tau);
    c.fill();
    final w = math.cos(t * 31 + rx) * 4.4;
    c.fillStyle = const Color(0xFF263238);
    c.fillRect(rx - w.abs(), -5.5, w.abs() * 2, 1);
    c.circ(rx, -5, .8, const Color(0xFF263238));
  }
  c.fillStyle = const Color(0xFFECEFF1);
  c.rr(-5.5, -2.6, 11, 7.4, 3);
  c.fill();
  c.fillStyle = const Color(0xFFCFD8DC);
  c.fillRect(-5, 2.6, 10, 1.4);
  c.fillStyle = const Color(0xFF263238);
  c.rr(-3.6, -1.4, 7.2, 3.8, 1.4);
  c.fill();
  final bl = (t % 3.2) > 3.05;
  c.fillStyle = const Color(0xFF4DD0E1);
  if (bl) {
    c.fillRect(-2.4, .4, 1.6, .5);
    c.fillRect(.8, .4, 1.6, .5);
  } else {
    c.fillRect(-2.4, -.4, 1.6, 1.8);
    c.fillRect(.8, -.4, 1.6, 1.8);
  }
  final on = math.sin(t * 6) > 0;
  c.circ(4.2, -2, .8, on ? const Color(0xFFFF1744) : const Color(0xFF7F0000));
  c.circ(-4.2, -2, .8, on ? const Color(0xFF00E676) : const Color(0xFF1B5E20));
  c.fillStyle = const Color(0xFF455A64);
  c.fillRect(-2.6, 4.8, 1, 1.6);
  c.fillRect(1.6, 4.8, 1, 1.6);
  c.restore();
}

// ---------------- G13 crystal wings ----------------
const List<double> _shards = [-21, -17, -23, -8, -21, 1, -14, 6];

void _crystalWing(Ctx2D c, double t, bool far) {
  c.save();
  if (far) {
    c.globalAlpha *= .7;
    c.scale(.86, .86);
  }
  for (var i = _shards.length ~/ 2 - 1; i >= 0; i--) {
    final tx = _shards[i * 2], ty = _shards[i * 2 + 1];
    final len = math.sqrt(tx * tx + ty * ty);
    final nx = -ty / len * 3.4,
        ny = tx / len * 3.4,
        mx = tx * .55,
        my = ty * .55;
    c.fp(
      i.isOdd ? const Color(0xFF7C4DFF) : const Color(0xFF4DD0E1),
      c.poly([0, 0, mx + nx, my + ny, tx, ty, mx, my]),
    );
    c.fp(
      i.isOdd ? const Color(0xFFB388FF) : const Color(0xFFB2EBF2),
      c.poly([0, 0, mx - nx, my - ny, tx, ty, mx, my]),
    );
    c.fillStyle = rgba(255, 255, 255, .8);
    c.fill(
      c.poly([
        mx * .4 - nx * .2, my * .4 - ny * .2, mx - nx * .7, my - ny * .7, //
        mx - nx * .45, my - ny * .45,
      ]),
    );
  }
  c.restore();
}

void _crystalBack(Ctx2D c, BirdShape s, double t, bool flap) {
  final a = (flap ? .5 : -.22) + math.sin(t * 3) * .05;
  c.save();
  c.translate(s.wing[0] + 2, s.wing[1] - 6);
  c.shadowColor = rgba(128, 222, 234, .9);
  c.shadowBlur = 6;
  c.save();
  c.rotate(a - .4);
  _crystalWing(c, t, true);
  c.restore();
  c.save();
  c.rotate(a);
  _crystalWing(c, t, false);
  c.shadowBlur = 0;
  for (var i = 0; i < _shards.length ~/ 2; i++) {
    final tw = math.sin(t * 3.2 + i * 1.7);
    if (tw > .1) {
      c.star(
        _shards[i * 2],
        _shards[i * 2 + 1],
        1.2 + tw * 2.6,
        _white,
        t * 2 + i,
      );
    }
  }
  c.restore();
  final k = (t * 2.2).floor(), u = t * 2.2 - k;
  if (u < .6) {
    final sx = s.wing[0] - 4 - artHash(k) * 12;
    final sy = s.wing[1] - 10 - artHash(k + 7) * 12;
    final r = math.sin(u / .6 * math.pi) * 2.2;
    c.star(sx, sy, r, const Color(0xFFE0F7FA), u * 3);
  }
  c.restore();
}

// ---------------- G14 atom ----------------
const List<(double, double, Color, double, double)> _orbits = [
  (0, 1.9, Color(0xFF00E5FF), 0, 1),
  (1, -2.5, Color(0xFFFF4FB7), 2, 1),
  (-1, 2.2, Color(0xFFFFE03A), 4, -1),
];

void _atomPass(Ctx2D c, BirdShape s, double t, bool front) {
  final cx = (s.l + s.r) / 2 - 1, cy = (s.top + s.bot) / 2 + 1.5;
  const rX = 23.0, rY = 6.2;
  c.save();
  c.translate(cx, cy);
  c.lineWidth = 1.3;
  for (final (th, _, col, _, d) in _orbits) {
    c.save();
    c.rotate(th);
    c.strokeStyle = col;
    c.globalAlpha = front ? .8 : .45;
    final f = front == (d > 0);
    c.beginPath();
    c.ellipse(0, 0, rX, rY, 0, f ? 0 : math.pi, f ? math.pi : _tau);
    c.stroke();
    c.restore();
  }
  c.globalAlpha = 1;
  for (final (th, sp, col, ph, d) in _orbits) {
    final ct = math.cos(th), st = math.sin(th);
    for (var j = 4; j >= 0; j--) {
      final a = t * sp + ph - j * .13 * sp.sign, dp = math.sin(a) * d;
      if ((dp >= 0) != front) continue;
      final lx = math.cos(a) * rX, ly = math.sin(a) * rY;
      final X = lx * ct - ly * st, Y = lx * st + ly * ct;
      if (j != 0) {
        c.globalAlpha = .5 - j * .1;
        c.circ(X, Y, 2 - j * .3, col);
        c.globalAlpha = 1;
      } else {
        final sc = front ? 1.0 : .8;
        c.shadowColor = col;
        c.shadowBlur = 6;
        c.circ(X, Y, 2.6 * sc, col);
        c.shadowBlur = 0;
        c.circ(X - .6, Y - .6, 1 * sc, _white);
      }
    }
  }
  c.restore();
}

// ---------------- G15 disco ball ----------------
const List<Color> _spots = [
  Color(0xFFFFE03A), Color(0xFF00E5FF), Color(0xFFFF4FB7), //
  Color(0xFF69F0AE), Color(0xFFB388FF),
];
final List<double> _dsp = List<double>.filled(10, 0);

void _disco(Ctx2D c, BirdShape s, double t, bool flap) {
  final bx = s.l - 6, by = s.top - 6 + math.sin(t * 2.2) * 1.2;
  const R = 7.0;
  // coloured light spots sweeping over the body
  final P = _dsp;
  for (var i = 0; i < 5; i++) {
    final u = (t * .3 + i / 5) % 1;
    P[i * 2] = s.l - 4 + u * (s.r - s.l + 8);
    P[i * 2 + 1] =
        s.top +
        6 +
        (((i * 3) % 5) / 4) * (s.bot - s.top - 12) +
        math.sin(t * 2 + i) * 2;
  }
  c.save();
  c.globalAlpha = .2;
  for (var i = 0; i < 5; i += 2) {
    final x = P[i * 2], y = P[i * 2 + 1], dx = x - bx, dy = y - by;
    var d = math.sqrt(dx * dx + dy * dy);
    if (d == 0) d = 1;
    final nx = -dy / d, ny = dx / d;
    c.fillStyle = _spots[i];
    c.beginPath();
    c.moveTo(bx, by);
    c.lineTo(x + nx * 3, y + ny * 3);
    c.lineTo(x - nx * 3, y - ny * 3);
    c.fill();
  }
  c.restore();
  c.save();
  c.clip(s.body);
  for (var i = 0; i < 5; i++) {
    final x = P[i * 2], y = P[i * 2 + 1];
    c.globalAlpha = .35;
    c.circ(x, y, 4.2, _spots[i]);
    c.globalAlpha = .75;
    c.circ(x, y, 2.6, _spots[i]);
    c.globalAlpha = .9;
    c.circ(x - .7, y - .7, .9, _white);
  }
  c.restore();
  // hanger
  c.fillStyle = const Color(0xFF546E7A);
  c.fillRect(bx - .6, by - R - 4, 1.2, 3);
  c.fillStyle = const Color(0xFF78909C);
  c.rr(bx - 2, by - R - 1.6, 4, 2.4, .8);
  c.fill();
  // ball: mirror tiles on a sphere, scrolling with the spin
  c.save();
  c.shadowColor = rgba(255, 255, 255, .95);
  c.shadowBlur = 6;
  c.circ(bx, by, R, const Color(0xFF78909C));
  c.restore();
  c.save();
  c.beginPath();
  c.arc(bx, by, R, 0, _tau);
  c.clip();
  const rows = 5, cols = 6;
  final sp = t * 1.4, rot = sp % 1, base = sp.floor();
  for (var j = 0; j < rows; j++) {
    final v0 = -1 + j * 2 / rows, v1 = v0 + 2 / rows;
    final y0 = by + v0 * R, y1 = by + v1 * R;
    final m = (v0 + v1) / 2;
    final hw = math.sqrt(math.max(0, 1 - m * m)) * R;
    for (var i = -1; i < cols; i++) {
      final p0 = -math.pi / 2 + (i + rot) / cols * math.pi;
      final p1 = p0 + math.pi / cols;
      if (p1 <= -math.pi / 2 || p0 >= math.pi / 2) continue;
      final x0 = bx + math.sin(math.max(-math.pi / 2, p0)) * hw;
      final x1 = bx + math.sin(math.min(math.pi / 2, p1)) * hw;
      final h = artHash(j * 31 + (i - base) * 7);
      final lit = .5 + .5 * math.sin(t * 6 + h * 20);
      c.fillStyle = h < .2
          ? _spots[(j * 2 + i - base + 50) % 5]
          : Color.fromARGB(
              255,
              (140 + lit * 115).truncate(),
              (160 + lit * 95).truncate(),
              (180 + lit * 75).truncate(),
            );
      c.fillRect(x0 + .3, y0 + .3, math.max(0, x1 - x0 - .6), y1 - y0 - .6);
    }
  }
  c.fillStyle = Ctx2D.radialGradient('disco', -2.5, -2.5, 1, 0, 0, R, const [
    (0, Color.fromRGBO(255, 255, 255, 0)),
    (.6, Color.fromRGBO(38, 50, 56, 0)),
    (1, Color.fromRGBO(38, 50, 56, .55)),
  ]);
  c.translate(bx, by);
  c.fillRect(-R, -R, 2 * R, 2 * R);
  c.restore();
  final tw = math.sin(t * 3.3).abs();
  c.star(bx - 2.6, by - 2.8, 1.3 + tw * 2.2, _white, t);
  final k = (t * 1.8).floor(), u = t * 1.8 - k;
  if (u < .5) {
    c.star(
      bx + (artHash(k) - .5) * 9,
      by + (artHash(k + 3) - .5) * 9,
      math.sin(u / .5 * math.pi) * 2.4,
      _white,
      u,
    );
  }
}
