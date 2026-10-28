import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../home/menu_primitives.dart' show formatCoins, withMenuKnock;
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import 'item_art.dart';
import 'shop_widgets.dart' show ShopCardArt;
import 'shop_glyphs.dart';
import '../../game/paints.dart';

/// What a tile shows right now (read from the shop every frame).
class ItemTileState {
  const ItemTileState({
    required this.owned,
    required this.equipped,
    required this.tryingOn,
    required this.isNew,
    this.affordable = true,
  });

  final bool owned;

  /// The wallet covers the price (the tried-on BUY pill turns grey if not).
  final bool affordable;

  /// Equipped and not covered by a try-on on its layer.
  final bool equipped;
  final bool tryingOn;
  final bool isNew;
}

/// One 92 x 92 grid tile of the skin shop (PRD-menu-v2 §3.3 / §4.1, mock
/// `.tile`): the item art in an 84 x 68 box on the card fill plus its state
/// decorations — equipped (3 pt pink inner outline + check badge, the bird
/// flaps), locked (art at 42 %, lock top-left, coin price pill), trying on
/// (outline pulsing pink <-> soft, art solid, the price pill turned into a
/// pulsing pink "BUY [coin] price" pill — WP-J2: a second tap buys; grey
/// and still when unaffordable, still tappable), NEW (gold tag
/// overhanging the top-right corner, wobbling) and the rarity markers
/// (rare / epic / legendary bottom bar, epic / legendary 1 pt inner
/// outline, a moving shine on the legendary bar). Presses scale it to 93 %;
/// a tab switch fades / raises it in after [enterDelay].
///
/// Static art is a cached [Picture]; animated items (and flapping birds)
/// redraw every frame, only while the tile is inside the grid viewport.
class ItemTile extends PositionComponent with TapCallbacks {
  ItemTile({
    required this.item,
    required Rect rect,
    required this.state,
    required this.onPressed,
    required this.art,
    required this.cardColor,
    required this.tint,
    required this.reduceMotion,
    this.isActive,
    this.cardArt,
    // region P26-F10b
    this.trophyImage,
    // endregion
    this.isOnScreen,
    double? enterDelay,
    // region P26-J6
    this.rewardTile = false,
    // endregion
  }) : _age = enterDelay == null ? double.infinity : -enterDelay,
       _price = PriceChip(
         item.price,
         background: Config.menuPink,
         textColor: Config.menuSoft,
       ),
       super(
         position: rect.center.toVector2(),
         size: rect.size.toVector2(),
         anchor: Anchor.center,
       ) {
    // A random phase so neighbouring animated tiles do not move in step
    // (mock `t: Math.random() * 5`), deterministic per item.
    _t = (item.key.hashCode % 500) / 100;
  }

