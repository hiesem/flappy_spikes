import 'dart:ui' show Canvas, Color, Paint, Path, PathFillType, Rect;

import 'package:flame/components.dart';
import 'package:flame/effects.dart' show OpacityProvider;
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import 'home/menu_primitives.dart';

/// PRD-2.3 §26.2: the lock over a Shop or Skins screen that the player has
/// not unlocked yet (best score below [Config.menuUnlockBest]). It dims the
/// whole playfield edge to edge, both spike strips included
/// ([Config.menuLockDimColor], #000000 at 90 %; owner 2026-10-13), and shows
/// two centred lines of text. It lives in the world at
/// [Config.menuLockOverlayPriority] (above the screens and the ground strip
/// the game draws over them) and follows its screen's fade ([source]). The
/// back button stays bright through a hole (its artwork is the shared
/// corner box below the screens; QA S8-12) and the coin pill is lifted above
/// the overlay while it is up ([Config.menuLockPillPriority]). It swallows
/// every other tap, so nothing under it reacts: no sound, no knock, no
/// scroll.
class MenuLockOverlay extends PositionComponent
    with TapCallbacks, GroupOpacity, HasGameReference<FlappySpikesGame> {
  MenuLockOverlay({
    required Rect rect,
    required this.lines,
    Rect? hole,
    this.source,
  }) : _hole = hole?.shift(-rect.topLeft),
       super(
         position: rect.topLeft.toVector2(),
         size: rect.size.toVector2(),
         priority: Config.menuLockOverlayPriority,
       );

  /// The back button's box (in world coordinates), left undimmed: its
  /// artwork is the shared corner box below the screens, which must stay
  /// fully bright (PRD-2.3 §26.2, QA S8-12). Stored in local coordinates.
  final Rect? _hole;

  /// The text lines, top to bottom (`SCORE 25 POINTS` / `TO UNLOCK THE SHOP`).
  final List<String> lines;

  /// The locked screen whose opacity (crossfades) the overlay follows.
  final OpacityProvider? source;

  /// #000000 at 90 % (PRD-2.3 §26.2, owner 2026-10-13).
  static const Color dimColor = Config.menuLockDimColor;

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
  void onMount() {
    super.onMount();
    final pill = game.coinPill;
    if (pill.priority < Config.menuLockPillPriority) {
      pill.priority = Config.menuLockPillPriority;
    }
  }

  @override
  void onRemove() {
    final others = parent?.children
        .whereType<MenuLockOverlay>()
        .any((o) => o != this && !o.isRemoving);
    final pill = game.coinPill;
    if (others != true && pill.priority == Config.menuLockPillPriority) {
      pill.priority = FlappySpikesGame.groundOverMenusPriority;
    }
    super.onRemove();
  }

  @override
  void renderTree(Canvas canvas) {
    final s = source;
    if (s != null) opacity = s.opacity;
    super.renderTree(canvas);
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

  /// The hole belongs to the back button below (it takes its own taps).
  @override
  bool containsLocalPoint(Vector2 point) =>
      super.containsLocalPoint(point) &&
      !(_hole?.contains(point.toOffset()) ?? false);

  /// The taps on the lock are used up here (no sound, no knock).
  @override
  void onTapDown(TapDownEvent event) => event.handled = true;
}
