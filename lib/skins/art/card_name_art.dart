import 'dart:math' as math;
// region P26-F9f
import 'dart:typed_data';
// endregion

import 'package:flutter/widgets.dart';

import 'art_paint.dart';
import 'look_painter.dart';
import '../look.dart';

/// The single name-style master for cards, shop tiles and leaderboard rows.
/// [t] is elapsed game time in seconds: retaining it freezes every effect.
/// No ticker, wall clock or random state is owned by this art.
abstract final class CardNameArt {
  // region P26-F9f
  /// Prepare the run's fitted glyphs before its first rendered frame.
  static void prepare(
    String id,
    String text, {
    required double fontSize,
    required double maxWidth,
  }) {
    _NameLayout.obtain(id, text, fontSize, maxWidth);
  }

  /// Counts actual TextPainter layouts, including fitting and glyph outlines.
  @visibleForTesting
  static int get debugLayoutCount => _NameLayout.layouts;

  @visibleForTesting
  static void debugClearLayoutCache() => _NameLayout.clear();
  // endregion

  static const ids = <String>[
    'n_tangerine',
    'n_ocean',
    'n_grass',
    'n_cherry',
    'n_grape',
    'n_midnight',
    'n_bubble',
    'n_candy',
    'n_comic',
    'n_sunset',
    'n_spiky',
    'n_rainbow',
    'n_gold',
    'n_flappy',
    'n_glitch',
    'n_fire',
    'n_stardust',
    'n_sky',
    'n_thunder',
    'n_marquee',
  ];

  /// Draw centred at [center], or with its fitted left edge at [center] when
  /// [start] is true. [maxWidth] fits the text, excluding ornamental overflow
  /// (reserve .6 × fontSize horizontally and 1.3 × above the centre).
  /// Unknown/empty ids draw the ordinary plum name. Nothing is clipped here.
  static void paint(
    Canvas canvas,
    String id,
    String text, {
    required double t,
    Offset center = Offset.zero,
    double fontSize = 18,
    double maxWidth = double.infinity,
    bool start = false,
    // region P26-F9f
    /// Run hosts reuse glyph layouts; preview/reference hosts retain native
    /// coloured text rasterization. Both use the same style/animation drawing.
    bool cacheLayout = false,
    // endregion
  }) {
    // region P26-F9f
    final art = _Name(id, text, fontSize, maxWidth, t, cached: cacheLayout);
    // endregion
    canvas.save();
    canvas.translate(start ? center.dx + art.w / 2 : center.dx, center.dy);
    art.back(canvas);
    art.ink(canvas);
    art.front(canvas);
    canvas.restore();
  }
}

/// Widget adapter of [CardNameArt]. Gradient ink uses ShaderMask; Flame uses
/// the same gradient directly on TextPainter's foreground paint.
/// The caller rebuilds with its game-clock value; this widget never ticks.
class CardNameStyle extends StatelessWidget {
  const CardNameStyle({
    super.key,
    required this.id,
    required this.text,
    required this.t,
    this.fontSize = 18,
    this.maxWidth = double.infinity,
  });

  final String id, text;
  final double t, fontSize, maxWidth;

  @override
  Widget build(BuildContext context) {
    final art = _Name(id, text, fontSize, maxWidth, t);
    // Whole, even extents keep canvas and widget glyph origins on pixels.
    final size = Size(
      ((art.w + art.f * 1.2) / 2).ceil() * 2.0,
      (art.f * 2.8 / 2).ceil() * 2.0,
    );
    Widget ink = CustomPaint(size: size, painter: _Part(art, 1));
    if (art.gradient != null) {
      ink = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            art.gradient!.createShader(art.rect.shift(bounds.center)),
        child: ink,
      );
    }
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(size: size, painter: _Part(art, 0)),
          ink,
          CustomPaint(size: size, painter: _Part(art, 2)),
        ],
      ),
    );
  }
}

