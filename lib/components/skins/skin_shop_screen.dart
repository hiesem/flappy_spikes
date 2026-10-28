import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../../run/effects/coin_icon.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import '../home/menu_primitives.dart';
import '../levels/emblem_view.dart';
import '../menu_screen_chrome.dart';
import 'celebration.dart';
import 'item_art.dart';
import 'item_tile.dart';
import 'preview_stage.dart';
import 'shop_glyphs.dart' show ShopText;
import 'shop_widgets.dart';
import 'skin_tab_bar.dart';

/// The 2.0 skin shop (PRD-menu-v2 §3–4, approved layout A "Big preview +
/// tabs") on the shared [MenuScreen] chrome (coin pill + back button, no
/// title): the collection bar, the live [PreviewStage] with the name row
/// and the action button, the six-tab [SkinTabBar] and a scrolling
/// 3-column grid of [ItemTile]s for the open tab.
///
/// The screen owns the view state — open [tab], the one tried-on item
/// ([tryOnId], always on the open tab) and the NEW tags snapshotted at
/// open — and the visual feedback ([hop], [celebrate], [showNoCoins]).
/// Every tap routes to a game method (`selectSkinTab`, `tapItem`,
/// `buyTriedOnItem`), which owns the flows, sounds and analytics.
class SkinShopScreen extends MenuScreen {
  SkinShopScreen({
    required super.onBack,
    SkinLayer initialTab = SkinLayer.bird,
    this.initialTryOn,
    super.lock,
  }) : _tab = initialTab,
       super(title: '');

  SkinLayer _tab;
  // region P26-F9e
  // The CARDS filter adds a fixed row, so its scroll viewport is replaced
  // when crossing between CARDS and wardrobe tabs.
  late MenuScrollArea _shopScroll;
  @override
  MenuScrollArea get scroll => _shopScroll;
  @override
  set scroll(MenuScrollArea value) => _shopScroll = value;
  CardKind cardKind = CardKind.frame;
  ShopCardArt? _cardArt;
  ShopCardArt get cardArt => _cardArt!;
  final List<MenuText> _kindLabels = [];
  final List<MenuButton> _kindButtons = [];
  PositionComponent? _skillHeader;
  bool get onCards => _tab == SkinLayer.card;
  String cardCounter(CardKind kind) =>
      '${cardItemsFor(kind).where((i) => game.menu.items.isOwned(SkinLayer.card, i.id)).length}/20';
  SkinItem cardNone(CardKind kind) => SkinItem(
    layer: SkinLayer.card,
    id: '',
    name: 'None',
    rarity: null,
    price: 0,
    cardKind: kind,
  );
  void selectCardKind(CardKind kind) {
    if (!onCards || kind == cardKind) return;
    cardKind = kind;
    clearTryOn();
    play(Sfx.skTab);
    _fillGrid(animate: true);
  }
  // endregion

  /// Locked item of the initial tab to open tried on (Shop featured row).
  final String? initialTryOn;
  String? _tryOnId;
  late final Set<String> _newKeys;
  final ItemArtCache art = ItemArtCache();
  final List<(double, void Function())> _timers = [];

  late final CollectionBar bar;
  late final PreviewStage stage;
  late final SkinNameRow nameRow;
  late final ShopActionButton actionButton;
  late final SkinTabBar tabBar;
  List<ItemTile> tiles = [];

  /// The open tab.
  SkinLayer get tab => _tab;

  /// The tried-on (locked) item id on [tab], or null.
  String? get tryOnId => _tryOnId;

  /// The tried-on item, or null.
  SkinItem? get tryOnItem =>
      _tryOnId == null ? null : itemById(_tab, _tryOnId!);

  /// The equipped look with the try-on applied (what the preview shows).
  Look get previewLook {
    final look = game.menu.items.look;
    final id = _tryOnId;
    // region P26-F9e
    if (onCards) return id == null ? look : look.withCardItem(cardKind, id);
    // endregion
    return id == null ? look : look.withItem(_tab, id);
  }

