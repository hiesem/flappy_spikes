import 'dart:math' as math;
import 'dart:ui';

/// Shared drawing helpers for the skin art port of
/// `design/menu_v2/skin_art.js` (all coordinates in art units, the 44 x 36
/// bird box). Pure `dart:ui` painting — no Flame, no game dependency.

/// A full turn (JS `TAU`).
const double tau = math.pi * 2;

/// Palette constants shared by the art (JS `PINK`, `SOFT`, `GOLD`, `PLUM`).
const Color artPink = Color(0xFFEC008C);
const Color artSoft = Color(0xFFFCD9EE);
const Color artGold = Color(0xFFFFB529);
const Color artPlum = Color(0xFF7A0044);

/// Octagon with corner cut [c] (JS `oct`).
Path octPath(double x, double y, double w, double h, double c) => Path()
  ..moveTo(x + c, y)
  ..lineTo(x + w - c, y)
  ..lineTo(x + w, y + c)
  ..lineTo(x + w, y + h - c)
  ..lineTo(x + w - c, y + h)
  ..lineTo(x + c, y + h)
  ..lineTo(x, y + h - c)
  ..lineTo(x, y + c)
  ..close();

/// Closed polygon from flat `[x0, y0, x1, y1, ...]` coordinates (JS `poly`).
Path polyPath(List<double> pts) => addPoly(Path(), pts);

/// Appends a closed polygon sub-path to [path] and returns it.
Path addPoly(Path path, List<double> pts) {
  path.moveTo(pts[0], pts[1]);
  for (var i = 2; i < pts.length; i += 2) {
    path.lineTo(pts[i], pts[i + 1]);
  }
  return path..close();
}

/// Deterministic pseudo-random in [0, 1) (JS `hash`).
double artHash(num i) {
  final s = math.sin(i * 127.1 + 311.7) * 43758.5453;
  return s - s.floorToDouble();
}

final Paint _fill = Paint()..style = PaintingStyle.fill;
final Paint _stroke = Paint()
  ..style = PaintingStyle.stroke
  ..strokeMiterLimit = 10; // canvas 2D default
final Paint _shader = Paint()..style = PaintingStyle.fill;

/// The shared fill paint set to [color]. Use it immediately (it is reused).
Paint fillPaint(Color color) => _fill..color = color;

/// The shared stroke paint (butt caps, miter joins like canvas 2D).
Paint strokePaint(Color color, double width) => _stroke
  ..color = color
  ..strokeWidth = width;

/// The shared shader fill paint (optionally with an [opacity]).
Paint shaderPaint(Shader shader, {double opacity = 1}) => _shader
  ..shader = shader
  ..color = Color.fromRGBO(0, 0, 0, opacity);

/// `ctx.fillRect` in [color].
void fillRect(Canvas c, double x, double y, double w, double h, Color color) =>
    c.drawRect(Rect.fromLTWH(x, y, w, h), fillPaint(color));

/// Filled circle (JS `circ`).
void circ(Canvas c, double x, double y, double r, Color color) =>
    c.drawCircle(Offset(x, y), r, fillPaint(color));

/// Rounded rect with one radius (JS `rr` + fill).
void fillRoundRect(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
  double r,
  Color color,
) => c.drawRRect(
  RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
  fillPaint(color),
);

final Path _star = () {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final rr = i.isOdd ? .38 : 1.0;
    final a = i * math.pi / 4;
    final x = math.cos(a) * rr, y = math.sin(a) * rr;
    i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
  }
  return p..close();
}();

/// Four-point sparkle star of radius [r] rotated by [rot] (JS `star`).
void paintStar(
  Canvas c,
  double x,
  double y,
  double r,
  Color color, {
  double rot = 0,
}) {
  c.save();
  c.translate(x, y);
  c.rotate(rot);
  c.scale(r, r);
  c.drawPath(_star, fillPaint(color));
  c.restore();
}

final Path _heart = Path()
  ..moveTo(0, 4)
  ..cubicTo(-7, -1, -5, -7, 0, -3.5)
  ..cubicTo(5, -7, 7, -1, 0, 4)
  ..close();

/// Heart of size [s] centred at ([x], [y]) (JS `heart`).
void paintHeart(Canvas c, double x, double y, double s, Color color) {
  c.save();
  c.translate(x, y);
  c.scale(s / 10, s / 10);
  c.drawPath(_heart, fillPaint(color));
  c.restore();
}

/// Dash a path like `ctx.setLineDash(pattern)` (offset 0).
Path dashPath(Path source, List<double> pattern) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    var i = 0;
    var on = true;
    while (d < metric.length) {
      final len = pattern[i % pattern.length];
      if (on) out.addPath(metric.extractPath(d, d + len), Offset.zero);
      d += len;
      on = !on;
      i++;
    }
  }
  return out;
}
