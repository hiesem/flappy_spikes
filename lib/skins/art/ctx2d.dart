import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'art_paint.dart';

/// PRD-2.3 §19.4: a tiny Canvas2D-style facade over `dart:ui` [Canvas], so
/// the 60 new skin items can be ported **1:1** from
/// `design/skins_v23/parts/*.js` (same calls, same numbers, same order).
///
/// It covers exactly the subset of the HTML canvas API those files use:
/// fill / stroke styles (colours and cached gradients), `lineWidth`,
/// `lineCap`, `lineJoin`, `globalAlpha`, `shadowColor` / `shadowBlur`,
/// line dashes, `save` / `restore`, transforms, the path builder (`moveTo`,
/// `lineTo`, `quadraticCurveTo`, `bezierCurveTo`, `arc`, `ellipse`, `rect`,
/// `roundRect`, `closePath`), `fill`, `stroke`, `clip` and `fillRect`, plus
/// the shared `skin_art.js` helpers (`circ`, `star`, `poly`, `oct`, `rr`).
///
/// Canvas semantics kept on purpose:
/// * `lineTo` / curves on an empty path start the sub-path (no stray line
///   from the origin), `arc` / `ellipse` join the current point with a line;
/// * angles follow the canvas rules (clockwise sweep `a1 - a0` taken modulo
///   a full turn, a full circle when the difference reaches 2π);
/// * `shadowBlur` is in **screen** units like the canvas (not scaled by the
///   transform): the blur sigma is `shadowBlur / 2` divided by the current
///   transform scale;
/// * `save` / `restore` keep the drawing state (styles, alpha, shadow, dash)
///   but never the current path.
///
/// Performance (§19.4): one shared instance, one reused [Paint], the current
/// path and every `poly` / `oct` / [newPath] come from a pool that is reset
/// per painter call (no Path allocation in steady state), and gradients are
/// built once and cached by key ([linearGradient] / [radialGradient]).
final class Ctx2D {
  Ctx2D._();

  static final Ctx2D _shared = Ctx2D._();

  /// Runs [draw] against [canvas] with a fresh drawing state, restoring the
  /// canvas to its save count afterwards (an unbalanced port can never leak
  /// a clip or a transform into the next painter).
  static void run(Canvas canvas, void Function(Ctx2D x) draw) {
    final x = _shared;
    final prevCanvas = x._canvas;
    final prevPool = x._poolNext;
    final nested = prevCanvas != null;
    final saved = nested ? x._snapshot() : null;
    x._canvas = canvas;
    if (!nested) x._poolNext = 0;
    x._reset();
    if (nested) x._depth = saved!.depth;
    final count = canvas.getSaveCount();
    try {
      draw(x);
    } finally {
      canvas.restoreToCount(count);
      x._canvas = prevCanvas;
      if (nested) {
        x._restoreState(saved!);
      } else {
        x._poolNext = prevPool;
      }
    }
  }

  Canvas? _canvas;
  Canvas get canvas => _canvas!;

  // ---------------------------------------------------------------- state
  Object fillStyle = const Color(0xFF000000);
  Object strokeStyle = const Color(0xFF000000);
  double lineWidth = 1;
  StrokeCap lineCap = StrokeCap.butt;
  StrokeJoin lineJoin = StrokeJoin.miter;
  double globalAlpha = 1;
  Color shadowColor = const Color(0x00000000);
  double shadowBlur = 0;
  List<double>? _dash;
  double lineDashOffset = 0;

  final List<_State> _stack = [];
  int _depth = 0;

  void _reset() {
    fillStyle = const Color(0xFF000000);
    strokeStyle = const Color(0xFF000000);
    lineWidth = 1;
    lineCap = StrokeCap.butt;
    lineJoin = StrokeJoin.miter;
    globalAlpha = 1;
    shadowColor = const Color(0x00000000);
    shadowBlur = 0;
    _dash = null;
    lineDashOffset = 0;
    _depth = 0;
    _path = _take();
    _hasPoint = false;
  }