  /// The item the name row / action button describe: the try-on, else the
  /// equipped item of the open tab.
  // region P26-F9e
  SkinItem get activeItem =>
      tryOnItem ??
      (onCards
          ? cardItemById(game.menu.items.look.cardIdFor(cardKind))!
          : itemById(_tab, game.menu.items.look.idFor(_tab))!);
  // endregion

  /// Whether [item] shows its NEW tag (snapshot at open, cleared on tap).
  bool isNewTag(SkinItem item) => _newKeys.contains(item.key);

  bool get reduceMotion => game.reduceMotion;

  @override
  bool get showsTitle => false;

  @override
  Rect scrollViewportFor(double viewHeight) =>
      // region P26-F9e
      Config.skinShopGridRectFor(viewHeight, cards: onCards);
  // endregion

  /// The grid tile of [id] on the open tab.
  ItemTile tileFor(String id) => tiles.firstWhere((t) => t.item.id == id);

  Color get stageColor =>
      Color.lerp(game.stageBackground, tint, Config.skinShopStageMix)!;
  Color get tileColor =>
      Color.lerp(game.stageBackground, tint, Config.skinShopTileMix)!;

  /// Plays [sfx] unless the screen is leaving.
  void play(Sfx sfx) {
    if (active) game.sound.play(sfx);
  }

  @override
  Future<void> buildContent() async {
    final items = game.menu.items;
    if (onCards && initialTryOn != null) {
      cardKind = cardItemById(initialTryOn!)?.cardKind ?? CardKind.frame;
    }
    _newKeys = {
      for (final item in allItems)
        if (items.isNew(item.layer, item.id)) item.key,
    };
    bar = CollectionBar(
      rect: Config.skinShopBarRect,
      owned: () => items.ownedCount,
      total: kCollectibleTotal,
      popEnabled: () => !reduceMotion,
    );
    // region P26-F9e
    _cardArt = ShopCardArt(
      coin: game.images.fromCache(CoinIcon.asset),
      look: items.look,
      name: game.storage.versusCustomName.isNotEmpty
          ? game.storage.versusCustomName
          : game.storage.versusNickname ?? 'Birdie',
      paintRays: PreviewStage.paintRays,
    );
    stage = _CardPreviewStage(
      screen: this,
      // endregion
      rect: Config.skinShopStageRect,
      look: () => previewLook,
      triedLayer: () => _tryOnId == null ? null : _tab,
      tab: () => _tab,
      background: () => stageColor,
      play: play,
      reduceMotion: () => reduceMotion,
    )..primeSounds(items.look);
    const stageRect = Config.skinShopStageRect;
    nameRow = SkinNameRow(
      position: Vector2(
        stageRect.left + Config.skinShopNameLeft,
        stageRect.top + Config.skinShopNameTop,
      ),
      item: () => activeItem,
      tint: () => tint,
    );
    actionButton = ShopActionButton(
      bottomRight: Vector2(
        stageRect.right - Config.skinShopActionInset,
        stageRect.bottom - Config.skinShopActionInset,
      ),
      kind: () {
        // region P26-F9e
        if (tryOnItem?.isSkillOnly ?? false) return ShopActionKind.skillOnly;
        if (onCards && activeItem.id.isEmpty) return ShopActionKind.nothingOn;
        // endregion
        if (_tryOnId != null) return ShopActionKind.buy;
        return activeItem.isNone
            ? ShopActionKind.nothingOn
            : ShopActionKind.equipped;
      },
      price: () => tryOnItem?.price ?? 0,
      affordable: () => game.menu.wallet.balance >= (tryOnItem?.price ?? 0),
      tint: () => tint,
      reduceMotion: () => reduceMotion,
      onPressed: () {
        if (!(tryOnItem?.isSkillOnly ?? false)) game.buyTriedOnItem();
      },
      isActive: isActive,
    );
    tabBar = SkinTabBar(
      rect: Config.skinShopTabBarRect,
      active: () => _tab,
      counter: (layer) =>
          '${items.ownedCountFor(layer)}/${items.totalFor(layer)}',
      tint: () => tint,
      onSelect: game.selectSkinTab,
      isActive: isActive,
    );
    addAll([bar, stage, nameRow, actionButton, tabBar]);
    // region P26-F9e
    for (final kind in CardKind.values) {
      final label = MenuText(
        '',
        fontSize: 9,
        color: Config.menuPink,
        position: Vector2(
          Config.skinShopTile / 2,
          Config.skinShopCardRowHeight / 2,
        ),
        anchor: Anchor.center,
      );
      final button = MenuButton(
        position: Config.skinShopCardKindRectFor(
          kind.index,
        ).topLeft.toVector2(),
        size: Config.skinShopCardKindRectFor(kind.index).size.toVector2(),
        isActive: () => isActive() && onCards,
        onPressed: () => selectCardKind(kind),
      );
      button.add(label);
      _kindLabels.add(label);
      _kindButtons.add(button);
      add(button);
    }
    add(_GridScrollDecoration(this));
    // endregion
    _fillGrid(animate: false);
    final initial = initialTryOn;
    if (initial != null && !items.isOwned(_tab, initial)) {
      _tryOnId = initial;
      scrollToItem(initial);
      // The Shop featured row opens the shop already trying that item on:
      // that counts as tapping it, so its NEW tag clears and the item is
      // persisted as seen (§3.3 / WP-C), exactly like a grid tap.
      final item = itemById(_tab, initial);
      if (item != null && isNewTag(item)) {
        clearNew(item);
        unawaited(items.markSeen(_tab, initial));
      }
    }
  }

