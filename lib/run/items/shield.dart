import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/sound.dart';
import '../config/lives_config.dart';
import '../config/parts_config.dart';
import '../effects/dashed_path.dart';
import '../effects/easing.dart';
import '../effects/save_burst.dart';
import '../elements.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_layers.dart';

/// The Shield powerup, run side (PRD-2 §3.7, §3.9, §5.5).
///
/// - Armed by the field pickup (`pu_shield_get`, `shield_collected`), the
///   home slot (`RunController.start` arms it before the first hoop) or a
///   pair's SHIELD gift (WP-3d sets `state.shield`). [ShieldCircle] shows
///   whenever `state.shield` is on.
/// - As the mistake interceptor of order 10 (call: it absorbs before the
///   extra life, matching the prototype) it absorbs exactly one mistake, no
///   timer: `pu_shield_hit`, the circle flashes white and shatters into 12
///   gold / pink shards, 2 s invulnerability (the bird flash is
///   `InvulnerabilityFeature`), `shield_used` (cause).
class ShieldFeature extends RunFeature implements MistakeInterceptor {
  RunContext? _c;
  ShieldCircle? _circle;

  @override
  int get order => 10;

  @override
  String get id => 'shield';

  ShieldCircle? get circle => _circle;

  @override
  void attach(RunContext c) {
    _c = c;
    c.run.pipeline.add(this);
    c.events.on<PickupCollected>(_onPickup);
    final circle = ShieldCircle(c);
    _circle = circle;
    c.game.world.add(circle);
    // Home slot: active from the start of the run.
    if (c.s.shield) circle.form();
  }

  void _onPickup(PickupCollected e) {
    if (e.element != ElementId.shield) return;
    final c = _c;
    if (c == null) return;
    c.sfx(Sfx.puShieldGet);
    c.track('shield_collected');
    if (c.s.shield) return; // already armed: one hit only, no stacking
    c.s.shield = true;
    _circle?.form(delay: LivesConfig.formDelay);
  }

  @override
  bool tryAbsorb(Mistake m, RunContext ctx) {
    final s = ctx.s;
    if (!s.shield) return false;
    s
      ..shield = false
      ..invulnerable = LivesConfig.invulnerable;
    ctx.sfx(Sfx.puShieldHit);
    _circle?.shatter();
    ctx.track('shield_used', {'cause': m.cause.analyticsName});
    return true;
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.run.pipeline.remove(this);
      c.events.off<PickupCollected>(_onPickup);
    }
    _circle?.removeFromParent();
    _circle = null;
    _c = null;
  }
}

/// §5.5 the shield circle on the bird: 84 pt (gold 3.5 pt ring, 28 % soft
/// pink fill) with a rotating dashed white inner ring (90°/s) and an idle
/// pulse ±5 %, no badge on top; it forms with a pop (0.35 s, slight
/// overshoot) and shatters on a hit. Drawn over the bird (world = screen
/// coordinates), under the hoops' front halves.
class ShieldCircle extends PositionComponent {
  ShieldCircle(this.c) : super(priority: RunLayer.bird + 1);

  final RunContext c;

  double _t = 0;
  double? _formAt;

  bool get shown => _formAt != null;

  void form({double delay = 0}) => _formAt = _t + delay;

  /// Forming progress 0..1.
  double get born {
    final f = _formAt;
    if (f == null) return 0;
    return Ease.smooth(((_t - f) / LivesConfig.popIn).clamp(0.0, 1.0));
  }

  /// The circle's scale now: born × idle pulse × the pop-in overshoot.
  double get scaleNow {
    final f = _formAt;
    if (f == null) return 0;
    final b = born;
    final idle =
        1 +
        LivesConfig.shieldPulse *
            math.sin(
              math.max(0, _t - f - LivesConfig.popIn) *
                  LivesConfig.shieldPulseOmega,
            );
    final over = b < 1 ? 1 + LivesConfig.shieldOvershoot * (1 - b) : 1.0;
    return b * idle * over;
  }

  Offset? get centre {
    final bird = c.game.runBird;
    if (bird == null || !bird.isLoaded) return null;
    final p = bird.body.position;
    return Offset(p.x, p.y);
  }

  /// §5.5 white flash + 12 gold / pink triangle shards; hides.
  void shatter() {
    final at = centre;
    _formAt = null;
    if (at == null) return;
    final s = c.s;
    SaveBurst.emit(
      c.run.particles,
      Offset(at.dx + s.camX, at.dy + s.camY),
      c.cosmetic,
      hearts: false,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (c.s.shield && _formAt == null) form();
    if (!c.s.shield && _formAt != null) _formAt = null;
  }

  static final Paint _fill = Paint();
  static final Paint _ring = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    final k = scaleNow;
    if (k <= 0) return;
    final at = centre;
    if (at == null) return;
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..scale(k);
    _fill.color = PartsConfig.softPink.withValues(
      alpha: LivesConfig.shieldFillAlpha,
    );
    canvas.drawCircle(Offset.zero, LivesConfig.shieldRadius, _fill);
    _ring
      ..strokeWidth = LivesConfig.shieldStroke
      ..color = PartsConfig.gold;
    canvas
      ..drawCircle(Offset.zero, LivesConfig.shieldRadius, _ring)
      ..rotate(_t * LivesConfig.shieldSpin * math.pi / 180);
    DashedPathPainter.stroke(
      canvas,
      Path()..addOval(
        Rect.fromCircle(
          center: Offset.zero,
          radius: LivesConfig.shieldInnerRadius,
        ),
      ),
      color: const Color(
        0xFFFFFFFF,
      ).withValues(alpha: LivesConfig.shieldInnerAlpha),
      width: LivesConfig.shieldInnerStroke,
      dashes: LivesConfig.shieldInnerDash,
    );
    canvas.restore();
  }
}
