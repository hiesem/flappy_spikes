// A copy of flame's FixedResolutionViewport (same package-internal members:
// the viewport transform and the viewfinder's visibleRect cache).
// ignore_for_file: invalid_use_of_internal_member
import 'dart:math';

import 'package:flame/camera.dart';
import 'package:flame/extensions.dart';
// ReadOnlyScaleProvider lives in flame's effects internals (the same import
// FixedResolutionViewport uses).
// ignore: implementation_imports
import 'package:flame/src/effects/provider_interfaces.dart';

/// PRD-2.2 §7.5.2: Flame's `FixedResolutionViewport` with a resolution that
/// can change at run time ([setResolution]). The game shows a fixed 320 pt
/// wide window; its height is the visible playfield, which shrinks by the
/// banner strip during a run and grows back on the Home arrival.
///
/// Same behaviour as `FixedResolutionViewport` otherwise: it takes as much
/// of the canvas as the aspect allows, centred, and scales uniformly.
class PlayfieldViewport extends Viewport implements ReadOnlyScaleProvider {
  PlayfieldViewport({required Vector2 resolution, super.children})
    : _resolution = resolution.clone();

  final Vector2 _resolution;

  /// The world window this viewport shows (points).
  Vector2 get resolution => _resolution;

  double get _aspectRatio => _resolution.x / _resolution.y;

  Rect _clipRect = Rect.zero;
  final Vector2 _scaleVector = Vector2.zero();

  /// Changes the shown window (e.g. 320 × 711 → 320 × 663) and re-fits it to
  /// the current canvas at once.
  void setResolution(double width, double height) {
    if (_resolution.x == width && _resolution.y == height) return;
    _resolution.setValues(width, height);
    final game = findGame();
    if (game != null && isLoaded) _handleResize(game.canvasSize);
  }

  @override
  Vector2 get virtualSize => _resolution;

  @override
  Vector2 get scale => transform.scale;

  @override
  void onLoad() {
    _handleResize(findGame()!.canvasSize);
  }

  @override
  void onGameResize(Vector2 size) {
    if (isLoaded) super.onGameResize(size);
    _handleResize(size);
  }

  void _handleResize(Vector2 canvasSize) {
    final availableWidth = canvasSize.x;
    final availableHeight = canvasSize.y;
    size = (availableHeight * _aspectRatio > availableWidth)
        ? Vector2(availableWidth, availableWidth / _aspectRatio)
        : Vector2(availableHeight * _aspectRatio, availableHeight);
    position.x = (availableWidth - size.x) / 2 + anchor.x * size.x;
    position.y = (availableHeight - size.y) / 2 + anchor.y * size.y;
    _clipRect = Rect.fromLTRB(0, 0, size.x, size.y);
  }

  @override
  void clip(Canvas canvas) => canvas.clipRect(_clipRect, doAntiAlias: false);

  @override
  bool containsLocalPoint(Vector2 point) {
    final x = point.x;
    final y = point.y;
    return x >= 0 && y >= 0 && x <= virtualSize.x && y <= virtualSize.y;
  }

  @override
  void onViewportResize() {
    final desiredWidth = size.y * _aspectRatio;
    if (desiredWidth > size.x) {
      size.y = size.x / _aspectRatio;
    } else {
      size.x = desiredWidth;
    }
    _clipRect = Rect.fromLTRB(-size.x / 2, -size.y / 2, size.x / 2, size.y / 2);
    final scaleX = size.x / _resolution.x;
    final scaleY = size.y / _resolution.y;
    _scaleVector.setAll(min(scaleX, scaleY));
    transform.scale = _scaleVector;
    camera.viewfinder.visibleRect = null;
  }

  @override
  Vector2 globalToLocal(Vector2 point, {Vector2? output}) {
    final viewportPoint = super.globalToLocal(point, output: output);
    return transform.globalToLocal(viewportPoint, output: output);
  }

  @override
  Vector2 localToGlobal(Vector2 point, {Vector2? output}) {
    final viewportPoint = transform.localToGlobal(point, output: output);
    return super.localToGlobal(viewportPoint, output: output);
  }

  @override
  void transformCanvas(Canvas canvas) {
    canvas.translate(size.x / 2, size.y / 2);
    super.transformCanvas(canvas);
    canvas.translate(-(size.x / 2) / scale.x, -(size.y / 2) / scale.y);
  }
}