  _State _snapshot() => _State()
    ..copyFrom(this)
    ..path = _path
    ..hasPoint = _hasPoint
    ..depth = _depth;

  void _restoreState(_State s) {
    s.applyTo(this);
    _path = s.path!;
    _hasPoint = s.hasPoint;
    _depth = s.depth;
  }

  /// `ctx.setLineDash(pattern)` (an odd-length pattern repeats twice, as on
  /// the canvas; an empty list clears it).
  void setLineDash(List<double> pattern) {
    if (pattern.isEmpty) {
      _dash = null;
    } else {
      _dash = pattern.length.isOdd ? [...pattern, ...pattern] : pattern;
    }
  }

  void save() {
    canvas.save();
    if (_stack.length <= _depth) _stack.add(_State());
    _stack[_depth++].copyFrom(this);
  }

  void restore() {
    if (_depth == 0) return;
    canvas.restore();
    _stack[--_depth].applyTo(this);
  }

  void translate(double x, double y) => canvas.translate(x, y);
  void rotate(double a) => canvas.rotate(a);
  void scale(double sx, double sy) => canvas.scale(sx, sy);

  // ---------------------------------------------------------- path pool
  final List<Path> _pool = [];
  int _poolNext = 0;

  Path _take() {
    if (_poolNext == _pool.length) _pool.add(Path());
    return _pool[_poolNext++]..reset();
  }

  /// `new Path2D()`: an empty pooled path (valid until the painter returns).
  Path newPath() => _take();

  late Path _path;
  bool _hasPoint = false;

  /// The current path (what `fill()` / `stroke()` / `clip()` use).
  Path get path => _path;

  void beginPath() {
    _path = _take();
    _hasPoint = false;
  }

  void moveTo(double x, double y) {
    _path.moveTo(x, y);
    _hasPoint = true;
  }

  void lineTo(double x, double y) {
    if (_hasPoint) {
      _path.lineTo(x, y);
    } else {
      moveTo(x, y);
    }
  }

  void quadraticCurveTo(double cx, double cy, double x, double y) {
    if (!_hasPoint) moveTo(cx, cy);
    _path.quadraticBezierTo(cx, cy, x, y);
  }

  void bezierCurveTo(
    double c1x,
    double c1y,
    double c2x,
    double c2y,
    double x,
    double y,
  ) {
    if (!_hasPoint) moveTo(c1x, c1y);
    _path.cubicTo(c1x, c1y, c2x, c2y, x, y);
  }

  void closePath() {
    if (_hasPoint) _path.close();
  }

  void rect(double x, double y, double w, double h) {
    _path.addRect(Rect.fromLTWH(x, y, w, h));
    _path.moveTo(x, y);
    _hasPoint = true;
  }

  /// `ctx.roundRect(x, y, w, h, r)`: [r] is one radius or the canvas'
  /// four-value list `[topLeft, topRight, bottomRight, bottomLeft]`.
  void roundRect(double x, double y, double w, double h, Object r) {
    final Radius tl, tr, br, bl;
    if (r is List<num>) {
      tl = Radius.circular(r[0].toDouble());
      tr = Radius.circular(r[1].toDouble());
      br = Radius.circular(r[2].toDouble());
      bl = Radius.circular(r[3].toDouble());
    } else {
      tl = tr = br = bl = Radius.circular((r as num).toDouble());
    }
    _path.addRRect(
      RRect.fromLTRBAndCorners(
        math.min(x, x + w),
        math.min(y, y + h),
        math.max(x, x + w),
        math.max(y, y + h),
        topLeft: tl,
        topRight: tr,
        bottomRight: br,
        bottomLeft: bl,
      ),
    );
    _path.moveTo(x, y);
    _hasPoint = true;
  }

  /// `rr(ctx, ...)` of skin_art.js: begin a path holding one round rect.
  void rr(double x, double y, double w, double h, Object r) {
    beginPath();
    roundRect(x, y, w, h, r);
  }

  void arc(
    double x,
    double y,
    double r,
    double a0,
    double a1, [
    bool ccw = false,
  ]) => ellipse(x, y, r, r, 0, a0, a1, ccw);

