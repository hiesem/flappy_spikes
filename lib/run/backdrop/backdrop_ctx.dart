import 'dart:math' as math;
import 'dart:ui';

import 'backdrop_math.dart';

/// PRD-2.4 §3 — a thin canvas-2D facade over a Flutter [Canvas], so the
/// prototype's drawing code (`docs/p24/endless_vertical.html`) ports line by
/// line: `fillStyle` / `strokeStyle` / `lineWidth` / `globalAlpha` state with
/// `save` / `restore`, one current path (`beginPath`, `moveTo`, `arc`,
/// `ellipse`, `roundRect`, …), `fill` / `stroke` / `clip`.
///
/// It also carries the world state the prototype keeps in `W_` (camera,
/// clock, the stage being drawn, the drawn x range) so every scene painter
/// gets one object. One [Ctx] lives as long as the backdrop: its [Path] and
/// [Paint]s are reused every frame (PRD-2.4 §3.4: no per-frame allocation on
/// the hot path).
class Ctx {
  Ctx();

  late Canvas canvas;

  // ------------------------------------------------------------ world state
  /// `W_.cam`: the world distance (prototype `cam`, pt).
  double cam = 0;

  /// `S.t`: the run clock (s).
  double t = 0;

  /// `W_.env`: the absolute stage index being drawn (may exceed 9 or be
  /// negative; scenes use `modI(env, kNST)`).
  int env = 0;

  /// `XL` / `XR`: the drawn x range (design pt).
  double xl = 0, xr = kVW;

  /// Design y of the top of the screen: 0 at 568 pt, negative on taller
  /// views (the sky grows above the 568 design; PRD-2.4 §3.3).
  double yTop = 0;

  /// The view height (pt) and its extra over the 568 design.
  double viewHeight = kVH;
  double get ext => viewHeight - kVH;

  /// `W_.vert`: an older move draws the arriving stage (no sky gradients).
  bool vert = false;

  /// `W_.cut`: tiles that end with their stage are cut, not thinned.
  bool cut = false;

  /// `G.fold` (seam 6): < 1 while the paper peaks pop up from the page.
  double fold = 1;

  // ------------------------------------------------------------ strip cache
  final Map<int, _Strip> _strips = {};
  final _Style _held = _Style();

  /// PRD-2.4 §3.4 a static band (no animation: a function of its scroll
  /// offset only) drawn from a cached [Picture]: [paint] records the band
  /// once for offset `off0` over three screen widths, and every frame the
  /// picture is drawn shifted by `off0 − off`. Re-recorded when the band has
  /// scrolled a screen width, or the view changed. [key] names the band.
  void strip(int key, double off, void Function(double off) paint) {
    var s = _strips[key];
    if (s == null ||
        (off - s.off0).abs() > kVW ||
        s.yTop != yTop ||
        s.xl != xl ||
        s.xr != xr) {
      s?.pic.dispose();
      final rec = PictureRecorder();
      final outer = canvas, oxl = xl, oxr = xr, depth = _depth;
      _held.copyFrom(this);
      canvas = Canvas(rec);
      xl = oxl - kVW;
      xr = oxr + kVW;
      paint(off);
      while (_depth > depth) {
        restore();
      }
      canvas = outer;
      xl = oxl;
      xr = oxr;
      _held.copyTo(this);
      s = _strips[key] = _Strip(rec.endRecording(), off, yTop, xl, xr);
    }
    canvas.save();
    canvas.translate(s.off0 - off, 0);
    canvas.drawPicture(s.pic);
    canvas.restore();
  }

  /// Drops every cached strip (the backdrop calls it when it leaves the
  /// world; a new run starts with its own Ctx).
  void clearStrips() {
    for (final s in _strips.values) {
      s.pic.dispose();
    }
    _strips.clear();
  }

  /// How many strip pictures are cached (tests).
  int get stripCount => _strips.length;

  // ------------------------------------------------------------ rng pool
  final List<Rng> _rngs = List.generate(8, (_) => Rng());
  int _rngDepth = 0;

  /// A pooled [Rng] for one `each` call (released with [releaseRng]).
  Rng takeRng() {
    if (_rngDepth >= _rngs.length) _rngs.add(Rng());
    return _rngs[_rngDepth++];
  }

  void releaseRng() => _rngDepth--;

  // ------------------------------------------------------------ style state
  Color _fillColor = const Color(0xFF000000);
  Color _strokeColor = const Color(0xFF000000);

  /// `fillStyle = colour` (clears a gradient fill).
  Color get fillStyle => _fillColor;
  set fillStyle(Color c) {
    _fillColor = c;
    fillShader = null;
  }

  /// `fillStyle = gradient`.
  Shader? fillShader;

  /// `strokeStyle = colour` (clears a gradient stroke).
  Color get strokeStyle => _strokeColor;
  set strokeStyle(Color c) {
    _strokeColor = c;
    strokeShader = null;
  }

  /// `strokeStyle = gradient`.
  Shader? strokeShader;
  double lineWidth = 1;
  StrokeCap lineCap = StrokeCap.butt;
  StrokeJoin lineJoin = StrokeJoin.miter;
  double globalAlpha = 1;
  List<double>? lineDash;
  double lineDashOffset = 0;

