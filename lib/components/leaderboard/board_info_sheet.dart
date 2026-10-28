import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart' show bleedRectFor;
import '../../game/sound.dart';
import '../../run/config/puzzle_config.dart';
import '../../run/effects/coin_icon.dart';
import '../../run/effects/coin_popup.dart';
import '../../run/effects/spike_teeth.dart';
import '../../run/hoops/ring_painter.dart';
import '../../run/pickups/feather_pickup.dart';
import '../../run/pickups/puzzle_piece_pickup.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/art/card_frame_art.dart';
import '../../skins/art/card_name_art.dart';
import '../../skins/look.dart';
import '../noads_celebration.dart';
import '../ui/mystery_box.dart';

/// O59/O67: a tap-anywhere picture guide over the board.
class BoardInfoSheet extends PositionComponent with TapCallbacks {
  BoardInfoSheet({
    required double height,
    required this.playSound,
    required this.onClose,
    required this.motion,
  }) : super(size: Vector2(320, height), priority: 2000000);

  final void Function(Sfx) playSound;
  final VoidCallback onClose;
  final bool Function() motion;
  double elapsed = 0;
  double _idle = 0;
  int _pops = 0;
  bool _closed = false;
  bool _finished = false;
  double _closing = 0;
  Image? coin;
  final CoinPopup _coinPopup = CoinPopup();
  final NoAdsCelebrationRays _rays = NoAdsCelebrationRays(
    rayCenter: Offset.zero,
    motion: () => false,
  );
  static const captions = [
    'FLY AND SCORE',
    'TOP THE BOARD',
    'WIN GIFT BOXES',
    'BEAT THE RECORDS',
  ];
  static const pink = Color(0xffec008c),
      gold = Color(0xffffb529),
      plum = Color(0xff2a0f22);

  /// The run picture uses the same geometry at every screen height.
  double get guideScale => math.min(1, size.y / 711);
  Rect get runPictureRect => Rect.fromLTWH(
    160 + (18 - 160) * guideScale,
    142 * guideScale,
    136 * guideScale,
    96 * guideScale,
  );

