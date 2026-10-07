import 'package:flame/events.dart';
import 'package:flutter/gestures.dart';

import '../game/config.dart';

/// The game's drag dispatcher: Flame's [MultiDragDispatcher] with its own
/// drag slop. The game registers it (under [MultiDragDispatcherKey]) before
/// any [DragCallbacks] component mounts, so Flame uses it instead of creating
/// its default one.
///
/// While at least one menu scroll list is mounted ([scrollAreas] > 0) a press
/// that travels more than [Config.menuScrollSlop] world points becomes a drag:
/// the drag recognizer wins the gesture arena at that distance, the tap
/// recognizer is rejected and every pressed tile / button gets a tap cancel
/// instead of a tap up (QA S1-50). Otherwise Flutter's default slop applies.
class MenuDragDispatcher extends MultiDragDispatcher {
  MenuDragDispatcher({required this.pointsToPixels});

  /// Logical pixels per world point right now (the camera scale).
  final double Function() pointsToPixels;

  /// Mounted menu scroll lists (they register themselves).
  int scrollAreas = 0;

  /// The current drag slop in logical pixels (null = Flutter's default).
  double? get touchSlop => scrollAreas > 0
      ? Config.menuScrollSlop * pointsToPixels()
      : null;

  @override
  void onMount() {
    // Replaces (does not extend) the base registration, which would install
    // a recognizer with the default slop.
    game.gestureDetectors.add<ImmediateMultiDragGestureRecognizer>(
      ImmediateMultiDragGestureRecognizer.new,
      (ImmediateMultiDragGestureRecognizer instance) {
        instance
          ..gestureSettings = _DynamicSlop(() => touchSlop)
          ..onStart = (Offset point) => _DragAdapter(this, point);
      },
    );
  }
}

/// Gesture settings whose touch slop is read when a pointer moves (the
/// camera scale and the mounted lists can change after the recognizer was
/// created).
class _DynamicSlop extends DeviceGestureSettings {
  const _DynamicSlop(this._slop) : super();

  final double? Function() _slop;

  @override
  double? get touchSlop => _slop();
}

/// Adapts a recognizer [Drag] to the dispatcher (same as Flame's internal
/// adapter).
class _DragAdapter implements Drag {
  _DragAdapter(this._listener, Offset startPoint) {
    _id = _nextId++;
    _listener.handleDragStart(
      _id,
      DragStartDetails(
        sourceTimeStamp: Duration.zero,
        globalPosition: startPoint,
        localPosition: _listener.renderBox.globalToLocal(startPoint),
      ),
    );
  }

  final MultiDragListener _listener;
  late final int _id;

  // Far from Flame's own counter so ids never collide with another adapter.
  static int _nextId = 1 << 30;

  @override
  void update(DragUpdateDetails details) =>
      _listener.handleDragUpdate(_id, details);

  @override
  void end(DragEndDetails details) => _listener.handleDragEnd(_id, details);

  @override
  void cancel() => _listener.handleDragCancel(_id);
}
