import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/rendering.dart';
import 'package:flutter/animation.dart' show Curves;

import '../../game/config.dart';
import '../skins/celebration.dart' show keyframe;

/// A card flip about the component's centre (PRD-home-v3 §7 owned flips):
/// CSS `rotateX` ([vertical]) / `rotateY` without perspective, i.e. the
/// box squashes to cos(angle) along that axis; [scale] grows it evenly.
class FlipEffect extends Decorator {
  FlipEffect(this.target, {required this.vertical});

  final PositionComponent target;

  /// True = rotateX (squashes the height), false = rotateY (the width).
  final bool vertical;

  /// cos(angle): 1 flat, 0 edge-on.
  double squash = 1;
  double scale = 1;

  bool get isIdentity => squash == 1 && scale == 1;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    if (isIdentity) {
      draw(canvas);
      return;
    }
    final px = target.size.x / 2, py = target.size.y / 2;
    canvas.save();
    canvas.translate(px, py);
    canvas.scale(
      vertical ? scale : scale * squash,
      vertical ? scale * squash : scale,
    );
    canvas.translate(-px, -py);
    draw(canvas);
    canvas.restore();
  }
}

/// Drives one flip of [effect]: 0 -> 90° in [Config.flipOutDuration]
/// (ease-in), then [onSwap] (the new face) and -90° -> 0° with a 104 %
/// overshoot at 70 % in [Config.flipInDuration] (ease-out), then [onDone]
/// and removal. Removed early, it still swaps and settles.
class FlipDriver extends Component {
  FlipDriver(this.effect, {required this.onSwap, this.onDone});

  final FlipEffect effect;
  final void Function() onSwap;
  final void Function()? onDone;

  double _t = 0;
  bool _swapped = false;
  bool _done = false;

  /// Whether the new face is up (tests).
  bool get swapped => _swapped;

  void _swap() {
    if (_swapped) return;
    _swapped = true;
    onSwap();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _swap();
    effect
      ..squash = 1
      ..scale = 1;
    onDone?.call();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    const out = Config.flipOutDuration;
    if (_t < out) {
      final a = Curves.easeIn.transform(_t / out) * math.pi / 2;
      effect.squash = math.cos(a);
      return;
    }
    _swap();
    final u = (_t - out) / Config.flipInDuration;
    if (u >= 1) {
      _finish();
      removeFromParent();
      return;
    }
    final e = Curves.easeOut.transform(u);
    final degrees = keyframe(const [(0, -90), (.7, 0), (1, 0)], e);
    effect
      ..squash = math.cos(degrees * math.pi / 180)
      ..scale = keyframe(const [(0, 1), (.7, 1.04), (1, 1)], e);
  }

  @override
  void onRemove() {
    _finish();
    super.onRemove();
  }
}

/// The video icon shrinking away (§7: opacity 1 -> 0, scale -> 30 % in
/// [Config.videoIconShrinkDuration]) as a decorator on the icon.
class ShrinkAway extends Decorator {
  ShrinkAway(this.target);

  final PositionComponent target;

  /// 0 = untouched .. 1 = gone.
  double k = 0;

  @override
  void apply(void Function(Canvas) draw, Canvas canvas) {
    if (k <= 0) {
      draw(canvas);
      return;
    }
    if (k >= 1) return;
    final px = target.size.x / 2, py = target.size.y / 2;
    final s = 1 - .7 * k;
    canvas.save();
    canvas.translate(px, py);
    canvas.scale(s);
    canvas.translate(-px, -py);
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - k));
    draw(canvas);
    canvas.restore();
    canvas.restore();
  }
}

/// Runs a [ShrinkAway] on [target] over [Config.videoIconShrinkDuration],
/// then calls [onDone] (rebuild without the icon) and removes itself.
class ShrinkDriver extends Component {
  ShrinkDriver(this.target, {required this.onDone}) {
    target.decorator.addLast(_effect = ShrinkAway(target));
  }

  final PositionComponent target;
  final void Function() onDone;
  late final ShrinkAway _effect;
  double _t = 0;
  bool _done = false;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _effect.k = (_t / Config.videoIconShrinkDuration).clamp(0.0, 1.0);
    if (_effect.k >= 1) removeFromParent();
  }

  @override
  void onRemove() {
    if (!_done) {
      _done = true;
      onDone();
    }
    super.onRemove();
  }
}
