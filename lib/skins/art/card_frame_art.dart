import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../run/effects/collect_art.dart';
import '../../run/effects/spike_teeth.dart';
import '../look.dart';
import 'art_paint.dart';
import 'bird_art.dart' show BirdSpec, paintBirdBody, paintBirdFace;
import 'look_painter.dart';
import 'hoop_painter.dart';
import 'shapes.dart';

/// Shared vector frame master for shop, VS intro, HUD and leaderboard (F9/O82).
/// Coordinates follow versus_cards.html's 52-unit avatar. The ornaments use
/// compact geometry so the complete silhouettes fit the HUD's 7 pt allowance.
/// Call back → avatar → front. [t] is elapsed *game* seconds, supplied by the
/// host: retaining it on pause retains every animation phase. No clock is read.
abstract final class CardFrameArt {
  static const ids = <String>[
    'f_bubblegum',
    'f_tape',
    'f_checker',
    'f_eggshell',
    'f_stitch',
    'f_hazard',
    'f_spikes',
    'f_feathers',
    'f_hoops',
    'f_pinball',
    'f_deepsea',
    'f_neon',
    'f_laurel',
    'f_magma',
    'f_storm',
    'f_wings',
    'f_orbit',
    'pecking',
    'roost',
    'prey',
  ];

  static const animatedIds = <String>{
    'f_eggshell',
    'f_feathers',
    'f_hoops',
    'f_pinball',
    'f_deepsea',
    'f_neon',
    'f_magma',
    'f_storm',
    'f_wings',
    'f_orbit',
    'pecking',
    'roost',
    'prey',
  };

  /// Maximum outward reach, capped at 7 logical points even for large previews.
  static double outset(double size) => math.min(7, size * 9.5 / 52);

  static void paintBack(
    Canvas canvas,
    String id, {
    required double size,
    double t = 0,
  }) => _paint(canvas, id, size, t, true);

  static void paintFront(
    Canvas canvas,
    String id, {
    required double size,
    double t = 0,
  }) => _paint(canvas, id, size, t, false);

  static void _paint(Canvas c, String id, double size, double t, bool back) {
    if (size <= 0 || !size.isFinite || !ids.contains(id)) return;
    c.save();
    c.scale(size / 52);
    // Keep the avatar at its requested size while scaling only the decoration
    // envelope for previews larger than the 38 pt HUD reference.
    final art = _Frame(
      c,
      t.isFinite ? t : 0,
      math.min(1, 7 / (size / 52 * 9.5)),
    );
    if (back) {
      art.back(id);
    } else {
      art.front(id);
    }
    c.restore();
  }
}

/// CustomPaint adapter. [size] is the avatar side, [centre] is in local widget
/// coordinates (defaults to its centre). Hosts must leave room for [outset].
class CardFramePainter extends CustomPainter {
  const CardFramePainter({
    required this.id,
    required this.avatarSize,
    this.t = 0,
    this.back = false,
    this.centre,
  });
  final String id;
  final double avatarSize;
  final double t;
  final bool back;
  final Offset? centre;
  double get outset => CardFrameArt.outset(avatarSize);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final p = centre ?? size.center(Offset.zero);
    canvas.translate(p.dx, p.dy);
    if (back) {
      CardFrameArt.paintBack(canvas, id, size: avatarSize, t: t);
    } else {
      CardFrameArt.paintFront(canvas, id, size: avatarSize, t: t);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CardFramePainter oldDelegate) =>
      id != oldDelegate.id ||
      avatarSize != oldDelegate.avatarSize ||
      back != oldDelegate.back ||
      centre != oldDelegate.centre ||
      (CardFrameArt.animatedIds.contains(id) && t != oldDelegate.t);
}

class _Frame {
  _Frame(this.c, this.t, this.envelope);
  final Canvas c;
  final double t, envelope;
  static const h = 26.0;
  static const gold = artGold;
  static Color col(int rgb) => Color(0xFF000000 | rgb);

  // Responsive decoration coordinates leave the avatar interior unchanged.
  double _q(double v) =>
      v.abs() <= h ? v : v.sign * (h + (v.abs() - h) * envelope);
  Offset pt(double x, double y) => Offset(_q(x), _q(y));
  void line(
    List<double> xy,
    int rgb,
    double w, {
    double alpha = 1,
    List<double>? dash,
  }) {
    final p = Path()..moveTo(_q(xy[0]), _q(xy[1]));
    for (var i = 2; i < xy.length; i += 2) {
      p.lineTo(_q(xy[i]), _q(xy[i + 1]));
    }
    c.drawPath(
      dash == null ? p : ArtPaint.dashed(p, dash, 0),
      Paint()
        ..color = col(rgb).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * envelope,
    );
  }

