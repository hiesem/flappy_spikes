import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../../skins/catalog.dart';
import '../../skins/look.dart';
import 'shop_glyphs.dart';
import '../../game/paints.dart';

/// Piecewise-linear keyframe lookup: [keys] are (offset, value) pairs with
/// ascending offsets from 0 to 1 (WAAPI keyframes).
double keyframe(List<(double, double)> keys, double u) {
  if (u <= keys.first.$1) return keys.first.$2;
  for (var i = 1; i < keys.length; i++) {
    final (o1, v1) = keys[i];
    if (u <= o1) {
      final (o0, v0) = keys[i - 1];
      return v0 + (v1 - v0) * (u - o0) / (o1 - o0);
    }
  }
  return keys.last.$2;
}

/// The "UNLOCKED!" banner over the preview after a purchase (PRD-menu-v2
/// §3.6, mock `.unlock`): rarity label (11 pt, spaced), the item name
/// (24 pt) and "UNLOCKED!" (12 pt) on a block in the rarity colour with a
/// 4 pt drop shadow; pops in from 30 % with a slight rotation, holds and
/// fades up after 1.9 s (2.6 s legendary), then removes itself. Without
/// motion ([reduceMotion]) it only fades.
class UnlockBanner extends PositionComponent {
  UnlockBanner({
    required this.item,
    required double centerX,
    required double top,
    this.reduceMotion = false,
  }) : duration = item.rarity == Rarity.legendary
           ? Config.skinShopBannerDurationLegendary
           : Config.skinShopBannerDuration,
       super(position: Vector2(centerX, top), priority: 50);

  final SkinItem item;
  final double duration;
  final bool reduceMotion;

  late final ShopText _rarity = ShopText(
    item.rarity?.label ?? '',
    fontSize: 11,
    color: const Color(0xE6FFFFFF),
    letterSpacingEm: 0.24,
  );
  late final ShopText _name = ShopText(
    item.name.toUpperCase(),
    fontSize: 24,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: 0.06,
  );
  late final ShopText _unlocked = ShopText(
    'UNLOCKED!',
    fontSize: 12,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: 0.2,
  );

  double _t = 0;

  /// The name line (tests).
  String get nameText => _name.text;
  String get rarityText => _rarity.text;

  double get _boxWidth =>
      math.max(_name.width, math.max(_rarity.width, _unlocked.width)) + 36;
  double get _boxHeight =>
      7 + _rarity.height + _name.height + _unlocked.height + 9;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= duration) removeFromParent();
  }

  static final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final u = Curves.easeOut.transform((_t / duration).clamp(0.0, 1.0));
    final opacity = keyframe(const [(0, 0), (.12, 1), (.85, 1), (1, 0)], u);
    if (opacity <= 0) return;
    final scale = reduceMotion
        ? 1.0
        : keyframe(const [(0, .3), (.12, 1.12), (.2, 1), (.85, 1), (1, .9)], u);
    final rotate = reduceMotion
        ? 0.0
        : keyframe(const [(0, -8), (.12, 2), (.2, 0), (1, 0)], u);
    final dy = reduceMotion
        ? 0.0
        : keyframe(const [(0, 0), (.85, 0), (1, -14)], u);
    final w = _boxWidth, h = _boxHeight;
    canvas.save();
    canvas.translate(0, dy + h / 2);
    canvas.rotate(rotate * math.pi / 180);
    canvas.scale(scale);
    canvas.saveLayer(null, layerPaint(opacity.clamp(0.0, 1.0)));
    final box = Rect.fromLTWH(-w / 2, -h / 2, w, h);
    canvas.drawRect(
      box.shift(const Offset(0, 4)),
      _paint..color = const Color(0x2E000000),
    );
    canvas.drawRect(box, _paint..color = item.rarity?.color ?? Config.menuPink);
    var y = -h / 2 + 7;
    for (final line in [_rarity, _name, _unlocked]) {
      line.paint(canvas, Offset(-line.width / 2, y));
      y += line.height;
    }
    canvas.restore();
    canvas.restore();
  }
}

/// Full-screen white flash of a legendary purchase (0.9 -> 0 over 0.6 s).
class ScreenFlash extends PositionComponent {
  ScreenFlash({required Vector2 size}) : super(size: size, priority: 60);

  double _t = 0;

  double get opacity =>
      .9 * (1 - (_t / Config.skinShopFlashDuration).clamp(0.0, 1.0));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= Config.skinShopFlashDuration) removeFromParent();
  }

  @override
  void render(Canvas canvas) => canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
  );
}

/// Short screen shake of a legendary purchase (0.38 s, mock keyframes
/// (0,0) (-4,3) (4,-3) (-2,2) (0,0)): offsets the camera, restored at the
/// end or when removed early. [keysX] / [keysY], [duration] and [delay]
/// override the skin-shop shake (e.g. the No-ads celebration).
class ScreenShake extends Component {
  ScreenShake(
    this.viewfinder, {
    this.keysX = _x,
    this.keysY = _y,
    this.duration = Config.skinShopShakeDuration,
    this.delay = 0,
  });

  final Viewfinder viewfinder;
  final List<(double, double)> keysX;
  final List<(double, double)> keysY;
  final double duration;
  final double delay;
  double _t = 0;

  static const List<(double, double)> _x = [
    (0, 0),
    (.25, -4),
    (.5, 4),
    (.75, -2),
    (1, 0),
  ];
  static const List<(double, double)> _y = [
    (0, 0),
    (.25, 3),
    (.5, -3),
    (.75, 2),
    (1, 0),
  ];

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t < delay) return;
    final u = ((_t - delay) / duration).clamp(0.0, 1.0);
    // The world moves by the offset: the camera moves the other way.
    viewfinder.position = Vector2(-keyframe(keysX, u), -keyframe(keysY, u));
    if (u >= 1) removeFromParent();
  }

  @override
  void onRemove() {
    viewfinder.position = Vector2.zero();
    super.onRemove();
  }
}

/// The dark "NOT ENOUGH COINS" toast (mock `.toast.bad`): white 15 pt text
/// on #2B2B2B, centred at top 318; pops in from 80 % (0.15 of 1.5 s),
/// holds, fades up and removes itself.
class ShopToast extends PositionComponent {
  ShopToast(this.message, {required double centerX, required double top})
    : super(position: Vector2(centerX, top), priority: 55);

  final String message;
  late final ShopText _text = ShopText(
    message,
    fontSize: 15,
    color: const Color(0xFFFFFFFF),
    letterSpacingEm: 0.08,
  );
  double _t = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= Config.skinShopToastDuration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final u = (_t / Config.skinShopToastDuration).clamp(0.0, 1.0);
    final opacity = keyframe(const [(0, 0), (.15, 1), (.8, 1), (1, 0)], u);
    final dy = keyframe(const [(0, 10), (.15, 0), (.8, 0), (1, -8)], u);
    final scale = keyframe(const [(0, .8), (.15, 1), (1, 1)], u);
    final w = _text.width + 28;
    final h = _text.height + 17;
    canvas.save();
    canvas.translate(0, dy + h / 2);
    canvas.scale(scale);
    canvas.saveLayer(null, layerPaint(opacity.clamp(0.0, 1.0)));
    canvas.drawRect(
      Rect.fromLTWH(-w / 2, -h / 2, w, h),
      Paint()..color = const Color(0xFF2B2B2B),
    );
    _text.paint(canvas, Offset(-_text.width / 2, -h / 2 + 9));
    canvas.restore();
    canvas.restore();
  }
}
