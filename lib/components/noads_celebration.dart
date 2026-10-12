import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Cubic, Curves;

import '../game/config.dart';
import '../services/iap_service.dart' show kNoAdsBonusCoins;
import 'home/menu_primitives.dart';
import 'skins/celebration.dart' show keyframe;
import 'ui/live_effects.dart' show WiggleEffect;
import 'ui/p1_popup.dart';
import '../game/paints.dart';

/// Images the celebration draws.
const List<String> kNoAdsCelebrationImages = [
  'menu/noads.png',
  'menu/close.png',
  'menu/coin.png',
];

/// "YOU'RE AD-FREE!" (PRD-home-v3 §7, mock build79 `celebrate`): the
/// legendary-level popup after a fresh No-ads purchase, in the P1 style.
///
/// The card swings in (scale .6 -> 1.06 -> 1, -4° -> 1° -> 0°, 0.36 s);
/// its 170 pt pink header shows slowly rotating gold rays (16, 0.5 rad/s)
/// and 10 orbiting, twinkling white sparkles behind the big soft crossed-AD
/// icon (92 pt), which wobbles (0.42 s after 0.12 s) before the gold check
/// stamp slams onto its lower right (2.6 -> .9 -> 1, -35° -> 6° -> 0°,
/// 0.34 s at 0.33 s). Body: title band, "No more forced ads.", the thanks
/// line, the "+1 000 BONUS COINS" chip and the gold CLAIM button.
///
/// The flash, shake, confetti and jingle belong to the game (they cover the
/// whole screen); CLAIM calls [onClaim], ✕ / dim / Esc [onDismiss] — both
/// collect the bonus. Reduce motion: no swing, wobble or stamp slam, the
/// rays and sparkles stand still.
class NoAdsCelebration extends P1Popup {
  NoAdsCelebration({required this.onClaim, required super.onDismiss});

  final void Function() onClaim;

  late final MenuButton closeButton;
  late final MenuButton claimButton;
  late final MenuText titleText;
  late final _Header _header;

  /// The CLAIM button in world coordinates (the bonus coins start there).
  Rect get claimRect {
    final p = claimButton.absolutePositionOfAnchor(Anchor.topLeft);
    return Rect.fromLTWH(p.x, p.y, claimButton.width, claimButton.height);
  }

  /// The card's centre-top area the confetti bursts from (mock: card left
  /// + 140, top + 90), in world coordinates.
  Offset get confettiOrigin =>
      Offset(card.x + Config.p1PopupWidth / 2, card.y + 90);

  double _t = 0;

  /// Seconds since the popup opened (tests).
  double get elapsed => _t;

  /// Whether the gold check has landed (tests).
  bool get stamped => _header.stampProgress >= 1;

  /// The AD icon's wobble right now (tests): (scale, radians).
  (double, double) get iconWobble => _header.wobble;

  static const _swingCurve = Curves.easeOut;