  // region P26-F9e
  final ShopCardArt? cardArt;
  // region P26-F10b
  /// Shared Home trophy asset, used as the skill-only mark.
  final Image? trophyImage;
  // endregion
  // endregion
  // region P26-J6
  /// Static, non-interactive reward presentation at the supplied rect size.
  final bool rewardTile;
  Picture? _rewardPicture;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!rewardTile) return;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    if (item.layer == SkinLayer.trail) {
      final emitter = art.emitterFor(item);
      for (var i = 0; i < 30; i++) {
        ItemArt.advanceTrail(emitter, i / 30, 1 / 30);
      }
      ItemArt.paint(canvas, item, emitter: emitter);
    } else {
      ItemArt.paint(canvas, item);
    }
    _rewardPicture = recorder.endRecording();
  }

  // endregion

  final SkinItem item;
  final ItemTileState Function() state;
  final void Function() onPressed;
  final ItemArtCache art;
  final Color Function() cardColor;
  final Color Function() tint;
  final bool Function() reduceMotion;
  final bool Function()? isActive;

  /// Whether the tile is inside the grid viewport (animated art only runs
  /// then; null = always).
  final bool Function()? isOnScreen;

  final PriceChip _price;
  late final TileBuyPill _buyPill = TileBuyPill(item.price);
  late final ShopText _newLabel = ShopText(
    'NEW',
    fontSize: Config.skinShopTagFontSize,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: 0.06,
  );

  // region P26-F9e
  final ShopText _nameStyleLabel = ShopText(
    'NAME STYLE',
    fontSize: 7,
    color: Config.menuPlum,
  );
  final ShopText _skillLabel = ShopText(
    '? ? ?',
    fontSize: 10,
    color: Config.menuPlum,
  );
  // endregion
  double _t = 0;
  double _clock = 0;
  double _age;
  bool _pressed = false;
  double _scale = 1;
  ItemTileState _state = const ItemTileState(
    owned: false,
    equipped: false,
    tryingOn: false,
    isNew: false,
  );

  ItemTileState get current => _state;

  /// Whether the BUY pill replaces the price pill (locked + tried on).
  bool get showsBuyPill =>
      !item.isSkillOnly && !_state.owned && _state.tryingOn;

  /// The BUY pill (tests).
  TileBuyPill get buyPill => _buyPill;

  /// Current BUY pill scale (1 when still: unaffordable / reduce motion).
  double get buyPillScale {
    if (!showsBuyPill || !_state.affordable || reduceMotion()) return 1;
    // Same `buyp 1s ease-in-out infinite` pulse as the preview's BUY.
    final u = _clock % 1;
    final k = Curves.easeInOut.transform(u < .5 ? u * 2 : 2 - u * 2);
    return 1 + (Config.skinShopActionPulse - 1) * k;
  }

  /// BUY pill rect in tile-local coordinates (unscaled).
  Rect get buyPillRect => Rect.fromLTWH(
    (width - _buyPill.width) / 2,
    height - Config.skinShopPriceBottom - _buyPill.height,
    _buyPill.width,
    _buyPill.height,
  );
  bool get pressed => _pressed;

  /// Entrance progress 0..1 (1 = settled).
  double get enterProgress =>
      (_age / Config.skinShopEnterDuration).clamp(0.0, 1.0);

  /// Whether the art is redrawn every frame (vs. the cached picture).
  bool get animatesArt =>
      (item.layer == SkinLayer.card
          ? ShopCardArt.animated(item)
          : ItemArt.isAnimated(item)) ||
      (item.layer == SkinLayer.bird && (_state.equipped || _state.tryingOn));

  bool get _visible => isOnScreen?.call() ?? true;

  // region P26-J6
  @override
  bool containsLocalPoint(Vector2 point) =>
      !rewardTile &&
      (isActive?.call() ?? true) &&
      super.containsLocalPoint(point);

  // endregion

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _pressed = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    _pressed = false;
    withMenuKnock(this, onPressed);
  }

  @override
  void onTapCancel(TapCancelEvent event) => _pressed = false;

  @override
  void update(double dt) {
    super.update(dt);
    // region P26-J6
    if (rewardTile) return;
    // endregion
    // region P26-F9e
    if (!_visible || reduceMotion()) cardArt?.releaseAnimation(this);
    // endregion
    _state = state();
    _clock += dt;
    if (_age < Config.skinShopEnterDuration) _age += dt;
    // CSS `transition: transform .12s`.
    final target = _pressed ? Config.skinShopPressScale : 1.0;
    final step = dt / 0.12 * (1 - Config.skinShopPressScale);
    _scale = _scale < target
        ? math.min(target, _scale + step)
        : math.max(target, _scale - step);
    scale.setAll(_scale);
    if (_visible && animatesArt && !reduceMotion()) {
      _t += dt;
      if (item.layer == SkinLayer.trail) {
        ItemArt.advanceTrail(art.emitterFor(item), _t, dt);
      }
    }
  }

  // region P26-F9e
  @override
  void onRemove() {
    // region P26-J6
    _rewardPicture?.dispose();
    _rewardPicture = null;
    // endregion
    cardArt?.releaseAnimation(this);
    super.onRemove();
  }
  // endregion

  @override
  void renderTree(Canvas canvas) {
    if (!_visible) {
      cardArt?.releaseAnimation(this);
      return;
    }
    final e = enterProgress;
    if (e >= 1) {
      super.renderTree(canvas);
      return;
    }
    if (e <= 0) return;
    final eased = Curves.easeOut.transform(e);
    canvas.saveLayer(null, layerPaint(eased));
    if (!reduceMotion()) {
      canvas.translate(0, Config.skinShopEnterRise * (1 - eased));
    }
    super.renderTree(canvas);
    canvas.restore();
  }

  static final Paint _paint = Paint();
  static final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  static final Paint _alpha = Paint();

  @override
  void render(Canvas canvas) {
    // region P26-J6
    if (rewardTile) {
      final rarity = item.rarity?.color ?? const Color(0xFF999999);
      canvas.drawRect(size.toRect(), _paint..color = const Color(0xFFF4F4F4));
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(2, 2, width - 4, height - 6));
      final artScale = math.min(
        (width - 4) / ItemArt.w,
        (height - 6) / ItemArt.h,
      );
      canvas.translate(
        (width - ItemArt.w * artScale) / 2,
        2 + (height - 6 - ItemArt.h * artScale) / 2,
      );
      canvas.scale(artScale);
      final picture = _rewardPicture;
      if (picture != null) canvas.drawPicture(picture);
      canvas.restore();
      canvas.drawRect(
        size.toRect().deflate(1),
        _stroke
          ..color = rarity
          ..strokeWidth = 2,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, height - 4, width, 4),
        _paint..color = rarity,
      );
      return;
    }
    // endregion
    final s = _state;
    final rect = size.toRect();
    canvas.drawRect(
      rect,
      _paint..color = item.isSkillOnly ? const Color(0xFFFFF2CF) : cardColor(),
    );

    // Art (42 % while locked, solid while being tried on). Static art is a
    // cached picture with that alpha already baked in, so a settled locked
    // tile never composites a per-frame layer; only the animated art (whose
    // picture changes every frame) is dimmed through one.
    final dim = !s.owned && !s.tryingOn;
    canvas.save();
    canvas.translate(
      (width - Config.skinShopArtWidth) / 2,
      (height - Config.skinShopArtHeight) / 2,
    );
    // The mock's thumbnail is an 84 x 68 canvas: art never leaves it.
    canvas.clipRect(
      const Rect.fromLTWH(
        0,
        0,
        Config.skinShopArtWidth,
        Config.skinShopArtHeight,
      ),
    );
    // region P26-F9e
    if (item.layer == SkinLayer.card && cardArt != null) {
      if (dim) {
        canvas.saveLayer(
          null,
          _alpha
            ..color = const Color.fromRGBO(
              0,
              0,
              0,
              Config.skinShopLockedOpacity,
            ),
        );
      }
      canvas.save();
      canvas.translate(
        Config.skinShopArtWidth / 2,
        Config.skinShopArtHeight / 2,
      );
      cardArt!.paint(
        canvas,
        item,
        reduceMotion() || !_visible ? 0 : _t,
        owner: this,
      );
      canvas.restore();
      if (dim) canvas.restore();
    } else if (animatesArt) {
      // endregion
      if (dim) {
        canvas.saveLayer(
          const Rect.fromLTWH(
            0,
            0,
            Config.skinShopArtWidth,
            Config.skinShopArtHeight,
          ),
          _alpha
            ..color = const Color.fromRGBO(
              0,
              0,
              0,
              Config.skinShopLockedOpacity,
            ),
        );
      }
      final flap = item.layer == SkinLayer.bird && (s.equipped || s.tryingOn);
      ItemArt.paint(
        canvas,
        item,
        t: _t,
        flap: flap,
        emitter: item.layer == SkinLayer.trail ? art.emitterFor(item) : null,
      );
      if (dim) canvas.restore();
    } else {
      canvas.drawPicture(
        dim ? art.lockedPictureFor(item) : art.pictureFor(item),
      );
    }
    canvas.restore();

    // region P26-F9e
    if (item.cardKind == CardKind.name) {
      _nameStyleLabel.paint(
        canvas,
        Offset((width - _nameStyleLabel.width) / 2, 59),
      );
    }
    // endregion
    // Inner outlines: equipped / trying on win over the rarity outline.
    final rarity = item.isNone ? null : item.rarity;
    const ow = Config.skinShopOutline;
    if (s.equipped || s.tryingOn) {
      var color = Config.menuPink;
      if (s.tryingOn && !reduceMotion()) {
        // `.9s ease-in-out infinite alternate` pink -> soft.
        final u =
            (_clock % (2 * Config.skinShopTryPulse)) / Config.skinShopTryPulse;
        final k = Curves.easeInOut.transform(u > 1 ? 2 - u : u);
        color = Color.lerp(Config.menuPink, Config.menuSoft, k)!;
      }
      canvas.drawRect(
        rect.deflate(ow / 2),
        _stroke
          ..color = color
          ..strokeWidth = ow,
      );
    } else if (rarity == Rarity.epic || rarity == Rarity.legendary) {
      canvas.drawRect(
        rect.deflate(.5),
        _stroke
          ..color = rarity!.color.withValues(
            alpha: rarity == Rarity.epic ? .35 : .6,
          )
          ..strokeWidth = 1,
      );
    }

    // region P26-F10b
    final trophy = trophyImage;
    if (item.isSkillOnly && trophy != null) {
      canvas.drawImageRect(trophy,
        Rect.fromLTWH(0, 0, trophy.width.toDouble(), trophy.height.toDouble()),
        const Rect.fromLTWH(5, 4, 15, 15), _paint..color = const Color(0xFFFFFFFF));
    }
    // endregion
    // Lock + price pill.
    if (!s.owned) {
      // region P26-F10b
      if (!item.isSkillOnly) {
      // endregion
      canvas.save();
      canvas.translate(Config.skinShopLockLeft, Config.skinShopLockTop);
      ShopGlyphs.lock(
        canvas,
        Config.skinShopLockSize,
        tint().withValues(alpha: .75),
      );
      canvas.restore();
      // region P26-F10b
      }
      // endregion
      if (item.isSkillOnly) {
        // region P26-F10b
        canvas.drawRect(
          Rect.fromLTWH((width - _skillLabel.width - 16) / 2, height - 24,
              _skillLabel.width + 16, 19),
          _paint..color = Config.menuGold,
        );
        // endregion
        _skillLabel.paint(
          canvas,
          Offset((width - _skillLabel.width) / 2, height - 20),
        );
      } else if (s.tryingOn) {
        final r = buyPillRect;
        final k = buyPillScale;
        canvas.save();
        canvas.translate(r.center.dx, r.center.dy);
        canvas.scale(k);
        _buyPill.paint(
          canvas,
          Offset(-r.width / 2, -r.height / 2),
          poor: !s.affordable,
        );
        canvas.restore();
      } else {
        _price.paint(
          canvas,
          Offset(
            (width - _price.width) / 2,
            height - Config.skinShopPriceBottom - _price.height,
          ),
        );
      }
    }

    // Check badge.
    if (s.equipped) {
      const b = Config.skinShopCheckBadge;
      canvas.drawRect(
        Rect.fromLTWH(width - b, height - b, b, b),
        _paint..color = Config.menuPink,
      );
      canvas.save();
      canvas.translate(width - b + 4, height - b + 4);
      ShopGlyphs.check(canvas, 14, const Color(0xFFFFFFFF));
      canvas.restore();
    }

    // Rarity bar (above the badge, as the mock's ::after).
    if (rarity != null && rarity != Rarity.common) {
      final bar = Rect.fromLTWH(
        0,
        height - Config.skinShopRarityBar,
        width,
        Config.skinShopRarityBar,
      );
      if (rarity == Rarity.legendary) {
        // 200 %-wide gold / light / gold gradient sliding right, 1.6 s.
        final period = 2 * width;
        final shift = reduceMotion()
            ? 0.0
            : (_clock % Config.skinShopShineLoop) /
                  Config.skinShopShineLoop *
                  period;
        _paint.shader = Gradient.linear(
          Offset(shift, 0),
          Offset(shift + period, 0),
          const [Color(0xFFFFB529), Color(0xFFFFF6D6), Color(0xFFFFB529)],
          const [0, .5, 1],
          TileMode.repeated,
        );
        canvas.drawRect(bar, _paint);
        _paint.shader = null;
      } else {
        canvas.drawRect(bar, _paint..color = rarity.color);
      }
    }

    if (s.isNew) _paintNewTag(canvas);
  }

  void _paintNewTag(Canvas canvas) {
    const padX = 5.0, padY = 2.0;
    final tw = _newLabel.width + 2 * padX;
    final th = _newLabel.height + 2 * padY;
    final right = width + Config.skinShopTagOverhangX;
    final top = -Config.skinShopTagOverhangY;
    canvas.save();
    canvas.translate(right - tw / 2, top + th / 2);
    if (!reduceMotion()) {
      // `nwb 1.2s ease-in-out infinite`: 50 % = scale 1.12, rotate 4°.
      final u = (_clock % Config.skinShopNewWobble) / Config.skinShopNewWobble;
      final k = Curves.easeInOut.transform(u < .5 ? u * 2 : 2 - u * 2);
      canvas.rotate(4 * math.pi / 180 * k);
      canvas.scale(1 + .12 * k);
    }
    canvas.drawRect(
      Rect.fromLTWH(-tw / 2, -th / 2, tw, th),
      _paint..color = Config.menuGold,
    );
    _newLabel.paint(canvas, Offset(-tw / 2 + padX, -th / 2 + padY));
    canvas.restore();
  }
}

