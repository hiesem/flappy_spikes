import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:flutter/painting.dart' as p show TextDirection;

import '../../game/config.dart';
import '../config/fever_config.dart';
import 'banners.dart';
import '../../game/paints.dart';

/// §5.18 the FEVER! banner: "FEVER!" in Opificio 44 pt with a vertical
/// gradient `#FFF59D` → `#FF9800` → `#E64A19` and a 7 pt plum `#7A0044`
/// outline; pops in (0.6 → 1.1 → 1), a slight tilt and jitter, ≈ 1.6 s,
/// fading over its last 0.3 s. It shows **above** the tier banner, together
/// with it (the [BannerLane.fever] slot of master #7's [BannerHost]).
class FeverBanner extends RunBanner {
  FeverBanner() : super(lane: BannerLane.fever);

  @override
  String get text => FeverConfig.bannerText;

  @override
  Color get color => FeverConfig.bannerOutline;

  @override
  double get fontSize => FeverConfig.bannerFontSize;

  @override
  double get duration => FeverConfig.bannerDuration;

  TextPainter? _fill, _stroke;

  static TextStyle _style(Paint paint) => TextStyle(
    fontFamily: Config.uiFont,
    fontSize: FeverConfig.bannerFontSize,
    foreground: paint,
  );

  void _layout() {
    if (_fill != null) return;
    final probe = TextPainter(
      text: TextSpan(text: text, style: _style(Paint())),
      textDirection: p.TextDirection.ltr,
    )..layout();
    final h = probe.height;
    _stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: _style(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = FeverConfig.bannerOutlineWidth
            ..strokeJoin = StrokeJoin.round
            ..color = FeverConfig.bannerOutline,
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
    _fill = TextPainter(
      text: TextSpan(
        text: text,
        style: _style(
          Paint()
            ..shader = Gradient.linear(
              Offset(0, h / 2 - 24),
              Offset(0, h / 2 + 24),
              FeverConfig.bannerGradient,
              const [0, .5, 1],
            ),
        ),
      ),
      textDirection: p.TextDirection.ltr,
    )..layout();
  }

  /// (scale, opacity) at [t] s: pop 0.6 → 1.1 over 0.12 s, back to 1 by
  /// 0.22 s, fade over the last 0.3 s.
  (double, double) popAt(double t) {
    final pop = t < .12
        ? .6 + t / .12 * .5
        : t < .22
        ? 1.1 - (t - .12)
        : 1.0;
    final a = ((duration - t) / .3).clamp(0.0, 1.0);
    return (pop, a);
  }

  @override
  Future<void> onLoad() async {
    position = Vector2(bandWidth / 2, FeverConfig.bannerCentreY);
    size = Vector2.zero();
  }

  @override
  void render(Canvas canvas) {
    _layout();
    final (s, a) = popAt(time);
    if (a <= 0) return;
    final fill = _fill!, stroke = _stroke!;
    canvas.save();
    canvas.scale(s, s);
    canvas.rotate(
      FeverConfig.bannerTilt + math.sin(time * 30) * FeverConfig.bannerJitter,
    );
    final layer = a < 1;
    if (layer) {
      canvas.saveLayer(null, layerPaint(a));
    }
    final o = Offset(-fill.width / 2, -fill.height / 2);
    stroke.paint(canvas, o);
    fill.paint(canvas, o);
    if (layer) canvas.restore();
    canvas.restore();
  }
}
