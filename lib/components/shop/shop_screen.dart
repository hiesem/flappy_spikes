import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../game/purchases.dart';
import '../../game/sound.dart';
import '../../menu/free_coins_policy.dart';
import '../../services/iap_service.dart';
import '../../skins/catalog.dart';
import '../../skins/art/look_painter.dart';
import '../../skins/art/trail.dart';
import '../../skins/item_store.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';
import '../skins/item_art.dart';
import '../ui/bird_idle.dart';
import '../ui/flip.dart';
import '../ui/live_effects.dart';

/// Coin packs in grid order with their flap tags (PRD-1 §5.2).
const List<(IapProduct, String?)> kShopPacks = [
  (IapProduct.coins500, null),
  (IapProduct.coins1800, 'MOST POPULAR'),
  (IapProduct.coins5000, null),
  (IapProduct.coins12000, 'BEST DEAL'),
];

/// Images the Shop content draws (besides the chrome).
const List<String> kShopImages = [
  'menu/noads.png',
  'menu/check.png',
  'menu/video_soft.png',
  'menu/coin_stack_1.png',
  'menu/coin_stack_2.png',
  'menu/coin_stack_3.png',
  'menu/coin_stack_4.png',
];

/// Logical sizes of the coin-stack art (WP3 manifest).
const List<(double, double)> _kStackSizes = [
  (28, 28),
  (28, 43),
  (20, 44),
  (20, 56),
];

/// The Shop's featured item (PRD-menu-v2 §4 / WP-C): the first item of the
/// 2.0 update ([kNewInUpdate], in its order) not owned yet, else the
/// cheapest item not owned (catalogue order breaks ties), or null when
/// everything is owned.
SkinItem? featuredItemFor(ItemStore items) {
  for (final key in kNewInUpdate) {
    final [layerKey, id] = key.split(':');
    final layer = SkinLayer.fromKey(layerKey);
    if (layer == null) continue;
    final item = itemById(layer, id);
    if (item != null && !items.isOwned(layer, id)) return item;
  }
  SkinItem? best;
  for (final item in allItems) {
    if (item.isNone || items.isOwned(item.layer, item.id)) continue;
    if (best == null || item.price < best.price) best = item;
  }
  return best;
}

/// The Shop (PRD-1 §5.2, approved design S1-B): Remove-ads banner, free
/// coins for a rewarded ad, the 2 x 2 coin packs and the featured skin, on
/// the shared [MenuScreen] chrome (PRD-home-v3 §9: RESTORE PURCHASES lives
/// in Settings only). Every action
/// routes to a game method; the screen polls the menu / store state each
/// frame (prices, pending purchases, cooldown, No-ads ownership).
class ShopScreen extends MenuScreen {
  ShopScreen({required super.onBack}) : super(title: 'SHOP');

  late final ShopBanner banner;
  late final FreeCoinsRow freeCoins;
  late final List<CoinPackCard> packs;
  late final FeaturedSkinRow featured;

  /// The Shop's idle clock (§8.3 live effects).
  late final LiveClock clock;

  @override
  List<String> get contentImages => kShopImages;

  @override
  Future<void> buildContent() async {
    final h = game.viewHeight;
    banner = ShopBanner(
      rect: Config.shopBannerRectFor(h),
      icon: sprite('menu/noads.png'),
      check: sprite('menu/check.png'),
      // PO change 2026-10-05: buys directly; the popup is launch-only.
      onPressed: () => game.buyNoAds('shop_banner'),
      isActive: isActive,
    );
    freeCoins = FreeCoinsRow(
      rect: Config.shopFreeCoinsRectFor(h),
      coin: sprite('menu/coin.png'),
      video: sprite('menu/video_soft.png'),
      onPressed: game.claimFreeCoins,
      isActive: isActive,
    );
    packs = [
      for (final (i, (product, tag)) in kShopPacks.indexed)
        CoinPackCard(
          rect: Config.shopPackRectFor(h, i),
          product: product,
          tag: tag,
          stack: sprite('menu/coin_stack_${i + 1}.png'),
          stackSize: Vector2(_kStackSizes[i].$1, _kStackSizes[i].$2),
          onPressed: () => game.buyProduct(product, sfx: Sfx.skTap),
          isActive: isActive,
          streakDelay: Config.shopStreakDelayPacks[i],
        ),
    ];
    featured = FeaturedSkinRow(
      rect: Config.shopFeaturedRectFor(h),
      coin: sprite('menu/coin.png'),
      onPressed: () {
        final item = featured.item;
        if (item != null) game.openFeaturedItem(item);
      },
      isActive: isActive,
      isPaused: () => game.liveMotionPaused,
    );
    scroll
      ..contentBottom = Config.shopContentBottomFor(h)
      ..content.addAll([banner, freeCoins, ...packs, featured]);

    // §8.3 / §8.4: GET pulse + nod, the price buttons' cascading streaks,
    // the pack tags' wiggle and the featured bird's calm idle — one clock,
    // paused under popups / ads, at rest under reduce motion.
    clock = LiveClock(
      paused: () => game.liveMotionPaused,
      still: () => game.reduceMotion,
    );
    clock
      ..bind(freeCoins.animate)
      ..bind(banner.animate)
      ..bind(featured.animate);
    for (final pack in packs) {
      clock.bind(pack.animate);
    }
    add(clock);
  }