  @override
  Future<void> buildCard(PositionComponent card) async {
    final images = game.images;
    final noAds = Sprite(await images.load('menu/noads.png'));
    final close = Sprite(await images.load('menu/close.png'));
    final coin = Sprite(await images.load('menu/coin.png'));
    const w = Config.p1PopupWidth;
    const pad = Config.p1PopupPad;
    const headerH = Config.noAdsCelebrationHeaderHeight;
    const titleH = Config.noAdsCelebrationTitleHeight;
    _header = _Header(icon: noAds, motion: !game.reduceMotion);
    closeButton = closeBox(close, onDismiss);
    titleText = MenuText(
      "YOU'RE AD-FREE!",
      fontSize: Config.noAdsCelebrationTitleFontSize,
      color: Config.menuPink,
      letterSpacingEm: 0.1,
      anchor: Anchor.center,
      position: Vector2(w / 2, titleH / 2),
    );
    final titleBand = RectangleComponent(
      position: Vector2(0, headerH),
      size: Vector2(w, titleH),
      paint: Paint()..color = Config.menuSoft,
      children: [titleText],
    );

    var y = headerH + titleH + pad;
    final message = MenuText(
      'No more forced ads.',
      fontSize: 18,
      color: Config.menuPlum,
      letterSpacingEm: 0.02,
      anchor: Anchor.topCenter,
      position: Vector2(w / 2, y),
    );
    y += message.height + 6;
    final thanks = MenuParagraph(
      'Thanks for supporting Flappy Spikes!',
      fontSize: 13,
      color: Config.p1PopupSmallText,
      letterSpacingEm: 0.02,
      lineHeight: 1.35,
      maxWidth: w - 2 * pad,
      position: Vector2(pad, y),
    );
    y += thanks.height + 14;

    // "+1 000 BONUS COINS" chip: gold 22 % over the card, 6 / 12 padding.
    final chipText = MenuText(
      '+${formatCoins(kNoAdsBonusCoins)} BONUS COINS',
      fontSize: 15,
      color: Config.menuPlum,
      letterSpacingEm: 0.08,
    );
    final chipWidth = 20 + 8 + chipText.width + 24;
    final chipHeight = math.max(20.0, chipText.height) + 12;
    final chip = _MixedBox(
      position: Vector2((w - chipWidth) / 2, y),
      size: Vector2(chipWidth, chipHeight),
      mix: .22,
    );
    layoutRow(chip, [MenuIcon(coin, size: Vector2.all(20)), chipText], gap: 8);
    y += chipHeight + 14;

    // CLAIM [coin] +1 000.
    claimButton = MenuButton(
      color: Config.menuGold,
      position: Vector2(pad, y),
      size: Vector2(w - 2 * pad, Config.noAdsCelebrationClaimHeight),
      onPressed: onClaim,
      isActive: isActive,
    );
    layoutRow(claimButton, [
      MenuText(
        'CLAIM',
        fontSize: 22,
        color: Config.menuPlum,
        letterSpacingEm: 0.1,
      ),
      MenuIcon(coin, size: Vector2.all(22)),
      MenuText(
        '+${formatCoins(kNoAdsBonusCoins)}',
        fontSize: 22,
        color: Config.menuPlum,
        letterSpacingEm: 0.1,
      ),
    ], gap: 9);
    y += Config.noAdsCelebrationClaimHeight + pad;
    cardHeight = y;

    card.addAll([
      _header,
      closeButton,
      titleBand,
      message,
      thanks,
      chip,
      claimButton,
    ]);
    _pose();
  }

  void _pose() {
    // Reduce motion (also switched on mid-celebration): the card settles
    // and the header's rays, sparkles and wobble stop.
    final motion = !game.reduceMotion;
    _header.motion = motion;
    if (!motion) {
      cardPose.rest();
      return;
    }
    final u = _swingCurve.transform(
      (_t / Config.noAdsCelebrationSwing).clamp(0.0, 1.0),
    );
    cardPose
      ..scale = keyframe(const [(0, .6), (.7, 1.06), (1, 1)], u)
      ..angle = keyframe(const [(0, -4), (.7, 1), (1, 0)], u) * math.pi / 180;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (isLoaded) _pose();
  }
}

/// A box filled with the menu gold [mix] over the stage background (the
/// bonus chip, CSS `color-mix(gold 22%, bg)`).
class _MixedBox extends PositionComponent {
  _MixedBox({super.position, super.size, required this.mix});

  final double mix;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    // Menus are always colour stage 0 (#F1F1F1).
    _paint.color = Color.lerp(const Color(0xFFF1F1F1), Config.menuGold, mix)!;
    canvas.drawRect(size.toRect(), _paint);
  }
}

/// The 170 pt pink header: rays, sparkles, the crossed-AD icon with its
/// wobble and the gold check stamp. Clips to its box.
class _Header extends PositionComponent {
  _Header({required Sprite icon, required this.motion})
    : super(
        size: Vector2(Config.p1PopupWidth, Config.noAdsCelebrationHeaderHeight),
      ) {
    _icon = MenuIcon(
      icon,
      size: Vector2.all(Config.noAdsCelebrationIconSize),
      position: Vector2(
        (Config.p1PopupWidth - Config.noAdsCelebrationIconSize) / 2,
        (Config.noAdsCelebrationHeaderHeight -
                Config.noAdsCelebrationIconSize) /
            2,
      ),
    );
    _icon.decorator.addLast(_wobble = WiggleEffect(_icon));
  }

  /// False under reduce motion (read live: the card updates it).
  bool motion;
  late final MenuIcon _icon;
  late final WiggleEffect _wobble;
  double _t = 0;

  /// Time of the rays / sparkles: frozen while [motion] is off.
  double _motionT = 0;

  static const Offset _rayCentre = Offset(140, 88);
  static const _stampCurve = Cubic(.3, 0, .3, 1);

  final Paint _fill = Paint()..color = Config.menuPink;
  final Paint _ray = Paint();
  final Paint _star = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _ring = Paint()..color = Config.menuPink;
  final Paint _gold = Paint()..color = Config.menuGold;
  final Paint _check = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.6
    ..strokeCap = StrokeCap.square
    ..color = Config.menuPlum;
  final Path _wedge = Path();
  final Path _starPath = Path();

