import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../components/ui/confetti.dart';
import '../../run/effects/coin_icon.dart';
import '../../run/effects/twinkle.dart';
import 'art_paint.dart';
import 'hoop_painter.dart';
import 'look_painter.dart';
import '../look.dart';

/// Host adapter to one of the existing shared ray masters (O98).
/// [t] is the same frozen-or-running game clock as the sticker body.
typedef CardStickerRays =
    void Function(Canvas canvas, Offset centre, double radius, double t);

/// F9 / O80: the twenty approved versus-card victory stickers.
///
/// Coordinates match `versus_cards.html` (120 × 96 art units, origin at the
/// centre). The caller supplies elapsed game-clock seconds [t]; keeping that
/// value fixed freezes every effect. No ticker, unseeded random or wall clock.
/// Coins use the loaded [CoinIcon] asset, shared with the rest of the game.
abstract final class CardStickerArt {
  static const ids = <String>[
    's_gg',
    's_thumbs',
    's_heart',
    's_wow',
    's_kaching',
    's_spiked',
    's_pow',
    's_nailed',
    's_bye',
    's_hatch',
    's_zoom',
    's_hot',
    's_medal',
    's_piggy',
    's_disco',
    's_champ',
    's_fireworks',
    's_unstop',
    's_flawless',
    's_topflock',
  ];

  static bool has(String id) => ids.contains(id);

  /// Paint at the canvas origin. Unknown/empty slots paint nothing.
  /// The optional [paintRays] host callback renders the existing shared ray
  /// master behind Champion, Flawless and Top of the Flock. Those masters
  /// currently have private entry points; this painter never duplicates them.
  /// Supply [coinImage] (loaded with [CoinIcon.load]) for Ka-ching and Piggy
  /// Bank; it is optional for every other sticker. [scale] is art-unit scale.
  static void paint(
    Canvas canvas,
    String id, {
    double t = 0,
    double scale = 1,
    ui.Image? coinImage,
    CardStickerRays? paintRays,
  }) {
    if (!has(id) || scale <= 0) return;
    assert(t.isFinite);
    assert(
      coinImage != null || (id != 's_kaching' && id != 's_piggy'),
      'Coin stickers need the shared CoinIcon image.',
    );
    canvas.save();
    canvas.scale(scale);
    final d = _Sticker(canvas, t, coinImage);
    if (id == 's_champ' || id == 's_flawless' || id == 's_topflock') {
      paintRays?.call(
        canvas,
        Offset(
          0,
          id == 's_champ'
              ? 0
              : id == 's_flawless'
              ? -12
              : -14,
        ),
        46,
        t,
      );
    }
    d.back(id);
    final recorder = ui.PictureRecorder();
    final bodyCanvas = Canvas(recorder);
    _Sticker(bodyCanvas, t, coinImage).body(id);
    final body = recorder.endRecording();
    // SVG die-cut: a 7-unit white round outline, then a 2.5-unit hard
    // drop shadow. Tint the SAME body picture, including shared bird art,
    // rather than keeping a second silhouette drawing.
    void silhouette(Color color, double dy) {
      canvas.saveLayer(
        const Rect.fromLTRB(-100, -100, 100, 100),
        Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      );
      for (var i = 0; i < 24; i++) {
        final a = i / 24 * ArtPaint.tau;
        canvas.save();
        canvas.translate(math.cos(a) * 3.5, math.sin(a) * 3.5 + dy);
        canvas.drawPicture(body);
        canvas.restore();
      }
      canvas.drawPicture(body);
      canvas.restore();
    }

    silhouette(const Color(0x33000000), 2.5);
    silhouette(const Color(0xFFFFFFFF), 0);
    canvas.drawPicture(body);
    body.dispose();
    d.fx(id);
    canvas.restore();
  }
}

/// Widget adapter; Flame callers can call [CardStickerArt.paint] directly.
/// Update [t] from the game clock, including in previews and paused runs.
class CardStickerPainter extends CustomPainter {
  const CardStickerPainter({
    required this.id,
    this.t = 0,
    this.coinImage,
    this.paintRays,
  });
  final String id;
  final double t;
  final ui.Image? coinImage;
  final CardStickerRays? paintRays;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    CardStickerArt.paint(
      canvas,
      id,
      t: t,
      scale: math.min(size.width / 120, size.height / 96),
      coinImage: coinImage,
      paintRays: paintRays,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(CardStickerPainter oldDelegate) =>
      id != oldDelegate.id ||
      t != oldDelegate.t ||
      coinImage != oldDelegate.coinImage ||
      paintRays != oldDelegate.paintRays;
}

const _pink = Color(0xFFEC008C), _gold = Color(0xFFFFB529);
const _plum = Color(0xFF7A0044), _white = Color(0xFFFFFFFF);
const _red = Color(0xFFE53935), _blue = Color(0xFF29B6F6);
const _darkGold = Color(0xFFE69500), _paleGold = Color(0xFFFFE7A6);
const _tau = math.pi * 2;

double _clamp(double x) => x.clamp(0.0, 1.0);
double _out(double x) => 1 - math.pow(1 - _clamp(x), 3).toDouble();
double _back(double x) {
  final u = _clamp(x) - 1;
  return 1 + 2.9 * u * u * u + 1.9 * u * u;
}

double _lerp(double a, double b, double u) => a + (b - a) * u;
double _hash(double i) {
  final x = math.sin(i * 12.9898 + 78.233) * 43758.5453;
  return x - x.floor();
}

class _Sticker {
  _Sticker(this.c, this.t, this.coinImage);
  final Canvas c;
  final double t;
  final ui.Image? coinImage;