  void _fillGrid({required bool animate}) {
    final h = game.viewHeight;
    for (final tile in tiles) {
      tile.removeFromParent();
    }
    // region P26-F9e
    _skillHeader?.removeFromParent();
    final list = onCards
        ? [cardNone(cardKind), ...cardItemsFor(cardKind)]
        : itemsFor(_tab);
    if (onCards) {
      final currentLook = game.menu.items.look;
      if (cardArt.look.bird != currentLook.bird ||
          cardArt.look.gear != currentLook.gear ||
          cardArt.look.hat != currentLook.hat) {
        final old = cardArt;
        _cardArt = ShopCardArt(
          coin: old.coin,
          look: currentLook,
          name: old.name,
          paintRays: old.paintRays,
        );
        old.dispose();
      }
      for (final item in [
        for (final kind in CardKind.values) cardNone(kind),
        ...list.where((i) => i.id.isNotEmpty),
        for (final kind in CardKind.values)
          if (game.menu.items.look.cardIdFor(kind).isNotEmpty)
            cardItemById(game.menu.items.look.cardIdFor(kind))!,
      ]) {
        cardArt.prepare(item);
      }
    }
    tiles = [
      for (final (i, item) in list.indexed)
        _tile(
          item,
          Config.skinShopTileRectFor(h, i, cards: onCards),
          i,
          animate,
        ),
    ];
    if (onCards) {
      _skillHeader = MenuText(
        'EARNED BY SKILL · NOT SOLD',
        fontSize: 10,
        color: Config.menuPlum,
        position: Vector2(
          Config.skinShopGridLeft,
          tiles[Config.skinShopCardSoldTiles].toRect().top -
              Config.skinShopCardSkillHeaderInset,
        ),
      );
      scroll.content.add(_skillHeader!);
    }
    scroll
      ..contentBottom =
          tiles.last.toRect().bottom + Config.skinShopGridPadBottom
      ..offset = 0
      ..content.addAll(tiles);
    // endregion
  }

