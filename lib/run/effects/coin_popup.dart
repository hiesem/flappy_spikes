import 'dart:ui';

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../config/parts_config.dart';
import 'coin_icon.dart';
import 'particle_pool.dart';
import '../../game/paints.dart';

/// Master #8 — the pass coin popup (PRD §3.0.9 #8, §5.4 `Scene.coin`): gold
/// `#FFB529` "+N" in 28 pt Opificio followed (3 pt gap) by the 24 pt
/// `coin.png` icon, its top-left corner starting at (x − 10, y − 70) from the
/// pass point. Over 1.1 s: in the first 20 % opacity 0 → 1, scale 0.7 → 1.1,
/// y +6 → −4; then opacity → 0, scale → 1, y → −40 (linear, scale about the
/// popup centre). A normal pass shows "+1", a perfect pass "+2", the chick
/// egg adds the "×2" suffix.
///
/// Recycle through an [EffectPool]: `pool.obtain()..play(...)`.
class CoinPopup extends PooledEffect {
  CoinPopup({super.priority});

  /// A pool for coin popups (one per layer).
  static EffectPool<CoinPopup> newPool() => EffectPool(CoinPopup.new);

  int amount = 1;
  bool doubled = false;
  /// The loaded `coin.png` (set in [onLoad]; tests may set it directly).
  Image? coinImage;
  TextPainter? _text;
  String _textKey = '';

  @override
  double get duration => PartsConfig.popupDuration;

  /// Starts the popup for a pass at [at] (the bird/hoop point).
  CoinPopup play(Offset at, int amount, {bool doubled = false, double delay = 0}) {
    this.amount = amount;
    this.doubled = doubled;
    position.setValues(at.dx, at.dy);
    restart(delay: delay);
    return this;
  }

  /// Width of the "+N" text (for tests / layout).
  double get textWidth => _layoutText().width;

  @override
  Future<void> onLoad() async {
    coinImage ??= await CoinIcon.load(findGame()!.images);
  }

  TextPainter _layoutText() {
    final key = '+$amount${doubled ? ' ×2' : ''}';
    if (_text != null && key == _textKey) return _text!;
    _textKey = key;
    _text = TextPainter(
      text: TextSpan(
        text: '+$amount',
        style: const TextStyle(
          fontFamily: Config.uiFont,
          fontSize: PartsConfig.popupFontSize,
          color: PartsConfig.gold,
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
    return _text!;
  }

  TextPainter? _suffix;

  @override
  void renderAt(Canvas canvas, double k) {
    final double alpha, scale, dy;
    if (k < .2) {
      final u = k / .2;
      alpha = u;
      scale = .7 + .4 * u;
      dy = 6 - 10 * u;
    } else {
      final u = (k - .2) / .8;
      alpha = 1 - u;
      scale = 1.1 - .1 * u;
      dy = -4 - (PartsConfig.popupRise - 4) * u;
    }
    if (alpha <= 0) return;
    final text = _layoutText();
    const coin = PartsConfig.popupCoinSize;
    const gap = PartsConfig.popupGap;
    final suffix = doubled
        ? (_suffix ??= TextPainter(
            text: const TextSpan(
              text: '×2',
              style: TextStyle(
                fontFamily: Config.uiFont,
                fontSize: PartsConfig.popupFontSize,
                color: PartsConfig.gold,
              ),
            ),
            textDirection: p.TextDirection.ltr,
          )..layout())
        : null;
    final w = text.width + gap + coin + (suffix == null ? 0 : gap + suffix.width);
    final h = text.height > coin ? text.height : coin;
    final left = PartsConfig.popupOffset.dx;
    final top = PartsConfig.popupOffset.dy + dy;
    canvas.save();
    canvas.translate(left + w / 2, top + h / 2);
    canvas.scale(scale);
    canvas.translate(-w / 2, -h / 2);
    canvas.saveLayer(
      Rect.fromLTWH(-4, -4, w + 8, h + 8),
      layerPaint(alpha.clamp(0.0, 1.0)),
    );
    text.paint(canvas, Offset(0, (h - text.height) / 2));
    final coinImage = this.coinImage;
    if (coinImage != null) {
      CoinIcon.paint(
        canvas,
        coinImage,
        Offset(text.width + gap + coin / 2, h / 2),
        coin,
      );
    }
    suffix?.paint(
      canvas,
      Offset(text.width + gap + coin + gap, (h - suffix.height) / 2),
    );
    canvas.restore();
    canvas.restore();
  }
}
