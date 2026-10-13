import 'dart:math' as math;
import 'dart:ui';

import 'art_paint.dart';
import 'hoop_art_v23.dart';

/// Canvas port of `hoopHalf` from `design/menu_v2/skin_art.js` (PRD-menu-v2
/// §5.4). A hoop is a vertical ring drawn as an ellipse: the **back** half is
/// drawn before the bird and the **front** half after it, so the bird flies
/// through the opening. Ring and opening sizes are fixed by gameplay — only
/// the colours, texture and animation come from the skin.
///
/// Pure painting: no Flame, no game state.
class HoopPainter {
  HoopPainter._();

  /// Hoop ids in catalogue order (PRD-menu-v2 §5.4; PRD-2.3 §19.3: the 2.3
  /// hoops of [HoopArtV23] mixed in by rarity).
  static const List<String> ids = [
    'pink', 'sky', 'lime', 'violet', 'night', //
    'sunset', 'lemon', 'bamboo', 'rope', 'cloud',
    'candy', 'polka', 'checker', 'donut',
    'tire', 'melon', 'zipper', 'tape', 'pearls', 'vine',
    'neon', 'lava', 'ice', 'electric', 'water', 'cog',
    'rainbow', 'galaxy', 'blackhole', 'aurora',
  ];

  /// The free default, used when an unknown id is requested.
  static const String fallbackId = 'pink';