  ItemTile _tile(SkinItem item, Rect rect, int index, bool animate) {
    late final ItemTile tile;
    tile = ItemTile(
      item: item,
      rect: rect,
      art: art,
      cardArt: item.layer == SkinLayer.card ? cardArt : null,
      state: () {
        final items = game.menu.items;
        final tried = _tryOnId == item.id;
        return ItemTileState(
          owned: items.isOwned(item.layer, item.id),
          equipped:
              _tryOnId == null &&
              (onCards && item.id.isEmpty
                  ? items.look.cardIdFor(cardKind).isEmpty
                  : items.isEquipped(item.layer, item.id)),
          tryingOn: tried,
          isNew: _newKeys.contains(item.key),
          affordable: game.menu.wallet.balance >= item.price,
        );
      },
      // region P26-F9e
      onPressed: () {
        if (onCards && item.id.isEmpty) {
          unawaited(game.clearShopCard(cardKind));
        } else if (item.isSkillOnly &&
            !game.menu.items.isOwned(item.layer, item.id)) {
          setTryOn(item.id);
          play(Sfx.skTap);
        } else {
          game.tapItem(item.layer, item.id, fromTile: true);
        }
      },
      // endregion
      cardColor: () => tileColor,
      tint: () => tint,
      reduceMotion: () => reduceMotion,
      isActive: isActive,
      isOnScreen: () => _onScreen(tile),
      enterDelay: animate
          ? (index % Config.skinShopColumns) * Config.skinShopEnterColumnDelay +
                (index ~/ Config.skinShopColumns) * Config.skinShopEnterRowDelay
          : null,
    );
    return tile;
  }

  bool _onScreen(ItemTile tile) {
    final viewport = scroll.viewport;
    final top = scroll.screenY(tile.y - tile.height / 2);
    final bottom = scroll.screenY(tile.y + tile.height / 2);
    // The NEW tag overhangs the top by 6 pt.
    return bottom > viewport.top && top - 8 < viewport.bottom;
  }

  /// Scrolls the tile of [id] into view (no-op when it is visible).
  void scrollToItem(String id, {bool animate = false}) {
    final rect = tileFor(id).toRect();
    final viewport = scroll.viewport;
    if (scroll.screenY(rect.top) >= viewport.top &&
        scroll.screenY(rect.bottom) <= viewport.bottom) {
      return;
    }
    scroll.scrollTo(rect.top - Config.skinShopGridPadTop, animate: animate);
  }

  // --- view-state changes (called by the game's flows) -----------------------

  /// Opens [layer]'s tab: clears the try-on, refills the grid with the
  /// staggered fade / rise entrance, scrolls to the top.
  void selectTab(SkinLayer layer) {
    if (layer == _tab) return;
    _tryOnId = null;
    // region P26-F9e
    final changeViewport = onCards != (layer == SkinLayer.card);
    _tab = layer;
    if (changeViewport) {
      scroll.removeFromParent();
      for (final gate in children.query<MenuScrollTapGate>()) {
        gate.removeFromParent();
      }
      scroll = MenuScrollArea(
        viewport: scrollViewportFor(game.viewHeight),
        bleedBottom: Config.menuSpikeToothDepth,
        isActive: isActive,
      );
      add(scroll);
      add(
        MenuScrollTapGate(
          scroll: scroll,
          position: scroll.visibleRect.topLeft.toVector2(),
          size: scroll.visibleRect.size.toVector2(),
          priority: 1 << 20,
        ),
      );
    }
    // endregion
    _fillGrid(animate: true);
  }

  /// Puts the locked item [id] of the open tab on the preview bird.
  void setTryOn(String id) => _tryOnId = id;

  void clearTryOn() => _tryOnId = null;

  /// Drops [item]'s NEW tag for this visit.
  void clearNew(SkinItem item) => _newKeys.remove(item.key);

  /// The preview bird hops (equip, try-on).
  void hop([double strength = 1]) => stage.hop(strength);