  final List<_Style> _stack = [];
  int _depth = 0;

  void save() {
    canvas.save();
    if (_depth >= _stack.length) _stack.add(_Style());
    _stack[_depth++].copyFrom(this);
  }

  void restore() {
    if (_depth == 0) return;
    canvas.restore();
    _stack[--_depth].copyTo(this);
  }

  /// Clears every style back to the canvas defaults (start of a frame).
  void resetStyle() {
    _fillColor = const Color(0xFF000000);
    fillShader = null;
    _strokeColor = const Color(0xFF000000);
    strokeShader = null;
    lineWidth = 1;
    lineCap = StrokeCap.butt;
    lineJoin = StrokeJoin.miter;
    globalAlpha = 1;
    lineDash = null;
    lineDashOffset = 0;
    _depth = 0;
    _rngDepth = 0;
    vert = false;
    cut = false;
    fold = 1;
  }

  void translate(double x, double y) => canvas.translate(x, y);
  void rotate(double a) => canvas.rotate(a);
  void scale(double x, double y) => canvas.scale(x, y);

  // ------------------------------------------------------------ path
  final Path path = Path();
  bool _has = false;

  void beginPath() {
    path.reset();
    _has = false;
  }

  void moveTo(double x, double y) {
    path.moveTo(x, y);
    _has = true;
  }

  void lineTo(double x, double y) {
    if (!_has) return moveTo(x, y);
    path.lineTo(x, y);
  }

  void quadraticCurveTo(double cpx, double cpy, double x, double y) {
    if (!_has) moveTo(cpx, cpy);
    path.quadraticBezierTo(cpx, cpy, x, y);
  }

  void closePath() {
    if (!_has) return;
    path.close();
  }

  void rect(double x, double y, double w, double h) {
    path.addRect(Rect.fromLTWH(x, y, w, h));
    _has = true;
  }