  void group(
    void Function() draw, {
    double x = 0,
    double y = 0,
    double angle = 0,
    double sx = 1,
    double sy = 1,
  }) {
    c.save();
    c.translate(x, y);
    c.rotate(angle * math.pi / 180);
    c.scale(sx, sy);
    draw();
    c.restore();
  }

  void alpha(double a, void Function() draw) {
    c.saveLayer(
      const Rect.fromLTRB(-100, -100, 100, 100),
      Paint()..color = _white.withValues(alpha: _clamp(a)),
    );
    draw();
    c.restore();
  }

  void path(Path p, Color color, {Color? stroke, double width = 1}) {
    c.drawPath(p, Paint()..color = color);
    if (stroke != null) {
      c.drawPath(
        p,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void poly(List<double> p, Color col, {Color? stroke, double width = 1}) =>
      path(
        ArtPaint.poly([
          for (var i = 0; i < p.length; i += 2) Offset(p[i], p[i + 1]),
        ]),
        col,
        stroke: stroke,
        width: width,
      );
  void rect(double x, double y, double w, double h, Color col) =>
      c.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = col);
  void ellipse(
    double x,
    double y,
    double rx,
    double ry,
    Color col, {
    Color? stroke,
    double width = 1,
  }) => path(
    Path()..addOval(
      Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
    ),
    col,
    stroke: stroke,
    width: width,
  );
  void circle(
    double x,
    double y,
    double r,
    Color col, {
    Color? stroke,
    double width = 1,
  }) => ellipse(x, y, r, r, col, stroke: stroke, width: width);
  void line(List<double> p, Color col, double width) {
    final a = Path()..moveTo(p[0], p[1]);
    for (var i = 2; i < p.length; i += 2) {
      a.lineTo(p[i], p[i + 1]);
    }
    c.drawPath(
      a,
      Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void star(double x, double y, double r, Color col, [double a = 0]) =>
      Twinkle.paint(c, Offset(x, y), r * 2, col, rotation: a, waist: .38);
  void text(
    String s,
    double x,
    double y,
    double size,
    Color col, {
    bool fred = false,
    double spacing = 0,
    Color? stroke,
    double width = 1,
  }) {
    final base = TextStyle(
      fontFamily: fred ? 'Fredoka' : 'Opificio Neue',
      fontWeight: fred ? FontWeight.w600 : FontWeight.w400,
      fontSize: size,
      letterSpacing: spacing,
    );
    void draw(TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(c, Offset(x - p.width / 2, y - p.height / 2));
      p.dispose();
    }

    if (stroke != null) {
      draw(
        base.copyWith(
          foreground: Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = width,
        ),
      );
    }
    draw(base.copyWith(color: col));
  }

  void bird(
    double x,
    double y,
    double s, {
    String id = 'classic',
    double angle = 0,
  }) => group(
    () => LookPainter.paint(c, Look(bird: id), t: t),
    x: x,
    y: y,
    angle: angle,
    sx: s,
    sy: s,
  );
  void coin(double x, double y, double r) {
    if (coinImage != null) CoinIcon.paint(c, coinImage!, Offset(x, y), r * 2);
  }

  void ribbon(
    String label, {
    double y = 20,
    double w = 60,
    double h = 16,
    Color col = _gold,
    Color ink = _plum,
    double size = 11,
    double spacing = 1,
  }) {
    rect(-w / 2, y - h / 2, w, h, col);
    text(label, 0, y + .5, size, ink, spacing: spacing);
  }

  void body(String id) {
    switch (id) {
      case 's_gg':
        group(() {
          rect(-27, -16, 54, 32, _white);
          path(
            Path()..addRect(const Rect.fromLTWH(-27, -16, 54, 32)),
            const Color(0x00000000),
            stroke: _pink,
            width: 3,
          );
          text('GG!', 0, 1.5, 24, _pink, fred: true);
        }, angle: -7);
      case 's_thumbs':
        group(() {
          rect(-20, -1, 8, 22, _pink);
          rect(-12, -4, 25, 25, _gold);
          rect(-6, -26, 10, 24, _gold);
          rect(0, -26, 4, 22, _darkGold);
          for (final y in [3.0, 9.0, 15.0]) {
            rect(1, y, 12, 2, _darkGold);
          }
          rect(-4.5, -24, 5, 4, _paleGold);
        }, angle: -10);
        star(22, -18, 5, _gold);
        star(-24, -20, 3.4, _pink, .4);
      case 's_heart':
        final b =
            math.pow(math.max(0.0, math.sin(t * 6)), 10) * .13 +
            math.pow(math.max(0.0, math.sin(t * 6 - 1.1)), 10) * .08;
        final s = 3.4 * (1 + b);
        group(
          () {
            final p = Path()
              ..moveTo(0, 5.6 * s)
              ..cubicTo(-7 * s, 0, -7 * s, -6 * s, -3.4 * s, -7.4 * s)
              ..cubicTo(-1.6 * s, -8 * s, -.4 * s, -7 * s, 0, -5.6 * s)
              ..cubicTo(.4 * s, -7 * s, 1.6 * s, -8 * s, 3.4 * s, -7.4 * s)
              ..cubicTo(7 * s, -6 * s, 7 * s, 0, 0, 5.6 * s)
              ..close();
            path(p, const Color(0xFFFF4FB7), stroke: _pink, width: 3);
            group(
              () =>
                  ellipse(0, 0, 1.6 * s, .9 * s, _white.withValues(alpha: .75)),
              x: -3 * s,
              y: -4.6 * s,
              angle: -32,
            );
          },
          angle: -8,
          y: 4,
        );
      case 's_wow':
        group(() {
          text(
            'WOW',
            0,
            2,
            30,
            const Color(0xFF4FC3F7),
            fred: true,
            stroke: const Color(0xFF0277BD),
            width: 5,
          );
          rect(-24, -6, 8, 2.4, _white.withValues(alpha: .7));
        }, angle: -8);
        star(33, -17, 5, _gold);
        star(-34, 15, 3.6, _pink, .4);
      case 's_kaching':
        group(() {
          coin(0, -7, 20);
          rect(
            -8,
            (t % 2.4) > 2.05 ? -11.6 : -14,
            4,
            (t % 2.4) > 2.05 ? 1.4 : 4,
            _plum,
          );
          rect(4, -14, 4, 4, _plum);
          final p = Path()
            ..moveTo(-7, -3)
            ..quadraticBezierTo(0, 3, 7, -3);
          c.drawPath(
            p,
            Paint()
              ..color = _plum
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
          poly([-36, 13, 36, 13, 32, 28, -32, 28], _plum);
          text('KA-CHING!', 0, 20.5, 11, _gold, spacing: 1);
        }, angle: -6);
        star(26, -24, 4 + math.max(0.0, math.sin(t * 4)) * 3, _white);
      case 's_spiked':
        group(() {
          poly([-26, 20, -3, -26, 20, 20], const Color(0xFF808080));
          poly([-3, -26, 20, 20, -3, 20], const Color(0xFF6E6E6E));
          group(
            () {
              circle(0, 0, 11, _red);
              rect(-2, -7.5, 4, 9, _white);
              rect(-2, 3.6, 4, 3.6, _white);
            },
            x: 19,
            y: -15,
            angle: math.sin(t * 6) * 10,
          );
        }, angle: -6);
      case 's_pow':
        group(() {
          final p = <double>[];
          for (var i = 0; i < 24; i++) {
            final a = i / 24 * _tau, r = i.isOdd ? 21.0 : 33.0;
            p.addAll([math.cos(a) * r * 1.1, math.sin(a) * r * .86]);
          }
          poly(p, _red);
          poly(p.map((v) => v * .74).toList(), const Color(0xFFFFEB3B));
          text('POW!', 0, 1, 19, _white, fred: true, stroke: _plum, width: 4);
        }, angle: -8);
      case 's_nailed':
        group(() {
          HoopPainter.paintHalf(
            c,
            'sky',
            const Offset(-12, -10),
            21,
            t,
            front: false,
            lineWidth: 4,
          );
          bird(8, -11, .78);
          HoopPainter.paintHalf(
            c,
            'sky',
            const Offset(-12, -10),
            21,
            t,
            front: true,
            lineWidth: 4,
          );
          poly([
            -38,
            12,
            -30,
            12,
            -30,
            26,
            -38,
            26,
            -33,
            19,
          ], const Color(0xFFC98A00));
          poly([
            38,
            12,
            30,
            12,
            30,
            26,
            38,
            26,
            33,
            19,
          ], const Color(0xFFC98A00));
          ribbon('NAILED IT', y: 17.5, w: 62, h: 15, size: 10.5);
        }, angle: -5);
      case 's_bye':
        group(() {
          bird(-14, 8, .95);
          group(
            () => poly([0, 0, -4, -15, 5, -3], const Color(0xFFC2187A)),
            x: 1,
            y: -17,
            angle: math.sin(t * 9) * .45 * 180 / math.pi,
            sy: -1,
          );
          path(
            Path()
              ..moveTo(2, -30)
              ..relativeLineTo(34, 0)
              ..relativeLineTo(0, 20)
              ..relativeLineTo(-20, 0)
              ..relativeLineTo(-8, 7)
              ..relativeLineTo(0, -7)
              ..relativeLineTo(-6, 0)
              ..close(),
            _white,
            stroke: _plum,
            width: 2.2,
          );
          text('BYE!', 19, -19.5, 13, _plum, fred: true);
        }, angle: -6);
      case 's_hatch':
        hatch();
      case 's_zoom':
        group(() {
          final f = math.sin(t * 30) * 2.4;
          poly([-14, -5, -27 - f, 0, -14, 5], const Color(0xFFFF7A1A));
          poly([-14, -3, -21 - f * .6, 0, -14, 3], const Color(0xFFFFE082));
          poly([-14, -7, -7, -7, -17, -15], _pink);
          poly([-14, 7, -7, 7, -17, 15], _pink);
          poly([-15, -7, 9, -7, 19, 0, 9, 7, -15, 7], const Color(0xFFECEFF1));
          poly([9, -7, 19, 0, 9, 7], _pink);
          circle(0, 0, 3.6, _blue, stroke: const Color(0xFF0277BD), width: 1.4);
        }, angle: -30);
        group(
          () => ribbon('ZOOM', y: 23, w: 48, size: 12, spacing: 1.5),
          angle: -6,
        );
      case 's_hot':
        group(() {
          for (var i = 0; i < 5; i++) {
            final x = -20.0 + i * 10,
                h = 11 + math.sin(t * 11 + i * 1.7) * 3 + (i == 2 ? 5 : 0.0);
            poly([
              x - 6,
              -8,
              x - 3,
              -8 - h * .5,
              x + math.sin(t * 7 + i) * 1.5,
              -8 - h,
              x + 3,
              -8 - h * .5,
              x + 6,
              -8,
            ], i.isOdd ? _gold : const Color(0xFFFF7A1A));
          }
          poly([
            -30,
            -9,
            30,
            -9,
            30,
            15,
            -30,
            15,
            -24,
            3,
          ], const Color(0xFFFF5722));
          rect(-24, -9, 54, 4, _white.withValues(alpha: .25));
          text('HOT!', 3, 3.5, 19, _white, fred: true);
        }, angle: -6);
      case 's_medal':
        group(
          () => group(() {
            poly([-14, -32, -5, -32, 5, -6, -4, -6], _pink);
            poly([14, -32, 5, -32, -5, -6, 4, -6], _blue);
            circle(0, 8, 17, const Color(0xFFC98A00));
            circle(0, 8, 15, _gold);
            circle(
              0,
              8,
              11,
              const Color(0xFFFFC233),
              stroke: _darkGold,
              width: 1.6,
            );
            final p = <double>[];
            for (var i = 0; i < 10; i++) {
              final a = i / 10 * _tau - math.pi / 2, r = i.isEven ? 8.0 : 3.6;
              p.addAll([math.cos(a) * r, 8.5 + math.sin(a) * r]);
            }
            poly(p, const Color(0xFFFFF3C4));
            poly([-11, -2, -6, -6, -12, 4], _white.withValues(alpha: .55));
          }, y: 30),
          y: -30,
          angle: math.sin(t * 2.4) * 8,
        );
      case 's_piggy':
        piggy();
      case 's_disco':
        disco();
      case 's_champ':
        champion();
      case 's_fireworks':
        group(() {
          poly([-40, 14, -30, 14, -30, 30, -40, 30, -35, 22], _plum);
          poly([40, 14, 30, 14, 30, 30, 40, 30, 35, 22], _plum);
          path(
            Path()..addRect(const Rect.fromLTWH(-31, 10, 62, 22)),
            _pink,
            stroke: _gold,
            width: 2,
          );
          text('WIN!', 0, 21.5, 18, _white, fred: true);
        }, angle: -5);
      case 's_unstop':
        unstoppable();
      case 's_flawless':
        flawless();
      case 's_topflock':
        topflock();
    }
  }

  void hatch() {
    final clock = t % 3.4,
        wob = clock < 1.3
            ? math.sin(clock * 22) * 7 * math.min(1, clock / .3)
            : 0.0;
    final op = _out((clock - 1.4) / .35), hd = _back((clock - 1.5) / .4);
    const shell = Color(0xFFF6EBD2),
        edge = Color(0xFFCDB27E),
        speck = Color(0xFFC9AE7A);
    void spots(List<double> p) {
      for (var i = 0; i < p.length; i += 2) {
        rect(p[i], p[i + 1], 2.4, 2.4, speck);
      }
    }

    group(
      () => group(() {
        if (clock < 1.15) {
          ellipse(0, 0, 18, 22, shell, stroke: edge, width: 1.6);
          spots([-8, -10, 6, -14, 9, 6, -10, 8, 0, 14, -2, -2]);
          if (clock > .9) {
            line(
              [-17, 0, -11, 4, -6, -1, 0, 5, 6, -1, 11, 4, 17, 0],
              const Color(0xFF8D6E43),
              1.4,
            );
          }
        } else {
          if (hd > 0) bird(0, _lerp(8, -12, hd), .66);
          Path shellPath(bool top) => Path()
            ..moveTo(-17.6, 0)
            ..lineTo(-11, 4)
            ..lineTo(-6, -1)
            ..lineTo(0, 5)
            ..lineTo(6, -1)
            ..lineTo(11, 4)
            ..lineTo(17.6, 0)
            ..quadraticBezierTo(
              top ? 17 : 18,
              top ? -22 : 22,
              0,
              top ? -22 : 22,
            )
            ..quadraticBezierTo(top ? -17 : -18, top ? -22 : 22, -17.6, 0)
            ..close();
          path(shellPath(false), shell, stroke: edge, width: 1.6);
          spots([-10, 8, 9, 6]);
          group(
            () {
              path(shellPath(true), shell, stroke: edge, width: 1.6);
              spots([-8, -12, 6, -15]);
            },
            x: 14 * op,
            y: -20 * op,
            angle: 32 * op,
          );
        }
      }, y: -22),
      y: 22,
      angle: wob,
    );
  }

  void piggy() {
    final clock = t % 2.2, wg = clock < .5 ? math.sin(clock * 40) * 4 : 0.0;
    const pink = Color(0xFFF06292);
    group(
      () => group(() {
        rect(-13, 9, 6, 9, pink);
        rect(6, 9, 6, 9, pink);
        final tail = Path()
          ..moveTo(-21, -2)
          ..relativeQuadraticBezierTo(-7, -2, -5, -7)
          ..relativeQuadraticBezierTo(2, -3, 4, 1);
        c.drawPath(
          tail,
          Paint()
            ..color = pink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        ellipse(0, 0, 22, 15, const Color(0xFFF8A5C2));
        poly([-10, -12, -5, -22, 0, -13], pink);
        ellipse(20, 2, 6, 5, pink);
        rect(17, 0, 2, 3, _plum);
        rect(21, 0, 2, 3, _plum);
        rect(9, -6, 3.4, 3.4, const Color(0xFF4A1030));
        rect(-7, -15.6, 14, 2.8, const Color(0xFF7A0044));
        ellipse(-9, -6, 5, 2.4, _white.withValues(alpha: .45));
      }, y: -14),
      y: 14,
      angle: -4 + wg,
    );
  }

  void disco() {
    const fs = 5.2;
    final shift = (t * 6) % fs, cycle = (t * 6 / fs).floor();
    rect(-1, -31, 2, 10, const Color(0xFF555555));
    circle(0, -4, 17.6, const Color(0xFF546E7A));
    c.save();
    c.clipPath(Path()..addOval(const Rect.fromLTWH(-17, -21, 34, 34)));
    for (var r = -4; r <= 4; r++) {
      for (var q = -5; q <= 5; q++) {
        final v = _hash(((r + 9) * 31 + q + cycle * 7).toDouble());
        final col = v < .25
            ? const Color(0xFF78909C)
            : v < .55
            ? const Color(0xFFB0BEC5)
            : v < .85
            ? const Color(0xFFECEFF1)
            : _white;
        rect(
          q * fs + shift - fs / 2,
          r * fs - 4 - fs / 2,
          fs - .6,
          fs - .6,
          col,
        );
      }
    }
    c.restore();
    group(
      () => ribbon(
        'PARTY!',
        y: 23,
        w: 52,
        size: 12,
        spacing: 1.4,
        col: _pink,
        ink: _white,
      ),
      angle: -5,
    );
  }

  void crown(double x, double y, double s) => group(
    () {
      poly([
        -11,
        0,
        -11,
        -9,
        -5.5,
        -4.5,
        0,
        -12,
        5.5,
        -4.5,
        11,
        -9,
        11,
        0,
      ], _gold);
      rect(-11, -2.6, 22, 2.6, _darkGold);
      poly([
        -11,
        -9,
        -5.5,
        -4.5,
        -5.5,
        -2.6,
        -11,
        -6,
      ], _white.withValues(alpha: .45));
      rect(-2.2, -7.4, 4.4, 4.4, _red);
      circle(-7, -1.3, 1.2, const Color(0xFF1E88E5));
      circle(7, -1.3, 1.2, const Color(0xFF43A047));
    },
    x: x,
    y: y,
    sx: s,
    sy: s,
  );

  void champion() {
    group(() {
      poly([-15, -16, 15, -16, 13, -1, 4, 5, -4, 5, -13, -1], _gold);
      poly([4, -16, 15, -16, 13, -1, 4, 5], _darkGold);
      final left = Path()
        ..moveTo(-15, -13)
        ..relativeQuadraticBezierTo(-9, 0, -6, 8)
        ..relativeQuadraticBezierTo(2, 4, 8, 4);
      final right = Path()
        ..moveTo(15, -13)
        ..relativeQuadraticBezierTo(9, 0, 6, 8)
        ..relativeQuadraticBezierTo(-2, 4, -8, 4);
      c.drawPath(
        left,
        Paint()
          ..color = _gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      c.drawPath(
        right,
        Paint()
          ..color = _darkGold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      rect(-3, 5, 6, 6, _darkGold);
      rect(-11, 10, 22, 5, _plum);
      crown(0, -17, .82);
      poly([-34, 18, 34, 18, 30, 32, -30, 32], _plum);
      text('CHAMP!', 0, 25.5, 12, _gold, spacing: 1.5);
    }, angle: -4);
    for (var i = 0; i < 4; i++) {
      star(
        <double>[-30, 28, -24, 30][i],
        <double>[-26, -22, 20, 14][i],
        2 + math.max(0.0, math.sin(t * 3 + i * 1.7)) * 4,
        _white,
      );
    }
  }

  void unstoppable() => group(() {
    final clock = t % 2.8;
    void spike(double x, double h) {
      poly([x - 11, 6, x, 6 - h, x + 11, 6], const Color(0xFF8A8A8A));
      poly([x, 6 - h, x + 11, 6, x, 6], const Color(0xFF6E6E6E));
    }

    spike(-25, 22);
    spike(25, 22);
    final reform = _clamp((clock - 2.45) / .3);
    if (clock < .42 || reform > 0) {
      final s = clock < .42 ? 1.0 : _back(reform);
      group(() => group(() => spike(0, 30), y: -6), y: 6, sx: s, sy: s);
    } else {
      poly([
        -10,
        6,
        -6,
        -2,
        -2,
        1,
        2,
        -4,
        6,
        0,
        10,
        6,
      ], const Color(0xFF8A8A8A));
    }
    double x, y, rot, opacity = 1;
    if (clock < .42) {
      final u = clock / .42;
      x = _lerp(-50, -2, u * u);
      y = -14;
      rot = 6;
    } else if (clock < .9) {
      final u = _out((clock - .42) / .48);
      x = _lerp(-2, 20, u);
      y = _lerp(-14, -26, u);
      rot = _lerp(6, -10, u);
    } else if (clock < 2.3) {
      x = 20;
      y = -26 + math.sin((clock - .9) * 5) * 1.6;
      rot = -10;
    } else {
      final u = _clamp((clock - 2.3) / .3);
      x = _lerp(20, 60, u * u);
      y = -26 - u * 8;
      rot = -10;
      opacity = 1 - u;
    }
    if (opacity > 0) alpha(opacity, () => bird(x, y, .62, angle: rot));
    poly([
      -46,
      14,
      -36,
      14,
      -36,
      30,
      -46,
      30,
      -41,
      22,
    ], const Color(0xFFB71C1C));
    poly([46, 14, 36, 14, 36, 30, 46, 30, 41, 22], const Color(0xFFB71C1C));
    ribbon(
      'UNSTOPPABLE',
      y: 19.5,
      w: 76,
      h: 17,
      col: _red,
      ink: const Color(0xFFFFE082),
      size: 10.5,
      spacing: .6,
    );
    rect(-38, 11, 76, 3, _white.withValues(alpha: .25));
  }, angle: -5);

  void flawless() {
    final p = (t * .22) % 1;
    const cy = -12.0,
        top = cy - 14,
        gir = cy - 5,
        tip = cy + 20,
        rg = 27.0,
        rt = 15.0;
    const pal = [
      Color(0xFF8A0052),
      Color(0xFFB0006B),
      _pink,
      Color(0xFFFF4FB7),
      Color(0xFFFF8AC8),
      Color(0xFFFFD1EA),
    ];
    poly(
      [-rt, top, rt, top, rg, gir, 0, tip, -rg, gir],
      const Color(0xFFB0006B),
      stroke: const Color(0xFF5A0033),
      width: 2,
    );
    for (var i = 0; i < 8; i++) {
      final a1 = _tau * (i / 8 + p),
          a2 = _tau * ((i + 1) / 8 + p),
          am = (a1 + a2) / 2;
      if (math.cos(am) <= 0) continue;
      final sh = _clamp((math.cos(am) * .55 + math.sin(am) * .45 + 1) / 2),
          ix = math.min(5, (sh * 5.99).floor());
      final xg1 = rg * math.sin(a1),
          xg2 = rg * math.sin(a2),
          xt1 = rt * math.sin(a1),
          xt2 = rt * math.sin(a2);
      poly([xg1, gir, xg2, gir, 0, tip], pal[math.max(0, ix - 1)]);
      poly([xt1, top, xt2, top, xg2, gir, xg1, gir], pal[ix]);
    }
    poly([
      -rt,
      top,
      rt,
      top,
      rt - 3,
      top + 2.2,
      -rt + 3,
      top + 2.2,
    ], _white.withValues(alpha: .55));
    group(() {
      poly([-31, 14, 31, 14, 28, 30, -28, 30], const Color(0xFFC98A00));
      ribbon('FLAWLESS', y: 19.5, w: 60, h: 15, size: 11, spacing: 1.6);
      rect(-30, 12, 60, 3, _paleGold);
    }, angle: -3);
  }

  void topflock() => group(() {
    final clock = t % 3.2,
        bow =
            math.max(0.0, math.sin(_clamp((clock - .75) / .9) * math.pi)) * 14;
    rect(-38, 3, 25, 17, const Color(0xFFB0BEC5));
    rect(-38, 3, 25, 3, const Color(0xFFECEFF1));
    rect(13, 7, 25, 13, const Color(0xFFD7894A));
    rect(13, 7, 25, 3, const Color(0xFFF2B98A));
    rect(-13, -5, 26, 25, _gold);
    rect(-13, -5, 26, 3, _paleGold);
    text('1', 0, 9, 14, _plum);
    text('2', -25.5, 13, 10, const Color(0xFF546E7A));
    text('3', 25.5, 15, 10, const Color(0xFF7A3E12));
    group(() => bird(0, -6.4, .42, id: 'sky'), x: -25, y: 3, angle: bow);
    group(
      () => group(() => bird(0, -10.4, .42, id: 'lime'), y: 6, angle: bow),
      x: 25,
      y: 1,
      sx: -1,
    );
    bird(0, -15, .6);
    ribbon(
      'TOP OF THE FLOCK',
      y: 26.5,
      w: 88,
      h: 13,
      col: _plum,
      ink: _gold,
      size: 8.4,
      spacing: .5,
    );
  }, angle: -4);

  void back(String id) {
    // Ray backdrops belong to the existing shared ray masters (O98). They
    // are supplied by the host via CardStickerArt.paint's paintRays seam.
    if (id == 's_unstop') {
      final u = _clamp((t % 2.8 - .42) / .45);
      if (u > 0 && u < 1) {
        circle(-2, -12, 8 + u * 30, _paleGold.withValues(alpha: (1 - u) * .54));
      }
    }
    if (id == 's_fireworks') {
      for (final (bx, by, col, off) in [
        (-20.0, -16.0, const Color(0xFFFF4FB7), 0.0),
        (19.0, -22.0, _gold, .6),
        (2.0, -6.0, _blue, 1.2),
      ]) {
        final u = ((t + off) % 1.8) / 1.8;
        if (u > .72) continue;
        final v = _out(u / .72),
            r1 = 6 + v * 20,
            r0 = r1 * .5 * v,
            op = 1 - u / .72;
        for (var i = 0; i < 12; i++) {
          final a = i / 12 * _tau + off;
          line(
            [
              bx + math.cos(a) * r0,
              by + math.sin(a) * r0,
              bx + math.cos(a) * r1,
              by + math.sin(a) * r1,
            ],
            col.withValues(alpha: op),
            2.4,
          );
          if (i % 3 == 0) {
            star(
              bx + math.cos(a) * (r1 + 3),
              by + math.sin(a) * (r1 + 3) + v * 4,
              2.4 * op,
              _white,
              a,
            );
          }
        }
        circle(bx, by, (1 - v) * 7, _white.withValues(alpha: op));
      }
    }
  }

  void fx(String id) {
    if (id == 's_zoom') {
      group(() {
        for (var i = 0; i < 3; i++) {
          final u = (t * 2.2 + i / 3) % 1;
          rect(
            -46 - u * 16,
            -9 + i * 7.0,
            14 * (1 - u),
            2,
            _plum.withValues(alpha: .8 * (1 - u)),
          );
        }
      }, angle: -30);
    }
    if (id == 's_piggy') {
      for (var i = 0; i < 3; i++) {
        final u = (t % 2.2 - .15 - i * .18) / .9;
        if (u <= 0 || u >= 1) continue;
        alpha(
          1 - math.pow(u, 3).toDouble(),
          () => group(
            () => coin(0, 0, 4.6),
            x: (i - 1) * 16 * u + 2,
            y: -17 - 36 * u + 44 * u * u,
            angle: u * 400,
          ),
        );
      }
    }
    if (id == 's_disco') {
      const colors = [
        _pink,
        _blue,
        _gold,
        Color(0xFF7CB342),
        Color(0xFF9B30D9),
      ];
      for (var i = 0; i < 10; i++) {
        final a = i / 10 * _tau + t * 1.1, r = 31.0 + (i % 2) * 4;
        rect(
          math.cos(a) * r - 1.8,
          math.sin(a) * r * .8 - 6,
          3.6,
          3.6,
          colors[i % 5].withValues(
            alpha: .45 + .55 * math.max(0.0, math.sin(t * 6 + i * 1.7)),
          ),
        );
      }
    }
    if (id == 's_unstop') {
      final clock = t % 2.8, a = clock - .42;
      if (a > 0 && a < .9) {
        for (var i = 0; i < 6; i++) {
          final ang =
                  -math.pi * .15 - i * .38 + (_hash(i.toDouble()) - .5) * .3,
              sp = 60 + _hash(i + 3.0) * 40;
          final x = -2 + math.cos(ang) * sp * a * (i.isOdd ? 1 : -.6),
              y = -8 + math.sin(ang) * sp * a + 120 * a * a,
              r = (3 + _hash(i + 7.0) * 2.5) * (1 - a / .9 * .4);
          alpha(
            1 - a / .9,
            () => group(
              () => poly([
                -r,
                r * .7,
                0,
                -r,
                r,
                r * .7,
              ], i.isOdd ? const Color(0xFF8A8A8A) : const Color(0xFF6E6E6E)),
              x: x,
              y: y,
              angle: a * 500 + i * 60,
            ),
          );
        }
        if (a < .16) star(-2, -12, (1 - a / .16) * 16, _white, .4);
      }
      if (clock < .42 || (clock > .42 && clock < 2.3)) {
        final k = clock < .42 ? 1 : .6;
        for (var i = 0; i < 3; i++) {
          final u = (t * 3 + i / 3) % 1,
              bx = clock < .42
                  ? _lerp(-50, -2, math.pow(clock / .42, 2).toDouble())
                  : 20.0;
          rect(
            bx - 22 - u * 14,
            (clock < .42 ? -17.0 : -30) + i * 5,
            10 * (1 - u),
            1.8,
            _plum.withValues(alpha: .75 * (1 - u) * k),
          );
        }
      }
    }
    if (id == 's_flawless') {
      final sw = (t % 2.6) / 1.1;
      if (sw < 1) {
        final x = -34 + sw * 68;
        poly([
          x,
          -26,
          x + 5,
          -26,
          x - 5,
          6,
          x - 10,
          6,
        ], _white.withValues(alpha: math.sin(sw * math.pi) * .8));
      }
      for (var i = 0; i < 3; i++) {
        final ph = (t * .8 + i / 3) % 1;
        star(
          <double>[-24, 22, 4][i],
          <double>[-28, -22, 6][i],
          1 + math.sin(ph * math.pi) * 4.5,
          _white,
          t,
        );
      }
      const colors = [
        Color(0xFFFF5252),
        _gold,
        Color(0xFFFFEB3B),
        Color(0xFF69F0AE),
        Color(0xFF40C4FF),
        Color(0xFFB388FF),
      ];
      for (var i = 0; i < 6; i++) {
        final a = i / 6 * _tau + t * .9, r = 36 + math.sin(t * 2 + i) * 3;
        rect(
          math.cos(a) * r - 1.6,
          -12 + math.sin(a) * r * .7 - 1.6,
          3.2,
          3.2,
          colors[i].withValues(
            alpha: .4 + .6 * math.max(0.0, math.sin(t * 5 + i * 1.3)),
          ),
        );
      }
    }
    if (id == 's_topflock') {
      final clock = t % 3.2,
          d = _clamp(clock / .55),
          land = clock - .55,
          op = clock > 2.95 ? 1 - _clamp((clock - 2.95) / .25) : 1.0;
      final cy = clock < .55
          ? _lerp(-62, -27, d * d)
          : -27 - (land < .3 ? math.sin(land / .3 * math.pi) * 3 : 0.0);
      alpha(op, () => crown(0, cy, .8));
      if (land > 0 && land < .5) {
        for (var i = 0; i < 6; i++) {
          final a = -math.pi / 2 + (i - 2.5) * .42, r = 6 + land * 44;
          star(
            math.cos(a) * r,
            -30 + math.sin(a) * r * .7,
            3 * (1 - land / .5),
            i.isOdd ? _white : _gold,
            land * 6,
          );
        }
      }
      // Confetti is rendered by the shared ConfettiBurst master below.
      final confetti = ConfettiBurst.rain(
        count: 8,
        width: 80,
        left: -40,
        random: math.Random(26),
      );
      final elapsed = t % ConfettiBurst.rainLife;
      final steps = (elapsed * 60).floor();
      for (var i = 0; i < steps; i++) {
        confetti.update(1 / 60);
      }
      confetti.update(elapsed - steps / 60);
      c.save();
      c.clipRect(const Rect.fromLTRB(-52, -55, 52, 38));
      confetti.render(c);
      c.restore();
    }
  }
}
