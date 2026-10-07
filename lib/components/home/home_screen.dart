import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/events.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/sound.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/tintable.dart';
import '../../menu/powerup_slot.dart';
import '../../services/iap_service.dart';
import '../../skins/look.dart';
import '../look_component.dart';
import '../ui/bird_idle.dart';
import '../ui/flip.dart';
import '../ui/live_effects.dart';
import 'menu_primitives.dart';

/// Images the home screen draws (all under `assets/images/`).
const List<String> kHomeImages = [
  'menu/play.png',
  'menu/video.png',
  'menu/shield_slot.png',
  'menu/check.png',
  'menu/shop.png',
  'menu/skins.png',
  'menu/invite.png',
  'menu/noads.png',
  'menu/trophy.png',
];

/// The 2.0 home screen (PRD-1 §4, approved design G1 centred): coin pill,
/// settings gear, title, the start block (equipped bird + START + powerup
/// slot), the Shop / Skins / Invite / No-ads tiles and the leaderboard row.
/// Replaces the 1.0 `StartPanel`.
///
/// Every button routes to a [FlappySpikesGame] method; this component only
/// draws and keeps itself in sync with the menu state (polled each frame —
/// cheap, and it also catches changes without a notifier such as an ad
/// finishing loading or the no-ads flag). Text uses the stage foreground
/// (Tintable); chrome is the fixed menu pink.
class HomeScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity
    implements Tintable {
  HomeScreen({required this.bestScore, required this.gamesPlayed})
    : super(priority: 20);

  int bestScore;
  int gamesPlayed;

  /// False once the screen starts leaving (START, settings): its buttons
  /// stop hit-testing so taps reach the game below during the fade-out.
  bool active = true;

  Color _tint = const Color(0xFF828282);

  /// The coin pill is shared chrome owned by the game (it stays put across
  /// home / Shop / Skins transitions), drawn above this screen.
  CoinPill get coinPill => game.coinPill;

  /// Tap target of the settings gear; its pink box and glyph are the
  /// game's shared [MenuCornerBox] below this screen.
  late final MenuButton gearButton;
  late final MenuText title;
  late final List<MenuText> subtitle;
  late final HomeBird bird;
  late final MenuButton startButton;
  late final PowerupSlotButton slotButton;
  late final MenuTile shopTile;
  late final MenuTile skinsTile;
  late final MenuTile inviteTile;
  late final MenuTile noAdsTile;
  late final LeaderboardRow leaderboard;

  /// The screen's idle clock (§8.2 live effects).
  late final LiveClock clock;

  List<MenuTile> get tiles => [shopTile, skinsTile, inviteTile, noAdsTile];

  bool _isActive() => active;

  /// True once the screen was taken off the tree (e.g. a replay right
  /// after it was added) — see [MenuScreen.built].
  bool get _detached => parent == null || isRemoving || isRemoved;
  bool _built = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (_detached) return;
    final game = this.game;
    final h = game.viewHeight;
    final images = game.images;
    final loaded = await Future.wait(kHomeImages.map(images.load));
    if (_detached) return;
    final sprites = {
      for (var i = 0; i < kHomeImages.length; i++)
        kHomeImages[i]: Sprite(loaded[i]),
    };
    Sprite icon(String name) => sprites['menu/$name.png']!;

    // --- top row ----------------------------------------------------------
    // The coin pill and the gear's box + glyph are the game's shared chrome
    // (see FlappySpikesGame.coinPill / MenuCornerBox); only the gear's tap
    // target (and its pressed shade) lives here.
    final gearRect = Config.homeGearRectFor(h);
    gearButton = MenuButton(
      position: gearRect.topLeft.toVector2(),
      size: gearRect.size.toVector2(),
      onPressed: game.openSettings,
      isActive: _isActive,
    );
    // §8.2 / §8.4: one idle clock for the screen's live effects.
    clock = LiveClock(
      paused: () => game.liveMotionPaused,
      still: () => game.reduceMotion,
    );

    // --- title ------------------------------------------------------------
    title = MenuText(
      'Flappy Spikes',
      fontSize: Config.homeTitleFontSize,
      color: _tint,
      lineHeight: 1,
      position: Config.homeTitlePositionFor(h),
      anchor: Anchor.topCenter,
    );
    final sub = Config.homeSubtitlePositionFor(h);
    const subLine =
        Config.homeSubtitleFontSize * Config.homeSubtitleLineHeight;
    subtitle = [
      for (final (i, line) in const ['DON’T TOUCH', 'THE SPIKES'].indexed)
        MenuText(
          line,
          fontSize: Config.homeSubtitleFontSize,
          color: _tint,
          lineHeight: Config.homeSubtitleLineHeight,
          position: sub + Vector2(0, i * subLine),
          anchor: Anchor.topCenter,
        ),
    ];
    // Long-press on the title opens the debug panel (debug builds / Linux).
    final titleHotspot = _LongPressArea(
      position: Vector2(Config.homeMargin, Config.homeTitleTop),
      size: Vector2(
        Config.worldWidth - 2 * Config.homeMargin,
        Config.homeSubtitleTop + 2 * subLine - Config.homeTitleTop,
      ),
      onLongPress: game.openDebugPanel,
      isActive: () => active && FlappySpikesGame.debugAvailable,
    );

    // --- start block --------------------------------------------------------
    bird = HomeBird(
      rect: Config.homeBirdRectFor(h),
      look: game.menu.items.look,
      isActive: _isActive,
    );
    final startRect = Config.homeStartRectFor(h);
    startButton = MenuButton(
      color: Config.menuPink,
      position: startRect.topLeft.toVector2(),
      size: startRect.size.toVector2(),
      onPressed: game.startRun,
      isActive: _isActive,
    );
    _layoutRow(startButton, [
      MenuIcon(icon('play'), size: Vector2.all(32)),
      MenuText(
        'START',
        fontSize: 36,
        color: Config.menuSoft,
        letterSpacingEm: 0.14,
      ),
    ], gap: 10);
    slotButton = PowerupSlotButton(
      rect: Config.homeSlotRectFor(h),
      video: icon('video'),
      shield: icon('shield_slot'),
      onPressed: game.tapPowerupSlot,
      isActive: _isActive,
    );

    // --- tiles ------------------------------------------------------------
    MenuTile tile(int index, String name, String label, void Function() tap) =>
        MenuTile(
          rect: Config.homeTileRectFor(h, index),
          icon: icon(name),
          label: label,
          onPressed: tap,
          check: icon('check'),
          isActive: _isActive,
        );
    // §8.2: tiles press with `sk_tap`.
    shopTile = tile(0, 'shop', 'SHOP', () => game.openShop(sfx: Sfx.skTap));
    skinsTile = tile(1, 'skins', 'SKINS', game.openSkins);
    inviteTile = tile(2, 'invite', 'INVITE', game.invite);
    // PO change 2026-10-05: the tile starts the store purchase straight
    // away; the popup is the automatic launch upsell only.
    noAdsTile = tile(3, 'noads', 'NO ADS', () => game.buyNoAds('home_tile'));

    leaderboard = LeaderboardRow(
      rect: Config.homeLeaderboardRectFor(h),
      trophy: icon('trophy'),
      bestScore: bestScore,
      gamesPlayed: gamesPlayed,
      onPressed: () => game.showLeaderboard(sfx: Sfx.skTap),
      isActive: _isActive,
    );

    clock
      ..bind(slotButton.animate)
      ..bind(
        (t, still) => skinsTile.tagWobble.setPose(
          still ? (scale: 1, degrees: 0) : LiveCurves.newTagWobble(t),
        ),
      )
      ..bind(
        (t, still) => leaderboard.trophyWiggle.setPose(
          still ? (scale: 1, degrees: 0) : LiveCurves.trophyWiggle(t),
        ),
      );

    addAll([
      clock,
      gearButton,
      titleHotspot,
      title,
      ...subtitle,
      bird,
      slotButton,
      startButton,
      ...tiles,
      leaderboard,
    ]);
    _built = true;
    _sync(force: true);
    setTint(_tint);
  }

  /// Lays [items] out left-to-right as one centred group inside [parent]
  /// (the mocks' `display:flex; justify-content:center; align-items:center;
  /// gap`), vertically centred.
  static void _layoutRow(
    PositionComponent parent,
    List<PositionComponent> items, {
    required double gap,
  }) => layoutRow(parent, items, gap: gap);

  // --- state sync ------------------------------------------------------------

  bool? _hasNew;
  bool? _noAds;
  bool? _noAdsPending;

  @override
  void update(double dt) {
    super.update(dt);
    if (_built) _sync();
  }

  void _sync({bool force = false}) {
    final menu = game.menu;
    final hasNew = menu.items.hasNewBadge;
    if (force || hasNew != _hasNew) {
      _hasNew = hasNew;
      skinsTile.tag = hasNew ? 'NEW' : null;
    }
    // PRD-home-v3 §7: after a fresh purchase the owned looks wait for the
    // celebration's flips.
    final noAds = game.noAdsShown;
    final pending = game.purchases.isPending(IapProduct.noAds);
    if (force || noAds != _noAds || pending != _noAdsPending) {
      _noAds = noAds;
      _noAdsPending = pending;
      // PRD-1 §3.5 / PRD-home-v3 §7: owners keep the tile on a lighter
      // pink: check icon + "AD-FREE". A pending No-ads purchase dims and
      // disables the tile (as the Shop banner).
      noAdsTile
        ..dimmed = !noAds && pending
        ..owned = noAds
        ..tappable = !pending;
    }
    slotButton.setState(
      offered: menu.slot.offered,
      noAds: game.noAdsVideoGone,
      adAvailable: game.monetization.ads.isAvailable,
    );
    slotButton.outlineColor = game.stageBackground;
  }

  /// Re-reads all menu state now (instead of on the next frame).
  void refresh() {
    if (_built) _sync(force: true);
  }

  void setStats({required int bestScore, required int gamesPlayed}) {
    this.bestScore = bestScore;
    this.gamesPlayed = gamesPlayed;
    if (_built) {
      leaderboard.setStats(bestScore: bestScore, gamesPlayed: gamesPlayed);
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (_built) {
      title.color = color;
      for (final line in subtitle) {
        line.color = color;
      }
      leaderboard.tint = color;
    }
  }
}