  static double _sweep(double a0, double a1, bool ccw) {
    const t = ArtPaint.tau;
    if (!ccw) {
      final d = a1 - a0;
      if (d >= t) return t;
      final m = d % t;
      return m < 0 ? m + t : m;
    }
    final d = a0 - a1;
    if (d >= t) return -t;
    final m = d % t;
    return -(m < 0 ? m + t : m);
  }

  final Path _tmp = Path();

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
    if (rx < 0 || ry < 0) return;
    final sweep = _sweep(a0, a1, ccw);
    if (rot == 0) {
      _arcInto(
        _path,
        Rect.fromLTRB(x - rx, y - ry, x + rx, y + ry),
        a0,
        sweep,
        !_hasPoint,
      );
    } else {
      _tmp.reset();
      _arcInto(_tmp, Rect.fromLTRB(-rx, -ry, rx, ry), a0, sweep, true);
      final c = math.cos(rot), s = math.sin(rot);
      final m = Float64List(16)
        ..[0] = c
        ..[1] = s
        ..[4] = -s
        ..[5] = c
        ..[10] = 1
        ..[12] = x
        ..[13] = y
        ..[15] = 1;
      final t = _tmp.transform(m);
      if (_hasPoint) {
        _path.extendWithPath(t, Offset.zero);
      } else {
        _path.addPath(t, Offset.zero);
      }
    }
    _hasPoint = true;
  }

  static void _arcInto(
    Path p,
    Rect rect,
    double start,
    double sweep,
    bool move,
  ) {
    if (sweep.abs() >= ArtPaint.tau - 1e-9) {
      p.arcTo(rect, start, sweep / 2, move);
      p.arcTo(rect, start + sweep / 2, sweep / 2, false);
    } else {
      p.arcTo(rect, start, sweep, move);
    }
  }

  // ---------------------------------------------------------- drawing
  final Paint _paint = Paint();
  final Paint _shadow = Paint();

  double _scaleNow() {
    final m = canvas.getTransform();
    final det = (m[0] * m[5] - m[1] * m[4]).abs();
    return det > 0 ? math.sqrt(det) : 1;
  }

  /// Configures [_paint] for [style] at the current alpha; returns false
  /// when nothing would show.
  bool _prep(Object style, bool stroke) {
    final p = _paint
      ..maskFilter = null
      ..blendMode = BlendMode.srcOver
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill;
    if (stroke) {
      p
        ..strokeWidth = lineWidth
        ..strokeCap = lineCap
        ..strokeJoin = lineJoin
        ..strokeMiterLimit = 10;
    }
    final a = globalAlpha.clamp(0.0, 1.0);
    if (a <= 0) return false;
    if (style is Color) {
      p
        ..shader = null
        ..color = style.withValues(alpha: style.a * a);
      return style.a > 0;
    }
    final g = style as CanvasGrad;
    p
      ..shader = g.shader
      ..color = Color.fromRGBO(0, 0, 0, a);
    return true;
  }

  void _withShadow(Object style, void Function(Paint) draw) {
    if (shadowBlur <= 0 || shadowColor.a == 0) return;
    final sa =
        shadowColor.a *
        globalAlpha.clamp(0.0, 1.0) *
        (style is Color ? style.a : 1);
    if (sa <= 0) return;
    final sp = _shadow
      ..shader = null
      ..style = _paint.style
      ..strokeWidth = _paint.strokeWidth
      ..strokeCap = _paint.strokeCap
      ..strokeJoin = _paint.strokeJoin
      ..strokeMiterLimit = 10
      ..color = shadowColor.withValues(alpha: sa)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        shadowBlur / 2 / _scaleNow(),
      );
    draw(sp);
  }

  /// `ctx.fill()` / `ctx.fill(path)` / `ctx.fill(path, 'evenodd')`.
  void fill([Path? p, bool evenOdd = false]) {
    final path = p ?? _path;
    if (!_prep(fillStyle, false)) return;
    final type = path.fillType;
    if (evenOdd) path.fillType = PathFillType.evenOdd;
    _withShadow(fillStyle, (sp) => canvas.drawPath(path, sp));
    canvas.drawPath(path, _paint);
    if (evenOdd) path.fillType = type;
  }

  /// `ctx.stroke()` / `ctx.stroke(path)` (honours the line dash).
  void stroke([Path? p]) {
    var path = p ?? _path;
    if (lineWidth <= 0 || !_prep(strokeStyle, true)) return;
    final dash = _dash;
    if (dash != null) path = ArtPaint.dashed(path, dash, lineDashOffset);
    _withShadow(strokeStyle, (sp) => canvas.drawPath(path, sp));
    canvas.drawPath(path, _paint);
  }

  /// Performance helper (§19.4 budget, not a canvas call): runs [draw] —
  /// strokes / fills drawn WITHOUT `shadowBlur` — into one layer that is
  /// blurred once with the canvas shadow sigma for [blur] (screen units, as
  /// `shadowBlur`), limited to [bounds]. Equivalent to giving every one of
  /// those draws `shadowColor = its own colour` and `shadowBlur = blur`, but
  /// costs one blur instead of one per draw. Callers then draw the crisp
  /// shapes on top.
  void glowLayer(double blur, Rect bounds, void Function() draw) {
    final sigma = blur / 2 / _scaleNow();
    final savedBlur = shadowBlur;
    shadowBlur = 0;
    canvas.saveLayer(
      bounds.inflate(sigma * 3),
      Paint()..imageFilter = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
    try {
      draw();
    } finally {
      canvas.restore();
      shadowBlur = savedBlur;
    }
  }

  /// `ctx.clip()` / `ctx.clip(path)`.
  void clip([Path? p]) => canvas.clipPath(p ?? _path);

  /// `ctx.fillRect(x, y, w, h)` (negative sizes allowed, as on the canvas).
  void fillRect(double x, double y, double w, double h) {
    if (w == 0 || h == 0) return;
    final r = Rect.fromLTRB(
      math.min(x, x + w),
      math.min(y, y + h),
      math.max(x, x + w),
      math.max(y, y + h),
    );
    if (!_prep(fillStyle, false)) return;
    _withShadow(fillStyle, (sp) => canvas.drawRect(r, sp));
    canvas.drawRect(r, _paint);
  }

  // ------------------------------------------------- skin_art.js helpers
  /// `poly([[x0,y0],[x1,y1],...])` from flat coordinates (pooled path).
  Path poly(List<double> pts) {
    final p = _take()..moveTo(pts[0], pts[1]);
    for (var i = 2; i < pts.length; i += 2) {
      p.lineTo(pts[i], pts[i + 1]);
    }
    return p..close();
  }

  /// `oct(x, y, w, h, c)` (pooled path).
  Path oct(double x, double y, double w, double h, double c) => _take()
    ..moveTo(x + c, y)
    ..lineTo(x + w - c, y)
    ..lineTo(x + w, y + c)
    ..lineTo(x + w, y + h - c)
    ..lineTo(x + w - c, y + h)
    ..lineTo(x + c, y + h)
    ..lineTo(x, y + h - c)
    ..lineTo(x, y + c)
    ..close();

  /// `fillP(ctx, c, p)` / the parts' `fp`.
  void fp(Object c, Path p) {
    fillStyle = c;
    fill(p);
  }

  /// `circ(ctx, x, y, r, c)`: sets the fill style and fills a circle.
  void circ(double x, double y, double r, Object c) {
    fillStyle = c;
    beginPath();
    arc(x, y, r, 0, ArtPaint.tau);
    fill();
  }

  /// `star(ctx, x, y, r, c, rot)` of skin_art.js (8 points, inner .38).
  void star(double x, double y, double r, Object c, [double rot = 0]) {
    save();
    translate(x, y);
    rotate(rot);
    fillStyle = c;
    beginPath();
    for (var i = 0; i < 8; i++) {
      final q = i.isOdd ? r * .38 : r, a = i * math.pi / 4;
      lineTo(math.cos(a) * q, math.sin(a) * q);
    }
    fill();
    restore();
  }

  // ------------------------------------------------------------ gradients
  static final Map<Object, CanvasGrad> _grads = {};

  /// Cap of the gradient cache; keys are expected to be few (static
  /// geometry per shape / ring size, quantised animation inputs).
  static const int gradCacheCap = 256;

  static CanvasGrad _cached(Object key, CanvasGrad Function() make) {
    final hit = _grads[key];
    if (hit != null) return hit;
    if (_grads.length >= gradCacheCap) _grads.remove(_grads.keys.first);
    return _grads[key] = make();
  }

  /// Cached `createLinearGradient(x0, y0, x1, y1)` + its colour [stops]
  /// (offset, colour pairs). [key] must identify every input.
  static CanvasGrad linearGradient(
    Object key,
    double x0,
    double y0,
    double x1,
    double y1,
    List<(double, Color)> stops,
  ) => _cached(
    key,
    () => CanvasGrad._(
      Gradient.linear(
        Offset(x0, y0),
        Offset(x1, y1),
        [for (final s in stops) s.$2],
        [for (final s in stops) s.$1],
      ),
    ),
  );

  /// Cached `createRadialGradient(x0, y0, r0, x1, y1, r1)` + [stops].
  static CanvasGrad radialGradient(
    Object key,
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
    List<(double, Color)> stops,
  ) => _cached(
    key,
    () => CanvasGrad._(
      Gradient.radial(
        Offset(x1, y1),
        r1,
        [for (final s in stops) s.$2],
        [for (final s in stops) s.$1],
        TileMode.clamp,
        null,
        Offset(x0, y0),
        r0,
      ),
    ),
  );

  /// Number of cached gradients (tests: the cache stays bounded).
  static int get cachedGradients => _grads.length;
}

