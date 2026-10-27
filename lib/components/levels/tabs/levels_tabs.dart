import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/rendering.dart';

import '../../../game/config.dart';
import '../../../game/storage.dart';
import '../../home/menu_primitives.dart';

/// PRD G4 / O69. Every entry starts on LEVELS; selection is not persisted.
enum LevelsTab {
  levels('LEVELS', 'LEVELS'),
  worlds('WORLDS', 'WORLDS'),
  guide('GUIDE', 'FLIGHT GUIDE'),
  album('ALBUM', 'PUZZLE ALBUM');

  const LevelsTab(this.label, this.title);
  final String label;
  final String title;
}

/// Fixed 320 pt layout from levels_tabs.html (including the 568 pt frame).
abstract final class LevelsTabsLayout {
  static const header = Rect.fromLTWH(14, 172, 292, 84);
  static const listTop = 264.0;
  static Rect viewport(double height) => Rect.fromLTRB(0, listTop, 320, height);
  static Rect tab(LevelsTab tab) =>
      Rect.fromLTWH(14 + tab.index * 74, 134, 70, 28);
}

/// Text-only tabs, using the shared menu button master.
class LevelsTabs extends PositionComponent {
  LevelsTabs({required this.onSelect, required this.isActive})
    : super(priority: 10);

  final void Function(LevelsTab) onSelect;
  final bool Function() isActive;
  LevelsTab selected = LevelsTab.levels;
  final Map<LevelsTab, MenuButton> buttons = {};
  final Map<LevelsTab, MenuText> labels = {};
  final Map<LevelsTab, _TabDot> _dots = {};

  bool hasDot(LevelsTab tab) => _dots[tab]?.shown ?? false;

  @override
  Future<void> onLoad() async {
    for (final tab in LevelsTab.values) {
      final rect = LevelsTabsLayout.tab(tab);
      final button = MenuButton(
        position: Vector2(rect.left, rect.top),
        size: Vector2(rect.width, rect.height),
        isActive: isActive,
        onPressed: () => onSelect(tab),
      );
      final label = MenuText(
        tab.label,
        fontSize: 11,
        color: Config.menuPink,
        letterSpacingEm: .12,
        anchor: Anchor.center,
        position: Vector2(35, 14.5),
      );
      final dot = _TabDot()..position = Vector2(68, 2);
      buttons[tab] = button;
      labels[tab] = label;
      _dots[tab] = dot;
      button.addAll([label, dot]);
      add(button);
    }
  }

  void sync(GameStorage storage) {
    if (buttons.isEmpty) return;
    for (final tab in LevelsTab.values) {
      final open = tab == selected;
      buttons[tab]!.color = open ? Config.menuPink : Config.menuSoft;
      labels[tab]!.color = open ? const Color(0xFFFFFFFF) : Config.menuPink;
      _dots[tab]!.shown =
          !open &&
          switch (tab) {
            LevelsTab.worlds => storage.worldsReached > storage.worldsSeen,
            LevelsTab.guide =>
              storage.metElements.length > storage.guideSeenCount,
            _ => false,
          };
    }
  }
}

/// Static notification dot, not a reward or sticker.
class _TabDot extends PositionComponent {
  _TabDot() : super(priority: 2);
  bool shown = false;
  final Paint _gold = Paint()..color = Config.menuGold;
  final Paint _outline = Paint()..color = const Color(0xFFF1F1F1);

  @override
  void render(Canvas canvas) {
    if (!shown) return;
    canvas.drawCircle(Offset.zero, 7, _outline);
    canvas.drawCircle(Offset.zero, 5, _gold);
  }
}

/// Keeps a tab mounted (and its scroll position intact) without drawing it.
class LevelsTabVisibility extends Decorator {
  LevelsTabVisibility(this.visible);
  final bool Function() visible;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    if (visible()) draw(canvas);
  }
}