/// Coin balance pill (mock `.pill`): darker 38x38 "+" box, balance in soft
/// pink, gold coin; grows leftwards with the number of digits, its
/// top-right corner pinned to [topRight]. The whole pill opens the Shop at
/// the coin packs.
///
/// One instance, owned by the game, serves home, Shop and Skins (all pin
/// it to the same corner): it survives their crossfades at full opacity
/// and only fades with a scene that has no pill (settings, a run).
class CoinPill extends MenuButton
    with GroupOpacity, HasGameReference<FlappySpikesGame> {
  CoinPill({
    required int initialBalance,
    required Vector2 topRight,
    required super.onPressed,
    super.isActive,
    super.priority,
  }) : _balance = initialBalance,
       _topRight = topRight.clone(),
       super(
         color: Config.menuPink,
         size: Vector2(0, pillHeight),
         position: topRight.clone(),
       ) {
    decorator.addLast(_pillPop = WiggleEffect(this));
  }

  static const double pillHeight = Config.homeTopRowHeight;
  static const double plusGap = 9; // "+" box -> text
  static const double coinGap = 8; // text -> coin
  static const double coinSize = 24;
  static const double padRight = 12;
  static const double fontSize = 20;

  final Vector2 _topRight;
  int _balance;

  late final MenuText label;
  late final MenuIcon _coinIcon;
  late final RectangleComponent _plusBox;

  /// The wallet balance (the target of a running [countFrom]).
  int get balance => _balance;
  set balance(int value) {
    if (value == _balance) return;
    _balance = value;
    if (isLoaded && _countFrom == null && _held == null) _layout();
  }

  int? _held;

  /// Whether the number is frozen by [hold] (a coin reward in flight).
  bool get held => _held != null;

  /// Freezes the number on what it shows now: the wallet can be credited
  /// while the reward's coins are still flying (PRD-menu-v2 §8.3).
  void hold() {
    _held ??= _shown;
  }

  /// Ends a [hold]: counts from the frozen number to [balance] over
  /// [duration] s ([linear] = the reward's even count, else ease-out).
  void releaseHold({
    double duration = Config.coinRewardCountDuration,
    bool linear = false,
  }) {
    final from = _held;
    if (from == null) return;
    _held = null;
    countFrom(from, duration: duration, linear: linear);
  }

  double _popT = -1;
  double _popScale = Config.coinPopScale;
  double _popDuration = Config.coinPopDuration;
  double _popDegrees = 0;
  late final WiggleEffect _coinPop;

  /// The pill coin pops to [scale] and back over [duration] s, turning to
  /// [degrees] at the peak (default: the GET landing, 135 % in 0.3 s; the
  /// PRD-home-v3 §5 landings 125 % / 0.18 s, the end spin-pop 150 % /
  /// -20° / 0.42 s).
  void popCoin({
    double scale = Config.coinPopScale,
    double duration = Config.coinPopDuration,
    double degrees = 0,
  }) {
    _popT = 0;
    _popScale = scale;
    _popDuration = duration;
    _popDegrees = degrees;
  }

  late final WiggleEffect _pillPop;
  double _pillPopT = -1;

  /// §5 end of a count-up: the whole pill pops to 114 % and back in
  /// 0.38 s (ease-out).
  void popPill() => _pillPopT = 0;

  /// Current scale of the whole pill (tests).
  double get pillScale => _pillPop.scale;

  /// §5 count-up: the pill glows gold (`0 0 16px 4px` gold 75 %, fades in
  /// / out in 0.25 s) and its number turns gold (0.2 s).
  bool glow = false;
  double _glowK = 0;

  /// Glow strength 0..1 right now (tests).
  double get glowLevel => _glowK;

  final Paint _glowPaint = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  /// Current scale of the pill coin (tests).
  double get coinScale => _coinPop.scale;

  /// Landing spot of a [CoinFly] coin: the coin's top-left + 3 (mock),
  /// in world coordinates.
  Offset get coinFlyTarget {
    final p = isLoaded ? _coinIcon.absolutePosition : absolutePosition;
    return Offset(p.x + 3, p.y + 3);
  }

  /// Seconds into the glint loop (frozen while idle motion is paused).
  double _glintT = 0;
  late final _CoinGlint _glint;

  /// Current glint opacity (tests).
  double get glintOpacity => _glint.opacity;

  /// The number on the pill right now (differs from [balance] while a
  /// [countFrom] animation runs).
  int get shownBalance => _shown;
  int _shown = 0;

  int? _countFrom;
  double _countT = 0;
  double _countDuration = 0;
  double _shakeT = -1;
  double _flashT = -1;

  static const double shakeDuration = 0.32;
  static const double flashDuration = 0.9; // one of the two gold flashes
  static const List<double> _shakeKeys = [0, -6, 6, -4, 0];

  /// Counts the number from [from] to [balance] over [duration] s
  /// (ease-out cubic), e.g. a skin-shop purchase (PRD-menu-v2 §3.6).
  void countFrom(
    int from, {
    double duration = Config.skinShopCountDuration,
    bool linear = false,
  }) {
    _countFrom = from;
    _countT = 0;
    _countDuration = duration;
    _countLinear = linear;
    if (isLoaded) _layout();
  }

  bool _countLinear = false;

  /// "Not enough coins" (§3.6): a short horizontal shake ([shake] false
  /// under reduce motion) and the "+" box flashing gold twice.
  void nudge({bool shake = true}) {
    if (shake) _shakeT = 0;
    _flashT = 0;
  }

  /// Horizontal shake offset right now (tests).
  double get shakeOffset {
    if (_shakeT < 0) return 0;
    final u = (_shakeT / shakeDuration).clamp(0.0, 1.0) * 4;
    final i = u.floor().clamp(0, 3);
    return _shakeKeys[i] + (_shakeKeys[i + 1] - _shakeKeys[i]) * (u - i);
  }

  /// Whether the "+" box is mid gold flash (tests).
  bool get flashing => _flashT >= 0;

  @override
  void update(double dt) {
    super.update(dt);
    _updateLive(dt);
    final from = _countFrom;
    if (from != null) {
      _countT += dt;
      if (_countT >= _countDuration) {
        _countFrom = null;
      }
      if (isLoaded) _layout();
    }
    if (_shakeT >= 0) {
      _shakeT += dt;
      if (_shakeT >= shakeDuration) _shakeT = -1;
    }
    if (_flashT >= 0) {
      _flashT += dt;
      if (_flashT >= 2 * flashDuration) _flashT = -1;
      if (isLoaded) {
        // #c40073 -> gold -> #c40073 per flash (mock `.plus` keyframes).
        final u = _flashT < 0 ? 0.0 : (_flashT % flashDuration) / flashDuration;
        final k = u < .5 ? u * 2 : (1 - u) * 2;
        _plusBox.paint.color = Color.lerp(
          Config.menuPinkDark,
          Config.menuGold,
          k,
        )!;
      }
    }
  }

  /// Coin glint (§8.2, home and Shop, 8.4 s loop) and the reward pop.
  void _updateLive(double dt) {
    if (!isLoaded) return;
    final scene = game.menuScene;
    final enabled =
        !game.reduceMotion &&
        (scene == MenuScene.home || scene == MenuScene.shop);
    if (!game.liveMotionPaused) _glintT += dt;
    final g = LiveCurves.glint(_glintT);
    _glint
      ..opacity = enabled ? g.opacity : 0
      ..glintScale = g.scale
      ..angle = g.degrees * math.pi / 180;
    if (_popT >= 0) {
      _popT += dt;
      final d = _popDuration;
      if (_popT >= d) {
        _popT = -1;
        _coinPop.rest();
      } else {
        final u = _popT / d;
        final k = u < .5 ? u * 2 : (1 - u) * 2;
        _coinPop
          ..scale = 1 + (_popScale - 1) * k
          ..angle = _popDegrees * k * math.pi / 180;
      }
    }
    if (_pillPopT >= 0) {
      _pillPopT += dt;
      const d = Config.coinRewardPillPopDuration;
      if (_pillPopT >= d) {
        _pillPopT = -1;
        _pillPop.scale = 1;
      } else {
        final u = Curves.easeOut.transform(_pillPopT / d);
        final k = u < .5 ? u * 2 : (1 - u) * 2;
        _pillPop.scale = 1 + (Config.coinRewardPillPopScale - 1) * k;
      }
    }
    final glowTarget = glow ? 1.0 : 0.0;
    if (_glowK != glowTarget) {
      final step = dt / Config.coinRewardGlowFade;
      _glowK = _glowK < glowTarget
          ? math.min(glowTarget, _glowK + step)
          : math.max(glowTarget, _glowK - step);
      label.color = Color.lerp(
        Config.menuSoft,
        Config.menuGold,
        (_glowK * 1.25).clamp(0.0, 1.0), // number: 0.2 s of the 0.25 s
      )!;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_glowK > 0) {
      _glowPaint.color = Config.menuGold.withValues(alpha: .75 * _glowK);
      canvas.drawRect(size.toRect().inflate(4), _glowPaint);
    }
    super.render(canvas);
  }

  @override
  void renderTree(Canvas canvas) {
    final dx = shakeOffset;
    if (dx == 0) {
      super.renderTree(canvas);
      return;
    }
    canvas.save();
    canvas.translate(dx, 0);
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final images = game.images;
    final plusIcon = Sprite(await images.load('menu/plus.png'));
    final coinIcon = Sprite(await images.load('menu/coin.png'));
    label = MenuText(
      formatCoins(_balance),
      fontSize: fontSize,
      color: Config.menuSoft,
    );
    _coinIcon = MenuIcon(coinIcon, size: Vector2.all(coinSize));
    _coinIcon.decorator.addLast(_coinPop = WiggleEffect(_coinIcon));
    // Mock `.glint`: 12 pt at left 12 / top -2 of the 24 pt coin box.
    _glint = _CoinGlint(position: Vector2(18, 4));
    _plusBox = RectangleComponent(
      size: Vector2.all(pillHeight),
      paint: Paint()..color = Config.menuPinkDark,
    );
    addAll([
      _plusBox,
      MenuIcon(
        plusIcon,
        size: Vector2.all(16),
        position: Vector2.all(pillHeight / 2),
        anchor: Anchor.center,
      ),
      label,
      _coinIcon,
    ]);
    _coinIcon.add(_glint);
    _layout();
  }

  void _layout() {
    final from = _countFrom;
    if (from == null) {
      _shown = _held ?? _balance;
    } else {
      final u = (_countT / _countDuration).clamp(0.0, 1.0);
      final eased = _countLinear ? u : 1 - math.pow(1 - u, 3);
      _shown = (from + (_balance - from) * eased).round();
    }
    label.text = formatCoins(_shown);
    const textX = pillHeight + plusGap;
    label.position = Vector2(textX, (pillHeight - label.height) / 2);
    final coinX = textX + label.width + coinGap;
    _coinIcon.position = Vector2(coinX, (pillHeight - coinSize) / 2);
    size = Vector2(coinX + coinSize + padRight, pillHeight);
    // Right-anchored: every width change re-pins the right edge.
    position = Vector2(_topRight.x - size.x, _topRight.y);
  }
}

