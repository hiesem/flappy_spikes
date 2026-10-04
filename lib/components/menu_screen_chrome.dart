import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';
import 'home/home_screen.dart';
import 'home/menu_primitives.dart';

/// Images of the shared menu chrome the game owns ([CoinPill],
/// [MenuCornerBox]).
const List<String> kMenuChromeImages = [
  'menu/plus.png',
  'menu/coin.png',
  'menu/gear.png',
  'menu/back.png',
];

/// Shared chrome of the full-screen menus (Shop now, Skins next; PRD-1 §5):
/// a pink back button top-left in the home gear's place and the coin pill
/// top-right (both drawn by the game's shared chrome, which survives the
/// screen crossfades: [MenuCornerBox], [CoinPill]), the
/// screen title centred at the top, and a vertically drag-scrollable
/// content area ([scroll]) between the title and the bottom spike tips. A full-screen blocker below it all
/// swallows taps the buttons miss.
///
/// Subclasses add their content in [buildContent] (into [scroll], in world
/// coordinates as measured on the mock — the area translates and clips),
/// list extra images in [contentImages] and keep themselves in sync in
/// [sync] (polled every frame, like the home screen). Text tinting goes
/// through [onTint]; [cardColor] is the mock's card fill.
abstract class MenuScreen extends PositionComponent
    with HasGameReference<FlappySpikesGame>, GroupOpacity
    implements Tintable {
  MenuScreen({required this.title, required this.onBack})
    : super(priority: 20);

  /// Uppercase title text.
  final String title;
  final void Function() onBack;

  /// False once the screen starts leaving: its buttons stop hit-testing.
  bool active = true;
  bool isActive() => active;

  /// The game's shared coin pill (drawn above this screen; it stays put
  /// across home / Shop / Skins transitions).
  CoinPill get coinPill => game.coinPill;

  /// Tap target of the back button; its pink box and chevron are the
  /// game's shared [MenuCornerBox] below this screen.
  late final MenuButton backButton;
  late final MenuText titleText;
  late final MenuScrollArea scroll;

  final Map<String, Sprite> _sprites = {};
  Color _tint = const Color(0xFF828282);

  /// Current stage foreground (text colour of the title, amounts, ...).
  Color get tint => _tint;

  /// Card fill: the stage foreground at [Config.menuCardMix] over the stage
  /// background.
  Color get cardColor =>
      Color.lerp(game.stageBackground, _tint, Config.menuCardMix)!;

  /// Images (under `assets/images/`) [buildContent] uses via [sprite].
  List<String> get contentImages => const [];

  /// A loaded sprite from [kMenuChromeImages] or [contentImages].
  Sprite sprite(String path) => _sprites[path]!;

  /// Adds the screen's content to [scroll].
  Future<void> buildContent();

  /// Re-reads the menu state; [force] on the first call.
  void sync({bool force = false}) {}

  /// The stage foreground changed (menus are always stage 0, so this is
  /// mostly the initial tint).
  void onTint(Color color) {}

  /// True once the screen was taken off the tree (a fast back / Esc can
  /// close it, and its fade-out remove it, before or while it loads).
  bool get _detached => parent == null || isRemoving || isRemoved;

  /// Whether [onLoad] ran to the end and built the screen (false for a
  /// screen closed before it could load).
  bool get built => _built;
  bool _built = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // A screen removed before its load started or finished just stays
    // empty: there is no game to read from any more, and it is gone anyway.
    if (_detached) return;
    final game = this.game;
    final h = game.viewHeight;
    size = Vector2(Config.worldWidth, h);
    final paths = {...kMenuChromeImages, ...contentImages}.toList();
    final loaded = await Future.wait(paths.map(game.images.load));
    if (_detached) return;
    for (var i = 0; i < paths.length; i++) {
      _sprites[paths[i]] = Sprite(loaded[i]);
    }

    final backRect = Config.menuScreenBackRectFor(h);
    backButton = MenuButton(
      position: backRect.topLeft.toVector2(),
      size: backRect.size.toVector2(),
      onPressed: onBack,
      isActive: isActive,
    );
    titleText = MenuText(
      title,
      fontSize: Config.menuScreenTitleFontSize,
      color: _tint,
      letterSpacingEm: Config.menuScreenTitleLetterSpacing,
      position: Config.menuScreenTitlePositionFor(h),
      anchor: Anchor.topCenter,
    );
    final top = Config.menuScreenContentTopFor(h);
    scroll = MenuScrollArea(
      viewport: Rect.fromLTRB(
        0,
        top,
        Config.worldWidth,
        Config.menuScreenContentBottomFor(h),
      ),
      isActive: isActive,
    );
    addAll([
      _ScreenTapBlocker(size: size.clone()),
      scroll,
      backButton,
      titleText,
    ]);
    await buildContent();
    _built = true;
    if (_detached) return;
    sync(force: true);
    setTint(_tint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_built) sync();
  }

  @override
  void setTint(Color color) {
    _tint = color;
    if (_built) {
      titleText.color = color;
      onTint(color);
    }
  }
}