  void poly(List<double> xy, int rgb, {double alpha = 1}) {
    c.drawPath(
      polyPath([for (var i = 0; i < xy.length; i++) _q(xy[i])]),
      Paint()..color = col(rgb).withValues(alpha: alpha),
    );
  }

  void rect(double x, double y, double w, double ht, int rgb) => c.drawRect(
    Rect.fromPoints(pt(x, y), pt(x + w, y + ht)),
    Paint()..color = col(rgb),
  );
  void dot(double x, double y, double r, int rgb, {double alpha = 1}) =>
      c.drawOval(
        Rect.fromPoints(pt(x - r, y - r), pt(x + r, y + r)),
        Paint()..color = col(rgb).withValues(alpha: alpha),
      );
  void square(
    double o,
    int rgb,
    double w, {
    double alpha = 1,
    double radius = 0,
    List<double>? dash,
  }) {
    final p = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(-_q(o), -_q(o), _q(o), _q(o)),
          Radius.circular(radius),
        ),
      );
    c.drawPath(
      dash == null ? p : ArtPaint.dashed(p, dash, 0),
      Paint()
        ..color = col(rgb).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * envelope,
    );
  }

  void star(
    double x,
    double y,
    double r,
    int rgb, {
    bool four = false,
    double rot = 0,
  }) {
    if (four) {
      c.save();
      final p = pt(x, y);
      c.translate(p.dx, p.dy);
      c.rotate(rot);
      CollectArt.star4(c, Offset.zero, r * envelope, col(rgb));
      c.restore();
    } else {
      final pts = <double>[];
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + rot + i * math.pi / 5,
            q = i.isEven ? r : r * .45;
        pts.addAll([x + math.cos(a) * q, y + math.sin(a) * q]);
      }
      poly(pts, rgb);
    }
  }

  (double, double, double, double) per(double u, double o) {
    final a = ((u % 1 + 1) % 1) * 4, v = (a - a.floor()) * 2 * o - o;
    return switch (a.floor()) {
      0 => (v, -o, 0, -1),
      1 => (o, v, 1, 0),
      2 => (-v, o, 0, 1),
      _ => (-o, -v, -1, 0),
    };
  }

  List<double> rot(
    List<double> p,
    double a,
    double x,
    double y, {
    double mirror = 1,
  }) => [
    for (var i = 0; i < p.length; i += 2) ...[
      x + mirror * (p[i] * math.cos(a) - p[i + 1] * math.sin(a)),
      y + p[i] * math.sin(a) + p[i + 1] * math.cos(a),
    ],
  ];
  static final _perchedBirds = [
    for (final rgb in [
      0x4A0029,
      0x7A0044,
      0xB0006B,
      0xEC008C,
      0xFF4FB7,
      0xFF8AC8,
    ])
      BirdSpec(
        'card_perch',
        'sq',
        c: col(rgb),
        d: col(rgb).withValues(alpha: .8),
      ),
  ];

  void bird(
    double x,
    double y,
    double scale, {
    double angle = 0,
    String id = 'classic',
    BirdSpec? spec,
  }) {
    c.save();
    final p = pt(x, y);
    c.translate(p.dx, p.dy);
    c.rotate(angle);
    c.scale(scale * envelope);
    if (spec == null) {
      LookPainter.paint(
        c,
        Look(bird: id),
        t: t,
        flap: math.sin(t * 9) > 0,
      );
    } else {
      c.translate(-22, -18);
      paintBirdBody(c, spec, t);
      paintBirdFace(c, spec, t, math.sin(t * 9) > 0);
    }
    c.restore();
  }

  void plaque(String label, double o) {
    rect(-8, o - 4, 16, 8, 0xFFB529);
    final p = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Opificio Neue',
          fontSize: 7 * envelope,
          color: artPlum,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(c, pt(0, o) - Offset(p.width / 2, p.height / 2));
    p.dispose();
  }

  void cornerGems(double o) {
    for (final x in [-o, o]) {
      for (final y in [-o, o]) {
        c.drawPath(
          octPath(
            _q(x) - 2.7 * envelope,
            _q(y) - 2.7 * envelope,
            5.4 * envelope,
            5.4 * envelope,
            1.4 * envelope,
          ),
          Paint()..color = gold,
        );
      }
    }
  }

  void back(String id) {
    switch (id) {
      case 'f_feathers':
        for (final sx in [-1.0, 1.0]) {
          for (final sy in [-1.0, 1.0]) {
            final base = math.atan2(sy, sx) + math.pi / 2;
            for (var i = 0; i < 3; i++) {
              final a = base + (i - 1) * .5 + math.sin(t * 2 + i + sx) * .05;
              final p = rot(
                [0, 0, 2.5, -2, 2.3, -7, 0, -10, -2.3, -7, -2.5, -2],
                a,
                sx * 25,
                sy * 25,
              );
              poly(p, [0x26C6DA, 0xFF4FB7, 0xFFB529][i]);
              line(
                rot([0, 0, 0, -9], a, sx * 25, sy * 25),
                0xFFFFFF,
                .65,
                alpha: .7,
              );
            }
          }
        }
      case 'f_wings':
        for (final sd in [-1.0, 1.0]) {
          for (var i = 0; i < 3; i++) {
            final len = 9.5 - i * 1.6,
                a = -.6 + i * .38 - math.sin(t * 4.2) * .16 * (1 - i * .3);
            poly(
              rot(
                [0, -2.5, len * .72, -2.5, len, 0, len * .72, 2.5, 0, 2.5],
                a,
                sd * 25,
                -6 + i * 6,
                mirror: sd,
              ),
              [0xFFC233, 0xFFE9A6, 0xC98A00][i],
            );
          }
        }
      case 'f_orbit':
        orbit(false);
      case 'roost':
        for (var i = 0; i < 3; i++) {
          poly(
            rot(
              [0, -2, 7, -2.5, 11.0 - i, 0, 7, 2.5, 0, 2],
              -2.2 - i * .32 + math.sin(t * 2.4 + i) * .04,
              -24,
              -25,
            ),
            [0x0D47A1, 0x1B5E20, 0x123A8C][i],
          );
        }
      case 'prey':
        // The hawk's head turns above the steel rim; hooked beak and brow.
        final a = math.sin(t * 1.3) * .12;
        poly(
          rot([-7, 2, -7, -3, -4, -7, 2, -7, 5, -3, 4, 2], a, -2, -28),
          0x4E342E,
        );
        poly(rot([-5, -1, -4, -5, 0, -6, 2, -2], a, -2, -28), 0x6D4C41);
        poly(rot([3, -4, 9, -2, 8, 1, 6, -1, 3, -1], a, -2, -28), 0xFFC233);
        dot(0, -31, 1.7, 0xFFB529);
        dot(.4, -31, .8, 0x111111);
        poly(rot([-3, -6, 3, -4, 2, -3, -3, -4], a, -2, -28), 0x2B1B17);
    }
  }

  void front(String id) {
    switch (id) {
      case 'f_bubblegum':
        const o = 28.6;
        square(o, 0xFF7EC7, 5.2);
        for (var i = 0; i < 9; i++) {
          final u = -o + (i + .5) * 2 * o / 9;
          for (final p in [(u, -o), (u, o), (-o, u), (o, u)]) {
            dot(p.$1, p.$2, 1.15, 0xFFFFFF);
          }
        }
      case 'f_tape':
        square(27.4, 0x29B6F6, 2.8);
        for (final p in [(-25.0, -25.0), (25.0, 25.0)]) {
          poly(
            rot([-8, -3, 8, -3, 8, 3, -8, 3], -math.pi / 4, p.$1, p.$2),
            0x81D4FA,
            alpha: .92,
          );
          for (var i = 0; i < 4; i++) {
            final x = -7 + i * 4.0;
            poly(
              rot(
                [x, -3, x + 1.5, -3, x + 1.5, 3, x, 3],
                -math.pi / 4,
                p.$1,
                p.$2,
              ),
              0xFFFFFF,
              alpha: .5,
            );
          }
        }
      case 'f_checker':
        const d = 6.5;
        for (var i = 0; i < 10; i++) {
          for (var j = 0; j < 10; j++) {
            if (i > 0 && j > 0 && i < 9 && j < 9) continue;
            rect(
              -32.5 + i * d,
              -32.5 + j * d,
              d + .1,
              d + .1,
              (i + j).isEven ? 0x222222 : 0xFFFFFF,
            );
          }
        }
        square(32.5, 0x222222, 1);
      case 'f_eggshell':
        const o = 29.0;
        square(o, 0xCDB27E, 6.6);
        square(o, 0xF6EBD2, 5);
        for (var i = 0; i < 22; i++) {
          final (x, y, nx, ny) = per(artHash(i + 40), o);
          final j = (artHash(i + 80) - .5) * 3;
          rect(x + nx * j - .8, y + ny * j - .8, 1.6, 1.6, 0xB89A66);
        }
        line(
          [
            for (var i = 0; i <= 8; i++) ...[
              -o * .3 + i * o * .11,
              -o + (i.isOdd ? 1.9 : -1.9),
            ],
          ],
          0x8D6E43,
          1,
        );
        poly(
          rot(
            [-3, 1, -1.5, -1.5, 2, -2, 3, 1, 1.5, 0, 0, 1.5],
            (.28 + math.sin(t * 2) * .07),
            21,
            -33,
          ),
          0xCDB27E,
        );
        poly(
          rot(
            [-2.6, .8, -1.3, -1.3, 1.8, -1.7, 2.7, .8, 1.3, 0, 0, 1.3],
            (.28 + math.sin(t * 2) * .07),
            21,
            -33,
          ),
          0xF6EBD2,
        );
      case 'f_stitch':
        const o = 29.0;
        square(o, 0xF48FB1, 6.4);
        square(o + 3.2, 0xE0679A, .8);
        square(o - 3.2, 0xE0679A, .8);
        square(o, 0xFFFFFF, 1.2, dash: [3, 2.2]);
        dot(-o, -o, 4, 0xC98A00);
        dot(-o, -o, 3.2, 0xFFB529);
        for (final x in [-1.0, 1.0]) {
          for (final y in [-1.0, 1.0]) {
            dot(-o + x * 1.1, -o + y * 1.1, .6, 0x8A5A00);
          }
        }
      case 'f_hazard':
        const a = 32.4, b = 26.0;
        c.save();
        final path = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Rect.fromLTRB(-_q(a), -_q(a), _q(a), _q(a)))
          ..addRect(Rect.fromLTRB(-b, -b, b, b));
        c.clipPath(path);
        rect(-a, -a, 2 * a, 2 * a, 0xFFD400);
        for (var x = -3 * a; x < a; x += 7) {
          poly([
            x,
            -a,
            x + 3.5,
            -a,
            x + 3.5 + 2 * a,
            a,
            x + 2 * a,
            a,
          ], 0x222222);
        }
        c.restore();
        square(a, 0x222222, .8);
        square(b, 0x222222, .8);
      case 'f_spikes':
        final o = _q(28);
        for (var side = 0; side < 4; side++) {
          c.save();
          c.rotate(side * math.pi / 2);
          // The run's tooth master, turned outwards and fitted to four teeth.
          c.clipRect(Rect.fromLTRB(-o, -o - 7.4 * envelope, o, -o + .1));
          c.translate(-o, -o);
          c.scale(
            2 * o / (4 * SpikeTeethPainter.period),
            -7.4 * envelope / SpikeTeethPainter.depth,
          );
          SpikeTeethPainter.paint(
            c,
            width: 4 * SpikeTeethPainter.period,
            reach: SpikeTeethPainter.depth,
            color: col(0x808080),
          );
          c.restore();
        }
        square(28, 0x808080, 4);
      case 'f_feathers':
        square(27.4, 0x26C6DA, 2.8);
      case 'f_hoops':
        hoops();
      case 'f_pinball':
        const o = 29.0;
        square(o, 0x5F6B72, 7);
        square(o, 0xC3CDD3, 5);
        square(o - 1.4, 0xF4F7F9, 1);
        for (var i = 0; i < 16; i++) {
          final (x, y, _, _) = per(i / 16 + 1 / 32, o);
          final on = ((t * 8).floor() - i) % 4 == 0,
              rgb = i.isOdd ? 0xFFEB3B : 0xFF4FB7;
          if (on) dot(x, y, 3.4, rgb, alpha: .35);
          dot(x, y, 1.9, 0x4D575D);
          dot(x, y, 1.6, on ? rgb : 0x8A969C);
        }
        for (final x in [-o, o]) {
          for (final y in [-o, o]) {
            final r = t % 2.4 < .12 ? 5.4 : 4.6;
            dot(x, y, r, 0xE53935);
            dot(x, y, r * .56, 0xFFFFFF);
            dot(x, y, r * .3, 0xE53935);
          }
        }
      case 'f_deepsea':
        const o = 29.0;
        final pts = <double>[];
        for (var i = 0; i <= 96; i++) {
          final u = i / 96;
          final (x, y, nx, ny) = per(u, o);
          final w = math.sin(u * 48 * math.pi + t * 3) * 1.1;
          pts.addAll([x + nx * w, y + ny * w]);
        }
        line(pts, 0x00796B, 7);
        line(pts, 0x26C6DA, 4.6);
        line(pts, 0xB2EBF2, .9, alpha: .8);
        for (final sd in [-1, 1]) {
          for (var i = 0; i < 4; i++) {
            final u = (t * .32 + i / 4 + (sd > 0 ? .12 : 0)) % 1,
                y = 29 - u * 61,
                x = sd * 33.0 + math.sin(t * 3 + i * 2) * .4,
                r = 1.0 + i % 2 * .5;
            dot(x, y, r + .4, 0x4DD0E1, alpha: 1 - u * .7);
            dot(x, y, r, 0xB2EBF2, alpha: .6);
            dot(x - r * .35, y - r * .35, r * .3, 0xFFFFFF);
          }
        }
        star(-o, o, 5.4, 0xFF7043, rot: .5 + math.sin(t * 1.5) * .14);
        star(-o, o, 2.4, 0xFFAB91, rot: .5);
      case 'f_neon':
        final fl = math.sin(t * 17) + math.sin(t * 5.3 + 1) > 1.55 ? .35 : 1.0;
        square(30, 0xFF4FB7, 9, alpha: .22 * fl, radius: 5);
        square(30, 0xFF4FB7, 3.4, alpha: fl, radius: 5);
        square(30, 0xFFE3F3, 1.2, alpha: fl, radius: 5);
        square(26.6, 0x00E5FF, 6, alpha: .18, radius: 5);
        square(26.6, 0x00E5FF, 2.2, radius: 5);
        square(26.6, 0xE0FFFF, .8, radius: 5);
        rect(-3, -32.2, 6, 4.4, 0x555555);
      case 'f_laurel':
        const o = 28.4;
        square(o, 0xC98A00, 5.4);
        square(o, 0xFFC233, 3.4);
        square(27.4, 0xFFE9A6, .9);
        for (final sd in [-1.0, 1.0]) {
          for (var i = 0; i < 6; i++) {
            final u = i / 5,
                x = sd * (32 - math.sin(u * math.pi) * 1.5),
                y = 24 - u * 42.64;
            poly(
              rot([0, -4, 2, 0, 0, 2.5, -2, 0], sd * (.5 - u * .3), x, y),
              i.isOdd ? 0x2E7D32 : 0x43A047,
            );
          }
          line([sd * 31.5, 28, sd * 31, -15.6], 0x2E7D32, 1.2);
        }
        star(0, 29, 6, 0xFFB529);
        star(0, 29, 3, 0xFFE9A6);
      case 'f_magma':
        const o = 29.0;
        final gl = .55 + .45 * math.sin(t * 2.4), pts = <double>[];
        square(o, 0x1B0F0C, 7.4);
        square(o, 0x3E2723, 5.4);
        for (var i = 0; i <= 48; i++) {
          final (x, y, nx, ny) = per(i / 48, o);
          final j = (i.isOdd ? 1 : -1) * (.6 + artHash(i) * 1.4);
          pts.addAll([x + nx * j, y + ny * j]);
        }
        line(pts, 0xFF6D00, 2.4, alpha: gl);
        line(pts, 0xFFD180, .8, alpha: gl);
        for (var i = 0; i < 7; i++) {
          final u = (t * .45 + i / 7) % 1,
              x = -o + artHash(i + 3) * 2 * o + math.sin(t * 2 + i) * 2,
              y = -31 - u * 3.2;
          dot(x, y, .9, i.isOdd ? 0xFFB529 : 0xFF7A1A, alpha: 1 - u);
        }
      case 'f_storm':
        storm();
      case 'f_wings':
        square(29, 0xC98A00, 6.4);
        square(29, 0xFFC233, 4.4);
        square(29.9, 0xFFE9A6, 1.3);
        poly([
          -7,
          -29,
          -7,
          -33.5,
          -3.5,
          -31,
          0,
          -35,
          3.5,
          -31,
          7,
          -33.5,
          7,
          -29,
        ], 0xFFB529);
        rect(-7, -29, 14, 1.6, 0xE69500);
        rect(-1.5, -33.5, 3, 3, 0xE53935);
        for (var i = 0; i < 4; i++) {
          star(
            i == 0 || i == 3 ? -29 : 29,
            i < 2 ? -29 : 29,
            1 + 3 * math.max(0, math.sin(t * 3 + i * 1.6)),
            0xFFFFFF,
            four: true,
            rot: t,
          );
        }
      case 'f_orbit':
        const o = 29.0;
        square(o, 0x120634, 7);
        square(o, 0x2A1260, 5);
        square(o - 2.3, 0x7C4DFF, .8);
        for (var i = 0; i < 12; i++) {
          final (x, y, nx, ny) = per(artHash(i + 20), o);
          final j = (artHash(i + 60) - .5) * 3;
          star(
            x + nx * j,
            y + ny * j,
            1 + math.max(0, math.sin(t * 3 + i * 1.3)) * 1.8,
            i % 3 != 0 ? 0xFFFFFF : 0xFFE082,
            four: true,
            rot: t,
          );
        }
        orbit(true);
      case 'pecking':
        const o = 28.6;
        square(o, 0x3E2723, 6);
        square(o, 0x795548, 4.4);
        square(o, 0x5D4037, 1, dash: [4, 3]);
        for (var j = 0; j < 6; j++) {
          final sc = .17 - j * .012,
              x = -25 + j * 10.0,
              p = (t * 1.4 - j * .16) % 1.6,
              angle = p < .22 ? math.sin(p / .22 * math.pi) * .66 : 0.0;
          rect(x - 1, -30, .6, 1.5, 0xFFB529);
          rect(x + .5, -30, .6, 1.5, 0xFFB529);
          bird(x, -31.8, sc, angle: angle, spec: _perchedBirds[j]);
        }
        cornerGems(o);
        plaque('10', o);
      case 'prey':
        prey();
      case 'roost':
        square(28.6, 0x4A0029, 5.6);
        square(28.6, 0x7A0044, 3.6);
        for (final p in [
          (-5.0, -31.0, 2.6),
          (0.0, -32.0, 3.0),
          (5.0, -31.0, 2.6),
        ]) {
          dot(p.$1, p.$2, p.$3, 0xE53935);
        }
        cornerGems(28.6);
        plaque('50', 28.6);
        final p = Path()
          ..moveTo(-3, _q(32.6))
          ..quadraticBezierTo(0, _q(37.6), 3, _q(32.6));
        // A compact wattle beneath the plaque, inside the 7 pt envelope.
        c.drawPath(p, Paint()..color = col(0xE53935));
    }
  }

  void hoops() {
    const o = 29.0;
    square(o, 0xFF7EC7, 1.6);
    final positions = [
      (0.0, -o, false),
      (o, 0.0, true),
      (0.0, o, false),
      (-o, 0.0, true),
    ];
    void halves(bool front) {
      for (final (x, y, hz) in positions) {
        c.save();
        final p = pt(x, y);
        c.translate(p.dx, p.dy);
        if (hz) c.rotate(math.pi / 2);
        HoopPainter.paintHalf(
          c,
          'sky',
          Offset.zero,
          5.6 * envelope,
          t,
          front: front,
          rx: 2.1 * envelope,
          lineWidth: 1.6 * envelope,
        );
        c.restore();
      }
    }

    halves(false);
    final u = t * .16 % 1;
    for (var j = 3; j > 0; j--) {
      final (x, y, _, _) = per(u - .012 * j, o);
      dot(x, y, 1.3 - j * .25, 0xFFB3DA, alpha: 1 - j * .25);
    }
    final (x, y, _, _) = per(u, o);
    bird(x, y, .15, angle: (u * 4).floor() * math.pi / 2);
    halves(true);
  }

  void storm() {
    const o = 28.0;
    final ph = t % 3.2, fl = ph < .16;
    square(o, 0x455A64, 3);
    for (var i = 0; i < 5; i++) {
      final x = -o + (i + .5) * 2 * o / 5,
          u = (t * 1.8 + artHash(i + 9)) % 1,
          y = o + 3 + u * 2;
      line([x, y, x - 1.2, y + 2], 0x4FC3F7, 1, alpha: 1 - u);
    }
    for (var layer = 0; layer < 2; layer++) {
      for (var i = 0; i < 20; i++) {
        final (x, y, nx, ny) = per(i / 20 + .025, o);
        final r = 3.2 + artHash(i) * 1.2;
        dot(
          x + nx,
          y + ny + (layer == 0 ? 1 : -.4),
          r * (layer == 0 ? 1 : .82),
          fl
              ? (layer == 0 ? 0xB0BEC5 : 0xFFFFFF)
              : (layer == 0 ? 0x546E7A : 0x90A4AE),
        );
      }
    }
    if (ph < .3) {
      poly([29, -10, 33, -10, 30, -4, 34, -4, 27, 7, 29, 0, 26, 0], 0xFFEB3B);
    }
  }

  void orbit(bool front) {
    // Flattened ellipse retains the behind/in-front crossing at small HUD size.
    const r = 29.8, ry = 10.0, a = -math.pi / 10;
    final pts = <double>[];
    for (var i = 0; i <= 48; i++) {
      final q = (front ? 0 : math.pi) + i * math.pi / 48;
      pts.addAll(rot([math.cos(q) * r, math.sin(q) * ry], a, 0, 0));
    }
    line(pts, 0xB39DFF, .9, alpha: .75, dash: [2, 2]);
    for (final (q, rk, rad) in [
      (t * .8, 1.0, 3.4),
      (t * .8 * 1.7 + 2.2, .82, 1.8),
    ]) {
      if ((math.sin(q) > 0) != front) continue;
      final p = rot([math.cos(q) * r * rk, math.sin(q) * ry * rk], a, 0, 0),
          x = p[0],
          y = p[1];
      if (rad > 3) {
        final ring = Rect.fromPoints(
          pt(x - 4.8, y - 1.3),
          pt(x + 4.8, y + 1.3),
        );
        c.drawOval(
          ring,
          Paint()
            ..color = col(0xC98A00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * envelope,
        );
        dot(x, y, rad, 0xFF8A65);
        dot(x + .8, y + .7, rad * .7, 0xF4511E, alpha: .55);
        dot(x - .9, y - .9, rad * .3, 0xFFCCBC);
        c.drawArc(
          ring,
          0,
          math.pi,
          false,
          Paint()
            ..color = col(0xFFE082)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8 * envelope,
        );
      } else {
        dot(x, y, rad, 0xECEFF1);
        dot(x + .4, y + .3, rad * .45, 0xB0BEC5);
      }
    }
  }

  void prey() {
    const o = 28.6;
    square(o, 0x1C262B, 6.4);
    square(o, 0x37474F, 4.6);
    for (var i = 0; i < 20; i++) {
      final (x, y, nx, ny) = per(i / 20 + .025, o);
      const d = 1.4;
      poly(
        nx != 0
            ? [x - nx * d, y - d * 1.4, x + nx * d, y, x - nx * d, y + d * 1.4]
            : [x - d * 1.4, y - ny * d, x, y + ny * d, x + d * 1.4, y - ny * d],
        0x607D8B,
      );
    }
    for (final sx in [-1.0, 1.0]) {
      for (final sy in [-1.0, 1.0]) {
        final x = sx * 30.2, y = sy * 30.2;
        for (final (dx, dy) in [(-sx, 0.0), (0.0, -sy), (-sx, -sy)]) {
          final a = math.atan2(dy, dx);
          poly(
            rot([0, -2, 4, -1.7, 6, 0, 5, 3, 4, 1.2, 0, 1.2], a, x, y),
            0x8A5A00,
          );
          poly(
            rot([0, -1, 4, -1, 5, 0, 4.5, 1.5, 3.7, .4, 0, .4], a, x, y),
            0xFFB529,
          );
        }
        dot(x, y, 3.2, 0xC98A00);
        dot(x - .8, y - .8, 1.4, 0xFFE082);
      }
    }
    for (var i = 0; i < 5; i++) {
      final x = -9 + i * 4.5, y = 33.0;
      poly([
        x - 1,
        y + 1.8,
        x + 1.6,
        y - 1.8,
        x + 3,
        y - 1.8,
        x + .4,
        y + 1.8,
      ], (t * 2.5).floor() % 6 > i ? 0xE53935 : 0x7F2A2A);
    }
    if (t % 2.6 < .3) {
      star(
        .5,
        -31.5,
        1 + 2.5 * math.sin(t % 2.6 / .3 * math.pi),
        0xFFFFFF,
        four: true,
      );
    }
  }
}
