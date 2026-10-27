import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../levels/level_progress.dart';
import '../../levels/levels.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../look_component.dart';
import '../ui/confetti.dart';
import '../ui/live_effects.dart' show WiggleEffect;
import 'emblem_view.dart';

/// Images the LEVEL UP popup draws (under `assets/images/`).
const List<String> kLevelUpPopupImages = ['menu/close.png', 'menu/coin.png'];

/// The LEVEL UP popup (PRD-home-v3 §4.3, build74 `levelUp`), in the No-ads
/// popup style (P1): a dim over home and a centred 280 pt card — pink
/// header (178 pt) with slowly rotating soft-pink rays and the new emblem
/// + equipped bird popping in (0 -> 1.12 -> 1 over 0.45 s), the darker ✕
/// box top-right, the soft "LEVEL UP!" band, "YOU ARE NOW A(N)", the rank
/// name, "Next: HAWK at 800" / "The highest level. Legendary!" and the gold
/// CLAIM [coin] +reward button.
///
/// On open (0.18 s in) confetti bursts from the emblem over the whole
/// screen: 50 / 90 / 140 pieces for lv 1-4 / 5-8 / 9-10 (none under reduce
/// motion). CLAIM calls [onClaim] with the button's world rect, ✕ / Esc
/// with null — both claim (the reward is never lost). Taps on the dim are
/// swallowed. The game owns the bookkeeping (back stack, claim, sounds,
/// analytics).
class LevelUpPopup extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity, TapCallbacks {
  LevelUpPopup({required this.pending, required this.look, required this.onClaim})
    : super(priority: 26);

  final PendingLevelUp pending;
  final Look look;
  final void Function(Rect? from) onClaim;

  static const Color dimColor = Color(0xB8282830); // rgba(40,40,48,.72)
  static const Color mutedText = Color(0xFF9A4D78);

  /// False once the popup starts closing: nothing in it takes taps.
  bool active = true;
  bool _isActive() => active;

  late final PositionComponent card;
  late final WiggleEffect _cardPop;
  late final MenuButton closeButton;
  late final MenuButton claimButton;
  late final MenuText nameText;
  late final MenuText articleText;
  late final MenuText nextText;
  late final MenuText claimText;
  late final EmblemView emblem;
  late final LookComponent bird;

  final Paint _dimPaint = Paint()..color = dimColor;
  final Paint _cardPaint = Paint();

  double _t = 0;
  bool _built = false;
  bool _confettiDone = false;

  /// The confetti once it started (tests).
  ConfettiBurst? confetti;

  /// Confetti pieces for [level] (§4.3).
  static int confettiFor(int level) => level >= 9
      ? 140
      : level >= 5
      ? 90
      : 50;

  /// "A" / "AN" before the rank name.
  static String articleFor(String name) =>
      RegExp('^[AEIOU]').hasMatch(name) ? 'YOU ARE NOW AN' : 'YOU ARE NOW A';

  /// The line under the name.
  static String nextLineFor(int level) {
    final next = trackLevelDef(level + 1);
    return next == null
        ? 'The highest level. Legendary!'
        : 'Next: ${next.name} at ${formatCoins(next.points)}';
  }

  /// Emblem pop-in scale at [k] = t / 0.45 (build74 `pf`).
  static double popIn(double k) {
    if (k >= 1) return 1;
    final e = 1 - math.pow(1 - k, 3).toDouble();
    return e * 1.12 - (k > .8 ? (k - .8) * .6 : 0);
  }

