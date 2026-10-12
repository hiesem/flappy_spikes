import 'dart:ui';

import 'package:flame/components.dart';

/// §3.0.3 / §3.12 the portal clear's fade (S6-47): a hoop half or pickup a
/// ride clears ahead of the bird fades to transparent over
/// `RunSpawner.clearAhead`'s 0.2 s before it is removed. The whole
/// component tree (its own drawing and its children) goes through one
/// translucent layer while [clearAlpha] < 1.
mixin ClearFade on Component {
  /// 1 = opaque (not clearing), 0 = gone.
  double clearAlpha = 1;

  bool _layered = false;
  final Paint _fadePaint = Paint();

  /// PRD-2.2 §15.1 the pop-in scale of a feature follow-up created inside
  /// the screen (0 → 1.15 → 1), about the component's position.
  double popScale = 1;

  @override
  void renderTree(Canvas canvas) {
    if (popScale != 1) {
      if (popScale <= 0) return;
      final Object self = this;
      final pivot = self is PositionComponent
          ? Offset(self.position.x, self.position.y)
          : Offset.zero;
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.scale(popScale);
      canvas.translate(-pivot.dx, -pivot.dy);
      try {
        _renderFaded(canvas);
      } finally {
        canvas.restore();
      }
      return;
    }
    _renderFaded(canvas);
  }

  void _renderFaded(Canvas canvas) {
    if (clearAlpha >= 1) {
      super.renderTree(canvas);
      return;
    }
    if (clearAlpha <= 0) return;
    _fadePaint.color = Color.fromRGBO(0, 0, 0, clearAlpha);
    canvas.saveLayer(null, _fadePaint);
    _layered = true;
    try {
      super.renderTree(canvas);
    } finally {
      _layered = false;
      canvas.restore();
    }
  }

  /// Runs [paint] faded when `render` is called outside [renderTree]
  /// (direct paints in tests / shots); inside [renderTree] the layer is
  /// already applied.
  void paintFaded(Canvas canvas, void Function(Canvas) paint) {
    if (clearAlpha >= 1 || _layered) {
      paint(canvas);
      return;
    }
    if (clearAlpha <= 0) return;
    _fadePaint.color = Color.fromRGBO(0, 0, 0, clearAlpha);
    canvas.saveLayer(null, _fadePaint);
    paint(canvas);
    canvas.restore();
  }
}