  /// `roundRect(x, y, w, h, r)` with one radius.
  void roundRect(double x, double y, double w, double h, double r) {
    final rr = r.abs();
    path.addRRect(RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(rr)));
    _has = true;
  }

  /// `roundRect(x, y, w, h, [tl, tr, br, bl])`.
  void roundRect4(
    double x,
    double y,
    double w,
    double h,
    double tl,
    double tr,
    double br,
    double bl,
  ) {
    path.addRRect(
      RRect.fromLTRBAndCorners(
        x,
        y,
        x + w,
        y + h,
        topLeft: Radius.circular(tl),
        topRight: Radius.circular(tr),
        bottomRight: Radius.circular(br),
        bottomLeft: Radius.circular(bl),
      ),
    );
    _has = true;
  }

  static double _sweep(double a0, double a1, bool ccw) {
    if (!ccw) {
      final d = a1 - a0;
      if (d >= kTau) return kTau;
      if (d == 0) return 0;
      final m = modD(d, kTau);
      return m == 0 ? kTau : m;
    }
    final d = a0 - a1;
    if (d >= kTau) return -kTau;
    if (d == 0) return 0;
    final m = modD(d, kTau);
    return -(m == 0 ? kTau : m);
  }

  /// `arc(x, y, r, a0, a1, ccw)`.
  void arc(double x, double y, double r, double a0, double a1,
      [bool ccw = false]) {
    ellipse(x, y, r, r, 0, a0, a1, ccw);
  }

  /// `ellipse(x, y, rx, ry, rot, a0, a1, ccw)`.
  void ellipse(
    double x,
    double y,
    double rx,
    double ry,
    double rot,
    double a0,
    double a1, [
    bool ccw = false,
  ]) {
    final sweep = _sweep(a0, a1, ccw);
    if (rot == 0 && sweep.abs() >= kTau && !_has) {
      path.addOval(Rect.fromLTRB(x - rx, y - ry, x + rx, y + ry));
      _has = true;
      return;
    }
    if (rot == 0) {
      final r = Rect.fromLTRB(x - rx, y - ry, x + rx, y + ry);
      if (sweep.abs() >= kTau) {
        // Two halves: a single 360° arcTo degenerates.
        path.arcTo(r, a0, sweep / 2, !_has);
        path.arcTo(r, a0 + sweep / 2, sweep / 2, false);
      } else {
        path.arcTo(r, a0, sweep, !_has);
      }
      _has = true;
    } else {
      // A rotated ellipse: sampled (only small leaves use one).
      final n = math.max(8, (sweep.abs() / kTau * 48).ceil());
      final cr = math.cos(rot), sr = math.sin(rot);
      for (var i = 0; i <= n; i++) {
        final a = a0 + sweep * i / n;
        final ex = rx * math.cos(a), ey = ry * math.sin(a);
        final px = x + cr * ex - sr * ey, py = y + sr * ex + cr * ey;
        if (i == 0) {
          _has ? lineTo(px, py) : moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
    }
  }

  // ------------------------------------------------------------ painting
  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  Color _alpha(Color c) =>
      globalAlpha >= 1 ? c : c.withValues(alpha: c.a * clampD(globalAlpha, 0, 1));

  Paint get fillPaint {
    final s = fillShader;
    _fill
      ..shader = s
      ..color = s == null
          ? _alpha(_fillColor)
          : Color.fromRGBO(0, 0, 0, clampD(globalAlpha, 0, 1));
    return _fill;
  }

  Paint get strokePaint {
    final s = strokeShader;
    _stroke
      ..shader = s
      ..color = s == null
          ? _alpha(_strokeColor)
          : Color.fromRGBO(0, 0, 0, clampD(globalAlpha, 0, 1))
      ..strokeWidth = lineWidth
      ..strokeCap = lineCap
      ..strokeJoin = lineJoin;
    return _stroke;
  }

  /// `fill()` (non-zero), or `fill('evenodd')`.
  void fill({bool evenOdd = false}) {
    if (globalAlpha <= 0) return;
    path.fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    canvas.drawPath(path, fillPaint);
    path.fillType = PathFillType.nonZero;
  }

  void stroke() {
    if (globalAlpha <= 0 || lineWidth <= 0) return;
    final dash = lineDash;
    if (dash == null || dash.isEmpty) {
      canvas.drawPath(path, strokePaint);
      return;
    }
    canvas.drawPath(_dashed(path, dash, lineDashOffset), strokePaint);
  }

  /// `clip()` with the current path.
  void clip() => canvas.clipPath(path);

  void clipRect(double x, double y, double w, double h) =>
      canvas.clipRect(Rect.fromLTWH(x, y, w, h));

  void fillRect(double x, double y, double w, double h) {
    if (globalAlpha <= 0 || w == 0 || h == 0) return;
    canvas.drawRect(_rect(x, y, w, h), fillPaint);
  }

  void strokeRect(double x, double y, double w, double h) {
    if (globalAlpha <= 0) return;
    canvas.drawRect(_rect(x, y, w, h), strokePaint);
  }

  static Rect _rect(double x, double y, double w, double h) =>
      Rect.fromLTRB(math.min(x, x + w), math.min(y, y + h), math.max(x, x + w),
          math.max(y, y + h));

  /// `circ(c, x, y, r)`: a filled circle.
  void circ(double x, double y, double r) {
    if (globalAlpha <= 0 || r <= 0) return;
    beginPath();
    canvas.drawCircle(Offset(x, y), r, fillPaint);
  }

  /// `createLinearGradient(x0, y0, x1, y1)` with `[offset, colour]` stops.
  Shader linearGradient(
    double x0,
    double y0,
    double x1,
    double y1,
    List<Color> colors,
    List<double> stops,
  ) =>
      Gradient.linear(Offset(x0, y0), Offset(x1, y1), colors, stops);

  /// `createRadialGradient(x, y, 0, x, y, r)`.
  Shader radialGradient(
    double x,
    double y,
    double r,
    List<Color> colors,
    List<double> stops,
  ) =>
      Gradient.radial(Offset(x, y), r, colors, stops);

  static Path _dashed(Path src, List<double> dash, double offset) {
    final out = Path();
    final total = dash.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return src;
    for (final m in src.computeMetrics()) {
      var d = -modD(offset, total);
      var i = 0;
      while (d < m.length) {
        final len = dash[i % dash.length];
        if (i.isEven) {
          final a = math.max(0.0, d), b = math.min(m.length, d + len);
          if (b > a) out.addPath(m.extractPath(a, b), Offset.zero);
        }
        d += len;
        i++;
      }
    }
    return out;
  }
}

class _Strip {
  _Strip(this.pic, this.off0, this.yTop, this.xl, this.xr);
  final Picture pic;
  final double off0, yTop, xl, xr;
}

class _Style {
  Color fillStyle = const Color(0xFF000000);
  Shader? fillShader;
  Color strokeStyle = const Color(0xFF000000);
  Shader? strokeShader;
  double lineWidth = 1;
  StrokeCap lineCap = StrokeCap.butt;
  StrokeJoin lineJoin = StrokeJoin.miter;
  double globalAlpha = 1;
  List<double>? lineDash;
  double lineDashOffset = 0;

  void copyFrom(Ctx c) {
    fillStyle = c.fillStyle;
    fillShader = c.fillShader;
    strokeStyle = c.strokeStyle;
    strokeShader = c.strokeShader;
    lineWidth = c.lineWidth;
    lineCap = c.lineCap;
    lineJoin = c.lineJoin;
    globalAlpha = c.globalAlpha;
    lineDash = c.lineDash;
    lineDashOffset = c.lineDashOffset;
  }

  void copyTo(Ctx c) {
    c._fillColor = fillStyle;
    c.fillShader = fillShader;
    c._strokeColor = strokeStyle;
    c.strokeShader = strokeShader;
    c.lineWidth = lineWidth;
    c.lineCap = lineCap;
    c.lineJoin = lineJoin;
    c.globalAlpha = globalAlpha;
    c.lineDash = lineDash;
    c.lineDashOffset = lineDashOffset;
  }
}