  /// World rect of the CLAIM button (the coin-fly source).
  Rect get claimRect {
    final p = claimButton.absolutePosition;
    return Rect.fromLTWH(p.x, p.y, claimButton.width, claimButton.height);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    final loaded = await Future.wait(
      kLevelUpPopupImages.map(game.images.load),
    );
    final close = Sprite(loaded[0]);
    final coin = Sprite(loaded[1]);
    final def = pending.def;

    final rect = Config.levelUpCardRectFor(h);
    final w = rect.width;
    card = _Card(
      position: rect.topLeft.toVector2(),
      size: rect.size.toVector2(),
      fill: _cardPaint,
    );
    _cardPop = WiggleEffect(card);
    card.decorator.addLast(_cardPop);

    // Header: pink, rays, emblem + bird (clipped to the header).
    const emblemCentre = Offset(
      Config.levelUpCardWidth / 2,
      Config.levelUpEmblemY,
    );
    emblem = EmblemView(
      level: pending.toLevel,
      artScale: Config.levelUpEmblemScale,
      position: emblemCentre.toVector2(),
    )..popScale = 0;
    bird = LookComponent(
      look: look,
      artScale: Config.levelUpEmblemScale * Config.levelsBirdOnEmblem,
      anchor: Anchor.center,
      position: emblemCentre.toVector2(),
    )..scale = Vector2.zero();
    final header = _Header(
      this,
      size: Vector2(w, Config.levelUpHeaderHeight),
      children: [emblem, bird],
    );
    closeButton = MenuButton(
      color: Config.menuPinkDark,
      position: Vector2(w - Config.noAdsCloseSize, 0),
      size: Vector2.all(Config.noAdsCloseSize),
      onPressed: () => onClaim(null),
      isActive: _isActive,
      priority: 2,
      children: [
        MenuIcon(
          close,
          size: Vector2.all(18),
          position: Vector2.all(Config.noAdsCloseSize / 2),
          anchor: Anchor.center,
        ),
      ],
    );

    // Title band.
    const titleTop = Config.levelUpHeaderHeight;
    final titleBand = RectangleComponent(
      position: Vector2(0, titleTop),
      size: Vector2(w, Config.levelUpTitleHeight),
      paint: Paint()..color = Config.menuSoft,
    );
    final title = MenuText(
      'LEVEL UP!',
      fontSize: Config.levelUpTitleFontSize,
      color: Config.menuPink,
      letterSpacingEm: 0.14,
    );
    title.position = Vector2(
      (w - title.width) / 2,
      (Config.levelUpTitleHeight - title.height) / 2,
    );
    titleBand.add(title);

    // Body.
    var y = titleTop + Config.levelUpTitleHeight + Config.levelUpBodyPadTop;
    MenuText centred(MenuText text) =>
        text..position = Vector2((w - text.width) / 2, text.y);
    articleText = centred(
      MenuText(
        articleFor(def.name),
        fontSize: Config.levelUpSmallFontSize,
        color: mutedText,
        letterSpacingEm: 0.16,
        position: Vector2(0, y),
      ),
    );
    y += Config.levelUpSmallFontSize * kNormalLineHeight + 2;
    nameText = centred(
      MenuText(
        def.name,
        fontSize: Config.levelUpNameFontSize,
        color: Config.menuPlum,
        letterSpacingEm: 0.06,
        position: Vector2(0, y),
      ),
    );
    y += Config.levelUpNameFontSize * kNormalLineHeight + 4;
    nextText = centred(
      MenuText(
        nextLineFor(pending.toLevel),
        fontSize: Config.levelUpSmallFontSize,
        color: mutedText,
        letterSpacingEm: 0.03,
        position: Vector2(0, y),
      ),
    );
    y += Config.levelUpSmallFontSize * kNormalLineHeight +
        Config.levelUpButtonGap;

    claimButton = MenuButton(
      color: Config.menuGold,
      position: Vector2(Config.levelUpBodyPad, y),
      size: Vector2(
        w - 2 * Config.levelUpBodyPad,
        Config.levelUpButtonHeight,
      ),
      onPressed: () => onClaim(claimRect),
      isActive: _isActive,
    );
    MenuText buttonText(String text) => MenuText(
      text,
      fontSize: Config.levelUpButtonFontSize,
      color: Config.menuPlum,
      letterSpacingEm: 0.1,
    );
    claimText = buttonText('+${formatCoins(pending.reward)}');
    layoutRow(claimButton, [
      buttonText('CLAIM'),
      MenuIcon(coin, size: Vector2.all(Config.levelUpCoinSize)),
      claimText,
    ], gap: 9);

    card.addAll([
      header,
      closeButton,
      titleBand,
      articleText,
      nameText,
      nextText,
      claimButton,
    ]);
    add(card);
    _built = true;
    _apply();
  }

