import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerCancelEvent, PointerDownEvent, PointerEvent,
        PointerUpEvent;

import '../game/config.dart';
import '../game/flappy_game.dart';
import '../game/tintable.dart';
import 'home/home_screen.dart';
import 'home/menu_primitives.dart';
import 'menu_drag_dispatcher.dart';

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

  /// Whether the screen shows its [title] (the skin shop has none).
  bool get showsTitle => true;

  /// The [scroll] viewport in world coordinates (default: from below the
  /// title to the bottom spike tips, full width).
  Rect scrollViewportFor(double viewHeight) => Rect.fromLTRB(
    0,
    Config.menuScreenContentTopFor(viewHeight),
    Config.worldWidth,
    Config.menuScreenContentBottomFor(viewHeight),
  );

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
    scroll = MenuScrollArea(viewport: scrollViewportFor(h), isActive: isActive);
    addAll([
      _ScreenTapBlocker(size: size.clone()),
      scroll,
      backButton,
      if (showsTitle) titleText,
      // Over the list while it moves on its own, so the touch that stops a
      // fling or a spring presses nothing in it (decision 1, 2026-10-07).
      // Controls outside the list stop it AND act (QA S1-51 decision).
      MenuScrollTapGate(
        scroll: scroll,
        position: scroll.viewport.topLeft.toVector2(),
        size: scroll.viewport.size.toVector2(),
        priority: 1 << 20,
      ),
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

/// A vertically drag-scrollable, clipped content area with momentum
/// (product decision 2026-10-07): a release flings the content with an
/// exponential decay, dragging past an edge follows at a rubber-banded rate,
/// and a fling or a release that ended past an edge springs back, critically
/// damped (~0.35 s). Children of [content] are positioned in world
/// coordinates (as on the mock at scroll 0); the area shows the [viewport]
/// band of them, shifted up by [offset].
///
/// Taps outside the viewport never reach the content, and neither do the taps
/// that stop a fling or a spring: [MenuScreen] puts a [MenuScrollTapGate] over
/// the viewport while [isBusy]. A press that travels more than
/// [Config.menuScrollSlop] is a drag and cancels the pressed child
/// ([MenuDragDispatcher]).
class MenuScrollArea extends PositionComponent with DragCallbacks {
  MenuScrollArea({required this.viewport, this.isActive})
    : super(
        position: viewport.topLeft.toVector2(),
        size: viewport.size.toVector2(),
      ) {
    content = PositionComponent(
      position: Vector2(-viewport.left, -viewport.top),
    );
  }

  /// The visible band, in world coordinates.
  final Rect viewport;
  final bool Function()? isActive;

  /// Holds the scrolled children (world coordinates at offset 0).
  late final PositionComponent content;

  /// World y of the content's bottom edge (set by the screen); the area
  /// scrolls until it reaches the viewport bottom.
  double contentBottom = 0;

  /// Unclamped scroll position. In range it is the offset; past an edge the
  /// rubber band maps it onto the (smaller) displayed [offset].
  double _raw = 0;
  double _offset = 0;

  double? _target;

  /// Fling velocity in pt/s (positive = the offset grows).
  double _velocity = 0;
  _SpringBack? _spring;

  /// The pointer is dragging the content (a drag that moved past the slop).
  bool _dragging = false;

  /// A touch stopped the motion and is still down (the gate's tap-down).
  bool _touchDown = false;

  /// A stopped spring must resume when that touch lifts without dragging, so
  /// a stop-tap never leaves the content out of range.
  bool _resumeSpring = false;

  final List<_DragSample> _samples = [];

  /// Current scroll offset (0 = top), in points.
  double get offset => _offset;
  set offset(double value) {
    _cancelMotion();
    _target = null;
    _setDisplay(value.clamp(0.0, maxOffset));
  }

  /// Largest offset: 0 when the content fits.
  double get maxOffset =>
      contentBottom > viewport.bottom ? contentBottom - viewport.bottom : 0;

  /// Whether the content is taller than the viewport.
  bool get scrollable => maxOffset > 0;

  /// Whether a fling is still moving the content.
  bool get isGliding => _velocity != 0;

  /// Whether the content is springing back to an edge.
  bool get isSpringing => _spring != null;

  /// Whether the content is moving on its own (a touch stops it).
  bool get isBusy => isGliding || isSpringing;

  /// Whether the content currently sits outside the scroll range.
  bool get isOverScrolled => _raw < 0 || _raw > maxOffset;

  /// Current fling velocity, pt/s (tests).
  double get velocity => _velocity;

  /// Scrolls (eased, ~0.25 s) so content y [worldY] sits at the viewport
  /// top, clamped to the scroll range. Cancels any fling or spring back.
  void scrollTo(double worldY, {bool animate = true}) {
    _cancelMotion();
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

  /// Stops a fling or spring where it is (a pointer went down on it). When
  /// [releaseAfterStop] follows without a drag, the spring back resumes.
  void stopMotion() {
    _cancelMotion();
    _resumeSpring = isOverScrolled;
    _touchDown = true;
  }

  /// The touch that called [stopMotion] lifted without dragging.
  void releaseAfterStop() {
    _touchDown = false;
    if (!_resumeSpring) return;
    _resumeSpring = false;
    if (isOverScrolled) _startSpring(0);
  }

  void _cancelMotion() {
    _velocity = 0;
    _spring = null;
    _resumeSpring = false;
  }

  /// Moves to the unclamped position [raw] (rubber banded when out of range).
  void _setRaw(double raw) {
    _raw = raw;
    _offset = _displayFor(raw);
    _syncContent();
  }

  /// Moves to the displayed [display] (the inverse of the rubber band; used
  /// by the spring and by every programmatic move, which stays in range).
  void _setDisplay(double display) {
    _offset = display;
    _raw = _rawForDisplay(display);
    _syncContent();
  }

  void _syncContent() {
    content.position.y = -viewport.top - _offset;
  }

  double _displayFor(double raw) {
    if (raw < 0) return -_rubber(-raw);
    final max = maxOffset;
    if (raw > max) return max + _rubber(raw - max);
    return raw;
  }

  double _rawForDisplay(double display) {
    if (display < 0) return -_invertRubber(-display);
    final max = maxOffset;
    if (display > max) return max + _invertRubber(display - max);
    return display;
  }

  double get _rubberRange => Config.menuScrollRubber * viewport.height;

  /// The rubber band: [over] pt past an edge shows as this much.
  double _rubber(double over) {
    final range = _rubberRange;
    return range * over / (range + over);
  }

  double _invertRubber(double shown) {
    final range = _rubberRange;
    final t = shown.clamp(0.0, range * 0.999);
    return range * t / (range - t);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(content);
  }

  MenuDragDispatcher? _drags;

  @override
  void onMount() {
    super.onMount();
    final drags = findRootGame()?.findByKey(const MultiDragDispatcherKey());
    if (drags is MenuDragDispatcher) {
      _drags = drags;
      drags.scrollAreas++;
    }
  }

  @override
  void onRemove() {
    _drags?.scrollAreas--;
    _drags = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = _target;
    if (target != null) {
      // Exponential ease: ~95 % of the way in 0.25 s.
      final next = _offset + (target - _offset) * (1 - math.pow(1e-7, dt));
      if ((target - next).abs() < 0.5) {
        _target = null;
        _setDisplay(target);
      } else {
        _setDisplay(next);
      }
      return;
    }
    final spring = _spring;
    if (spring != null) {
      _advanceSpring(spring, dt);
      return;
    }
    if (_velocity != 0) {
      _advanceGlide(dt);
      return;
    }
    // The content may have shrunk under us (a new tab): stay in range, but
    // never while a touch holds a stopped spring where it was.
    if (isOverScrolled && !_touchDown && !_dragging) {
      _setDisplay(_offset.clamp(0.0, maxOffset));
    }
  }

  /// One fling step: exponential deceleration, handing over to the spring
  /// when the content crosses an edge. Integrated in closed form
  /// (`v(t) = v0 d^t`, `x(t) = v0 (d^t - 1) / ln d`), so the distance does not
  /// depend on the frame rate (QA S2-50).
  void _advanceGlide(double dt) {
    final v0 = _velocity;
    const decay = Config.menuScrollFlingDecay;
    final keep = math.pow(decay, dt).toDouble();
    _setRaw(_raw + v0 * (keep - 1) / math.log(decay));
    final v = v0 * keep;
    if (isOverScrolled) {
      // Reached an edge: bounce (the spring starts with the remaining speed).
      _velocity = 0;
      _startSpring(v);
      return;
    }
    _velocity = v.abs() < Config.menuScrollRestVelocity ? 0 : v;
  }

  /// Springs the content back to the edge it crossed, from [velocity].
  void _startSpring(double velocity) {
    final edge = _raw < 0 ? 0.0 : maxOffset;
    final x = _offset - edge;
    if (x.abs() < 1e-9 && velocity.abs() < 1e-9) return;
    _spring = _SpringBack(edge: edge, x: x, v: velocity);
  }

  void _advanceSpring(_SpringBack spring, double dt) {
    final w = Config.menuScrollSpringOmega;
    spring.t += dt;
    final t = spring.t;
    final decay = math.exp(-w * t);
    final b = spring.v + w * spring.x;
    final x = (spring.x + b * t) * decay;
    final v = (spring.v - w * b * t) * decay;
    final settled =
        x.abs() < Config.menuScrollSpringRestDistance &&
        v.abs() < Config.menuScrollSpringRestVelocity;
    if (settled || t > Config.menuScrollSpringMaxDuration) {
      _spring = null;
      _setDisplay(spring.edge);
      return;
    }
    _setDisplay(spring.edge + x);
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
    _cancelMotion();
    _dragging = true;
    _touchDown = false;
    _samples.clear();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_dragging) return;
    event.handled = true;
    _setRaw(_raw - event.localDelta.y);
    _recordSample(event.timestamp, _offset);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_dragging) return;
    _dragging = false;
    final velocity = _releaseVelocity(event);
    _samples.clear();
    if (isOverScrolled) {
      _startSpring(velocity);
    } else if (velocity.abs() >= Config.menuScrollMinFlingVelocity) {
      _velocity = velocity;
    }
  }

  /// Offset velocity (pt/s, positive = the offset grows) when the finger
  /// lifts: the average over the last [Config.menuScrollVelocityWindow] of
  /// drag samples. Flutter's own estimate knows the release time, so it rules
  /// out a finger that had already stopped (stale samples).
  double _releaseVelocity(DragEndEvent event) {
    final estimate = _sampleVelocity();
    if (estimate == 0) return -event.velocity.y;
    return event.velocity.length < 1 ? 0 : estimate;
  }

  double _sampleVelocity() {
    if (_samples.length < 2) return 0;
    final last = _samples.last;
    var first = _samples.first;
    for (final sample in _samples) {
      if (last.time - sample.time <= Config.menuScrollVelocityWindow) {
        first = sample;
        break;
      }
    }
    final dt = last.time - first.time;
    if (dt <= 0) return 0;
    return ((last.offset - first.offset) / dt).clamp(
      -Config.menuScrollMaxFlingVelocity,
      Config.menuScrollMaxFlingVelocity,
    );
  }

  void _recordSample(Duration time, double offset) {
    var at = time.inMicroseconds / 1e6;
    // A host that sends no (or non-monotonic) timestamps must not poison the
    // average: keep the samples in order.
    if (_samples.isNotEmpty && at < _samples.last.time) at = _samples.last.time;
    _samples.add(_DragSample(at, offset));
    while (_samples.length > 2 &&
        at - _samples.first.time > Config.menuScrollVelocityWindow) {
      _samples.removeAt(0);
    }
  }
}

/// One drag sample for the release-velocity average.
class _DragSample {
  const _DragSample(this.time, this.offset);

  /// Seconds (the pointer event's own monotonic clock).
  final double time;
  final double offset;
}

/// A critically damped spring pulling the displayed offset back to [edge].
class _SpringBack {
  _SpringBack({required this.edge, required this.x, required this.v});

  /// The bound being returned to.
  final double edge;

  /// Initial offset from [edge] and its velocity.
  final double x;
  final double v;

  double t = 0;
}

/// Topmost child of a [MenuScreen] covering its list's viewport: swallows the
/// touch that stops a list fling or spring back (product decision
/// 2026-10-07). The list stops under the finger and nothing in it is pressed.
/// Inert (and invisible) whenever the list is at rest.
///
/// A touch anywhere else (coin pill, back, tabs, preview BUY) while the list
/// moves stops it too, but performs its normal action — native list
/// behaviour (QA S1-51, orchestrator decision 2026-10-07). The gate sees
/// those touches through a global pointer route.
class MenuScrollTapGate extends PositionComponent with TapCallbacks {
  MenuScrollTapGate({
    required this.scroll,
    super.position,
    super.size,
    super.priority,
  });

  final MenuScrollArea scroll;

  /// Set while the gate holds this touch's tap-down record (the list is at
  /// rest by then, so [scroll.isBusy] alone would stop claiming the point).
  bool _down = false;

  bool get _blocking =>
      (scroll.isActive?.call() ?? true) && (scroll.isBusy || _down);

  @override
  bool containsLocalPoint(Vector2 point) =>
      _blocking && super.containsLocalPoint(point);

  /// Pointers outside the viewport that stopped the list and are still down.
  final Set<int> _outside = {};

  @override
  void onMount() {
    super.onMount();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void onRemove() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    if (_outside.isNotEmpty) {
      _outside.clear();
      scroll.releaseAfterStop();
    }
    super.onRemove();
  }

  /// Every pointer event of the app, after the hit-tested handlers: a press
  /// inside the viewport already went through [onTapDown] and stopped the
  /// list, so a list still moving here was pressed somewhere else.
  void _onPointer(PointerEvent event) {
    if (!isMounted) return;
    if (event is PointerDownEvent) {
      if ((scroll.isActive?.call() ?? true) && scroll.isBusy) {
        _outside.add(event.pointer);
        scroll.stopMotion();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_outside.remove(event.pointer)) scroll.releaseAfterStop();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _down = true;
    scroll.stopMotion();
  }

  @override
  void onTapUp(TapUpEvent event) {
    _down = false;
    scroll.releaseAfterStop();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _down = false;
    scroll.releaseAfterStop();
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
