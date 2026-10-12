import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import 'config.dart';

/// PRD-2.2 §33.4 item 5: an idle menu draws at [Config.idleMenuFps]
/// instead of the display rate.
///
/// Home always has slow idle motion (the bird's bob and idle flap, the
/// START pulse and light streak, the NEW tag, trophy and coin glint), so
/// "no frames while nothing animates" never applies there; the menus keep
/// that motion and simply draw fewer frames of it. The game decides when a
/// menu is idle (see `FlappySpikesGame._menuIdle`) and reports it at the
/// end of each frame through [endFrame]:
///
/// - idle: Flame's game loop (a [Ticker]) is stopped after this frame, so
///   Flutter requests no vsync, builds, paints or rasterizes nothing; a
///   timer restarts the loop one idle frame period later.
/// - not idle: nothing happens, the loop runs at the display rate.
///
/// Any touch (a global pointer route, [attach]) and [wake] restart the loop
/// at once. The first frame after a restart gets the real elapsed time as
/// its step ([frameDt]): Flame's loop restarts with dt = 0, which would
/// otherwise freeze every animation.
///
/// Off by default ([enabled] false): `main.dart` turns it on for the app;
/// tests turn it on only to test it.
class IdleFrameLimiter {
  IdleFrameLimiter(this._game);

  final Game _game;

  /// Whether idle menus are limited at all.
  bool enabled = false;

  /// Frames per second of an idle menu; 0 = never limit.
  double fps = Config.idleMenuFps;

  /// Called on every touch (before the loop wakes): the game resets its
  /// idle time.
  void Function()? onInput;

  Timer? _wake;
  bool _stopped = false;
  bool _restarted = false;
  Duration? _lastFrame;
  bool _routed = false;

  /// True while the loop is stopped by the limiter (between two idle
  /// frames).
  bool get sleeping => _stopped;

  /// Frames seen ([frameDt] calls) and idle frames drawn so far
  /// (diagnostics / tests).
  int frames = 0;
  int idleFrames = 0;

  /// Flame's game loop (null while the game is not attached).
  ({void Function() start, void Function() stop})? get _loop {
    if (!_game.isAttached) return null;
    final loop = _game.renderBox.gameLoop;
    return loop == null ? null : (start: loop.start, stop: loop.stop);
  }

  /// Listens to every pointer event of the app (a touch wakes the loop).
  void attach() {
    if (_routed) return;
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
      _routed = true;
    } catch (_) {}
  }

  /// Stops listening and cancels a pending restart.
  void detach() {
    cancel();
    if (!_routed) return;
    _routed = false;
    try {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    } catch (_) {}
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerHoverEvent) return;
    onInput?.call();
    wake();
  }

  /// The step for this frame: [dt] as Flame measured it, except on the
  /// first frame after a limiter restart, which gets the real time since
  /// the previous frame.
  double frameDt(double dt) {
    frames++;
    final now = _frameStamp();
    final last = _lastFrame;
    _lastFrame = now;
    if (!_restarted) return dt;
    _restarted = false;
    if (now == null || last == null || now <= last) return dt;
    return (now - last).inMicroseconds / 1e6;
  }

  /// The vsync time stamp of the frame being drawn (null outside a frame,
  /// e.g. a test stepping `update` by hand).
  static Duration? _frameStamp() {
    try {
      final binding = SchedulerBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.idle) return null;
      return binding.currentFrameTimeStamp;
    } catch (_) {
      return null;
    }
  }

  /// End of a frame's update: stops the loop after this frame when the
  /// menu is [idle], with a restart scheduled one idle period later.
  void endFrame({required bool idle}) {
    if (!enabled || !idle || fps <= 0 || _game.paused) return;
    final loop = _loop;
    if (loop == null) return;
    idleFrames++;
    loop.stop();
    _stopped = true;
    // Wake a little before the frame is due, so the next vsync after the
    // timer is the one a full idle period after this frame.
    final periodUs = 1e6 / fps;
    final delayUs = math.max(0.0, periodUs - Config.idleMenuWakeLead * 1e6);
    _wake?.cancel();
    _wake = Timer(Duration(microseconds: delayUs.round()), wake);
  }

  /// Restarts the loop now (touch, timer, or anything that needs the
  /// display rate). No-op unless the limiter stopped it.
  void wake() {
    _wake?.cancel();
    _wake = null;
    if (!_stopped) return;
    _stopped = false;
    // A paused engine (backgrounded) restarts with resumeEngine().
    if (_game.paused) return;
    final loop = _loop;
    if (loop == null) return;
    _restarted = true;
    loop.start();
  }

  /// Forgets a stopped loop without restarting it (the engine was paused,
  /// e.g. the app went to the background; resumeEngine restarts it).
  void cancel() {
    _wake?.cancel();
    _wake = null;
    _stopped = false;
    _restarted = false;
  }
}