  @override
  bool containsLocalPoint(Vector2 point) =>
      bleedRectFor(this, size.y).contains(Offset(point.x, point.y));

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    playSound(Sfx.skDialog);
    coin = await CoinIcon.load(findGame()!.images);
    _coinPopup.coinImage = coin;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_closed) {
      _closing += dt;
      if (_closing >= .22 && !_finished) {
        _finished = true;
        onClose();
      }
      return;
    }
    elapsed += dt;
    if (motion()) _idle += dt;
    while (_pops < 4 && elapsed >= .5 + .6 * _pops) {
      playSound(Sfx.vsPop);
      _pops++;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    playSound(Sfx.skClose);
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    close();
  }

  static double _progress(double time, double start, double duration) =>
      ((time - start) / duration).clamp(0.0, 1.0);
  static double _back(double u) {
    const s = 1.70158;
    final t = u - 1;
    return 1 + (s + 1) * t * t * t + s * t * t;
  }

  void _text(
    Canvas c,
    String text,
    double x,
    double y,
    double font,
    Color color, {
    double maxWidth = 290,
    Color? outline,
  }) {
    TextPainter painter(TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    if (outline != null) {
      final border = painter(
        TextStyle(
          fontFamily: Config.uiFont,
          fontSize: font,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeJoin = StrokeJoin.round,
        ),
      );
      border.paint(c, Offset(x - border.width / 2, y - border.height / 2));
    }
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Config.uiFont,
          fontSize: font,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    p.paint(c, Offset(x - p.width / 2, y - p.height / 2));
  }

  void _rect(Canvas c, Rect rect, Color color) =>
      c.drawRect(rect, Paint()..color = color);
  void _bird(Canvas c, double x, double y, double scale) {
    c.save();
    c.translate(x, y);
    c.scale(scale);
    LookPainter.paint(
      c,
      Look.defaults,
      t: _idle,
      flap: math.sin(_idle * 9) > 0,
    );
    c.restore();
  }

  void _fly(Canvas c) {
    c.save();
    c.clipRect(const Rect.fromLTWH(-68, -48, 136, 96));
    _rect(c, const Rect.fromLTWH(-68, -48, 136, 96), const Color(0xfff1f1f1));
    // O90: scale the actual run strips and pin the solid bands to both edges.
    c.save();
    c.translate(-68, -48);
    c.scale(136 / 320);
    SpikeTeethPainter.paint(c, width: 320, color: const Color(0xff828282));
    c.restore();
    c.save();
    c.translate(-68, 48);
    c.scale(136 / 320, -136 / 320);
    SpikeTeethPainter.paint(c, width: 320, color: const Color(0xff828282));
    c.restore();
    RingPainter.paintHalf(
      c,
      centre: const Offset(8, 0),
      opening: 52,
      front: false,
      colors: RingColors.gold,
    );
    _bird(c, -60 + (_idle % 2.4) / 2.4 * 120, -3 * math.sin(_idle * 2), .7);
    RingPainter.paintHalf(
      c,
      centre: const Offset(8, 0),
      opening: 52,
      front: true,
      colors: RingColors.gold,
    );
    final phase = (_idle % 2.4 - 1.25) / 1.1;
    if (phase > 0 && phase < 1) {
      c.save();
      c.translate(24, 18);
      c.scale(.5);
      _coinPopup.renderAt(c, phase);
      c.restore();
    }
    c.restore();
  }

  void _climb(Canvas c, double local) {
    _rect(c, const Rect.fromLTWH(-70, -48, 140, 96), const Color(0xffffffff));
    final rise = _progress(local, .55, .5);
    for (var i = 0; i < 3; i++) {
      final y = i == 1
          ? -13 + rise * 30
          : i == 2
          ? 17 - rise * 30
          : -43.0;
      c.save();
      if (i == 2) {
        c.translate(0, y + 13);
        c.scale(1 + math.sin(rise * math.pi) * .08);
        c.translate(0, -y - 13);
        if (rise > 0 && rise < 1) {
          _rect(c, Rect.fromLTWH(-62, y + 3, 128, 26), const Color(0x2E7A0044));
        }
      }
      _rect(
        c,
        Rect.fromLTWH(-64, y, 128, 26),
        i == 2 ? const Color(0xffffd9ee) : const Color(0xfff1f1f1),
      );
      if (i == 2) {
        c.drawRect(
          Rect.fromLTWH(-63, y + 1, 126, 24),
          Paint()
            ..color = pink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      final rank = i == 0
          ? 1
          : i == 1
          ? (rise > .5 ? 3 : 2)
          : (rise > .5 ? 2 : 3);
      const colors = [Color(0xffc98a00), Color(0xff8e9aa2), Color(0xffa85a24)];
      final marker = Path()
        ..moveTo(-55, y + 4)
        ..lineTo(-45, y + 4)
        ..lineTo(-41, y + 8)
        ..lineTo(-41, y + 18)
        ..lineTo(-45, y + 22)
        ..lineTo(-55, y + 22)
        ..lineTo(-59, y + 18)
        ..lineTo(-59, y + 8)
        ..close();
      c.drawPath(marker, Paint()..color = colors[rank - 1]);
      _text(c, '$rank', -50, y + 13, 11, const Color(0xffffffff));
      c.save();
      c.translate(-26, y + 13);
      CardFrameArt.paintBack(c, ['f_bubblegum', 'f_hoops', 'f_laurel'][i], size: 19, t: _idle);
      _bird(c, 0, 0, .4);
      CardFrameArt.paintFront(c, ['f_bubblegum', 'f_hoops', 'f_laurel'][i], size: 19, t: _idle);
      c.restore();
      CardNameArt.paint(c, ['n_ocean', 'n_grape', 'n_cherry'][i], ['LENA', 'SAM', 'YOU'][i], t: _idle, center: Offset(17, y + 13), fontSize: 10.5, maxWidth: 52);
      if (i == 2 && rise >= 1) {
        final cy = y + 13 - math.sin(_idle * 3.2).abs() * 3;
        final arrow = Path()
          ..moveTo(50, cy - 9)
          ..lineTo(59, cy + 1)
          ..lineTo(53.5, cy + 1)
          ..lineTo(53.5, cy + 7)
          ..lineTo(46.5, cy + 7)
          ..lineTo(46.5, cy + 1)
          ..lineTo(41, cy + 1)
          ..close();
        c.drawPath(arrow, Paint()..color = gold);
      }
      c.restore();
    }
  }

  void _gift(Canvas c) {
    c.save();
    c.clipRect(const Rect.fromLTWH(-75, -60, 150, 120));
    _rays.paintRays(c, phase: _idle * .4);
    c.restore();
    final bob = math.sin(_idle * 2.2) * 2;
    if (coin != null) CoinIcon.paint(c, coin!, Offset(-52, bob), 22);
    FeatherArt.paintAt(c, Offset(-32, -35 + bob), .8, -.3);
    c.save();
    c.translate(29, -35 - bob);
    c.scale(.55);
    PuzzleArt.paintPieceCentred(c, 0, PuzzleConfig.themes.first);
    c.restore();
    c.save();
    c.translate(55, -3 + bob);
    MysteryBox.paint(c, MysteryBoxLook.tier(MysteryBoxTier.pink), size: 27);
    c.restore();
    c.save();
    c.translate(0, 18);
    MysteryBox.paint(
      c,
      MysteryBoxLook.colours(
        gold,
        const Color(0xffc98a00),
        ribbon: pink,
        label: null,
      ),
      size: 74,
    );
    c.restore();
  }

  void _trophy(Canvas c) {
    const dark = Color(0xffe69500);
    _rect(c, const Rect.fromLTWH(-27, -8, 54, 10), pink);
    _rect(c, const Rect.fromLTWH(-17, -15, 34, 7), gold);
    _rect(c, const Rect.fromLTWH(-5, -27, 10, 12), gold);
    // The cup handles use the run's hoop master.
    c.save();
    c.translate(-30, -49);
    c.scale(.58, .5);
    RingPainter.paintBoth(
      c,
      centre: Offset.zero,
      opening: 34,
      colors: RingColors.gold,
    );
    c.restore();
    c.save();
    c.translate(30, -49);
    c.scale(.58, .5);
    RingPainter.paintBoth(
      c,
      centre: Offset.zero,
      opening: 34,
      colors: RingColors.gold,
    );
    c.restore();
    final cup = Path()
      ..moveTo(-26, -63)
      ..lineTo(26, -63)
      ..lineTo(26, -52)
      ..quadraticBezierTo(26, -30, 0, -26)
      ..quadraticBezierTo(-26, -30, -26, -52)
      ..close();
    c.drawPath(cup, Paint()..color = gold);
    c.save();
    c.clipPath(cup);
    _rect(c, const Rect.fromLTWH(8, -63, 18, 38), dark);
    c.restore();
    // Five teeth from the run strip master, scaled to the cup's 52 pt rim.
    c.save();
    c.translate(-26, -63);
    c.scale(52 / 200, -11 / 18);
    c.clipRect(const Rect.fromLTWH(0, 0, 200, 18));
    SpikeTeethPainter.paint(c, width: 200, color: pink, reach: 18);
    c.restore();
    c.save();
    c.translate(0, -46);
    c.rotate(math.pi / 4);
    _rect(c, const Rect.fromLTWH(-11, -11, 22, 22), const Color(0xffffffff));
    c.restore();
    _bird(c, 0, -46 + math.sin(_idle * 2.4), .36);
  }

  void _record(Canvas c) {
    _trophy(c);
    _rect(c, const Rect.fromLTWH(-76, 17, 152, 30), const Color(0xffffffff));
    _rect(c, const Rect.fromLTWH(-76, 17, 152, 3), gold);
    final rank = Path()..moveTo(-67, 23)..lineTo(-57, 23)..lineTo(-52, 28)..lineTo(-52, 38)..lineTo(-57, 43)..lineTo(-67, 43)..lineTo(-72, 38)..lineTo(-72, 28)..close();
    c.drawPath(rank, Paint()..color = const Color(0xFFC98A00));
    _text(c, '1', -62, 33, 12, const Color(0xFFFFFFFF));
    c.save();
    c.translate(-37, 33);
    CardFrameArt.paintBack(c, 'f_bubblegum', size: 21, t: _idle);
    _bird(c, 0, 0, .4);
    CardFrameArt.paintFront(c, 'f_bubblegum', size: 21, t: _idle);
    c.restore();
    CardNameArt.paint(c, 'n_ocean', 'LENA', t: _idle, center: const Offset(2, 33), fontSize: 10, maxWidth: 45);
    _rect(c, const Rect.fromLTWH(40, 23, 31, 20), pink);
    _text(c, '812', 55.5, 33, 11, const Color(0xFFFFFFFF));
  }

  void _arrow(Canvas c, int i, double u) {
    if (u <= 0) return;
    const points = [
      (Offset(158, 170), Offset(234, 164), Offset(234, 242)),
      (Offset(162, 318), Offset(90, 314), Offset(86, 352)),
      (Offset(160, 434), Offset(234, 428), Offset(234, 452)),
    ];
    final (a, b, d) = points[i];
    final path = Path()..moveTo(a.dx, a.dy);
    for (var n = 1; n <= 30; n++) {
      final t = u * n / 30;
      final v = 1 - t;
      path.lineTo(
        v * v * a.dx + 2 * v * t * b.dx + t * t * d.dx,
        v * v * a.dy + 2 * v * t * b.dy + t * t * d.dy,
      );
    }
    for (final pair in [(plum, 12.0), (gold, 7.0)]) {
      c.drawPath(
        path,
        Paint()
          ..color = pair.$1
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = pair.$2,
      );
    }
    if (u > .82) {
      final angle = math.atan2(d.dy - b.dy, d.dx - b.dx);
      c.save();
      c.translate(d.dx, d.dy);
      c.rotate(angle);
      final head = Path()
        ..moveTo(11, 0)
        ..lineTo(-7, -12)
        ..lineTo(-3, 0)
        ..lineTo(-7, 12)
        ..close();
      c.drawPath(
        head,
        Paint()
          ..color = plum
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round,
      );
      c.drawPath(head, Paint()..color = gold);
      c.restore();
    }
  }

  @override
  void render(Canvas canvas) {
    final opacity = _closed ? (1 - _closing / .22).clamp(0.0, 1.0) : 1.0;
    canvas.saveLayer(
      bleedRectFor(this, size.y),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
    );
    _rect(
      canvas,
      bleedRectFor(this, size.y),
      Color.fromRGBO(30, 16, 26, .9 * _progress(elapsed, 0, .25)),
    );
    canvas.save();
    canvas.translate(160, 0);
    canvas.scale(guideScale);
    canvas.translate(-160, 0);
    final title = _progress(elapsed, .08, .4);
    if (title > 0) {
      canvas.save();
      canvas.translate(160, 106);
      canvas.scale(_back(title));
      _text(
        canvas,
        'LEADERBOARD',
        0,
        0,
        32,
        const Color(0xffffffff),
        outline: pink,
      );
      canvas.restore();
    }
    for (var i = 0; i < 3; i++) {
      _arrow(canvas, i, _progress(elapsed, .78 + i * .6, .34));
    }
    const positions = [
      Offset(86, 190),
      Offset(234, 308),
      Offset(86, 426),
      Offset(234, 544),
    ];
    for (var i = 0; i < 4; i++) {
      final start = .5 + i * .6, u = _progress(elapsed, start, .42);
      if (u <= 0) continue;
      final pos = positions[i];
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.scale(.35 + .65 * _back(u));
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(255, 255, 255, math.min(1, u * 2.5)),
      );
      switch (i) {
        case 0:
          _fly(canvas);
        case 1:
          _climb(canvas, elapsed - start);
        case 2:
          _gift(canvas);
        case 3:
          _record(canvas);
      }
      canvas.restore();
      canvas.restore();
      final cap = _progress(elapsed, start + .2, .3);
      if (cap > 0) {
        final y = pos.dy + 57 + (1 - cap) * 6;
        _rect(
          canvas,
          Rect.fromCenter(
            center: Offset(pos.dx, y + 12),
            width: 140,
            height: 24,
          ),
          pink,
        );
        _text(
          canvas,
          captions[i],
          pos.dx,
          y + 12,
          12,
          const Color(0xffffffff),
          maxWidth: 134,
        );
      }
    }
    final tap = _progress(elapsed, 3.05, .4);
    if (tap > 0) {
      _text(
        canvas,
        'TAP TO CONTINUE',
        160,
        656,
        19,
        const Color(0xffffd9ee).withValues(
          alpha: tap * (motion() ? .55 + .45 * math.cos(_idle * 2.4).abs() : 1),
        ),
      );
    }
    canvas.restore();
    canvas.restore();
  }
}