/// White 4-point glint on the pill coin (mock `.glint`, a 12 pt star
/// from the 20-unit path `M0-10L2.2-2.2 10 0 ...`), centred on its
/// position; [opacity], [glintScale] and `angle` come from
/// [LiveCurves.glint].
class _CoinGlint extends PositionComponent {
  _CoinGlint({super.position})
    : super(size: Vector2.all(12), anchor: Anchor.center, priority: 5);

  double opacity = 0;
  double glintScale = 0;

  static final Path _star = Path()
    ..moveTo(0, -10)
    ..lineTo(2.2, -2.2)
    ..lineTo(10, 0)
    ..lineTo(2.2, 2.2)
    ..lineTo(0, 10)
    ..lineTo(-2.2, 2.2)
    ..lineTo(-10, 0)
    ..lineTo(-2.2, -2.2)
    ..close();

  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    if (opacity <= 0 || glintScale <= 0) return;
    _paint.color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.save();
    canvas.translate(6, 6);
    canvas.scale(0.6 * glintScale);
    canvas.drawPath(_star, _paint);
    canvas.restore();
  }
}

/// The pink 38 pt box in the top-left corner: home's settings gear and the
/// menu screens' back chevron share it. Owned by the game like [CoinPill]
/// and drawn BELOW the screens, whose transparent [MenuButton]s on top
/// take the taps (and draw the pressed shade). The box itself keeps full
/// opacity across screen-to-screen crossfades; only the glyph crossfades
/// (gear <-> back), and Shop <-> Skins shows one steady chevron.
class MenuCornerBox extends PositionComponent
    with GroupOpacity, HasGameReference<FlappySpikesGame> {
  MenuCornerBox({required Rect rect, super.priority})
    : super(position: rect.topLeft.toVector2(), size: rect.size.toVector2()) {
    decorator.addLast(_press = WiggleEffect(this));
  }

  late final WiggleEffect _press;

  /// Mirrors the press scale of the screen's transparent gear / back
  /// button on top (§8.1 press), so the visible box shrinks with it.
  double get pressScale => _press.scale;
  set pressScale(double value) => _press.scale = value;

  static const double gearSize = 26;
  static const double backSize = 22;

  late final MenuIcon _gear;
  late final MenuIcon _back;
  final Paint _fill = Paint()..color = Config.menuPink;
  double _gearMix = 1;

  /// Share of the glyph that is the gear (1 = home, 0 = Shop / Skins); the
  /// chevron gets the rest. Within the box's own [opacity].
  double get gearMix => _gearMix;
  set gearMix(double value) {
    _gearMix = value.clamp(0.0, 1.0);
    if (isLoaded) _applyMix();
  }

  void _applyMix() {
    _gear.opacity = _gearMix;
    _back.opacity = 1 - _gearMix;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final images = game.images;
    MenuIcon glyph(Image image, double side) => MenuIcon(
      Sprite(image),
      size: Vector2.all(side),
      position: size / 2,
      anchor: Anchor.center,
    );
    _gear = glyph(await images.load('menu/gear.png'), gearSize);
    _back = glyph(await images.load('menu/back.png'), backSize);
    _applyMix();
    addAll([_gear, _back]);
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _fill);
}

