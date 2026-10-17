import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/flappy_game.dart';
import '../../game/sound.dart';
import '../config/lives_config.dart';
import '../effects/bird_attachment.dart';
import '../effects/easing.dart';
import '../effects/fetch_flight.dart';
import '../effects/life_icons.dart';
import '../effects/save_burst.dart';
import '../elements.dart';
import '../mistakes.dart';
import '../run_context.dart';
import '../run_events.dart';
import '../run_feature.dart';
import '../run_layers.dart';
import '../run_scaled_world.dart';

/// Hearts and the extra life (PRD-2 §3.3, §3.9, §5.2, §5.5).
///
/// - A collected heart counts 1/3 → 2/3 (`pu_heart_1`, `heart_collected`)
///   and flies to the HUD heart indicator (the shared [FetchFlight],
///   `FetchSpec.heart`); the 3rd heart turns into the extra life
///   (`pu_heart_2`; `hearts` back to 0, `extraLife` on) and the heart badge
///   pops in over the bird ([HeartBadge]). Hearts collected while the extra
///   life is active do nothing extra (no stacking).
/// - As the mistake interceptor of order 20 (after the shield, 10) it
///   forgives the next mistake: `pu_heart_use`, the badge pops into small
///   hearts, the indicator resets (hearts 0), 2 s invulnerability (the
///   bird flash is `InvulnerabilityFeature`), `extra_life_used` (cause).
class ExtraLifeFeature extends RunFeature implements MistakeInterceptor {
  RunContext? _c;
  HeartBadge? _badge;

  @override
  int get order => 20;

  @override
  String get id => 'extra_life';

  /// The badge over the bird (null before attach / after detach).
  HeartBadge? get badge => _badge;

  @override
  void attach(RunContext c) {
    _c = c;
    c.run.pipeline.add(this);
    c.events.on<PickupCollected>(_onPickup);
    final badge = HeartBadge(c);
    _badge = badge;
    c.game.world.addRun(badge);
  }

  void _onPickup(PickupCollected e) {
    if (e.element != ElementId.heart) return;
    final c = _c;
    if (c == null) return;
    final s = c.s;
    final p = e.pickup;
    if (p != null) {
      _fetch(c, Offset(p.position.x - s.camX, p.position.y - s.camY));
    }
    if (s.extraLife) {
      // §3.3 no stacking: a heart while the extra life is active does
      // nothing extra.
      c.track('heart_collected', {'hearts': LivesConfig.heartsPerLife});
      return;
    }
    s.hearts++;
    if (s.hearts >= LivesConfig.heartsPerLife) {
      s.hearts = 0;
      s.extraLife = true;
      c.sfx(Sfx.puHeart2);
      _badge?.form(delay: LivesConfig.formDelay);
      c.track('heart_collected', {'hearts': LivesConfig.heartsPerLife});
    } else {
      c.sfx(Sfx.puHeart1);
      c.track('heart_collected', {'hearts': s.hearts});
    }
  }

  /// §5.2 the touched heart flies straight into the HUD indicator.
  void _fetch(RunContext c, Offset from) {
    c.game.world.addRun(
      FetchFlight(
        from: from,
        to: LivesConfig.indicatorCentre,
        spec: FetchSpec.heart,
        priority: RunLayer.fx + 1,
        art: (canvas, scale, rotation) => LifeIcons.paintHeart(
          canvas,
          Offset.zero,
          LivesConfig.heartPickupSize * scale,
          outline: LivesConfig.heartOutline,
        ),
      ),
    );
  }

  @override
  bool tryAbsorb(Mistake m, RunContext ctx) {
    final s = ctx.s;
    if (!s.extraLife) return false;
    s
      ..extraLife = false
      ..hearts = 0
      ..invulnerable = LivesConfig.invulnerable;
    ctx.sfx(Sfx.puHeartUse);
    _badge?.pop();
    ctx.track('extra_life_used', {'cause': m.cause.analyticsName});
    return true;
  }

  @override
  void detach() {
    final c = _c;
    if (c != null) {
      c.run.pipeline.remove(this);
      c.events.off<PickupCollected>(_onPickup);
    }
    _badge?.removeFromParent();
    _badge = null;
    _c = null;
  }
}

/// §5.5 the extra-life heart badge: a 34 pt `#FF3B5C` heart with a white
/// outline and a highlight, ≈ 40 pt above the bird, bobbing ±4 pt
/// (≈ 0.6 Hz) and breathing ±8 %; it pops in (0.35 s, smoothstep) after
/// the 3rd heart and, on a save, pops into 12 small hearts (+ a white
/// flash, [SaveBurst]) in the run's particle pool. World coordinates = screen.
class HeartBadge extends PositionComponent with BirdAttachment {
  HeartBadge(this.c) : super(priority: RunLayer.bird + 1);

  final RunContext c;

  @override
  FlappySpikesGame get birdGame => c.game;

  double _t = 0;

  /// Time the badge started forming (null: hidden).
  double? _formAt;

  /// The badge is shown (forming or formed).
  bool get shown => _formAt != null;

  /// Forming progress 0..1 (0 when hidden or still waiting).
  double get born {
    final f = _formAt;
    if (f == null) return 0;
    return Ease.smooth(((_t - f) / LivesConfig.popIn).clamp(0.0, 1.0));
  }

  void form({double delay = 0}) => _formAt = _t + delay;

  /// The badge's centre on screen now (null without a bird).
  Offset? get centre {
    final bird = c.game.runBird;
    if (bird == null || !bird.isLoaded) return null;
    final p = bird.body.position;
    final bob = LivesConfig.badgeBob * math.sin(_t * LivesConfig.badgeBobOmega);
    return Offset(p.x, p.y - LivesConfig.badgeLift + bob);
  }

  /// §5.5 pops into small hearts (+ white flash) and hides.
  void pop() {
    final at = centre;
    _formAt = null;
    if (at == null) return;
    final s = c.s;
    final pool = c.run.particles;
    final r = c.cosmetic;
    // The pool lives in the fx track (track coordinates).
    final bx = at.dx + s.camX, by = at.dy + s.camY + LivesConfig.badgeLift;
    SaveBurst.emit(pool, Offset(bx, by), r, hearts: true);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // WP-2d: HUD-like, so it ignores the Hourglass time scale (the world
    // updates with dt × timeScale; this undoes it).
    final ts = c.s.timeScale;
    _t += ts > 0 ? dt / ts : dt;
    // Any source of an extra life shows the badge (and a lost one hides it).
    if (c.s.extraLife && _formAt == null) form();
    if (!c.s.extraLife && _formAt != null) _formAt = null;
  }

  @override
  void render(Canvas canvas) {
    final b = born;
    if (b <= 0) return;
    final at = centre;
    if (at == null) return;
    final pulse =
        1 + LivesConfig.badgePulse * math.sin(_t * LivesConfig.badgePulseOmega);
    LifeIcons.paintHeart(
      canvas,
      at,
      LivesConfig.badgeSize * b * pulse,
      outline: LivesConfig.heartOutline,
      shine: true,
      opacity: b,
    );
  }
}