  /// The card selling [product] (null for No ads).
  CoinPackCard? packFor(IapProduct product) {
    for (final card in packs) {
      if (card.product == product) return card;
    }
    return null;
  }

  /// Scrolls the coin packs into view (the pill's "+" while in the Shop).
  void scrollToCoins({bool animate = true}) => scroll.scrollTo(
    Config.shopCoinsAnchorFor(game.viewHeight),
    animate: animate,
  );

  @override
  void sync({bool force = false}) {
    final menu = game.menu;
    final iap = game.monetization.iap;
    final purchases = game.purchases;
    // PRD-home-v3 §7: after a fresh purchase the owned looks wait for the
    // celebration's flips (game.noAdsShown / noAdsVideoGone).
    banner.setState(
      owned: game.noAdsShown,
      price: iap.priceOf(IapProduct.noAds),
      pending: purchases.isPending(IapProduct.noAds),
    );
    freeCoins.setState(
      policy: menu.freeCoins,
      adAvailable: game.monetization.ads.isAvailable,
      busy: game.freeCoinsBusy,
      noAds: game.noAdsVideoGone,
    );
    for (final card in packs) {
      card.setState(
        price: iap.priceOf(card.product),
        pending: purchases.isPending(card.product),
      );
    }
    featured.item = featuredItemFor(menu.items);
    featured.tint = tint;
  }

  @override
  void onTint(Color color) {
    final card = cardColor;
    for (final pack in packs) {
      pack
        ..color = card
        ..amountColor = color;
    }
    featured
      ..color = card
      ..tint = color;
  }
}