  /// Colours of the rainbow ring (`skin_art.js`).
  static const List<Color> _rainbow = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00A2FF),
    Color(0xFFAF52DE),
  ];

  /// Draws one half of the vertical ring centred at [center].
  ///
  /// [ry] is the half opening height; `rx = ry * 0.26` (JS) unless [rx] is
  /// given (gameplay rings keep the fixed 24 pt width, PRD-2 §3.0.9 #3, via
  /// `RingPainter`). Draw the back
  /// half (`front: false`) before the bird and the front half after it. For
  /// the black-hole skin the back half also fills the opening with the swirl.
  /// [t] is time in seconds.
  static void paintHalf(
    Canvas canvas,
    String hoopId,
    Offset center,
    double ry,
    double t, {
    required bool front,
    double lineWidth = 7,
    double? rx,
  }) {
    if (ry <= 0 || lineWidth <= 0) return;
    if (paintHoopV23(
      canvas,
      hoopId,
      center,
      ry,
      t,
      front: front,
      lineWidth: lineWidth,
      rx: rx,
    )) {
      return;
    }
    final def = _byId(hoopId);
    final lw = lineWidth;
    rx ??= ry * .26;
    final a0 = front ? math.pi / 2 : -math.pi / 2;
    final a1 = front ? math.pi * 1.5 : math.pi / 2;

    /// The ring path at radius offsets ([dx], [dy]) from the arc centre.
    Path ring(double rx2, double ry2, [double dx = 0, double dy = 0]) =>
        Path()..arcTo(
          Rect.fromCenter(
            center: center + Offset(dx, dy),
            width: 2 * rx2,
            height: 2 * ry2,
          ),
          a0,
          a1 - a0,
          true,
        );

    void stroke(Path path, Color color, [double? width]) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width ?? lw
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
    }

    final base = front ? def.front : def.back;
    canvas.save();

    switch (def.style) {
      case _HoopStyle.candy:
        stroke(
          ring(rx, ry),
          front ? const Color(0xFFFFFFFF) : const Color(0xFFEEEEEE),
        );
        final stripe = front
            ? const Color(0xFFE53935)
            : const Color(0xFFB71C1C);
        stroke(
          ArtPaint.dashed(ring(rx, ry), [lw * .9, lw * .9], -t * 10),
          stripe,
        );
      case _HoopStyle.checker:
        stroke(
          ring(rx, ry),
          front ? const Color(0xFFFFFFFF) : const Color(0xFFCCCCCC),
        );
        const checker = Color(0xFF212121);
        final pattern = [lw * .7, lw * .7];
        stroke(
          ArtPaint.dashed(ring(rx - lw / 4, ry - lw / 4), pattern, 0),
          checker,
          lw / 2,
        );
        stroke(
          ArtPaint.dashed(ring(rx + lw / 4, ry + lw / 4), pattern, lw * .7),
          checker,
          lw / 2,
        );
      case _HoopStyle.polka:
        stroke(ring(rx, ry), base);
        final dot = const Color(0xE6FFFFFF);
        for (var i = 0; i < 9; i++) {
          final a = a0 + (i + .5) / 9 * (a1 - a0);
          ArtPaint.circ(
            canvas,
            center.dx + math.cos(a) * rx,
            center.dy + math.sin(a) * ry,
            lw * .2,
            dot,
          );
        }
      case _HoopStyle.donut:
        stroke(
          ring(rx, ry),
          front ? const Color(0xFFD9A066) : const Color(0xFFA0703C),
        );
        stroke(
          ring(rx, ry),
          front ? const Color(0xFFF48FB1) : const Color(0xFFC2185B),
          lw * .62,
        );
        if (front) {
          const sprinkles = [
            Color(0xFFFFFFFF),
            Color(0xFFFFEB3B),
            Color(0xFF29B6F6),
            Color(0xFF7CB342),
          ];
          for (var i = 0; i < 10; i++) {
            final a = a0 + (i + .5) / 10 * (a1 - a0);
            canvas
              ..save()
              ..translate(
                center.dx + math.cos(a) * rx,
                center.dy + math.sin(a) * ry,
              )
              ..rotate(i * 1.3)
              ..drawRect(
                Rect.fromLTWH(-lw * .22, -lw * .07, lw * .44, lw * .14),
                Paint()..color = sprinkles[i % 4],
              )
              ..restore();
          }
        }
      case _HoopStyle.neon:
        final pulse = .6 + .4 * math.sin(t * 5);
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = const Color(0xFF00E5FF)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            lw * (1 + pulse * 1.6) / 2,
          );
        canvas.drawPath(ring(rx, ry), glow);
        stroke(
          ring(rx, ry),
          front ? const Color(0xFF84FFFF) : const Color(0xFF00ACC1),
        );
        stroke(ring(rx, ry), const Color(0xFFFFFFFF), lw * .3);
      case _HoopStyle.lava:
        stroke(
          ring(rx, ry),
          front ? const Color(0xFFE65100) : const Color(0xFF8D1D00),
        );
        final hot = front ? const Color(0xFFFFD54F) : const Color(0xFFFF6D00);
        stroke(
          ArtPaint.dashed(ring(rx, ry), [
            lw * 1.2,
            lw * 1.4,
            lw * .4,
            lw,
          ], -t * 18),
          hot,
          lw * .4,
        );
      case _HoopStyle.ice:
        stroke(ring(rx, ry), base);
        stroke(
          ring(rx - lw * .2, ry - lw * .2, -lw * .15, 0),
          const Color(0xD9FFFFFF),
          lw * .25,
        );
        if (front) {
          final a = a0 + ((t * .5) % 1) * (a1 - a0);
          ArtPaint.star(
            canvas,
            center.dx + math.cos(a) * rx,
            center.dy + math.sin(a) * ry,
            lw * .7,
            const Color(0xFFFFFFFF),
            t,
          );
        }
      case _HoopStyle.rainbow:
        const n = 12;
        final bounds = Rect.fromCenter(
          center: center,
          width: 2 * rx,
          height: 2 * ry,
        );
        for (var i = 0; i < n; i++) {
          final color = _rainbow[(i + (t * 6).floor()) % 6];
          final segment = Path()
            ..arcTo(
              bounds,
              a0 + i / n * (a1 - a0),
              ((i + 1.05) / n - i / n) * (a1 - a0),
              true,
            );
          canvas.drawPath(
            segment,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = lw
              ..color = color.withValues(alpha: front ? 1 : .75),
          );
        }
      case _HoopStyle.galaxy:
        stroke(ring(rx, ry), base);
        for (var i = 0; i < 8; i++) {
          final a =
              a0 + ArtPaint.hash(i + (front ? 3 : 9).toDouble()) * (a1 - a0);
          final tw = (math.sin(t * 2.5 + i)).abs();
          ArtPaint.circ(
            canvas,
            center.dx +
                math.cos(a) * rx +
                (ArtPaint.hash(i.toDouble()) - .5) * lw * .5,
            center.dy + math.sin(a) * ry,
            lw * .12 + tw * lw * .12,
            const Color(0xFFFFFFFF).withValues(alpha: .3 + .7 * tw),
          );
        }
      case _HoopStyle.blackhole:
        if (!front) _paintBlackHoleInterior(canvas, center, rx, ry, t, lw);
        stroke(
          ring(rx, ry),
          front ? const Color(0xFF000000) : const Color(0xFF0A0A0A),
        );
        for (var k = 0; k < 2; k++) {
          final color = k == 1
              ? const Color(0x38FFFFFF)
              : const Color(0x8078788C);
          final inset = k == 1 ? lw * .22 : -lw * .18;
          stroke(
            ArtPaint.dashed(ring(rx + inset, ry + inset), [
              lw * 1.4,
              lw * 1.1,
            ], -t * (k == 1 ? 26 : 16) - k * lw),
            color,
            lw * .22,
          );
        }
        for (var i = 0; i < 9; i++) {
          final ph =
              (t * .35 + ArtPaint.hash(i + (front ? 1 : 5).toDouble())) % 1;
          final a = a0 + ph * (a1 - a0);
          final tw = (math.sin(t * 4 + i * 1.9)).abs();
          final off = (ArtPaint.hash(i + 20.0) - .5) * lw * 1.6;
          final px = center.dx + math.cos(a) * (rx + off * .3);
          final py = center.dy + math.sin(a) * (ry + off);
          if (i % 3 == 0) {
            ArtPaint.star(
              canvas,
              px,
              py,
              lw * (.25 + .35 * tw),
              const Color(0xFFFFFFFF),
              t + i,
            );
          } else {
            ArtPaint.circ(
              canvas,
              px,
              py,
              lw * (.06 + .08 * tw),
              const Color(0xFFFFFFFF).withValues(alpha: .4 + .6 * tw),
            );
          }
        }
      case _HoopStyle.plain:
        stroke(ring(rx, ry), base);
    }
    canvas.restore();
  }

  /// The shop-grid thumbnail: the ring tilted 10° with both halves drawn.
  static void paintHoopTile(
    Canvas c,
    String hoopId,
    Offset centre,
    double ry,
    double t,
  ) {
    if (ry <= 0) return;
    final lw = math.max(4.0, ry * .22);
    c
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(.18);
    paintHalf(c, hoopId, Offset.zero, ry, t, front: false, lineWidth: lw);
    paintHalf(c, hoopId, Offset.zero, ry, t, front: true, lineWidth: lw);
    c.restore();
  }

  /// The black-hole opening: a black disc with a three-armed swirl, glitter
  /// spiralling inward and a darker centre, clipped to the ring interior.
  /// Drawn as part of the back half (the bird then flies "through" it).
  static void _paintBlackHoleInterior(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double t,
    double lw,
  ) {
    final hole = Path()
      ..addOval(Rect.fromCenter(center: center, width: 2 * rx, height: 2 * ry));
    canvas
      ..save()
      ..drawPath(hole, Paint()..color = const Color(0xFF000000))
      ..clipPath(hole)
      ..translate(center.dx, center.dy)
      ..scale(rx / ry, 1);
    for (var arm = 0; arm < 3; arm++) {
      final path = Path();
      for (var i = 0; i <= 40; i++) {
        final u = i / 40;
        final r = ry * (1 - u) * .98;
        final a = -t * 2.2 + arm * ArtPaint.tau / 3 + u * 5.5;
        final px = math.cos(a) * r;
        final py = math.sin(a) * r;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ry * .13
          ..color = arm == 0
              ? const Color(0x47FFFFFF)
              : const Color(0x4D8C8CAA),
      );
    }
    for (var i = 0; i < 14; i++) {
      final u = (t * .4 + ArtPaint.hash(i + 31.0)) % 1;
      final r = ry * (1 - u);
      final a = -t * 2.2 + ArtPaint.hash(i + 7.0) * ArtPaint.tau + u * 5.5;
      final tw = 1 - u;
      ArtPaint.circ(
        canvas,
        math.cos(a) * r,
        math.sin(a) * r,
        ry * .035 * (1 + tw),
        const Color(0xFFFFFFFF).withValues(alpha: .25 + .75 * tw),
      );
    }
    canvas.drawCircle(
      Offset.zero,
      ry * .35,
      Paint()
        ..shader = Gradient.radial(Offset.zero, ry * .35, const [
          Color(0xFF000000),
          Color(0x00000000),
        ]),
    );
    canvas.restore();
  }

  static _HoopDef _byId(String id) {
    for (final def in _hoops) {
      if (def.id == id) return def;
    }
    return _hoops.first;
  }
}

