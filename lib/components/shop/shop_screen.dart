import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../game/purchases.dart';
import '../../menu/free_coins_policy.dart';
import '../../services/iap_service.dart';
import '../../skins/catalog.dart';
import '../../skins/art/trail.dart';
import '../../skins/item_store.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../menu_screen_chrome.dart';
import '../skins/item_art.dart';

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
/// coins for a rewarded ad, the 2 x 2 coin packs, the featured skin and a
/// restore-purchases link, on the shared [MenuScreen] chrome. Every action
/// routes to a game method; the screen polls the menu / store state each
/// frame (prices, pending purchases, cooldown, No-ads ownership).
class ShopScreen extends MenuScreen {
  ShopScreen({required super.onBack}) : super(title: 'SHOP');

  late final ShopBanner banner;
  late final FreeCoinsRow freeCoins;
  late final List<CoinPackCard> packs;
  late final FeaturedSkinRow featured;
  late final MenuButton restoreLink;

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
          onPressed: () => game.buyProduct(product),
          isActive: isActive,
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
    );
    const linkSize = Size(200, 24);
    final linkTop = Config.shopRestorePositionFor(h);
    restoreLink = MenuButton(
      position: Vector2(
        linkTop.x - linkSize.width / 2,
        linkTop.y - (linkSize.height - 11 * kNormalLineHeight) / 2,
      ),
      size: linkSize.toVector2(),
      onPressed: game.restorePurchases,
      isActive: isActive,
      children: [
        MenuText(
          'RESTORE PURCHASES',
          fontSize: 11,
          color: Config.menuPink,
          letterSpacingEm: 0.1,
          position: linkSize.toVector2() / 2,
          anchor: Anchor.center,
        ),
      ],
    );
    scroll
      ..contentBottom = Config.shopContentBottomFor(h)
      ..content.addAll([banner, freeCoins, ...packs, featured, restoreLink]);
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
    banner.setState(
      owned: menu.noAds,
      price: iap.priceOf(IapProduct.noAds),
      pending: purchases.isPending(IapProduct.noAds),
    );
    freeCoins.setState(
      policy: menu.freeCoins,
      adAvailable: game.monetization.ads.isAvailable,
      busy: game.freeCoinsBusy,
      noAds: menu.noAds,
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
/// No-ads purchase directly (PO 2026-10-05). Owners see the check in the
/// icon slot and "AD-FREE", dimmed and not tappable; a pending purchase
/// disables it too.
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

  bool get owned => _owned ?? false;

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
    dimmed = owned || pending;
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
    if (owned) return;
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
    _content.add(chip);
    layoutRow(this, [chip], gap: 0, right: width - 8);
  }
}

/// Gold "FREE +40" row with the pink WATCH chip (PRD-1 §3.2): a rewarded ad
/// for [FreeCoinsPolicy.reward] coins. No-ads owners get the same reward
/// without an ad, so their chip reads "CLAIM" with no video icon and ad
/// availability never dims it. While the policy blocks a claim the
/// chip shows the cooldown ("04:59") or "TOMORROW" (daily cap), dimmed;
/// with no ad loaded it is dimmed but still tappable (-> toast).
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

  static const double chipHeight = 28;
  static const double chipPadX = 12;

  String? _chipText;
  bool _chipDimmed = false;

  /// Visible chip text ("WATCH", "04:59", "TOMORROW"); exposed for tests.
  String get chipText => _chipText ?? '';
  bool get chipDimmed => _chipDimmed;

  _DimGroup? _chip;

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
      text = noAds ? 'CLAIM' : 'WATCH';
    }
    final claimable = text == 'WATCH' || text == 'CLAIM';
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
    final label = MenuText(
      _chipText ?? 'WATCH',
      fontSize: 16,
      color: Config.menuSoft,
      letterSpacingEm: 0.04,
    );
    final items = <PositionComponent>[
      if (_chipText == null || _chipText == 'WATCH')
        MenuIcon(video, size: Vector2.all(20)),
      label,
    ];
    final contentWidth =
        items.fold<double>(0, (sum, c) => sum + c.width) +
        6 * (items.length - 1);
    final chip = _DimGroup(
      size: Vector2(contentWidth + 2 * chipPadX, chipHeight),
      color: Config.menuPink,
    )..opacity = _chipDimmed ? MenuButton.dimmedOpacity : 1;
    layoutRow(chip, items, gap: 6);
    _chip = chip;
    layoutRow(this, [chip], gap: 0, right: width - 8);
  }
}

/// One coin pack: card fill, coin-stack art (bottom at card top + 78),
/// amount ("1,800"), full-width pink price button and an optional gold
/// flap tag centred on the top edge. The whole card buys the pack; it is
/// dimmed and inert while that purchase is pending.
class CoinPackCard extends MenuButton {
  CoinPackCard({
    required Rect rect,
    required this.product,
    required this.tag,
    required this.stack,
    required this.stackSize,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: const Color(0xFFE1E1E1),
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final IapProduct product;
  final String? tag;
  final Sprite stack;
  final Vector2 stackSize;

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
    final art = MenuIcon(
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
class FeaturedSkinRow extends MenuButton {
  FeaturedSkinRow({
    required Rect rect,
    required this.coin,
    required super.onPressed,
    super.isActive,
  }) : super(
         color: const Color(0xFFE1E1E1),
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
       );

  final Sprite coin;

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
    canvas.scale(artScale);
    canvas.translate(-ItemArt.w / 2, -ItemArt.h / 2);
    ItemArt.paint(canvas, item, t: _t, emitter: _emitter);
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
    _content.addAll([caption, name]);
    addAll([caption, name]);
    _content.add(pill);
    layoutRow(this, [pill], gap: 0, right: width - padX);
  }
}

/// A flat filled box whose subtree fades as one layer (the dimmed WATCH
/// chip).
class _DimGroup extends PositionComponent with GroupOpacity {
  _DimGroup({required super.size, required Color color})
    : _paint = Paint()..color = color;

  final Paint _paint;

  @override
  void render(Canvas canvas) => canvas.drawRect(size.toRect(), _paint);
}