  /// Seconds since the popup opened (the header clock).
  double get time => _t;

  void _apply() {
    if (!_built) return;
    _cardPaint.color = game.stageBackground;
    // Card pop: .8 -> 1.05 (70 %) -> 1 over 0.26 s, ease-out.
    final u = Curves.easeOut.transform(
      (_t / Config.levelUpCardPopDuration).clamp(0.0, 1.0),
    );
    _cardPop.scale = u < .7
        ? .8 + (1.05 - .8) * (u / .7)
        : 1.05 - .05 * ((u - .7) / .3);
    // Emblem + bird pop in (0 -> 1.12 -> 1 over 0.45 s).
    final s = popIn(_t / Config.levelUpPopDuration);
    // Reduce motion (PRD-home-v3 §3.2): a frozen emblem clock as on home
    // and LEVELS (flags, stars, rays, ring) and no sweep; the header rays
    // stop rotating too (_Header.render).
    final still = game.reduceMotion;
    emblem
      ..popScale = s
      ..t = still ? 0 : _t + 1
      ..shine = !still;
    bird
      ..scale = Vector2.all(s)
      ..flapOverride = (_t * 1.4) % 1 < .3;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _apply();
    if (!_confettiDone && _t >= Config.levelUpConfettiDelay) {
      _confettiDone = true;
      if (!game.reduceMotion) {
        final rect = Config.levelUpCardRectFor(game.viewHeight);
        final big = pending.toLevel >= 9;
        final burst = ConfettiBurst.burst(
          origin: Offset(Config.worldWidth / 2, rect.top + 90),
          count: confettiFor(pending.toLevel),
          speed: big ? 300 : 220,
          driftX: 0,
          priority: 30,
        );
        confetti = burst;
        parent?.add(burst);
      }
    }
  }

  @override
  void render(Canvas canvas) =>
      canvas.drawRect(bleedRectFor(this, size.y), _dimPaint); // WP-TAB

  @override
  bool containsLocalPoint(Vector2 point) =>
      active && super.containsLocalPoint(point);

  // The dim swallows taps (only ✕ and CLAIM close the popup).
  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }
}

/// The pink header: 16 slowly rotating soft-pink ray wedges (22 %, 0.5
/// rad/s, static under reduce motion) behind the emblem + bird, clipped to
/// the header.
class _Header extends PositionComponent {
  _Header(this._popup, {super.size, super.children});

  final LevelUpPopup _popup;
  final Paint _pink = Paint()..color = Config.menuPink;
  final Paint _ray = Paint()..color = Config.menuSoft.withValues(alpha: .22);

  static final Path _rays = () {
    final path = Path();
    const n = 16;
    const step = 2 * math.pi / n;
    final box = Rect.fromCircle(center: Offset.zero, radius: 190);
    for (var i = 0; i < n; i++) {
      path
        ..moveTo(0, 0)
        ..arcTo(box, i * step, step / 2, false)
        ..close();
    }
    return path;
  }();

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(x, y, width, height));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), _pink);
    final still = _popup.game.reduceMotion;
    canvas.save();
    canvas.translate(width / 2, Config.levelUpEmblemY);
    if (!still) canvas.rotate(_popup.time * .5);
    canvas.drawPath(_rays, _ray);
    canvas.restore();
  }
}

/// The card body: stage-background fill; swallows taps that miss its
/// buttons.
class _Card extends PositionComponent with TapCallbacks {
  _Card({super.position, super.size, required this.fill});

  final Paint fill;

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), fill);

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }
}