  /// Purchase feedback (§3.6) for [item]: celebration by rarity on the
  /// stage, the UNLOCKED! banner, legendary flash + shake (not under
  /// reduce motion), `sk_progress` when the collection bar ticks up.
  void celebrate(SkinItem item) {
    final rarity = item.rarity ?? Rarity.common;
    play(switch (rarity) {
      Rarity.common => Sfx.skBuyCommon,
      Rarity.rare => Sfx.skBuyRare,
      Rarity.epic => Sfx.skBuyEpic,
      Rarity.legendary => Sfx.skBuyLegendary,
    });
    final legendary = rarity == Rarity.legendary;
    after(
      legendary
          ? Config.skinShopProgressSoundDelayLegendary
          : Config.skinShopProgressSoundDelay,
      () => play(Sfx.skProgress),
    );
    stage.celebrate(rarity);
    add(
      UnlockBanner(
        item: item,
        centerX: Config.worldWidth / 2,
        top: Config.skinShopBannerTop,
        reduceMotion: reduceMotion,
      ),
    );
    if (legendary && !reduceMotion) {
      game.world.add(
        ScreenFlash(
          size: Vector2(game.viewWidth + game.extraWidth, game.viewHeight),
        )..position.x = -game.extraWidth, // WP-TAB: full width
      );
      game.world.add(ScreenShake(game.camera.viewfinder));
    }
  }

  /// BUY without enough coins: the dark toast (the game plays the sound
  /// and nudges the coin pill).
  void showNoCoins() {
    for (final toast in children.query<ShopToast>()) {
      toast.removeFromParent();
    }
    add(
      ShopToast(
        'NOT ENOUGH COINS',
        centerX: Config.worldWidth / 2,
        top: Config.skinShopToastTop,
      ),
    );
  }

  /// Runs [action] after [seconds] of game time (while the screen lives).
  void after(double seconds, void Function() action) =>
      _timers.add((seconds, action));

  @override
  void update(double dt) {
    super.update(dt);
    // region P26-F9e
    for (final kind
        in _kindLabels.length == 3 ? CardKind.values : <CardKind>[]) {
      final label = _kindLabels[kind.index];
      label.text = onCards
          ? '${switch (kind) {
              CardKind.frame => 'FRAMES',
              CardKind.name => 'NAMES',
              CardKind.sticker => 'STICKERS',
            }} ${cardCounter(kind)}'
          : '';
      _kindButtons[kind.index].color = !onCards
          ? null
          : cardKind == kind
          ? Config.menuPink
          : const Color(0xFFE2E2E2);
      label.color = cardKind == kind ? const Color(0xFFFFFFFF) : tint;
    }
    // endregion
    if (_timers.isEmpty) return;
    final due = <void Function()>[];
    for (var i = _timers.length - 1; i >= 0; i--) {
      final (left, action) = _timers[i];
      if (left - dt <= 0) {
        due.add(action);
        _timers.removeAt(i);
      } else {
        _timers[i] = (left - dt, action);
      }
    }
    for (final action in due.reversed) {
      action();
    }
  }

  @override
  void onRemove() {
    art.dispose();
    _cardArt?.dispose();
    super.onRemove();
  }
}

