import 'package:flame/extensions.dart';

import '../../game/config.dart';
import '../../game/sound.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import '../menu_screen_chrome.dart';
import 'celebration.dart';
import 'item_art.dart';
import 'item_tile.dart';
import 'preview_stage.dart';
import 'shop_widgets.dart';
import 'skin_tab_bar.dart';

/// The 2.0 skin shop (PRD-menu-v2 §3–4, approved layout A "Big preview +
/// tabs") on the shared [MenuScreen] chrome (coin pill + back button, no
/// title): the collection bar, the live [PreviewStage] with the name row
/// and the action button, the five-tab [SkinTabBar] and a scrolling
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
  }) : _tab = initialTab,
       super(title: '');

  SkinLayer _tab;

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
    return id == null ? look : look.withItem(_tab, id);
  }

  /// The item the name row / action button describe: the try-on, else the
  /// equipped item of the open tab.
  SkinItem get activeItem =>
      tryOnItem ?? itemById(_tab, game.menu.items.look.idFor(_tab))!;

  /// Whether [item] shows its NEW tag (snapshot at open, cleared on tap).
  bool isNewTag(SkinItem item) => _newKeys.contains(item.key);

  bool get reduceMotion => game.reduceMotion;

  @override
  bool get showsTitle => false;

  @override
  Rect scrollViewportFor(double viewHeight) =>
      Config.skinShopGridRectFor(viewHeight);

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
    stage = PreviewStage(
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
        if (_tryOnId != null) return ShopActionKind.buy;
        return activeItem.isNone
            ? ShopActionKind.nothingOn
            : ShopActionKind.equipped;
      },
      price: () => tryOnItem?.price ?? 0,
      affordable: () => game.menu.wallet.balance >= (tryOnItem?.price ?? 0),
      tint: () => tint,
      reduceMotion: () => reduceMotion,
      onPressed: () => game.buyTriedOnItem(),
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
    _fillGrid(animate: false);
    final initial = initialTryOn;
    if (initial != null && !items.isOwned(_tab, initial)) {
      _tryOnId = initial;
      scrollToItem(initial);
    }
  }

  void _fillGrid({required bool animate}) {
    final h = game.viewHeight;
    scroll.content.removeAll(tiles);
    final list = itemsFor(_tab);
    tiles = [
      for (final (i, item) in list.indexed)
        _tile(item, Config.skinShopTileRectFor(h, i), i, animate),
    ];
    scroll
      ..contentBottom = Config.skinShopContentBottomFor(h, list.length)
      ..offset = 0
      ..content.addAll(tiles);
  }

  ItemTile _tile(SkinItem item, Rect rect, int index, bool animate) {
    late final ItemTile tile;
    tile = ItemTile(
      item: item,
      rect: rect,
      art: art,
      state: () {
        final items = game.menu.items;
        final tried = _tryOnId == item.id;
        return ItemTileState(
          owned: items.isOwned(item.layer, item.id),
          equipped: _tryOnId == null && items.isEquipped(item.layer, item.id),
          tryingOn: tried,
          isNew: _newKeys.contains(item.key),
        );
      },
      onPressed: () => game.tapItem(item.layer, item.id),
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
    _tab = layer;
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
        ScreenFlash(size: Vector2(Config.worldWidth, game.viewHeight)),
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
    super.onRemove();
  }
}
