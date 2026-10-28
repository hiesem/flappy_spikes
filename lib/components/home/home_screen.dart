// region P26-G6b
import '../../progression/flight_guide.dart';
// endregion
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
import '../../menu/home_mode.dart';
import '../../menu/powerup_slot.dart';
import '../../services/iap_service.dart';
import '../../skins/look.dart';
import '../levels/emblem_view.dart';
import '../look_component.dart';
import '../ui/bird_idle.dart';
import '../ui/flip.dart';
import '../ui/live_effects.dart';
import 'menu_primitives.dart';
import 'mode_button.dart';
// region P26-G2b
import '../progression/streak_strip.dart';

// endregion

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
  'menu/lock.png',
  // region P26-LB4 — O63 removes the Home medal asset.
  // endregion P26-LB4
  'menu/logo.png', // owner 2026-10-17: the logo replaces the title text
];

/// The 2.0 home screen, v3 layout (PRD-home-v3 §3, approved design
/// `screen_home_final_v2.html`): settings gear, trophy and coin pill in the
/// top row, title + one-line subtitle, the level emblem with the equipped
/// bird on it (tap: LEVELS) flanked by BEST / LAST, START + the powerup
/// slot centred below it, and the Shop / Skins / Invite / No-ads tiles.
/// Replaces the 1.0 `StartPanel` and the PRD-1 layout.
///
/// Every button routes to a [FlappySpikesGame] method; this component only
/// draws and keeps itself in sync with the menu state (polled each frame —
/// cheap, and it also catches changes without a notifier such as an ad
/// finishing loading, the no-ads flag or a claimed level). Text uses the
/// stage foreground (Tintable); chrome is the fixed menu pink.
class HomeScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity
    implements Tintable {
  HomeScreen() : super(priority: 20);

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

  // region P26-LB4
  /// The trophy opens our board and wiggles every 10 s.
  late final MenuButton trophyButton;
  late final WiggleEffect trophyWiggle;

  // endregion P26-LB4
  /// The Flappy Spikes logo (owner 2026-10-17, size S: 150 pt wide), in its
  /// own colours (not stage-tinted); top-centre at [Config.homeTitlePositionFor].
  late final SpriteComponent title;
  late final MenuText subtitle;

  /// The level emblem under the bird (§3.1 / §3.2).
  late final EmblemView emblem;
  // region P26-G4a
  /// Q26: a persisted, one-shot hint; tab dots have their own seen state.
  MenuTag? levelsNewTag;
  WiggleEffect? _levelsTagWobble;

  void _syncLevelsNewTag() {
    final storage = game.storage;
    final pendingDot =
        storage.worldsReached > storage.worldsSeen ||
        // region P26-G6b
        flightGuideHasDot(storage.metElements, storage.guideSeenCount);
        // endregion
    final shown =
        storage.gamesPlayed > 3 &&
        storage.homeLevelsTag &&
        pendingDot &&
        game.menu.levels.pendingLevelUp == null &&
        _heldLevel == null;
    if (shown == (levelsNewTag != null)) return;
    levelsNewTag?.removeFromParent();
    levelsNewTag = null;
    _levelsTagWobble = null;
    if (!shown) return;
    final plate = Config.homePlateCentreFor(game.viewHeight);
    final stageScale = Config.homeStageScaleFor(game.viewHeight);
    final tag = MenuTag(
      'NEW',
      position: Vector2(plate.dx + 54 * stageScale, plate.dy - 92 * stageScale),
      priority: 10,
    );
    final wobble = WiggleEffect(tag);
    tag.decorator.addLast(wobble);
    levelsNewTag = tag;
    _levelsTagWobble = wobble;
    add(tag);
  }

  // endregion
  late final HomeBird bird;
  late final HomeStat bestStat;
  late final HomeStat lastStat;
  late final MenuButton startButton;
  late final PowerupSlotButton slotButton;

  /// PRD-2.2 §2 the VERSUS / FREE FLY button above START and the VS tag on
  /// START (VERSUS only).
  late final ModeButton modeButton;
  late final VsTag vsTag;
  late final MenuTile shopTile;
  late final MenuTile skinsTile;
  late final MenuTile inviteTile;
  late final MenuTile noAdsTile;

  /// The screen's idle clock (§8.2 live effects).
  late final LiveClock clock;

  List<MenuTile> get tiles => [shopTile, skinsTile, inviteTile, noAdsTile];

  bool _isActive() => active;

  /// True once the screen was taken off the tree (e.g. a replay right
  /// after it was added) — see [MenuScreen.built].
  bool get _detached => parent == null || isRemoving || isRemoved;
  bool _built = false;

  /// Whether [onLoad] ran to the end.
  bool get built => _built;

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
    // region P26-LB4
    final trophyRect = Config.homeTrophyRectFor(h);
    final trophyGlow = _TrophyGlow(position: trophyRect.topLeft.toVector2());
    final trophyIcon = MenuIcon(
      icon('trophy'),
      size: Vector2.all(Config.homeTrophyIconSize),
      position: trophyRect.size.toVector2() / 2,
      anchor: Anchor.center,
    );
    trophyWiggle = WiggleEffect(trophyIcon);
    trophyIcon.decorator.addLast(trophyWiggle);
    trophyButton = MenuButton(
      color: Config.menuPink,
      position: trophyRect.topLeft.toVector2(),
      size: trophyRect.size.toVector2(),
      onPressed: game.openBoard,
      isActive: _isActive,
      children: [trophyIcon],
    );
    // endregion P26-LB4
    // §8.2: one idle clock for the screen's live effects.
    clock = LiveClock(
      paused: () => game.liveMotionPaused,
      still: () => game.reduceMotion,
    );

    // region P26-G2b
    add(StreakStrip(isActive: () => active && !game.modalPopupOpen));
    // endregion

    // --- title ------------------------------------------------------------
    title = SpriteComponent(
      sprite: icon('logo'),
      size: Vector2(
        Config.homeLogoWidthFor(h),
        Config.homeLogoWidthFor(h) / Config.homeLogoAspect,
      ),
      position: Config.homeTitlePositionFor(h),
      anchor: Anchor.topCenter,
    );
    subtitle = MenuText(
      Config.tagline, // PRD-2.3 §12
      fontSize: Config.homeSubtitleFontSize,
      color: _tint,
      letterSpacingEm: Config.homeSubtitleLetterSpacing,
      position: Config.homeSubtitlePositionFor(h),
      anchor: Anchor.topCenter,
    );
    // Long-press on the title opens the debug panel (debug builds / Linux).
    final titleHotspot = _LongPressArea(
      position: Vector2(
        Config.homeTrophyLeft + Config.homeTopRowHeight + 4,
        Config.homeTitleTop,
      ),
      size: Vector2(
        Config.worldWidth - 2 * (Config.homeTrophyLeft + 42),
        Config.homeSubtitleTop +
            Config.homeSubtitleFontSize * kNormalLineHeight -
            Config.homeTitleTop,
      ),
      onLongPress: game.openDebugPanel,
      isActive: () => active && FlappySpikesGame.debugAvailable,
    );

    // --- emblem + bird stage, BEST / LAST ------------------------------------
    final stage = Config.homeStageRectFor(h);
    final plate = Config.homePlateCentreFor(h);
    emblem = EmblemView(
      // region P26-J2
      progression: true,
      // endregion
      level: _displayLevel,
      artScale: Config.homeEmblemScaleFor(h),
      position: plate.toVector2(),
    );
    bird = HomeBird(
      rect: stage,
      centre: (plate - stage.topLeft).toVector2(),
      artScale: Config.homeBirdScaleFor(h),
      look: game.menu.items.look,
      isActive: _isActive,
      onTap: game.tapHomeEmblem,
    );
    bestStat = HomeStat(
      rect: Config.homeFlankRectFor(h, right: false),
      label: 'BEST',
      gold: true,
    );
    lastStat = HomeStat(
      rect: Config.homeFlankRectFor(h, right: true),
      label: 'LAST',
      alignRight: true,
    );

    // --- START + powerup slot -------------------------------------------------
    final startRect = Config.homeStartRectFor(h);
    startButton = MenuButton(
      color: Config.menuPink,
      position: startRect.topLeft.toVector2(),
      size: startRect.size.toVector2(),
      onPressed: game.startRun,
      isActive: _isActive,
    );
    _layoutRow(startButton, [
      MenuIcon(icon('play'), size: Vector2.all(Config.homeStartIconSize)),
      MenuText(
        'START',
        fontSize: Config.homeStartFontSize,
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
    // PRD-2.2 §2: the mode button (added before START, so START keeps the
    // 1 pt where the button's 6 pt hit padding reaches over it) and the VS
    // tag (after START: drawn on its corner).
    final mode = game.homeMode;
    _mode = mode;
    modeButton = ModeButton(
      rect: Config.homeModeRectFor(h),
      mode: mode,
      onPressed: game.toggleHomeMode,
      isActive: _isActive,
    );
    vsTag = VsTag(
      rect: Config.homeVsTagRectFor(h),
      visible: mode == HomeMode.versus,
    );

    // --- tiles ------------------------------------------------------------
    MenuTile tile(int index, String name, String label, void Function() tap) =>
        MenuTile(
          rect: Config.homeTileRectFor(h, index),
          icon: icon(name),
          label: label,
          onPressed: tap,
          check: icon('check'),
          lock: icon('lock'),
          isActive: _isActive,
        );
    // §8.2: tiles press with `sk_tap`.
    shopTile = tile(0, 'shop', 'SHOP', () => game.openShop(sfx: Sfx.skTap));
    skinsTile = tile(1, 'skins', 'SKINS', game.openSkins);
    inviteTile = tile(2, 'invite', 'INVITE', game.invite);
    // PO change 2026-10-05: the tile starts the store purchase straight
    // away; the popup is the automatic launch upsell only.
    noAdsTile = tile(3, 'noads', 'NO ADS', () => game.buyNoAds('home_tile'));

    // region P26-G4a
    clock.bind((t, still) {
      _levelsTagWobble?.setPose(
        still ? (scale: 1, degrees: 0) : LiveCurves.newTagWobble(t),
      );
    });
    // endregion
    clock
      // region P26-LB4
      ..bind((t, still) => trophyGlow.ringWidth = still ? 2 : 3 + math.sin(t * 2))
      // endregion P26-LB4
      ..bind(slotButton.animate)
      ..bind(
        (t, still) => skinsTile.tagWobble.setPose(
          still ? (scale: 1, degrees: 0) : LiveCurves.newTagWobble(t),
        ),
      )
      ..bind(
        (t, still) => trophyWiggle.setPose(
          still ? (scale: 1, degrees: 0) : LiveCurves.trophyWiggle(t),
        ),
      )
      // §3.2: the emblem's sweep + per-level idle; reduce motion freezes
      // it (static picture, no sweep).
      ..bind((t, still) {
        emblem
          ..t = still ? 0 : t
          ..shine = !still;
      });

    addAll([
      clock,
      gearButton,
      // region P26-LB4
      trophyGlow,
      trophyButton,
      // endregion P26-LB4
      titleHotspot,
      title,
      subtitle,
      emblem,
      bird,
      bestStat,
      lastStat,
      slotButton,
      modeButton,
      startButton,
      vsTag,
      ...tiles,
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
  bool _locked = false; // PRD-2.3 §26: the Shop / Skins lock shown on the tiles
  bool? _noAds;
  bool? _noAdsPending;
  int? _best;
  int? _last;
  bool _lastKnown = false;

  /// The level the emblem shows: the current one, except that a LEVEL UP
  /// still owed shows the last claimed level until its CLAIM (the emblem
  /// then upgrades with a pop, §4.3).
  int get _displayLevel {
    final held = _heldLevel;
    if (held != null) return held;
    final levels = game.menu.levels;
    final pending = levels.pendingLevelUp;
    return pending?.fromLevel ?? levels.level;
  }

  /// The level shown between a LEVEL UP claim and its upgrade pop (§4.3:
  /// the emblem upgrades after the reward count-up); null = live level.
  int? _heldLevel;

  /// Keeps the emblem at [level] until [playUpgradePop].
  void holdLevel(int level) => _heldLevel = level;

  @override
  void update(double dt) {
    super.update(dt);
    if (_built) {
      _sync();
      _updatePop(dt);
    }
  }

  HomeMode? _mode;

  /// PRD-2.2 §2.1 shows [mode] on the button and the VS tag; [animate] for
  /// a tap (slide + pop / fade), else at once.
  void syncMode({bool animate = true}) {
    if (!_built) return;
    final mode = game.homeMode;
    if (mode == _mode) return;
    _mode = mode;
    modeButton.setMode(mode, animate: animate);
    vsTag.setShown(mode == HomeMode.versus, animate: animate);
  }

  void _sync({bool force = false}) {
    final menu = game.menu;
    // PRD-2.2 §2.2 a mode change from elsewhere ("Delete my data") shows
    // at once.
    syncMode(animate: false);
    final hasNew = menu.items.hasNewBadge;
    // PRD-2.3 §26.2: below the unlock best the SHOP and SKINS tiles show a
    // lock badge, and the NEW badge is hidden (no nagging before the unlock).
    final locked = menu.locked;
    if (force || hasNew != _hasNew || locked != _locked) {
      _hasNew = hasNew;
      _locked = locked;
      skinsTile.tag = hasNew && !locked ? 'NEW' : null;
      shopTile.locked = locked;
      skinsTile.locked = locked;
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

    // §3.1: BEST / LAST and the emblem follow the storage / levels.
    final storage = game.storage;
    final best = storage.bestScore;
    final last = storage.lastScore;
    if (force || best != _best) {
      _best = best;
      bestStat.value = formatCoins(best);
    }
    if (force || last != _last || _lastKnown != (last != null)) {
      _last = last;
      _lastKnown = last != null;
      // Unranked / new players: "—" before the first run.
      lastStat.value = last == null ? '—' : formatCoins(last);
    }
    emblem.level = _displayLevel;
    // region P26-G4a
    _syncLevelsNewTag();
    // endregion
  }

  /// Re-reads all menu state now (instead of on the next frame).
  void refresh() {
    if (_built) _sync(force: true);
  }

  double _popT = -1;

  /// Whether the upgrade pop is running (tests).
  bool get popping => _popT >= 0;

  /// §4.3: after a LEVEL UP claim the emblem upgrades with a pop (scale
  /// 0.6 -> 1.15 -> 1 over 0.7 s, build74 `evo`).
  void playUpgradePop() {
    _heldLevel = null;
    if (!_built) return;
    _sync(force: true);
    _popT = 0;
    emblem.popScale = upgradePopScale(0);
  }

  /// The build74 pop curve at [u] (0..1 of the 0.7 s).
  static double upgradePopScale(double u) {
    final k = u.clamp(0.0, 1.0);
    return .6 + .4 * (1 - math.pow(1 - k, 3)) + math.sin(k * math.pi) * .15;
  }

  void _updatePop(double dt) {
    if (_popT < 0) return;
    _popT += dt;
    final u = _popT / Config.homeEmblemPopDuration;
    if (u >= 1) {
      _popT = -1;
      emblem.popScale = 1;
    } else {
      emblem.popScale = upgradePopScale(u);
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (_built) {
      subtitle.color = color;
      bestStat.tint = color;
      lastStat.tint = color;
    }
  }
}

/// BEST / LAST column flanking the emblem (§3.1, build76 `.flank`): the
/// label (12 pt, 0.18 em, stage fg at 85 %) over the number (30 pt, faux
/// bold; BEST gold, LAST stage fg). Left-aligned, or right-aligned
/// ([alignRight]). A 4+ digit number is shrunk to fit the column clear of
/// LEGEND's wings ([Config.homeFlankNumberMaxWidth]).
class HomeStat extends PositionComponent {
  HomeStat({
    required Rect rect,
    required this.label,
    this.gold = false,
    this.alignRight = false,
  }) : super(position: rect.topLeft.toVector2(), size: rect.size.toVector2());

  final String label;
  final bool gold;
  final bool alignRight;

  late final MenuText labelText;
  MenuText? _number;
  String _value = '';
  Color _tint = const Color(0xFF828282);

  /// The number component (tests).
  MenuText get numberText => _number!;

  /// The number shown ("1 250", "—").
  String get value => _value;
  set value(String text) {
    if (text == _value && _number != null) return;
    _value = text;
    if (isLoaded) _buildNumber();
  }

  set tint(Color color) {
    _tint = color;
    if (!isLoaded) return;
    labelText.color = color.withValues(alpha: color.a * .85);
    if (!gold) _buildNumber();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    labelText = MenuText(
      label,
      fontSize: Config.homeFlankLabelFontSize,
      color: _tint.withValues(alpha: .85),
      letterSpacingEm: Config.homeFlankLabelLetterSpacing,
      lineHeight: Config.homeFlankLabelLine / Config.homeFlankLabelFontSize,
    );
    labelText.position = Vector2(alignRight ? width - labelText.width : 0, 0);
    add(labelText);
    _buildNumber();
  }

  void _buildNumber() {
    _number?.removeFromParent();
    final color = gold ? Config.menuGold : _tint;
    final number = MenuText(
      _value,
      fontSize: Config.homeFlankNumberFontSize,
      color: color,
      letterSpacingEm: Config.homeFlankNumberLetterSpacing,
      lineHeight: Config.homeFlankNumberLine / Config.homeFlankNumberFontSize,
      strokeWidth: gold ? .6 : .5,
    );
    // §3.1: 4+ digits shrink the font so the number fits the column.
    final digits = _value.replaceAll(RegExp(r'[^0-9]'), '').length;
    const maxWidth = Config.homeFlankNumberMaxWidth;
    final fit = digits >= 4 && number.width > maxWidth
        ? maxWidth / number.width
        : 1.0;
    final top = Config.homeFlankLabelLine + Config.homeFlankLabelGap;
    number
      ..scale = Vector2.all(fit)
      ..position = Vector2(
        alignRight ? width - number.width * fit : 0,
        top + Config.homeFlankNumberLine * (1 - fit) / 2,
      );
    _number = number;
    add(number);
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

  /// The wallet balance ([target] adds the not-yet-animated rewards).
  int get balance => _balance;
  set balance(int value) {
    if (value == _balance) return;
    _balance = value;
    if (isLoaded && _countFrom == null && _held == null) _layout();
  }

  int _reserved = 0;

  /// Coins credited (or about to be) whose reward animation has not
  /// counted them in yet: the pill never shows them early, so each
  /// [CoinRewardAnimation] counts only its own amount (e.g. a queued
  /// No-ads bonus stays out of a LEVEL UP count-up).
  int get reserved => _reserved;

  /// The number the pill settles on: [balance] minus [reserved].
  int get target => _balance - _reserved;

  /// Keeps [amount] out of the shown number until [unreserve]d.
  void reserve(int amount) {
    if (amount <= 0) return;
    _reserved += amount;
    if (isLoaded && _countFrom == null && _held == null) _layout();
  }

  /// Lets [amount] reserved coins count in (the next count-up includes
  /// them; called right before a reward's [releaseHold]).
  void unreserve(int amount) {
    if (amount <= 0) return;
    _reserved = math.max(0, _reserved - amount);
    if (isLoaded && _countFrom == null && _held == null) _layout();
  }

  int? _held;

  /// Whether the number is frozen by [hold] (a coin reward in flight).
  bool get held => _held != null;

  /// PRD-2.2 §33.4 item 5: a count-up, hold, pop, shake, flash or glow is
  /// running (the menu is not idle; the idle glint does not count).
  bool get busy =>
      _countFrom != null ||
      _held != null ||
      _popT >= 0 ||
      _pillPopT >= 0 ||
      _shakeT >= 0 ||
      _flashT >= 0 ||
      glow ||
      _glowK > 0;

  /// Freezes the number on what it shows now (or, mid count, on where
  /// that count ends): the wallet can be credited while the reward's coins
  /// are still flying (PRD-menu-v2 §8.3).
  void hold() {
    _held ??= _countFrom != null ? target : _shown;
  }

  /// Ends a [hold]: counts from the number shown now (the frozen one, or
  /// where a running count is) to [target] over [duration] s ([linear] =
  /// the reward's even count, else ease-out).
  void releaseHold({
    double duration = Config.coinRewardCountDuration,
    bool linear = false,
  }) {
    if (_held == null) return;
    _held = null;
    countFrom(_shown, duration: duration, linear: linear);
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

  /// Counts the number from [from] to [target] over [duration] s
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
      _shown = _held ?? target;
    } else {
      final u = (_countT / _countDuration).clamp(0.0, 1.0);
      final eased = _countLinear ? u : 1 - math.pow(1 - u, 3);
      _shown = (from + (target - from) * eased).round();
    }
    // PRD-2.3.1 §12.5 the pill stays clear of the Home medal button: a
    // number wider than its room shrinks (the pill keeps its max width).
    label.fitWidth(
      formatCoins(_shown),
      Config.homeCoinPillMaxWidth -
          (pillHeight + plusGap + coinGap + coinSize + padRight),
    );
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

/// The equipped bird standing on the home emblem (PRD-home-v3 §3.1),
/// drawn like the in-game bird at blend 0 (identity colours), its art-box
/// centre on [centre] (the plate centre) at [artScale] points per art unit
/// (1.32 at full size). The component covers the whole emblem stage: a tap
/// anywhere on it hops the bird and calls [onTap] (open LEVELS, §3.3).
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
    Vector2? centre,
    double? artScale,
    this.isActive,
    this.onTap,
    BirdIdle? idle,
  }) : idle = idle ?? BirdIdle(),
       super(position: rect.topLeft.toVector2(), size: rect.size.toVector2()) {
    this.centre = centre ?? size / 2;
    _look = LookComponent(
      look: look,
      artScale: artScale ?? Config.homeBirdScale,
      anchor: Anchor.center,
      position: this.centre.clone(),
      // Menus always render at colour stage 0: no stage blend.
    );
  }

  /// The bird's resting art-box centre in local coordinates.
  late final Vector2 centre;

  /// Called after a tap's hop (the home emblem: LEVELS).
  final void Function()? onTap;

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
    final tap = onTap;
    if (tap != null) withMenuKnock(this, tap);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_look);
    add(_Burst(idle, origin: centre));
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
      ..position = Vector2(centre.x + o.dx, centre.y + o.dy)
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
      fontSize: Config.homeSlotFontSize,
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
    Sprite? lock,
    super.isActive,
  }) : _iconSprite = icon,
       _labelText = label,
       _checkSprite = check,
       _lockSprite = lock,
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
  final Sprite? _lockSprite;

  bool _locked = false;
  _LockBadge? _lockBadge;

  /// PRD-2.3 §26.2: the lock badge while the screen behind this tile is
  /// locked (the tile still opens it).
  bool get locked => _locked;
  set locked(bool value) {
    if (_locked == value) return;
    _locked = value;
    if (isLoaded) _applyLock();
  }

  /// The lock badge while it is shown (tests).
  PositionComponent? get lockBadgeComponent => _lockBadge;

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
    icon = MenuIcon(_iconSprite, size: Vector2.all(Config.homeTileIconSize));
    label = MenuText(
      _labelText,
      fontSize: labelFontSize,
      color: Config.menuSoft,
      letterSpacingEm: 0.06,
    );
    addAll([icon, label]);
    _applyLabel();
    _applyTag();
    _applyLock();
  }

  void _applyLock() {
    _lockBadge?.removeFromParent();
    _lockBadge = null;
    final sprite = _lockSprite;
    if (!_locked || sprite == null) return;
    final badge = _LockBadge(sprite, tileWidth: width);
    _lockBadge = badge;
    add(badge);
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

/// PRD-2.3 §26.2: the lock badge of a locked Home tile: a small gold square
/// with the padlock, in the corner where the NEW tag sits.
class _LockBadge extends PositionComponent {
  _LockBadge(this.sprite, {required this.tileWidth}) : super(priority: 10);

  final Sprite sprite;
  final double tileWidth;
  final Paint _paint = Paint()..color = Config.menuGold;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2.all(Config.homeLockBadgeSize);
    position = Vector2(tileWidth + 5 - size.x, -6);
    add(
      MenuIcon(
        sprite,
        size: Vector2.all(Config.homeLockIconSize),
        position: Vector2.all((Config.homeLockBadgeSize - Config.homeLockIconSize) / 2),
      ),
    );
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
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

// region P26-LB4
class _TrophyGlow extends PositionComponent {
  _TrophyGlow({super.position}) : super(size: Vector2.all(38));
  double ringWidth = 2;
  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect().inflate(ringWidth / 2), Paint()
      ..color = const Color(0xffffb529)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth);
  }
}
// endregion P26-LB4