/// A cached canvas gradient usable as a fill / stroke style.
final class CanvasGrad {
  CanvasGrad._(this.shader);
  final Shader shader;
}

final class _State {
  Object fillStyle = const Color(0xFF000000);
  Object strokeStyle = const Color(0xFF000000);
  double lineWidth = 1;
  StrokeCap lineCap = StrokeCap.butt;
  StrokeJoin lineJoin = StrokeJoin.miter;
  double globalAlpha = 1;
  Color shadowColor = const Color(0x00000000);
  double shadowBlur = 0;
  List<double>? dash;
  double dashOffset = 0;
  Path? path;
  bool hasPoint = false;
  int depth = 0;

  void copyFrom(Ctx2D x) {
    fillStyle = x.fillStyle;
    strokeStyle = x.strokeStyle;
    lineWidth = x.lineWidth;
    lineCap = x.lineCap;
    lineJoin = x.lineJoin;
    globalAlpha = x.globalAlpha;
    shadowColor = x.shadowColor;
    shadowBlur = x.shadowBlur;
    dash = x._dash;
    dashOffset = x.lineDashOffset;
  }

  void applyTo(Ctx2D x) {
    x.fillStyle = fillStyle;
    x.strokeStyle = strokeStyle;
    x.lineWidth = lineWidth;
    x.lineCap = lineCap;
    x.lineJoin = lineJoin;
    x.globalAlpha = globalAlpha;
    x.shadowColor = shadowColor;
    x.shadowBlur = shadowBlur;
    x._dash = dash;
    x.lineDashOffset = dashOffset;
  }
}

/// `rgba(r, g, b, a)` as a [Color].
Color rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a);

/// `lerpC(a, b, u)` of skin_art.js: channel-wise mix truncated to integers
/// like the canvas' `rgb()` string.
Color lerpC(Color a, Color b, double u) {
  int ch(double x, double y) {
    final p = (x * 255).round(), q = (y * 255).round();
    return (p + (q - p) * u).truncate().clamp(0, 255);
  }

  return Color.fromARGB(255, ch(a.r, b.r), ch(a.g, b.g), ch(a.b, b.b));
}