/// The equipped bird in the start block, drawn exactly like the in-game
/// bird at blend 0 (identity colours), scaled to the mock's 44 pt wide box
/// and centred in it.
///
/// Live (PRD-menu-v2 §8.2): a [BirdIdle] drives it — bob, idle flap,
/// blinks and a random action every 6–12 s (bob + flap only under reduce
/// motion); everything freezes while a dialog / ad is on top. A tap hops
/// it (−204 pt/s) with `flap.mp3` and 7 pink / gold squares.
class HomeBird extends PositionComponent
    with HasGameReference<FlappySpikesGame>, TapCallbacks {
  HomeBird({
    required Rect rect,
    required Look look,
    this.isActive,
    BirdIdle? idle,
  }) : idle = idle ?? BirdIdle(),
       super(
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       ) {
    _look = LookComponent(
      look: look,
      artScale: Config.lookScaleForHome(rect),
      position: size / 2,
      // Menus always render at colour stage 0: no stage blend.
    );
  }

  /// Hop power of a tap on the bird (−204 pt/s) and of START (−153).
  static const double tapHop = 1.2;
  static const double startHop = 0.9;

  late final LookComponent _look;
  final bool Function()? isActive;

  /// The idle model (exposed for tests).
  final BirdIdle idle;

  /// The look drawn; follows `menu.items` while the screen is up.
  Look get look => _look.look;
  set look(Look value) => _look.look = value;

  /// Exposed for tests.
  LookComponent get lookComponent => _look;

  /// A hop of [power] (1 = −170 pt/s) with the tap burst.
  void hop(double power) => idle.hop(power, burst: true);

  @override
  bool containsLocalPoint(Vector2 point) =>
      (isActive?.call() ?? true) && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    game.sound.play(Sfx.flap);
    hop(tapHop);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_look);
    add(_Burst(idle, origin: size / 2));
    game.menu.items.addListener(_onItemsChanged);
    _apply();
  }

  @override
  void onRemove() {
    game.menu.items.removeListener(_onItemsChanged);
    super.onRemove();
  }

  @override
  void update(double dt) {
    // §8.4: the look's own clock (wind-up key / animated gear) pauses with
    // the screen's idle clock, together with the bob / flap idle.
    _look.paused = game.liveMotionPaused;
    super.update(dt);
    if (!game.liveMotionPaused) idle.step(dt, still: game.reduceMotion);
    _apply();
  }

  void _apply() {
    final o = idle.offset;
    _look
      ..position = Vector2(size.x / 2 + o.dx, size.y / 2 + o.dy)
      ..angle = idle.angle
      ..scale = Vector2(idle.scaleX, idle.scaleY)
      ..flapOverride = idle.flap
      ..blink = idle.blinking;
  }

  void _onItemsChanged() => _look.look = game.menu.items.look;
}

