import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart' show Curves;

import '../home/menu_primitives.dart' show kMenuFilterQuality;

/// The standard "coins added" feedback (PRD-menu-v2 §8.3 / Q-S9): [count]
/// coins fly from a button into the coin pill, [duration] s each,
/// [stagger] s apart after [delay] — a port of the GET reward in
/// `design/menu_v2/build55.py`. Each coin pops out of [from] (fading in at
/// 60 %), arcs 30 pt up with a random sideways drift (110 %) and lands on
/// [to] (80 %), the whole path eased in.
///
/// [onLand] fires for every coin as it lands, [onDone] once after the last
/// one; then the component removes itself. Removed early (scene change),
/// it still calls [onDone] so the pill never stays frozen.
class CoinFly extends Component {
  CoinFly({
    required this.coin,
    required Rect from,
    required this.to,
    this.count = 6,
    this.duration = 0.65,
    this.stagger = 0.07,
    this.delay = 0.25,
    this.coinSize = 18,
    this.onLand,
    this.onDone,
    math.Random? random,
    super.priority = 1000,
  }) {
    final rnd = random ?? math.Random();
    for (var i = 0; i < count; i++) {
      // Mock: x0 = button left + 40 + rand * 30 (of the 112 pt GET), y0 =
      // top + 6; mid point drifts ±20 pt and rises 30 pt.
      final x0 =
          from.left +
          from.width * (40 / 112) +
          rnd.nextDouble() * from.width * (30 / 112);
      final y0 = from.top + 6;
      _starts.add(Offset(x0, y0));
      _mids.add(Offset(x0 + (rnd.nextDouble() - .5) * 40, y0 - 30));
    }
  }

  final Sprite coin;
  final int count;
  final double duration;
  final double stagger;
  final double delay;
  final double coinSize;
  final void Function(int index)? onLand;
  final void Function()? onDone;

  /// Landing spot: top-left of a coin box over the pill coin.
  final Offset to;
  final List<Offset> _starts = [];
  final List<Offset> _mids = [];
  final Paint _paint = Paint()..filterQuality = kMenuFilterQuality;

  double _t = 0;
  int _landed = 0;
  bool _done = false;

  /// Coins that have landed so far (tests).
  int get landed => _landed;
  bool get done => _done;

  /// Total time until the last coin lands.
  double get totalDuration => delay + (count - 1) * stagger + duration;

  /// Progress 0..1 of coin [i] at clock [t] (null = not launched yet).
  double? progressOf(int i, double t) {
    final local = t - delay - i * stagger;
    if (local < 0) return null;
    return (local / duration).clamp(0.0, 1.0);
  }

  /// Where coin [i] is (top-left of its box), its scale and opacity at
  /// path progress [p] (linear keyframes, eased-in overall timing).
  ({Offset position, double scale, double opacity}) poseOf(int i, double p) {
    final e = Curves.easeIn.transform(p);
    if (e < .3) {
      final k = e / .3;
      return (
        position: Offset.lerp(_starts[i], _mids[i], k)!,
        scale: .6 + (1.1 - .6) * k,
        opacity: k,
      );
    }
    final k = (e - .3) / .7;
    return (
      position: Offset.lerp(_mids[i], to, k)!,
      scale: 1.1 + (.8 - 1.1) * k,
      opacity: 1,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_done) return;
    _t += dt;
    while (_landed < count && (progressOf(_landed, _t) ?? 0) >= 1) {
      onLand?.call(_landed);
      _landed++;
    }
    if (_landed >= count) _finish();
  }

  void _finish({bool remove = true}) {
    if (_done) return;
    _done = true;
    onDone?.call();
    if (remove) removeFromParent();
  }

  @override
  void onRemove() {
    _finish(remove: false);
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final half = coinSize / 2;
    for (var i = _landed; i < count; i++) {
      final p = progressOf(i, _t);
      if (p == null || p >= 1) continue;
      final pose = poseOf(i, p);
      if (pose.opacity <= 0) continue;
      _paint.color = Color.fromRGBO(0, 0, 0, pose.opacity);
      canvas.save();
      canvas.translate(pose.position.dx + half, pose.position.dy + half);
      canvas.scale(pose.scale);
      coin.render(
        canvas,
        position: Vector2(-half, -half),
        size: Vector2.all(coinSize),
        overridePaint: _paint,
      );
      canvas.restore();
    }
  }
}
