import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/events.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/tintable.dart';
import '../../menu/powerup_slot.dart';
import '../../menu/skin_catalog.dart';
import '../skin_sprite.dart';
import 'menu_primitives.dart';

/// Images the home screen draws (all under `assets/images/`).
const List<String> kHomeImages = [
  'menu/plus.png',
  'menu/coin.png',
  'menu/gear.png',
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

  late final CoinPill coinPill;
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

  List<MenuTile> get tiles => [shopTile, skinsTile, inviteTile, noAdsTile];

  bool _isActive() => active;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final h = game.viewHeight;
    final images = game.images;
    final loaded = await Future.wait(kHomeImages.map(images.load));
    final sprites = {
      for (var i = 0; i < kHomeImages.length; i++)
        kHomeImages[i]: Sprite(loaded[i]),
    };
    Sprite icon(String name) => sprites['menu/$name.png']!;

    // --- top row ----------------------------------------------------------
    coinPill = CoinPill(
      plusIcon: icon('plus'),
      coinIcon: icon('coin'),
      initialBalance: game.menu.wallet.balance,
      position: Config.homeCoinPillPositionFor(h),
      onPressed: () => game.openShop(scrollToCoins: true),
      isActive: _isActive,
    );
    final gearRect = Config.homeGearRectFor(h);
    gearButton = MenuButton(
      color: Config.menuPink,
      position: gearRect.topLeft.toVector2(),
      size: gearRect.size.toVector2(),
      onPressed: game.openSettings,
      isActive: _isActive,
      children: [
        MenuIcon(
          icon('gear'),
          size: Vector2.all(26),
          position: gearRect.size.toVector2() / 2,
          anchor: Anchor.center,
        ),
      ],
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
      sprites: await SkinSprites.load(images, game.menu.skins.equippedSkin),
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
      check: icon('check'),
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
    shopTile = tile(0, 'shop', 'SHOP', game.openShop);
    skinsTile = tile(1, 'skins', 'SKINS', game.openSkins);
    inviteTile = tile(2, 'invite', 'INVITE', game.invite);
    noAdsTile = tile(3, 'noads', 'NO ADS', () => game.openNoAdsPopup('home_tile'));

    leaderboard = LeaderboardRow(
      rect: Config.homeLeaderboardRectFor(h),
      trophy: icon('trophy'),
      bestScore: bestScore,
      gamesPlayed: gamesPlayed,
      onPressed: game.showLeaderboard,
      isActive: _isActive,
    );

    addAll([
      coinPill,
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

  int? _balance;
  bool? _hasNew;
  bool? _noAds;
  String? _skin;

  @override
  void update(double dt) {
    super.update(dt);
    _sync();
  }

  void _sync({bool force = false}) {
    final menu = game.menu;
    final balance = menu.wallet.balance;
    if (force || balance != _balance) {
      _balance = balance;
      coinPill.balance = balance;
    }
    final hasNew = menu.skins.hasNewBadge;
    if (force || hasNew != _hasNew) {
      _hasNew = hasNew;
      skinsTile.tag = hasNew ? 'NEW' : null;
    }
    final noAds = menu.noAds;
    if (force || noAds != _noAds) {
      _noAds = noAds;
      // PRD-1 §3.5: owners keep the tile, dimmed, as "AD-FREE ✓".
      noAdsTile
        ..dimmed = noAds
        ..owned = noAds;
    }
    final skin = menu.skins.equippedSkin;
    if (force || skin.id != _skin) {
      _skin = skin.id;
      if (bird.sprites.skin.id != skin.id) {
        _swapBird(skin);
      }
    }
    slotButton.setState(
      offered: menu.slot.offered,
      armed: menu.slot.armed,
      noAds: noAds,
      adAvailable: game.monetization.ads.isAvailable,
    );
    slotButton.outlineColor = game.stageBackground;
  }

  Future<void> _swapBird(SkinDef skin) async {
    final sprites = await SkinSprites.load(game.images, skin);
    if (isMounted) bird.sprites = sprites;
  }

  /// Re-reads all menu state now (instead of on the next frame).
  void refresh() {
    if (isLoaded) _sync(force: true);
  }

  void setStats({required int bestScore, required int gamesPlayed}) {
    this.bestScore = bestScore;
    this.gamesPlayed = gamesPlayed;
    if (isLoaded) {
      leaderboard.setStats(bestScore: bestScore, gamesPlayed: gamesPlayed);
    }
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (isLoaded) {
      title.color = color;
      for (final line in subtitle) {
        line.color = color;
      }
      leaderboard.tint = color;
    }
  }
}

/// Coin balance pill (mock `.pill`): darker 38x38 "+" box, balance in soft
/// pink, gold coin; grows with the number of digits. The whole pill opens
/// the Shop at the coin packs.
class CoinPill extends MenuButton {
  CoinPill({
    required this.plusIcon,
    required this.coinIcon,
    required int initialBalance,
    required super.onPressed,
    super.isActive,
    super.position,
  }) : _balance = initialBalance,
       super(color: Config.menuPink, size: Vector2(0, pillHeight));

  static const double pillHeight = Config.homeTopRowHeight;
  static const double plusGap = 9; // "+" box -> text
  static const double coinGap = 8; // text -> coin
  static const double coinSize = 24;
  static const double padRight = 12;
  static const double fontSize = 20;

  final Sprite plusIcon;
  final Sprite coinIcon;
  int _balance;

  late final MenuText label;
  late final MenuIcon _coinIcon;

  int get balance => _balance;
  set balance(int value) {
    _balance = value;
    if (isLoaded) _layout();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    label = MenuText(
      formatCoins(_balance),
      fontSize: fontSize,
      color: Config.menuSoft,
    );
    _coinIcon = MenuIcon(coinIcon, size: Vector2.all(coinSize));
    addAll([
      RectangleComponent(
        size: Vector2.all(pillHeight),
        paint: Paint()..color = Config.menuPinkDark,
      ),
      MenuIcon(
        plusIcon,
        size: Vector2.all(16),
        position: Vector2.all(pillHeight / 2),
        anchor: Anchor.center,
      ),
      label,
      _coinIcon,
    ]);
    _layout();
  }

  void _layout() {
    label.text = formatCoins(_balance);
    const textX = pillHeight + plusGap;
    label.position = Vector2(textX, (pillHeight - label.height) / 2);
    final coinX = textX + label.width + coinGap;
    _coinIcon.position = Vector2(coinX, (pillHeight - coinSize) / 2);
    size = Vector2(coinX + coinSize + padRight, pillHeight);
  }
}

/// The equipped bird in the start block, drawn exactly like the in-game
/// bird at blend 0 (identity colours), scaled to the mock's 44 pt wide box
/// and centred in it.
class HomeBird extends PositionComponent {
  HomeBird({required Rect rect, required SkinSprites sprites})
    : super(
        position: rect.topLeft.toVector2(),
        size: rect.size.toVector2(),
      ) {
    final scale = rect.width / SkinDef.spriteWidth;
    _sprite = SkinSpriteComponent(
      sprites: sprites,
      initialTint: sprites.skin.mockColor,
      size: Vector2(SkinDef.spriteWidth, SkinDef.spriteHeight) * scale,
      position: size / 2,
      anchor: const Anchor(SkinDef.anchorX, SkinDef.anchorY),
    );
  }

  late final SkinSpriteComponent _sprite;

  SkinSprites get sprites => _sprite.sprites;
  set sprites(SkinSprites value) {
    _sprite
      ..sprites = value
      ..tint = value.skin.mockColor;
  }

  /// Exposed for tests.
  SkinSpriteComponent get skinSprite => _sprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_sprite);
  }
}

/// The gold BIG HOOPS / SHIELD slot under START (PRD-1 §3.6): video icon +
/// label (+ shield icon), 3 pt background-coloured outline. Armed: label +
/// check, not tappable. Ad unavailable (and no No-ads): dimmed.
class PowerupSlotButton extends MenuButton {
  PowerupSlotButton({
    required Rect rect,
    required this.video,
    required this.shield,
    required this.check,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: Config.menuGold,
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final Sprite video;
  final Sprite shield;
  final Sprite check;

  Color outlineColor = const Color(0xFFF1F1F1);
  final Paint _outline = Paint();

  Powerup _shown = Powerup.none;
  bool _armed = false;
  bool _showVideo = true;
  bool _unavailable = false;

  /// The powerup the slot currently shows (exposed for tests).
  Powerup get shown => _shown;
  bool get armed => _armed;
  bool get unavailable => _unavailable;

  /// Visible label ("BIG HOOPS", "SHIELD"); exposed for tests.
  String get labelText => _label?.text ?? '';

  MenuText? _label;
  final List<Component> _content = [];

  static String labelFor(Powerup p) =>
      p == Powerup.shield ? 'SHIELD' : 'BIG HOOPS';

  void setState({
    required Powerup offered,
    required Powerup armed,
    required bool noAds,
    required bool adAvailable,
  }) {
    final isArmed = armed != Powerup.none;
    final shown = isArmed ? armed : offered;
    final showVideo = !isArmed && !noAds;
    final unavailable = !isArmed && !noAds && !adAvailable;
    tappable = !isArmed;
    dimmed = unavailable;
    if (shown == _shown &&
        isArmed == _armed &&
        showVideo == _showVideo &&
        unavailable == _unavailable &&
        _label != null) {
      return;
    }
    _shown = shown;
    _armed = isArmed;
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
    final items = <PositionComponent>[
      if (_showVideo) MenuIcon(video, size: Vector2.all(18)),
      label,
      if (!_armed && _shown == Powerup.shield)
        MenuIcon(shield, size: Vector2(18, 20)),
      if (_armed)
        MenuIcon(check, size: Vector2.all(14), recolor: Config.menuPlum),
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

  /// No-ads tile after purchase: label "AD-FREE" + check.
  bool get owned => _owned;
  set owned(bool value) {
    _owned = value;
    if (isLoaded) _applyLabel();
  }

  MenuIcon? _check;

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
    label.text = _owned ? 'AD-FREE' : _labelText;
    _check?.removeFromParent();
    _check = null;
    final groupHeight = icon.height + iconGap + label.height;
    final top = (height - groupHeight) / 2;
    icon.position = Vector2((width - icon.width) / 2, top);
    final labelY = top + icon.height + iconGap;
    if (_owned && _checkSprite != null) {
      final check = MenuIcon(_checkSprite, size: Vector2.all(10));
      const gap = 3.0;
      final rowWidth = label.width + gap + check.width;
      label.position = Vector2((width - rowWidth) / 2, labelY);
      check.position = Vector2(
        label.x + label.width + gap,
        labelY + (label.height - check.height) / 2,
      );
      _check = check;
      add(check);
    } else {
      label.position = Vector2((width - label.width) / 2, labelY);
    }
  }

  void _applyTag() {
    _tag?.removeFromParent();
    _tag = null;
    final text = _tagText;
    if (text == null) return;
    // Mock: right -5, top -6 (sticks out of the tile's corner).
    final tag = _TileTag(text, tileWidth: width);
    _tag = tag;
    add(tag);
  }

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
    final tile = RectangleComponent(
      size: Vector2.all(tileSize),
      paint: Paint()..color = Config.menuPink,
      children: [
        MenuIcon(
          trophy,
          size: Vector2.all(Config.homeTrophySize),
          position: Vector2.all(tileSize / 2),
          anchor: Anchor.center,
        ),
      ],
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