/// One hoop skin: its front/back colours plus the texture/animation style.
class _HoopDef {
  const _HoopDef(
    this.id,
    this.front,
    this.back, [
    this.style = _HoopStyle.plain,
  ]);

  final String id;
  final Color front;
  final Color back;
  final _HoopStyle style;
}

enum _HoopStyle {
  plain,
  candy,
  polka,
  checker,
  donut,
  neon,
  lava,
  ice,
  rainbow,
  galaxy,
  blackhole,
}

/// `HOOPS` in skin_art.js, in display order. The `wood` entry of the mock is
/// not in the 2.0 catalogue and is skipped.
const List<_HoopDef> _hoops = [
  _HoopDef('pink', Color(0xFFEC008C), Color(0xFFB0006B)),
  _HoopDef('sky', Color(0xFF29B6F6), Color(0xFF0277BD)),
  _HoopDef('lime', Color(0xFF7CB342), Color(0xFF33691E)),
  _HoopDef('violet', Color(0xFF8E24AA), Color(0xFF4A148C)),
  _HoopDef('night', Color(0xFF37474F), Color(0xFF101518)),
  _HoopDef('candy', Color(0xFFFFFFFF), Color(0xFFC62828), _HoopStyle.candy),
  _HoopDef('polka', Color(0xFF00ACC1), Color(0xFF006064), _HoopStyle.polka),
  _HoopDef('checker', Color(0xFFFFFFFF), Color(0xFF212121), _HoopStyle.checker),
  _HoopDef('donut', Color(0xFFF48FB1), Color(0xFFC68642), _HoopStyle.donut),
  _HoopDef('neon', Color(0xFF00E5FF), Color(0xFF00838F), _HoopStyle.neon),
  _HoopDef('lava', Color(0xFFFF6D00), Color(0xFFB71C1C), _HoopStyle.lava),
  _HoopDef('ice', Color(0xFFB3E5FC), Color(0xFF4FC3F7), _HoopStyle.ice),
  _HoopDef('rainbow', Color(0xFFFF0000), Color(0xFF880000), _HoopStyle.rainbow),
  _HoopDef('galaxy', Color(0xFF3A1C8C), Color(0xFF120634), _HoopStyle.galaxy),
  _HoopDef(
    'blackhole',
    Color(0xFF000000),
    Color(0xFF000000),
    _HoopStyle.blackhole,
  ),
];
