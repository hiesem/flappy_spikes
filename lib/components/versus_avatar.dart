import 'dart:ui';

import '../skins/art/look_painter.dart';
import '../skins/look.dart';

/// PRD-2.3 §21.3 the opponent's avatar fallback, one painter for every
/// avatar square (VS intro plate, versus HUD bar, results column): while
/// their picture loads, if it fails, or when they have none, the square
/// shows **their own bird in their look** ([LookPainter], the same art as
/// `LookComponent`), on the square's tint. The grey person icon is never
/// used for opponents (PRD-2.3 §0 item 6: it stays only on the NO RIVAL
/// FOUND plate).
abstract final class VersusAvatar {
  /// The bird's art box (44 art units wide) fills this share of the square.
  static const double birdFill = .78;

  /// Paints [look] centred in [r] (clipped to it), facing left when
  /// [mirror] (the opponent's side), at [opacity]; [t] drives animated
  /// items.
  static void paintBird(
    Canvas canvas,
    Rect r,
    Look look, {
    bool mirror = false,
    double opacity = 1,
    double t = 0,
  }) {
    if (opacity <= 0) return;
    canvas.save();
    canvas.clipRect(r);
    final layer = opacity < 1;
    if (layer) {
      canvas.saveLayer(
        r,
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0, 1)),
      );
    }
    final k = r.width * birdFill / LookPainter.boxWidth;
    // A little below centre: hats poke out above the 36-unit art box.
    canvas.translate(r.center.dx, r.center.dy + r.height * .06);
    canvas.scale(mirror ? -k : k, k);
    LookPainter.paint(canvas, look, t: t);
    if (layer) canvas.restore();
    canvas.restore();
  }
}