/// A vertically drag-scrollable, clipped content area. Children of
/// [content] are positioned in world coordinates (as on the mock at scroll
/// 0); the area shows the [viewport] band of them, shifted up by [offset].
/// Taps outside the viewport never reach the content.
class MenuScrollArea extends PositionComponent with DragCallbacks {
  MenuScrollArea({required this.viewport, this.isActive})
    : super(
        position: viewport.topLeft.toVector2(),
        size: viewport.size.toVector2(),
      ) {
    content = PositionComponent(position: Vector2(0, -viewport.top));
  }

  /// The visible band, in world coordinates.
  final Rect viewport;
  final bool Function()? isActive;

  /// Holds the scrolled children (world coordinates at offset 0).
  late final PositionComponent content;

  /// World y of the content's bottom edge (set by the screen); the area
  /// scrolls until it reaches the viewport bottom.
  double contentBottom = 0;

  double _offset = 0;
  double? _target;

  /// Current scroll offset (0 = top), in points.
  double get offset => _offset;
  set offset(double value) {
    _target = null;
    _setOffset(value);
  }

  /// Largest offset: 0 when the content fits.
  double get maxOffset =>
      contentBottom > viewport.bottom ? contentBottom - viewport.bottom : 0;

  /// Whether the content is taller than the viewport.
  bool get scrollable => maxOffset > 0;

  /// Scrolls (eased, ~0.25 s) so content y [worldY] sits at the viewport
  /// top, clamped to the scroll range.
  void scrollTo(double worldY, {bool animate = true}) {
    final target = (worldY - viewport.top).clamp(0.0, maxOffset);
    if (animate) {
      _target = target;
    } else {
      offset = target;
    }
  }

  /// Where an animated [scrollTo] is heading (null when idle).
  double? get target => _target;

  /// World y of content y [worldY] on screen right now.
  double screenY(double worldY) => worldY - _offset;

  void _setOffset(double value) {
    _offset = value.clamp(0.0, maxOffset);
    content.position.y = -viewport.top - _offset;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(content);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = _target;
    if (target == null) return;
    // Exponential ease: ~95 % of the way in 0.25 s.
    final next = _offset + (target - _offset) * (1 - math.pow(1e-7, dt));
    if ((target - next).abs() < 0.5) {
      _target = null;
      _setOffset(target);
    } else {
      _setOffset(next);
    }
  }

  @override
  void renderTree(Canvas canvas) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(position.x, position.y, width, height));
    super.renderTree(canvas);
    canvas.restore();
  }

  @override
  Iterable<Component> componentsAtLocation<T>(
    T locationContext,
    List<T>? nestedContexts,
    T? Function(CoordinateTransform, T) transformContext,
    bool Function(Component, T) checkContains,
  ) {
    // Content scrolled out of the viewport must not take taps.
    if (locationContext is Vector2 && !containsLocalPoint(locationContext)) {
      return const [];
    }
    return super.componentsAtLocation(
      locationContext,
      nestedContexts,
      transformContext,
      checkContains,
    );
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      (isActive?.call() ?? true) && super.containsLocalPoint(point);

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!scrollable) return;
    event.handled = true;
    _target = null;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!scrollable) return;
    event.handled = true;
    _setOffset(_offset - event.localDelta.y);
  }
}

/// Full-screen, bottom-most child of a [MenuScreen]: consumes taps no
/// button claimed (nothing behind a menu screen reacts to taps).
class _ScreenTapBlocker extends PositionComponent with TapCallbacks {
  _ScreenTapBlocker({super.size});

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
  }
}