/// Pink "REMOVE ADS" banner with the gold store-price chip; starts the
/// No-ads purchase directly (PO 2026-10-05). Owners see "✓ AD-FREE ·
/// THANK YOU" on a lighter pink ([Config.noAdsOwnedFill], PRD-home-v3 §7),
/// not tappable; a pending purchase dims and disables it. [flipToOwned]
/// turns it over (rotateX) to the owned face after the No-ads celebration.
class ShopBanner extends MenuButton {
  ShopBanner({
    required Rect rect,
    required this.icon,
    required this.check,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: Config.menuPink,
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final Sprite icon;
  final Sprite check;

  /// Light streak over the price chip (§8.3 cascade: first, delay 0).
  late final LightStreak streak = LightStreak(
    this,
    delay: Config.shopStreakDelayNoAds,
  );

  /// The price chip while shown (tests).
  RectangleComponent? priceChip;

  /// [LiveClock] binding.
  void animate(double t, bool still) =>
      still ? streak.progress = null : streak.at(t);

  static const double fontSize = 19;
  static const double letterSpacing = 0.04;
  static const double iconSize = 30;
  static const double checkSize = 26;
  static const double chipHeight = 36;
  static const double chipPadX = 12;

  bool? _owned;
  String? _price;
  bool _pending = false;

  MenuText? label;
  MenuText? priceLabel;

  /// The check in the icon slot (owners only); exposed for tests.
  MenuIcon? checkIcon;
  final List<Component> _content = [];

  /// The owned face is up (false while a [flipToOwned] still shows the
  /// old one).
  bool get owned => (_owned ?? false) && !_flipHold;

  /// True from [flipToOwned] until the flip shows the new face.
  bool _flipHold = false;
  FlipEffect? _flip;

  /// The flip while it runs (tests).
  FlipDriver? flipDriver;

  /// "THANK YOU" on the owned face (tests).
  MenuText? thanksLabel;

  /// PRD-home-v3 §7: flips over (0.18 s out + 0.28 s in, rotateX) to the
  /// owned face.
  void flipToOwned() {
    _flipHold = true;
    if (isLoaded) _rebuild();
    var effect = _flip;
    if (effect == null) {
      effect = _flip = FlipEffect(this, vertical: true);
      decorator.addLast(effect);
    }
    flipDriver?.removeFromParent();
    add(
      flipDriver = FlipDriver(
        effect,
        onSwap: () {
          _flipHold = false;
          if (isLoaded) _rebuild();
        },
        onDone: () => flipDriver = null,
      ),
    );
  }

  /// Visible label ("REMOVE ADS" / "AD-FREE"); exposed for tests.
  String get labelText => label?.text ?? '';

  /// The price shown on the chip (null when owned); exposed for tests.
  String? get price => owned ? null : _price;

  void setState({
    required bool owned,
    required String price,
    required bool pending,
  }) {
    tappable = !owned && !pending;
    dimmed = !owned && pending;
    if (owned == _owned && price == _price && pending == _pending) return;
    _owned = owned;
    _price = price;
    _pending = pending;
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
    priceLabel = null;
    priceChip = null;
    thanksLabel = null;
    color = owned ? Config.noAdsOwnedFill : Config.menuPink;
    // Owned: the check takes the crossed-AD icon's slot (same box, the
    // glyph centred in it) instead of trailing the label.
    final glyph = owned
        ? MenuIcon(
            check,
            size: Vector2.all(checkSize),
            position: Vector2.all(iconSize / 2),
            anchor: Anchor.center,
          )
        : null;
    checkIcon = glyph;
    final adIcon = glyph == null
        ? MenuIcon(icon, size: Vector2.all(iconSize))
        : (PositionComponent(size: Vector2.all(iconSize))..add(glyph));
    final text = MenuText(
      owned ? 'AD-FREE' : 'REMOVE ADS',
      fontSize: fontSize,
      color: Config.menuSoft,
      letterSpacingEm: letterSpacing,
    );
    label = text;
    final left = <PositionComponent>[adIcon, text];
    _content.addAll(left);
    // Mock: flex gap 6 + the label's 10 pt margin.
    layoutRow(this, left, gap: 16, left: 12);
    if (owned) {
      // Mock: soft 12 pt at 0.12 em, 85 %, 14 pt from the right edge.
      final thanks = MenuText(
        'THANK YOU',
        fontSize: 12,
        color: Config.menuSoft.withValues(alpha: .85),
        letterSpacingEm: 0.12,
      );
      thanksLabel = thanks;
      _content.add(thanks);
      layoutRow(this, [thanks], gap: 0, right: width - 14);
      return;
    }
    final price = MenuText(
      _price ?? '',
      fontSize: fontSize,
      color: Config.menuPlum,
      letterSpacingEm: letterSpacing,
    );
    priceLabel = price;
    final chip = RectangleComponent(
      size: Vector2(price.width + 2 * chipPadX, chipHeight),
      paint: Paint()..color = Config.menuGold,
    );
    layoutRow(chip, [price], gap: 0);
    streak.target = chip;
    chip.decorator.addLast(streak);
    priceChip = chip;
    _content.add(chip);
    layoutRow(this, [chip], gap: 0, right: width - 8);
  }
}

/// Gold "FREE +40" row with the pink GET chip (PRD-1 §3.2; PRD-menu-v2
/// §8.3: was WATCH — label only, the rewarded-ad flow is unchanged): a
/// rewarded ad for [FreeCoinsPolicy.reward] coins. No-ads owners get the
/// same reward without an ad, so their chip reads "CLAIM" with no video
/// icon and ad availability never dims it. While the policy blocks a claim
/// the chip shows the cooldown ("04:59") or "TOMORROW" (daily cap),
/// dimmed; with no ad loaded it is dimmed but still tappable (-> toast).
///
/// The chip is [Config.shopGetWidth] x [Config.shopGetHeight]: camera 20 pt
/// + "GET" 20 pt faux bold at 0.12 em. While claimable it pulses (1 ->
/// 1.05, pink glow) and the camera nods (§8.3), via [animate].
class FreeCoinsRow extends MenuButton {
  FreeCoinsRow({
    required Rect rect,
    required this.coin,
    required this.video,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: Config.menuGold,
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final Sprite coin;
  final Sprite video;

  /// The claim label with an ad (was "WATCH").
  static const String getLabel = 'GET';
  static const String claimLabel = 'CLAIM';

  static const double chipMinPad = 6;

  String? _chipText;
  bool _chipDimmed = false;

  /// Visible chip text ("GET", "CLAIM", "04:59", "TOMORROW"); exposed for
  /// tests.
  String get chipText => _chipText ?? '';
  bool get chipDimmed => _chipDimmed;

  _DimGroup? _chip;

  /// The chip (tests); its world rect is [chipRect].
  PositionComponent? get chip => _chip;

  /// The chip's rect in world coordinates (the coin-fly start), or null
  /// before it is built.
  Rect? get chipRect {
    final c = _chip;
    if (c == null || !c.isMounted) return null;
    final p = c.absolutePositionOfAnchor(Anchor.topLeft);
    return Rect.fromLTWH(p.x, p.y, c.width, c.height);
  }

  /// The GET text component while shown (tests).
  MenuText? chipLabel;

  /// The chip's video icon while shown (tests).
  MenuIcon? videoIcon;

  /// True while [shrinkVideo] runs: the chip keeps reading GET.
  bool _shrinking = false;

  /// PRD-home-v3 §7: after the No-ads celebration the video icon shrinks
  /// away (0.3 s), then the chip reads CLAIM. No-op without an icon.
  void shrinkVideo() {
    final icon = videoIcon;
    if (icon == null || _shrinking) return;
    _shrinking = true;
    add(ShrinkDriver(icon, onDone: () => _shrinking = false));
  }

  /// The chip's pulse (re-attached to every rebuilt chip).
  late final PulseEffect pulse = PulseEffect(
    this,
    amount: Config.shopGetPulse,
    glowColor: Config.shopGetGlow,
    glowBlur: Config.shopGetGlowBlur,
  );

  /// The camera icon's nod (re-attached to every rebuilt icon).
  late final WiggleEffect cameraNod = WiggleEffect(this);

  bool get _claimable =>
      _chipText == getLabel || _chipText == claimLabel || _chipText == null;

  /// [LiveClock] binding: pulse + nod while claimable and not dimmed.
  void animate(double t, bool still) {
    if (still || !_claimable || _chipDimmed) {
      pulse.rest();
      cameraNod.rest();
      return;
    }
    pulse.k = LiveCurves.pulse(t);
    cameraNod.angle = LiveCurves.cameraNod(t) * math.pi / 180;
  }

  /// "mm:ss" for a cooldown.
  static String formatCooldown(Duration d) {
    final s = (d.inMilliseconds / 1000).ceil();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void setState({
    required FreeCoinsPolicy policy,
    required bool adAvailable,
    required bool busy,
    bool noAds = false,
  }) {
    final String text;
    if (policy.remainingToday <= 0) {
      text = 'TOMORROW';
    } else if (policy.cooldownRemaining > Duration.zero) {
      text = formatCooldown(policy.cooldownRemaining);
    } else {
      text = noAds && !_shrinking ? claimLabel : getLabel;
    }
    final claimable = text == getLabel || text == claimLabel;
    tappable = claimable && !busy;
    final chipDimmed = !claimable || busy || (!noAds && !adAvailable);
    if (text == _chipText && chipDimmed == _chipDimmed && _chip != null) {
      return;
    }
    _chipText = text;
    _chipDimmed = chipDimmed;
    if (isLoaded) _rebuildChip();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    layoutRow(
      this,
      [
        MenuIcon(coin, size: Vector2.all(28)),
        MenuText(
          'FREE +${FreeCoinsPolicy.reward}',
          fontSize: 20,
          color: Config.menuPlum,
        ),
      ],
      gap: 10,
      left: 14,
    );
    _rebuildChip();
  }

  void _rebuildChip() {
    _chip?.removeFromParent();
    final text = _chipText ?? getLabel;
    final isGet = text == getLabel;
    final bold = isGet || text == claimLabel;
    final label = bold
        ? MenuText(
            text,
            fontSize: Config.shopGetFontSize,
            color: Config.menuSoft,
            letterSpacingEm: Config.shopGetLetterSpacing,
            strokeWidth: Config.shopGetStroke,
          )
        : MenuText(
            text,
            fontSize: 16,
            color: Config.menuSoft,
            letterSpacingEm: 0.04,
          );
    chipLabel = label;
    final icon = videoIcon = isGet
        ? MenuIcon(video, size: Vector2.all(Config.shopGetIconSize))
        : null;
    final items = <PositionComponent>[?icon, label];
    final gap = isGet ? Config.shopGetGap : 6.0;
    final contentWidth =
        items.fold<double>(0, (sum, c) => sum + c.width) +
        gap * (items.length - 1);
    final chip = _DimGroup(
      size: Vector2(
        // Fixed 112 pt (mock `.get`); only a longer state text (e.g.
        // "TOMORROW") may widen it.
        math.max(Config.shopGetWidth, contentWidth + 2 * chipMinPad),
        Config.shopGetHeight,
      ),
      color: Config.menuPink,
    )..opacity = _chipDimmed ? MenuButton.dimmedOpacity : 1;
    pulse.target = chip;
    chip.decorator.addLast(pulse);
    if (icon != null) {
      cameraNod.target = icon;
      icon.decorator.addLast(cameraNod);
    }
    layoutRow(chip, items, gap: gap);
    _chip = chip;
    layoutRow(this, [chip], gap: 0, right: width - 8);
  }
}

/// One coin pack: card fill, coin-stack art (bottom at card top + 78),
/// amount ("1,800"), full-width pink price button and an optional gold
/// flap tag centred on the top edge. The whole card buys the pack; it is
/// dimmed and inert while that purchase is pending.
///
/// Live (§8.3): a light streak over the price button every 6.4 s after
/// [streakDelay] (the cascade), the tag's wiggle every 6 s, and the coin
/// stack hops 4 pt when the card is pressed.
class CoinPackCard extends MenuButton {
  CoinPackCard({
    required Rect rect,
    required this.product,
    required this.tag,
    required this.stack,
    required this.stackSize,
    required super.onPressed,
    super.isActive,
    double streakDelay = 0,
  }) : streak = LightStreak(PositionComponent(), delay: streakDelay),
       super(
         color: const Color(0xFFE1E1E1),
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final IapProduct product;
  final String? tag;
  final Sprite stack;
  final Vector2 stackSize;

  /// The price button's light streak.
  final LightStreak streak;

  /// The tag's wiggle (no-op without a tag).
  late final WiggleEffect tagWiggle = WiggleEffect(this);

  late final MenuIcon stackArt;
  double _hopT = -1;

  /// The coin stack in world coordinates (PRD-home-v3 §5: the bought
  /// pack's coins burst out of it), or null before it is mounted.
  Rect? get stackRect {
    if (!isLoaded || !stackArt.isMounted) return null;
    final p = stackArt.absolutePositionOfAnchor(Anchor.topLeft);
    return Rect.fromLTWH(p.x, p.y, stackArt.width, stackArt.height);
  }

  /// Current coin-stack hop offset (pt, negative = up; tests).
  double get stackHop => LiveCurves.packHop(_hopT);

  /// [LiveClock] binding.
  void animate(double t, bool still) {
    if (still) {
      streak.progress = null;
      tagWiggle.rest();
      return;
    }
    streak.at(t);
    if (tag != null) tagWiggle.setPose(LiveCurves.packTagWiggle(t));
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    _hopT = 0; // §8.3: the coins hop when the pack is pressed
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_hopT < 0) return;
    _hopT += dt;
    if (_hopT >= LiveCurves.packHopDuration) _hopT = -1;
    if (isLoaded) {
      stackArt.position.y = Config.shopPackArtBottom + stackHop;
    }
  }

  late final MenuText amount;
  late final MenuText priceLabel;
  late final RectangleComponent priceButton;
  PositionComponent? tagComponent;

  String? _price;
  bool _pending = false;

  bool get pending => _pending;

  set amountColor(Color value) {
    if (isLoaded) amount.color = value;
    _amountColor = value;
  }

  Color _amountColor = const Color(0xFF828282);

  void setState({required String price, required bool pending}) {
    _pending = pending;
    tappable = !pending;
    dimmed = pending;
    if (price == _price) return;
    _price = price;
    if (isLoaded) _layoutPrice();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final art = stackArt = MenuIcon(
      stack,
      size: stackSize,
      position: Vector2(width / 2, Config.shopPackArtBottom),
      anchor: Anchor.bottomCenter,
    );
    amount = MenuText(
      formatAmount(product.coins),
      fontSize: 22,
      color: _amountColor,
      position: Vector2(width / 2, Config.shopPackAmountTop),
      anchor: Anchor.topCenter,
    );
    priceButton = RectangleComponent(
      position: Vector2(0, height - Config.shopPackPriceHeight),
      size: Vector2(width, Config.shopPackPriceHeight),
      paint: Paint()..color = Config.menuPink,
    );
    streak.target = priceButton;
    priceButton.decorator.addLast(streak);
    priceLabel = MenuText(
      _price ?? product.placeholderPrice,
      fontSize: 20,
      color: Config.menuSoft,
      letterSpacingEm: 0.04,
    );
    priceButton.add(priceLabel);
    addAll([art, amount, priceButton]);
    _layoutPrice();
    final text = tag;
    if (text != null) {
      final label = MenuText(
        text,
        fontSize: 13,
        color: Config.menuPlum,
        letterSpacingEm: 0.08,
      );
      final flap = RectangleComponent(
        size: Vector2(
          label.width + 2 * Config.shopPackTagPadX,
          Config.shopPackTagHeight,
        ),
        paint: Paint()..color = Config.menuGold,
        priority: 10,
      );
      flap.position = Vector2(
        (width - flap.width) / 2,
        -Config.shopPackTagHeight / 2,
      );
      layoutRow(flap, [label], gap: 0);
      label.position.y += 0.5; // browser rounds the flex centring down
      tagComponent = flap;
      tagWiggle.target = flap;
      flap.decorator.addLast(tagWiggle);
      add(flap);
    }
  }

  void _layoutPrice() {
    priceLabel
      ..text = _price ?? product.placeholderPrice
      ..position = Vector2(
        (priceButton.width - priceLabel.width) / 2,
        (priceButton.height - priceLabel.height) / 2,
      );
  }
}

/// Featured item row: the item's art (grid-tile art at 55 %), "FEATURED
/// SKIN" + name, and a pink coin price pill at the catalogue price. Tapping
/// opens the skin shop on the item's tab with it tried on. Hidden when
/// everything is owned.
///
/// Live (§8.3): the price pill's light streak closes the cascade (2.5 s)
/// and a featured bird idles calmly ([BirdIdle.calm]: bob, slow flap,
/// blink, an occasional lean, no hops).
class FeaturedSkinRow extends MenuButton {
  FeaturedSkinRow({
    required Rect rect,
    required this.coin,
    required super.onPressed,
    super.isActive,
    this.isPaused,
  }) : super(
         color: const Color(0xFFE1E1E1),
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final Sprite coin;

  /// Freezes the row's artwork clock while it returns true (§8.4: the
  /// featured art pauses with the Shop's idle clock under a popup / ad /
  /// debug panel).
  final bool Function()? isPaused;

  /// The price pill's light streak.
  late final LightStreak streak = LightStreak(
    this,
    delay: Config.shopStreakDelayFeatured,
  );

  /// The featured bird's calm idle (first lean / blink after 8 s, mock).
  final BirdIdle idle = BirdIdle(calm: true, firstAction: 8);

  bool _still = false;

  /// [LiveClock] binding; the bird steps here too so it pauses with the
  /// clock.
  double _lastT = 0;
  void animate(double t, bool still) {
    final dt = t - _lastT;
    _lastT = t;
    _still = still;
    if (still) {
      streak.progress = null;
    } else {
      streak.at(t);
    }
    if (dt > 0) idle.step(dt, still: still);
  }

  /// Scale of the 84 x 68 grid-tile art in the row.
  static const double artScale = 0.55;
  static const double padX = 10;
  static const double artSlot = 48;

  SkinItem? _item;
  bool _built = false;
  Color _tint = const Color(0xFF828282);
  final List<Component> _content = [];
  MenuText? _caption;
  MenuText? _name;
  MenuText? _price;
  TrailEmitter? _emitter;
  double _t = 0;

  /// The featured item (null = row hidden).
  SkinItem? get item => _item;
  set item(SkinItem? value) {
    if (_built && value?.key == _item?.key) return;
    _item = value;
    _emitter = value != null && value.layer == SkinLayer.trail
        ? TrailEmitter(value.id, lookPainter: paintLookForTrail)
        : null;
    if (isLoaded) _rebuild();
  }

  /// The price pill while shown (tests).
  RectangleComponent? pricePill;

  /// The visible name / price (tests).
  String? get nameText => _name?.text;
  String? get priceText => _price?.text;

  set tint(Color value) {
    if (value == _tint) return;
    _tint = value;
    _caption?.color = value;
    _name?.color = value;
  }

  @override
  void renderTree(Canvas canvas) {
    if (_item == null) return;
    super.renderTree(canvas);
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      _item != null && super.containsLocalPoint(point);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _rebuild();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isPaused?.call() ?? false) return; // frozen with the idle clock
    _t += dt;
    final emitter = _emitter;
    if (emitter != null) ItemArt.advanceTrail(emitter, _t, dt);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final item = _item;
    if (item == null) return;
    canvas.save();
    canvas.translate(padX + artSlot / 2, height / 2);
    if (item.layer == SkinLayer.bird && !item.isNone) {
      // Same size as the tile art (ItemArt's bird branch), idling.
      final o = idle.offset;
      canvas.translate(o.dx, o.dy);
      canvas.rotate(idle.angle);
      canvas.scale(idle.scaleX, idle.scaleY);
      canvas.scale(artScale * math.min(ItemArt.w / 56, ItemArt.h / 44));
      LookPainter.paint(
        canvas,
        Look(bird: item.id),
        t: _t,
        flap: idle.flap,
        blink: idle.blinking && !_still,
      );
    } else {
      canvas.scale(artScale);
      canvas.translate(-ItemArt.w / 2, -ItemArt.h / 2);
      ItemArt.paint(canvas, item, t: _t, emitter: _emitter);
    }
    canvas.restore();
  }

  void _rebuild() {
    _built = true;
    removeAll(_content);
    _content.clear();
    _caption = null;
    _name = null;
    _price = null;
    final item = _item;
    if (item == null) return;
    // Two-line text block (mock line-height 1.1; tuned against
    // shop_s1b.png): caption 11 pt, name 19 pt.
    final caption = MenuText(
      'FEATURED SKIN',
      fontSize: 11,
      color: _tint,
      letterSpacingEm: 0.1,
      position: Vector2(padX + artSlot + 10, 12),
    );
    final name = MenuText(
      item.name.toUpperCase(),
      fontSize: 19,
      color: _tint,
      position: Vector2(padX + artSlot + 10, 24),
    );
    _caption = caption;
    _name = name;
    final priceText = MenuText(
      formatCoins(item.price),
      fontSize: 16,
      color: Config.menuSoft,
    );
    _price = priceText;
    final pill = RectangleComponent(
      size: Vector2(14 + 4 + priceText.width + 20, priceText.height + 12),
      paint: Paint()..color = Config.menuPink,
    );
    // Mock `.price .coin` (14 pt) wins over `.cn` (18 pt).
    layoutRow(pill, [MenuIcon(coin, size: Vector2.all(14)), priceText], gap: 4);
    streak.target = pill;
    pill.decorator.addLast(streak);
    pricePill = pill;
    _content.addAll([caption, name]);
    addAll([caption, name]);
    _content.add(pill);
    layoutRow(this, [pill], gap: 0, right: width - padX);
  }
}

/// A flat filled box whose subtree fades as one layer (the dimmed GET
/// chip).
class _DimGroup extends PositionComponent with GroupOpacity {
  _DimGroup({required super.size, required Color color})
    : _paint = Paint()..color = color;

  final Paint _paint;

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}
