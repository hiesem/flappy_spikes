import 'dart:ui' show Canvas, Color, Paint, Path, PathFillType, Rect;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../game/config.dart';
import 'home/menu_primitives.dart';

/// PRD-2.3 §26.2: the lock over a Shop or Skins screen that the player has
/// not unlocked yet (best score below [Config.menuUnlockBest]). It dims the
/// content area between the spike strips (#000000 at 72 %) and shows two
/// centred lines of text. It sits above the content and below the back
/// button and the coin pill (the screen gives those a higher priority), and
/// it swallows every tap on it, so nothing under it reacts: no sound, no
/// knock, no scroll.
class MenuLockOverlay extends PositionComponent with TapCallbacks {
  MenuLockOverlay({required Rect rect, required this.lines, Rect? hole})
    : _hole = hole?.shift(-rect.topLeft),
      super(position: rect.topLeft.toVector2(), size: rect.size.toVector2());

  /// The back button's box (in the screen's coordinates), left undimmed:
  /// its artwork is the shared corner box below the screens, which must stay
  /// fully bright (PRD-2.3 §26.2, QA S8-12). Stored in local coordinates.
  final Rect? _hole;

  /// The text lines, top to bottom (`SCORE 25 POINTS` / `TO UNLOCK THE SHOP`).
  final List<String> lines;

  /// #000000 at 72 % (PRD-2.3 §26.2).
  static const Color dimColor = Color(0xB8000000);

  final Paint _paint = Paint()..color = dimColor;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final count = lines.length;
    for (var i = 0; i < count; i++) {
      add(
        MenuText(
          lines[i],
          fontSize: Config.menuLockFontSize,
          color: const Color(0xFFFFFFFF),
          letterSpacingEm: Config.menuLockLetterSpacing,
          position: Vector2(
            width / 2,
            height / 2 + (i - (count - 1) / 2) * Config.menuLockLineHeight,
          ),
          anchor: Anchor.center,
        ),
      );
    }
  }

  @override
  void render(Canvas canvas) {
    final hole = _hole;
    if (hole == null) {
      canvas.drawRect(size.toRect(), _paint);
      return;
    }
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(size.toRect())
        ..addRect(hole),
      _paint,
    );
  }

  /// The hole belongs to the back button above (it takes its own taps).
  @override
  bool containsLocalPoint(Vector2 point) =>
      super.containsLocalPoint(point) &&
      !(_hole?.contains(point.toOffset()) ?? false);

  /// The taps on the lock are used up here (no sound, no knock).
  @override
  void onTapDown(TapDownEvent event) => event.handled = true;
}