/// The tap burst's squares, drawn above the bird around [origin] (the
/// bird's resting centre; they do not follow its bob).
class _Burst extends Component {
  _Burst(this._idle, {required this.origin}) : super(priority: 10);

  final BirdIdle _idle;
  final Vector2 origin;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    for (final p in _idle.particles) {
      _paint.color = p.color.withValues(alpha: p.opacity);
      canvas.drawRect(
        Rect.fromLTWH(origin.x + p.x, origin.y + p.y, p.size, p.size),
        _paint,
      );
    }
  }
}

/// The gold BIG HOOPS / SHIELD slot under START: video icon + label (+
/// shield icon), 3 pt background-coloured outline. A tap plays a rewarded
/// ad and then starts the run with that powerup (2.0 DEVIATION from PRD-1
/// §3.6: there is no armed / check state). No-ads owners get no video icon
/// (no ad); ad unavailable (and no No-ads): dimmed, still tappable (toast).
///
/// Live (§8.2, the home's focus): a 3.2 s pulse 1 -> 1.035 with a gold
/// glow, a light streak every 6.4 s and the camera icon nodding at each
/// pulse peak — driven by the home's [LiveClock] through [animate].
class PowerupSlotButton extends MenuButton {
  PowerupSlotButton({
    required Rect rect,
    required this.video,
    required this.shield,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: Config.menuGold,
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       ) {
    pulse = PulseEffect(
      this,
      amount: Config.homeSlotPulse,
      glowColor: Config.homeSlotGlow,
      glowBlur: Config.homeSlotGlowBlur,
      inflate: Config.homeSlotOutline,
    );
    streak = LightStreak(this);
    decorator
      ..addLast(pulse)
      ..addLast(streak);
  }

  late final PulseEffect pulse;
  late final LightStreak streak;

  /// Nod of the video icon (re-attached to every rebuilt icon).
  late final WiggleEffect cameraNod = WiggleEffect(this);

  /// The video icon while shown (tests).
  MenuIcon? videoIcon;

  /// True while [shrinkVideo] runs: the icon stays until it is gone.
  bool _shrinking = false;

  /// PRD-home-v3 §7: the video icon shrinks away (0.3 s) after the No-ads
  /// celebration; the slot then rebuilds without it.
  void shrinkVideo() {
    final icon = videoIcon;
    if (icon == null || _shrinking) return;
    _shrinking = true;
    add(ShrinkDriver(icon, onDone: () => _shrinking = false));
  }

  /// [LiveClock] binding: pulse, streak and nod at idle time [t]; all at
  /// rest when [still] (reduce motion).
  void animate(double t, bool still) {
    if (still) {
      pulse.rest();
      streak.progress = null;
      cameraNod.rest();
      return;
    }
    pulse.k = LiveCurves.pulse(t);
    streak.at(t);
    cameraNod.angle = LiveCurves.cameraNod(t) * math.pi / 180;
  }

  final Sprite video;
  final Sprite shield;

  Color outlineColor = const Color(0xFFF1F1F1);
  final Paint _outline = Paint();

  Powerup _shown = Powerup.none;
  bool _showVideo = true;
  bool _unavailable = false;

  /// The powerup the slot currently shows (exposed for tests).
  Powerup get shown => _shown;
  bool get unavailable => _unavailable;

  /// Whether the video (ad) icon is drawn (exposed for tests).
  bool get showsVideo => _showVideo;

  /// Visible label ("BIG HOOPS", "SHIELD"); exposed for tests.
  String get labelText => _label?.text ?? '';

  MenuText? _label;
  final List<Component> _content = [];

  static String labelFor(Powerup p) =>
      p == Powerup.shield ? 'SHIELD' : 'BIG HOOPS';

  void setState({
    required Powerup offered,
    required bool noAds,
    required bool adAvailable,
  }) {
    final showVideo = !noAds || _shrinking;
    final unavailable = !noAds && !adAvailable;
    dimmed = unavailable;
    if (offered == _shown &&
        showVideo == _showVideo &&
        unavailable == _unavailable &&
        _label != null) {
      return;
    }
    _shown = offered;
    _showVideo = showVideo;
    _unavailable = unavailable;
    if (isLoaded) _rebuild();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _rebuild();
  }

  void _rebuild() {
    removeAll(_content);
    _content.clear();
    final label = MenuText(
      labelFor(_shown),
      fontSize: 18,
      color: Config.menuPlum,
      letterSpacingEm: 0.04,
    );
    _label = label;
    final icon = _showVideo ? MenuIcon(video, size: Vector2.all(18)) : null;
    videoIcon = icon;
    if (icon != null) {
      cameraNod.target = icon;
      icon.decorator.addLast(cameraNod);
    }
    final items = <PositionComponent>[
      ?icon,
      label,
      if (_shown == Powerup.shield) MenuIcon(shield, size: Vector2(18, 20)),
    ];
    _content.addAll(items);
    HomeScreen._layoutRow(this, items, gap: 8);
  }

  @override
  void render(Canvas canvas) {
    _outline.color = outlineColor;
    canvas.drawRect(
      Rect.fromLTWH(
        -Config.homeSlotOutline,
        -Config.homeSlotOutline,
        width + 2 * Config.homeSlotOutline,
        height + 2 * Config.homeSlotOutline,
      ),
      _outline,
    );
    super.render(canvas);
  }
}

/// One pink home tile (mock `.tile`): icon above an uppercase label, as a
/// vertically centred column with a 6 pt gap; optional gold corner tag.
class MenuTile extends MenuButton {
  MenuTile({
    required Rect rect,
    required Sprite icon,
    required String label,
    required super.onPressed,
    Sprite? check,
    super.isActive,
  }) : _iconSprite = icon,
       _labelText = label,
       _checkSprite = check,
       super(
         color: Config.menuPink,
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  static const double iconGap = 6;
  static const double labelFontSize = 13;

  final Sprite _iconSprite;
  final String _labelText;
  final Sprite? _checkSprite;

  late final MenuIcon icon;
  late final MenuText label;
  MenuTag? _tag;
  String? _tagText;
  bool _owned = false;

  /// Gold corner tag text (null = none), e.g. "NEW" on Skins.
  String? get tag => _tagText;
  set tag(String? value) {
    _tagText = value;
    if (isLoaded) _applyTag();
  }

  /// No-ads tile after purchase: the soft check replaces the crossed-AD
  /// icon in the icon slot and the label reads "AD-FREE" (PO 2026-10-04:
  /// an inline check truncated the label in the 70 pt tile).
  bool get owned => _owned && !_flipHold;
  set owned(bool value) {
    _owned = value;
    if (isLoaded) _applyLabel();
  }

  /// Whether the icon slot currently shows the check (exposed for tests).
  bool get showsCheck => owned && _checkSprite != null;

  /// True from [flipToOwned] until the flip shows the new face.
  bool _flipHold = false;
  FlipEffect? _flip;

  /// The flip while it runs (tests).
  FlipDriver? flipDriver;

  /// PRD-home-v3 §7: the No-ads tile flips over (rotateY, 0.18 s out +
  /// 0.28 s in) to its owned face.
  void flipToOwned() {
    _flipHold = true;
    if (isLoaded) _applyLabel();
    var effect = _flip;
    if (effect == null) {
      effect = _flip = FlipEffect(this, vertical: false);
      decorator.addLast(effect);
    }
    flipDriver?.removeFromParent();
    add(
      flipDriver = FlipDriver(
        effect,
        onSwap: () {
          _flipHold = false;
          if (isLoaded) _applyLabel();
        },
        onDone: () => flipDriver = null,
      ),
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    icon = MenuIcon(
      _iconSprite,
      size: Vector2.all(Config.homeTileIconSize),
    );
    label = MenuText(
      _labelText,
      fontSize: labelFontSize,
      color: Config.menuSoft,
      letterSpacingEm: 0.06,
    );
    addAll([icon, label]);
    _applyLabel();
    _applyTag();
  }

  void _applyLabel() {
    // PRD-home-v3 §7: owned = lighter pink (pink 55 % over the background).
    color = owned ? Config.noAdsOwnedFill : Config.menuPink;
    label.text = owned ? 'AD-FREE' : _labelText;
    final check = showsCheck;
    icon
      ..sprite = check ? _checkSprite : _iconSprite
      ..size = Vector2.all(
        check ? Config.homeTileCheckSize : Config.homeTileIconSize,
      );
    // The column keeps the regular icon box so the label stays on the
    // same baseline as the other tiles; the check is centred in it.
    const iconBox = Config.homeTileIconSize;
    final groupHeight = iconBox + iconGap + label.height;
    final top = (height - groupHeight) / 2;
    icon.position = Vector2(
      (width - icon.width) / 2,
      top + (iconBox - icon.height) / 2,
    );
    label.position = Vector2(
      (width - label.width) / 2,
      top + iconBox + iconGap,
    );
  }

  void _applyTag() {
    _tag?.removeFromParent();
    _tag = null;
    final text = _tagText;
    if (text == null) return;
    // Mock: right -5, top -6 (sticks out of the tile's corner).
    final tag = _TileTag(text, tileWidth: width);
    _tag = tag;
    tagWobble.target = tag;
    tag.decorator.addLast(tagWobble);
    add(tag);
  }

  /// The tag's idle wobble (§8.2: Skins NEW tag, driven by the home's
  /// [LiveClock]); re-attached to every new tag.
  late final WiggleEffect tagWobble = WiggleEffect(this);

  /// Exposed for tests.
  PositionComponent? get tagComponent => _tag;
}

/// A [MenuTag] anchored by its top-right corner 5 pt right / 6 pt above the
/// tile's top-right corner.
class _TileTag extends MenuTag {
  _TileTag(super.text, {required this.tileWidth}) : super(priority: 10);

  final double tileWidth;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    position = Vector2(tileWidth + 5 - width, -6);
  }
}

/// Leaderboard row (y 574 at 711): 70x70 trophy tile + "Best Score" /
/// "Games Played" (21 pt, stage fg, line-height 1.15) and a pink
/// "LEADERBOARD ›" caption; the whole row opens the leaderboards.
class LeaderboardRow extends MenuButton {
  LeaderboardRow({
    required Rect rect,
    required this.trophy,
    required this.bestScore,
    required this.gamesPlayed,
    required super.onPressed,
    super.isActive,
  }) : super(
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final Sprite trophy;

  /// The trophy's idle wiggle (§8.2, driven by the home's [LiveClock]).
  late final WiggleEffect trophyWiggle = WiggleEffect(this);
  int bestScore;
  int gamesPlayed;

  static const double statsFontSize = 21;
  static const double statsLineHeight = 1.15;
  static const double captionFontSize = 11;

  late final MenuText bestLabel;
  late final MenuText gamesLabel;
  late final MenuText caption;

  Color _tint = const Color(0xFF828282);

  set tint(Color value) {
    _tint = value;
    if (isLoaded) {
      bestLabel.color = value;
      gamesLabel.color = value;
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    const tileSize = Config.homeLeaderboardSize;
    final icon = MenuIcon(
      trophy,
      size: Vector2.all(Config.homeTrophySize),
      position: Vector2.all(tileSize / 2),
      anchor: Anchor.center,
    );
    trophyWiggle.target = icon;
    icon.decorator.addLast(trophyWiggle);
    final tile = RectangleComponent(
      size: Vector2.all(tileSize),
      paint: Paint()..color = Config.menuPink,
      children: [icon],
    );
    const textX = tileSize + Config.homeStatsGap;
    const line = statsFontSize * statsLineHeight;
    // The caption inherits line-height 1.15 (mock); the three lines are
    // centred as one block in the 70 pt row.
    const blockHeight = 2 * line + captionFontSize * statsLineHeight;
    const top = (tileSize - blockHeight) / 2;
    bestLabel = MenuText(
      'Best Score: $bestScore',
      fontSize: statsFontSize,
      color: _tint,
      lineHeight: statsLineHeight,
      position: Vector2(textX, top),
    );
    gamesLabel = MenuText(
      'Games Played: $gamesPlayed',
      fontSize: statsFontSize,
      color: _tint,
      lineHeight: statsLineHeight,
      position: Vector2(textX, top + line),
    );
    caption = MenuText(
      'LEADERBOARD ›',
      fontSize: captionFontSize,
      color: Config.menuPink,
      letterSpacingEm: 0.1,
      lineHeight: statsLineHeight,
      position: Vector2(textX, top + 2 * line),
    );
    addAll([tile, bestLabel, gamesLabel, caption]);
  }

  void setStats({required int bestScore, required int gamesPlayed}) {
    this.bestScore = bestScore;
    this.gamesPlayed = gamesPlayed;
    if (isLoaded) {
      bestLabel.text = 'Best Score: $bestScore';
      gamesLabel.text = 'Games Played: $gamesPlayed';
    }
  }
}

/// Invisible long-press target (the title -> debug panel). Plain taps are
/// consumed too, harmlessly (nothing on the home screen starts on a tap).
class _LongPressArea extends PositionComponent with TapCallbacks {
  _LongPressArea({
    required this.onLongPress,
    required this.isActive,
    super.position,
    super.size,
  });

  final void Function() onLongPress;
  final bool Function() isActive;

  @override
  bool containsLocalPoint(Vector2 point) =>
      isActive() && super.containsLocalPoint(point);

  @override
  void onLongTapDown(TapDownEvent event) => onLongPress();
}