class _Part extends CustomPainter {
  _Part(this.art, this.part);
  final _Name art;
  final int part;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    switch (part) {
      case 0:
        art.back(canvas);
      case 1:
        art.ink(canvas, mask: true);
      case 2:
        art.front(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Part oldDelegate) =>
      part != oldDelegate.part || !art.same(oldDelegate.art);
}

const _plum = Color(0xFF7A0044), _pink = Color(0xFFEC008C);
const _white = Color(0xFFFFFFFF), _gold = Color(0xFFFFC233);
Color _c(int rgb) => Color(0xFF000000 | rgb);

// region P26-F9f
TextPainter _layoutName(
  String text,
  double size,
  Color color, {
  Paint? foreground,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Fredoka',
        fontWeight: FontWeight.w600,
        fontSize: size,
        height: 1,
        color: foreground == null ? color : null,
        foreground: foreground,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  _NameLayout.layouts++;
  return painter;
}

/// Bounded LRU of time-independent metrics and monochrome glyph layouts.
/// Painters remain owned by their layout so a widget retaining an evicted
/// layout can still paint it; native paragraphs are released with that layout.
class _NameLayout {
  _NameLayout(
    this.id,
    this.text,
    double fontSize,
    double maxWidth, {
    bool prewarm = true,
  }) {
    f = fontSize;
    final natural = _layoutName(text, f, _white);
    if (natural.width > maxWidth && natural.width > 0) {
      f *= math.max(0, maxWidth) / natural.width;
    }
    natural.dispose();
    if (!prewarm) {
      final fitted = _layoutName(text, f, _white);
      w = fitted.width;
      fitted.dispose();
      return;
    }
    w = _label(text, 0).width;
    final glyphs = ['n_flappy', 'n_candy', 'n_rainbow'].contains(id);
    final widths = switch (id) {
      'n_bubble' => [.24],
      'n_gold' => [.1],
      'n_rainbow' => [.06],
      'n_flappy' => [.05],
      'n_fire' => [.09],
      'n_stardust' => [.07],
      'n_sky' => [.15],
      'n_thunder' => [.32, .12],
      'n_marquee' => [.06],
      _ => <double>[],
    };
    for (final value in [text, if (glyphs) ...text.characters]) {
      _label(value, 0);
      for (final width in widths) {
        _label(value, f * width);
      }
    }
  }

  static final cache = <(String, String, double, double), _NameLayout>{};
  static int layouts = 0;
  static int _cost = 0;
  static void clear() {
    cache.clear();
    _cost = 0;
  }

  int get cost => _labels.values.fold(
    0,
    (total, label) => total + label.painters.length + label.direct.length,
  );

  static _NameLayout obtain(String id, String text, double size, double room) {
    final key = (id, text, size, room);
    final hit = cache.remove(key);
    final layout = hit ?? _NameLayout(id, text, size, room);
    cache[key] = layout;
    if (hit == null) _cost += layout.cost;
    while ((cache.length > 128 || _cost > 8192) && cache.length > 1) {
      _cost -= cache.remove(cache.keys.first)!.cost;
    }
    return layout;
  }

  final String id, text;
  late final double w;
  late double f;
  final _labels = <(String, double), _NameLabel>{};
  static final _strokeWidth = Float32List(1);

  _NameLabel _label(String value, double stroke) {
    // Paint stores stroke widths as float32. Use the identical cache key for
    // constructor-time outlines and the Paint values supplied during drawing.
    _strokeWidth[0] = stroke;
    final width = _strokeWidth[0];
    return _labels.putIfAbsent((value, width), () {
      TextPainter make(Color source) => _layoutName(
        value,
        f,
        source,
        foreground: stroke == 0
            ? null
            : (Paint()
                ..color = source
                ..style = PaintingStyle.stroke
                ..strokeWidth = stroke
                ..strokeJoin = id == 'n_flappy'
                    ? StrokeJoin.miter
                    : StrokeJoin.round),
      );

      // Skia uses eight luminance buckets for glyph antialiasing. Keep the
      // masks as well as exact static-colour paragraphs, so tinting animated
      // ink does not turn every dark glyph into a heavier white glyph mask.
      // Every variant retains the same fitted font and glyph advances.
      final painters = [
        for (var i = 0; i < 8; i++)
          make(
            Color.fromARGB(
              255,
              (i * 255 / 7).round(),
              (i * 255 / 7).round(),
              (i * 255 / 7).round(),
            ),
          ),
      ];
      final colors = switch (id) {
        'n_tangerine' => [_c(0xF06A00)],
        'n_ocean' => [_c(0x1565C0)],
        'n_grass' => [_c(0x2E8B2E)],
        'n_cherry' => [_c(0xD32F2F)],
        'n_grape' => [_c(0x7B1FA2)],
        'n_midnight' => [_c(0x1A237E)],
        'n_bubble' => [_pink, _white],
        'n_comic' => [_c(0xFFB529), _plum],
        'n_gold' => [_c(0x8A5A00), _white],
        'n_rainbow' => [const Color(0x2E000000)],
        'n_flappy' => [_plum, _pink],
        'n_candy' => [_pink, _c(0x0097A7)],
        'n_glitch' => [_plum, _c(0x00E5FF), _c(0xFF4FB7)],
        'n_fire' => [_c(0x6D1B00), _white],
        'n_stardust' => [_c(0x170838), _white],
        'n_sky' => [_c(0x9FD8F5).withValues(alpha: .6)],
        'n_thunder' => [_c(0x2A0845), _white, _c(0xB388FF)],
        'n_marquee' => [_c(0x2A0016), _white],
        _ => [_plum],
      };
      return _NameLabel(
        painters,
        {for (final color in colors) color.toARGB32(): make(color)},
        painters.first.width,
        painters.first.height,
        stroke,
      );
    });
  }
}

class _NameLabel {
  const _NameLabel(
    this.painters,
    this.direct,
    this.width,
    this.height,
    this.stroke,
  );
  final List<TextPainter> painters;
  final Map<int, TextPainter> direct;
  final double width, height, stroke;

  void paint(Canvas canvas, Offset at, Color color) {
    final exact = direct[color.toARGB32()];
    if (exact != null) {
      exact.paint(canvas, at);
      return;
    }
    canvas.saveLayer(
      Rect.fromLTWH(at.dx, at.dy, width, height).inflate(stroke + 2),
      Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    );
    final r = (color.r * 255).round(),
        g = (color.g * 255).round(),
        b = (color.b * 255).round();
    int canonical(int channel) => ((channel >> 5) * 255 / 7).round();
    final luma =
        (canonical(r) * 54 + canonical(g) * 183 + canonical(b) * 19) >> 8;
    painters[luma >> 5].paint(canvas, at);
    canvas.restore();
  }
}
// endregion

class _Name {
  // region P26-F9f
  _Name(
    this.id,
    this.text,
    double fontSize,
    double maxWidth,
    this.t, {
    this.cached = false,
  }) : _layout = cached
           ? _NameLayout.obtain(id, text, fontSize, maxWidth)
           : _NameLayout(id, text, fontSize, maxWidth, prewarm: false);
  final bool cached;
  final _NameLayout _layout;
  double get f => _layout.f;
  double get w => _layout.w;
  // endregion
  final String id, text;
  final double t;
  bool same(_Name other) =>
      id == other.id && text == other.text && t == other.t && f == other.f;
  Rect get rect => Rect.fromLTWH(-w / 2, -f / 2, w, f);
  double get flash {
    final c = t % 2.3;
    return c < .1
        ? 1
        : c < .17
        ? .2
        : c < .27
        ? .8
        : math.max(0, 1 - (c - .27) / .25) * .3;
  }

  // region P26-F9f
  void draw(
    Canvas c,
    Color color, {
    Offset offset = Offset.zero,
    Paint? foreground,
    String? value,
    double? x,
  }) {
    if (!cached) {
      final painter = _layoutName(
        value ?? text,
        f,
        color,
        foreground: foreground,
      );
      painter.paint(c, Offset(x ?? -w / 2, -painter.height / 2) + offset);
      painter.dispose();
      return;
    }
    final stroke = foreground?.style == PaintingStyle.stroke
        ? foreground!.strokeWidth
        : 0.0;
    final label = _layout._label(value ?? text, stroke);
    label.paint(
      c,
      Offset(x ?? -w / 2, -label.height / 2) + offset,
      foreground?.color ?? color,
    );
  }
  // endregion

  void edge(Canvas c, Color color, double width) => draw(
    c,
    color,
    foreground: Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = f * width
      ..strokeJoin = StrokeJoin.round,
  );

  LinearGradient? get gradient {
    List<Color>? colors;
    List<double>? stops;
    switch (id) {
      case 'n_sunset':
        colors = [_c(0xFF9800), _pink];
        stops = [.2, .85];
      case 'n_gold':
        final p = (t * .55) % 1.7 - .35;
        colors = [_c(0xE09A00), _gold, _c(0xFFF8D6), _gold, _c(0xE09A00)];
        stops = [
          0,
          (p - .12).clamp(0, 1),
          p.clamp(0, 1),
          (p + .12).clamp(0, 1),
          1,
        ];
      case 'n_fire':
        colors = [_c(0xFFD54F), _c(0xFF7A1A), _c(0xE53935)];
        stops = [.1, .55, 1];
      case 'n_stardust':
        colors = [_c(0x7C4DFF), _c(0x2A1260)];
      case 'n_sky':
        colors = [_c(0x81D4FA), _c(0x1E9BE0), _c(0x0D5FA0)];
        stops = [.05, .5, 1];
      case 'n_thunder':
        colors = [_white, _c(0xFFF176), _c(0xFFB300)];
        stops = [.1, .42, 1];
      case 'n_marquee':
        colors = [_c(0xFFF3C4), _gold, _c(0xE69500)];
        stops = [.1, .5, 1];
    }
    if (colors == null) return null;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: id == 'n_gold'
          ? const Alignment(1, -.3)
          : id == 'n_stardust'
          ? Alignment.bottomRight
          : Alignment.bottomLeft,
      colors: colors,
      stops: stops,
    );
  }

  void back(Canvas c) {
    if (f <= 0 || w <= 0) return;
    switch (id) {
      case 'n_bubble':
        edge(c, _pink, .24);
      case 'n_comic':
        draw(c, _c(0xFFB529), offset: Offset(f * .09, f * .09));
      case 'n_gold':
        edge(c, _c(0x8A5A00), .1);
      case 'n_rainbow':
        edge(c, const Color(0x2E000000), .06);
      case 'n_spiky':
        final n = math.max(3, (w / (f * .3)).round());
        for (var i = 0; i < n; i++) {
          final x = -w / 2 + i * w / n, b = w / n, y = f * .62;
          c.drawPath(
            ArtPaint.poly([
              Offset(x, y),
              Offset(x + b / 2, y - f * .24),
              Offset(x + b, y),
            ]),
            Paint()..color = _c(0x808080),
          );
          c.drawPath(
            ArtPaint.poly([
              Offset(x + b / 2, y - f * .24),
              Offset(x + b, y),
              Offset(x + b / 2, y),
            ]),
            Paint()..color = _c(0x6E6E6E),
          );
        }
      case 'n_flappy':
        glyphs(c, outline: true);
      case 'n_glitch':
        final j = t % 1.9 < .16;
        final dx = f * (j ? .1 + .06 * math.sin(t * 90) : .04);
        final dy = j ? f * .05 * math.sin(t * 70) : 0.0;
        draw(c, _c(0x00E5FF), offset: Offset(-dx, dy));
        draw(c, _c(0xFF4FB7), offset: Offset(dx, -dy));
      case 'n_fire':
        final n = math.max(3, (w / (f * .42)).round());
        for (var i = 0; i < n; i++) {
          final x = -w / 2 + (i + .5) * w / n,
              h = f * (.42 + .16 * math.sin(t * 11 + i * 1.9));
          final lean = math.sin(t * 7 + i) * f * .06;
          for (final inner in [false, true]) {
            final a = inner ? .45 : 1.0, b = inner ? .6 : 1.0, y = -f * .16;
            c.drawPath(
              ArtPaint.poly([
                Offset(x - f * .2 * a, y),
                Offset(x - f * .12 * a, y - h * .45 * b),
                Offset(x + lean * b, y - h * b),
                Offset(x + f * .12 * a, y - h * .45 * b),
                Offset(x + f * .2 * a, y),
              ]),
              Paint()
                ..color = inner
                    ? _c(0xFFE082)
                    : i.isOdd
                    ? _c(0xFF7A1A)
                    : _c(0xFFB529),
            );
          }
        }
        edge(c, _c(0x6D1B00), .09);
      case 'n_stardust':
        edge(c, _c(0x170838), .07);
      case 'n_sky':
        draw(c, _c(0x9FD8F5).withValues(alpha: .6));
        c.save();
        c.clipRect(_skyClip);
        edge(c, _white.withValues(alpha: _skyFade), .15);
        c.restore();
      case 'n_thunder':
        edge(
          c,
          (flash > .05 ? _white : _c(0xB388FF)).withValues(
            alpha: flash > .05 ? flash * .7 : .34 + .12 * math.sin(t * 9),
          ),
          .32,
        );
        edge(c, _c(0x2A0845), .12);
      case 'n_marquee':
        final box = Rect.fromLTWH(
          -w / 2 - f * .38,
          -f * .6,
          w + f * .76,
          f * 1.2,
        );
        c.drawRect(box, Paint()..color = _c(0x4A0029));
        c.drawRect(
          box.deflate(f * .06),
          Paint()
            ..color = _c(0x7A0044)
            ..style = PaintingStyle.stroke
            ..strokeWidth = f * .05,
        );
        final nx = math.max(3, (box.width / (f * .36)).round()),
            ny = math.max(2, (box.height / (f * .36)).round());
        final bulbs = <Offset>[
          for (var i = 0; i < nx; i++)
            Offset(box.left + (i + .5) * box.width / nx, box.top),
          for (var i = 0; i < ny; i++)
            Offset(box.right, box.top + (i + .5) * box.height / ny),
          for (var i = nx - 1; i >= 0; i--)
            Offset(box.left + (i + .5) * box.width / nx, box.bottom),
          for (var i = ny - 1; i >= 0; i--)
            Offset(box.left, box.top + (i + .5) * box.height / ny),
        ];
        for (var i = 0; i < bulbs.length; i++) {
          final on = (i + (t * 7).floor()) % 3 == 0;
          if (on) {
            c.drawCircle(
              bulbs[i],
              f * .147,
              Paint()..color = _c(0xFFB529).withValues(alpha: .45),
            );
          }
          c.drawCircle(
            bulbs[i],
            f * .07,
            Paint()..color = on ? _c(0xFFF8DC) : _c(0x9C6B00),
          );
        }
        edge(c, _c(0x2A0016), .06);
    }
  }

  double get _skyFade => 1 - ((t % 4.2 - 3.85) / .35).clamp(0, 1) * .55;

  Rect get _skyClip => Rect.fromLTWH(
    -w / 2 - f,
    -f * 1.2,
    (t % 4.2 / 1.3).clamp(0, 1) * (w + f * .6) + f * .7,
    f * 2.4,
  );

  void glyphs(Canvas c, {bool outline = false}) {
    var x = -w / 2;
    var i = 0;
    // Grapheme clusters preserve player names containing accents and emoji.
    for (final glyph in text.characters) {
      final hop = id == 'n_flappy'
          ? -math.pow(math.max(0, math.sin(t * 5 - i * .7)), 2) * f * .18
          : 0.0;
      final color = id == 'n_rainbow'
          ? HSLColor.fromAHSL(1, (i * 48 - t * 120) % 360, .85, .47).toColor()
          : id == 'n_candy' && i.isOdd
          ? _c(0x0097A7)
          : _pink;
      draw(
        c,
        color,
        value: glyph,
        x: x,
        offset: Offset(0, hop),
        foreground: outline
            ? (Paint()
                ..color = _plum
                ..style = PaintingStyle.stroke
                ..strokeWidth = f * .05)
            : null,
      );
      // region P26-F9f
      if (cached) {
        x += _layout._label(glyph, 0).width;
      } else {
        final painter = _layoutName(glyph, f, _white);
        x += painter.width;
        painter.dispose();
      }
      // endregion
      i++;
    }
  }

  void ink(Canvas c, {bool mask = false}) {
    if (f <= 0 || text.isEmpty) return;
    if (['n_flappy', 'n_candy', 'n_rainbow'].contains(id)) {
      glyphs(c);
      return;
    }
    const flat = {
      'n_tangerine': 0xF06A00,
      'n_ocean': 0x1565C0,
      'n_grass': 0x2E8B2E,
      'n_cherry': 0xD32F2F,
      'n_grape': 0x7B1FA2,
      'n_midnight': 0x1A237E,
      'n_bubble': 0xFFFFFF,
    };
    final g = gradient;
    c.save();
    if (id == 'n_sky') c.clipRect(_skyClip);
    if (g != null && !mask) c.saveLayer(rect.inflate(f), Paint());
    draw(
      c,
      flat.containsKey(id) ? _c(flat[id]!) : _plum,
      offset: id == 'n_spiky'
          ? Offset(0, -f * .06)
          : id == 'n_glitch' && t % 1.9 < .16
          ? Offset(f * .05, 0)
          : Offset.zero,
      foreground: g == null
          ? null
          : (Paint()
              ..color = _white.withValues(alpha: id == 'n_sky' ? _skyFade : 1)),
    );
    if (g != null && !mask) {
      c.drawRect(
        rect.inflate(f),
        Paint()
          ..shader = g.createShader(rect)
          ..blendMode = BlendMode.srcIn,
      );
      c.restore();
    }
    c.restore();
  }

  void line(Canvas c, List<Offset> points, Color color, double width) =>
      c.drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = f * width
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

  void front(Canvas c) {
    if (f <= 0 || w <= 0) return;
    if (id == 'n_glitch' && t % 1.9 < .16) {
      c.drawRect(
        Rect.fromLTWH(-w / 2 - f * .1, f * .02, w + f * .2, f * .1),
        Paint()..color = _white.withValues(alpha: .7),
      );
    }
    if (id == 'n_stardust') {
      // Text alpha is the clip for drifting dust, matching the SVG clipPath.
      c.saveLayer(rect.inflate(f), Paint());
      for (var i = 0; i < 16; i++) {
        final x =
            -w / 2 +
            (ArtPaint.hash(i.toDouble()) * w +
                    t * f * .5 * (.5 + ArtPaint.hash(i + 5))) %
                w;
        final y = -f * .38 + ArtPaint.hash(i + 11) * f * .76;
        c.drawRect(
          Rect.fromLTWH(x, y, f * .08, f * .08),
          Paint()
            ..color = (i % 3 == 0 ? _c(0xFFE082) : _white).withValues(
              alpha: .55 + .45 * math.sin(t * 4 + i),
            ),
        );
      }
      c.saveLayer(rect.inflate(f), Paint()..blendMode = BlendMode.dstIn);
      draw(c, _white);
      c.restore();
      c.restore();
      for (var i = 0; i < 3; i++) {
        final q = t * .7 + i / 3, k = q.floorToDouble();
        ArtPaint.star(
          c,
          -w / 2 + ArtPaint.hash(i * 7 + k * 3) * w,
          (ArtPaint.hash(i * 3 + k * 5) - .5) * f * 1.05,
          math.sin((q - k) * math.pi) * f * .17,
          i.isOdd ? _c(0xFFB529) : _c(0x9B30D9),
          t * 2,
        );
      }
    }
    if (id == 'n_sky') {
      final cycle = t % 4.2,
          wr = (cycle / 1.3).clamp(0, 1),
          bx = -w / 2 - f * .3 + wr * (w + f * .6);
      final n = math.max(4, (w / (f * .32)).round());
      for (var i = 0; i < n; i++) {
        final u = (i + .5) / n,
            age = cycle - u * 1.3 * (w / (w + f * .6)) - .05;
        if (age < 0 || age > 1.7) continue;
        final v = age / 1.7;
        c.drawCircle(
          Offset(
            -w / 2 + u * w + math.sin(i * 2.1) * f * .05,
            f * .56 - v * f * .12,
          ),
          f * (.07 + .13 * v),
          Paint()..color = _c(0xE1F5FE).withValues(alpha: 1 - v),
        );
      }
      if (cycle < 1.45) {
        c.saveLayer(
          rect.inflate(f * 2),
          Paint()
            ..color = _white.withValues(
              alpha: 1 - ((cycle - 1.3) / .15).clamp(0, 1),
            ),
        );
        c.translate(bx, -f * .52 + math.sin(t * 16) * f * .05);
        c.rotate((-6 + math.sin(t * 16) * 5) * math.pi / 180);
        c.scale(f / 16 * .23);
        c.translate(-21, -18);
        LookPainter.paint(c, const Look(bird: 'classic'), t: t);
        c.restore();
      } else {
        final tw = math.max(0, math.sin((cycle - 1.45) * 2.4));
        ArtPaint.star(
          c,
          w / 2 + f * .12,
          -f * .42,
          f * .14 * tw,
          _white,
          t * 2,
        );
      }
    }
    if (id == 'n_thunder') {
      final cycle = t % 2.3, k = (t / 2.3).floorToDouble();
      final tx = -w / 2 + (.15 + ArtPaint.hash(k * 3) * .7) * w;
      final cx =
              tx +
              f * .3 * (ArtPaint.hash(k) - .5) +
              math.sin(t * 1.3) * f * .06,
          cy = -f * .98;
      final lit = flash > .05,
          dark = _c(lit ? 0x7E57C2 : 0x3B2A5E),
          mid = _c(lit ? 0xB39DDB : 0x56417F);
      for (final (x, y, rx, ry, col) in [
        (-.34, .04, .28, .18, dark),
        (.32, .05, .26, .16, dark),
        (0.0, -.06, .32, .22, mid),
        (-.02, .12, .58, .12, dark),
      ]) {
        c.drawOval(
          Rect.fromCenter(
            center: Offset(cx + x * f, cy + y * f),
            width: rx * f * 2,
            height: ry * f * 2,
          ),
          Paint()..color = col,
        );
      }
      if (lit) draw(c, _white.withValues(alpha: flash));
      if (cycle < .32) {
        final pts = <Offset>[
          for (var i = 0; i <= 5; i++)
            Offset(
              tx +
                  f * .3 * (ArtPaint.hash(k) - .5) * (1 - i / 5) +
                  (i > 0 && i < 5
                      ? (ArtPaint.hash(k * 7 + i) - .5) * f * .38
                      : 0),
              -f * .92 + i / 5 * f * .56,
            ),
        ];
        final opacity = cycle < .27 ? 1.0 : 1 - (cycle - .27) / .05;
        line(c, pts, _c(0xFFD600).withValues(alpha: opacity), .12);
        line(c, pts, _white.withValues(alpha: opacity), .045);
        line(
          c,
          [
            pts[2],
            pts[2] + Offset(f * .3, f * .18),
            pts[2] + Offset(f * .42, f * .38),
          ],
          _c(0xFFD600).withValues(alpha: opacity),
          .07,
        );
        ArtPaint.star(c, tx, -f * .36, f * .28 * opacity, _white);
      }
      final q = (t * 11).floorToDouble();
      for (var j = 0; j < 2; j++) {
        final sx = -w / 2 + ArtPaint.hash(q * 5 + j) * w,
            sy = (ArtPaint.hash(q * 3 + j * 9) - .5) * f * .7;
        final pts = [
          for (var i = 0; i <= 3; i++)
            Offset(sx + i * f * .34 / 3, sy + (i.isOdd ? -1 : 1) * f * .07),
        ];
        line(c, pts, _c(0xB388FF), .055);
        line(c, pts, _white, .022);
      }
    }
    if (id == 'n_marquee') {
      final sx = -w / 2 - f + ((t * .45) % 1.4 - .2) * (w + f * 2);
      c.saveLayer(rect.inflate(f), Paint());
      c.drawPath(
        ArtPaint.poly([
          Offset(sx, -f),
          Offset(sx + f * .32, -f),
          Offset(sx - f * .18, f),
          Offset(sx - f * .5, f),
        ]),
        Paint()..color = _white.withValues(alpha: .75),
      );
      c.saveLayer(rect.inflate(f), Paint()..blendMode = BlendMode.dstIn);
      draw(c, _white);
      c.restore();
      c.restore();
    }
  }
}