/// The tried-on tile's "BUY [coin] price" pill (WP-J2): pink with soft
/// text like the preview's BUY button, grey #A0A0A0 when unaffordable.
/// Sized so "BUY 5 000" still fits a 92 pt tile at the 1.06 pulse peak.
class TileBuyPill {
  TileBuyPill(int price)
    : _buy = ShopText(
        'BUY',
        fontSize: fontSize,
        color: Config.menuSoft,
        letterSpacingEm: 0.06,
      ),
      _price = ShopText(
        formatCoins(price),
        fontSize: fontSize,
        color: Config.menuSoft,
        letterSpacingEm: 0.04,
      );

  static const double fontSize = 10, padX = 4, padY = 3, gap = 3, coin = 11;
  static const double coinGap = 2;

  final ShopText _buy, _price;

  /// "BUY" and the price (tests).
  String get label => '${_buy.text} ${_price.text}';

  double get width =>
      padX + _buy.width + gap + coin + coinGap + _price.width + padX;
  double get height => coin + 2 * padY;

  static final Paint _paint = Paint();

  void paint(Canvas canvas, Offset topLeft, {required bool poor}) {
    canvas.drawRect(
      topLeft & Size(width, height),
      _paint..color = poor ? Config.skinShopPoorGrey : Config.menuPink,
    );
    var x = topLeft.dx + padX;
    _buy.paint(canvas, Offset(x, topLeft.dy + (height - _buy.height) / 2));
    x += _buy.width + gap;
    canvas.save();
    canvas.translate(x, topLeft.dy + padY);
    ShopGlyphs.coin(canvas, coin);
    canvas.restore();
    x += coin + coinGap;
    _price.paint(canvas, Offset(x, topLeft.dy + (height - _price.height) / 2));
  }
}