// region P26-F9e
/// Retains PreviewStage's update / celebration driver for all six tabs.
class _CardPreviewStage extends PreviewStage {
  _CardPreviewStage({
    required this.screen,
    required super.rect,
    required super.look,
    required super.triedLayer,
    required super.tab,
    required super.background,
    required super.play,
    required super.reduceMotion,
  });
  final SkinShopScreen screen;
  String? _cachedCard;
  @override
  Offset get celebrationCentre => screen.onCards
      ? Config.skinShopCardPreviewRect.center
      : super.celebrationCentre;
  late final EmblemView _emblem = EmblemView(
    // region P26-J2
    progression: true,
    // endregion
    level: screen.game.menu.levels.level,
    artScale: .36,
    position: Vector2(222, 65),
  );
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(_emblem);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final card = screen.onCards ? screen.previewLook.card : null;
    if (card == null || reduceMotion() || card != _cachedCard) {
      screen.cardArt.releaseAnimation(this);
    }
    _cachedCard = card;
    _emblem.popScale = screen.onCards ? 1 : 0;
    _emblem.t = reduceMotion() ? 0 : t;
  }

  @override
  void render(Canvas canvas) {
    if (!screen.onCards) {
      super.render(canvas);
      return;
    }
    canvas.drawRect(size.toRect(), Paint()..color = background());
    canvas.drawRect(
      Config.skinShopCardPreviewRect,
      Paint()..color = const Color(0xFFF4F4F4),
    );
    paintCelebration(canvas, confetti: false);
    final look = screen.previewLook;
    canvas.save();
    canvas.translate(width / 2, height / 2 + 2);
    for (final kind in CardKind.values) {
      final item = cardItemById(look.cardIdFor(kind))!;
      final shown = item.id.isEmpty ? screen.cardNone(kind) : item;
      canvas.save();
      switch (kind) {
        case CardKind.frame:
          canvas.translate(-90, 0);
          canvas.scale(1.25);
        case CardKind.name:
          canvas.translate(-12, 0);
          canvas.scale(1.2);
        case CardKind.sticker:
          canvas.translate(106, 14);
          canvas.rotate(.1);
          canvas.scale(.75);
      }
      if (kind != CardKind.sticker || item.id.isNotEmpty) {
        screen.cardArt.paint(
          canvas,
          shown,
          reduceMotion() ? 0 : t,
          owner: this,
        );
      }
      canvas.restore();
    }
    canvas.restore();
    if (screen.cardKind == CardKind.name) {
      _nameStyle.paint(canvas, const Offset(116, 38));
    }
    paintCelebration(canvas, rays: false);
  }

  @override
  void onRemove() {
    screen.cardArt.releaseAnimation(this);
    super.onRemove();
  }

  final ShopText _nameStyle = ShopText(
    'NAME STYLE',
    fontSize: 8,
    color: Config.menuPlum,
  );
}

/// Grid-only adornments. This component is fixed, above the clipped list.
class _GridScrollDecoration extends PositionComponent {
  _GridScrollDecoration(this.screen) : super(priority: 10);
  final SkinShopScreen screen;
  @override
  void render(Canvas canvas) {
    final scroll = screen.scroll;
    final r = scroll.viewport;
    if (scroll.offset > .1) {
      canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, Config.skinShopScrollShadow),
        Paint()
          ..shader = Gradient.linear(
            Offset(0, r.top),
            Offset(0, r.top + Config.skinShopScrollShadow),
            [const Color(0x22000000), const Color(0x00000000)],
          ),
      );
    }
    if (!scroll.scrollable) return;
    final h = (r.height * r.height / (r.height + scroll.maxOffset)).clamp(
      Config.skinShopScrollIndicatorMin,
      r.height,
    );
    final y =
        r.top +
        (r.height - h) * (scroll.offset / scroll.maxOffset).clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          r.right - Config.skinShopScrollIndicator,
          y,
          Config.skinShopScrollIndicator,
          h,
        ),
        const Radius.circular(1),
      ),
      Paint()..color = const Color(0x66828282),
    );
  }
}
// endregion

// region P26-F9e
/// Game action shared by every CARDS None tile. Keep persistence, sound and
/// equip analytics together, like the game's other explicit equip actions.
extension CardShopActions on FlappySpikesGame {
  Future<void> clearShopCard(CardKind kind) async {
    skinShop?.clearTryOn();
    sound.play(Sfx.skEquip);
    services.logItemEquip(SkinLayer.card, '');
    await menu.items.clearCard(kind);
  }
}
// endregion
