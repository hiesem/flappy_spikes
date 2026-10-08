import 'dart:ui';

import 'package:flame/cache.dart';
import 'package:flame/components.dart';

/// Master #14 — the coin icon (PRD §3.0.6 / §3.0.9 #14): always the game's
/// `menu/coin.png` sprite (solid `#FFB529` disc with a thick pale inner
/// ring), never a code-drawn coin. The only parameter is the size.
abstract final class CoinIcon {
  /// Asset path under `assets/images/`.
  static const String asset = 'menu/coin.png';

  static Future<Image> load(Images images) => images.load(asset);

  static Future<Sprite> sprite(Images images) async =>
      Sprite(await images.load(asset));

  static final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  /// Draws [image] (the loaded coin) as a [size] pt disc centred at [centre].
  static void paint(
    Canvas canvas,
    Image image,
    Offset centre,
    double size, {
    double opacity = 1,
  }) {
    if (size <= 0 || opacity <= 0) return;
    _paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: centre, width: size, height: size),
      _paint,
    );
  }
}
