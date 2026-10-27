import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/animation.dart' show Cubic;

import '../../game/config.dart';
import '../home/menu_primitives.dart' show withMenuKnock;
import '../../skins/look.dart';
import 'shop_glyphs.dart';

/// CSS `cubic-bezier(.3, 1.4, .5, 1)`: the underline's overshoot.
const Cubic kSkinShopOvershoot = Cubic(.3, 1.4, .5, 1);

/// The five-tab bar of the skin shop (PRD-menu-v2 §4.1, mock `.tabs`): per
/// tab a silhouette icon (30 x 24), the layer name (9 pt) and owned/total
/// (9 pt, 70 %); the active tab is pink with its icon at 118 %, and a 3 pt
/// pink underline slides between tabs (0.3 s, overshoot).
class SkinTabBar extends PositionComponent {
  SkinTabBar({
    required Rect rect,
    required this.active,
    required this.counter,
    required this.tint,
    required this.onSelect,
    this.isActive,
  }) : super(position: rect.topLeft.toVector2(), size: rect.size.toVector2());

  /// The open tab.
  final SkinLayer Function() active;

  /// "owned/total" of a layer.
  final String Function(SkinLayer layer) counter;
  final Color Function() tint;
  final void Function(SkinLayer layer) onSelect;
  final bool Function()? isActive;

  late final List<SkinTab> tabs;

  double _ulFrom = 0;
  double _ulTo = 0;
  double _ulT = 1;
  SkinLayer? _shown;

  // region P26-F9a
  double get tabWidth => width / kShopLayers.length;
  // endregion

  /// Underline left edge right now (relative to the bar).
  double get underlineX =>
      _ulFrom + (_ulTo - _ulFrom) * kSkinShopOvershoot.transform(_ulT);

  /// Whether the underline is still sliding.
  bool get sliding => _ulT < 1;

  SkinTab tabFor(SkinLayer layer) => tabs[layer.index];

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // region P26-F9a
    tabs = [
      for (final layer in kShopLayers)
        SkinTab(
          layer: layer,
          bar: this,
          position: Vector2(layer.index * tabWidth, 0),
          size: Vector2(tabWidth, height),
        ),
    ];
    // endregion
    addAll(tabs);
    _shown = active();
    _ulFrom = _ulTo = _shown!.index * tabWidth;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final current = active();
    if (current != _shown) {
      _ulFrom = underlineX;
      _ulTo = current.index * tabWidth;
      _ulT = 0;
      _shown = current;
    }
    if (_ulT < 1) {
      _ulT = (_ulT + dt / Config.skinShopTabSlideDuration).clamp(0.0, 1.0);
    }
  }

  static final Paint _ul = Paint()..color = Config.menuPink;

  @override
  void renderTree(Canvas canvas) {
    super.renderTree(canvas);
    canvas.drawRect(
      Rect.fromLTWH(
        x + underlineX,
        y + height - Config.skinShopTabUnderline,
        tabWidth,
        Config.skinShopTabUnderline,
      ),
      _ul,
    );
  }
}

/// One tab of [SkinTabBar] (icon, name, counter in a centred column with
/// 2 pt gaps).
class SkinTab extends PositionComponent with TapCallbacks {
  SkinTab({required this.layer, required this.bar, super.position, super.size});

  final SkinLayer layer;
  final SkinTabBar bar;

  late final ShopText _name = ShopText(
    layer.tabLabel,
    fontSize: Config.skinShopTabFontSize,
    color: Config.menuPink,
    letterSpacingEm: 0.1,
  );
  late final ShopText _count = ShopText(
    '',
    fontSize: Config.skinShopTabFontSize,
    color: Config.menuPink,
  );

  /// Icon scale (eases toward 1.18 when active, CSS `transition: .2s`).
  double _iconScale = 1;

  bool get selected => bar.active() == layer;

  /// The counter text (tests).
  String get countText => _count.text;

  @override
  bool containsLocalPoint(Vector2 point) =>
      (bar.isActive?.call() ?? true) && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) => event.handled = true;

  @override
  void onTapUp(TapUpEvent event) {
    event.handled = true;
    withMenuKnock(this, () => bar.onSelect(layer));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _count.text = bar.counter(layer);
    final target = selected ? Config.skinShopTabIconActiveScale : 1.0;
    final step = dt / 0.2 * (Config.skinShopTabIconActiveScale - 1);
    _iconScale = _iconScale < target
        ? (_iconScale + step).clamp(1.0, target)
        : (_iconScale - step).clamp(target, Config.skinShopTabIconActiveScale);
  }

  @override
  void render(Canvas canvas) {
    final color = selected ? Config.menuPink : bar.tint();
    _name.color = color;
    _count.color = color.withValues(alpha: color.a * .7);
    const iw = Config.skinShopTabIconWidth, ih = Config.skinShopTabIconHeight;
    const gap = 2.0;
    final total = ih + gap + _name.height + gap + _count.height;
    var y = (height - total) / 2;
    canvas.save();
    canvas.translate(width / 2, y + ih / 2);
    final k = (_iconScale - 1) / (Config.skinShopTabIconActiveScale - 1);
    canvas.translate(0, -k);
    canvas.scale(_iconScale);
    canvas.translate(-iw / 2, -ih / 2);
    ShopGlyphs.tabIcon(canvas, layer, iw, ih, color);
    canvas.restore();
    y += ih + gap;
    _name.paint(canvas, Offset((width - _name.width) / 2, y));
    y += _name.height + gap;
    _count.paint(canvas, Offset((width - _count.width) / 2, y));
  }
}