  (double, double) get wobble => (_wobble.scale, _wobble.angle);

  /// 0 before the stamp starts, 1 once it has landed.
  double get stampProgress => !motion
      ? 1
      : ((_t - Config.noAdsCelebrationStampDelay) /
                Config.noAdsCelebrationStampDuration)
            .clamp(0.0, 1.0);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_icon);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (!motion) {
      _wobble.rest();
      return;
    }
    _motionT += dt;
    final w =
        (_t - Config.noAdsCelebrationWobbleDelay) /
        Config.noAdsCelebrationWobble;
    if (w <= 0 || w >= 1) {
      _wobble.rest();
    } else {
      _wobble
        ..scale = keyframe(const [(0, 1), (.3, 1.08), (.55, .96), (1, 1)], w)
        ..angle =
            keyframe(const [(0, 0), (.3, -6), (.55, 5), (1, 0)], w) *
            math.pi /
            180;
    }
  }

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.clipRect(size.toRect());
    _renderBack(canvas);
    for (final child in children) {
      child.renderTree(canvas);
    }
    _renderStamp(canvas);
    canvas.restore();
  }

  void _renderBack(Canvas canvas) {
    canvas.drawRect(size.toRect(), _fill);
    // 16 gold rays (half-wedges of 200 pt), turning at 0.5 rad/s.
    final t = _motionT;
    canvas.save();
    canvas.translate(_rayCentre.dx, _rayCentre.dy);
    canvas.rotate(t * .5);
    const step = 2 * math.pi / 16;
    for (var i = 0; i < 16; i++) {
      _ray.color = i.isOdd
          ? const Color.fromRGBO(255, 229, 130, .34)
          : const Color.fromRGBO(255, 181, 41, .3);
      _wedge
        ..reset()
        ..moveTo(0, 0)
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: 200),
          i * step,
          step / 2,
          false,
        )
        ..close();
      canvas.drawPath(_wedge, _ray);
    }
    canvas.restore();
    // 10 sparkles on an ellipse around the icon, twinkling.
    for (var i = 0; i < 10; i++) {
      final a = i / 10 * 2 * math.pi + t * .8;
      final r = 58 + math.sin(t * 3 + i) * 6;
      final tw = .5 + .5 * math.sin(t * 5 + i * 1.3);
      _drawStar(
        canvas,
        _rayCentre.dx + math.cos(a) * r,
        _rayCentre.dy + math.sin(a) * r * .8,
        2 + tw * 2.4,
        t * 2 + i,
      );
    }
  }

  void _drawStar(Canvas canvas, double x, double y, double s, double rot) {
    _starPath.reset();
    for (var k = 0; k < 8; k++) {
      final rr = k.isOdd ? s * .3 : s;
      final a = k * math.pi / 4 + rot;
      final px = x + math.cos(a) * rr, py = y + math.sin(a) * rr;
      k == 0 ? _starPath.moveTo(px, py) : _starPath.lineTo(px, py);
    }
    _starPath.close();
    canvas.drawPath(_starPath, _star);
  }

  void _renderStamp(Canvas canvas) {
    final p = stampProgress;
    if (p <= 0) return;
    final u = _stampCurve.transform(p);
    final scale = keyframe(const [(0, 2.6), (.75, .9), (1, 1)], u);
    final degrees = keyframe(const [(0, -35), (.75, 6), (1, 0)], u);
    final alpha = keyframe(const [(0, 0), (.75, 1), (1, 1)], u);
    const s = Config.noAdsCelebrationStampSize;
    final c = Config.noAdsCelebrationStampTopLeft + const Offset(s / 2, s / 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.scale(scale);
    if (alpha < 1) {
      canvas.saveLayer(null, layerPaint(alpha));
    }
    canvas.drawCircle(Offset.zero, s / 2 + 5, _ring);
    canvas.drawCircle(Offset.zero, s / 2, _gold);
    // 40 pt check from the 24-unit path M4 12.5 l5 5 L20 6.5.
    canvas.save();
    canvas.scale(40 / 24);
    canvas.translate(-12, -12);
    canvas.drawPath(
      Path()
        ..moveTo(4, 12.5)
        ..lineTo(9, 17.5)
        ..lineTo(20, 6.5),
      _check..strokeWidth = 3.6,
    );
    canvas.restore();
    if (alpha < 1) canvas.restore();
    canvas.restore();
  }
}
