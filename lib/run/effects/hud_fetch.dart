import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import 'coin_icon.dart';

/// The collectables' "fly into the HUD" effect (PRD-2 §5.27 "caught coins
/// fly into the HUD piggy", §5.28 "each glows into the jar under the score").
/// The mock's `parts` ease: `x += (tx − x) · min(1, dt · 7)` for [life] s,
/// fading out as `1 − u²`; then gone. Positions are in the parent's
/// coordinates (add to `game.world`, which shares the HUD's screen space).
///
/// Subclass and override [paintAt] (or pass [paint]) for the item.
class HudFetch extends PositionComponent {
  HudFetch({
    required this.from,
    required this.to,
    this.life = .45,
    this.paint,
    super.priority,
  }) : _p = from;

  final Offset from, to;
  final double life;

  /// Draws the item centred at the origin with [alpha] (0..1) and [k] the
  /// life fraction (0..1). Overridden by subclasses.
  final void Function(Canvas canvas, double alpha, double k)? paint;

  Offset _p;
  double _t = 0;

  /// The ease constant (mock `min(1, dt · 7)`).
  static const double rate = 7;

  double get time => _t;

  @override
  void update(double dt) {
    super.update(dt);
    final k = math.min(1.0, dt * rate);
    _p = Offset(_p.dx + (to.dx - _p.dx) * k, _p.dy + (to.dy - _p.dy) * k);
    _t += dt;
    if (_t >= life) removeFromParent();
  }

  void paintAt(Canvas canvas, double alpha, double k) =>
      paint?.call(canvas, alpha, k);

  @override
  void render(Canvas canvas) {
    final k = (life <= 0 ? 1.0 : (_t / life)).clamp(0.0, 1.0);
    final a = 1 - k * k;
    if (a <= 0) return;
    canvas.save();
    canvas.translate(_p.dx, _p.dy);
    paintAt(canvas, a, k);
    canvas.restore();
  }
}

/// A caught coin flying into the HUD piggy (PRD-2 §5.27): the master #14
/// coin sprite, spinning, loaded in [onLoad] (CoinPopup's pattern).
class CoinFetch extends HudFetch with HasGameReference<FlappySpikesGame> {
  /// §5.27 the caught coin's flight into the HUD piggy (mock `m:.35`).
  CoinFetch({required super.from, required super.to, super.priority})
    : super(life: coinLife);

  /// §5.27 The flight time (s; mock `m:.35`).
  static const double coinLife = .35;

  /// The coin's drawn size (mock `s:6`).
  static const double coinSize = 8;

  Image? _image;

  @override
  Future<void> onLoad() async {
    _image = await CoinIcon.load(game.images);
  }

  @override
  void paintAt(Canvas canvas, double alpha, double k) {
    final image = _image;
    if (image == null) return;
    canvas.scale(math.cos(k * 12).abs().clamp(.15, 1.0), 1);
    CoinIcon.paint(canvas, image, Offset.zero, coinSize, opacity: alpha);
  }
}

/// A caught firefly glowing into the jar under the score (PRD-2 §5.28):
/// a lime halo with a pale core (mock `kind:'glow'`).
class GlowFetch extends HudFetch {
  /// §5.28 the caught firefly's glow into the jar (mock `m:.45`).
  GlowFetch({required super.from, required super.to, super.priority})
    : super(life: glowLife);

  /// §5.28 The flight time (s; mock `m:.45`).
  static const double glowLife = .45;

  /// §5.28 The glow radius (mock `s:3` → halo `s*3` = 9).
  static const double radius = 9;

  @override
  void paintAt(Canvas canvas, double alpha, double k) {
    // Local import-free halo so this file stays dependency-light.
    canvas.drawRect(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      Paint()
        ..shader = Gradient.radial(Offset.zero, radius, [
          const Color(0xFFD6FF50).withValues(alpha: .8 * alpha),
          const Color(0xFFD6FF50).withValues(alpha: 0),
        ]),
    );
    final p = Paint()
      ..color = const Color(0xFFFFFDE0).withValues(alpha: alpha);
    canvas.drawCircle(Offset.zero, radius * .6 * (1 - k * .5), p);
  }
}
